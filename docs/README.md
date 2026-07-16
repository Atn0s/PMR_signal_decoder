# 项目文档导航

这里汇总 MATLAB 多制式无线电解码项目的使用说明、架构设计、协议资料、
实现与验收记录以及迁移状态。

返回[项目首页](../README.md)。

## 快速入口

- 想运行项目或查找调用入口：阅读[使用说明](guides/USAGE.md)。
- 想理解从 IQ 输入到 Dibit 的完整链路：阅读[信号输入到原始 Dibit 恢复实现说明](architecture/信号输入到原始Dibit恢复实现说明.md)。
- 想理解五制式实时识别：阅读[实时微批处理五制式并行识别架构设计](architecture/实时微批处理五制式并行识别架构设计.md)。
- 想了解实时选频界面：先看[前端设计](architecture/实时频谱选频与循环回放解码前端设计.md)，再看[实现记录](records/frontend/实时频谱选频与循环回放解码前端实现记录.md)。
- 想查协议细节：进入 [NXDN](protocols/nxdn/README.md) 或 [TETRA](protocols/tetra/README.md) 文档索引。
- 想了解 Python 到 MATLAB 的迁移进度：阅读[迁移状态](migration/MIGRATION_STATUS.md)。

## 目录结构

```text
docs/
├── README.md            文档总入口
├── guides/              使用方法和运行入口
├── architecture/        当前架构、数据流和设计方案
├── protocols/           协议专属参考、方案和调试资料
│   ├── nxdn/
│   └── tetra/
├── records/             阶段性实现和验证记录
│   ├── frontend/
│   ├── recognition/
│   └── validation/
└── migration/           Python 到 MATLAB 的迁移资料
```

## 使用指南

- [项目使用说明](guides/USAGE.md)：脚本入口、实时前端、编程接口、协议竞速和 JSON 输出。

## 架构与设计

- [信号输入到原始 Dibit 恢复实现说明](architecture/信号输入到原始Dibit恢复实现说明.md)：当前公共信号处理链路。
- [已知频点多制式并行识别方案](architecture/已知频点多制式并行识别方案.md)：已知载频、未知制式场景的总体方案。
- [实时微批处理五制式并行识别架构设计](architecture/实时微批处理五制式并行识别架构设计.md)：流式输入、Probe、Epoch、健康监控和协议切换。
- [实时频谱选频与循环回放解码前端设计](architecture/实时频谱选频与循环回放解码前端设计.md)：交互式选频和文件回放前端设计。
- [60 MHz 宽带实时 IQ 信道化与并行解码设计](architecture/60MHz宽带实时IQ信道化与并行解码设计.md)：宽带 PFB、候选跟踪和细 DDC 架构。

## 协议资料

- [NXDN 文档索引](protocols/nxdn/README.md)：NXDN96 空口结构、独立解码方案和盲扫调试记录。
- [TETRA 文档索引](protocols/tetra/README.md)：当前工作流、DMO 链路层、扫描实验和阶段状态。

## 前端实现记录

- [已知载频 DDC 过渡模块实现记录](records/frontend/已知载频DDC过渡模块实现记录.md)
- [离线基带并行接入 scanner 实现记录](records/frontend/离线基带并行接入scanner实现记录.md)
- [宽带流式前端阶段一实现记录](records/frontend/宽带流式前端阶段一实现记录.md)
- [实时频谱选频与循环回放解码前端实现记录](records/frontend/实时频谱选频与循环回放解码前端实现记录.md)

## 识别链实现记录

- [并行 Probe 竞速实现记录](records/recognition/并行Probe竞速实现记录.md)
- [赢家缓冲追赶实现记录](records/recognition/赢家缓冲追赶实现记录.md)
- [持续解码重叠适配层](records/recognition/持续解码重叠适配层.md)
- [NXDN96 真正增量解码与持久 Worker 阶段记录](records/recognition/NXDN96真正增量解码与持久Worker阶段记录.md)
- [多协议真正增量解码与持久 Worker 第二阶段记录](records/recognition/多协议真正增量解码与持久Worker第二阶段记录.md)
- [解码健康与重新分类实现记录](records/recognition/解码健康与重新分类实现记录.md)
- [离线多 Epoch 识别与上报实现记录](records/recognition/离线多Epoch识别与上报实现记录.md)

## 验证与验收记录

- [五制式 Probe 窗口初始表征](records/validation/五制式Probe窗口初始表征.md)
- [2.5 MHz 五路近同步信号合成与验收](records/validation/2.5MHz五路近同步信号合成与验收.md)
- [2.5 MHz 一倍速多载波并行前端修正与验收记录](records/validation/2.5MHz一倍速多载波并行前端修正与验收记录.md)

## 迁移资料

- [Migration Status](migration/MIGRATION_STATUS.md)：分阶段迁移状态和增量同步记录。
- [Python 与 MATLAB 迁移对照](migration/python_matlab_migration_comparison.md)：工作流、协议逻辑、输出和测试覆盖差异。

## 维护约定

- `guides/` 和 `architecture/` 描述当前推荐用法与当前架构，代码变化后应同步更新。
- `protocols/` 保存协议专属的参考、实现边界和调试资料。
- `records/` 保存阶段性实现、实验和验收结论；历史结论应保留日期或阶段背景。
- 只有确认已经失效且没有参考价值的资料才归档或删除。
- 新文档应同时加入本索引；文档之间使用相对链接，避免依赖本机绝对路径。
