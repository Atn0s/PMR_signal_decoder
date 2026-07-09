# TETRA 文档索引

当前 TETRA 相关文档：

```text
current_decode_workflow.md  当前 TETRA 解码工作流程，重点说明 DMAC-SYNC、DCC、STCH
full_file_scan.md          TETRA-only 全文件多窗口扫描实验入口和当前样本结果
link_layer_decode_plan.md   TETRA DMO 链路层完整解码方案
phase1_status.md           TETRA 第一阶段状态、样本结果和当前边界
symbol_debug.md            tetra_symbol_debug 图像和输出说明
```

建议先读：

```text
docs/tetra/current_decode_workflow.md
```

该文档描述从 IQ 到 hard bit、DSB/DNB 识别、BKN 提取、完整 DMAC-SYNC、
DCC、STCH、SCH/F 尝试解码，以及当前 TCH/VOICE 边界。

统一输出入口：

```matlab
pdus = radio.scanFile(file, 'ProtocolNames', {'tetra'});
lines = radio.formatLines(pdus);
```

或者运行：

```matlab
run('tetra_cli.m')
```

TETRA 单模式全文件多窗口实验入口：

```matlab
run('examples/tetra/tetra_full_file_scan.m')
```

它暂时不接入 `scanner.m`，用于先验证整段 DMO 文件中的 DSB/DNB/STCH/TCH
candidate 时序和 session 汇总。

进入链路层实现前，再读：

```text
docs/tetra/link_layer_decode_plan.md
```
