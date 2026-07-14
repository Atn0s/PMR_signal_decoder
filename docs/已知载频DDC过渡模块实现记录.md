# 已知载频 DDC 过渡模块实现记录

## 1. 目标与边界

本模块把“宽带复数 IQ 中已经给出大致载频的位置”转换为现有五制式并行识别器能够
接收的单信道复数基带。当前只负责频率搬移、抗混叠滤波和降采样，不负责载波发现、
时间裁剪、Epoch 划分或协议解析。

```text
BVSP / RAW / stereo WAV 宽带 IQ
  -> 10 ms 分块文件源（不丢弃时间数据）
  -> 已知载频 NCO 数字下变频
  -> CIC 抽取 + CIC 补偿 FIR + 末级抗混叠 FIR
  -> 120 kS/s 单信道复数基带
  -> 现有活动检测和 RF Epoch 划分
  -> DMR/P25/dPMR/NXDN/TETRA Probe Race
  -> 赢家完整解码与 PDU 输出
```

当前阶段有意只接受一个载频。这里的“并行”是该载频上的五制式探测并行，不是多个
载频之间并行。多载频调度等真实 SDR 数据格式和设备接口确定后再扩展。

## 2. 为什么顺序必须是 DDC、滤波、降采样

以 61.44 MS/s 输入和 120 kS/s 输出为例，抽取倍数为 512。若直接每 512 点取一点，
原来整个 61.44 MHz Nyquist 区间会以 120 kHz 为周期折叠到输出的 ±60 kHz。目标之外
的载波、噪声、镜像和杂散会与目标信道不可逆地叠加。

实现先用 NCO 把给定载频移到 0 Hz，再以低通级联滤除将要折叠的频率，最后抽取。
R2022b 的 `dsp.DigitalDownConverter` 对 512 倍抽取自动采用三级结构；61.44 MS/s 测试
中实际级联因子为 `[128, 2, 2]`，避免在原始采样率直接执行一个极长的窄带 FIR。

默认参数为：

| 参数 | 默认值 | 含义 |
|---|---:|---|
| 输出采样率 | 120 kS/s | 同时容纳 48/72 kS/s 协议分支 |
| 双边通带带宽 | 40 kHz | 目标中心附近约 ±20 kHz |
| 阻带起点 | 55 kHz | 在输出 Nyquist ±60 kHz 前进入阻带 |
| 通带纹波 | 0.1 dB | 级联设计指标 |
| 阻带衰减 | 80 dB | 抗混叠设计指标 |
| 内部处理块 | 10 ms | 61.44 MS/s 时为 614400 个输入样点 |
| 滤波器冲洗 | 10 ms | 文件末尾补零，保留滤波器尾部响应 |

载频提示残差的滤波器侧近似约束为：

```text
abs(残余频偏) + 信号占用带宽/2 < 20 kHz
```

这只是通带预算，不是解码成功边界。例如按 25 kHz 占用带宽估算，平坦通带留给中心
误差的预算约为 7.5 kHz；每种制式的真正容限仍由同步器、SNR、采样率误差和录音质量
共同决定，必须用频偏注入试验统计，不能把 7.5 kHz 当作保证值。

## 3. 连续分块状态

`radio.tuned.ddcFeed` 在块之间保留 NCO、CIC 和 FIR 状态。上游可以提交任意长度的
`IqChunk`，模块先放入余量缓冲，再固定以 10 ms 内部块调用下变频器。这样解决了当前
R2022b System object 锁定首次输入尺寸的问题，同时给未来 SDR 微批输入保持统一接口。

正常连续输入不会重置滤波器。输入样点号跳变或 `Discontinuity=true` 时，模块丢弃旧
余量、重置 NCO/滤波器、增加连续性代号，并在输出块传播 discontinuity。文件结束时
只补足最后一个内部块并执行配置的短滤波器冲洗；它不按业务含义裁剪任何时间区间。

当前计算使用复数 `double`。在这台机器的 MATLAB R2022b 中，低幅度实测录音以复数
`single` 输入 `dsp.DigitalDownConverter` 时出现明显异常衰减，而 `double` 与整文件
`resample` 参考结果一致。后续若切换 single、GPU、MEX 或 C++，必须先增加幅度与解码
等价测试。

## 4. 文件和公共入口

新增的主要接口：

- `radio.tuned.captureInfo`：读取 BVSP 元数据或解析 RAW/WAV 参数；
- `radio.tuned.ddcInit/ddcFeed/ddcFlush`：有状态单信道转换；
- `radio.tuned.extractFile`：分块读取并输出 120 kS/s 基带；
- `radio.tuned.scanFile`：转换后接入现有多 Epoch 五制式竞争；
- `radio.scanFile(..., 'ExecutionMode','tuned-parallel')`：统一公共入口。

BVSP 当前支持已观察到的 USRP/CI16 格式：112 字节小端头、交错 int16 IQ，并从头部
自动取得采样率和中心频率。RAW 文件必须给出采样率；中心频率为 0 时，载频可以按
相对中心的数值理解。

`scanner.m` 示例配置：

```matlab
TARGET_FILE = '/home/lzkj/lzkj_workspace/DMR_signal/1.bvsp';
EXECUTION_MODE = 'tuned-parallel';
SAMPLE_RATE = [];                         % BVSP 自动读取 61.44 MS/s
WIDEBAND_CENTER_FREQUENCY_HZ = 0;         % BVSP 自动读取 430.999 MHz
FREQ_LIST = 1235200;                      % 相对中心频偏，单位 Hz
PROTOCOLS = {};                           % 五制式并行竞争
BLIND_SEARCH = false;
SHOW_FIGURE = false;
```

也可以直接调用：

```matlab
[pdus, report] = radio.scanFile('/path/to/1.bvsp', ...
    'ExecutionMode', 'tuned-parallel', ...
    'FreqList', 1235200, ...
    'ProtocolNames', {});
```

为了兼容已有脚本，`ExecutionMode='parallel'` 遇到非零单元素 `FreqList` 时也会自动进入
该过渡链路；空 `FreqList` 仍按原方式处理已经居中的基带。

## 5. 验证结果

自动测试 `tests.runTunedTransition` 覆盖：带自定义头的 RAW 分块读取、非整内部块文件尾、
NCO 搬移、带外分量抑制、512/非整数抽取参数约束以及载频越过输入 Nyquist 的拒绝。
修改过的公共 `FileSource` 也通过 `tests.runStreamingPhase1` 回归。

真实 BVSP 验收使用 `DMR_signal/1.bvsp`：

- 元数据：61.44 MS/s、430.999 MHz、61440000 个 IQ 样点、112 字节头；
- 载频：432.2342 MHz，即相对偏移 +1.2352 MHz；
- 输出：120 kS/s；
- DMR 单制式、关闭去重：2 个 `LATE_ENTRY` 和 1 个 `DMR_CALL`；
- 默认五制式进程池竞争：0.6 s 窗口确认 DMR，去重后输出 `LATE_ENTRY` 和
  `DMR_CALL`。

当前测得的整流程实时因子约为 10.9（DMR 单制式串行探测）和 28.4（首次启动五进程
池的五制式竞争）。该结果包含滤波器设计、进程池启动和离线完整解码，说明本阶段是
离线正确性基线，不代表已经具备 61.44 MS/s 在线实时能力。

## 6. 当前限制和下一步

1. 每次只接受一个 `FreqList`；尚未做最多五载频之间的任务并行和资源上限控制。
2. 输出 Epoch/PDU 样点号属于 120 kS/s 基带时间轴；滤波器群时延到宽带绝对样点的精确
   反向映射尚未加入。
3. 当前离线实现会把降采样后的单信道文件保存在内存中，再交给 Epoch 模块；它不会把
   61.44 MS/s 整文件装入内存，但还不是边产生边解码的在线生产者/消费者链路。
4. 只验证了现有 BVSP/USRP CI16 布局；真实 SDR 设备的数据帧头、时间戳、丢包标记和
   字节序确定后，需要增加对应 Source 适配器。
5. 后续优化顺序应为：精确时间映射与更多样例回归、多载频有界调度、边转换边送入
   `RaceCoordinator`、滤波器设计缓存/预热，最后再评估MEX/C++实时实现。

交互式实时功率谱、点击选频、循环文件回放和未来 SDR Source 的完整设计见
`docs/实时频谱选频与循环回放解码前端设计.md`。
