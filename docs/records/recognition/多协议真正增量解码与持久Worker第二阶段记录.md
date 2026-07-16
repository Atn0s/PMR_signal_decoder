# 多协议真正增量解码与持久 Worker 第二阶段记录

日期：2026-07-16

分支：`feature/streaming-protocol-race`

## 1. 阶段结论

本阶段把 NXDN96 原型推广到了 DMR、P25、dPMR 和 TETRA DMO。
当前五制式锁定后的运行状态为：

| 制式 | 持久进程 Actor | 真正增量 DSP/帧状态 | 当前边界 |
|---|---:|---:|---|
| DMR | 是 | 是 | 不解语音；粗频偏首次使用 1.25 s 样点估计 |
| P25 | 是 | 是 | 等待完整 864-symbol 帧后才输出，不输出尾部不完整 NID |
| dPMR | 是 | 是 | 稳定 Color Code 后处理需要跨块聚合 |
| NXDN96 | 是 | 是 | 保持上一阶段实现，不含 NXDN48/Type-D |
| TETRA DMO | 是 | 是 | 因果 π/4-DQPSK、slot/DMAC/会话；不含 TMO |

因此，锁定后的五个解码器都可以长期占用各自的进程 worker，避免每次 `parfeval`
重新创建任务；五种已支持模式均只消费新增 IQ，不再在 `LOCKED` 后重复跑有界
历史整窗。这完成了当前直通/DMO 范围内的协议级真增量化，但还不能据此宣称
五路场景具有确定性硬实时保证。

## 2. 当前数据链

```text
2.5 MHz CI16 文件/未来 SDR Chunk
        |
        v
共享五路融合 DDC（当前样例输出 125 kS/s）
        |
        +--> 每载波 Activity / Epoch / Ring Buffer
                    |
                    v
             五制式并行 Probe
                    |
                    v
              Winner Catch-up
                    |
                    v
        持久协议 Actor（每次仅提交新增 CI16 IQ）
                    |
                    v
        因果重采样/FIR/鉴频/DC -> 滚动同步缓存
                    |
                    v
        协议帧状态/会话状态 -> 新 PDU -> 健康判定
```

Probe 和 Winner Catch-up 仍负责从 Epoch 起点追上实时边缘。赢家进入 `LOCKED` 后，
`incrementalDecoderFeed` 根据协议分派到原生状态机；绝对源样点通过重采样比例和前端
群时延映射回输入时间轴。输入不连续或样点号跳变时销毁原生状态并建立新上下文，不把
跨丢样数据错误拼接成连续帧。

## 3. 持久 Worker 泛化

### 3.1 Actor 覆盖范围

`lockedDecoderActorEligible` 允许 DMR、P25、dPMR、NXDN 和 TETRA 的内建解码器使用
进程 Actor；带自定义 `DecodeFcn` 或 thread pool 的路径继续使用原兼容调度。精确
120 kS/s 的 NXDN 保留 `backgroundPool` 特例，常见 125 kS/s 调谐输出使用进程 Actor。

Actor 在 worker 内持有完整 `DecoderState`。客户端只保留轻量 shadow，后续请求不再
往返传输 FIR 延迟线、帧会话或大块历史。首次迁移时，原兼容层的 `historyIq` 和原生
`nativeSeed` 也使用 CI16 payload 传输，避免 complex-single 结构序列化放大。

### 3.2 诊断压缩

TETRA 离线诊断曾达到约 3.56 MB，其中 slot 和 training 数组占绝大部分。实时协调器
只需要标量证据和小型状态，因此 `compactDecoderDiagnostics` 递归保留小数组、短文本
和标量结构，删除训练序列、slot、符号和比特大数组，并记录省略计数。Actor 返回值及
客户端 shadow 的诊断负载均由回归约束为小于 64 KiB；离线调试入口仍保留完整诊断。

### 3.3 启动准入与预热

多个载波几乎同时完成分类时，五个长期 Actor 若在同一 UI tick 建立，会叠加队列握手、
worker 放置和 JIT 峰值。`multiStreamLockedDecodeDeferrals` 现在执行：

- `CLASSIFYING`、`RECLASSIFYING`、`CATCHING_UP` 优先于稳态 locked decode；
- 每个 Feed 默认最多新建 1 个 Actor；
- 两次 Actor 新建默认间隔 3 个 Feed；
- 已经存在的 Actor 不受新建限流影响，仍可继续处理。

预览的 `PREPARING` 阶段会让空 Actor 逐一访问全部进程 worker，再显式停止；同时在每个
worker 预热 DMR/P25/dPMR/NXDN/TETRA 的 125 kS/s 原生前端。这样把队列握手、
System object 初始化和大部分 JIT 成本移到文件播放前。代价是冷启动仍然
明显：本机最近两次五 worker、五 DDC 的完整准备耗时约为 41.3～41.6 s，它不计入
后续 1x 播放，但仍需继续优化用户体验。

## 4. 五个原生增量协议

五套实现统一提供：

```text
<protocol>.streamInit(sampleRateHz, cfg)
<protocol>.streamDecodeChunk(state, IqChunk)
<protocol>.streamFlush(state)
```

公共实现原则为：

1. 用有状态 `dsp.FIRRateConverter` 处理非整数块长的跨块重采样；
2. 粗频偏只在首个固定估计区间计算，后续 NCO 相位连续；
3. FIR、鉴频前一 IQ 样点和 DC IIR 状态跨 Chunk 保存；
4. 只在有足够完整帧样点时处理同步候选；
5. 维护绝对搜索游标并裁剪旧解调样点，内存不随文件时长增长；
6. 帧、呼叫和链路层会话通过 `frameDecoderInit/Feed/Finalize/Report` 持续更新；
7. 每次只返回本 Chunk 新产生的 PDU，并给出一一对应的源样点位置。

### 4.1 DMR

DMR 将同步候选解码、Late Entry collector、呼叫会话和跨窗 PDU 账本拆成持久状态。
离线 `dmr.decode` 也复用相同帧候选函数，减少两条路径的语义分叉。首次粗频偏估计区间
为 1.25 s，之后滚动同步缓存保持在约 1.5 s 以内。

### 4.2 P25

P25 将 Frame Sync、BCH NID、HDU/LDU1/LDU2 和呼叫会话拆成逐帧接口。流式路径发现
同步后会等到完整 864-symbol 帧到齐再输出，因此测试样例离线得到 12 条 PDU，而流式
得到 11 条完整、BCH 有效的帧；离线末尾那条仅有 NID、后续 LDU 不完整。该差异是因果
完整性策略，不是随机漏检。

### 4.3 dPMR

dPMR 持续保存 FS1/FS2 候选、CCH/Color Code、ID 拼接和呼叫会话。流式 Chunk 输出只做
结构归一化，不在每个 Chunk 内单独执行稳定 Color Code 过滤；否则不同 Chunk 边界可能
改变过滤结果，并破坏 PDU 与 `sourceSamples` 的一一对应。稳定颜色过滤由拥有完整聚合
视图的离线或最终消费者执行。

### 4.4 NXDN96

NXDN96 延续首阶段的有状态 FIR/重采样、FSW/LICH、SACCH 组合、FACCH/UDCH/CAC 和
Layer 3 会话实现。本阶段主要完成它与通用 Actor、启动准入和统一预热的整合。

### 4.5 TETRA DMO

TETRA 流式链路使用有状态 125 kS/s 到 72 kS/s 变换、固定 0.5 s 首段校准、
连续 NCO/RRC、跨 Chunk 符号插值与差分硬判决。比特层保存训练序列搜索游标、
完整 slot 边界、DMO DCC/MAC 上下文和会话状态；只处理新完整的 slot，并把比特缓冲
裁剪到约一个 slot 的必要量。离线 `decodeIqWindow` 与流式路径共用判决变体、
DMO burst 和 session 状态函数，但离线入口仍保留全量训练/slot 诊断。当前范围是
TETRA DMO，不包含 TMO 基站下行/上行信道。

## 5. 验证结果

### 5.1 协议级回归

2026-07-16 的完整 `tests.runAll()` 通过。协议级真实样本结果为：

| 制式 | 离线 PDU | 流式 PDU | 强校验/完整帧 | 热态实时因子 |
|---|---:|---:|---:|---:|
| DMR | 8 | 8 | 7 条强 PDU | 0.033 |
| P25 | 12 | 11 | 11 个 BCH 有效完整帧 | 0.071 |
| dPMR | 19 | 19 | 18 条 CRC 有效 PDU | 0.077 |
| NXDN96 | 415 | 415 | 524 帧、1062 块 | 0.176 |
| TETRA DMO | 58 | 58 | 42 条有效控制 PDU、52 个确认 burst | 0.550 |

DMR、P25、dPMR、TETRA 都另外使用两组不规则 Chunk 计划和 125 kS/s
DDC 输出验证了分块不变性；NXDN 继续覆盖 120/125 kS/s 增量路径。五制式滚动解调/
比特缓存均满足测试中的有界上限。TETRA 完整样本的离线扫描仍输出 685 条事件，
证明共用状态函数未改变原有语义。`tests.runPersistentLockedDecoder` 还用五种真实样本
验证了 Actor 首次启动、继续提交、强证据、PDU 输出、轻量 shadow 和安全释放。

### 5.2 2.5 MHz 五路近同步压力结果

相同文件、相同 Probe 窗口、相同五个频点，在五协议全部完成真增量化后连续
运行三次，结果为：

| 运行 | 五赢家 | 每路有 PDU | 最大输入滞后 | 端到端 RTF | 250 ms 门槛 |
|---|---:|---:|---:|---:|---:|
| A | 全部正确 | 是，`[4 1 5 18 71]` | 0.205 s | 1.048 | 通过 |
| B | 全部正确 | 是，`[5 1 6 16 76]` | 0.196 s | 1.047 | 通过 |
| C | 全部正确 | 收尾断言前未统计 | 0.259 s | 未完成报告 | 250 ms 失败 |

运行 A/B 分别输出 99/104 条 PDU，最终解码队列均为 0。运行 C 的最慢
Scanner Feed 为 0.1239 s，其中 TETRA 通道占约 0.1062 s；当时五路都已是
`LOCKED`，协议赢家仍全部正确，但输入 timer 的最大墙钟滞后超出门槛 9 ms。
本地拆分计时显示，125 kS/s 下 1 s IQ 压缩的中位耗时约 0.6 ms，空闲单 worker
下含 1 s seed 的 Actor 接管中位约 19 ms。因此压力场景中的 100 ms 级长尾不能
简化为历史数据压缩，更接近进程竞争、IPC/调度和 MATLAB UI timer 抖动的叠加。

所以当前能确认的是：**2.5 MS/s、五个已知载频、五制式未知时，功能识别与 PDU
闭环稳定；250 ms MATLAB 软实时门槛可以通过，但尚不能稳定保证。** 不应通过错开五路
信号、延长 Probe 窗口或减慢文件生产速度来掩盖这一波动。

短文件的 PDU 可能主要由 Winner Catch-up 产生，尚未进入多轮 `LOCKED` 增量处理；因此
locked-decoder completion 计数为零不代表没有完成协议识别。当前统计已补上 EOF 收尾
阶段的 locked decode，但下一步还应分别记录 Probe、Catch-up、Actor 首次启动和稳态
Feed 延迟，才能准确定位首次 PDU 延迟。

## 6. 下一阶段

1. 用至少数分钟的循环输入测量 backlog 斜率、首 PDU 延迟和稳态 PDU 延迟，避免只用
   6.48 s 文件证明收尾追赶。
2. 分离并统计 Probe、Catch-up、Actor 启动/握手、worker compute、IPC 和 UI timer 抖动；
   优先处理 MATLAB 调度长尾，而不是改变协议窗口。
3. 评估让 Winner Catch-up 所在 worker 直接转为持久 Actor，避免 `LOCKED` 后再次
   `parfeval` 和大 seed IPC；这需与全局 Probe 调度一起设计，不能让空闲 Actor 占满进程池。
4. 缩短冷启动：缓存可复用的进程池，评估按需协议预热，同时保留 Run 后不回卷、
   不漏样的不变式。
5. 真实 SDR 型号、块格式和硬件时间戳确定后再实现有界生产者/消费者队列；若产品化，
   MATLAB 保留为算法与回归基准，实时数据面迁移到 C++。

## 7. 复现命令

```matlab
startup
tests.runDmrStreaming()
tests.runP25Streaming()
tests.runDpmrStreaming()
tests.runNxdn96Streaming()
tests.runPersistentLockedDecoder()
tests.runAll()

report = tests.runFiveSignal2p5MHzAcceptance( ...
    'Regenerate', false, ...
    'VerifyKnownChannels', false, ...
    'StrictFrontend', true, ...
    'Verbose', true);
```

五路验收是压力实验，严格门槛失败时应保留原始结果并继续分析；它不是需要通过修改
样本来保证每次绿色的单元测试。
