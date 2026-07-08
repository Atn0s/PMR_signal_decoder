# Python DMR_demo 到 MATLAB 迁移一致性比对

比对日期：2026-07-07

比对对象：

- Python 源项目：`/home/lzkj/lzkj_workspace/python_docs/DMR_demo`
- MATLAB 迁移项目：`/home/lzkj/lzkj_workspace/matlab_docs`

本文按文件结构、离线工作流、协议处理逻辑、输出格式、测试覆盖和未迁移能力做对照。结论基于代码静态比对，重点记录实际不一致或需要进一步确认的争议点。

## 1. 总体结论

MATLAB 项目已经较完整迁移了 Python 项目的离线窄带解码主链路：

```text
IQ 读取 -> 采样率识别 -> baseband / freq_list / blind_search 分支
-> DDC -> 48 kHz 重采样 -> 协议 registry 分发
-> 协议 decode -> postprocess -> dedup -> formatter
```

以下部分可以认为结构和主流程基本一致：

| 范围 | 一致性 | 说明 |
|------|--------|------|
| 离线 `scanner` / `scanFile` 主链路 | 高 | Python `scanner.py` + `radio/pipeline.py` 对应 MATLAB `scanner.m` + `+radio/scanFile.m` + `+radio/scanIq.m`。 |
| IQ 读取和采样率识别 | 高 | raw IQ、WAV IQ、文件名采样率推断均有 MATLAB 对应实现。 |
| 通用 FSK frontend | 高 | DDC、Welch PSD 估计中心频偏、FIR 滤波、FM 鉴频、DC removal、幅度归一化公式基本对应。 |
| 协议 registry 分发 | 高 | DMR/P25 共用 `c4fm_4fsk` frontend，dPMR 使用独立 frontend，decode/postprocess/dedup/formatter 由协议 spec 声明。 |
| P25 离线 metadata decode | 较高 | NID/HDU/LDU1/LDU2/session assembler 基本逐项迁移。 |

但 MATLAB 项目不是 Python 项目的完整等价迁移。主要缺口如下：

| 等级 | 差异点 | 影响 |
|------|--------|------|
| 高 | Python `realtime/` 宽带/实时链路未迁移到 MATLAB | MATLAB 目前只能覆盖离线文件扫描，不能等价替代 Python 的 channelizer、detector、worker、aggregator、SDR source 工作流。 |
| 高 | dPMR FS1 header frame 解码未迁移 | Python 会输出 `DPMR_HEADER`，MATLAB 当前只跑 FS2 voice 路径，可能漏掉 header 中的 src/dst、color code 和 CCH 信息。 |
| 中高 | DMR 链路层解析不完全等价 | Python 使用 `okdmr` 的 BPTC/RS/VBPTC/FLC/CSBK 解析；MATLAB 使用本地轻量实现，CSBK src/dst 当前为 0，部分 FLC/纠错能力较弱。 |
| 中 | dPMR stable color postprocess 策略不同 | Python 结合重复数、首次出现和质量分数过滤；MATLAB 只按出现次数选择 stable color，输出集合可能不同。 |
| 中 | JSON 输出语义不同 | Python JSON 默认去掉 `raw_bits`；MATLAB `radio.writeJson` 当前会写出完整 struct，可能包含 `raw_bits`。 |
| 中 | 测试覆盖不等价 | Python 有较完整 pytest 覆盖 realtime/wideband/protocol；MATLAB 目前主要是 smoke test 和 golden baseline 工具。 |
| 低 | P25 synthetic uncoded NID 特判缺失 | Python 对仅前 16 bit 有效、校验位全 0 的 synthetic NID 会强制 BCH 无效；MATLAB 直接走最近码字 BCH。主要影响合成样本或特殊测试。 |

## 2. 文件结构对照

### 2.1 顶层和公共层

| Python | MATLAB | 状态 |
|--------|--------|------|
| `scanner.py` | `scanner.m`, `+radio/scanFile.m`, `+radio/scanIq.m` | 主流程已迁移；入口形态从 CLI 变为 MATLAB 脚本/函数。 |
| `common/io.py` | `+common/readRawIq.m`, `+common/detectSampleRate.m`, `+common/isWavIq.m`, `+common/defaultIqScale.m` | 已迁移。 |
| `common/dsp.py` | `+common/fskFrontend.m`, `+common/interpLinear.m`, `+common/resampleTo.m`, `+common/welchPsd.m` | 已迁移。 |
| `common/config.py` | `+radio/defaultConfig.m`, 各协议 `config.m` | 离线参数已迁移；realtime 参数未迁移。 |
| `radio/pipeline.py` | `+radio/scanIq.m`, `+radio/processCandidate.m`, `+radio/processBaseband.m`, `+radio/psdBlindSearch.m` | 已迁移。 |
| `radio/registry.py`, `radio/protocol.py` | `+radio/protocolRegistry.m`, `+radio/decodeIqEnabled.m`, `+radio/specForProtocol.m` | 已迁移。 |
| `radio/pdu.py` | `+radio/normalizePdus.m`, `+radio/addMeta.m`, `+radio/getField.m` | 部分迁移；MATLAB 没有等价的 `PDU` dataclass，只做 struct 规范化。 |
| `radio/output.py` | `+radio/formatLines.m`, `+radio/formatPdu.m`, `+radio/writeJson.m`, `+radio/pduTable.m` | 已迁移，但 JSON `raw_bits` 处理不同。 |

### 2.2 协议目录

| Python | MATLAB | 状态 |
|--------|--------|------|
| `dmr/` | `+dmr/` | 主 decode flow 已迁移；链路层解析不是完全等价。 |
| `p25/` | `+p25/` | 主流程和多数 FEC/解析函数已迁移。 |
| `dpmr/` | `+dpmr/` | FS2 voice 路径已迁移；FS1 header 路径缺失。 |
| `core/` | 无直接对应 | Python 中 `core/` 已是 legacy facade；MATLAB 未迁移可以接受。 |

### 2.3 Python 侧未迁移到 MATLAB 的目录

| Python 目录/文件 | MATLAB 对应 | 说明 |
|------------------|-------------|------|
| `realtime/` | 无 | 未迁移。包括 `channelizer.py`、`detector.py`、`worker.py`、`aggregator.py`、`wideband_scanner.py`、`iq_source.py`、`wideband_source.py`。 |
| `utils/` | 无 | 宽带可视化、合成和调试工具未迁移。 |
| `debug/` | 无 | 调试脚本未迁移。 |
| `tests/*.py` | `+tests/runAll.m` | 测试数量和粒度不等价。 |
| `docs/superpowers/` | 无 | Python 侧计划/设计过程文档未迁移。 |

### 2.4 MATLAB 侧新增内容

| MATLAB 内容 | Python 对应 | 说明 |
|-------------|-------------|------|
| `+viz/`, `+apps/RadioAnalyzer.m`, `open_radio_analyzer.m` | 无直接对应 | MATLAB 迁移项目新增的可视化/交互工作流。 |
| `+pybackend/` | 无直接对应 | MATLAB 调 Python 项目的兼容 fallback。 |
| `+tetra/`, `examples/tetra/`, `docs/tetra/`, `outputs/tetra_symbol_debug/` | Python 源项目无对应 | MATLAB 侧新增 TETRA 实验能力，不属于 DMR_demo 迁移一致性范围。 |
| `golden/current/` | Python 扫描结果基线 | 用 Python 生成 baseline，供 MATLAB 对照。 |

## 3. 离线工作流对照

### 3.1 Python 离线主流程

关键文件：

- `scanner.py`
- `radio/pipeline.py`
- `radio/registry.py`
- `radio/output.py`

流程：

```text
scanner.scan_file()
  -> common.io.read_rawiq()
  -> common.io.detect_sample_rate()
  -> radio.pipeline.scan_iq()
       -> process_baseband() / process_candidate() / psd_blind_search()
       -> registry.decode_iq_enabled()
       -> registry.postprocess_pdus_enabled()
       -> registry.deduplicate_pdus()
  -> radio.output.print_results()
  -> radio.output.write_json()  # 可选，去掉 raw_bits
```

### 3.2 MATLAB 离线主流程

关键文件：

- `scanner.m`
- `+radio/scanFile.m`
- `+radio/scanIq.m`
- `+radio/processBaseband.m`
- `+radio/processCandidate.m`
- `+radio/decodeIqEnabled.m`
- `+radio/formatLines.m`

流程：

```text
scanner.m / radio.scanFile()
  -> common.readRawIq()
  -> common.detectSampleRate()
  -> radio.scanIq()
       -> radio.processBaseband() / radio.processCandidate() / radio.psdBlindSearch()
       -> radio.decodeNarrowband()
       -> radio.decodeIqEnabled() 或 pybackend.scanIq()
       -> radio.postprocessPdus()
       -> radio.deduplicatePdus()
  -> radio.formatLines()
  -> radio.writeJson()  # 当前保留 raw_bits
```

### 3.3 一致点

- `freq_list` 优先于 `blind_search`，否则走 centered baseband。
- 宽带候选路径都做 DDC，再按 `target_sample_rate_hz = 48000` 重采样。
- DMR/P25 frontend 复用同一个 C4FM/4FSK frontend key。
- dPMR frontend 独立。
- 协议 postprocess 和 dedup 都经 registry/spec 分发。

### 3.4 工作流差异

| 差异 | Python | MATLAB | 影响 |
|------|--------|--------|------|
| 入口形态 | CLI，可多 target，可 `--json` | MATLAB 脚本/函数/可视化 app | 使用方式不同，不影响核心离线链路。 |
| 高采样率提醒 | `scanner.py` 对高采样率 baseband 给提示 | MATLAB 没有等价提示 | 可能误把 wideband 当 centered baseband。 |
| JSON 输出 | `radio.output.json_ready()` 去掉 `raw_bits` | `radio.writeJson()` 直接 `jsonencode(pdus)` | 输出体积和字段不一致。 |
| Python fallback | 不需要 | `PipelineBackend` / `DecoderBackend` 可选 `python` | 有利于对照，但不能证明 native MATLAB 完全等价。 |

## 4. 协议处理逻辑对照

### 4.1 DMR

#### 已迁移的主流程

| Python | MATLAB | 一致性 |
|--------|--------|--------|
| `dmr.decode_flow.decode_dmr_flow()` | `+dmr/decode.m` | 高 |
| `dmr.dsp.find_sync_positions()` | `+dmr/findSyncPositions.m` | 高 |
| `dmr.dsp.recover_burst()` | `+dmr/recoverBurst.m` | 高 |
| `_lock_voice_phase()` | `+dmr/lockVoicePhase.m` | 高 |
| `_recover_stepped_burst()` | `+dmr/recoverSteppedBurstBits.m` | 高 |
| `adaptive_slice_bits()` | `+dmr/adaptiveSliceBits.m` | 高 |

DMR 同步、相位搜索、132-symbol burst 恢复、voice late-entry stride、burst dedup window 等参数和公式基本一致。MATLAB 侧通过 `common.interpLinear()` 使用 Python 兼容的 zero-based 采样位置，避免了直接 1-based 改写造成的相位偏移。

#### 主要差异和争议点

| 等级 | 差异 | Python | MATLAB | 影响 |
|------|------|--------|--------|------|
| 中高 | BPTC/FEC 能力 | `okdmr.dmrlib` 的 `BPTC19696.deinterleave_data_bits(..., repair_if_necessary=True)` | `+dmr/bptc196DataBits.m` 只按 map 抽取数据位 | MATLAB 对有误码样本的恢复能力可能低于 Python。 |
| 中高 | Full Link Control 解析 | `FullLinkControl.from_bits()` | `+dmr/parseFullLinkControl.m` 只显式处理部分 FLCO 字段 | 非常规 FLCO 或厂商字段可能解析不完整。 |
| 中高 | CSBK 解析 | `CSBK.from_bits()` 输出 source/target/csbko/feature_set | `+dmr/decodeBurst.m` 中 `decodeCsbk()` 当前 `src=0`, `dst=0`，只读 csbko/fid/last_block | CSBK PDU 信息明显弱于 Python，dedup/输出可能不同。 |
| 中 | Late Entry VBPTC/CS5 | `VBPTC12873` + `FiveBitChecksum` | `+dmr/vbptc128DataBits.m` + `+dmr/fiveBitChecksumOk.m` | 当前样本可能通过，但算法来源不完全等价。 |
| 中 | 命名枚举 | Python 使用 okdmr enum 名称 | MATLAB 用 `dmr.flcoName()` / `dmr.fidName()` 本地映射 | 新 FID/FLCO 名称可能不一致。 |

判断：DMR 可以认为“前端和 burst 恢复基本等价”，但链路层只能算“功能近似迁移”，不能声明字段级完全一致。

### 4.2 P25 Phase 1

#### 已迁移的主流程

| Python | MATLAB | 一致性 |
|--------|--------|--------|
| `p25.decode_flow.decode()` | `+p25/decode.m` | 高 |
| `p25.sync.find_frame_sync()` | `+p25/findFrameSync.m` | 高 |
| `recover_symbols_from_fs()` | `+p25/recoverSymbolsFromFs.m` | 高 |
| `slice_symbols_to_bits()` | `+p25/sliceSymbolsToBits.m` | 高 |
| `extract_nid_bits()` | `+p25/extractNidBits.m` | 高 |
| `decode_nid()` | `+p25/decodeNid.m` | 较高 |
| `decode_ldu1_lc()` | `+p25/decodeLdu1Lc.m` | 高 |
| `decode_hdu_hcw()` | `+p25/decodeHduHcw.m` | 高 |
| `decode_ldu2_es()` | `+p25/decodeLdu2Es.m` | 高 |
| `P25SessionAssembler` | `+p25/sessionInit.m`, `+p25/sessionFeed.m` | 高 |

P25 的 NID、HDU、LDU1 LC、LDU2 ES、P25_CALL session assembler 和稳定 NAC 过滤基本都已 MATLAB 化。本地 FEC 实现覆盖 BCH、RS GF(2^6)、Golay、Hamming。

#### 主要差异和争议点

| 等级 | 差异 | Python | MATLAB | 影响 |
|------|------|--------|--------|------|
| 低 | synthetic uncoded NID 特判 | `p25.nid.decode_nid()` 检测 raw info 非空且校验位全 0，直接标记 `valid_bch=False` | `+p25/decodeNid.m` 直接调用 `bch6316Decode()` | 可能影响合成测试或特殊未编码输入。 |
| 低 | 数据结构 | Python 使用 dataclass，如 `P25NID`, `HeaderCodeWord`, `LinkControl` | MATLAB 使用 struct | 语义基本一致，但下游字段类型可能有细小差异。 |

判断：P25 是三种协议中迁移一致性最高的一部分，建议后续重点用 golden vector 和边界单测确认数值完全一致。

### 4.3 dPMR

#### 已迁移的主流程

| Python | MATLAB | 一致性 |
|--------|--------|--------|
| `dpmr.dsp.find_dpmr_sync()` | `+dpmr/findSync.m` | 高 |
| `recover_frame_symbol_candidates()` | `+dpmr/recoverFrameSymbolCandidates.m` | 高 |
| `decode_voice_symbols()` | `+dpmr/decodeVoiceSymbols.m` | 高 |
| `decode_cch()` | `+dpmr/decodeCch.m` | 较高 |
| `DPMRSessionAssembler` | `+dpmr/sessionInit.m`, `+dpmr/sessionFeed.m` | 较高 |

FS2 voice decode 的同步搜索、symbol candidate 评分、CCH/Color Code 解析、session 拼接已有 MATLAB 对应实现。

#### 主要差异和争议点

| 等级 | 差异 | Python | MATLAB | 影响 |
|------|------|--------|--------|------|
| 高 | FS1 header frame 缺失 | `dpmr.decode_flow._decode_header_frame()` 先找 FS1，输出 `DPMR_HEADER` | `+dpmr/decode.m` 只找 `SyncTypes={'FS2'}` 并输出 `DPMR_VOICE` | MATLAB 会漏掉 Python 的 header PDU、header CCH、header color candidate、header src/dst。 |
| 中 | 配置字段未完整暴露 | `DPMRConfig` 有 phase/sps/sample window/candidate limit 等字段 | `+dpmr/config.m` 只保留部分字段，`+dpmr/decode.m` 中多处硬编码默认值 | 当前默认值基本相同，但后续调参无法从 config 统一管理。 |
| 中 | stable color postprocess 不一致 | `filter_stable_pdus()` 按 repeats、first_seen、quality score 选 stable color，并可过滤低质量 PDU，写入 `stable_color_repeats` | `+dpmr/postprocess.m` 只按出现次数选 stable color，未做质量门控，未写 repeats | 噪声样本、多候选样本下输出集合可能不同。 |
| 低中 | `raw_bits` 表示不同 | Python `raw_bits` 是 bytes，JSON 输出会删除 | MATLAB voice `raw_bits` 当前是 bit 向量，并可能进入 JSON | 输出比较需要归一化。 |

判断：dPMR 当前只能说 FS2 voice 路径基本迁移，不能认为完整迁移了 Python dPMR decode flow。

## 5. realtime / wideband 工作流

Python 源项目有完整 realtime/宽带链路：

| Python 文件 | 职责 | MATLAB 状态 |
|-------------|------|-------------|
| `realtime/channelizer.py` | Polyphase DFT channelizer，含 2x oversampled WOLA 路径 | 未迁移 |
| `realtime/detector.py` | 宽带/子带 active channel detector | 未迁移 |
| `realtime/worker.py` | window 内 DDC、重采样、协议 decode，标记 `_fo_hz` / `_window_id` | 未迁移 |
| `realtime/aggregator.py` | DMR session 聚合，按频率桶/src/dst 合并并关闭 call | 未迁移 |
| `realtime/wideband_scanner.py` | 一次性宽带 capture channelize 后逐窗口解码 | 未迁移 |
| `realtime/iq_source.py`, `realtime/wideband_source.py` | 输入源抽象 | 未迁移 |
| `realtime/scanner_rt.py` | realtime 扫描入口 | 未迁移 |

MATLAB 侧有 `radio.psdBlindSearch()` 和 `processCandidate()`，可以做离线 PSD 候选搜索，但这不等价于 Python 的实时/宽带工作流：

- 没有 polyphase channelizer。
- 没有窗口化 detector。
- 没有跨窗口 session aggregator。
- 没有 `_window_id` / `_rf_hz` 语义。
- 没有 detector close / timeout close 的 call 生命周期。

判断：如果迁移目标包含 Python 项目的 realtime/宽带能力，这部分仍是未迁移状态。

## 6. 输出格式和 PDU schema

### 一致点

三种协议都归一到类似字段：

```text
protocol, type, src, dst, ts, flco, fid, extra, raw_bits
```

宽带候选频偏在 Python 中以 `_fo_hz` 暴露，MATLAB 中用 `fo_hz` 字段，并通过 `radio.getField()` 兼容 `_fo_hz` / `x_fo_hz` / `fo_hz`。

### 差异点

| 等级 | 差异 | Python | MATLAB | 建议 |
|------|------|--------|--------|------|
| 中 | JSON 是否包含 `raw_bits` | `radio.output.json_ready()` 调 `include_raw_bits=False` | `radio.writeJson()` 直接编码 struct | 若 JSON 用于回归，建议 MATLAB 写出前也剔除 `raw_bits`。 |
| 低 | metadata 字段名 | `_fo_hz` | `fo_hz`，兼容读取 `_fo_hz` | 文档和 golden 比较脚本中需做别名归一。 |
| 低 | `PDU` 对象 | Python 有 dict-compatible dataclass | MATLAB 只有 struct normalize | 可接受，但测试要覆盖字段缺省值。 |

## 7. 测试覆盖对照

Python 项目测试覆盖包括：

- protocol dispatch
- radio pipeline
- PDU schema
- DMR CLI/offline
- P25 sync/NID/DSP/framing/decoder/full LC/e2e
- dPMR decoder/CCH/color code
- realtime worker/ring buffer/detector/aggregator/e2e
- channelizer/wideband source/wideband e2e

MATLAB 当前测试入口：

- `+tests/runAll.m`
- `examples/runGoldenRegression.m`
- `tools/buildGoldenVectors.m`
- `golden/current/*.json`

主要差异：

| 等级 | 差异 | 影响 |
|------|------|------|
| 中 | MATLAB `runAll` 是 smoke test，主要验证函数可运行和返回 struct | 不能覆盖协议边界条件、纠错、格式化和 wideband 行为。 |
| 中 | golden baseline 已有，但 `examples/runGoldenRegression.m` 当前只调用 `tests.runAll()` | 没有实际逐字段比较 MATLAB 输出和 Python golden JSON。 |
| 高 | realtime/wideband 测试无 MATLAB 对应 | 相关能力未迁移，也无法回归。 |

建议将 golden regression 做成真正的比较：

```text
for each golden/current/*.json:
  -> radio.scanFile(..., PipelineBackend='matlab', DecoderBackend='matlab')
  -> 去掉 raw_bits
  -> 归一 fo_hz/_fo_hz、浮点容差、字段顺序
  -> 对比协议/type/src/dst/flco/fid/extra 关键字段
```

## 8. 需要优先处理的不一致

### P0：确认迁移范围

如果目标只是 MATLAB 离线窄带分析工具，当前迁移主线基本成立；如果目标是完整替代 Python DMR_demo，则 realtime/宽带链路必须单独规划迁移。

### P1：补 dPMR FS1 header frame

需从 Python 迁移：

- `dpmr.decode_flow._decode_header_frame()`
- `decode_header_payload()`
- header quality score
- header CCH/color offsets
- `DPMR_HEADER` PDU 输出字段

MATLAB 侧已有 `dpmr.findSync()`、`dpmr.recoverFrameSymbolCandidates()`、`dpmr.decodeCch()`、`dpmr.getColorCode()`，补 header path 的工作量相对可控。

### P1：补真实 golden regression

当前已有 Python baseline 文件，但 MATLAB 回归入口未逐字段比较。建议先补比较器，再用它驱动后续差异修复。

### P2：增强 DMR 链路层

优先级建议：

1. 让 MATLAB `decodeCsbk()` 解析 src/dst/csbko/feature_set，接近 Python `CSBK.from_bits()` 输出。
2. 明确 `bptc196DataBits()` 是否需要 repair；如果需要，补 BPTC 修复或在文档里声明 MATLAB 仅支持无修复抽取。
3. 校验 `fiveBitChecksumOk()` 与 okdmr `FiveBitChecksum.verify()` 在样本和构造向量上的一致性。
4. 扩充 `flcoName()` / `fidName()` 映射。

### P2：统一 dPMR postprocess

将 MATLAB `+dpmr/postprocess.m` 对齐 Python `filter_stable_pdus()`：

- 记录 `stable_color_repeats`。
- 按 first_seen 和 quality score tie-break。
- 当 stable color 中存在 high/medium 质量 PDU 时，过滤 low/none。

### P3：统一 JSON 输出

如果 JSON 用作下游接口或回归基线，建议 MATLAB `radio.writeJson()` 默认去掉 `raw_bits`，或提供参数控制。

### P3：补 P25 synthetic uncoded NID 特判

影响面较小，但容易补齐：在 `+p25/decodeNid.m` 中对 `bits(1:16)` 非空且 `bits(17:64)` 全 0 的情况设置 `valid_bch=false`、`corrected=false`，并直接使用 raw info。

## 9. 当前可认为一致的核心映射

| 功能 | Python | MATLAB |
|------|--------|--------|
| 默认目标采样率 | `RadioConfig.target_sample_rate_hz = 48000` | `radio.defaultConfig().targetSampleRateHz = 48000` |
| sample rate tolerance | `1.0 Hz` | `1.0 Hz` |
| PSD threshold | `15 dB` | `15 dB` |
| PSD nperseg | `4096` | `4096` |
| DMR/P25 symbol rate | `4800` | `4800` |
| dPMR symbol rate | `2400` | `2400` |
| DMR/P25 samples per symbol | `10` | `10` |
| dPMR samples per symbol | `20` | `20` |
| DMR voice burst stride | `2880 samples` | `2880 samples` |
| P25 stable NAC filter | `min_count=5`, `min_ratio=0.4` | `minCount=5`, `minRatio=0.4` |
| dPMR sync threshold | `0.82` | `0.82` |

## 10. 结论

MATLAB 项目已经完成了 Python DMR_demo 的离线扫描主架构迁移，并且 DMR/P25/dPMR 三个协议都有 native MATLAB decoder。若只按 centered baseband 或简单 `freq_list` / PSD blind search 的离线样本来看，结构、参数和调用顺序总体一致。

不能忽略的差异是：

1. Python 的 realtime/宽带工程链路没有迁移。
2. dPMR 缺 FS1 header path。
3. DMR 链路层不是 okdmr 的完整等价实现。
4. MATLAB golden regression 目前还不是逐字段对比。
5. JSON/PDU 细节存在小差异。

因此，当前状态更适合描述为：

```text
MATLAB 已迁移 Python 项目的离线窄带/候选扫描主链路和主要 metadata 解码能力；
但尚未达到 Python DMR_demo 全工程能力和全部协议字段行为的完全等价。
```
