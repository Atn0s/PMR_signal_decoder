# NXDN96 独立解码实现方案

状态：已实现、通过独立测试及全项目回归，并已接入统一 scanner。

当前本地样本基线：

| 样本 | 有效帧 | CRC有效信道块 | 呼叫会话 |
|---|---:|---:|---:|
| `nxdn96_1_78125.rawiq` | 524 | 1062 | 4 |
| `nxdn96_2_78125.rawiq` | 574 | 1160 | 4 |

两个样本均解析出 RAN 40、源 ID 1203、conference group call、TX_REL 和分段别名
`WM 3`。VCH 只记录存在性，没有进入正式数据 PDU。

## 1. 目标与边界

本阶段只开发 NXDN96，即 12.5 kHz 信道、9600 bit/s、4800 symbol/s 的 NXDN
空中接口。输入是已经给出中心频点或已经基本居中的窄带复数 IQ。

本阶段目标是：

1. 从复数 IQ 稳定恢复 NXDN96 帧；
2. 先完成 FSW、LICH、SACCH 和 FACCH1，再补齐 CAC、UDCH 和 FACCH2 的
   NXDN96 物理层及信道译码；
3. 重组完整 SACCH 超帧；
4. 解析 CRC 有效的 Layer 3 数据 PDU；
5. 输出与 DMR、P25、dPMR 一致的统一 PDU 结构；
6. 在两份本地 NXDN96 样本和合成测试向量上通过测试。

明确不属于本阶段的内容：

- 独立开发阶段不修改 `radio.protocolRegistry`、`scanner.m` 或默认扫描协议；该约束
  已在独立基线提交后解除，并通过后续分阶段接入完成统一注册；
- 不进行多制式识别、宽带盲扫或并行调度；
- 不支持 NXDN48（6.25 kHz、4800 bit/s）；
- 不支持 Type-D 专用帧结构；
- 不解码 AMBE/AMBE+2 语音，不输出音频；
- 不因为发现 VCH 就把语音负载伪装成数据 PDU；
- RCCH/CAC、UDCH、FACCH2 不属于现有两份样本驱动的首个里程碑，但属于独立
  NXDN96 模块完成后、接入 scanner 之前必须补齐的范围。

代码包使用 `+nxdn`，而不是 `+nxdn96`。速率模式放在配置中，从而避免以后加入
NXDN48 时复制整个协议目录。

## 2. “完整 PDU”的定义

本项目中的完整数据 PDU 必须满足以下条件之一：

- FACCH1：一个 144 bit 物理信道块完成去交织、去打孔、Viterbi 译码和 CRC12
  校验，得到完整的 80 bit Layer 3 数据；
- SACCH：四个 CRC6 有效的 18 bit 分片按照 1/4、2/4、3/4、4/4 顺序重组，得到
  完整的 72 bit Layer 3 数据；
- 非超帧 SACCH：只在标准明确表示为单消息且 CRC6 有效时输出相应短数据记录，不能
  将单个超帧分片当成完整 72 bit PDU；
- UDCH/FACCH2：一个 348 bit 物理块完成去交织、去打孔、Viterbi 和 CRC15 校验，
  得到 SR 及完整的 176 bit Layer 3 数据；
- CAC：根据 LICH 和方向选择 Outbound CAC、Inbound Long CAC 或 Inbound Short CAC
  的译码参数，完成 Viterbi、CRC16 和固定 null/tail 校验，得到完整的 144、128 或
  96 bit Layer 3 数据。

LICH 通过奇偶校验只表示帧结构可信，不等于 Layer 3 PDU 已经解码成功。单个 SACCH
分片、CRC 失败块、同步候选和 VCH 区域只进入诊断报告，不进入正式数据 PDU 列表。

未知 Layer 3 消息类型不能丢弃。只要信道 CRC 有效，就输出
`NXDN_L3_UNKNOWN`，并保留功能信道、消息类型、方向、RAN、完整 payload hex 和
`raw_bits`。这样“尚未语义解析”与“译码失败”能够明确区分。

## 3. NXDN96 物理层基线

关键参数如下：

| 参数 | NXDN96 值 |
|---|---:|
| 信道间隔 | 12.5 kHz |
| 比特率 | 9600 bit/s |
| 符号率 | 4800 symbol/s |
| 建议内部采样率 | 48 kHz |
| 每符号采样数 | 10 |
| 帧长 | 40 ms |
| 每帧 | 384 bit / 192 symbol |
| FSW | 20 bit，`0xCDF59` |
| PN9 | `X^9 + X^4 + 1` |
| PN9 初值 | `0x0E4`，每帧复位 |

4FSK 映射：

| Dibit | 符号电平 | 标称频偏 |
|---|---:|---:|
| `01` | `+3` | `+2400 Hz` |
| `00` | `+1` | `+800 Hz` |
| `10` | `-1` | `-800 Hz` |
| `11` | `-3` | `-2400 Hz` |

384 bit 帧的固定布局为：

```text
FSW 20 | LICH 16 | SACCH 60 | payload half 1 144 | payload half 2 144
```

对应 192 个符号：

```text
FSW 1..10 | LICH 11..18 | SACCH 19..48 | half 1 49..120 | half 2 121..192
```

FSW 不参与扰码。从 LICH 开始到帧尾的 182 个 dibit 使用同一帧内 PN9 序列；PN9
作用是根据序列位翻转 dibit 的符号位。实现必须在 dibit 层解扰，不能先丢掉幅度位。

## 4. 独立调用链

开发阶段不经过 scanner，调用链固定为：

```text
nxdn96_cli.m
  -> common.readRawIq / common.detectSampleRate
  -> nxdn.decodeIq(iq, inputSampleRate, cfg)
       -> nxdn.frontend
       -> nxdn.decode
            -> findFrameSync
            -> recoverFrameSymbols
            -> descrambleDibits
            -> decodeLich / frameInfoFromLich
            -> decodeSacch / decodeFacch1 / decodeUdchFacch2 / decodeCac
            -> sacchAssembler
            -> parseLayer3
            -> PDU/session output
```

推荐公共接口：

```matlab
cfg = nxdn.config();
[pdus, report] = nxdn.decodeIq(iq, sampleRate, cfg);
```

同时保留未来 scanner 需要的分层接口：

```matlab
y = nxdn.frontend(iq, sampleRate, cfg);
[pdus, report] = nxdn.decode(y, cfg);
```

`decodeIq` 只是独立开发期的薄封装，核心算法不能只藏在该函数中。

## 5. 文件架构

### 5.1 与现有协议一致的稳定外层

以下文件有意识地与 DMR、P25、dPMR 保持一致：

```text
+nxdn/
  config.m
  constants.m
  spec.m
  frontend.m
  decode.m
  postprocess.m
  dedupKey.m
  formatPdu.m
  sessionInit.m
  sessionFeed.m
  sessionFinalize.m
```

职责如下：

- `config.m`：只保存可调参数和标准常量的配置值；
- `constants.m`：FSW、dibit 映射、帧位置、LICH 枚举和消息类型表；
- `spec.m`：提前提供兼容统一注册表的适配器，但本阶段不注册；
- `frontend.m`：DDC、重采样、信道滤波、FM 鉴频、DC/残余频偏校正；
- `decode.m`：协议流水线编排，不堆积底层算法；
- `postprocess.m`：统一 PDU 规范化入口；
- `dedupKey.m`：以后接入统一去重时直接使用；
- `formatPdu.m`：独立 CLI 和未来 scanner 共用文本格式；
- `session*`：将 VCALL、TX_REL 等数据 PDU 汇总为可选的 `NXDN_CALL`，不涉及语音。

`spec.m` 的预期形状为：

```matlab
name                    = 'NXDN'
aliases                 = {'nxdn', 'nxdn96'}
frontendKey             = 'nxdn_4fsk'
scanMode                = 'narrowband_4fsk'
targetSampleRateHz      = 48000
supportsBlindSearch     = true
supportsFrequencyOffsets = true
```

此文件存在不代表已经接入。只有后续整体接入阶段才修改协议名称规范化、注册表、扫描
默认值和入口测试。

### 5.2 NXDN 协议内部文件

建议拆分为：

```text
+nxdn/
  findFrameSync.m
  recoverFrameSymbols.m
  sliceDibits.m
  descrambleDibits.m
  pn9Sequence.m
  decodeLich.m
  frameInfoFromLich.m
  blockDeinterleave.m
  depuncture.m
  viterbiDecodeK5.m
  crc6.m
  crc12.m
  crc15.m
  crc16Cac.m
  decodeSacch.m
  decodeFacch1.m
  decodeUdchFacch2.m
  decodeCac.m
  sacchAssemblerInit.m
  sacchAssemblerFeed.m
  parseLayer3.m
  messageTypeName.m
  bitsToInt.m
  bitsToHex.m
```

不要把去交织、Viterbi、CRC、LICH 和 Layer 3 解析全部写进 `decode.m`。这些函数
需要能够接受合成 bit vector 独立测试。

第一版 Viterbi 建议实现协议内的 K=5 译码器，支持打孔位置的 erasure metric，避免
引入新的 Communications Toolbox 依赖。先使用可靠的硬判决路径；符号质量和路径
metric 保留在诊断结构中，为后续软判决升级预留接口。

## 6. 前端、同步和帧锁

### 6.1 前端

`frontend.m` 可以复用 `common.fskFrontend` 的基本结构，但必须使用 NXDN 自己的
配置：

```text
targetSampleRateHz = 48000
symbolRateHz       = 4800
samplesPerSymbol   = 10
nominalDeviationHz = 2400
frontendCutoffHz   = 约 6500，最终由样本测试确定
```

不得复用 DMR/P25 的 `c4fm_4fsk` 归一化结果。两者虽然符号率相同，标称频偏和最佳
滤波配置不同。单独前端也是保持现有三制式稳定的隔离边界。

前端诊断至少记录：

- 输入和输出采样率；
- 粗频偏及残余 DC；
- 有效样本功率；
- 滤波配置；
- 输出样本数及与原始输入的索引换算关系。

### 6.2 FSW 检测

`findFrameSync` 使用完整四电平 FSW 模板，不只使用正负号。它应：

1. 在 10 个采样相位上寻找候选；
2. 输出归一化相关分数、符号相位、极性和 FSW 起始位置；
3. 以 40 ms 周期聚类候选，抑制同一帧的重复峰；
4. 允许短时漏帧，但需要连续周期证据后进入锁定状态；
5. 不以单个低质量相关峰宣告有效帧。

候选结构建议为：

```text
fs_start
symbol_phase
polarity
score
frame_index
locked
```

### 6.3 帧恢复和切片

每个候选恢复 192 个符号。切片器使用 `+3/+1/-1/-3` 最近邻判决，同时输出：

- dibit；
- 归一化符号电平；
- 最近判决距离；
- 每帧平均/最大判决误差。

同步极性和残余中心偏差必须先修正，再进行 LICH 和信道译码。不能通过放宽 CRC 或
奇偶校验来掩盖定时错误。

## 7. LICH 和帧分类

LICH 的处理顺序为：

1. 对 LICH 的 8 个 dibit 执行 PN9 解扰；
2. 从每个 dibit 取信息位，组合为 8 bit（7 bit LICH 加 1 bit parity）；
3. 检查每个编码 dibit 的固定填充位；
4. 检查 LICH parity；
5. 解析 RF channel、functional channel、option/steal flag 和 direction；
6. 根据 steal flag 决定两个 144 bit half 是 VCH 还是 FACCH1。

`frameInfoFromLich` 至少输出：

```text
lich_value
parity_ok
fill_bits_ok
rf_channel_type       RCCH / RTCH / RDCH / RTCH_C
functional_channel    SACCH / UDCH / idle / CAC
direction             inbound / outbound
steal_flag
half1_type            VCH / FACCH1 / other
half2_type            VCH / FACCH1 / other
superframe
```

当前样本中已确认的主导 LICH 为：

- `0x50`：RDCH、超帧 SACCH、两个 half 均为 FACCH1、入站；
- `0x56`：RDCH、超帧 SACCH、两个 half 均为 VCH、入站；
- 少量 `0x40`：RDCH、非超帧 SACCH、两个 half 均为 FACCH1、入站。

这些向量应直接成为 LICH 单元测试，而不是只依赖大样本回归。

## 8. SACCH 和 FACCH1 信道译码

### 8.1 SACCH

每帧 SACCH 的物理输入是 60 bit，逆向处理为：

```text
60 received
-> deinterleave (depth 5)
-> depuncture to 72 coded bits
-> K=5, rate 1/2 Viterbi
-> 36 decoded bits
-> 26 information bits + CRC6 + 4 zero tail bits
-> SR 8 bits + Layer 3 fragment 18 bits
```

CRC6 生成多项式：

```text
X^6 + X^5 + X^2 + X + 1
```

超帧重组器以 SR 的 structure 字段区分 `1/4 -> 2/4 -> 3/4 -> 4/4`。以下任一条件
发生时必须丢弃未完成组装并重新等待 `1/4`：

- 分片序号跳变、重复或乱序；
- 中间帧 CRC 失败；
- RAN、方向或 RF channel 改变；
- 帧位置不再满足 40 ms 连续关系；
- 超过配置的组装超时。

只有四个 18 bit 分片齐全时才向 `parseLayer3` 交付 72 bit 数据。

### 8.2 FACCH1

每个被 LICH 标记为 FACCH1 的 half 独立译码：

```text
144 received
-> deinterleave (depth 9)
-> depuncture to 192 coded bits
-> K=5, rate 1/2 Viterbi
-> 96 decoded bits
-> 80 Layer 3 bits + CRC12 + 4 zero tail bits
```

CRC12 生成多项式：

```text
X^12 + X^11 + X^3 + X^2 + X + 1
```

两个 half 必须分别保留 `half_index`。如果承载相同 PDU，语义去重由
`dedupKey` 处理；信道译码层不能假设两个 half 一定重复。

Viterbi 输出除数据外还应包含路径 metric、尾状态和 tail error。正式 PDU 必须 CRC
有效；CRC 失败块只在 `report.channelBlocks` 中保留。

### 8.3 UDCH 和 FACCH2

当 LICH 将业务区标记为 UDCH 或 FACCH2 时，348 bit 物理块按同一信道编码逆向
处理：

```text
348 received
-> deinterleave (depth 29)
-> depuncture to 406 coded bits
-> K=5, rate 1/2 Viterbi
-> 203 decoded bits
-> SR 8 bits + 176 Layer 3 bits + CRC15 + 4 zero tail bits
```

CRC15 生成多项式：

```text
X^15 + X^14 + X^11 + X^10 + X^7 + X^6 + X^2 + 1
```

UDCH 和 FACCH2 都承载 22 octet Layer 3 数据，但语义和消息允许范围不同，必须根据
LICH 保留正确的 `functional_channel`。UDCH 的后续数据块可能主要是用户数据；只要
CRC 有效就应完整输出 payload 和序列信息，即使暂未解释用户数据内容。

### 8.4 CAC

RCCH 按方向和 CAC 类型使用三套参数：

| 类型 | 物理 bit | 信息组成 | CRC | 交织深度 |
|---|---:|---|---:|---:|
| Outbound CAC | 300 | SR 8 + L3 144 + null 3 | 16 | 25 |
| Inbound Long CAC | 252 | SR 8 + L3 128 | 16 | 21 |
| Inbound Short CAC | 252 | SR 8 + L3 96 + null 2 | 16 | 21 |

三者均使用 K=5、rate 1/2 卷积码和 4 个 zero tail bit，但 puncture pattern 不同；
Short CAC 不打孔。CRC16 生成多项式为：

```text
X^16 + X^12 + X^5 + 1
```

固定 null、tail 和 CRC 必须同时校验。RCCH 帧中 CAC 之外的 guard/post 区域只用于
帧布局和诊断，不进入 Layer 3 payload。

## 9. Layer 3 和统一 PDU

Layer 3 parser 接受已经通过信道 CRC 的 SACCH、FACCH1、UDCH、FACCH2 或 CAC
数据，按 MSB-first 转换为 octet。首批语义解析至少覆盖当前业务信道常见消息：

- `VCALL`；
- `VCALL_IV`；
- `TX_REL`；
- `TX_REL_EX`；
- `IDLE`；
- 样本中实际出现的补充业务消息。

在允许接入 scanner 之前，还要为 RCCH 和数据业务补齐消息分派表，包括呼叫请求、
响应、信道指配、数据呼叫、状态/短数据及断开类消息。语义尚未实现的标准消息仍可
先以 CRC 有效的 generic PDU 输出，但其完整 channel payload、message type、方向和
功能信道不得丢失。

解析器必须先建立通用 message type dispatch。未实现的标准消息仍输出完整原始数据，
后续增加消息解析时不需要修改物理层和信道译码层。

统一 PDU 固定字段与现有制式一致：

```matlab
pdu = struct( ...
    'protocol', 'NXDN', ...
    'type', 'NXDN_VCALL', ...
    'src', sourceId, ...
    'dst', destinationId, ...
    'ts', 0, ...
    'flco', 'VCALL', ...
    'fid', '', ...
    'extra', extra, ...
    'raw_bits', layer3Bits);
```

`extra` 至少包含：

```text
ran
rf_channel_type
functional_channel
direction
lich
message_type
message_name
payload_hex
crc_ok
fs_start
frame_index
half_index
superframe_start
call_type
cipher_type
key_id
voice_present
voice_half_mask
```

不适用于某条消息的字段可以为空，但字段含义不能随消息类型改变。`src`、`dst` 只有
在标准消息中确实存在并成功解析时才填写，不能从相邻帧猜测后回填到原始 PDU。

`NXDN_CALL` 是会话汇总 PDU，和原始 `NXDN_VCALL`、`NXDN_TX_REL` 并存。它只能由
数据控制消息生成，不依赖语音内容。

### 9.1 后续优化：跨功能信道语义去重

当前打印路径已经启用 `nxdn.deduplicatePdus`。两份样本分别由 415/452 条原始 PDU
去重到 16 条，去除率约 96%。当前键保留完整 `payload_hex`，因此同一 Layer 3 消息
分别由 SACCH 和 FACCH1 承载时仍会保留两份：VCALL 为 2 条，4 个 Alias 分片为
8 条。

此行为暂时保留，便于观察消息来自哪个功能信道，不作为统一入口接入的阻塞项。后续
需要更精简的事件打印时，再增加规范化语义键：

- VCALL 使用 RAN、源/目标 ID、呼叫类型、Voice Option、Cipher 和 Key ID；
- TX_REL 使用 RAN、源/目标 ID 和呼叫类型；
- Alias 使用 MFID、分片序号、总分片数和有效 alias bytes；
- `NXDN_CALL` 继续保留 `start_sample`，不能把不同呼叫会话合并；
- 未知消息继续使用完整 payload，避免错误合并。

按当前样本估算，启用跨信道语义去重后，16 条打印记录可进一步收敛到 11 条。

## 10. 诊断报告

独立开发阶段需要比最终 scanner 输出更丰富的 `report`：

```text
frontend
syncCandidates
frames
lichHistogram
channelBlocks
sacchAssemblies
pduCount
quality
```

每帧诊断建议包含 FSW score、定时相位、切片误差、LICH 值及校验、SACCH CRC、两个
half 的类型和 FACCH1 CRC。诊断结构用于定位算法问题，不应全部复制进每个正式 PDU。

## 11. 测试方案

### 11.1 纯单元测试

新增 `+tests/runNxdn96.m`，并由 `+tests/runAll.m` 调用。至少覆盖：

1. FSW 标准模板和 dibit/频偏映射；
2. PN9 初始序列、逐帧复位和扰码/解扰往返；
3. 已知 LICH 向量：`0x50`、`0x56`、`0x40`；
4. LICH parity 错误和固定填充位错误；
5. CRC6、CRC12、CRC15、CRC16 的已知向量和单 bit 错误拒绝；
6. K=5 卷积编码/Viterbi 往返；
7. puncture/depuncture 和 interleave/deinterleave 往返；
8. 合成 FACCH1 从 Layer 3 数据到物理 bit 再译码；
9. 合成四帧 SACCH 超帧重组；
10. SACCH 缺帧、乱序、RAN 改变和 CRC 失败时不输出完整 PDU；
11. VCALL、TX_REL 和未知消息的 Layer 3 解析；
12. 纯噪声、错误 FSW 和不完整尾帧返回空 PDU；
13. VCH 数据不会进入正式 PDU 的 `raw_bits` 或 `payload_hex`；
14. 合成 UDCH/FACCH2 和三种 CAC 的正向编码、逆向译码及错误拒绝。

测试编码器只放在测试包中，用来生成正向向量，不能和生产解码路径共享同一个逆向
实现，以免同一错误在编码和解码两侧互相抵消。

### 11.2 本地样本集成测试

使用：

```text
signal_data/nxdn96_1_78125.rawiq
signal_data/nxdn96_2_78125.rawiq
```

这两个文件继续由 `.gitignore` 排除，不提交远程。集成测试在文件不存在时明确显示
`SKIP`，不能导致其他开发环境失败。

样本验收条件：

- 两个文件都建立连续 40 ms 帧锁；
- 主要 LICH 包含 `0x50` 和 `0x56`，且 parity 通过率达到稳定高水平；
- 两个文件都产生 CRC 有效的 SACCH 或 FACCH1 完整 PDU；
- 每个输出 PDU 的功能信道、RAN、方向、消息类型和 payload hex 可追溯到具体帧；
- 重复运行得到相同的语义 PDU 集合；
- 不输出任何解码后的语音或 VCH payload；
- 第一轮可靠译码完成后，将实际 PDU 数量、类型和关键字段冻结为本地 golden 摘要。

不在实现前硬编码“样本一定包含 VCALL/TX_REL”。消息类型必须由 CRC 有效的实际译码
结果确定，再固化 golden，避免为了满足预期而错误调参。

### 11.3 现有回归

NXDN 开发期间必须持续通过：

```matlab
tests.runAll()
```

并确认 DMR、P25、dPMR、TETRA 的输出没有变化。由于本阶段不修改 registry 和
scanner，现有默认协议集合也必须保持不变。

## 12. 分阶段实施顺序

### 阶段 A：物理层锁定

实现 `config/constants/frontend/findFrameSync/recoverFrameSymbols/sliceDibits`，在两份
样本上稳定找到 40 ms 帧序列。

验收：帧位置、相关分数、极性和 LICH 原始 dibit 可重复。

### 阶段 B：解扰和 LICH

实现 PN9、LICH parity、固定填充位和帧分类。

验收：样本稳定得到 `0x50/0x56/0x40`，并正确标记 FACCH1/VCH half。

### 阶段 C：信道译码

实现去交织、去打孔、K=5 Viterbi、CRC6/CRC12、SACCH 和 FACCH1。

验收：合成向量全部通过，真实样本出现可重复的 CRC 有效块。

### 阶段 D：补齐 NXDN96 数据/控制信道

实现 UDCH/FACCH2、Outbound CAC、Inbound Long CAC 和 Inbound Short CAC，使用
合成标准向量完成 CRC、puncture、interleave 和帧布局测试。

验收：所有 NXDN96 非语音功能信道都能产生 CRC 有效的完整 channel payload；错误
向量不会产生正式 PDU。

### 阶段 E：Layer 3 和完整 PDU

实现 SACCH 超帧组装、消息 dispatch、常见呼叫消息、未知消息保留、统一 PDU 和
格式化。

验收：两份样本都输出可追溯的完整数据 PDU，字段和 raw bits 一致。

### 阶段 F：会话与独立入口

实现 `session*`、`postprocess/dedupKey/formatPdu`、`decodeIq` 和 `nxdn96_cli.m`，补齐
本地 golden 摘要。

验收：独立入口可直接读取两个样本并输出 PDU/JSON；所有 NXDN 和现有测试通过。

### 后续独立阶段

独立解码验收完成后，统一 scanner 注册、默认串行和 blind search 已按阶段完成。
后续独立阶段包括：

1. 加入已知频点多制式并行 probe；
2. 支持 NXDN48；
3. 支持 Type-D；
4. 提取或解码语音。

## 13. 完成标准

本阶段只有同时满足以下条件才算完成：

- `+nxdn` 文件边界符合本方案，核心算法可独立单元测试；
- FSW、PN9、LICH、SACCH、FACCH1、UDCH、FACCH2、CAC、各类 CRC 和 Layer 3
  均有正反测试；
- 两个真实样本均产生 CRC 有效的完整数据 PDU；
- 所有 NXDN96 非语音功能信道均有合成端到端测试；
- 未知但 CRC 有效的消息得到保留，不被误报为失败；
- VCH 只产生诊断元数据，不解析、不保存为数据 payload；
- `tests.runAll()` 和 `tests.runNxdn96()` 均通过；
- 独立基线提交保持 `radio.protocolRegistry` 和 scanner 不变；后续接入提交另行验证
  显式、默认串行和 blind-search 行为；
- 大样本继续被忽略，不进入 Git；
- 文档、CLI 输出和 PDU 字段与代码一致。
