# 离线基带并行接入 scanner 实现记录

> 本文记录“输入已经位于基带”的阶段性基线。后续已增加单载频宽带 DDC 过渡层，见
> `docs/已知载频DDC过渡模块实现记录.md`；本文中的“尚未包含非零 FreqList DDC”只描述
> 当时的实现状态。

## 1. 本阶段范围

本阶段把五制式 Probe Race 接入 `scanner.m`，只处理一个已经下变频到复数基带附近的
离线 IQ 文件。当前不包含宽带 PSD 候选搜索、非零 `FreqList` DDC、多频点并行或 SDR
实时源。

串行扫描仍是默认兼容基线。并行模式通过以下配置显式启用：

```matlab
EXECUTION_MODE = 'parallel';
PROTOCOLS = {};       % DMR/P25/dPMR/NXDN/TETRA
FREQ_LIST = [];
BLIND_SEARCH = false;
```

## 2. 执行流程

```text
离线复数 IQ
  -> 100 ms 微块与活动检测
  -> 按 offHangSec 将文件切分为独立 RF Epoch
  -> 每个 Epoch 从活动候选起点构造共享、渐进增长的 IQ 快照
  -> 到达各制式首探/后续窗口时，向进程池提交可运行 Probe
  -> 每个 Epoch 独立确认赢家、AMBIGUOUS 或 REJECTED_ALL
  -> 唯一赢家从该 Epoch 的 pre-trigger 起点完整解码
  -> 协议后处理、可选去重、格式化与 scanner 图形输出
```

离线适配层先完成活动分段，再按时间顺序处理各 Epoch，并等待当前一代 Probe 完成后
推进该 Epoch。这样磁盘读取不会越过异步 worker，也不会因环形缓冲推进过快而丢失
分类前数据。相同发射机跨静默边界不合并，PDU 去重也不会跨 Epoch 执行。

空 `PROTOCOLS` 在并行模式下显式注册五种 Probe，不沿用串行 centered 模式为了性能而
排除 TETRA 的默认集合。单独指定制式仍可用于诊断。

## 3. 入口和报告

- `radio.scanFile(..., 'ExecutionMode', 'parallel')`：公共文件入口；
- `radio.stream.scanBasebandFile`：文件读取与多 Epoch 入口；
- `radio.stream.scanBasebandIqEpochs`：活动分段、逐 Epoch 识别和完整解码；
- `radio.stream.detectActivityEpochs`：独立 RF Epoch 边界检测；
- `radio.stream.identifyBasebandIq`：只执行活动检测和协议竞速；
- `viz.analyzeFile`：透传并行参数并在 `result.scanReport` 返回报告；
- `scanner.m`：通过 `EXECUTION_MODE` 切换串行/并行。

`scanReport` 记录 outcome、赢家、实际执行模式、串行降级原因、Epoch 列表、分类样本
区间、关闭原因、PDU 索引、竞速历史、分类/解码耗时和 PDU 数量。如果进程池不可创建，结果会标记为
`serial_fallback`；这只改变调度方式，不改变证据规则。

## 4. 频偏边界的含义

当前可以对外声明的是“五种代表性录音均验证到残余频偏 ±2 kHz”，不能把它解释为
算法的真实失效极限。这个数值来自 `radio.stream.characterizeProbeWindows` 的注入试验：

```matlab
xOffset = x .* exp(1j * 2*pi * deltaF * (0:numel(x)-1).' / fs);
```

分别注入 `-2000、-1000、0、+1000、+2000 Hz`，再执行相同的渐进 Probe，并且只有协议
强证据通过才记为成功。扫描在 ±2 kHz 处停止，因此现有数据证明的是共同可用范围至少为
±2 kHz，而不是 ±2 kHz 之外必然失败。

并行调度本身不增加也不减小频偏容限；实际边界由各制式的重采样、信道滤波、PSD 粗频偏
估计和残余频偏校正共同决定。生产边界需要扩展频偏扫描直到失败，并在多设备、多录音、
多个 SNR、随机截取和采样率误差条件下，以预定成功率（例如 99%）统计共同边界。

## 5. 验证结果

自动测试 `tests.runStreamingPhase8/9` 覆盖公共入口约束、默认五制式集合、进程池/降级
状态、静默边界、相同发射机独立上报、协议切换 rollover 和真实 NXDN 完整解析。
阶段 1–9 与原串行五制式回归全部通过。

五种完整代表性文件通过默认五制式进程池竞速：DMR 3 个 Epoch、P25 2 个、dPMR 1 个、
NXDN 4 个、TETRA 2 个，所有 Epoch 均确认到正确制式。由于去重不再跨 Epoch，重复
发射会保留为独立 PDU；这与旧整文件语义去重的数量不可直接比较。

## 6. 尚未包含

1. 非零频点的流式 DDC 和双采样率 48/72 kHz 分支；
2. 宽带 PSD 候选到单信道 Race 的适配；
3. TETRA 宽带盲检候选器；
4. UNKNOWN 退避和 AMBIGUOUS 二次判决；
5. 真正因果、带 DSP 状态的增量解码器；
6. SDR Source 和实时背压策略。
