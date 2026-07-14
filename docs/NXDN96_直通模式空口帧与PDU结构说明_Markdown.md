---
title: "NXDN96 直通模式空口帧与 PDU 结构说明"
scope: "12.5 kHz / 9600 bit/s / RDCH / Direct Mode"
standards:
  - "NXDN TS 1-A Version 1.3 — Common Air Interface"
  - "NXDN TS 1-B Version 1.3 — Basic Operation"
---

# NXDN96 直通模式空口帧与 PDU 结构说明

**适用范围：**12.5 kHz / 9600 bit/s / RDCH / Direct Mode<br>
**重点内容：**帧组织、SACCH、FACCH1、UDCH、FACCH2、VCALL 字段及信道编码

```text
NXDN96 RDCH 语音帧（40 ms / 384 bit）

┌──────────┬──────────┬──────────────┬──────────────────────────────────┐
│ FSW      │ LICH     │ SACCH        │ 业务区                           │
│ 20 bit   │ 16 bit   │ 60 bit       │ 288 bit                          │
└──────────┴──────────┴──────────────┴──────────────────────────────────┘
                                         │
                    ┌────────────────────┼────────────────────┐
                    │                    │                    │
                    ▼                    ▼                    ▼
              EHR：4×VCH72        EFR：2×VCH144       2×FACCH1-144
```

封面概览：NXDN96直通语音帧的384-bit组织

依据：NXDN TS 1-A Version 1.3（Common Air Interface）<br>
补充：NXDN TS 1-B Version 1.3（Basic Operation）

# 文档说明
本文档将此前讨论内容整理为一套自洽的NXDN96直通模式结构说明。对象限定为常规系统中的SU-SU直连通信，物理信道为RDCH；重点解析语音通信期间的伴随控制数据，而不是AMBE+2语音解码本身。

| **最核心结论：**NXDN96每个物理帧固定为384 bit、40 ms。稳态语音使用4帧SACCH超级帧（160 ms）：SACCH的72-bit三层PDU被拆为4个18-bit 片段；每个片段独立编码为60-bit 空口SACCH。 |
|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 目录

- [1. 适用范围与基本参数](#1-适用范围与基本参数)
- [2. 信道层级与直通模式定位](#2-信道层级与直通模式定位)
- [3. 传输单位：符号、帧、超级帧与发射过程](#3-传输单位符号帧超级帧与发射过程)
- [4. 384-bit RDCH 语音帧](#4-384-bit-rdch语音帧)
- [5. 四帧 SACCH 超级帧](#5-四帧sacch超级帧)
- [6. 各功能块的形成与信道编码](#6-各功能块的形成与信道编码)
- [7. SACCH 完整结构及 72-bit PDU](#7-sacch完整结构及72-bit-pdu)
- [8. VCALL 字段：组呼、个呼、EHR/EFR 与加密](#8-vcall字段组呼个呼ehrefr与加密)
- [9. FACCH1：快速控制与语音抢占](#9-facch1快速控制与语音抢占)
- [10. UDCH 与 FACCH2](#10-udch与facch2)
- [11. LICH、FSW 与加扰](#11-lichfsw与加扰)
- [12. 接收端解析流程与工程优先级](#12-接收端解析流程与工程优先级)
- [13. 典型字段示例](#13-典型字段示例)
- [14. 协议位置索引](#14-协议位置索引)
- [附录 A. 关键长度核算](#附录a-关键长度核算)
- [附录 B. 名词缩写表](#附录b-名词缩写表)

# 1. 适用范围与基本参数
本说明中的“NXDN96”指12.5 kHz信道间隔、9600 bit/s空口传输速率的NXDN模式。直通通信不经过TRS或CRS，由一个Subscriber Unit直接向另一个Subscriber Unit发射。

| **参数**   | **NXDN96直通模式取值**     | **说明**                             |
|------------|----------------------------|--------------------------------------|
| 系统形态   | Conventional / Direct Mode | SU-SU simplex，不经过中继            |
| RF物理信道 | RDCH                       | 承载直通语音或数据                   |
| 信道间隔   | 12.5 kHz                   | NXDN96                               |
| 传输速率   | 9600 bit/s                 | 每帧40 ms恰好384 bit                 |
| 符号率     | 4800 symbol/s              | 4FSK每符号2 bit                      |
| 调制       | Nyquist 4-Level FSK        | dibit映射为±1、±3符号                |
| 语音编码   | AMBE+2 EHR / EFR           | EHR 3600 bit/s；EFR 7200 bit/s为选项 |
| 帧长度     | 384 bit / 40 ms            | 不含首次发射前的Preamble             |
| 语音超级帧 | 4帧 / 160 ms               | SACCH按1/4～4/4重组                  |

**协议位置：**Part 1-A §2.1、§2.3、表2.3-1（正文第2、12页；PDF第15、25页）；§4.3（正文第19页；PDF第32页）。

# 2. 信道层级与直通模式定位
```text
NXDN 信道层级

RF 物理信道
├── RCCH：集群控制信道
│   ├── CAC
│   │   ├── BCCH
│   │   ├── CCCH
│   │   └── UPCH
│   └── LICH
├── RTCH：集群业务信道
│   ├── USC：VCH / UDCH / SACCH / FACCH1 / FACCH2
│   └── LICH
└── RDCH：常规与直通业务信道
    ├── USC：VCH / UDCH / SACCH / FACCH1 / FACCH2
    └── LICH

直通模式的核心物理信道：RDCH
```

图2-1 NXDN物理信道与功能信道层级

## 2.1 RF物理信道
| **类型** | **名称**           | **用途**                                 |
|----------|--------------------|------------------------------------------|
| RCCH     | RF Control Channel | 集群系统中的注册、广播、寻呼、呼叫请求   |
| RTCH     | RF Traffic Channel | 集群系统中的语音与用户数据业务           |
| RDCH     | RF Direct Channel  | 常规系统中的语音与用户数据；直通模式使用 |

## 2.2 功能信道及CAC/USC
| **分类** | **功能信道**                         | **核心含义**                       |
|----------|--------------------------------------|------------------------------------|
| CAC      | BCCH / CCCH / UPCH                   | RCCH上的功能信道集合               |
| USC      | VCH / UDCH / SACCH / FACCH1 / FACCH2 | RTCH或RDCH上的用户业务功能信道集合 |
| 独立     | LICH                                 | 存在于所有RF信道，不归入CAC或USC   |

| **直通模式最重要的数据流：**RDCH语音流 = Preamble（仅发射开始） + 重复的\[FSW + LICH + SACCH + VCH/FACCH1\]。其中SACCH和FACCH1承载你关注的源ID、目的ID、呼叫类型、加密状态等伴随数据。 |
|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

**协议位置：**Part 1-A §4.2.1～§4.2.3，表4.2-1～4.2-3（正文第15～18页；PDF第28～31页）。

# 3. 传输单位：符号、帧、超级帧与发射过程
| **层次**    | **长度/周期**                   | **含义**                                       |
|-------------|---------------------------------|------------------------------------------------|
| bit         | 1 bit                           | 编码后的二进制数据                             |
| dibit       | 2 bit                           | 4FSK一次符号映射的输入                         |
| symbol      | 208.3 μs                        | 4800 symbol/s；取值+3、+1、-1、-3              |
| frame       | 384 bit = 192 symbols = 40 ms   | 严格的最小空口传输单位                         |
| superframe  | 4 frames = 1536 bit = 160 ms    | 完整SACCH 72-bit PDU的最小重组周期             |
| PTT发射过程 | 起始单帧 + N个超级帧 + 结束单帧 | 开始和结束使用非超级帧SACCH；稳态使用4帧超级帧 |

> 音频/三层控制消息 → 功能信道装载 → CRC/FEC/交织 → 384-bit 帧 → dibit → 4FSK符号 → 符号级加扰 → Nyquist成形 → RF

**协议位置：**Part 1-A §3.3、§4.3、§4.3.2.2（正文第13、19、23页；PDF第26、32、36页）。

# 4. 384-bit RDCH 语音帧
```text
RDCH 语音帧的三种业务区解释

固定前部（96 bit）
┌──────────┬──────────┬──────────────┐
│ FSW 20   │ LICH 16  │ SACCH 60     │
└──────────┴──────────┴──────────────┘

后部业务区（288 bit）
EHR： ┌────────┬────────┬────────┬────────┐
      │ VCH 72 │ VCH 72 │ VCH 72 │ VCH 72 │
      └────────┴────────┴────────┴────────┘

EFR： ┌────────────────┬────────────────┐
      │ VCH 144        │ VCH 144        │
      └────────────────┴────────────────┘

抢占：┌────────────────┬────────────────┐
      │ FACCH1 144     │ FACCH1 144     │
      └────────────────┴────────────────┘
```

图4-1 RDCH语音帧的EHR、EFR及FACCH1抢占形式

## 4.1 固定前96 bit
| **块** | **空口长度** | **作用**                                    |
|--------|--------------|---------------------------------------------|
| FSW    | 20 bit       | 固定帧同步字，建立40 ms 帧边界               |
| LICH   | 16 bit       | 描述RF信道类型、USC类型、Steal Flag和方向   |
| SACCH  | 60 bit       | 当前帧的一个SACCH编码块；对应SR8 + L3片段18 |

## 4.2 后288 bit业务区
| **模式**   | **组织形式**   | **语音含义**                                        |
|------------|----------------|-----------------------------------------------------|
| EHR        | 4 × VCH72      | 每个72-bit VCH对应20 ms语音；一个VCH帧携带80 ms语音 |
| EFR        | 2 × VCH144     | 每个144-bit VCH对应20 ms语音；一帧携带40 ms语音     |
| FACCH1抢占 | 2 × FACCH1-144 | 可替换前半、后半或两个144-bit半区                   |

| **长度核算：**FSW20 + LICH16 + SACCH60 + 业务区288 = 384 bit。Preamble≥24 bit只在RDCH一次新发射开始时附加，不计入384 bit。 |
|----------------------------------------------------------------------------------------------------------------------------|

**协议位置：**Part 1-A §4.4.2.2、图4.4-3（正文第26页；PDF第39页）；§4.4.3～§4.4.4（正文第28页；PDF第41页）。

# 5. 四帧 SACCH 超级帧
```text
一个 SACCH 超级帧 = 4 × 40 ms = 160 ms

┌──────────────────┬──────────────────┬──────────────────┬──────────────────┐
│ Frame 1          │ Frame 2          │ Frame 3          │ Frame 4          │
│ SA-1/4           │ SA-2/4           │ SA-3/4           │ SA-4/4           │
│ Structure = 11   │ Structure = 10   │ Structure = 01   │ Structure = 00   │
├──────────────────┼──────────────────┼──────────────────┼──────────────────┤
│ 18-bit 片段1      │ 18-bit 片段2      │ 18-bit 片段3      │ 18-bit 片段4      │
└──────────────────┴──────────────────┴──────────────────┴──────────────────┘
               四段重组为一条 72-bit Layer 3 PDU

9600/EHR 的基本业务分配：
[VCH帧] → [FACCH1/Idle帧] → [VCH帧] → [FACCH1/Idle帧]
```

图5-1 SACCH四帧超级帧及9600/EHR的功能信道分配

## 5.1 SACCH超级帧的本质
稳态语音期间，SACCH不是每个40 ms 帧各自携带一条完整消息，而是一条72-bit Layer 3消息跨4帧传输。每帧仅携带其中18 bit，并在前面附加8-bit SR。

| **帧**  | **SR.Structure** | **含义**        | **承载的L3片段**                |
|---------|------------------|-----------------|---------------------------------|
| Frame 1 | 11               | 1/4，超级帧起点 | bit 71…54（按协议传输顺序理解） |
| Frame 2 | 10               | 2/4             | 下一组18 bit                    |
| Frame 3 | 01               | 3/4             | 下一组18 bit                    |
| Frame 4 | 00               | 4/4，超级帧末尾 | 最后18 bit                      |

## 5.2 9600 bit/s EHR的固定分配
EHR每20 ms产生一个72-bit VCH。一个40 ms物理帧可装4个VCH，即80 ms语音，因此下一帧没有新的语音数据需要发送。Part 1-B规定基本序列为：VCH帧、FACCH1帧、VCH帧、FACCH1帧；偶数帧固定为FACCH1帧或Idle。

> Superframe = \[SA-1/4 + 4×VCH72\] + \[SA-2/4 + 2×FACCH1\] + \[SA-3/4 + 4×VCH72\] + \[SA-4/4 + 2×FACCH1\]

## 5.3 EFR与EHR的区别
| **项目**      | **EHR**                           | **EFR**                        |
|---------------|-----------------------------------|--------------------------------|
| 声码器净数据  | 49 bit / 20 ms                    | 88 bit / 20 ms                 |
| 加语音FEC后   | 72 bit / 20 ms                    | 144 bit / 20 ms                |
| 空口语音码率  | 3600 bit/s                        | 7200 bit/s                     |
| 40 ms 帧内语音 | 4×72 = 288 bit，表示80 ms语音     | 2×144 = 288 bit，表示40 ms语音 |
| 典型用途      | 标准、低码率、可留出FACCH1/间歇帧 | 更高语音质量，9600模式可选     |

**协议位置：**Part 1-A §4.3.2.2、图4.3-8（正文第23页；PDF第36页）；§7.1（正文第164页；PDF第177页）。9600/EHR固定分配见Part 1-B §4.1.2.1、图4.1-5～4.1-6（正文第5～6页；PDF第10～11页）。

# 6. 各功能块的形成与信道编码
```text
各功能信道的长度变化

SACCH
18-bit L3片段 + SR8
        = 26
        + CRC6 = 32
        + Tail4 = 36
        × R=1/2卷积码 = 72
        → 删余 = 60
        → 交织 = 60 bit

FACCH1
80-bit L3
        + CRC12 = 92
        + Tail4 = 96
        × R=1/2卷积码 = 192
        → 删余 = 144
        → 交织 = 144 bit

UDCH / FACCH2
176-bit L3 + SR8
        = 184
        + CRC15 = 199
        + Tail4 = 203
        × R=1/2卷积码 = 406
        → 删余 = 348
        → 交织 = 348 bit

LICH
7-bit控制信息 + 1-bit偶校验 = 8 bit
        → 每bit转换为dibit = 16 bit
```

图6-1 SACCH、FACCH1、UDCH/FACCH2与LICH的长度变化

## 6.1 SACCH：26 bit编码为60 bit
1. 从完整72-bit三层消息中取当前18-bit 片段。

2. 在前面附加8-bit SR，得到26 bit。

3. 计算CRC-6，得到32 bit。

4. 附加4个全0 Tail bit，得到36 bit。

5. 采用K=5、R=1/2卷积编码，得到72 bit。

6. 按SACCH删余矩阵删除12 bit，得到60 bit。

7. 按5×12结构交织，长度仍为60 bit。

## 6.2 FACCH1：80 bit编码为144 bit
> 80 L3 + CRC12 = 92；+ Tail4 = 96；卷积编码→192；删余→144；交织→144 bit

## 6.3 UDCH/FACCH2：184 bit编码为348 bit
> 176 L3 + SR8 = 184；+ CRC15 = 199；+ Tail4 = 203；卷积编码→406；删余→348；交织→348 bit

## 6.4 共同卷积码参数
> Constraint Length K=5，Rate R=1/2<br>
> G1(D)=1+D³+D⁴<br>
> G2(D)=1+D+D²+D⁴

**协议位置：**Part 1-A §4.5.2.1～§4.5.2.3、图4.5-4～4.5-6（正文第36～41页；PDF第49～54页）。

# 7. SACCH 完整结构及 72-bit PDU
## 7.1 SACCH不是固定PDU，而是承载容器
SACCH的三层容量固定为9 octets（72 bit），但里面的具体字段由Message Type决定。直通语音中最关键的PDU是VCALL；加密时还可能承载VCALL_IV；其他允许使用SA的控制消息也可装入。

## 7.2 SR：每个60-bit SACCH块的结构头
| **bit** | **字段**  | **长度** | **含义**                                                                      |
|---------|-----------|----------|-------------------------------------------------------------------------------|
| 7–6     | Structure | 2 bit    | 11=1/4，10=2/4，01=3/4，00=4/4或Single                                        |
| 5–0     | RAN       | 6 bit    | 直通模式下用于判断信令是否匹配；00表示接收机可对任意RAN开静噪，01～3F用户定义 |

## 7.3 72-bit PDU如何跨四帧装载
> 完整L3消息72 bit → \[18\]\[18\]\[18\]\[18\]<br>
> 每帧形成：SR8 + 当前18-bit 片段 = 26 bit → SACCH编码 → 60 bit空口字段

## 7.4 Layer 3消息的通用开头
| **位置**        | **字段**     | **含义**                               |
|-----------------|--------------|----------------------------------------|
| Octet 0 bit7    | F1           | 随消息定义的Flag 1；VCALL中为spare     |
| Octet 0 bit6    | F2           | 随消息定义的Flag 2；VCALL中为spare     |
| Octet 0 bit5～0 | Message Type | 决定后续Elements的解释方式             |
| Octet 1～n      | Elements     | 按具体PDU定义排列；未占满的octet补Null |

**协议位置：**Part 1-A §6.2.1（正文第75～76页；PDF第88～89页）；§6.2.3.1（正文第79页；PDF第92页）；§6.3.1～§6.3.3（正文第81～82页；PDF第94～95页）。

# 8. VCALL 字段：组呼、个呼、EHR/EFR 与加密
```text
VCALL 在 72-bit SACCH 中的组织

┌─────────┬────────────────────────────────────────────┐
│ Octet 0 │ F1 | F2 | Message Type                    │
├─────────┼────────────────────────────────────────────┤
│ Octet 1 │ CC Option                                  │
├─────────┼────────────────────────────────────────────┤
│ Octet 2 │ Call Type | Voice Call Option              │
├─────────┼────────────────────────────────────────────┤
│ Octet 3 │ Source Unit ID 高8位                       │
│ Octet 4 │ Source Unit ID 低8位                       │
├─────────┼────────────────────────────────────────────┤
│ Octet 5 │ Destination Group/Unit ID 高8位            │
│ Octet 6 │ Destination Group/Unit ID 低8位            │
├─────────┼────────────────────────────────────────────┤
│ Octet 7 │ Cipher Type | Key ID                       │
├─────────┼────────────────────────────────────────────┤
│ Octet 8 │ Null（VCALL为8 octets，补齐SACCH的9 octets）│
└─────────┴────────────────────────────────────────────┘
```

图8-1 VCALL在72-bit SACCH中的字段组织

## 8.1 VCALL整体布局
| **Octet** | **字段**                       | **长度**  | **具体含义**                              |
|-----------|--------------------------------|-----------|-------------------------------------------|
| 0         | F1 \| F2 \| Message Type       | 8 bit     | VCALL的F1/F2为spare；Message Type=000001  |
| 1         | CC Option                      | 8 bit     | 紧急、跨系统、寻呼优先级                  |
| 2         | Call Type \| Voice Call Option | 3 + 5 bit | 组呼/个呼及EHR/EFR/双工模式               |
| 3–4       | Source Unit ID                 | 16 bit    | 消息发送方/当前讲话方                     |
| 5–6       | Destination Group or Unit ID   | 16 bit    | 组呼解释为Group ID；个呼解释为被叫Unit ID |
| 7         | Cipher Type \| Key ID          | 2 + 6 bit | 加密方式与密钥编号                        |
| 8         | Null                           | 8 bit     | VCALL仅8 octets，装入9-octet SACCH时补齐  |

## 8.2 CC Option
| **bit** | **字段**      | **0**                       | **1**                                 |
|---------|---------------|-----------------------------|---------------------------------------|
| 7       | Emergency     | Normal                      | Emergency                             |
| 6       | Intra / Inter | Intra-system或Single System | Inter-system；相关消息可带Location ID |
| 5       | Priority      | Normal paging               | Priority paging                       |
| 4～0    | spare         | —                           | —                                     |

直通模式通常为Single System，因此普通清语音呼叫中CC Option常见为0x00；是否为紧急呼叫则看bit7。

## 8.3 Call Type：如何表示组呼和个呼
| **3-bit值** | **名称**          | **含义**             | **直通模式意义** |
|-------------|-------------------|----------------------|------------------|
| 000         | Broadcast Call    | 单向组呼；仅集群系统 | 直通模式不用     |
| 001         | Conference Call   | 双向组呼             | 直通组呼使用     |
| 010         | Unspecified Call  | 仅用于TX_REL         | 结束消息可见     |
| 011         | reserved          | 保留                 | —                |
| 100         | Individual Call   | 个呼                 | 直通个呼使用     |
| 101         | reserved          | 保留                 | —                |
| 110         | Interconnect Call | PSTN呼叫             | 直通模式通常不用 |
| 111         | Speed Dial Call   | PSTN快速拨号         | 直通模式通常不用 |

## 8.4 Voice Call Option
| **bit** | **字段**          | **取值**                                           |
|---------|-------------------|----------------------------------------------------|
| 4       | Duplex            | 0=Half Duplex（SU处于Simplex）；1=Duplex           |
| 3       | spare             | 保留                                               |
| 2～0    | Transmission Mode | 000=4800/EHR；010=9600/EHR；011=9600/EFR；其他保留 |

## 8.5 组呼与个呼的ID解释
| **呼叫类型**                 | **Source ID**    | **Destination ID** |
|------------------------------|------------------|--------------------|
| Conference Group Call（001） | Caller’s Unit ID | Group ID           |
| Individual Call（100）       | Caller’s Unit ID | Called Unit ID     |

## 8.6 Unit ID、Group ID与加密
| **字段**    | **常用范围/取值** | **含义**                                      |
|-------------|-------------------|-----------------------------------------------|
| Unit ID     | 0001～FFEF        | 系统内标准Unit ID；0000为Null，FFFF为All Unit |
| Group ID    | 0001～FFEF        | 标准Group ID；0000为Null，FFFF为All Group     |
| Cipher Type | 00/01/10/11       | Non-ciphered / Scramble / DES / AES           |
| Key ID      | 00～3F            | 00为默认、未指定或非加密；01～3F用户定义      |

**协议位置：**Part 1-A §6.4.1.1、图6.4-1、表6.4-5（正文第87页；PDF第100页）；§6.5.3～§6.5.4（正文第138～139页；PDF第151～152页）；§6.5.11～§6.5.13（正文第141～142页；PDF第154～155页）；§6.5.27～§6.5.28（正文第151页；PDF第164页）。

# 9. FACCH1：快速控制与语音抢占
## 9.1 FACCH1的定位
FACCH1是10-octet（80-bit）Layer 3承载容器。它通过替换一个144-bit语音半区来发送高速控制或语音期间的短数据。一个384-bit语音帧有两个独立FACCH1位置。

| **Steal Flag** | **业务区解释**            |
|----------------|---------------------------|
| 11             | 不抢占：全部为VCH         |
| 10             | 后半144 bit为FACCH1       |
| 01             | 前半144 bit为FACCH1       |
| 00             | 两个144-bit半区均为FACCH1 |

## 9.2 FACCH1常见PDU
| **PDU**              | **Layer 3字段概览**                                                            | **作用**                       |
|----------------------|--------------------------------------------------------------------------------|--------------------------------|
| VCALL                | 与SACCH中的VCALL相同；不足10 octets补Null                                      | 快速重复呼叫信息               |
| VCALL_IV             | Message Type + 64-bit Initialization Vector                                    | DES/AES语音的初始化向量        |
| TX_REL               | CC Option + Call Type + Source ID + Destination ID                             | 最后一个发射帧通知松开PTT      |
| SDCALL_REQ Header    | CC Option + Call Type/Data Call Option + IDs + Cipher/Key + Packet Information | 语音同时传送短数据的首块       |
| SDCALL_REQ User Data | Packet Frame Number + Block Number + User Data                                 | 后续短数据块                   |
| 状态/远程控制消息    | Message Type后按相应PDU定义                                                    | 状态、查询、远程控制等补充业务 |

## 9.3 TX_REL字段
| **Octet** | **字段**                     |
|-----------|------------------------------|
| 0         | F1 \| F2 \| Message Type     |
| 1         | CC Option                    |
| 2         | Call Type \| spare           |
| 3–4       | Source Unit ID               |
| 5–6       | Destination Group or Unit ID |
| 7–9       | Null补齐到10 octets          |

**协议位置：**Part 1-A §4.2.2.6（正文第17页；PDF第30页）；§4.5.2.2、图4.5-5（正文第38～39页；PDF第51～52页）；§6.2.3.2（正文第79页；PDF第92页）；§6.4.1.2、§6.4.1.6、§6.4.1.9～§6.4.1.10。

# 10. UDCH 与 FACCH2
## 10.1 二者的共同空口结构
RDCH数据帧为FSW20 + LICH16 + UDCH/FACCH2 348。UDCH和FACCH2的三层容量均为22 octets（176 bit），编码前增加8-bit SR，最终形成348-bit空口块。

| **功能信道** | **用途**                       | **典型PDU**                                                              |
|--------------|--------------------------------|--------------------------------------------------------------------------|
| UDCH         | 正式用户数据传输               | 首块为DCALL Header；后续为Packet Frame Number + Block Number + User Data |
| FACCH2       | 替换UDCH的快速控制，或独立控制 | TX_REL、状态消息、数据呼叫控制等                                         |

## 10.2 DCALL Header
| **Octet**  | **字段**                         |
|------------|----------------------------------|
| 0          | Message Type                     |
| 1          | CC Option                        |
| 2          | Call Type \| Data Call Option    |
| 3–4        | Source Unit ID                   |
| 5–6        | Destination Group or Unit ID     |
| 7          | Cipher Type \| Key ID            |
| 8–10       | Packet Information               |
| 可选11～18 | Initialization Vector（DES/AES） |

## 10.3 后续UDCH用户数据块
> Octet 0：Message Type<br>
> Octet 1：Packet Frame Number \| Block Number<br>
> Octet 2～21：User Data Area<br>
> 最后一个数据块的User Data区域包含整包Message CRC

**协议位置：**Part 1-A §4.4.2.4、图4.4-5（正文第27页；PDF第40页）；§4.5.2.3（正文第40～41页；PDF第53～54页）；§6.2.3.3～§6.2.3.4（正文第80页；PDF第93页）；§6.4.1.3～§6.4.1.4（正文第89～90页；PDF第102～103页）。

# 11. LICH、FSW 与加扰
## 11.1 LICH原始7 bit
| **bit** | **字段**        | **RDCH直通语音中的意义**                                       |
|---------|-----------------|----------------------------------------------------------------|
| 6～5    | RF Channel Type | 10 = RDCH                                                      |
| 4～3    | USC Type        | 00=非超级帧SACCH；01=UDCH；10=超级帧SACCH；11=超级帧SACCH/Idle |
| 2～1    | Steal Flag      | 决定VCH、FACCH1或FACCH2的装载                                  |
| 0       | Direction       | 0=Inbound；按常规系统表，SU→CR/SU（含SU直通发射）采用0         |

## 11.2 LICH编码
> 7-bit Control Data → 对最高4 bit增加1-bit偶校验 → 8 bit → 每个bit转换为一个dibit（0→01，1→11）→ 16-bit空口LICH

## 11.3 常见直通语音LICH值
| **原始7 bit** | **含义**                                        |
|---------------|-------------------------------------------------|
| 1010110       | RDCH + 超级帧SACCH + 全部VCH + SU发送方向       |
| 1010100       | 后半区FACCH1                                    |
| 1010010       | 前半区FACCH1                                    |
| 1010000       | 两个半区均FACCH1                                |
| 1000000       | 非超级帧SACCH + 两个FACCH1（发射开始/结束常用） |
| 1001110       | UDCH数据帧                                      |
| 1001000       | FACCH2帧                                        |
| 1011000       | 超级帧SACCH / Idle                              |

## 11.4 FSW与加扰范围
FSW固定为20 bit（HEX CDF59），不经过加扰。LICH、SACCH、VCH、FACCH1、UDCH和FACCH2需要按符号加扰；Preamble、FSW、Guard和Post不加扰。

> 扰码多项式：x⁹ + x⁴ + 1<br>
> 每帧初始化：S8…S0 = 0 1 1 1 0 0 1 0 0<br>
> PN=0：符号不反相；PN=1：符号乘以-1（+3↔-3，+1↔-1）

| **加扰不改变长度：**384 bit先形成192个4FSK符号；FSW的前10个符号保持不变，LICH开始到帧尾的182个符号进行符号极性反转。 |
|----------------------------------------------------------------------------------------------------------------------|

**协议位置：**Part 1-A §4.4.4（正文第28页；PDF第41页）；§4.5.3、图4.5-7（正文第42～43页；PDF第55～56页）；§4.6、图4.6-1～4.6-2（正文第48～49页；PDF第61～62页）；§5.2.1～§5.2.2（正文第50～52页；PDF第63～65页）。

# 12. 接收端解析流程与工程优先级
```text
接收端伴随数据解析流程

IQ / 中频数据
      │
      ▼
4FSK解调、符号判决
      │
      ▼
Preamble / FSW检测，建立40 ms 帧边界
      │
      ▼
对LICH至帧尾进行反加扰
      │
      ▼
LICH解码
      ├── RDCH语音帧
      ├── FACCH1抢占状态
      ├── UDCH / FACCH2数据帧
      └── Idle
      │
      ▼
SACCH：去交织 → 补删余位 → Viterbi → CRC-6
      │
      ▼
读取SR，收集1/4～4/4四个18-bit 片段
      │
      ▼
重组72-bit PDU，解析VCALL等消息
      │
      ├── Source Unit ID
      ├── Destination Group / Unit ID
      ├── Group / Individual Call
      ├── EHR / EFR
      ├── Cipher Type / Key ID
      └── RAN
      │
      ▼
FACCH1 / FACCH2：解析TX_REL、VCALL_IV、短数据等
```

图12-1 从IQ/中频输入到伴随数据输出的解析流程

## 12.1 推荐模块顺序
1. 4FSK解调并输出软判决或硬判决dibit。

2. 利用Preamble与FSW建立符号、帧边界；每40 ms切出384 bit。

3. 按照每帧重置的PN序列对LICH至帧尾反加扰。

4. 先解LICH，确认当前是RDCH语音帧、数据帧、FACCH1抢占还是Idle。

5. 每帧解码60-bit SACCH，取得SR8与18-bit三层片段。

6. 按Structure收集4个片段，拼成72-bit PDU并解析Message Type。

7. 若Steal Flag指示FACCH1，解码对应144-bit块；若为UDCH/FACCH2，解码348-bit块。

8. 输出源ID、目标ID/组ID、呼叫类型、RAN、EHR/EFR、加密方式、Key ID和TX_REL状态。

## 12.2 面向“只解伴随数据、不解语音”的最小实现
| **优先级** | **模块**                                      | **必须程度**     |
|------------|-----------------------------------------------|------------------|
| P0         | FSW帧同步、每帧反加扰、LICH解码               | 必须             |
| P0         | SACCH去交织、去删余、Viterbi、CRC-6、四帧重组 | 必须             |
| P0         | VCALL 字段解析                                 | 必须             |
| P1         | FACCH1解码与TX_REL/VCALL_IV解析               | 强烈建议         |
| P1         | EHR/FACCH1超级帧状态机                        | 强烈建议         |
| P2         | UDCH/FACCH2数据业务                           | 根据项目范围     |
| P3         | AMBE+2 VCH语音解码                            | 当前目标可不实现 |

# 13. 典型字段示例
## 13.1 9600/EHR普通直通组呼
> CC Option = 00000000 (0x00)<br>
> Call Type = 001 (Conference Group Call)<br>
> Voice Call Option = 00010 (Half Duplex + 9600/EHR)<br>
> Octet 2 = 001 00010 = 0x22<br>
> Destination字段解释为Group ID

## 13.2 9600/EHR普通直通个呼
> CC Option = 00000000 (0x00)<br>
> Call Type = 100 (Individual Call)<br>
> Voice Call Option = 00010 (Half Duplex + 9600/EHR)<br>
> Octet 2 = 100 00010 = 0x82<br>
> Destination字段解释为被叫Unit ID

## 13.3 9600/EFR组呼与个呼
| **场景**     | **Call Type** | **Voice Call Option** | **Octet 2**     |
|--------------|---------------|-----------------------|-----------------|
| 9600/EFR组呼 | 001           | 00011                 | 00100011 = 0x23 |
| 9600/EFR个呼 | 100           | 00011                 | 10000011 = 0x83 |

## 13.4 加密示例
| **Cipher Type** | **模式**     | **后续处理**                                 |
|-----------------|--------------|----------------------------------------------|
| 00              | Non-ciphered | Key ID通常为00                               |
| 01              | Scramble     | Key ID标识用户定义的扰码/密钥配置            |
| 10              | DES          | 需要VCALL_IV中的64-bit Initialization Vector |
| 11              | AES          | 需要VCALL_IV中的64-bit Initialization Vector |

注意：空口“Scrambler Method”是所有控制/语音数据都要进行的物理层符号加扰，与Cipher Type=01的语音加密Scramble Mode不是同一个概念。

# 14. 协议位置索引
| **主题**                                  | **协议章节**                      | **位置**                   |
|-------------------------------------------|-----------------------------------|----------------------------|
| 基本参数                                  | Part 1-A §2.3、表2.3-1            | 正文12 / PDF25             |
| 4FSK映射                                  | Part 1-A §3.3、表3.3-1            | 正文13 / PDF26             |
| RF与功能信道                              | Part 1-A §4.2、表4.2-1～4.2-3     | 正文15～18 / PDF28～31     |
| 四帧SACCH映射                             | Part 1-A §4.3.2.2、图4.3-8        | 正文23 / PDF36             |
| RDCH语音帧                                | Part 1-A §4.4.2.2、图4.4-3        | 正文26 / PDF39             |
| Preamble与FSW                             | Part 1-A §4.4.3～§4.4.4           | 正文28 / PDF41             |
| SACCH编码                                 | Part 1-A §4.5.2.1、图4.5-4        | 正文36～37 / PDF49～50     |
| FACCH1编码                                | Part 1-A §4.5.2.2、图4.5-5        | 正文38～39 / PDF51～52     |
| UDCH/FACCH2编码                           | Part 1-A §4.5.2.3、图4.5-6        | 正文40～41 / PDF53～54     |
| LICH编码                                  | Part 1-A §4.5.3、图4.5-7          | 正文42～43 / PDF55～56     |
| 空口加扰                                  | Part 1-A §4.6、图4.6-1～4.6-2     | 正文48～49 / PDF61～62     |
| LICH字段与实际值                          | Part 1-A §5.2.1～§5.2.2           | 正文50～52 / PDF63～65     |
| 通用L3消息格式                            | Part 1-A §6.2.1                   | 正文75～76 / PDF88～89     |
| SACCH/FACCH1/UDCH/FACCH2容量              | Part 1-A §6.2.3                   | 正文79～80 / PDF92～93     |
| SR、RAN与四段重组                         | Part 1-A §6.3                     | 正文81～82 / PDF94～95     |
| VCALL                                     | Part 1-A §6.4.1.1、图6.4-1        | 正文87 / PDF100            |
| VCALL_IV                                  | Part 1-A §6.4.1.2、图6.4-2        | 正文88 / PDF101            |
| DCALL                                     | Part 1-A §6.4.1.3～§6.4.1.4       | 正文89～90 / PDF102～103   |
| TX_REL                                    | Part 1-A §6.4.1.6、图6.4-6        | 正文91 / PDF104            |
| CC Option / Call Type / Voice Call Option | Part 1-A §6.5.11～§6.5.13         | 正文141～142 / PDF154～155 |
| Cipher Type / Key ID                      | Part 1-A §6.5.27～§6.5.28         | 正文151 / PDF164           |
| EHR/EFR语音码字                           | Part 1-A §7.1                     | 正文164 / PDF177           |
| 9600/EHR超级帧分配                        | Part 1-B §4.1.2.1、图4.1-5～4.1-6 | 正文5～6 / PDF10～11       |
| RDCH典型语音发射                          | Part 1-B §4.1.3、图4.1-7          | 正文7起                    |

# 附录 A. 关键长度核算
| **对象**    | **原始/中间长度**                                | **空口长度**                    |
|-------------|--------------------------------------------------|---------------------------------|
| 单帧        | FSW20 + LICH16 + SACCH60 + Payload288            | 384 bit                         |
| 超级帧      | 4 × 384                                          | 1536 bit / 160 ms               |
| SACCH完整L3 | 72 = 4 × 18                                      | 每帧片段编码为60，四帧共240 bit |
| SACCH每帧   | 18 L3 + 8 SR + 6 CRC + 4 Tail = 36；卷积后72     | 删余/交织后60                   |
| FACCH1      | 80 L3 + 12 CRC + 4 Tail = 96；卷积后192          | 删余/交织后144                  |
| UDCH/FACCH2 | 176 L3 + 8 SR + 15 CRC + 4 Tail = 203；卷积后406 | 删余/交织后348                  |
| EHR VCH     | 49语音 + 23 FEC                                  | 72 bit / 20 ms                  |
| EFR VCH     | 88语音 + 56 FEC                                  | 144 bit / 20 ms                 |

# 附录 B. 名词缩写表
| **缩写** | **英文**                          | **中文/作用**           |
|----------|-----------------------------------|-------------------------|
| SU       | Subscriber Unit                   | 用户台/终端             |
| CR       | Conventional Repeater             | 常规中继台              |
| TR       | Trunking Repeater                 | 集群中继台              |
| RDCH     | RF Direct Channel                 | 常规/直通业务物理信道   |
| RTCH     | RF Traffic Channel                | 集群业务信道            |
| RCCH     | RF Control Channel                | 集群控制信道            |
| CAC      | Common Access Channel             | RCCH功能信道集合        |
| USC      | User Specific Channel             | RTCH/RDCH功能信道集合   |
| LICH     | Link Information Channel          | 链路与帧结构标识        |
| SACCH    | Slow Associated Control Channel   | 慢速随路控制            |
| FACCH1   | Fast Associated Control Channel 1 | 语音期间快速控制/短数据 |
| FACCH2   | Fast Associated Control Channel 2 | 数据期间快速控制        |
| VCH      | Voice Channel                     | 语音码字承载            |
| UDCH     | User Data Channel                 | 用户数据承载            |
| RAN      | Radio Access Number               | 无线接入号/直通匹配码   |
| FSW      | Frame Sync Word                   | 帧同步字                |
| EHR      | Enhanced Half Rate                | 3600 bit/s语音码率      |
| EFR      | Enhanced Full Rate                | 7200 bit/s语音码率      |
| VCALL    | Voice Call                        | 语音呼叫状态PDU         |
| TX_REL   | Transmission Release              | 发射结束PDU             |

# 结语：实现时应抓住的主线
| **主线1：**384-bit 帧只是物理容器；LICH决定当前帧如何解释，不能在未解析LICH前直接把后288 bit固定当作VCH。 |
|----------------------------------------------------------------------------------------------------------|

| **主线2：**SACCH的“72 bit”是四帧重组后的Layer 3容量；单帧空口SACCH为60 bit，其解码输入是SR8 + L3片段18。 |
|----------------------------------------------------------------------------------------------------------|

| **主线3：**组呼和个呼不是由信道类型区分，而是由VCALL的Call Type区分：001为Conference Group Call，100为Individual Call；目的16-bit字段随之解释为Group ID或Unit ID。 |
|--------------------------------------------------------------------------------------------------------------------------------------------------------------------|

| **主线4：**当前项目若只关注伴随数据，优先完成FSW/LICH/SACCH/FACCH1链路即可；AMBE+2语音解码可以完全独立，暂不实现。 |
|--------------------------------------------------------------------------------------------------------------------|
