# 迁移状态

## 当前基线（2026-07-22）

项目已经收敛为原生 MATLAB 并行解码实现：

- 实时 UI 入口：`radio_parallel_frontend.m`；
- 离线文件入口：`radio.scanFile`；
- 支持 `parallel`、`tuned-parallel`、`wideband` 三种并行拓扑；
- DMR、P25、dPMR、NXDN96、TETRA 均走 MATLAB 协议实现；
- 并行池不可用时直接报错，不改变执行方式；
- 外部样例只通过 `RADIO_SAMPLE_DATA_ROOT` 定位。

早期迁移用的 Python 解码桥、Python 命令行包装、串行调度器、串行降级分支，以及
`radio_frontend.m`、`open_radio_analyzer.m`、`apps.RadioAnalyzer` 已删除。`golden/`
中的 JSON 只作为历史回归数据保留，不再由运行时调用 Python 生成。

## 已完成模块

- 公共 DSP：IQ 读取、采样率识别、重采样、PSD、4FSK 前端；
- 协议包边界：DMR、P25、dPMR、NXDN96、TETRA 的配置、解码、后处理和格式化；
- 流式识别：RF Epoch、并行 Probe、赢家追赶、持久锁定解码；
- 已知载频：有状态融合 DDC 和多载频扫描；
- 宽带发现：2× 过采样 WOLA/PFB、候选跟踪、精细 DDC；
- 实时回放：共享 IQ 环、文件生产 Actor、频谱 Actor、DDC Actor 和 UI 无关会话状态；
- 回归：协议样例、流式生命周期、并行调度、实时前端分层和多载频验收。

## 入口边界

`radio_parallel_frontend` 负责交互式 1× 文件回放。UI 只负责输入、选频和状态展示，
处理生命周期位于 `radio.live.parallelSession*`。关闭 UI 会关闭对应会话；自动化可以用
`Visible='off'` 隐藏窗口，但完全无 UI 的文件处理应调用 `radio.scanFile`。

顶层 `scanner.m`、协议 CLI 和 `carrier_scope.m` 已删除。协议包内的调试函数、
`viz.analyzeFile` 和 `examples/` 仅用于诊断与示例。

## 尚未纳入当前范围

- 生产级 SDR 数据源、硬件时间戳和设备溢出策略；
- 61.44 MS/s 宽带链的实时加速；
- C++ UI/数据源集成；
- 更完整的 DMR FEC、CSBK 与链路控制覆盖；
- 声码器音频输出。

旧的设计和验证文档仍保留研发过程数据。凡其中提到已删除的 UI、Python 桥或串行
调度，均属于历史阶段，不代表当前可用接口。
