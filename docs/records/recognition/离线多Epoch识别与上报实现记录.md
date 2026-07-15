# 离线多 Epoch 识别与上报实现记录

## 1. 决策

离线并行入口不建立跨 Epoch Session。Epoch 表示一段连续的射频活动和一套连续有效
的解码状态；一旦低功率持续时间达到 `offHangSec`，当前 Epoch 关闭。后续信号即使
解码出相同协议、相同 `src` 和相同 `dst`，也建立新的 `epochId` 并独立上报。

协议解码器内部原有的 `DMR_CALL`、`NXDN_CALL`、`TETRA_SESSION` 等协议级摘要 PDU
不在本次修改范围内。这里取消的是调度层额外进行的跨 Epoch 归并。

## 2. 数据流

```text
centered baseband IQ
        │
        ▼
ActivityDetector（100 ms Chunk、开关迟滞、300 ms off hang）
        │
        ▼
detectActivityEpochs
        │  Epoch 1 / Epoch 2 / ...
        ▼
逐 Epoch 五制式 Probe Race
        │
        ▼
唯一赢家完整解码该 Epoch（包含受边界约束的 pre-trigger）
        │
        ▼
PDU.extra.stream.epoch_id + report.epochs
```

离线文件中的 Epoch 按时间顺序处理；每个 Epoch 内部仍可并行运行 DMR、P25、dPMR、
NXDN 和 TETRA Probe。多个 Epoch 之间暂不并行，符合当前“单已知频点、协议并行”
的资源策略。

## 3. 边界语义

- `candidateStartSample`：首次连续活动的 Chunk 起点。
- `decodeStartSample`：`candidateStartSample-preTriggerSec`，但不会跨入前一 Epoch。
- `endSample`：关闭条件被确认时的尾后绝对采样位置；因此包含最多约
  `offHangSec` 的关闭观察区间。
- `closeReason=rf_activity_ended`：低功率持续时间达到关闭保持值。
- `closeReason=end_of_input`：文件结束时仍存在活动 Epoch。
- `closeReason=input_discontinuity`：输入丢样或绝对采样不连续。
- `closeReason=protocol_switch`：能量持续存在，但原解码器失锁且其他制式被强确认。

默认 `chunkDurationSec=0.100`、`offHangSec=0.300`。因此小于 300 ms 的短暂静默通常
保留在当前 Epoch；1 秒静默会关闭旧 Epoch，并在后续活动到来时创建新 Epoch。

## 4. 输出契约

`radio.scanFile(..., 'ExecutionMode', 'parallel')` 的第二返回值新增：

```matlab
report.epochCount
report.confirmedEpochCount
report.epochs(k).epochId
report.epochs(k).protocol
report.epochs(k).candidateStartSample
report.epochs(k).decodeStartSample
report.epochs(k).endSample
report.epochs(k).outcome
report.epochs(k).closeReason
report.epochs(k).pduStartIndex
report.epochs(k).pduEndIndex
report.epochs(k).pduCount
```

每个 PDU 同时携带：

```matlab
pdu.extra.stream.epoch_id
pdu.extra.stream.source_sample
pdu.extra.stream.source_time_sec
```

全文件不再执行会删除相同发射机重复 Epoch 的语义去重。`Deduplicate=true` 只在单个
Epoch 的解码结果内部生效。

## 5. 协调器 Epoch rollover

`RaceCoordinator` 在协议确认时把赢家、置信度、锁定采样和频偏写入当前 Epoch。
信号结束时通过 `closedEpochs` 上报关闭记录。能量未消失而赢家制式改变时：

1. 以原解码器最后一次强证据位置作为模糊边界起点；
2. 旧 Epoch 以 `protocol_switch` 关闭；
3. 创建新的 `epochId` 和 generation；
4. 新赢家从带 pre-trigger 的边界区域重新追赶；
5. 旧 Future 继续由 epoch/generation 校验隔离。

切换确认时间晚于实际变化时间时，两个 Epoch 都保存 `ambiguousInterval`，不伪造
精确切换点。

## 6. 测试覆盖

`tests.runStreamingPhase9` 覆盖：

- 200 ms 静默保持一个 Epoch；
- 1 秒静默生成两个 Epoch；
- 两个 Epoch 输出相同 `src` 时仍保留两份 PDU和两个 `epoch_id`；
- 原协议失锁、另一制式确认时关闭旧 Epoch并创建新 Epoch；
- classification report、PDU 索引和关闭原因的一致性。

真实 `nxdn96_1_78125.rawiq` 内部检测到四段独立活动，四个 Epoch 均识别为 NXDN，
验证了原先整文件单赢家路径无法表达的多次发射场景。

## 7. 当前限制

- Epoch 活动检测仍基于每 Chunk 平均功率，边界精度受 Chunk 大小影响。
- `offHangSec=0.300` 是研究初值，后续应使用真实 SDR 噪声和衰落样本标定。
- 离线路径先完成活动分段再逐 Epoch 识别；在线 SDR 路径由 `RaceCoordinator` 边采集
  边输出关闭 Epoch。
- UNKNOWN 指数退避和 AMBIGUOUS 二次消歧尚未完成。
- 多频点信道化不在本阶段范围内。
