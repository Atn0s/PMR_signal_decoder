# 60 MHz 宽带实时 IQ 信道化与并行解码设计

## 1. 目标和边界

目标输入是覆盖约 60 MHz 瞬时带宽的连续复数 IQ。系统不知道活动信号位于哪些
频点，也不知道每个频点采用 DMR、P25、dPMR、NXDN 还是 TETRA。实际处理参数必须
使用 SDR 给出的真实采样率，例如 60 MS/s、61.44 MS/s 或 64 MS/s，不能把“60 MHz
带宽”硬编码成固定采样率。

宽带层只负责发现、分离和跟踪载波，不参与协议判决。每个活动载波被转换为一条
连续窄带 IQ 流，再复用已有的 `ChannelController -> RF Epoch -> 五制式 Probe Race
-> 赢家持续解码`。相同发射机跨静默边界仍作为不同 Epoch 上报，不增加跨 Epoch
Session 聚合。

第一版范围：

- MATLAB 中进行离线文件的流式 Chunk 回放；
- 建立和真实 SDR 相同的 `scannerFeed` 增量接口；
- 2 倍过采样 WOLA/PFB 粗信道化；
- 活动子带检测、细频点估计和候选生命周期；
- 每个候选独立接入现有五制式并行竞速；
- 保存宽带原始采样位置和射频中心频率映射。

本阶段不包含具体 SDR 驱动、FPGA/GPU 实现、TETRA TMO 协议补全或同频碰撞分离。

## 2. 总体架构

```text
SdrSource / Wideband FileSource
  5～10 ms Wideband IqChunk
              │
              ▼
  连续 2x-oversampled WOLA/PFB
              │
      N 路低速粗子带 IQ
              │
              ├── 每路功率与局部噪声底
              ├── 活动粗带筛选
              └── 粗带内细 PSD 与候选聚类
                              │
                              ▼
                     CandidateTracker
             TENTATIVE / ACTIVE / OFF_PENDING
                              │
             ┌────────────────┼────────────────┐
             ▼                ▼                ▼
          Track A          Track B          Track C
          细 DDC           细 DDC           细 DDC
          低通 FIR         低通 FIR         低通 FIR
             │                │                │
             ▼                ▼                ▼
       ChannelController  ChannelController  ChannelController
             │                │                │
             ▼                ▼                ▼
        RF Epoch + 每频点五制式 Probe Race + 赢家持续解码
                              │
                              ▼
          PDU + channel_id + epoch_id + RF Hz + SDR 绝对采样位置
```

频点级并行与制式级并行相互独立。若当前有 `C` 个尚未分类的活动频点，最多短暂
存在 `5C` 个 Probe；确认协议后，每个频点只保留一个赢家解码器。

## 3. 两级 Chunk 时序

宽带数据不能直接沿用 100 ms 窄带 Chunk。以 61.44 MS/s complex-single 为例，
100 ms 输入约占 49 MB，还会产生更大的中间矩阵。初始时序为：

```text
SDR 宽带输入       10 ms ── 10 ms ── 10 ms ── ...
PFB 输出           连续状态，不在 Chunk 边界重置
候选检测积分       10～30 ms
候选窄带流         逐 PFB batch 输出
协议处理           在 ChannelController 中继续累计到各 Probe 所需窗口
Epoch 关闭         窄带低功率持续 300 ms
频点路由释放       默认 350 ms，保证 Epoch 已收到关闭 Chunk
```

候选路由保持时间比 Epoch 的 300 ms 多 50 ms只是资源生命周期保护，不改变 Epoch
语义，也不把两次发射合并。

## 4. 2 倍过采样 WOLA/PFB

设输入采样率为 `Fs`、粗通道数为 `N`、每相位抽头数为 `M`：

```text
原型 FIR 长度 L = N*M
相邻粗通道间隔 Δf = Fs/N
2 倍过采样 hop = N/2
每路输出采样率 Fs_sub = Fs/hop = 2*Fs/N
```

默认参数：

| 参数 | 数值 |
|---|---:|
| `N` | 1024 |
| 过采样倍数 | 2 |
| `M` | 8 taps/phase |
| 原型截止位置 | 0.60 个通道间隔 |
| 输入 Chunk | 10 ms |

当 `Fs=61.44 MS/s`：

```text
Δf = 60 kHz
hop = 512 个宽带样点
Fs_sub = 120 kS/s
L = 8192 taps
```

每个 WOLA 窗口先乘原型 FIR，按 `N x M` 折叠求和，再沿 `N` 方向 FFT。FFT 输出
还要按照窗口的宽带绝对起点进行相位去旋转，否则在 `hop=N/2` 时奇数通道会产生
交替相位，不能作为连续子带 IQ。

2 倍过采样使位于两个粗通道边界的载波同时在相邻通道中保留。候选创建时选择
信噪比较高的粗通道，并在活动期间固定该路由，避免粗通道来回切换造成相位跳变。

## 5. 从粗子带到真实载波

约 60 kHz 的粗子带不是最终无线信道，其中可能同时存在多个 6.25、12.5 或 25 kHz
载波。处理分两步：

1. 对所有 PFB 通道计算 batch 平均功率，以通道功率中位数估计当前宽带噪声底；
2. 只对超过 `noise + onMargin` 的粗通道运行细 PSD，并按载波间距聚类。

默认细检测参数：

| 参数 | 初值 |
|---|---:|
| 粗带启动余量 | 10 dB |
| 细 PSD 门限 | 8 dB |
| 细 FFT | 512 |
| 信道能量平滑宽度 | 4.8 kHz |
| 最小候选间距 | 5 kHz |
| 相邻粗带重复合并范围 | 2.5 kHz |

在 120 kS/s 子带中，512 点 FFT 的频率间隔约为 234 Hz。同一 4FSK 载波的多个
符号谱线先按 4.8 kHz 能量窗合成一个信道候选；相隔至少约 6.25 kHz 的两个载波
仍保留为两个候选。

当前噪声估计以每个 batch 的全带中位数为基线。真实 SDR 接入后还要加入长期噪声
分位数、已占用通道排除、DC spur/固定杂散表以及频带边缘有效区掩码。

## 6. CandidateTracker

候选以精细频率而不是 PFB bin 编号匹配：

```text
ABSENT
  │ 首次检测
  ▼
TENTATIVE
  │ 连续达到 minOnSec=30 ms
  ▼
ACTIVE
  │ 当前 batch 未检测到
  ▼
OFF_PENDING
  ├── 350 ms 内恢复：回到 ACTIVE，保持同一频点路由
  └── 达到 350 ms：关闭并释放路由
```

频率采用指数平滑更新，默认 `alpha=0.25`。跟踪器只负责计算资源和 DDC 路由，不
建立业务 Session。窄带 `ChannelController` 仍根据自己的 300 ms 静默条件关闭 RF
Epoch；稍后同频信号会创建新的 Track/ChannelController/Epoch。

## 7. 细 DDC 与协议层接口

每个 Track 固定一个粗 PFB 通道，使用跟踪频率与粗通道中心之差驱动连续 NCO：

```text
residualHz = candidateOffsetHz - coarseBinCenterHz
subbandIq * exp(-j*ncoPhase)
  -> 18 kHz 低通 FIR
  -> 约 117～120 kS/s 的居中窄带 IqChunk
```

NCO 相位和 FIR 状态跨 Chunk 保留。第一版不在宽带层提前生成 48/72 kS/s 双路，
而是把约 120 kS/s 窄带流交给现有协议层：DMR/P25/dPMR/NXDN 内部转到 48 kS/s，
TETRA 转到 72 kS/s。后续性能优化再把这两路重采样提升为共享前端。

窄带 Chunk 的 `sourceSampleStart` 使用全局 PFB 输出采样编号，附加保存：

```text
widebandSourceSampleStart / End
widebandSampleRateHz
widebandCenterFrequencyHz
frequencyOffsetHz
coarseBin
coarseCenterOffsetHz
```

PDU 输出增加 `extra.wideband`，将窄带 PDU 位置映射回 SDR 宽带绝对采样位置。

## 8. 丢样、换频和背压

SDR 输入必须始终带绝对采样编号。发现下列任一条件时视为不连续：

- SDR 明确报告 `droppedSourceSamples > 0`；
- 新 Chunk 起点不等于上一 Chunk 终点；
- `discontinuity=true`；
- SDR 中心频率变化。

不连续时关闭所有现有 Track/Epoch，清除 WOLA 重叠、NCO、FIR、重采样、同步和协议
状态。换频第一版要求建立新的 `WidebandScanner`，不允许在一个连续实例中静默改变
中心频率。

采集线程不能等待协议解码。生产调度优先级应为：

1. SDR 采集和宽带环形缓冲；
2. 已锁定信道持续解码；
3. 活动信道协议分类；
4. TENTATIVE 候选；
5. 可视化和诊断输出。

离线 `scanFile` 当前按最快速度回放。真实 SDR 版本还需要固定容量宽带环形缓冲、
候选准入上限、积压高水位和 `BUFFER_OVERRUN` 事件。

## 9. MATLAB 性能基线

2026-07-14 在当前开发环境对一个 10 ms、61.44 MS/s complex-single 噪声 Chunk 测得：

```text
输入样点             614400
首次输出 PFB 帧       1185
PFB 输出矩阵          约 9.3 MiB
冷启动 PFB            约 0.123 s
冷启动无信号检测      约 0.033 s
预热后单次 PFB        约 0.055～0.070 s
```

因此当前纯 MATLAB CPU WOLA/PFB 的预热实时因子仍约为 5.5～7，仅是正确性基线，
不能宣称已经达到 60 MHz 实时处理。下一步性能路径为：

1. 用真实 60 MHz 文件分析热点和内存复制；
2. MATLAB `gpuArray`/GPU FFT 原型；
3. C++ SIMD/FFTW 或 CUDA PFB；
4. 条件允许时在 SDR FPGA 侧完成粗信道化；
5. MATLAB 只保留候选控制、协议验证和回归用途。

## 10. 实施阶段

### 阶段 W1：流式宽带骨架——已完成

- 连续 2x WOLA/PFB；
- 跨 Chunk 相位和重叠状态；
- 绝对宽带采样映射；
- 无信号、边界载波和分块一致性测试。

### 阶段 W2：候选与单频点接入——已完成

- 粗功率与细 PSD；
- 相邻 PFB 重复候选合并；
- 多载波分离；
- CandidateTracker；
- 细 DDC/FIR；
- 每候选 `RaceCoordinator`；
- `radio.wideband.scanFile/scanIq/scannerFeed`。

### 阶段 W3：真实宽带标定——下一阶段

- 构造或采集真实 60 MHz 多载波文件；
- 标定噪声、动态范围、DC spur、边缘衰减和频率漂移；
- 五制式随机频点与同时活动测试；
- 统计误候选、漏检、确认延迟和 CPU/内存高水位。

### 阶段 W4：实时性能与 SDR Source

- 固定容量宽带输入环形缓冲；
- 采集/信道化/协议任务分线程；
- GPU/C++/FPGA PFB；
- SDR 时间戳和丢样事件；
- 平均实时因子目标不高于 0.7。
