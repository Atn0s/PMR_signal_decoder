# 信号输入到原始 Dibit 恢复实现说明

> 文档基线：2026-07-15 当前工作区代码
>
> 适用工程：MATLAB Multi-Protocol Radio Decoder
>
> 覆盖制式：DMR、P25 Phase 1、dPMR、NXDN96、TETRA DMO

## 1. 文档目的与边界

本文说明当前工程从复数 IQ 信号进入系统，到恢复出空口硬判决 dibit 为止，已经实现了
哪些模块、各模块怎样连接、关键参数是什么，以及当前实现仍有哪些限制。

本文覆盖：

1. BVSP、无头交错 IQ、双通道 IQ WAV 和内存 IQ 的输入；
2. 整文件、分块回放和统一 `IqChunk` 时间轴；
3. 已居中基带、指定频偏、人工频谱选频和宽带自动候选发现；
4. DDC、抗混叠滤波、抽取、PFB 信道化、细频偏校正和协议目标采样率转换；
5. 活动窗口、RF Epoch 和协议观察窗对物理层输入的切分；
6. 四种 4FSK 制式的鉴频、同步、符号定时、幅度校准和 dibit 判决；
7. TETRA 的频偏校正、RRC 匹配滤波、符号定时、差分相位判决和 dibit 可靠度。

本文不展开恢复 dibit 之后的协议后端，包括但不限于：

- DMR 的 Slot Type、BPTC、RS、CSBK、Full Link Control 和会话解析；
- P25 的 NID/BCH、HDU/LDU、Golay/RS/Hamming 和 Link Control；
- dPMR 的 CCH、颜色码、呼叫标识和超帧拼接；
- NXDN 的 PN9 解扰、LICH、SACCH、FACCH、CAC、UDCH 和 Layer 3；
- TETRA 的 DSB/DNB 突发分类、BKN、RCPC、DMAC 和会话解析。

本文采用如下边界定义：

> “原始 dibit”是调制判决器根据接收波形恢复出的空口二比特硬判决，位于解扰、解交织、
> 信道译码、CRC/FEC 校验和协议字段解析之前。同步模板可以用于定时、极性和幅度校准；
> TETRA 训练序列可以用于解决共轭和位序歧义，但不在本文继续进入链路层负载解析。

NXDN 尤其需要区分两个概念：`nxdn.sliceDibits` 输出的是物理判决后的、尚未 PN9 解扰的
空口 dibit；`nxdn.descrambleDibits` 已经属于本文边界之后。

本文以默认的原生 MATLAB 路径，即 `PipelineBackend='matlab'`、
`DecoderBackend='matlab'` 为准。工程仍保留 Python 兼容桥，用于行为对照和回退；它不是
本文所描述的 MATLAB 前端实现。NXDN 不支持 Python decoder fallback，流式五制式窗口
入口也直接调用原生 MATLAB 物理层。

## 2. 当前实现的总体数据流

当前工程并非只有一条输入链。不同入口最终都把一个已选出的单信道复基带窗口送入五种
制式各自的物理层恢复器。

```text
BVSP / RAW IQ / stereo IQ WAV / memory IQ / future SDR IqChunk
                              |
             +----------------+----------------+
             |                |                |
             v                v                v
       已居中或给定频偏    人工频谱点击选频      宽带自动发现
       serial / parallel   radio_frontend     wideband WOLA/PFB
             |                |                |
             |          单载频有状态 DDC       粗子带 + 细频点跟踪
             |                |                +-> 细 DDC/低通
             |                |                |
             +----------------+----------------+
                              |
                  单信道复数基带 IQ 窗口
                              |
          +-------------------+-------------------+
          |                   |                   |
          v                   v                   v
     48 kS/s 4FSK        48 kS/s NXDN       72 kS/s TETRA
   DMR/P25/dPMR        独立 4FSK 前端       pi/4-DQPSK 前端
          |                   |                   |
          v                   v                   v
   FM 鉴频实数波形      FM 鉴频实数波形       RRC 后复符号
          |                   |                   |
   同步/定时/校准        FSW/定时/校准       定时/差分相位/歧义选择
          |                   |                   |
          +-------------------+-------------------+
                              |
                    空口 hard dibit / bit pair
                              |
                 ===== 本文说明到此为止 =====
                              |
                  解扰、FEC、帧与 PDU 后端
```

### 2.1 四种公共执行方式

| 执行方式 | 主要入口 | 输入假设 | 载频处理 | 到协议前的典型采样率 |
|---|---|---|---|---:|
| 传统串行离线 | `radio.scanFile`，`ExecutionMode='serial'` | 整文件，可已居中、给出 `FreqList` 或做传统 PSD 盲扫 | 直接复数混频；必要时多相重采样 | 4FSK 为 48 kS/s；TETRA 自行转 72 kS/s |
| 已居中并行识别 | `ExecutionMode='parallel'` | 单个已居中基带信道 | 不再发现载频，按 Epoch 切窗 | 保持源速率，进入每个制式时转 48/72 kS/s |
| 已知载频过渡链/交互前端 | `ExecutionMode='tuned-parallel'` 或 `radio_frontend` | 宽带 IQ 中给出一个载频 | 有状态数字下变频和抗混叠抽取 | 先到 120 kS/s，再转 48/72 kS/s |
| 宽带自动发现 | `ExecutionMode='wideband'` | 宽带 RAW/WAV 或内存 IQ | 2 倍过采样 WOLA/PFB、候选跟踪、细 DDC | 61.44 MS/s 输入时子带为 120 kS/s，再转 48/72 kS/s |

交互式 `radio_frontend` 与自动 `radio.wideband` 是两条不同链：前者由用户在实时绘制的
频谱上选择一个载频，后者由 PFB 和候选检测器自动维护多个频率轨迹。当前交互前端不会
在后台同时运行 PFB 自动发现。

为兼容旧脚本，`radio.scanFile` 在收到 `ExecutionMode='parallel'`、一个非零
`FreqList` 且未开启盲扫时，会自动改走已知载频 DDC 过渡链。真正“已经居中的并行
基带”入口应使用空 `FreqList`。

## 3. 信号输入层

### 3.1 整文件 IQ 读取

传统离线路径由 `common.readRawIq` 读取完整文件：

- 无头 RAW 按 `I,Q,I,Q,...` 交错排列；
- 支持 `int8`、`int16`、`int32`、`single/float32` 和 `double/float64`；
- 整数默认分别除以 `128`、`32768`、`2147483648`，得到复数 `double`；
- 浮点输入默认比例为 `1`；
- WAV 使用前两个声道作为 I 和 Q，要求至少双声道；
- 若 RAW 最后只剩一个不成对的标量，整文件读取器只保留完整的 IQ 对。

`common.detectSampleRate` 按以下顺序推断采样率：

1. 文件名末尾 `_数字.rawiq`，例如 `_78125.rawiq`；
2. 文件名末尾的 `数字MHz.rawiq`；
3. WAV 自身的 `SampleRate` 元数据；
4. 都无法取得时，调用者必须显式传入采样率。

### 3.2 BVSP 捕获

`radio.tuned.captureInfo` 和循环回放源支持当前样本中已经观察到的 BVSP/USRP/CI16
格式：

- 112 字节小端头；
- 负载为交错 `int16` IQ；
- 从头部取得采样率、带宽、RF 中心频率、设备字符串、文件序号和声明文件长度；
- RF 中心频率头字段按 kHz 保存，读取后乘以 1000 得到 Hz；
- 文件长度和 IQ 对齐不一致时直接报错。

BVSP 支持集中在 `radio.tuned`、`radio.replay` 和 `radio_frontend`。传统
`common.readRawIq` 本身不解析 BVSP 头；自动 PFB 文件入口目前也没有独立的 BVSP
头解析参数。因此处理 BVSP 宽带录音时，应使用已知载频链或交互前端，而不是把它当作
普通无头 RAW 直接交给传统串行入口。

### 3.3 分块输入与 `IqChunk` 契约

流式层不直接依赖某一种硬件，而是统一接收 `radio.stream.makeIqChunk` 生成的结构：

```text
channelId
sequenceNumber
sourceSampleStart       零基、包含
sourceSampleEnd         零基、末端不包含
timestampStartNs
centerFrequencyHz
sampleRateHz
iq
discontinuity
droppedSourceSamples
```

若上游没有硬件时间戳，`timestampStartNs` 由绝对样点号和采样率换算。每个块都会由
`validateIqChunk` 检查样点范围与 IQ 长度一致性。`discontinuity=true`、样点号跳变或
`droppedSourceSamples>0` 会使下游有状态滤波器、候选轨迹和 Epoch 按各自规则复位，避免
跨丢样边界继续沿用相位、滤波历史或协议状态。

### 3.4 文件回放模式

`radio.replay.fileLoopSource*` 以拉取方式产生默认 10 ms 的 `IqChunk`，并维护单调的全局
逻辑样点号。已实现三种模式：

| 模式 | 文件尾行为 | 用途 |
|---|---|---|
| `once` | 单次结束并进入冲洗/finalize | 确定性离线处理 |
| `continuous-test` | 下一遍直接接到全局时间轴后 | 用短样本构造更长的协议观察窗 |
| `epoch-repeat` | 插入静默，下一遍首块标记不连续 | 把每次回放作为独立 RF Epoch |

文件源是 pull-based：当前块处理完成后才读取下一块。处理速度不足时，逻辑回放会变慢，
但不会产生无界队列。真实 SDR 的推送式有界队列、溢出策略和硬件时间戳尚未实现。

## 4. 载频选择与单信道提取

### 4.1 已居中基带

当 `FreqList=[]` 且不盲扫时，传统路径认为 IQ 已经位于目标信道附近。四种 4FSK
制式由 `radio.processBaseband` 转换到 48 kS/s；TETRA 显式启用时保留复 IQ，并在自己的
窗口解码器中转换到 72 kS/s。

`common.resampleTo` 使用 MATLAB `resample` 做有理多相重采样。上、下采样整数由目标和
源采样率取整后约分得到；采样率相同则只整理为列向量。

### 4.2 传统 `FreqList` 和 PSD 盲扫

指定相对频偏 `fo` 时，`radio.processCandidate` 先执行：

```matlab
iqShifted = iq .* exp(-1i * 2*pi * fo * t);
```

随后将四种窄带 4FSK 候选重采样到 48 kS/s。TETRA 的传统 `FreqList` 路径也先做同样的
复数移频，但由 TETRA 自己完成 72 kS/s 转换和匹配滤波。

未知窄带载频时，`radio.psdBlindSearch`：

1. 用默认 4096 点双边 Welch PSD；
2. 在线性功率上以 4.8 kHz 窗口聚合能量，避免把同一 4FSK 信号的多条谱线当成多台
   电台；
3. 以谱噪声中位数加 15 dB 为默认门限；
4. 使用默认 5 kHz 的候选非极大值抑制间距；
5. 对每个保留候选分别移频和解调。

传统盲扫当前只默认覆盖 DMR、P25、dPMR 和 NXDN。TETRA 没有接入这条旧式 PSD 盲扫；
TETRA 的自动宽带发现只能通过后述 `radio.wideband` PFB 路径参与。

### 4.3 实时频谱点击选频

`radio_frontend` 的预览链把每个宽带块同时送给 `radio.scope`：

- 默认 FFT 长度 65536；
- 以 Hann 窗计算线性 PSD；
- 默认每 100 ms 发布一次结果；
- 平均谱指数系数为 0.25；
- 同时维护 Max Hold；
- 瀑布图最多 200 行、最多 4096 个显示频点，不保存宽带 IQ 历史。

用户点击后，`radio.scope.refineCarrier` 在点击点附近搜索。默认搜索半径为
`max(50 kHz, 2×所选信道带宽)`，先以所选带宽对线性功率做滑动平均，再在峰值附近用
“功率减局部噪声”的非负权重计算频率质心。精调结果作为已知载频 DDC 的频率偏移。

### 4.4 已知载频有状态 DDC

`radio.tuned.ddcInit/ddcFeed/ddcFlush` 把一个已知宽带载频转换为单信道复基带。默认值为：

| 参数 | 默认值 |
|---|---:|
| 输出采样率 | 120 kS/s |
| 双边通带带宽 | 40 kHz |
| 阻带起点 | 55 kHz |
| 通带纹波 | 0.1 dB |
| 阻带衰减 | 80 dB |
| 内部处理块 | 10 ms |
| 文件尾滤波器冲洗 | 10 ms |

底层使用 `dsp.DigitalDownConverter`，其功能顺序是 NCO 复数下变频、级联抗混叠滤波和
整数抽取。输入采样率除以 120 kS/s 必须是至少为 2 的整数；目标载频连同 55 kHz
阻带边界必须留在输入 Nyquist 范围内。

DDC 在块间保留 NCO 和滤波器状态。任意长度的上游块先进入余量缓冲，只以固定 10 ms
整数抽取块调用 System object。检测到不连续时清除余量、复位转换器并增加连续性代号。
当前转换计算显式使用复数 `double`，这是现有 MATLAB R2022b 环境下避免低幅度
`single` 异常衰减的已验证基线。

120 kS/s 同时给 48 kS/s 的 4FSK 分支和 72 kS/s 的 TETRA 分支保留了可重采样余量。
在交互前端中，连续 10 ms DDC 输出会先拼成默认 100 ms 基带微批，再送给活动检测与
协议窗口控制器。

### 4.5 宽带 WOLA/PFB 自动发现

`radio.wideband` 已经实现一条 MATLAB 正确性基线：

```text
宽带 IqChunk
  -> 2x oversampled WOLA/PFB
  -> 粗子带功率检测
  -> 子带内细 PSD 候选
  -> CandidateTracker
  -> 每条轨迹的残余 NCO + 低通
  -> 单信道 IqChunk
```

默认信道化参数：

| 参数 | 默认值 |
|---|---:|
| PFB 通道数 | 1024 |
| 过采样倍数 | 2 |
| hop | 512 个宽带样点 |
| 每通道原型滤波器抽头 | 8 |
| 原型总长度 | 8192 |
| 原型截止 | 0.60 个 bin |
| 分块 FFT 帧数 | 64 |

PFB 的 bin 间隔为 `Fs/1024`，子带输出采样率为 `Fs/512`，即 bin 间隔的两倍。
61.44 MS/s 输入时，bin 间隔为 60 kHz，子带采样率恰好为 120 kS/s。信道化器保留输入
余量，并记录原型滤波器群时延对应的宽带样点位置；不连续时清空状态。

候选检测首先计算每个粗子带的平均功率，默认开启门限为粗带噪声中位数加 10 dB；已有
轨迹使用加 6 dB 的较低保持门限。每个活动粗带内部再调用信道级 PSD 搜索：

- 细 FFT 默认 512；
- 细门限为局部噪声加 8 dB；
- 信道能量平滑 4.8 kHz；
- 最小候选间距 5 kHz；
- 2.5 kHz 内的跨粗带重复候选合并。

`CandidateTracker` 以 2.5 kHz 容差关联相邻批次，频率平滑系数为 0.25，连续出现 30 ms
后确认，消失后保持 350 ms。每条轨迹绑定一个粗 PFB bin；细提取器使用连续 NCO 消除
“平滑载频减粗 bin 中心”的残余频偏，再用 129 抽头 Hamming 窗低通，截止频率 18 kHz。
细提取不再次降采样，因此输出率仍为 PFB 子带率。

这条链已经能从文件或内存宽带 IQ 建立候选、提取信道并进入五制式竞速，但 61.44 MS/s
纯 MATLAB CPU 实现尚未达到硬实时。生产级 SDR Source、准入/背压和加速实现仍未完成。

## 5. 基带活动切分和协议观察窗

这一层不改变调制本身，但决定哪些 IQ 样点会交给物理层恢复器，因此属于完整数据流的一
部分。

### 5.1 活动检测与 Epoch

默认流式配置为：

| 参数 | 默认值 |
|---|---:|
| 检测微批 | 100 ms |
| 环形缓冲 | 8 s |
| pre-trigger | 0.5 s |
| 初始噪声底 | -60 dB |
| 开启门限 | 噪声底 + 10 dB |
| 关闭门限 | 噪声底 + 6 dB |
| 最短开启时间 | 50 ms |
| 关闭保持 | 300 ms |

活动检测器对每个微批计算 `mean(abs(iq)^2)`。非活动期用 0.05 的指数系数更新噪声底；
开启和关闭使用迟滞。达到开启条件时创建 RF Epoch，关闭保持到期、输入丢样或显式结束
时关闭 Epoch。环形缓冲保存 pre-trigger 和协议观察窗所需的有限历史。

### 5.2 五制式观察窗与目标采样率

`radio.stream.probeRegistry` 当前配置如下：

| 制式 | 初始观察窗 | 最大观察窗 | 物理层目标采样率 |
|---|---:|---:|---:|
| DMR | 0.30 s | 1.50 s | 48 kS/s |
| P25 | 0.10 s | 1.00 s | 48 kS/s |
| dPMR | 0.32 s | 1.50 s | 48 kS/s |
| NXDN | 0.16 s | 1.00 s | 48 kS/s |
| TETRA | 0.50 s | 6.00 s | 72 kS/s |

观察窗按 2 倍逐步扩展。`radio.stream.decodeProtocolWindow` 将环形缓冲中的复数
`single` 快照显式转为复数 `double`，然后按制式重采样。TETRA 直接进入
`tetra.decodeIqWindow`；其他制式通过注册表调用各自 `frontendFcn`。

协议竞速当前要调用 dibit 之后的校验结果来判断哪种制式成立，但那些证据规则不属于本
文范围。与物理层实现相关的事实是：同一 IQ 快照会分别按候选制式恢复符号/dibit，获胜
后也仍通过重叠整窗重算继续解码，并非五套已经完全状态化的因果流式解调器。

## 6. 四种 4FSK 的公共鉴频前端

DMR、P25 和 dPMR 调用 `common.fskFrontend`；NXDN 使用一套结构相近但频偏估计不同的
独立前端。公共处理的核心顺序如下。

### 6.1 残余频偏校正

若调用者给出 `Fo`，先执行一次复数移频。当前 DMR/P25/dPMR 协议适配器传入的 `Fo`
均为 0，因为载频搬移已经由外层候选/DDC 完成。

随后对当前完整 IQ 窗计算 Welch PSD，并把最大 PSD bin 作为前端残余频率 `cf`，再乘：

```text
exp(-j 2π cf n / Fs)
```

NXDN 不取单个最大 bin，而是在 `|f| <= 8 kHz` 内使用
`max(PSD - band内PSD中位数, 0)` 作为权重求功率质心；无有效权重时取 0。

### 6.2 通道低通

四种制式都使用 151 抽头 FIR。DMR/P25/dPMR 的公共前端通过 `fir1` 设计，NXDN 也使用
相同形式。当前均用 `filtfilt` 做前后向零相位滤波，所以这一段是整窗、非因果的离线实现，
不是可以直接逐样点部署的实时 FIR 状态机。

### 6.3 FM 相位差分鉴频

滤波后 IQ 记为 `x[n]`，鉴频器计算：

```text
deltaPhi[n] = angle(x[n+1] * conj(x[n]))
```

同时用相邻点中前一点的幅度构造活动掩码：

```text
threshold = median(amplitude) + 0.3 * (mean(amplitude) - median(amplitude))
```

活动样点足够时，以活动区 `deltaPhi` 的中位数作为残余直流/频偏；否则使用全部样点中位
数。最后按标称最外层频偏归一化：

```text
y[n] = (deltaPhi[n] - center) * 3 / (2*pi*DevNominal/Fs)
```

因此理想的四个 4FSK 层级统一落在 `-3, -1, +1, +3` 附近。鉴频使输出长度比输入复 IQ
少一个样点。

### 6.4 公共物理参数

| 制式 | 符号率 | 目标采样率 | 每符号样点 | 低通截止 | `DevNominal` |
|---|---:|---:|---:|---:|---:|
| DMR | 4800 sym/s | 48 kS/s | 10 | 9.5 kHz | 1944 Hz |
| P25 Phase 1 | 4800 sym/s | 48 kS/s | 10 | 9.5 kHz | 1944 Hz |
| dPMR | 2400 sym/s | 48 kS/s | 20 | 3.5 kHz | 1050 Hz |
| NXDN96 | 4800 sym/s | 48 kS/s | 10 | 6.5 kHz | 2400 Hz |

DMR 和 P25 在注册表中使用相同 `frontendKey='c4fm_4fsk'`，且当前前端参数相同；两者在
同一次统一扫描中会复用一份鉴频输出。dPMR 和 NXDN 因带宽、频偏估计或标称频偏不同，
各自生成独立输出。

### 6.5 四电平到 dibit 的统一映射

四种 4FSK 实现采用相同的空口位对映射：

| 归一化电平 | bit pair | 数值 dibit（MSB-first） |
|---:|:---:|---:|
| `-3` | `11` | 3 |
| `-1` | `10` | 2 |
| `+1` | `00` | 0 |
| `+3` | `01` | 1 |

各制式在同步、定时和校准方法上不同，不能仅对整段鉴频波形统一按固定门限切片。

## 7. DMR：从鉴频波形到 dibit

### 7.1 同步搜索

`dmr.findSyncPositions` 内置四种 24 符号模板：

- `BS_VOICE`；
- `MS_VOICE`；
- `DATA_BS`；
- `DATA_MS`。

每个模板按 10 samples/symbol 重复成波形，与鉴频输出做归一化互相关。语音模板门限为
0.68，数据模板门限为 0.55，峰最小间距为 800 个 48 kS/s 样点。代码同时搜索正相关
峰和负相关峰，因此同步候选携带 `polarity=+1/-1`。

### 7.2 数据突发的定时和幅度校准

`dmr.recoverBurst` 围绕同步中心恢复 132 个符号。它在 `-8...+8` 个样点之间测试 65 个
相位，即 0.25 样点间隔：

1. 按候选极性翻转鉴频波形；
2. 用线性插值在每隔 10 样点的位置取 132 个符号；
3. 取其中第 55～78 个符号与 24 符号同步模板做带截距的一次线性拟合；
4. 用拟合系数把整段观测幅度映射到标称同步层级；
5. 计算全部校准符号到 `[-3,-1,+1,+3]` 最近层级的均方残差；
6. 保留残差最小的相位和校准符号序列。

### 7.3 语音突发序列

语音候选先由 `dmr.lockVoicePhase` 用同样的 0.25 样点网格锁定一个相位。随后
`recoverSteppedBurstBits` 以 2880 个 48 kS/s 样点，即 60 ms，为固定步长向后恢复最多
6 个 132 符号突发。相位和极性沿这一组突发保持不变。

### 7.4 硬判决

`dmr.adaptiveSliceBits` 不直接使用固定的 `±2/0` 门限，而根据当前 132 符号段的 90% 和
10% 分位数构造：

```text
center = (p90 + p10)/2
upperMiddle = (p90 + center)/2
lowerMiddle = (p10 + center)/2
```

再按四个区间输出 `01 / 00 / 10 / 11`。一个突发得到 132 个 dibit，也就是 264 个
MSB-first hard bit。到 `adaptiveSliceBits` 的输出即到达本文边界；后续
`dmr.decodeBurst` 或语音嵌入信令收集不在本文展开。

## 8. P25 Phase 1：从鉴频波形到 dibit

### 8.1 帧同步

`p25.findFrameSync` 使用 48 bit、24 符号的 P25 Frame Sync。模板按 10 samples/symbol
展开后与鉴频波形做归一化互相关，同时搜索正、负极性：

- 默认 NCC 门限 0.62；
- 峰最小间距 120 个符号，即 1200 个 48 kS/s 样点；
- 候选记录帧同步起点、极性和相关分数。

### 8.2 符号恢复和校准

`p25.recoverSymbolsFromFs` 从 Frame Sync 起点向后恢复所需长度：最短 FS+NID 路径为
57 个符号，需要完整 LDU 时为 864 个符号。默认定时相位搜索为 `-4...+4` 样点、共
33 点，同样是 0.25 样点间隔。

每个候选相位执行：

1. 应用同步候选极性；
2. 线性插值得到符号；
3. 用前 24 个观测符号到标称 Frame Sync 的带截距线性拟合校准整帧；
4. 评价“同步段拟合残差 + 0.05×全帧最近四电平残差”；
5. 保留总代价最小的校准符号序列。

### 8.3 硬判决

`p25.sliceSymbolsToBits` 将每个校准符号直接判到最近的 `-3,-1,+1,+3`，再按
`11,10,00,01` 展开为 MSB-first bit pair。57 符号窗口得到 114 bit，864 符号窗口得到
1728 bit。该函数输出即为本文边界；NID 提取和后续 BCH/帧类型处理不在本文展开。

## 9. dPMR：从鉴频波形到 dibit

### 9.1 同步类型和相关搜索

`dpmr.findSync` 支持 FS1、FS2、FS3、FS4 及其反向模板。当前解码入口主要用：

- FS1：头部帧；
- FS2：语音帧。

FS1 为 24 dibit，FS2 为 12 dibit。同步模板先按映射
`[0,1,2,3] -> [+1,+3,-1,-3]` 转为电平，再减去模板均值并按 20 samples/symbol 展开。
相关计算也对当前滑窗鉴频波形去局部均值。

默认条件：

- NCC 门限 0.82；
- 峰最小间距 1200 个样点；
- 初步同步误差相位在 `-12...+12` 样点间取 13 点；
- 同步符号允许错误数为 0；
- 3 个符号范围内的重复候选按符号错误、残差和 NCC 排序去重。

### 9.2 384 dibit 帧恢复

`dpmr.recoverFrameSymbolCandidates` 对 FS1 和 FS2 路径都恢复 384 个 dibit。默认：

- 每符号样点固定为 20；配置虽允许搜索，当前 `spsSearchMin=max=20`；
- 相位从 `-12...+12` 取 25 点，即 1 样点间隔；
- 每个符号只取中心插值值，`sampleWindows=0`；
- FS1 最多保留残差最小的 16 个候选，FS2 最多保留 8 个。

对每组定时参数，用开头同步段做带截距线性拟合，把整帧映射到标称电平，然后逐符号
选择最近的 `dpmr.constants().dibitLevels=[+1,+3,-1,-3]`。候选代价由同步段残差加
0.03 倍全帧四电平残差构成，同时记录 90% 判决误差和模糊符号数。

若候选来自反向同步模板，判决后的数值 dibit 再与二进制 `10` 异或，即执行
`0<->2`、`1<->3` 的极性恢复。

### 9.3 当前边界输出

这里的 `candidate.symbols` 名称容易误解：它已经不是模拟符号幅度，而是 384 个
`0,1,2,3` 数值 dibit。后续 `dpmr.symbolsToBits` 才把它们展开成 bit pair，并进入 CCH、
颜色码等解析；因此本文边界位于 `recoverFrameSymbolCandidates` 的候选输出。

## 10. NXDN96：从鉴频波形到 dibit

### 10.1 独立前端

`nxdn.frontend` 可以直接接受任意输入采样率，先转换到 48 kS/s，再执行第 6 节所述的
独立频率质心估计、151 抽头 6.5 kHz 低通、`filtfilt`、相位差分鉴频和残余中位数去除。
输出仍按 2400 Hz 标称最外层频偏归一化到四个标称层级。

前端诊断同时记录输入/输出样点数、粗频偏、鉴频残余频偏和活动样点比例。统一扫描器
通常已经先把窗口转换到 48 kS/s，因此前端中的重采样会被自动跳过；独立入口
`nxdn.decodeIq` 则可以直接处理例如 78.125 kS/s 的居中录音。

### 10.2 FSW 搜索

NXDN96 一帧为 192 dibit，当前 FSW 模板为 10 个电平符号。`nxdn.findFrameSync`：

1. 分别检查 10 个整数采样相位；
2. 对每个相位形成符号间隔序列；
3. 用 10 符号 FSW 做 valid NCC；
4. 对相关绝对值使用默认 0.70 门限；
5. 相关符号的正负号给出候选极性；
6. 以 900 个 48 kS/s 样点为最小间距，优先保留分数高的候选。

与 DMR/P25 不同，这一步只检查整数样点相位。

### 10.3 192 dibit 恢复和校准

`nxdn.recoverFrameSymbols` 在同步候选前后 `-4...+4` 个整数样点中细化起点。每个候选
直接每隔 10 点取完整 192 符号，并用模型：

```text
observedFSW = scale * nominalFSW + center
```

拟合比例和偏置。若比例绝对值小于 0.05 则拒绝；否则用
`(observed-center)/scale` 归一化整帧。因为比例可以为负，这一步同时消除了同步极性。
最终保留归一化 FSW 相关分数最高的起点。

### 10.4 硬判决

`nxdn.sliceDibits` 计算每个归一化符号到 `[-3,-1,+1,+3]` 的距离，并同时输出：

- `dibits`：`uint8` 的 `0...3` 空口 dibit；
- `levels`：对应的最近标称电平；
- `error`：到最近电平的绝对距离。

每个有效帧得到 192 个物理 dibit。此时仍包含 10 个 FSW dibit，后续 182 个 dibit 尚未
执行 PN9 解扰。`nxdn.decodeLich`、`nxdn.descrambleDibits` 及任何信道块译码均位于本文
边界之后。

## 11. TETRA：从复数 IQ 到 dibit

TETRA 不经过 FM 鉴频实数波形，而是保留复数 IQ，使用相邻复符号的差分相位恢复
pi/4-DQPSK dibit。核心入口为 `tetra.decodeIqWindow`。

### 11.1 采样率和活动窗口

TETRA 参数为：

| 参数 | 当前值 |
|---|---:|
| 符号率 | 18 ksym/s |
| 前端采样率 | 72 kS/s |
| 每符号样点 | 4 |
| RRC 滚降系数 | 0.35 |
| RRC 配置跨度 | 10 symbols，当前实现生成 81 taps |

IQ 先减去复均值，再用 `common.resampleTo` 转到 72 kS/s。核心
`tetra.decodeIqWindow` 假定调用者已经选好了待解窗口；它本身不再做活动检测。

直接兼容入口 `tetra.decode` 和调试入口会在核心解码前调用 `tetra.activeWindow`。该函数
以 1 ms 为单位计算功率包络：

```text
floor = 第20百分位功率
top   = 第95百分位功率
threshold = max(floor + 8 dB, floor + 0.35*(top-floor))
```

若有效活动窗不足或几乎全程活动，则使用受限预览窗口；否则选择综合平均功率和持续长度
最高的活动段并加前后保护。普通调试配置前后各保护 20 ms、窗口最多 350 ms；
`tetra.decode` 的扫描兼容配置把后保护扩展为 2.2 s、窗口上限扩展为 2.5 s。

统一串行扫描实际使用的 `tetra.scanIqWindows` 可以检测多个活动段：默认前保护 50 ms、
后保护 250 ms，150 ms 内的活动段合并；长段切为最长 6 s、相邻重叠 1.25 s 的窗口。
流式协议竞速则已经由 RF Epoch/环形缓冲选好快照，直接调用 `decodeIqWindow`。这些规则
都只决定送入物理层的 IQ 范围。

### 11.2 粗频偏校正

`tetra.coarseFrequencyOffset` 对活动 IQ 做 Welch PSD，在 `±14 kHz` 内保留高于全谱中位
数 4 dB 的点：

- 至少 3 个点时，按线性 PSD 求频率质心；
- 否则使用 PSD 最大峰；
- 结果限制在 `±14 kHz`。

随后把该频偏用复数 NCO 搬到零频。

### 11.3 RRC 匹配滤波

`tetra.rrcTaps` 生成单位能量 Root Raised Cosine 冲激响应。当前代码的时间轴为
`-span*sps ... +span*sps`，所以 `span=10、sps=4` 时实际为 81 抽头。匹配滤波通过
`conv(...,'same')` 对整个窗口执行，仍是离线整窗处理。

### 11.4 符号定时搜索

`tetra.timingSearch` 在一个符号的 4 个样点内搜索：

```text
0, 0.25, 0.50, ..., 3.75 samples
```

每个候选相位用线性插值得到复符号 `s[k]`，并计算：

```text
dphi[k] = angle(s[k+1] * conj(s[k]))
amplitude[k] = min(abs(s[k+1]), abs(s[k]))
```

有效转移门限为幅度中位数加上 20% 的“90% 分位数减中位数”。如果有效转移少于
`max(16, 总数的10%)`，则退回使用全部转移。

对有效差分相位，再在 `-pi/4...+pi/4` 内以 1 度步长搜索公共相位偏置，使其到四个理想
中心的中位绝对误差最小：

```text
-3*pi/4, -pi/4, +pi/4, +3*pi/4
```

所有定时相位中，差分相位中位误差最小者获胜。

### 11.5 二次残余频偏校正

第一次定时搜索得到的公共差分相位偏置被换算为：

```text
residualHz = diffPhaseOffsetRad * 18000 / (2*pi)
```

当其绝对值位于 3 Hz 到 2500 Hz 之间时，代码再次对原粗校正 IQ 做复数频移、RRC 匹配
滤波和完整定时搜索。超出该范围或过小时保留第一次结果。

### 11.6 pi/4-DQPSK 判决与歧义消除

`tetra.pi4dqpskDecision` 的标准映射为：

| 差分相位中心 | bit pair | 数值 dibit |
|---:|:---:|---:|
| `-3*pi/4` | `11` | 3 |
| `-pi/4` | `10` | 2 |
| `+pi/4` | `00` | 0 |
| `+3*pi/4` | `01` | 1 |

为了处理 IQ 共轭和 bit 顺序不确定性，`decodeIqWindow` 会尝试：

1. `standard`；
2. `conjugate`：差分相位取反；
3. `swap_bits`：每个 dibit 的两位交换；
4. `conjugate_swap`：同时取反和交换。

每个变体都重新选择最佳公共相位偏置并搜索已知训练序列。选择分数为：

```text
training.score + 1000*goodTrainingCount + 100*candidateTrainingCount
```

这一步只用训练序列解决物理层相位/位序歧义；从 `tetra.inferDmoBursts` 开始的突发和
链路层处理不属于本文。

### 11.7 TETRA 边界输出

判决结构同时包含：

- `bitPairs`：每行一个二比特；
- `bits`：串行 hard bit；
- `dibits`：`0...3` 数值；
- `diffPhaseRaw` 和 `diffPhaseCorrected`；
- `errorRad`；
- `validTransitionMask`；
- `transitionAmplitude`；
- `dibitReliability`、`bitReliability` 和 `bitValidMask`。

可靠度由相位误差分数和以幅度 90% 分位数归一化的幅度分数相乘；无效转移可靠度置零。
当前后端仍主要使用 hard bit 和有效掩码，并未实现完整的 soft-decision 链路译码。

由于采用差分判决，`N` 个复符号只产生 `N-1` 个 dibit。

## 12. 五制式 dibit 边界对照

当前工程已经恢复出五制式 dibit，但内部表示尚未统一：

| 制式 | 边界函数/字段 | 当前表示 | 典型长度 | 下一步（本文不展开） |
|---|---|---|---:|---|
| DMR | `dmr.adaptiveSliceBits` | 一维 `0/1`，每两个 bit 一个 dibit | 132 dibit/突发 | `dmr.decodeBurst` 或嵌入信令收集 |
| P25 | `p25.sliceSymbolsToBits` | 一维 `0/1`，每两个 bit 一个 dibit | 57 或 864 dibit | NID/HDU/LDU 处理 |
| dPMR | `recoverFrameSymbolCandidates(...).symbols` | `double` 的 `0...3` 数值 dibit | 384 dibit/帧 | `symbolsToBits`、CCH/CC |
| NXDN | `nxdn.sliceDibits` 的 `dibits` | `uint8` 的 `0...3` 数值 dibit | 192 dibit/帧 | PN9 解扰、LICH/信道块 |
| TETRA | `tetra.pi4dqpskDecision` | 同时有 bit pair、串行 bit、`0...3` dibit、可靠度 | 符号数减 1 | DMO burst/BKN/链路层 |

因此，“物理层已经实现”不等于“已有一个统一可调用的 raw-dibit API”。目前统一公共入口
`radio.scanFile/radio.scanIq` 的对外输出仍是 PDU；各制式的 dibit 位于协议包内部，并被
后端直接消费。若下一阶段需要保存、对比或回放原始 dibit，建议新增统一结构，例如：

```text
RawDibitFrame {
    protocol
    sourceSampleStart
    sourceSampleRateHz
    symbolRateHz
    dibits              % uint8 0..3
    bitPairs            % optional logical Nx2
    decisionError
    reliability
    validMask
    syncType
    polarityOrVariant
    timing
    frequencyOffsetHz
}
```

这属于建议接口，不是当前已经存在的实现。

## 13. 状态连续性与“实时”含义

当前链路中真正跨块保存状态的部分包括：

- 文件回放的绝对样点号和循环状态；
- 实时频谱的 FFT 余量、平均谱、Max Hold 和瀑布环形缓冲；
- 已知载频 DDC 的 NCO、CIC/FIR 和输入余量；
- WOLA/PFB 的输入历史、帧位置和连续性代号；
- 宽带候选轨迹、细 DDC NCO 和 129 抽头 FIR 状态；
- 活动检测、Epoch、环形 IQ 缓冲和调度状态。

五种协议的物理层本身目前主要是“冻结 IQ 窗口后整窗计算”：

- DMR/P25/dPMR/NXDN 使用整窗 Welch、`filtfilt`、同步相关和相位网格搜索；
- TETRA 使用整窗频偏估计、`conv(...,'same')`、全窗口定时搜索和训练序列评分；
- 获胜制式的持续解码使用有限重叠窗口反复调用现有整窗解码器，并用绝对样点键去重。

因此当前所称“实时前端”主要是流式输入、连续 DDC/PFB、活动控制和异步调度已经建立；
协议物理层尚未全部改造成保持重采样相位、鉴频前一 IQ、定时环、相关尾部和帧状态的
因果增量实现。

## 14. 当前能力与限制总结

### 14.1 已经实现

1. RAW/WAV 整文件读取、BVSP 元数据读取和 10 ms 分块回放；
2. 统一绝对时间轴 `IqChunk` 和不连续传播；
3. 传统频偏列表和窄带 PSD 候选搜索；
4. 实时 Average/Max Hold/瀑布图、点击载频及质心精调；
5. 单载频 120 kS/s 有状态 DDC；
6. 1024 通道、2 倍过采样 WOLA/PFB 正确性实现；
7. 粗/细候选检测、频率轨迹和每候选细 DDC；
8. 活动检测、RF Epoch、环形缓冲和五制式观察窗；
9. DMR、P25、dPMR、NXDN96 的 4FSK 硬 dibit 恢复；
10. TETRA 的 pi/4-DQPSK hard dibit、有效掩码和可靠度恢复。

### 14.2 仍然受限

1. 没有生产级真实 SDR Source、硬件时间戳、有界推送队列和溢出策略；
2. 61.44 MS/s WOLA/PFB 的 MATLAB CPU 版本是正确性基线，不承诺 1× 实时；
3. `radio_frontend` 一次只允许用户选择一个载频；
4. 已知载频 PDU 回映射到宽带绝对样点尚未补偿 DDC 滤波群时延；
5. 四种 FSK 和 TETRA 解调器仍含整窗、非因果处理；
6. DMR/P25 使用固定 10 samples/symbol，NXDN 只做整数相位细化，dPMR 默认也固定
   20 samples/symbol；尚无连续符号钟漂移跟踪环；
7. 硬判决接口未统一，除 TETRA 外没有统一可靠度/soft dibit 输出；
8. 传统 PSD 盲扫不包含 TETRA；只有显式 TETRA、已知载频竞速或宽带 PFB 路径会尝试
   TETRA；
9. 当前 BVSP 解析只覆盖已经观察到的 112 字节 USRP/CI16 格式；
10. 本文之后的五制式后端能力并不完整，尤其不能由“dibit 已恢复”推断语音或所有控制
    信道均已实现。

当前 MATLAB 实现还依赖相应工具箱能力：有理重采样、`fir1` 和 `filtfilt` 需要相关信号
处理函数；已知载频链使用 `dsp.DigitalDownConverter`；五进程并行竞速需要 Parallel
Computing Toolbox。并行池不可用时部分离线路径可以记录原因并回退串行，但缺失核心 DSP
函数时前端会明确报错。

### 14.3 现有验证入口

与本文范围直接相关的回归入口包括：

- `tests.runAll`：统一入口、PSD 候选、五制式样本和各阶段回归总入口；
- `tests.runNxdn96`：FSW、dibit 映射、物理帧和 NXDN 实录；
- `tests.runTunedTransition`：已知载频 NCO、抽取、带外抑制和参数拒绝；
- `tests.runStreamingPhase10`：WOLA/PFB 分块等价性、候选、跟踪、细提取和宽带 DMR
  全链；
- `tests.runRealtimeFrontendPhase1...4`：循环源、频谱/精调、DDC 微批和隐藏 UI 全链；
- `tests.runRealtimeFrontendBvspAcceptance`：外部真实 BVSP 的可选串行/五进程验收。

这些测试既包含纯合成向量，也会在外部样本存在时运行 DMR、P25、dPMR、NXDN 和 TETRA
实录路径。BVSP 实录验收没有放进每次 `runAll`，因为它依赖工作区外的大文件和本机并行
环境。

## 15. 关键代码索引

### 输入与公共 DSP

- `+common/readRawIq.m`
- `+common/detectSampleRate.m`
- `+common/resampleTo.m`
- `+common/welchPsd.m`
- `+common/fskFrontend.m`
- `+radio/+stream/makeIqChunk.m`
- `+radio/+stream/fileSourceInit.m`
- `+radio/+replay/fileLoopSourceInit.m`

### 载频与信道提取

- `+radio/psdBlindSearch.m`
- `+radio/processCandidate.m`
- `+radio/+scope/spectrumFeed.m`
- `+radio/+scope/refineCarrier.m`
- `+radio/+tuned/ddcInit.m`
- `+radio/+tuned/ddcFeed.m`
- `+radio/+wideband/channelizerFeed.m`
- `+radio/+wideband/detectCandidates.m`
- `+radio/+wideband/candidateTrackerFeed.m`
- `+radio/+wideband/channelExtractorFeed.m`

### 流式切窗与协议分发

- `+radio/+stream/activityDetectorFeed.m`
- `+radio/+stream/probeRegistry.m`
- `+radio/+stream/decodeProtocolWindow.m`
- `+radio/+tuned/streamScannerQueueBaseband.m`

### 五制式物理层边界

- DMR：`+dmr/frontend.m`、`findSyncPositions.m`、`recoverBurst.m`、
  `lockVoicePhase.m`、`recoverSteppedBurstBits.m`、`adaptiveSliceBits.m`
- P25：`+p25/frontend.m`、`findFrameSync.m`、`recoverSymbolsFromFs.m`、
  `sliceSymbolsToBits.m`
- dPMR：`+dpmr/frontend.m`、`findSync.m`、`recoverFrameSymbolCandidates.m`、
  `dibitsToLevels.m`
- NXDN：`+nxdn/frontend.m`、`findFrameSync.m`、`recoverFrameSymbols.m`、
  `sliceDibits.m`
- TETRA：`+tetra/decodeIqWindow.m`、`coarseFrequencyOffset.m`、`rrcTaps.m`、
  `timingSearch.m`、`pi4dqpskDecision.m`

## 16. 一句话结论

当前工程已经打通“多种 IQ 输入 → 载频选择/信道提取 → 单信道复基带 → 频偏与采样率
归一化 → 符号同步和定时 → 五制式空口 hard dibit”的完整 MATLAB 正确性链路；但生产级
SDR 接入、硬实时加速、因果增量协议解调和统一 raw-dibit 公共接口仍是后续工作。
