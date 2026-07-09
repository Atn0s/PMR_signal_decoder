# TETRA 当前解码工作流程

本文描述当前 MATLAB 工程中的 TETRA DMO 解码实验流程，重点说明 DSB
同步突发和 `SCH/S` 解码是如何实现的。

当前目标不是完整 MAC、语音或协议插件接入，而是把空口 IQ 信号稳定恢复到
可以交给数据链路层继续处理的 bit 块：

```text
IQ -> 72 kHz -> RRC 匹配滤波 -> 符号定时
-> pi/4-DQPSK 差分判决 -> hard bit 流
-> DMO DSB/DNB burst 识别 -> BKN1/BKN2 提取
-> DSB BKN1/SCH-S 解码 -> FN/TN 时序上下文
```

## 入口

交互脚本：

```matlab
run('examples/tetra/tetra_symbol_debug.m')
```

核心函数：

```matlab
result = tetra.symbolDebug(file, ...)
```

MATLAB 的 `+tetra`、`+common` 目录是 package 目录。例如：

```matlab
tetra.symbolDebug(...)
```

实际调用的是：

```text
+tetra/symbolDebug.m
```

同理，`common.readRawIq(...)` 调用的是 `+common/readRawIq.m`。

当前示例脚本把 active 窗口拉长到约 2.5 秒：

```matlab
'ActivePrePadSec', 0.020, ...
'ActivePostPadSec', 2.200, ...
'ActiveMaxSec', 2.500
```

这样可以同时看到一段初始同步、后续 DNB 负载、下一段初始同步，以及后面继续
出现的 DNB 负载。

## 当前长窗口样本结果

默认 DMO 样本：

```text
/home/lzkj/lzkj_workspace/python_docs/DMR_demo/data/tetra_dmo_20240413_430050000_baseband.wav
```

当前 2.5 秒窗口运行结果：

```text
active window:          5.177 s - 7.638 s
active span:            2.461 s
input sample rate:      50000 Hz
processing sample rate: 72000 Hz
coarse offset:          +320.8 Hz
residual correction:    +100.0 Hz
timing phase:           0.75 samples
timing median error:    0.0554 rad
symbols:                44298
bits:                   88594
decision variant:       standard
DMO candidates:         434
complete candidates:    430
confirmed bursts:       62
confirmed DSB:          38
confirmed DNB:          24
payload blocks:         124
SCH/S decoded:          38
timing assigned:        62
frequency correction:   38 valid DSB fields, median abs error 59.1 Hz
```

观察到的结构是：

```text
1. 先出现一组连续 DSB：FN6 TN1 到 FN9 TN4。
2. 随后出现 DNB normal_1：FN10 TN1、FN11 TN1、FN12 TN1。
3. 中间穿插 DSB：FN12 TN3。
4. 继续出现 DNB normal_2 / normal_1：FN13 TN1 到 FN17 TN1。
5. FN18 附近出现 DSB，同步上下文跨过 multiframe 边界回到 FN1。
6. 约 6.7 秒后再次出现一组连续 DSB：FN15 TN1 到 FN18 TN4。
7. 第二组同步后继续出现 DNB normal_1 / normal_2。
```

这只是该样本当前窗口中的观测结果，不是协议规定每次呼叫都必须这样排列。
真正有规范意义的是：DSB 能给出同步和 FN/TN，DNB 能承载业务或控制负载，
FN/TN 可以按 18 frame x 4 slot 的循环向前或向后推算。

## 从 IQ 到 hard bit

### 1. IQ 读取和采样率处理

`tetra.symbolDebug` 首先调用：

```matlab
iq = common.readRawIq(path, 'DType', p.Results.IqDType);
fs = common.detectSampleRate(path);
iq = iq(:);
iq = iq - mean(iq);
[iq72, up, down] = common.resampleTo(iq, fs, cfg.frontendSampleRateHz);
```

当前 TETRA 前端处理采样率固定为：

```text
72000 Hz
```

TETRA 符号率是：

```text
18000 symbol/s
```

所以每个符号对应：

```text
72000 / 18000 = 4 samples/symbol
```

这就是后续符号定时搜索里 `0` 到 `3.75` samples 相位的来源。

### 2. active window 选择

`tetra.activeWindow` 对 72 kHz IQ 做 1 ms 功率包络：

```text
window power = mean(abs(iq)^2) over 1 ms
```

然后用噪声地板和高分位功率估计门限，找出最明显的活动段。示例脚本现在会在
活动段前保留 20 ms，后面保留 2.2 s，并限制最大窗口 2.5 s。

`02_active_window` 现在包含两幅图：

```text
top:    整个输入文件的 1 ms 功率包络，标出当前处理窗口 start/end
bottom: 当前处理窗口附近的放大图，用来观察同步段、间隙和后续 burst
```

这一步只是在做离线实验的局部截取。后续要做真正连续解码时，应该改成多窗口
扫描或流式状态机，而不是只处理一个 active window。

### 3. 粗频偏和残余频偏

当前实现先用活动段 PSD 估计粗频偏：

```matlab
[coarseFoHz, coarseInfo] = tetra.coarseFrequencyOffset(activeIq, fs72, cfg);
freqCorrected = activeIq .* exp(-1i * 2 * pi * coarseFoHz .* t);
```

然后在第一次符号定时搜索后，根据差分相位的整体偏移估计残余频偏：

```text
residualHz = diffPhaseOffsetRad * symbolRateHz / (2*pi)
```

如果残余频偏在允许范围内，会再补偿一次并重新做匹配滤波和定时搜索。

### 4. RRC 匹配滤波

`tetra.rrcTaps` 生成 roll-off 为 `0.35` 的 RRC 滤波器，然后：

```matlab
matched = conv(freqCorrected, h, 'same');
```

这里的 `matched` 或 `matched2` 仍然是离散时间复数 IQ 序列，不是已经判决的符号。
它的意义是：用与发射端成形滤波相匹配的滤波器，把符号中心处的信噪比和相位判决
质量提高，同时抑制相邻符号间干扰。

### 5. 符号定时搜索

`tetra.timingSearch` 在一个符号的 4 个采样点范围内搜索小数相位：

```text
0, 0.25, 0.50, ..., 3.75 samples
```

每一个候选相位都会通过线性插值抽样：

```matlab
symbols = common.interpLinear(x, pos);
```

小数样点不是 ADC 真实采到的样点，而是在离散波形上估算“如果这个时刻采样，
值应该是多少”。后续真正使用的就是这些插值得到的符号序列。

每个候选相位都会计算相邻符号的差分相位：

```text
dphi(k) = angle(symbol(k+1) * conj(symbol(k)))
```

pi/4-DQPSK 的理想差分相位中心是：

```text
-3*pi/4, -pi/4, +pi/4, +3*pi/4
```

定时搜索选择让这些差分相位最集中、median error 最小的采样相位。

### 6. pi/4-DQPSK 差分判决

`tetra.pi4dqpskDecision` 使用相邻符号的相位差，而不是绝对星座点位置。当前
标准判决映射是：

```text
dibit 11 -> -3*pi/4
dibit 10 -> -pi/4
dibit 00 -> +pi/4
dibit 01 -> +3*pi/4
```

代码还会尝试几个变体：

```text
standard
conjugate
swap_bits
conjugate_swap
```

然后用训练序列命中情况选择最佳变体。默认 DMO 样本当前选择 `standard`。

### 7. 训练序列扫描

`tetra.findTrainingSequences` 在 hard bit 流中扫描已知训练序列：

```text
normal_1
normal_2
normal_3
extended
sync
```

这一步的作用不是“解码业务”，而是用协议中固定出现的 bit 序列做 sanity check，
并反推出 burst 起点。

## DMO burst 识别

当前 DMO slot 长度：

```text
255 symbols = 510 bits
```

一个 frame 有 4 个 slot，一个 multiframe 有 18 个 frame：

```text
1 frame      = 4 slots
1 multiframe = 18 frames = 72 slots
```

### DSB 布局

`+tetra/dmoBurstDefinitions.m` 中当前 DSB 布局：

```text
slot bits 1..34:     guard/ramp
slot bits 35..46:    P3 preamble
slot bits 47..48:    phase bits
slot bits 49..128:   frequency correction field, 80 bits
slot bits 129..248:  BKN1, logical channel SCH/S, 120 bits
slot bits 249..286:  sync training sequence, 38 bits
slot bits 287..502:  BKN2, logical channel SCH/H, 216 bits
slot bits 503..504:  tail bits, expected 00
slot bits 505..510:  guard/ramp
```

识别 DSB 的核心依据：

```text
1. sync training sequence 命中，并且它应落在 slot bit 249。
2. 反推 slotStart = trainingOffset - 249 + 1。
3. 检查 P3 preamble。
4. 检查 80-bit frequency correction field。
5. 检查 sync training 本身。
6. 检查 tail bits。
```

当前默认阈值要求很严格。样本中确认到的 DSB 基本是：

```text
fieldErr = 0/132
```

这里的 132 是：

```text
P3 12 bits + frequency correction 80 bits + sync training 38 bits + tail 2 bits
```

### DNB 布局

当前识别两类 DNB：

```text
DNB normal_1:
  slot bits 35..46:    P1
  slot bits 49..264:   BKN1, TCH or SCH/F
  slot bits 265..286:  normal_1 training, 22 bits
  slot bits 287..502:  BKN2, TCH or SCH/F

DNB normal_2:
  slot bits 35..46:    P2
  slot bits 49..264:   BKN1, STCH
  slot bits 265..286:  normal_2 training, 22 bits
  slot bits 287..502:  BKN2, TCH or STCH
```

当前 DNB 的 BKN1/BKN2 已经能提取，但还没有继续做 SCH/F、STCH、TCH 的信道
解码。因此它们现在是“可交给下一阶段的物理 payload bit 块”，还不是最终 MAC PDU
或语音帧。

## DSB/SCH/S 解码实现

DSB 中 `BKN1` 承载 `SCH/S`，长度为 120 bit。当前代码已经对这 120 bit 做了
第一个同步信道解码：

```text
DSB BKN1/SCH-S 120 scrambled bits
-> descramble
-> block deinterleave
-> RCPC rate 2/3 hard Viterbi decode
-> split type-2 bits into type-1 + parity + tail
-> DMO block-code parity check
-> parse 60-bit DMAC-SYNC SCH/S fields
```

对应函数：

```text
+tetra/decodeSchS.m
+tetra/scramblingSequence.m
+tetra/blockDeinterleave.m
+tetra/rcpcDecodeRate23.m
+tetra/dmoBlockCodeParity.m
+tetra/parseDmacSyncSchS.m
```

### 1. SCH/S 解扰

入口：

```matlab
schS = tetra.decodeSchS(payloadBlocks(idx).bits, cfg);
```

`decodeSchS` 要求输入正好 120 bit：

```matlab
descrambled = xor(syncBlockBits, tetra.scramblingSequence(120));
```

对 DSB 的 `SCH/S` 和 `SCH/H`，当前实现使用 DSB 规定的零 colour-code seed。
这一步把空口扰码去掉，恢复后续反交织和信道译码需要的 type-3 bit 序列。

### 2. 反交织

```matlab
type3Bits = tetra.blockDeinterleave(descrambled, 11);
```

这里是 `(120, 11)` block deinterleave。交织的作用是把空口中的连续错误打散，
让卷积码和块码更容易处理。接收端必须做反交织，把 bit 顺序还原到信道译码前
的顺序。

### 3. RCPC rate 2/3 Viterbi 解码

```matlab
[type2Bits, rcpcInfo] = tetra.rcpcDecodeRate23(type3Bits, 80);
```

输入 120 bit，输出 80 bit type-2 bits。当前是 hard-decision Viterbi：

```text
state count: 16
initial state: 0
preferred final state: 0
puncturing observation pattern: [1 2 5]
branch metric: Hamming distance
```

默认样本中所有成功 SCH/S 的 `rcpcMetric` 都是 0，说明这些同步块在硬判决层面
没有出现需要 Viterbi 修正的错误。

### 4. type-2 拆分和块码校验

80 bit type-2 被拆成：

```text
type1 bits:  bits 1..60
parity:      bits 61..76
tail:        bits 77..80
```

代码：

```matlab
type1Bits = type2Bits(1:60);
rxParity = type2Bits(61:76);
calcParity = tetra.dmoBlockCodeParity(type1Bits);
tailBits = type2Bits(77:80);
```

`dmoBlockCodeParity` 用 DMO block code 生成 16 bit parity。当前验收要求：

```text
blockCodeErrors <= 0
tailErrors <= 0
```

也就是 parity 必须完全通过，4 个 tail bit 必须全为 0。

### 5. DMAC-SYNC SCH/S 字段解析

通过校验后，`parseDmacSyncSchS` 从 60 bit type-1 中解析：

```text
systemCode
syncPduType
communicationType
conditional flags
abChannelUsage
slotNumber
frameNumber
airInterfaceEncryptionState
encryption dependent or reserved bits
```

默认样本中解析结果稳定为：

```text
system:      EN 300 396-3 DMO AI
sync type:   DMAC-SYNC
comm:        Direct MS-MS
AB usage:    Channel A, normal mode
encryption:  DM-1 no air interface encryption
```

最重要的是：

```text
frameNumber = FN
slotNumber  = TN
```

这两个字段给出了当前 DSB 所在的 DMO multiframe 时序位置。

### 6. 用 SCH/S 给其他 burst 赋时序

确认 DSB 并解出 SCH/S 后，`tetra.inferDmoBursts` 会把 DSB 当作时序参考点。
对没有 SCH/S 的 DNB，代码按 slot 起点差值推算：

```text
slotDelta = round((burst.slotStartBit - ref.slotStartBit) / 510)
```

然后在 72 slot 的循环里推进：

```text
FN/TN index = (FN - 1) * 4 + (TN - 1)
index = mod(index + slotDelta, 72)
FN = floor(index / 4) + 1
TN = mod(index, 4) + 1
```

这就是当前 Fig11 中 DNB 也能显示 `FNx TNy` 的原因。DNB 自身没有被解出
SCH/S，它的时序是从附近 DSB 推算得到的。

## DSB frequency correction 验证

DSB 的 frequency correction field 是 80 bit：

```text
8 ones + 64 zeros + 8 ones
```

按 dibit 两两分组，就是：

```text
4 symbols of 11
32 symbols of 00
4 symbols of 11
```

当前 pi/4-DQPSK 映射：

```text
11 -> -3*pi/4
00 -> +pi/4
```

差分相位如果每个符号固定增加 `Delta phase`，等效频率就是：

```text
f = Delta phase / (2*pi) * symbolRate
```

所以：

```text
11: f = (-3*pi/4) / (2*pi) * 18000 = -6750 Hz
00: f = (+pi/4)  / (2*pi) * 18000 = +2250 Hz
```

这就是 `12_frequency_correction_check` 里理论图案的来源：

```text
4 symbols at -6.75 kHz
32 symbols at +2.25 kHz
4 symbols at -6.75 kHz
```

当前长窗口中，38 个 DSB 都通过了这个检查，整体 median abs error 约 59 Hz。
这个图的价值是：它不是只看 training sequence，而是直接验证 DSB 的固定频率
校正字段是否在差分相位层面符合 TETRA 的数学结构。

## 输出文件

每次运行 `tetra.symbolDebug` 都会写：

```text
summary.mat
summary.json
bits_preview.txt
slots_preview.txt
dmo_payload_preview.txt
schs_preview.txt
frequency_correction_preview.txt
```

`09_decision_preview` deliberately starts at the first confirmed burst when one
is available. If it started at the active-window pre-pad, the displayed dibits
could be dominated by noise or ramp-up before the first DSB and therefore show a
misleading subset of dibit levels.

`13_transition_validity` compares the Fig8 timing-valid/low-energy transition
mask with confirmed DSB/DNB spans. In the current long-window DMO sample,
transitions inside confirmed bursts are timing-valid about 96.2 % of the time,
while transitions outside confirmed bursts are timing-valid only about 0.2 % of
the time. This confirms that most Fig8 grey points are off-burst gaps,
guard/ramp regions, or burst-boundary transitions rather than TETRA payload
symbols.

关键文件：

```text
slots_preview.txt
  候选 burst、确认 burst、字段错误、BKN 范围、SCH/S 摘要。

dmo_payload_preview.txt
  已确认 DSB/DNB 的 BKN1/BKN2 bit 块。

schs_preview.txt
  DSB BKN1/SCH-S 的解码结果，包括 FN/TN、通信类型、加密状态。

frequency_correction_preview.txt
  DSB frequency correction field 的理论值、观测值和误差。
```

## 当前边界和下一步

当前已经完成：

```text
1. 从 IQ 恢复稳定 hard bit 流。
2. 用训练序列和固定字段确认 DMO DSB/DNB。
3. 提取 DSB/DNB 的 BKN1/BKN2。
4. 解码 DSB BKN1/SCH-S。
5. 拿到 DMO frame/slot 时序上下文。
6. 用 DSB 的 SCH/S 时序给邻近 DNB 赋 FN/TN。
```

当前还没有完成：

```text
1. DSB BKN2/SCH-H 解码。
2. DNB SCH/F 解码。
3. DNB normal_2 的 STCH 解码。
4. TCH/语音业务信道解码。
5. 连续文件级或流式多 active-window 状态跟踪。
```

因此下一步建议是：

```text
1. 优先解 DSB BKN2/SCH-H，因为它和 SCH/S 同在 DSB 中，时序已经可靠。
2. 再解 normal_2 DNB 的 STCH，用于呼叫控制或 stealing 信息。
3. 最后接 TCH/语音信道，进入真正的业务内容恢复。
```

## Burst-aware 差分判决改进计划

当前 `tetra.symbolDebug` 为了便于第一阶段调试，是对整个 active window 连续
抽样并连续计算差分相位：

```text
symbol(k), symbol(k+1) -> dphi(k)
```

这会产生跨越以下区域的无意义 transition：

```text
slot guard/ramp
burst 外空隙
发射关闭或重新开启
不同 burst 之间的相位重置
active window pre-pad/post-pad
```

这些 transition 当前不会参与 timing/phase offset 估计，并且在 Fig8/Fig13 中
标为 low-energy。后续正式链路层输入不应该依赖整段连续 hard bit stream，而
应该改成 burst-aware 输出：

```text
1. 先用能量、训练序列和固定字段确认 DSB/DNB slot。
2. 不跨 slot/burst 边界解释差分相位。
3. 对每个 confirmed burst 单独形成连续 slot bit 序列。
4. slot 开头的 guard/ramp 和不可靠初始 transition 不进入 BKN payload。
5. 只输出结构化 BKN payload，而不是输出整段 active window bit 流。
```

目标输出结构应类似：

```text
Burst {
  burstType
  trainingName
  frameNumber
  slotNumber
  slotStartBit
  slotEndBit
  bkn1Bits
  bkn2Bits
  validTransitionRatio
  fieldErrors
}
```

链路层只消费：

```text
DSB BKN1 -> SCH/S
DSB BKN2 -> SCH/H
DNB normal_2 BKN1 -> STCH
DNB normal_2 BKN2 -> TCH or STCH
DNB normal_1 BKN1+BKN2 -> TCH or SCH/F
```

链路层不消费：

```text
burst 外 hard bits
guard/ramp bits
跨 burst/gap 的 differential transition
active window pre-pad/post-pad bits
```

这项改进的核心原则是：**低能量点不是要被“修正”的 payload bit，而是要在
burst 边界确认后从链路层输入中排除；burst 内少量错误 bit 再交给训练序列、
固定字段、RCPC、block code、CRC/FCS 等机制处理。**
