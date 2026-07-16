# 信号输入到原始 Dibit 恢复实现说明

> 文档基线：2026-07-16 当前工作区代码
>
> 适用工程：MATLAB Multi-Protocol Radio Decoder
>
> 覆盖制式：DMR、P25 Phase 1、dPMR、NXDN96、TETRA DMO

## 1. 文档目的与边界

本文说明当前工程从复数 IQ 信号进入系统，到恢复出空口硬判决 dibit 为止，已经实现了
哪些模块、各模块怎样连接、关键参数是什么，以及当前实现仍有哪些限制。

本文覆盖：

1. BVSP、无头交错 IQ、双通道 IQ WAV 和内存 IQ 的输入；
2. 整文件、分块回放、异步共享环和统一 `IqChunk` 时间轴；
3. `radio_live_frontend` 的 Preview、频谱点击和 Run 起点，以及传统已居中/指定频偏与宽带自动发现；
4. DDC、抗混叠滤波、抽取、PFB 信道化、细频偏校正和协议目标采样率转换；
5. 活动窗口、RF Epoch、协议 Probe、Winner Catch-up 与锁定后的因果增量链；
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

当前工程并非只有一条输入链。不同入口最终都把一个已选出的单信道复基带交给五种制式
各自的物理层恢复器。本文重点说明当前主入口 `radio_live_frontend.m` 的默认异步链路；
传统离线入口和自动 WOLA/PFB 链保留在后续章节作为对照。

```text
BVSP / RAW IQ / stereo IQ WAV / memory IQ / future SDR IqChunk
                              |
             +----------------+----------------+
             |                |                |
             v                v                v
       已居中或给定频偏    人工频谱点击选频      宽带自动发现
       serial / parallel  radio_live_frontend  wideband WOLA/PFB
             |                |                |
             |          最多五载频融合 DDC      粗子带 + 细频点跟踪
             |                |                +-> 细 DDC/低通
             |                |                |
             +----------------+----------------+
                              |
                 每载频单信道复数基带 IqChunk
                    典型为 120 或 125 kS/s
                              |
                 活动检测 / Epoch / 8 s 环形缓冲
                              |
             +----------------+----------------+
             |                                 |
             v                                 v
       识别期：整窗并行 Probe             锁定期：原生增量解调
       逐步扩展 0.1~6.0 s                  只消费新到达 IQ
             |                                 |
      48 kS/s 四种 4FSK / 72 kS/s TETRA，完成各自前端
             |                                 |
             +----------------+----------------+
                              |
              同步 -> 定时/校准 -> 调制硬判决
                              |
                    空口 hard dibit / bit pair
                              |
                 ===== 本文说明到此为止 =====
                              |
              解扰、FEC、帧/PDU证据、会话和健康判断
```

### 2.1 四种公共执行方式

| 执行方式 | 主要入口 | 输入假设 | 载频处理 | 到协议前的典型采样率 |
|---|---|---|---|---:|
| 传统串行离线 | `radio.scanFile`，`ExecutionMode='serial'` | 整文件，可已居中、给出 `FreqList` 或做传统 PSD 盲扫 | 直接复数混频；必要时多相重采样 | 4FSK 为 48 kS/s；TETRA 自行转 72 kS/s |
| 已居中并行识别 | `ExecutionMode='parallel'` | 单个已居中基带信道 | 不再发现载频，按 Epoch 切窗 | 保持源速率，进入每个制式时转 48/72 kS/s |
| 已知载频过渡链/交互前端 | `ExecutionMode='tuned-parallel'` 或 `radio_live_frontend` | 宽带 IQ 中给出 1～5 个载频 | 融合有状态数字下变频和抗混叠抽取 | 先到 120/125 kS/s，再转 48/72 kS/s |
| 宽带自动发现 | `ExecutionMode='wideband'` | 宽带 RAW/WAV 或内存 IQ | 2 倍过采样 WOLA/PFB、候选跟踪、细 DDC | 61.44 MS/s 输入时子带为 120 kS/s，再转 48/72 kS/s |

交互式 `radio_live_frontend` 与自动 `radio.wideband` 是两条不同链：前者由用户在实时
绘制的频谱上选择最多五个载频，后者由 PFB 和候选检测器自动维护多个频率轨迹。当前
交互前端不会在后台同时运行 PFB 自动发现。旧入口 `radio_frontend` 仍保留，但不是本文
“点击后实时多载频解码”主链。

为兼容旧脚本，`radio.scanFile` 在收到 `ExecutionMode='parallel'`、一个非零
`FreqList` 且未开启盲扫时，会自动改走已知载频 DDC 过渡链。真正“已经居中的并行
基带”入口应使用空 `FreqList`。

### 2.2 `radio_live_frontend` 从点击到 dibit 的完整调用链

默认配置满足 `UseAsyncFrontend=true`、`UseFusedDdc=true` 且
`ParallelMode='parallel'`，所以执行的是下列异步主链：

```text
Preview 1x
  radio_live_frontend/startPreviewPublic
    -> ensureDecodeRuntimePrepared
       -> 建立 5 个协议 worker + 1 个预留 DDC process worker
       -> 在所有 worker 预热整窗和增量协议入口
    -> startAsyncSource
       -> fileProducerWorker(backgroundPool，20 ms/块，1×节拍)
          +-> sharedIqRingWriteTransport(CI16，共享环，默认约 2 s)
          +-> spectrumActorWorker(backgroundPool，best effort)

点击频谱
  onSpectrumClick
    -> addFrequencyPublic
       -> radio.scope.refineCarrier
       -> state.selections(upsert，最多 5 路)
       -> 仅保存频点；此时尚未启动 DDC 或协议解码

Run decode
  runPublic
    -> resolveInputConfig
    -> startScannerBuild
       +-> sharedIqRingSnapshot                 记录当前实时边沿
       +-> startAsyncDdc
       |  -> ddcActorRetarget                   写入全部选中频偏
       |  -> ddcActorAttachRing(nextSequence)   从下一块开始，无预览倒带
       +-> multiStreamScannerInit(ExternalBaseband=true)

后续每个宽带块
  ddcActorWorker
    -> sharedIqRingRead
    -> radio.tuned.multiDdcFeed
       -> 矩阵 NCO 混频
       -> dsp.DigitalDownConverter 抗混叠 + 整数抽取
       -> 每载频一个 120/125 kS/s IqChunk
    -> multiStreamScannerFeedBasebands
       -> streamScannerQueueBaseband            拼成 100 ms 协调器微批
       -> raceCoordinatorFeed
          -> ringBufferPush + activityDetectorFeed
          -> protocolCandidateGate              保守区分 4FSK/TETRA
          -> parallelProbeRaceStart             整窗五制式竞速
          -> executeProbeTaskPacked
          -> runProtocolProbe
          -> decodeProtocolWindow
             -> 48/72 kS/s -> 同步/定时/校准 -> hard dibit
             -> FEC/PDU 强证据用于确定制式
          -> winnerCatchup
          -> lockedDecoderStart / persistent worker
             -> incrementalDecoderFeed
             -> <protocol>.streamDecodeChunk
             -> 因果重采样/滤波 -> 同步/定时 -> hard dibit
```

这里有三条需要特别注意的代码语义：

1. 点击执行的是 `onSpectrumClick -> addFrequencyPublic`，只更新 `state.selections` 并启用
   `Run decode` 按钮；真正的解码起点是按下 `Run decode` 时
   `sharedIqRingSnapshot().nextSequence` 指向的下一块。即使共享环仍保存点击前约 2 s IQ，
   默认也不会回读这些旧槽位。
2. UI 中 `6.25/12.5/25 kHz` 的 `BW` 当前只传给 `refineCarrier`，决定频谱平滑宽度和
   质心区域；它没有写入 `TunedConfig`，因此不会改变后续固定 40 kHz DDC 通带，也不会
   限定候选协议。
3. 频谱是 best-effort 消费者，队列满时允许丢弃旧 PSD 块并给下一块加不连续标志；解码
   共享环不允许静默丢块。DDC 读指针落后超过环容量时，`sharedIqRingRead` 返回 `overrun`，
   DDC Actor 报错并停止该解码链。

### 2.3 识别期与锁定期为何是两套物理层执行方式

当前代码有意保留两种执行方式，它们最终调用相同或等价的调制判决函数，但前端状态模型
不同：

| 项目 | 制式识别/赢家追赶 | 锁定后的持续解码 |
|---|---|---|
| 入口 | `decodeProtocolWindow`、`winnerCatchup` | `incrementalDecoderFeed`、各制式 `streamDecodeChunk` |
| 输入 | 环形缓冲冻结快照 | 尚未消费的新 `IqChunk` |
| 重采样 | `common.resampleTo`，每次整窗执行 | 有状态多相转换器，跨块保存相位/历史 |
| 滤波 | 4FSK 使用 `filtfilt`；TETRA 使用整窗卷积 | 因果 `filter`，保留 FIR、上一 IQ、NCO/DC 状态 |
| 同步搜索 | 对当前观察窗重新搜索 | 只搜索已经完整到达、尚未处理的候选范围 |
| 用途 | 以强 FEC/PDU 证据确定赢家 | 持续恢复后续 dibit/PDU 并监测健康度 |

因此“首次看到 dibit”通常发生在并行 Probe 内；“不重复消费旧样点地持续恢复 dibit”发生
在 `CATCHING_UP -> LOCKED` 之后。公共接口当前只上报 PDU，raw dibit 是协议解码器内部
临时边界，并没有作为独立事件从 worker 返回。

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

BVSP 支持集中在 `radio.tuned`、`radio.replay`、`radio_frontend` 和
`radio_live_frontend`。传统
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

`fileLoopSourceRead` 本身是 pull-based。传统同步入口在当前块处理完成后才读取下一块；
`radio_live_frontend` 则由 `fileProducerWorker` 在 `backgroundPool` 中按 1× 时钟主动拉取，
默认生成 20 ms 块，最多一次追赶 16 块。它把同一块编码成带独立比例因子的 CI16 传输，
一份写入默认约 2 s 的文件映射共享 IQ 环，另一份直接送给频谱 Actor。共享环读出后恢复
为复数 `single`，融合 DDC 计算前再转成 `double`。

这仍然是文件回放而非真实 SDR：生产级硬件时间戳、设备推送队列和射频设备溢出策略尚未
接入。实时前端已经有界：PSD 队列可丢显示块，解码环溢出和非异步后备队列超限则明确
取消解码，而不是形成无界积压。

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

`radio_live_frontend` 的默认预览链由 `fileProducerWorker` 直接把每个宽带块送给后台
`spectrumActorWorker`；UI 定时器只轮询最新快照，不转发宽带 IQ。`radio.scope` 当前：

- 默认 FFT 长度 65536；
- 以 Hann 窗计算线性 PSD；
- 默认每 100 ms 发布一次结果；
- 平均谱指数系数为 0.25；
- 同时维护 Max Hold；
- 瀑布图最多 200 行、最多 4096 个显示频点，不保存宽带 IQ 历史。

为限制宽带 CPU，`spectrumFeed` 每次发布只对最新 65536 个样点执行一次 FFT，不再变换
发布周期内的每个非重叠帧。默认 PSD 队列上限为 12 块；队列满时只牺牲显示连续性，
不会删除共享解码环中的 IQ。

`onSpectrumClick` 把坐标轴 MHz 值恢复成绝对 Hz，随后调用
`addFrequencyPublic(...,'Refine',true)`。`radio.scope.refineCarrier` 在点击点附近搜索。
默认搜索半径为
`max(50 kHz, 2×所选信道带宽)`，先以所选带宽对线性功率做滑动平均，再在峰值附近用
“功率减局部噪声”的非负权重计算频率质心。精调结果减去捕获中心频率得到 DDC 偏移。
距已有选择不超过 `max(500 Hz, BW/10)` 时更新该选择，否则按频率追加；默认最多五路。
解码运行期间禁止改变选择，`Clear carriers` 会拆除解码器，但频谱回放继续且不会倒带。

### 4.4 已知载频有状态 DDC

单路兼容链使用 `radio.tuned.ddcInit/ddcFeed/ddcFlush`；当前实时多载频默认使用
`multiDdcInit/multiDdcFeed/multiDdcFlush`，把多个选中载频合并成一次矩阵混频和一次矩阵
`dsp.DigitalDownConverter` 调用。公共配置为：

| 参数 | 默认值 |
|---|---:|
| 首选输出采样率 | 120 kS/s；不能整除输入时自动选择兼容率 |
| 双边通带带宽 | 40 kHz |
| 阻带起点 | 55 kHz |
| 通带纹波 | 0.1 dB |
| 阻带衰减 | 80 dB |
| 内部处理块 | 10 ms |
| 文件尾滤波器冲洗 | 10 ms |

融合实现先用连续矩阵 NCO 将每个频偏搬到零频，再以中心频率 0 的
`dsp.DigitalDownConverter` 完成抗混叠滤波和整数抽取。输入采样率除以输出率必须是至少
为 2 的整数；目标载频连同 55 kHz 阻带边界必须留在输入 Nyquist 范围内。

`resolveInputConfig` 在 120 kS/s 不能整除输入时依次尝试
`125/120/128/100/96/80 kS/s`，并要求输出 Nyquist 高于 55 kHz。两个典型结果是：

- 2.5 MS/s 捕获：自动选择 125 kS/s，整数抽取 20；
- 61.44 MS/s 捕获：保持 120 kS/s，整数抽取 512。

DDC 在块间保留 NCO 和滤波器状态。任意长度的上游块先进入余量缓冲，只以固定 10 ms
整数抽取块调用 System object。检测到不连续时清除余量、复位转换器并增加连续性代号。
当前转换计算显式使用复数 `double`，这是现有 MATLAB R2022b 环境下避免低幅度
`single` 异常衰减的已验证基线。

120/125 kS/s 都给 48 kS/s 的 4FSK 分支和 72 kS/s 的 TETRA 分支保留了重采样余量。
融合 DDC Actor 跨输入块保存每路 NCO、抽取器、余量和连续性代号；输出在客户端按载频
分别进入 `streamScannerQueueBaseband`，拼成默认 100 ms 基带微批后再送活动检测与协议
协调器。DDC 输出样点号按宽带样点号除以抽取率建立，但当前宽带 PDU 回映射仍没有补偿
DDC 滤波群时延。

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
| 初始噪声底 | `NaN`，首个可用块自动估计 |
| 开启门限 | 噪声底 + 10 dB |
| 关闭门限 | 噪声底 + 6 dB |
| 最短开启时间 | 50 ms |
| 关闭保持 | 300 ms |
| 谱噪声 FFT | 2048 点、最多 4 段 |
| 谱噪声更新周期 | 0.5 s |

活动检测器对每个微批计算 `mean(abs(iq)^2)`。默认不再假设固定的 -60 dB 噪声底，而是
对复 IQ 的 Hann 加窗 periodogram 取频点中位数，再除以 `log(2)` 估计复高斯噪声功率；
窄带 PMR 只占少数频点，所以即使第一块已经有信号也能初始化底噪。非活动期间用 0.05
指数系数更新平滑值；如果功率突然超过旧门限，还会立即触发一次谱估计以避免沿用陈旧
底噪。调用者显式提供有限噪声底时，该值被视为校准先验，不再自动覆盖。

开启和关闭使用迟滞。状态依次为
`NO_SIGNAL -> ACTIVITY_PENDING -> CLASSIFYING`；达到 50 ms 开启条件时创建 RF Epoch，
关闭保持到期、输入丢样或显式结束时关闭 Epoch。8 s 环形缓冲始终先接收当前 100 ms
微批，用来保存 pre-trigger、Probe 快照、winner catch-up 和锁定解码积压。

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

每次尝试完成后，`nextWindowSec` 取“已尝试时长的 2 倍”并受最大窗限制；没有新增样点时
不会重复提交。并行传输不直接序列化复数 MATLAB 数组，而是由
`lockedDecoderActorPackChunk` 按当前块峰值缩放成 CI16，worker 再恢复复数 `single`。
默认五路载频共享五个协议 worker：每个载频同时在途任务数默认为
`floor(NumWorkers/channelCount)`，多载频时每个 100 ms feed 最多新启动一路 Probe race，
防止所有信道同时冷启动压垮进程池。

### 5.3 调制家族门控和并行 Probe

分类期间，`raceCoordinatorFeed` 同时推进家族门控和 Probe，而不是等门控先结束。
`protocolCandidateGate` 最多查看最近 250 ms IQ 的相邻样点差分相位。至少 80 ms 才开始分析，
至少 180 ms 才允许作出决定，并要求连续两次得到相同家族。它只在证据很强时把候选缩为：

- `fsk4`：DMR、P25、dPMR、NXDN；
- `pi4dqpsk`：TETRA；
- `uncertain`：保留全部制式，避免门控把不确定性变成漏检。

门控尚未稳定时，Probe 可以先按全候选启动；若家族在 race 运行期间稳定，
`parallelProbeRaceApplyCandidateMask` 会对尚未需要的候选应用新掩码。因此门控是保守的减负载器，
不是首个 Probe 的 180 ms 串行前置延迟。

`parallelProbeRaceStart` 对达到各自观察窗长度的候选调用
`executeProbeTaskPacked -> runProtocolProbe -> decodeProtocolWindow`。同一个基带快照会在不同
worker 内独立重采样和恢复 dibit。虽然 DMR/P25 在协议注册表中具有相同
`frontendKey='c4fm_4fsk'`，这个缓存只被传统同进程 `radio.decodeIqEnabled` 使用；当前并行
Probe 不会跨 worker 共享一份鉴频波形。

识别器必须越过本文定义的 raw-dibit 边界做一次校验，才能避免“仅同步相关峰”造成误锁。
当前强证据为：

| 制式 | 确认依据 |
|---|---|
| DMR | RS 有效 Full LC，或 CS5 有效 Late Entry LC |
| P25 | BCH 有效 NID |
| dPMR | CRC 有效 CCH，或至少两个 Hamming 有效 CCH |
| NXDN | CRC 有效信道块并且 LICH 有效 |
| TETRA | FEC 有效的 DMO 控制块 |

只有同步、单个弱 CCH、LICH 或训练序列时保持 `candidate` 并扩大观察窗。UI 默认开启
`EarlyProbeConfirm`，置信度达到 0.99 后可以取消尚未完成的其他候选任务。

### 5.4 赢家追赶、原生增量解调和重新分类

赢家确认后，协调器进入 `CATCHING_UP`。`winnerCatchup` 从
`max(环形缓冲起点, candidateStart-0.5 s)` 到当时实时边沿再执行一次完整赢家解码，合并
Probe 已产生的 PDU。`Deduplicate=true` 时这里调用 `radio.deduplicatePdus`；
`radio_live_frontend` 默认为 `false`，保留调试阶段的每次 PDU 上报。完成后 `lockedDecoderInit` 用追赶末端作为
`lastProcessedEndSample`，并把各协议所需的一段历史作为 `nativeSeed`。
`lockedDecoderInit` 仍会把已有 PDU 样点键放入 `seenKeys`，防止同一空口块因接管重叠再次输出；
关闭的是“不同样点但内容相同”的语义去重。

内置五制式在没有自定义 `LockedDecodeFcn` 时都设置 `nativeStreaming=true`。后续
`lockedDecoderReady` 只在积累到最小新时长后提交尚未消费的 IQ：DMR/dPMR/TETRA 为
250 ms，P25/NXDN 为 200 ms。持久 worker 保存原生重采样器、FIR、NCO/DC、上一 IQ、
同步搜索指针、有限波形缓存和帧/会话状态；客户端只保留调度所需的轻量 shadow state。
首次 Actor 接管时会先在 worker 内喂入 `nativeSeed` 来填充因果滤波、同步与帧状态，
这次 seed 产生的输出被丢弃，然后才处理第一段新 IQ；这是一次性状态迁移，不是之后每块重算历史。

锁定解码连续 3 次没有强证据进入 `LOSS_PENDING`，达到 6 次进入 `RECLASSIFYING`；恢复
强证据则回到 `LOCKED`。重新分类会增加 generation，旧 worker 结果因 epoch/generation
不匹配而被丢弃，避免异步迟到结果污染当前制式。

## 6. 四种 4FSK：整窗 Probe 与因果锁定前端

DMR、P25、dPMR 和 NXDN 最终都得到一条约为
`-3/-1/+1/+3` 的实数鉴频波形，但当前代码有两套执行形式：

- Probe/追赶路径对冻结 IQ 窗整体处理；DMR、P25 和 dPMR 调用
  `common.fskFrontend`，NXDN 调用独立的 `nxdn.frontend`。
- `LOCKED` 路径调用 `<protocol>.streamInit/streamDecodeChunk`，保存重采样器、
  FIR、鉴频前一个 IQ、DC 跟踪和同步搜索游标，不再对旧窗重算。

下面 6.1～6.3 首先说明整窗路径，6.4 再说明锁定后的对应实现。

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

### 6.4 锁定后的因果增量前端

`incrementalDecoderFeed` 会按获胜制式分派到原生状态机。四种 4FSK 的因果顺序为：

```text
新增 120/125 kS/s IQ
  -> 跨块有状态重采样到 48 kS/s
  -> 首段频偏估计/NCO（NXDN 例外）
  -> 151-tap 因果 FIR，保存 zi
  -> angle(x[n] * conj(x[n-1]))，保存 x[n-1]
  -> 0.25 s 时常的一阶 DC 跟踪
  -> 有界 demodBuffer + nextSearchSample/Center
  -> 只处理已完整到达的同步候选
```

| 制式 | 重采样实现 | 首段粗频偏 | 流式特点 |
|---|---|---:|---|
| DMR | `dsp.FIRRateConverter` | 1.25 s，PSD 最大 bin | 连续 NCO、151-tap FIR、突发搜索游标 |
| P25 | `dsp.FIRRateConverter` | 1.00 s，PSD 最大 bin | 同上，但保留足以等待完整 864-symbol 帧的缓冲 |
| dPMR | `dsp.FIRRateConverter` | 1.00 s，PSD 最大 bin | 同上，以 384-dibit 帧为完整候选 |
| NXDN | 120/125 kS/s 优先自实现多相 FIR，其他比率可用 `dsp.FIRRateConverter` | 无一次性 PSD 质心 | 151-tap FIR 后直接鉴频，用 DC IIR 持续吸收剩余中心偏移 |

因果 FIR 会引入 75 个 48 kS/s 样点的群时延，重采样器还有自身时延。
`streamInit` 把两者合成 `pipelineDelaySamples`，PDU 样点回映时再按采样率比换算回
DDC 输入时间轴。这个映射不等于已补偿更外层的宽带 DDC 群时延。

### 6.5 共同物理参数

| 制式 | 符号率 | 目标采样率 | 每符号样点 | 低通截止 | `DevNominal` |
|---|---:|---:|---:|---:|---:|
| DMR | 4800 sym/s | 48 kS/s | 10 | 9.5 kHz | 1944 Hz |
| P25 Phase 1 | 4800 sym/s | 48 kS/s | 10 | 9.5 kHz | 1944 Hz |
| dPMR | 2400 sym/s | 48 kS/s | 20 | 3.5 kHz | 1050 Hz |
| NXDN96 | 4800 sym/s | 48 kS/s | 10 | 6.5 kHz | 2400 Hz |

DMR 和 P25 在注册表中使用相同 `frontendKey='c4fm_4fsk'`，且整窗前端参数相同。
传统同进程 `radio.decodeIqEnabled` 可以复用一份鉴频结果；
`radio_live_frontend` 的并行 Probe 把各候选发到不同 worker，因此并不跨 worker 共享该结果。
锁定后当然也只运行获胜制式的一套原生前端。

### 6.6 四电平到 dibit 的统一映射

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
MSB-first hard bit。`adaptiveSliceBits` 的输出即是本文边界。数据路径由
`dmr.decodeBurst` 在函数内部调用它，随后立即进入 Slot Type/BPTC/RS；语音路径由
`recoverSteppedBurstBits` 调用它，随后进入嵌入信令收集。这些后续均不在本文展开。

### 7.5 在锁定流中的实际调用顺序

DMR 锁定后不另造一套 dibit 算法，而是在有界鉴频缓冲上复用上述函数：

```text
dmr.streamDecodeChunk
  -> processAvailableBursts
  -> dmr.findSyncPositions
  -> dmr.frameDecoderFeedCandidate
  -> dmr.decodeSyncCandidate
     +-> data:  recoverBurst -> decodeBurst -> adaptiveSliceBits
     +-> voice: lockVoicePhase -> recoverSteppedBurstBits
                                      -> adaptiveSliceBits
```

`nextSearchCenter` 阻止已扫过区间被重复处理；缓冲只保留完成后续语音突发所需的
历史和同步 guard。`frameDecoderFeedCandidate` 还保存已见突发键、Late Entry
collector 和会话状态；这些位于 raw dibit 之后，但它们提供锁定所需的强证据。

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

### 8.4 在锁定流中的实际调用顺序

```text
p25.streamDecodeChunk
  -> processAvailableFrames
  -> p25.findFrameSync
  -> p25.decodeFrameCandidate
     -> recoverSymbolsFromFs(57 symbols) -> sliceSymbolsToBits
     -> 若 DUID 需要完整帧：
        recoverSymbolsFromFs(864 symbols) -> sliceSymbolsToBits
  -> p25.frameDecoderFeedRecord
```

流式实现要等到 `lduSymbols*samplesPerSymbol = 8640` 个 48 kS/s 鉴频样点完整
到达，才把对应范围交给帧候选解码。因而文件尾部仅有 FS+NID、但没有完整
864-symbol 帧的候选不会在增量路径输出。`nextSearchSample` 及同步 guard 使历史
裁剪后仍能跨 Chunk 找到 Frame Sync。

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

### 9.4 在锁定流中的实际调用顺序

```text
dpmr.streamDecodeChunk
  -> processAvailableFrames
  -> dpmr.findSync
  -> dpmr.frameDecoderFeedCandidate
  -> dpmr.decodeSyncCandidate
  -> dpmr.recoverFrameSymbolCandidates
  -> candidate.symbols = 384 个数值 dibit
```

前端只在累积到完整 384 符号，即 `384*20=7680` 个 48 kS/s 鉴频样点后处理候选。
目前 `dpmr.config` 及实际恢复函数仍把 `samplesPerSymbol` 固定为 20；这是时间分辨率
和计算量之间的当前选择，不是一个会在流中自动收敛的 SPS 估计器。
增量优化避免了旧 IQ 的重采样和鉴频重算，但每个完整候选内的 25 个相位测试仍会执行。

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

### 10.5 锁定后 NXDN 的差异

`nxdn.streamDecodeChunk` 不再运行 10.1 中的整窗 PSD 质心和 `filtfilt`。它的实际顺序为：

```text
nxdn.streamDecodeChunk
  -> polyphaseRateConvert / dsp.FIRRateConverter
  -> 151-tap causal filter
  -> adjacent-IQ FM discriminator + DC tracker
  -> processAvailableFrames
  -> nxdn.findFrameSync
  -> nxdn.frameDecoderFeedCandidate
  -> recoverFrameSymbols -> sliceDibits
```

每满 `192*10=1920` 个 48 kS/s 鉴频样点就有条件恢复一帧。增量路径对 120/125 kS/s
调谐输出优先使用纯 MATLAB 多相 FIR，不显式构造插零向量。
`nextSearchSample` 只允许新完整帧进入 `frameDecoderFeedCandidate`；该函数内部的
`sliceDibits` 输出仍然是与整窗路径相同的 192 个物理 dibit。

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

### 11.8 锁定后的因果 TETRA DMO 路径

TETRA 获胜后调用 `tetra.streamInit/streamDecodeChunk`，不再对每个重叠窗重复执行
`decodeIqWindow`：

```text
新增 120/125 kS/s IQ
  -> dsp.FIRRateConverter -> 72 kS/s
  -> 首个 0.5 s calibrationBuffer
     -> coarseFrequencyOffset
     -> 因果 RRC + timingSearch
     -> 剩余频偏评估 + bestDecisionVariant
  -> 连续 NCO + 保存 zi 的因果 RRC
  -> 按锁定相位跨 Chunk 插值取样
  -> 保存 previousSymbol 的 pi4dqpskDecision
  -> bitBuffer/validMask -> 仅处理新完整 510-bit slot
```

首次校准会暂存 0.5 s IQ；校准完成后该段也会被送入连续前端，不会丢掉。
之后只采用已锁定的频偏、定时相位、判决变体和相位偏置；当前没有连续更新符号钟
相位的跟踪环。

`tetra.pi4dqpskDecision` 在这条路径中仍会构造 `bitPairs/bits/dibits`。但
`streamDecodeChunk` 当前只把 `bits` 和 `bitValidMask` 放入持久缓冲，数值
`dibits` 是调制判决内的瞬时结果，不会单独返回给协调器。当前该增量后端只实现
TETRA DMO，不包含 TMO。

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
后端直接消费。在 Probe 中，它们在 `executeProbeTaskPacked` 所在 worker 内生成，
紧接着被 FEC/PDU 证据评估消费；在 `LOCKED` 中，它们在持久协议 Actor 内生成，
紧接着被帧/会话状态机消费。两种情况下都不会以独立消息返回 UI。

若下一阶段需要保存、对比或回放原始 dibit，建议新增统一结构，例如：

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

### 13.1 状态归属

当前链路不是一个大循环，而是多个长寿命组件通过有界队列/共享环连接。
理清“谁保存什么”可以解释为什么分块不应改变 dibit 结果：

| 所在组件 | 主要持久状态 | 不连续时的处置 |
|---|---|---|
| `fileProducerWorker` | 文件位置、循环次数、全局源样点号、回放节拍 | 依回放模式标记 `discontinuity` |
| `sharedIqRing` | write sequence、live sample edge、每槽 CI16/比例/时间元数据 | guard 不一致则重读；消费者落后则显式 overrun |
| `spectrumActorWorker` | PSD 余量、Average、Max Hold、发布节拍 | 可丢显示块，下一块重置谱状态 |
| `ddcActorWorker` | 共享环读序号、每载频 NCO、抽取器、10 ms 余量 | 重置 DDC；环溢出不静默跳过 |
| 每载频 `raceCoordinator` | 8 s IQ 环、Activity/Epoch、家族门控、Probe race、winner、generation | 关闭 Epoch、取消任务并重建候选状态 |
| Probe worker | 单次冻结快照和整窗诊断 | 无跨任务 DSP 状态 |
| 获胜协议 Actor | 重采样/FIR/NCO/DC、上一 IQ/符号、搜索游标、帧与会话状态 | 销毁原生上下文，从新连续段重建 |
| UI/client | 用户选频、运行代、轻量 decoder shadow、PDU/状态文本 | generation 不匹配的迟到结果丢弃 |

WOLA/PFB 自动发现路径另外保存 WOLA 输入历史、候选轨迹、残余 NCO 和
129-tap 细提取 FIR；它不会与人工点击链同时运行。

### 13.2 从点击到稳态 dibit 的时间线

```text
点击频点
  -> 仅保存 selection
点击 Run（t0）
  -> 记录 live edge，从下一个 20 ms 宽带块开始 DDC
  -> DDC 内部每 10 ms 处理，client 每 100 ms 送一个基带微批
  -> 活动达到 50 ms 条件后建立 Epoch
  -> 同时推进家族门控和已达初始窗的 Probe
     +-> Probe 初始窗为 0.10~0.50 s
     +-> 门控至少看 180 ms 且连续 2 次稳定后，才缩小后续候选
  -> 无强证据则按 2 倍窗扩展，最长至 1.0~6.0 s
  -> 强 FEC/PDU 证据确认获胜制式
  -> Winner Catch-up 追到当时实时边沿
  -> 启动/接管持久协议 Actor，用 nativeSeed 建立连续状态
  -> 每累积 200/250 ms 未消费 IQ 提交一次增量解码
```

上述 50/180/200/250 ms 及 Probe 窗是“必须累积的信号时长”，不是对首个 dibit
墙钟延迟的单独保证。微批对齐、worker 排队、首次 JIT、Probe 计算、catch-up 和协议帧本身
长度都会叠加墙钟延迟。例如 DMR 增量前端还要等首段 1.25 s 粗频偏估计；
TETRA 要等 0.5 s 校准。

`ensureDecodeRuntimePrepared` 在 Preview 前预热进程池、五制式和 DDC Actor。这会把大部分
冷启动移到播放前；当前实现记录在测试机上观察到约 41 s 的协议/DDC runtime 完整冷预热，
这是用户体验开销，但不计入后续 1× 文件播放实时因子。

### 13.3 连续性和异步正确性约束

1. 宽带块用绝对 `sourceSampleStart/sourceSampleEnd` 和 sequence 排序；任何样点跳变都不得
   被当作连续 IQ。
2. 共享环的每个槽使用前后 sequence guard，防止消费者读到覆盖中的半块数据。
3. 进程输入用每块独立峰值比例的 CI16 打包，它减少 IPC 负载，但也意味着 Probe/
   Actor 看到的是一次 16-bit 量化后的近似 IQ。
4. Probe、catch-up 和 locked result 都带 epoch/generation；用户 Clear、重分类或新 Epoch 之后的
   旧 Future 即使迟到，也不能更改当前获胜制式。
5. 异步不等于允许无界积压。显示支路可丢帧；解码支路一旦共享环 overrun，必须显式
   失败或重建，不得用慢放或静默丢样掩盖。

### 13.4 当前“实时”结论

2026-07-16 的
[多协议真正增量解码与持久 Worker 第二阶段记录](../records/recognition/多协议真正增量解码与持久Worker第二阶段记录.md)
表明：2.5 MS/s 宽带输入、五个已知大致频点、
DMR/P25/dPMR/NXDN/TETRA 近同步出现时，五个获胜制式和 PDU 闭环均能正确完成。
两次运行的最大输入滞后约 0.196～0.205 s，另一次达到 0.259 s，超过当时的
250 ms 软实时门槛 9 ms。因此准确表述是：

- 2.5 MHz/五已知载频的功能检测与持续解码已打通；
- MATLAB 软实时多次可达，但尚不是确定性 250 ms 保证；
- 已知最大长尾更像进程竞争、IPC/调度和 UI timer 抖动叠加，不能只归因于某次降采样；
- 这不是 60 MHz 输入、真实 SDR 或硬实时保证。

## 14. 当前能力与限制总结

### 14.1 已经实现

1. RAW/WAV/BVSP 输入、循环回放、绝对样点时间轴和不连续传播；
2. `radio_live_frontend` 默认 20 ms、1× 异步文件生产，约 2 s CI16 共享 IQ 环；
3. 后台实时频谱、Average/Max Hold、质心精调和最多五路点击选频；
4. 最多五载频矩阵 NCO + 融合有状态 DDC，2.5 MS/s 自动选 125 kS/s；
5. 100 ms 基带微批、自适应活动检测、RF Epoch、8 s 环形缓冲和 pre-trigger；
6. 4FSK/TETRA 家族门控、五制式并行递增 Probe、强证据锁定和 Winner Catch-up；
7. DMR、P25、dPMR、NXDN96 的 4FSK hard dibit 恢复；
8. TETRA 的 pi/4-DQPSK hard dibit、有效掩码和可靠度恢复；
9. 五制式获胜后的持久协议 Actor、因果增量 DSP/帧状态和重分类；
10. 1024 通道、2 倍过采样 WOLA/PFB 正确性实现，包括候选轨迹和细提取；
11. 传统离线频偏列表、窄带 PSD 盲扫和同进程 DMR/P25 前端复用。

### 14.2 仍然受限

1. 没有生产级真实 SDR Source、DMA/驱动接入和硬件时间戳；当前有界共享环验证的是文件生产者。
2. 61.44 MS/s WOLA/PFB 的 MATLAB CPU 版本是正确性基线，不承诺 1× 实时；
3. `radio_live_frontend` 默认上限是五个选频，并共享五个协议 worker；载频继续增加不能靠线性加 worker 扩展。旧 `radio_frontend` 仍是单载频入口。
4. 已知载频 PDU 回映射到宽带绝对样点尚未补偿 DDC 滤波群时延；
5. 离线调试入口仍保留整窗/全诊断处理；锁定后的 DMR、P25、dPMR、NXDN96 和
   TETRA DMO 已有因果增量解调路径，但 Probe/Catch-up 仍是整窗，并行 Probe 不跨 worker 复用 DMR/P25 前端；
6. DMR/P25 使用固定 10 samples/symbol，NXDN 只做整数相位细化，dPMR 默认也固定
   20 samples/symbol；尚无连续符号钟漂移跟踪环；
7. 硬判决接口未统一，除 TETRA 外没有统一可靠度/soft dibit 输出；
8. 传统 PSD 盲扫不包含 TETRA；只有显式 TETRA、已知载频竞速或宽带 PFB 路径会尝试 TETRA；
9. 当前 BVSP 解析只覆盖已经观察到的 112 字节 USRP/CI16 格式；
10. 增量 DMR/P25/dPMR 的粗频偏在首段估计后固定，TETRA 的频偏/定时/判决变体在 0.5 s 校准后固定；没有针对长时频漂的闭环跟踪；
11. 当前协议范围是 DMR、P25 Phase 1、dPMR、NXDN96 和 TETRA DMO；TETRA TMO、NXDN48/Type-D 不在增量路径范围；
12. 本文之后的后端能力并不完整，尤其不能由“dibit 已恢复”推断语音或所有控制信道均已实现；
13. 完整冷预热和 MATLAB 调度尾延迟仍较大；2.5 MHz 五路是功能及软实时基线，不是硬实时证明。

当前 MATLAB 实现还依赖相应工具箱能力：整窗有理重采样、`fir1` 和 `filtfilt` 需要相关信号
处理函数；调谐链使用 `dsp.DigitalDownConverter`；多个增量前端使用 `dsp.FIRRateConverter`；
异步生产、协议进程池和持久 Actor 需要 Parallel Computing Toolbox。并行池不可用时部分离线路径可回退串行，
但 `radio_live_frontend` 的默认异步主链不能在缺少这些能力时仍维持相同运行模型。

### 14.3 现有验证入口

与本文范围直接相关的回归入口包括：

- `tests.runAll`：统一入口、PSD 候选、五制式样本和各阶段回归总入口；
- `tests.runDmrStreaming/runP25Streaming/runDpmrStreaming/runNxdn96Streaming/runTetraStreaming`：
  原生增量解调、不规则分块一致性、有界缓冲和真实样本；
- `tests.runPersistentLockedDecoder`：五制式持久 Actor、CI16 接管、轻量 shadow 和安全释放；
- `tests.runTunedTransition/runFusedMultiDdc`：采样率选择、NCO、融合抽取、带外抑制与分块等价；
- `tests.runStreamingPhase10`：WOLA/PFB 分块等价性、候选、跟踪、细提取和宽带 DMR
  全链；
- `tests.runSharedIqRing`：共享 CI16 槽、sequence guard、覆盖检测和运行代切换；
- `tests.runRealtimeFrontendPhase1...7`：循环源、频谱/精调、单/多载频 DDC、隐藏 UI、
  共享环隔离和 Clear/二次 Run；
- `tests.runFiveSignal2p5MHzAcceptance`：2.5 MS/s、五载频近同步功能与软实时压力验收；
- `tests.runRealtimeFrontendBvspAcceptance`：外部真实 BVSP 的可选串行/五进程验收。

这些测试既包含纯合成向量，也会在外部样本存在时运行 DMR、P25、dPMR、NXDN 和 TETRA
实录路径。五路压力验收和 BVSP 实录验收没有放进每次 `runAll`，因为它们依赖大文件、
较长墙钟时间和本机并行调度环境。

## 15. 关键代码索引

### 主入口、实时生产与频谱

- `radio_live_frontend.m`
- `+radio/+live/fileProducerStart.m`
- `+radio/+live/fileProducerWorker.m`
- `+radio/+live/sharedIqRingCreate.m`
- `+radio/+live/sharedIqRingWriteTransport.m`
- `+radio/+live/sharedIqRingRead.m`
- `+radio/+live/sharedIqRingSnapshot.m`
- `+radio/+live/spectrumActorWorker.m`
- `+radio/+scope/spectrumFeed.m`
- `+radio/+scope/refineCarrier.m`

### IQ 输入与公共 DSP

- `+common/readRawIq.m`
- `+common/detectSampleRate.m`
- `+common/resampleTo.m`
- `+common/welchPsd.m`
- `+common/fskFrontend.m`
- `+radio/+stream/makeIqChunk.m`
- `+radio/+stream/fileSourceInit.m`
- `+radio/+replay/fileLoopSourceInit.m`

### 点击载频与融合 DDC

- `+radio/+tuned/resolveInputConfig.m`
- `+radio/+live/ddcActorStart.m`
- `+radio/+live/ddcActorAttachRing.m`
- `+radio/+live/ddcActorWorker.m`
- `+radio/+tuned/multiDdcInit.m`
- `+radio/+tuned/multiDdcFeed.m`
- `+radio/+tuned/multiStreamScannerInit.m`
- `+radio/+tuned/multiStreamScannerFeedBasebands.m`
- `+radio/+tuned/streamScannerQueueBaseband.m`

### 备选载频发现路径

- `+radio/psdBlindSearch.m`
- `+radio/processCandidate.m`
- `+radio/+wideband/channelizerFeed.m`
- `+radio/+wideband/detectCandidates.m`
- `+radio/+wideband/candidateTrackerFeed.m`
- `+radio/+wideband/channelExtractorFeed.m`

### 活动、Probe、Catch-up 与锁定分发

- `+radio/+stream/activityDetectorFeed.m`
- `+radio/+stream/raceCoordinatorFeed.m`
- `+radio/+stream/protocolCandidateGate.m`
- `+radio/+stream/probeRegistry.m`
- `+radio/+stream/parallelProbeRaceStart.m`
- `+radio/+stream/executeProbeTaskPacked.m`
- `+radio/+stream/runProtocolProbe.m`
- `+radio/+stream/decodeProtocolWindow.m`
- `+radio/+stream/winnerCatchup.m`
- `+radio/+stream/lockedDecoderStart.m`
- `+radio/+stream/lockedDecoderActorWorker.m`
- `+radio/+stream/incrementalDecoderFeed.m`

### 五制式整窗/增量物理层边界

- DMR：`+dmr/frontend.m`、`streamInit.m`、`streamDecodeChunk.m`、`findSyncPositions.m`、
  `recoverBurst.m`、`recoverSteppedBurstBits.m`、`adaptiveSliceBits.m`
- P25：`+p25/frontend.m`、`streamInit.m`、`streamDecodeChunk.m`、`findFrameSync.m`、
  `recoverSymbolsFromFs.m`、`sliceSymbolsToBits.m`
- dPMR：`+dpmr/frontend.m`、`streamInit.m`、`streamDecodeChunk.m`、`findSync.m`、
  `recoverFrameSymbolCandidates.m`、`symbolsToBits.m`
- NXDN：`+nxdn/frontend.m`、`streamInit.m`、`streamDecodeChunk.m`、`findFrameSync.m`、
  `recoverFrameSymbols.m`、`sliceDibits.m`
- TETRA：`+tetra/decodeIqWindow.m`、`streamInit.m`、`streamDecodeChunk.m`、
  `coarseFrequencyOffset.m`、`rrcTaps.m`、`timingSearch.m`、`pi4dqpskDecision.m`

## 16. 一句话结论

当前主链已经打通“点击选频 → 从 Run 时 live edge 开始融合 DDC → 活动/Epoch →
整窗五制式 Probe → 强证据锁定 → 持久 Actor 因果增量解调 → 空口 hard dibit”的
完整实现；当前主要缺口是统一 raw-dibit 对外接口、长时频率/符号钟跟踪、确定性实时性以及
生产级 SDR/C++ 数据面。
