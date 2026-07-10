# TETRA DMO BKN1/BKN2 解析参考

本文用于说明 TETRA DMO 的 BKN1、BKN2 在 DSB/DNB 中承载什么内容，如何从
MAC PDU 的 Type-1 信息位经过信道编码映射到空口 BKN bit，以及当前 MATLAB
实现已经支持和仍未支持的解析范围。

核心结论：BKN1/BKN2 是物理层复用块，不是两个具有固定字段格式的 PDU。它们
承载的逻辑信道由 burst 类型和训练序列决定；空口中的 BKN bit 已经经过纠错编码、
交织和扰码，不能直接当作 MAC PDU 字段切片。

## 标准依据

- [ETSI EN 300 396-2 V1.4.1：DMO Radio aspects](https://www.etsi.org/deliver/etsi_en/300300_300399/30039602/01.04.01_60/en_30039602v010401p.pdf)，重点为第 8、9 章。
- [ETSI EN 300 396-3 V1.4.1：DMO MS-MS Air Interface protocol](https://www.etsi.org/deliver/etsi_en/300300_300399/30039603/01.04.01_60/en_30039603v010401p.pdf)，重点为第 8、9 章。

## 1. BKN1/BKN2 承载关系

| Burst | 训练序列 | BKN1 | BKN2 | MAC PDU |
|---|---|---|---|---|
| DSB | sync | SCH/S，120 个空口 bit | SCH/H，216 个空口 bit | 两块共同组成一个 DMAC-SYNC |
| DNB | normal-1 | SCH/F 或 TCH 的前半 | SCH/F 或 TCH 的后半 | SCH/F：DMAC-DATA/FRAG/END；TCH：DMAC-TRAFFIC |
| DNB | normal-2 | STCH | STCH 或 TCH | STCH：DMAC-DATA/END/U-SIGNAL |

需要特别注意：

1. DSB 的两个块是两个独立编码块，但共同承载一个 DMAC-SYNC。
2. SCH/F 是一个完整的 432-bit 空口编码块，然后切成 BKN1、BKN2 各 216 bit。
3. normal-1 只表示该 DNB 是 TCH 或 SCH/F，必须通过 SCH/F 的纠错校验确认。
4. normal-2 表示 BKN1 一定是 STCH。BKN1 内的
   `second half slot stolen flag` 决定 BKN2 是 STCH 还是 TCH。
5. TCH 上的 DMAC-TRAFFIC 没有 MAC header，全部可用容量都是语音或电路数据。

项目映射定义见 `+tetra/dmoBurstDefinitions.m`。

## 2. 空口物理位置

项目使用包含 guard/ramp 的 510-bit slot 坐标。ETSI 的 burst BN 从有效 burst
字段开始计数，因此项目 slot 坐标比 ETSI burst BN 多 34 bit。

### 2.1 DNB

```text
slot 1..34      guard/ramp
slot 35..46     P1/P2 preamble
slot 47..48     phase adjustment
slot 49..264    BKN1，216 scrambled bits
slot 265..286   normal training，22 bits
slot 287..502   BKN2，216 scrambled bits
slot 503..504   tail = 00
slot 505..510   guard/ramp
```

对应 ETSI burst BN：

```text
BN 15..230    bkn1(1)..bkn1(216)
BN 253..468   bkn2(1)..bkn2(216)
```

### 2.2 DSB

```text
slot 1..34      guard/ramp
slot 35..46     P3 preamble
slot 47..48     phase adjustment
slot 49..128    frequency correction，80 bits
slot 129..248   SCH/S，120 scrambled bits
slot 249..286   sync training，38 bits
slot 287..502   SCH/H，216 scrambled bits
slot 503..504   tail = 00
slot 505..510   guard/ramp
```

严格按标准命名，DSB 中第一个 120-bit 字段是同步块 `sb(1)..sb(120)`。项目为了
统一 BKN 提取接口，将其命名为 `BKN1/SCH-S`。

提取实现见 `+tetra/extractDmoPayload.m`。

## 3. MAC bit 到 BKN bit 的完整映射

发送方向处理链如下：

```text
MAC PDU 字段
    -> Type-1 信息位
    -> 加 16-bit block-code parity 和 4 个零 tail
    -> Type-2 bits
    -> RCPC rate 2/3
    -> Type-3 bits
    -> 块交织
    -> Type-4 bits
    -> DCC 扰码
    -> Type-5 bits
    -> 映射/切分为 BKN1、BKN2
```

接收方向按相反顺序执行。当前通用实现位于
`+tetra/decodeDmoSignallingBlock.m`。

### 3.1 Type-1：MAC PDU 原始字段

MAC 字段按照标准 PDU 表格从上到下连接：

- 表格上方字段先发送；
- 多 bit 数值按 MSB first 发送；
- SCH/S 固定为 60 bit；
- SCH/H、STCH 固定为 124 bit；
- SCH/F 固定为 268 bit。

### 3.2 16-bit block code 和 4-bit tail

对于长度为 `K1` 的 Type-1 block：

```text
b2(1..K1)          = b1(1..K1)
b2(K1+1..K1+16)   = 16 个 block-code parity bits
b2(K1+17..K1+20)  = 0000 tail
```

块码生成多项式为：

```text
G(X) = X^16 + X^12 + X^5 + 1
```

| 逻辑信道 | Type-1 | parity | tail | Type-2 |
|---|---:|---:|---:|---:|
| SCH/S | 60 | 16 | 4 | 80 |
| SCH/H | 124 | 16 | 4 | 144 |
| STCH | 124 | 16 | 4 | 144 |
| SCH/F | 268 | 16 | 4 | 288 |

项目实现见 `+tetra/dmoBlockCodeParity.m`。

### 3.3 RCPC 2/3 编码

每个 Type-2 bit 先进入 16 状态、母码率 1/4 的卷积编码器。四个生成多项式为：

```text
G1(D) = 1 + D + D^4
G2(D) = 1 + D^2 + D^3 + D^4
G3(D) = 1 + D + D^2 + D^4
G4(D) = 1 + D + D^3 + D^4
```

随后使用穿孔序列：

```text
P = [1, 2, 5]
```

即每两个输入 bit 产生 8 个母码输出时保留：

```text
V(1), V(2), V(5)
V(9), V(10), V(13)
...
```

因此每 2 个 Type-2 bit 产生 3 个 Type-3 bit：

```text
80  -> 120
144 -> 216
288 -> 432
```

项目接收端使用 Viterbi 逆解，见 `+tetra/rcpcDecodeRate23.m`。

### 3.4 块交织

标准 `(K,a)` 块交织公式：

```text
b4(k) = b3(i)
k = 1 + mod(a*i, K)
i = 1..K
```

| 逻辑信道 | K | a |
|---|---:|---:|
| SCH/S | 120 | 11 |
| SCH/H、STCH | 216 | 101 |
| SCH/F | 432 | 103 |

因此 MAC 中相邻的 bit 在 BKN 中通常不相邻。逆交织实现见
`+tetra/blockDeinterleave.m`。

### 3.5 DCC 扰码

```text
b5(k) = b4(k) XOR p(k)
```

`p(k)` 由标准定义的 32 阶 LFSR 产生。

对于 DSB：

```text
SCH/S seed = 30 个 0
SCH/H seed = 30 个 0
```

对于 DNB 上的 SCH/F、STCH、TCH：

```text
DCC = MNI 最低 6 bit || source SSI 24 bit
```

项目对应代码：

```matlab
dcc = [mniBits(19:24); sourceBits(1:24)];
```

实现见 `+tetra/dmoDcc.m` 和 `+tetra/scramblingSequence.m`。

### 3.6 Type-5 到 BKN 的映射

SCH/S：

```text
sb(k) = b5(k), k=1..120
```

SCH/H 或 STCH：

```text
bkn1(k) = b5(k)，或者
bkn2(k) = b5(k)，k=1..216
```

SCH/F：

```text
BKN1(k) = b5(k),       k=1..216
BKN2(k) = b5(k+216),   k=1..216
```

因此 SCH/F 接收端必须先拼接：

```matlab
schfBits = [bkn1Bits; bkn2Bits];   % 432 bits
```

不能分别将 BKN1、BKN2 当成两个 SCH/F block 解码。

## 4. DSB：DMAC-SYNC 精确位布局

DSB 的逻辑关系为：

```text
BKN1/SCH-S -> 解出 60 Type-1 bits
BKN2/SCH-H -> 解出 124 Type-1 bits
SCH/S + SCH/H -> 一个完整 DMAC-SYNC
```

### 4.1 SCH/S：固定 60 bit

| Type-1 bit | 长度 | 内容 |
|---|---:|---|
| 1..4 | 4 | System code |
| 5..6 | 2 | SYNC PDU type，`00` 表示 DMAC-SYNC |
| 7..8 | 2 | Communication type |
| 9 | 1 | master/slave link flag 或 reserved |
| 10 | 1 | gateway generated message flag 或 reserved |
| 11..12 | 2 | A/B channel usage |
| 13..14 | 2 | Slot number，`00..11` 对应 slot 1..4 |
| 15..19 | 5 | Frame number，`00001..10010` 对应 frame 1..18 |
| 20..21 | 2 | Air-interface encryption state |
| 22..60 | 39 | 加密相关字段或 reserved |

当 encryption state 为 `00` 时，bit 22..60 应全部为 0。

当 encryption state 非零时：

| Type-1 bit | 内容 |
|---|---|
| 22..50 | TVP，29 bit |
| 51 | reserved |
| 52..55 | KSG number |
| 56..60 | encryption key number |

对应代码见 `+tetra/parseDmacSyncSchS.m`。

### 4.2 SCH/H：124 bit 条件布局

标准字段顺序：

```text
10-bit repeater/gateway/reserved
fill bit indication
fragmentation flag
[4-bit number of SCH/F slots，仅 fragmentation=1]
2-bit frame countdown
2-bit destination address type
[24-bit destination address]
2-bit source address type
[24-bit source address]
[24-bit MNI]
5-bit message type
message-dependent elements
DM-SDU
fill bits
```

最常见的 Direct MS-MS、无 fragmentation、源和目的地址均存在时，精确位置为：

| Type-1 bit | 长度 | 内容 |
|---|---:|---|
| 1..10 | 10 | reserved，应为 0 |
| 11 | 1 | fill bit indication |
| 12 | 1 | fragmentation flag=`0` |
| 13..14 | 2 | frame countdown |
| 15..16 | 2 | destination address type |
| 17..40 | 24 | destination SSI |
| 41..42 | 2 | source address type |
| 43..66 | 24 | source SSI |
| 67..90 | 24 | MNI |
| 91..95 | 5 | message type |
| 96..124 | 29 | message-dependent elements、DM-SDU、fill |

如果 fragmentation flag=`1`，则在 bit 13..16 插入 `number of SCH/F slots`，
其后的字段整体向后移动 4 bit。

对应代码见 `+tetra/parseDmacSync.m`。

## 5. DNB：MAC PDU 类型和位布局

### 5.1 PDU 到逻辑信道的映射

| MAC PDU | 允许的逻辑信道 |
|---|---|
| DMAC-DATA | STCH、SCH/F |
| DMAC-FRAG | SCH/F |
| DMAC-END | STCH、SCH/F |
| DMAC-U-SIGNAL | STCH |
| DMAC-TRAFFIC | TCH |

### 5.2 DMAC-DATA

| Type-1 bit | 长度 | 内容 |
|---|---:|---|
| 1..2 | 2 | MAC PDU type=`00` |
| 3 | 1 | fill bit indication |
| 4 | 1 | second half slot stolen flag |
| 5 | 1 | fragmentation flag |
| 6 | 1 | null PDU flag |
| 7..8 | 2 | frame countdown |
| 9..10 | 2 | air-interface encryption state |
| 11..12 | 2 | destination address type |
| 13..36 | 24 | destination address，条件存在 |
| 37..38 | 2 | source address type |
| 39..62 | 24 | source address，条件存在 |
| 63..86 | 24 | MNI，Direct MS-MS/DM-REP 时存在 |
| 87..91 | 5 | message type |
| 92..末尾 | 可变 | message-dependent elements、DM-SDU、fill |

如果 bit 6 `nullPduFlag=1`，PDU 在该 bit 后结束，后面不再有有效字段。

STCH 的 Type-1 总长为 124 bit；SCH/F 的 Type-1 总长为 268 bit，所以 SCH/F
能够承载更大的 DM-SDU。

### 5.3 DMAC-FRAG 和 DMAC-END

```text
bit 1..2  MAC PDU type = 01
bit 3     subtype：0=DMAC-FRAG，1=DMAC-END
bit 4     fill bit indication
bit 5..   DM-SDU fragment
```

- DMAC-FRAG 只允许出现在 SCH/F。
- DMAC-END 可以出现在 SCH/F，也可以出现在第二个 STCH 半时隙。

### 5.4 DMAC-U-SIGNAL

它固定占满一个 124-bit STCH Type-1 block：

```text
bit 1..2    MAC PDU type = 11
bit 3       second half slot stolen flag
bit 4..124  U-plane DM-SDU，固定 121 bit
```

### 5.5 DMAC-TRAFFIC

DMAC-TRAFFIC 没有 MAC header：

```text
全部可用业务容量 = 语音或电路数据
```

其具体编码取决于 TCH/S、TCH/7.2、TCH/4.8、TCH/2.4 和交织深度。当前项目
尚未实现完整 TCH/语音解码。

DNB PDU 解析入口见 `+tetra/parseDmoMacPdu.m`。

## 6. 5-bit message type

DMAC-SYNC 和 DMAC-DATA header 后面的 5-bit message type：

```text
00000  DM-RESERVED
00001  DM-SDS OCCUPIED
00010  DM-TIMING REQUEST
00011  DM-TIMING ACK
00100  Reserved
00101  Reserved
00110  Reserved
00111  Reserved
01000  DM-SETUP
01001  DM-SETUP PRES
01010  DM-CONNECT
01011  DM-DISCONNECT
01100  DM-CONNECT ACK
01101  DM-OCCUPIED
01110  DM-RELEASE
01111  DM-TX CEASED
10000  DM-TX REQUEST
10001  DM-TX ACCEPT
10010  DM-PREEMPT
10011  DM-PRE ACCEPT
10100  DM-REJECT
10101  DM-INFO
10110  DM-SDS UDATA
10111  DM-SDS DATA
11000  DM-SDS ACK
11001  Gateway-specific
11010  Reserved
11011  Reserved
11100  Reserved
11101  Reserved
11110  Proprietary
11111  Proprietary
```

后续 message-dependent elements 的具体格式由 message type 决定。当前部分解析
位于 `+tetra/parseDmoMessageElements.m`。

## 7. DM-SETUP 位放置示例

假定：

- Direct MS-MS；
- 使用 SCH/H；
- fragmentation flag=`0`；
- 源地址和目的地址均存在；
- message type=`01000`，即 DM-SETUP。

此时 SCH/H 的 bit 91..95 为 `01000`，后续字段为：

| Type-1 bit | 内容 |
|---|---|
| 96 | timing flag |
| 97 | LCH flag |
| 98 | pre-emption flag |
| 99..101 | power class |
| 102 | power control flag |
| 103..104 | reserved |
| 105 | dual-watch synchronization flag |
| 106 | two-frequency call flag |
| 107..110 | circuit mode type |
| 111..114 | reserved |
| 115..116 | priority level |
| 117 | end-to-end encryption flag |
| 118 | call type flag |
| 119 | external source flag |
| 120..121 | reserved |
| 122..124 | fill 区域 |

如果需要 fill，标准要求：

```text
fill bit indication = 1
真实 PDU 之后的第一个 fill bit = 1
其余 fill bits = 0
```

因此该例通常为：

```text
bit 122 = 1
bit 123 = 0
bit 124 = 0
```

## 8. 当前 MATLAB 解码流程

当前信令信道的物理层逆处理已经实现：

```text
BKN Type-5 bits
    -> descramble
    -> deinterleave
    -> RCPC Viterbi
    -> parity/tail check
    -> Type-1 MAC bits
```

上层处理流程为：

```text
DSB:
  BKN1 -> SCH/S
  BKN2 -> SCH/H
  -> DMAC-SYNC
  -> MNI + source SSI
  -> DCC

normal-2 DNB:
  BKN1 -> STCH
  -> 读取 secondHalfSlotStolenFlag
  -> BKN2 按 STCH 或 TCH 处理

normal-1 DNB:
  BKN1+BKN2 -> 尝试 SCH/F
  -> parity/tail 通过：解析 MAC PDU
  -> 校验失败：保留为 TCH candidate
```

主要实现文件：

```text
+tetra/extractDmoPayload.m
+tetra/decodeDmoSignallingBlock.m
+tetra/decodeSchS.m
+tetra/parseDmacSyncSchS.m
+tetra/parseDmacSync.m
+tetra/parseDmoMacPdu.m
+tetra/parseDmoMessageElements.m
+tetra/inferDmoBursts.m
```

## 9. 当前实现边界

### 9.1 Fill bit 删除不完整

当前解析器会保存 `remainingBits`，但还没有严格定位并删除末尾的
`1 000...` fill pattern，因此 DM-SDU 尾部可能包含 fill bit。

### 9.2 Message-dependent 解析仍是子集

尤其是 DM-SDS UDATA/DATA，目前只解析部分 SDS header。Calling-party TSI、
SDTI 对应载荷、长度指示和 FCS 等仍主要保留为 raw bits。

### 9.3 尚未执行空口解密

当 `airInterfaceEncryptionState` 非 `00` 时，部分地址、DM-SDU 或其后的字段
可能是密文，不能继续按明文字段解释。

### 9.4 TCH 尚未实现

normal-1 的 SCH/F 校验失败后会保留为 TCH candidate，但当前不能进一步判断是
语音还是哪一种电路数据，也未完成 TCH/S 语音解码。

### 9.5 PDU 与逻辑信道合法性检查不完整

例如通用解析器能够把 STCH 上的 `01 + subtype=0` 解释为 DMAC-FRAG，但标准
规定 DMAC-FRAG 只允许出现在 SCH/F。

### 9.6 DNB 解扰依赖正确的会话 DCC

必须从对应呼叫上下文的 DMAC-SYNC 得到正确 MNI 和 source SSI。若错误沿用其他
会话的 DCC，通常会表现为 RCPC metric、block-code parity 或 tail 校验失败。

## 10. 建议的后续实现顺序

1. 实现并测试标准 fill-bit 删除。
2. 加入 PDU 与逻辑信道合法性检查。
3. 按 EN 300 396-3 第 9.5 节补齐各 message-dependent elements。
4. 完成 SDS 的 SDTI、长度、FCS 和分片重组。
5. 明确加密状态下的解析边界。
6. 最后进入 TCH/S、TCH/7.2、TCH/4.8、TCH/2.4 和语音处理。
