# TETRA 全文件多窗口扫描

本文描述当前新增的 TETRA-only 全文件扫描实验入口。它暂时不接入
`scanner.m` 或 `radio.scanFile` 的统一分发，目的是先把单模式链路跑通、观察
整段录音中的 DSB/DNB/STCH/TCH candidate 时序。

## 入口

示例脚本：

```matlab
run('examples/tetra/tetra_full_file_scan.m')
```

直接调用：

```matlab
result = tetra.scanFileWindows(file, ...
    'OutputDir', 'outputs/tetra_full_file_scan/interactive_latest', ...
    'ShowProgress', true);
```

返回的 `result` 主要字段：

```text
result.windows        扫描窗口起止时间、功率、切片信息
result.windowReports  每个窗口的解调计数和质量指标
result.pdus           去重后的全文件 TETRA 事件 + session 汇总
result.lines          和 radio.formatLines 类似的可读文本
result.summary        全文件统计
```

指定 `OutputDir` 后会写出：

```text
full_file_scan_summary.mat
tetra_pdus.json
tetra_lines.txt
windows.csv
```

## 切窗策略

流程是：

```text
IQ 文件 -> 识别采样率 -> 整段重采样到 72 kHz
-> 1 ms 功率包络 -> 门限检测活动区
-> 合并相隔很近的活动 run
-> 按 6 s 窗口、1.25 s 重叠切片
-> 每个窗口复用同一套 TETRA 物理层和 DMO 控制解码
-> 去重合并事件 -> 重建全文件 DMO session
```

默认参数在 `+tetra/config.m`：

```text
fullScanPrePadSec     = 0.050
fullScanPostPadSec    = 0.250
fullScanMergeGapSec   = 0.150
fullScanWindowSec     = 6.000
fullScanOverlapSec    = 1.250
fullScanMinWindowSec  = 0.250
```

这样设计的原因：

```text
1. TETRA DMO 后续业务 burst 可能是稀疏出现的，不能只截取最强的同步建立段。
2. 窗口需要足够长，尽量让 DSB 同步和后续 DNB 业务处在同一解码上下文内。
3. 窗口之间需要重叠，避免 slot 或训练序列恰好落在窗口边界处丢失。
4. 当前训练序列搜索还不是流式状态机，所以先用离线多窗口扫描验证整段结构。
```

## 当前默认样本结果

样本：

```text
/home/lzkj/lzkj_workspace/python_docs/DMR_demo/data/tetra_dmo_20240413_430050000_baseband.wav
```

当前运行结果：

```text
duration:        37.970 s
scan windows:    7
decoded windows: 7
PDUs/events:     687
DMAC-SYNC:       146
STCH:            51
SCH/F:           0
TCH candidates:  488
sessions:        2
```

两条 session 汇总：

```text
SRC=6087104 DST=100 START=5.197s  END=6.146s  DUR=0.949s  RELEASE=DM-RELEASE
SRC=3418531 DST=100 START=6.727s  END=34.762s DUR=28.036s RELEASE=DM-RELEASE
```

其中 `TCH candidates` 表示 normal_1 或未被 stealing 的 BKN 被识别为业务候选，
当前阶段不做语音内容解码。

## 和单窗口调试的关系

`tetra.symbolDebug` 仍然用于图像分析和物理层调试，它默认只选择一个 active
window，并生成各处理阶段图窗。

`tetra.scanFileWindows` 不生成图，重点是全文件事件输出。它内部每个窗口调用：

```matlab
tetra.decodeIqWindow(...)
```

这个窗口级函数和 `tetra.decode` 共用同一套解调和 DMO 控制解析逻辑，避免单窗口
调试与全文件扫描出现两套不同实现。

## 当前边界

当前全文件扫描仍然是离线多窗口实验，不是完整流式接收机：

```text
1. 窗口之间只做事件去重和 session 重建，尚未实现跨窗口的完整 MAC 状态机。
2. TCH/VOICE 不解码，只输出 TCH candidate 元数据。
3. SCH/F 当前会尝试解码，未通过校验时保留为 TCH candidate。
4. 后续可以把训练序列搜索、DCC 上下文和 DMO session 状态机改成真正流式。
```
