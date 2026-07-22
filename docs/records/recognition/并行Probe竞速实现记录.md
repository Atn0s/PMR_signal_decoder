# 并行 Probe 竞速实现记录

> 历史实现记录：本文的串行对照、`auto` 降级和测量数据用于记录
> 并行化过程。串行调度与降级已于 2026-07-22 删除。

## 1. 实现边界

阶段 4 只并行协议识别 Probe，不复制或改写协议解码器。串行和并行调度共同调用：

```text
runProtocolProbe
  -> 现有协议前端/解码器
  -> evaluateProbeEvidence
  -> ProbeResult
```

因此串行仍是无 Parallel Computing Toolbox、池启动失败或故障排查时的回退路径，
而不是第二套协议实现。

## 2. 主要接口

```matlab
handle = radio.stream.parallelProbeRaceStart(snapshot, states, ...
    'EpochId', epochId, ...
    'Generation', generation, ...
    'Mode', 'auto', ...
    'NumWorkers', 5);

[handle, status] = radio.stream.parallelProbeRacePoll(handle);
[handle, result] = radio.stream.parallelProbeRaceCollect(handle, ...
    'TimeoutSec', timeoutSec);
[handle, result] = radio.stream.parallelProbeRaceCancel(handle);
```

`Start` 只提交达到自身下一个窗口的 Probe；窗口不足和已经终止的 Probe 在本地立即
返回。`Poll` 不阻塞采集线程，只收集已经 finished 的 Future；`Collect` 用于离线测试
或允许等待的调用方；`Cancel` 是尽力取消，正确性仍由 epoch/generation 检查保证。

## 3. 池生命周期

`radio.stream.acquireParallelPool` 先调用 `gcp('nocreate')` 复用已有池，只在没有池时
创建。默认使用 5 个 process worker，对应当前五个制式。池创建和 worker 首次加载
代码有显著成本，因此池必须在应用启动阶段建立并长期复用，不能在每次活动开始时重建。
新建进程池使用独立临时 `JobStorageLocation`，避免服务账户或受限环境没有用户主目录
写权限；启动会对瞬态验证失败重试一次，仍失败则由 `auto` 模式回退串行。

池类型规则：

- `auto`：当前等同于 `processes`；
- `processes`：生产和真实协议 Probe 的默认值；
- `threads`：仅保留给不调用受限 MEX 的实验任务。

本机 R2022b 的 thread pool 能运行纯 MATLAB 假任务，但五个真实 Probe 全部因
`parallel:threadpool:DisallowedMexFunction` 失败。现有 DSP 路径包含 thread worker
不允许的 MEX，因此不能用共享内存 thread pool 规避 IQ 序列化。若调用方已经启动了
与请求类型不一致的池，调度器不删除外部池，而是回退串行。

## 4. 结果一致性和消歧

每个 Future 必须同时满足以下条件才可写入当前 Race：

```text
result.epochId      == activeEpochId
result.generation   == activeGeneration
state.epochId       == activeEpochId
state.generation    == activeGeneration
result.protocol     == registry[index].name
state.protocol      == registry[index].name
```

任一条件失败，worker 返回值会被丢弃，当前位置写入当前 generation 的 error 结果，
并增加 `staleResultCount`。测试已验证 5 个旧 generation 返回值不会形成赢家。

同一批次：

- 一个强确认：`confirmed`；
- 两个及以上强确认：`ambiguous`，winner 为空；
- 全部最大窗口拒绝：`rejected_all`；
- 仍有 pending/candidate/no evidence：`classifying`；
- 全部只有 error/rejected 且至少一个 error：`error`。

不能在第一个 Future 确认后立即选择赢家；必须收集当前已提交批次，避免把运行速度当成
协议优先级。

## 5. 取消语义

`cancel(future)` 只是资源优化。Epoch 结束、输入丢样或重新分类时：

1. 调用取消；
2. 上层递增 generation 或创建新 Epoch；
3. 所有迟到返回仍经过 epoch/generation 过滤；
4. 被取消 Race 不产生 confirmed winner。

因此即使 MEX 内部计算不能立即停止，也不会污染新信号。

## 6. 本机性能结果

环境：MATLAB R2022b Parallel Computing Toolbox 7.7，Processes profile，5 workers。

### 6.1 确定性任务

五个 Probe 各等待 250 ms：

| 调度 | 总耗时 |
|---|---:|
| 串行 | 1.265 s |
| 热进程池并行 | 0.300 s |

### 6.2 真实 P25 渐进窗口

使用 P25 录音起点的 1 秒快照，同时尝试五种协议；并行和串行的逐 Probe 状态及赢家
完全一致：

| 调度 | 总耗时 | 结论 |
|---|---:|---|
| 串行 | 6.749 s | P25 |
| 冷协议 worker 并行 | 4.381 s | P25 |
| 同一持久池热态并行 | 1.553 s | P25 |

在全量回归中，客户端已经被阶段 2 的真实样本测试预热，另一次测量为串行 1.133 秒、
冷 worker 并行 3.775 秒、热 worker 并行 1.574 秒。两组结果说明 MATLAB JIT、函数
缓存、worker 单线程执行、数据复制和当时系统负载都会显著改变墙钟时间；单个录音上
“并行一定更快”不是功能不变量。产品默认切换必须以连续流、双方均预热、重复多轮的
P50/P95 和实时因子为准。

6 秒最大窗口的强制交叉测试只得到很小加速，因为 process worker 中 TETRA 长窗口比
客户端单进程更慢，并受到数据复制和 CPU/内存争用影响。实际调度必须使用渐进窗口：
一旦其他制式通过强校验，不应为了证明 TETRA 不匹配而继续扩展到 6 秒。

## 7. 当前限制

1. IQ 快照会分别传给每个 process worker，尚未使用共享内存或 worker 常量；
2. Probe 仍是整窗重算，窗口扩展会重复前端计算；
3. 阶段 4 尚未实现赢家从 pre-trigger 追赶和持续增量解码；
4. 池大小需要在目标 CPU 上根据真实负载重新标定，不保证 5 workers 永远最优；
5. 实时验收应统计采集积压和端到端实时因子，而不只比较单次 Race 墙钟时间。
