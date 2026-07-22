# 使用指南

当前只保留两个正式入口：

1. `radio_parallel_frontend.m`：带 UI 的 1× 实时文件回放与多频点解码；
2. `radio.scanFile`：不创建 UI 的离线文件解码。

两者都只调用原生 MATLAB 并行解码链。运行时不再包含 Python 解码桥，也不会在
并行池不可用时切换执行方式。

## 实时 UI 入口

```matlab
startup
radio_parallel_frontend
```

操作顺序：

1. 打开 BVSP、交错 RAW IQ 或双声道 IQ WAV；
2. RAW IQ 没有文件头时填写采样率，中心频率可以留空；
3. 点击 **Preview 1x**；
4. 在频谱上选择最多五个载频；
5. 点击 **Run decode**；
6. 点击 **Clear carriers** 可在不中断文件回放和频谱的情况下重新选频。

入口使用共享 IQ 环、后台频谱 Actor、一个融合 DDC worker 和协议 process pool。
文件生产按墙钟 1× 前进，不会为了等待解码而主动降低速度。

支持三种回放方式：

- `once`：文件只播放一次；
- `continuous-test`：把多次文件循环接在同一逻辑时间线上；
- `epoch-repeat`：循环之间插入静默和不连续标记，每次循环形成独立 RF Epoch。

自动化测试可以隐藏窗口并用参数选频：

```matlab
app = radio_parallel_frontend( ...
    'Visible', 'off', ...
    'DefaultFile', '/path/to/capture.bvsp', ...
    'ReplayMode', 'once', ...
    'ProtocolNames', {}, ...
    'NumWorkers', 5);
cleanup = onCleanup(@() app.Close());

app.StartPreview('StartTimer', false);
app.Step(8);
app.SelectOffsetHz(-300e3, 'Refine', false);
app.SelectOffsetHz(+150e3, 'Refine', false);
app.StartDecode('StartTimer', false);
state = app.Step(500);
```

`Visible='off'` 只是隐藏 MATLAB 窗口；调用 `Close` 或直接关闭窗口会释放 timer、
共享环和 worker 任务，不会让会话在后台继续。处理状态已经拆到
`radio.live.parallelSession*`，因此后续迁移到 C++ 时无需保留 UI 控件层。当前工程中需要
完全无 UI 的文件处理时，直接使用下面的 `radio.scanFile`。

## 离线文件入口

### 已居中基带

```matlab
[pdus, report] = radio.scanFile('/path/to/centered.rawiq', ...
    'ExecutionMode', 'parallel', ...
    'ProtocolNames', {}, ...              % 空集合表示启用全部协议
    'SampleRate', 78125);
```

`parallel` 要求输入只包含一个已移到复基带中心的信道。解码器按 RF Epoch 组织结果，
每个 Epoch 独立完成 DMR、P25、dPMR、NXDN、TETRA 协议竞争。

### 宽带文件中的一个已知载频

```matlab
[pdus, report] = radio.scanFile('/path/to/capture.bvsp', ...
    'ExecutionMode', 'tuned-parallel', ...
    'FreqList', 1235200, ...              % 相对文件中心的频偏，Hz
    'ProtocolNames', {});
```

`tuned-parallel` 接受一个相对频偏，执行有状态 NCO 下变频、抗混叠滤波和整数抽取，
然后进入同一套并行协议竞争链。BVSP 的采样率和中心频率从文件头读取；RAW IQ 可通过
`SampleRate` 和 `CenterFrequencyHz` 指定。

### 宽带自动发现

```matlab
[pdus, report] = radio.scanFile('/path/to/wideband.rawiq', ...
    'ExecutionMode', 'wideband', ...
    'SampleRate', 61.44e6, ...
    'CenterFrequencyHz', 430e6);
```

`wideband` 使用流式 2× 过采样 WOLA/PFB 发现和跟踪载频，再为每个活动载频创建协议
竞争。该实现用于正确性验证；61.44 MS/s 的 MATLAB CPU 路径目前不保证实时。

## 进程池要求

协议识别固定使用 process pool，`NumWorkers` 控制协议 worker 数量。池无法创建、
规模不足或当前已运行 thread pool 时，接口直接报错，不改变执行语义。

实时 UI 还需要一个独立的融合 DDC worker，因此默认需要六个进程：五个协议 worker
加一个 DDC worker。

## 输出

`pdus` 是统一 PDU 结构数组；`report` 包含执行模式、Epoch、选中协议、时间范围和统计
信息。常用输出辅助函数：

```matlab
lines = radio.formatLines(pdus);
radio.writeJson(pdus, 'decoded.json');
```

`Deduplicate=false` 可保留重复帧用于调试，默认执行语义不会因此改变。

## 样例与测试

外部 IQ 样例目录通过环境变量指定：

```text
RADIO_SAMPLE_DATA_ROOT=/path/to/sample/data
```

未设置时使用本仓库的 `signal_data/` 目录。运行完整回归：

```matlab
tests.runAll
```

协议包内的调试函数、`viz.analyzeFile` 和 `examples/` 用于诊断或示例，
不是额外的正式解码入口。
