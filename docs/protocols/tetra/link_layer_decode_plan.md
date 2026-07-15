# TETRA DMO 链路层解码方案

本文给出从当前 TETRA 物理层实验进入 DMO 链路层完整解码的实现方案。

当前已完成：

```text
IQ -> 72 kHz -> RRC -> timing -> pi/4-DQPSK hard bits
-> DMO DSB/DNB confirmed bursts
-> BKN1/BKN2 payload extraction
-> DSB BKN1/SCH-S decode
-> FN/TN timing assignment
```

下一阶段目标：

```text
1. 解 DSB BKN2/SCH-H。
2. 合成完整 DMAC-SYNC。
3. 从 DMAC-SYNC 建立 DMO 上下文和 DCC。
4. 解 DNB normal_2 的 STCH。
5. 解 DNB normal_1 的 SCH/F 或 TCH。
6. 建立 MAC PDU 输出。
```

状态机决策：当前离线阶段只做事件输出和 session 重建，不继续实现完整 MAC
状态机。后续进入实时处理时，系统也会采用“采集约 1 s 信号后批处理”的方式，
因此应统一实现 batch-oriented DMO context，而不是逐 sample 的流式状态机。
该批处理上下文用于在批次之间保存 FN/TN、DCC、source/destination、MNI、
当前 session 和事件去重键。当前阶段暂不考虑。

## 关键原则

链路层不应该消费整段 active-window hard bit stream。链路层输入应是已确认的
burst payload：

```text
DSB BKN1 -> SCH/S
DSB BKN2 -> SCH/H
DNB normal_2 BKN1 -> STCH
DNB normal_2 BKN2 -> TCH or STCH
DNB normal_1 BKN1+BKN2 -> TCH or SCH/F
```

burst 外 bit、guard/ramp bit、跨 burst/gap 的 differential transition 不进入
链路层。

当前实现状态：`pi4dqpskDecision` 输出每个 hard bit 的 validity/reliability，
`inferDmoBursts` 将 validity 映射到 confirmed slot，`extractDmoPayload` 在每个
BKN block 上记录 `validRatio`。低于 `dmoPayloadMinValidRatio` 的 BKN block 会
被跳过，不进入 SCH/S、SCH/H、STCH 或 SCH/F 解码。

## 阶段 1：通用信令块解码器

当前 `+tetra/decodeSchS.m` 只支持 SCH/S：

```text
120 scrambled bits
-> descramble
-> (120,11) deinterleave
-> RCPC rate 2/3 hard Viterbi
-> 60 type-1 bits + 16 parity + 4 tail
```

下一步应抽象为通用函数：

```matlab
decoded = tetra.decodeDmoSignallingBlock(bits, kind, dccBits, cfg)
```

建议支持：

```text
kind = 'SCH/S'
  input:       120 bits
  type-1:       60 bits
  type-2:       80 bits
  interleaver: (120,11)

kind = 'SCH/H'
  input:       216 bits
  type-1:      124 bits
  type-2:      144 bits
  interleaver: (216,101)

kind = 'STCH'
  input:       216 bits
  type-1:      124 bits
  type-2:      144 bits
  interleaver: (216,101)

kind = 'SCH/F'
  input:       432 bits
  type-1:      268 bits
  type-2:      288 bits
  interleaver: (432,103)
```

输出字段：

```text
logicalChannel
inputBits
descrambledBits
type3Bits
type2Bits
type1Bits
blockCodeErrors
tailErrors
rcpcMetric
ok
```

验收：

```text
1. 现有 SCH/S 测试结果保持不变。
2. 当前样本 38 个 DSB 的 SCH/S 仍全部 ok。
3. 新通用解码器与旧 decodeSchS 在 SCH/S 上输出一致。
```

## 阶段 2：解 DSB BKN2/SCH-H

DSB 当前已提取：

```text
BKN1: slot bits 129..248, SCH/S, 120 bits
BKN2: slot bits 287..502, SCH/H, 216 bits
```

SCH/H 解码流程：

```text
216 scrambled SCH/H bits
-> descramble with zero DCC
-> (216,101) deinterleave
-> RCPC rate 2/3 Viterbi
-> 124 type-1 bits + 16 parity + 4 tail
-> parse SCH/H part
```

注意：DSB 的 SCH/S 和 SCH/H 使用 zero DCC，所以 SCH/H 可以在不知道 DCC 的
情况下先解。

验收：

```text
1. 当前样本 DSB BKN2/SCH-H 有稳定 parity/tail/RCPC 结果。
2. 每个 DSB 输出 SCH/S 和 SCH/H 两部分。
3. `schs_preview.txt` 扩展或新增 `sync_preview.txt`，能列出完整同步消息摘要。
```

## 阶段 3：完整 DMAC-SYNC 解析

当前 `parseDmacSyncSchS` 只解析 SCH/S 的 60 bit，得到：

```text
systemCode
syncPduType
communicationType
abChannelUsage
slotNumber
frameNumber
airInterfaceEncryptionState
```

下一步需要新增完整解析器：

```matlab
sync = tetra.parseDmacSync(schS.type1Bits, schH.type1Bits, cfg)
```

目标输出：

```text
syncPduType
communicationType
frameNumber
slotNumber
abChannelUsage
airInterfaceEncryptionState
messageType / usage
sourceAddress
destinationAddress or groupAddress
MNI
frameCountdown
call or occupation parameters
reserved/fill/error fields
```

验收：

```text
1. 当前样本能区分 DM-SETUP、DM-OCCUPIED 或其它同步消息类型。
2. 能打印 source address、MNI、frame countdown。
3. 同一段连续 DSB 的 frame/slot 和消息字段变化符合时序预期。
```

## 阶段 4：DCC 和 DMO 上下文

普通 DNB 的 STCH/SCH-F/TCH 解扰需要 DCC。DCC 来自当前 traffic transmission
的 DMAC-SYNC 上下文：

```text
DCC = MNI low 6 bits + source address 24 bits
```

需要维护状态：

```text
currentMaster
sourceAddress
destinationAddress
MNI
DCC
communicationType
abChannelUsage
frameNumber
slotNumber
lastValidDmacSync
```

验收：

```text
1. 每个 confirmed DSB 更新 DMO context。
2. DNB 解码时能找到最近且时序合理的 DCC。
3. 没有 DCC 时，DNB payload 只导出不解码，不伪造结果。
```

## 阶段 5：解 normal_2 的 STCH

`normal_2` 表示 stealing/STCH：

```text
BKN1: STCH
BKN2: TCH or STCH
```

实现步骤：

```text
1. 取 DNB normal_2 BKN1 216 bits。
2. 用当前 DCC 解 STCH。
3. 解析 STCH MAC header。
4. 判断 BKN2 是 TCH 还是 STCH。
5. 如果 BKN2 也是 STCH，再对 BKN2 解 STCH。
```

目标输出：

```text
frameNumber
slotNumber
halfSlot
logicalChannel = STCH
macPduType
isCPlane or isUPlane
secondHalfStolen
rawType1Bits
parsedFields
```

验收：

```text
1. 当前样本 FN13 TN1 normal_2 能解释 BKN1 里具体是什么 STCH PDU。
2. 能判断 BKN2 是 TCH 还是 STCH。
3. STCH parity/tail/RCPC 通过；如果失败，要明确输出失败原因。
```

## 阶段 6：解 SCH/F

`normal_1` 的 DNB 可能是 TCH，也可能是 SCH/F。SCH/F 使用完整 DNB 两个 BKN：

```text
BKN1 216 bits + BKN2 216 bits = 432 bits
```

解码流程：

```text
432 scrambled SCH/F bits
-> descramble with DCC
-> (432,103) deinterleave
-> RCPC rate 2/3 Viterbi
-> 268 type-1 bits + 16 parity + 4 tail
-> parse full-slot signalling PDU
```

验收：

```text
1. 能对 normal_1 DNB 尝试 SCH/F decode。
2. SCH/F 成功时输出 MAC PDU。
3. SCH/F 失败时保留该 DNB 为 TCH candidate，不把 TCH 错判成 SCH/F。
```

## 阶段 7：TCH 和语音前置处理

TCH 不建议立即作为第一目标。应先完成 SCH/H、STCH、SCH/F，因为这些控制信道
提供上下文、DCC、call state 和 stealing 信息。

TCH 阶段需要：

```text
traffic slot collection
voice frame/block assembly
interleaving and channel decode
encryption state handling
codec payload extraction
```

如果 `airInterfaceEncryptionState` 非 DM-1，则语音 payload 可能无法直接解码。

验收：

```text
1. 能连续收集属于同一次 call 的 TCH blocks。
2. 能识别 encrypted / unencrypted。
3. 对未加密样本输出 codec payload 或 voice-frame candidate。
```

## 阶段 8：实时批处理上下文和输出

当前离线阶段已经输出 MAC PDU 和 session 摘要。完整跨批次上下文等进入实时
处理阶段时统一做，形式不是逐 sample 流式状态机，而是：

```matlab
[state, events] = tetra.processBatch(iq1s, fs, state)
```

`state` 至少需要保存：

```text
last frame/slot reference
last valid DMAC-SYNC time
current DCC
sourceAddress
destinationAddress
MNI
communication type
air-interface encryption state
current session
recent emitted-event keys
```

批处理输出仍沿用当前 PDU/event 结构：

```text
TETRA_DMAC_SYNC
TETRA_STCH
TETRA_SCHF
TETRA_TCH_CANDIDATE
TETRA_SESSION
```

典型批处理逻辑：

```text
1. 当前批次先独立完成物理层和 burst 识别。
2. 如果本批有 DSB，刷新 FN/TN、DCC 和 session 上下文。
3. 如果本批没有 DSB，但 state 里有有效 DCC，则用上一批上下文解释 DNB/STCH。
4. 输出本批新增事件，并用 recent emitted-event keys 去重。
5. 返回更新后的 state，供下一批使用。
```

该阶段暂不在当前离线文件解码任务中实现。

## 推荐实现顺序

```text
1. 抽象通用 signalling block decoder。
2. 用通用 decoder 替换现有 decodeSchS，保证结果不变。
3. 实现 decodeSchH，先只做 channel decode 和校验。
4. 实现 parseDmacSync，把 SCH/S + SCH/H 合并。
5. 建 DMO context 和 DCC。
6. 解当前样本 normal_2 的 STCH。
7. 尝试 normal_1 的 SCH/F，失败则标记为 TCH candidate。
8. 补全更多 MAC message element 解析。
9. 进入实时批处理阶段时，再统一实现 batch-oriented DMO context。
10. 如确有需求，最后进入 TCH/voice。
```

## 风险点

```text
1. SCH/H 字段解析需要严格对照 ETSI bit layout。
2. DCC 错误会导致 DNB 解扰全部失败。
3. TCH 和 SCH/F 需要避免误判，应以 parity/tail/CRC/FCS 为准。
4. 当前 hard-decision Viterbi 对弱信号不如 soft-decision 稳。
5. 多个连续 call 或多发射机时，需要更严格的 context 选择。
```

## 第一阶段链路层验收目标

最小可交付目标：

```text
1. 当前样本所有 DSB 同时输出 SCH/S 和 SCH/H decode status。
2. 能输出完整 DMAC-SYNC 摘要。
3. 能生成 DCC。
4. 能解释至少一个 normal_2 STCH。
5. 能把 normal_1 DNB 分类为 SCH/F success 或 TCH candidate。
```

## 当前实现状态

已实现到阶段 6，TCH/VOICE 暂不做：

```text
1. decodeDmoSignallingBlock 已支持 SCH/S、SCH/H、STCH、SCH/F。
2. decodeSchS 已迁移到通用信令块解码器，旧字段保持兼容。
3. DSB BKN2/SCH-H 已解码，当前样本 38/38 通过 block/tail 校验。
4. parseDmacSync 已合并 SCH/S + SCH/H，输出完整 DMAC-SYNC 摘要。
5. DCC 已由 MNI 低 6 bit + source address 24 bit 生成，并作为 DNB 解扰上下文。
6. normal_2 STCH 已解码，当前样本解析到 DM-INFO、DM-RELEASE、Null PDU。
7. normal_1 SCH/F 已尝试解码；当前样本均未通过 block-code 校验，因此保留为 TCH candidate。
```

当前样本验收结果：

```text
confirmed bursts:       62
DSB / DNB:              38 / 24
SCH/S decoded:          38
SCH/H decoded:          38
DMAC-SYNC decoded:      38
DCC contexts:           38
MAC/control blocks:     28
STCH decoded:           6
SCH/F decoded:          0
MAC PDU decoded:        6
```

新增输出：

```text
schs_preview.txt      SCH/S、SCH/H、完整 DMAC-SYNC、DCC
dmo_mac_preview.txt   DSB context、STCH、SCH/F attempt、TCH candidate
radio.scanFile        TETRA_DMAC_SYNC、TETRA_STCH、TETRA_TCH_CANDIDATE、TETRA_SESSION
```
