# 01 — 顶层端口 ENTITY 与声明区（完整小白向）

源文件：`YBT_FPGA_SSTMC20260817_fan/SSTMC_FPGA.vhd`  
范围：**第 1～188 行**（`LIBRARY` → `ENTITY` → `ARCHITECTURE` 声明区，到 `BEGIN` 之前）  
`BEGIN` 在 **第 189 行**（逻辑见 **02** 篇）

> 本篇目标：把「外面有哪些脚、里面先声明了什么」一次讲全。  
> 引脚号来自工程 `.qsf`（见 `03_芯片与引脚说明.md`）；若改板以 `.qsf` 为准。

---

## 目录

1. [文件开头：库](#1-文件开头库第-15-行)
2. [ENTITY 是什么](#2-entity-是什么第-739-行)
3. [端口总览（一张表）](#3-端口总览一张表)
4. [端口分组逐句](#4-端口分组逐句)
5. [ARCHITECTURE 声明区总览](#5-architecture-声明区总览第-41188-行)
6. [常量 CONSTANT 全表](#6-常量-constant-全表)
7. [信号 SIGNAL 分组全表](#7-信号-signal-分组全表)
7.6. [LED 边沿检测与 DC 三角波信号详解](#76-led-边沿检测与-dc-三角波信号详解第-179187-行)
8. [组件 COMPONENT 全表](#8-组件-component-全表)
9. [端口 ↔ 内部信号 对应关系](#9-端口--内部信号-对应关系)
10. [小白易错点 + 下一篇](#10-小白易错点--下一篇)

---

## 1. 文件开头：库（第 1～5 行）

```vhdl
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_arith.ALL;
USE IEEE.STD_LOGIC_signed.ALL;
USE IEEE.NUMERIC_STD.ALL;
```

| 语句 | 小白话 |
|------|--------|
| `LIBRARY IEEE;` | 打开 IEEE 标准库这个“书架” |
| `USE …STD_LOGIC_1164.ALL` | 拿来 `STD_LOGIC`、`STD_LOGIC_VECTOR`、`rising_edge` 等 |
| `USE …STD_LOGIC_arith.ALL` | **老库**：`CONV_INTEGER`、`CONV_STD_LOGIC_VECTOR`（本工程大量用） |
| `USE …STD_LOGIC_signed.ALL` | **老库**：把向量当有符号做运算 |
| `USE …NUMERIC_STD.ALL` | **新库**：`unsigned`/`signed`（也引用了） |

**小白注意：** 新老算术库混用是历史遗留；先跟着读，不要随便删某一个 `USE`。

---

## 2. ENTITY 是什么（第 7～39 行）

```vhdl
ENTITY SSTMC_FPGA IS
	PORT(
		…一长串引脚…
	);
END SSTMC_FPGA;
```

| 概念 | 含义 |
|------|------|
| **ENTITY** | 这块 FPGA 顶层对**外部世界**的接口说明书 |
| **PORT** | 每个物理引脚：名字、进/出、类型 |
| **ARCHITECTURE**（第 41 行起） | 内部怎么实现（声明 + `BEGIN` 后的逻辑） |

类比：ENTITY = 芯片管脚图；ARCHITECTURE = 芯片内部电路。

语法要点：

- `IN`：只能从外部读进来，内部不能驱动它  
- `OUT`：内部驱动外部；老标准里内部不宜再读 OUT（本工程多用中间 SIGNAL）  
- 同一行可写多个同类型端口：`zz_r, zc_r : IN STD_LOGIC;`

---

## 3. 端口总览（一张表）

本顶层一共 **约 40 个端口名**（部分同一行声明）。按功能分组：

| 分组 | 端口 | 数量感 |
|------|------|--------|
| 时钟 | `CLKIN` | 1 |
| 光纤数据 | `zz_r/t`, `zc_r/t` | 4 |
| 三相同步 | `zc_a/b/c` | 3 |
| 电压 ADC | `UAD1/2_CLK`, `UAD1/2_DAT` | 4 |
| 驱动故障 | `F_FLT1～4` | 4 |
| H 桥驱动 | `FHOE`, `FHRDY×2`, `FHS1～4` | 7 |
| DC 驱动脚 | `FLOE`, `FL1～3 S1/S2` | 7 |
| 风扇 | `FFAN_FB1`, `FFAN_PWM`, `FFAN_COM` | 3 |
| 温度 ADC | `F_T1～5 CLK/OUT` | 10 |
| LED | `F_LED1～4` | 4 |

---

## 4. 端口分组逐句

### 4.1 时钟（第 9 行）

```vhdl
CLKIN : IN STD_LOGIC;  --50MHZ
```

| 项 | 说明 |
|----|------|
| 方向 | `IN` |
| 引脚（.qsf） | N11 |
| 物理 | 板载 **50 MHz** 晶振 |
| 进 FPGA 后干什么 | 复位计数、20 kHz/5 Hz 分频、通信、均流、软启、保护、LED；并进 PLL 得到约 120 MHz |

---

### 4.2 光纤：系统链路 ZZ + 从控链路 ZC（第 11～13 行）

```vhdl
zz_r, zc_r       : IN  STD_LOGIC;
zz_t, zc_t       : OUT STD_LOGIC;
zc_a, zc_b, zc_c : OUT STD_LOGIC;
```

#### 数据光纤（真正传帧）

| 端口 | 方向 | 引脚 | 连谁 | 人话 |
|------|------|------|------|------|
| `zz_r` | IN | T12 | 系统总控 | **收**系统发来的串行比特 |
| `zz_t` | OUT | T13 | 系统总控 | **发**给系统（代码里相对内部发送信号**取反**） |
| `zc_r` | IN | R11 | 单元从控 | **收**从控串行比特 |
| `zc_t` | OUT | T10 | 单元从控 | **发**给从控（同样取反） |

命名习惯：

- **zz** ≈ 系统（总）↔ 本单元主控  
- **zc** ≈ 本单元主控 ↔ 单元从控  
- **`_r`** = receive（收），**`_t`** = transmit（发）

位宽约定（声明区常量，后面详表）：

| 链路 | 本板接收 | 本板发送 |
|------|----------|----------|
| ZZ | 54 bit | 51 bit |
| ZC | 43 bit | 21 bit |

#### 相位同步（不是数据帧）

| 端口 | 方向 | 引脚 | 人话 |
|------|------|------|------|
| `zc_a` | OUT | R9 | A 相载波/半周期同步脉冲，给从控对齐 |
| `zc_b` | OUT | T8 | B 相 |
| `zc_c` | OUT | T7 | C 相 |

来自内部 DC 工作 PWM 的半周期标志，**不是**光纤协议里的数据位。

```
系统 ←zz_t/zz_r→ 本FPGA ←zc_t/zc_r→ 从控
                      ↓
                   zc_a/b/c（同步）
```

---

### 4.3 直流电压 ADC（AMC1305）（第 15～16 行）

```vhdl
UAD1_CLK, UAD2_CLK : OUT STD_LOGIC;
UAD1_DAT, UAD2_DAT : IN  STD_LOGIC;
```

| 端口 | 方向 | 人话 |
|------|------|------|
| `UAD1_CLK` / `UAD2_CLK` | OUT | FPGA 提供给两路隔离调制器的 **SCLK** |
| `UAD1_DAT` / `UAD2_DAT` | IN | 芯片吐出的 **DOUT** 比特流 |

内部对应：

| 外部 | 内部结果信号 | 含义 |
|------|--------------|------|
| 通道 1 | `sig_UTh` | 直流上臂电压 |
| 通道 2 | `sig_UBh` | 直流下臂电压 |
| 合成 | `sig_UhO` | 总压相关 |
| 过压标志 | `sig_UdGY` | 过压预警（再进保护） |

模块：`AMC1305_16bit_Controller`（见 08 篇）。

---

### 4.4 驱动故障输入（第 18～19 行）

```vhdl
F_FLT1, F_FLT2 : IN STD_LOGIC;
F_FLT3, F_FLT4 : IN STD_LOGIC;
```

| 端口 | 方向 | 引脚（约） | 人话 |
|------|------|------------|------|
| `F_FLT1～4` | IN | A14, A13, A15, B15 | 驱动板故障反馈，**低电平**表示有故障意图 |

处理进程：`Dv_Ft`（**1259～1303**）。
**重要现状：** 持续低电平计数逻辑还在，但 **`sig_Dvft(0～3) <= '1'` 被注释掉** → 这些脚当前**可能不会真正锁进总故障**。调现场时要知道。

---

### 4.5 H 桥（HB）驱动输出（第 21～24 行）

```vhdl
FHOE_DRV            : OUT STD_LOGIC;
FHRDY_12, FHRDY_34  : OUT STD_LOGIC;
FHS1_DRV, FHS2_DRV  : OUT STD_LOGIC;  -- PHB_ATop, PHB_ABot
FHS3_DRV, FHS4_DRV  : OUT STD_LOGIC;  -- PHB_BTop, PHB_BBot
```

| 端口 | 方向 | 引脚（约） | 人话 |
|------|------|------------|------|
| `FHOE_DRV` | OUT | A12 | H 桥输出使能；**本工程常驱动为 `'0'`** |
| `FHRDY_12` | OUT | A10 | 桥臂 1/2 就绪类信号 |
| `FHRDY_34` | OUT | B11 | 桥臂 3/4 就绪 |
| `FHS1_DRV` | OUT | A8 | A 臂上管（ATop） |
| `FHS2_DRV` | OUT | A9 | A 臂下管（ABot） |
| `FHS3_DRV` | OUT | A7 | B 臂上管（BTop） |
| `FHS4_DRV` | OUT | B7 | B 臂下管（BBot） |

命令来源：系统光纤下发的 `sig_HPwma/b` → 死区 `sig_HPwmDa/b`（`SqHBPWM` **1022～1044**）→ `PWM_HBbs`（**1047～1077**）生成四管波形。
使能条件还看 `sig_HPwm`、`sig_Bs`、`sig_CLR` 等（见 07 篇）。

---

### 4.6 直流侧（DC）驱动脚（第 26～29 行）

```vhdl
FLOE_DRV            : OUT STD_LOGIC;
FL1S1_DRV, FL1S2_DRV : OUT STD_LOGIC;
FL2S1_DRV, FL2S2_DRV : OUT STD_LOGIC;
FL3S1_DRV, FL3S2_DRV : OUT STD_LOGIC;
```

| 端口 | 设计意图 | **当前工程实际**（BEGIN 后 191～196 行） |
|------|----------|------------------------------------------|
| `FLOE_DRV` | DC 输出使能 | 常 `'0'` |
| `FL1S1_DRV` | DC 相管脚 | **接成 `CLKIN`（调试）** |
| `FL1S2_DRV` | | **接成 `sig_clk20KHz`** |
| `FL2S1/S2` | | **接成 `sig_HPwma/b`** |
| `FL3S1/S2` | | **接成 `sig_RES` / `sig_clkMHz`** |

正式把 Boost/工作 PWM 打到这些脚的 `PWM_DCbs` **整段被注释**。  
读代码时：**不要默认这些脚上是 DC 六管正式波形。**

---

### 4.7 风扇（第 31～32 行）

```vhdl
FFAN_FB1           : IN  STD_LOGIC;
FFAN_PWM, FFAN_COM : OUT STD_LOGIC;
```

| 端口 | 方向 | 人话 |
|------|------|------|
| `FFAN_FB1` | IN | 风扇反馈/转速类；源码里曾参与保护，现有注释 |
| `FFAN_PWM` | OUT | 风扇调速 PWM（三角波与 `sig_P23t` 比较） |
| `FFAN_COM` | OUT | 风扇公共/使能，正常时常 `'1'` |

进程：`TrFAN`（**320～344**，见 02 篇）。总故障或复位时 PWM 固定安全电平。

---

### 4.8 温度 ADC（AMC1035×5）（第 34～35 行）

```vhdl
F_T1CLK, F_T2CLK, F_T3CLK, F_T4CLK, F_T5CLK : OUT STD_LOGIC;
F_T1OUT, F_T2OUT, F_T3OUT, F_T4OUT, F_T5OUT : IN  STD_LOGIC;
```

| 端口 | 方向 | 人话 |
|------|------|------|
| `F_TnCLK` | OUT | 第 n 路温度芯片的 SCLK（工程里五路常同源） |
| `F_TnOUT` | IN | 第 n 路 DOUT 比特流 |

顶层例化对应关系：

| 外部脚 | 内部信号 | 用途 |
|--------|----------|------|
| CH1～5 | `sig_T4O`～`sig_T8O` | 本板五路温度（12 bit） |
| （从控来的温度） | `sig_T1O`～`sig_T3O` → 缩放 `sig_T1s`～`T3s` | 经 ZC 光纤上来，再打包给系统 |

模块：`AMC1035_5CH_Controller`（见 08 篇）。

---

### 4.9 LED（第 37 行）

```vhdl
F_LED1, F_LED2, F_LED3, F_LED4 : OUT STD_LOGIC;
-- 注释：LED1系统-主控通信; LED2主控-从控; LED3重故障/H-PWM; LED4 D-PWM
```

| 端口 | 引脚（约） | 含义（源码注释 + 逻辑） |
|------|------------|-------------------------|
| `F_LED1` | T3 | 系统↔本单元通信活着（收帧翻转等） |
| `F_LED2` | T2 | 本单元↔从控通信活着 |
| `F_LED3` | R2 | 闪≈H-PWM 工作；总闭锁时常灭 |
| `F_LED4` | R1 | D-PWM 相关指示；光纤单帧错误时会被拉灭 |

上电约 5 s 内还有复位闪烁效果（`sig_ledres`，见 02 篇）。

---

## 5. ARCHITECTURE 声明区总览（第 41～188 行）

```vhdl
ARCHITECTURE BEHAV OF SSTMC_FPGA IS
	-- 这里只能：CONSTANT / SIGNAL / COMPONENT / 类型…
BEGIN
	-- 这里才能：赋值、PROCESS、例化
```

声明区 = **资源清单**：先报有哪些常数、内部导线、要例化哪些子模块。  
**不能**在声明区写 `y <= a and b` 这种执行语句。

### 5.1 声明区行号快查

| 行号 | 内容 |
|------|------|
| 41 | `ARCHITECTURE BEHAV OF SSTMC_FPGA IS` |
| 43～55 | 全局常量（死区、过温、Boost 等） |
| 57～63 | 时钟 / 复位 / 闭锁 / LED 中间量 |
| 65～71 | `COMPONENT sz_pll` |
| 74～89 | ZZ 通信常量与信号 |
| 93～105 | ZC 通信常量与信号 |
| 108～121 | `COMPONENT TX_Comm` |
| 125～126 | `sig_UdGY`、`sig_T4O`～`sig_T8O` |
| 127～140 | `COMPONENT AMC1305_16bit_Controller` |
| 142～163 | `COMPONENT AMC1035_5CH_Controller` |
| 166 | `CH1_fI`～`CH3_fI` |
| 168～176 | HB / DC Boost PWM 信号 |
| 179～187 | LED 边沿检测 + DC 工作三角波（见 **7.6**） |
| 189 | `BEGIN`（逻辑见 **02** 篇） |

---

## 6. 常量 CONSTANT 全表

| 常量 | 行号 | 值 | 含义（结合注释） |
|------|------|-----|------------------|
| `BS_MAXCNT` | 43 | 750 | Boost 三角波相关：注释 80 kHz≈120M/2/750 |
| `BS_MDUCNT` | 44 | 13653 | Boost/调制相关计数常数 |
| `D_AUTO_OFF_DELAY_CNT` | 45 | 10000 | D 自动关断延时计数（闭锁后延时清 `Dauto`） |
| `NumFI` | 47 | 180 | 故障输入滤波：180/50MHz≈**3.6 µs** |
| `NumHSQ` | 48 | 192 | **HB 死区**：192/120MHz≈**1.6 µs** |
| `NumDSQ` | 49 | 24 | **DC 死区**：24/120MHz≈**200 ns** |
| `T1safeACT` | 51 | 162 | 温度组 1 动作阈值（过温开始计时） |
| `T1safeRES` | 52 | 142 | 温度组 1 恢复阈值（滞回低于此清计数） |
| `T2safeACT` | 53 | 176 | 温度组 2 动作阈值 |
| `T2safeRES` | 54 | 156 | 温度组 2 恢复阈值 |
| `TsafeTimer` | 55 | 60000 | 过温持续时间计数上限 |
| `zz_DELAY` | 74 | 20 | ZZ 光纤每 bit 占 20 个 50M 拍 → 400 ns |
| `zz_dtIN` | 75 | 54 | ZZ **接收**位宽 |
| `zz_dtOUT` | 76 | 51 | ZZ **发送**位宽 |
| `zc_DELAY` | 93 | 20 | ZC 同样 400 ns/bit |
| `zc_dtIN` | 94 | 43 | ZC 接收位宽 |
| `zc_dtOUT` | 95 | 21 | ZC 发送位宽 |

---

## 7. 信号 SIGNAL 分组全表

### 7.1 全局时钟 / 复位 / 闭锁 / LED（57～63）

| 信号 | 初值 | 含义 |
|------|------|------|
| `sig_RES` | `'1'` | 上电复位，高有效；约 1 ms 后变 `'0'` |
| `sig_clkMHz` | `'0'` | PLL 输出 ≈120 MHz |
| `sig_clk20KHz` | `'0'` | 20 kHz 心跳（通信/均流） |
| `sig_clk5Hz` | `'0'` | 5 Hz（LED 慢闪） |
| `sig_ledres` | `'0'` | 上电闪烁门控 |
| `sig_Bs` | `'0'` | **总闭锁** = 复位 OR 总故障 |
| `sig_Dzgz` | `'0'` | 从控上报的重故障 |
| `sig_OpenCLR` / `sig_OpenF` | `'0'` | 软启流程里“开清故障/开故障参与”的门控 |
| `led1～4_clk` | `'0'` | 各 LED 翻转时钟中间量 |

### 7.2 系统通信 ZZ（74～89）

| 信号 | 含义 |
|------|------|
| `sig_zzclk` | ZZ 发送启动时钟（接 20 kHz） |
| `sig_zzdtin` | 收自系统的 54 bit |
| `sig_zzdtout` | 发给系统的 51 bit |
| `sig_zzFiberT` | 发送模块原始输出（再取反到 `zz_t`） |
| `sig_zzsinFt` | ZZ 单帧头尾/校验错误 |
| `sig_zzFinish` | ZZ 收帧完成脉冲 |
| `sig_zzclk_r/edge` | 20 k 边沿检测 |
| `sig_zzFinish_r/edge` | 收完成边沿检测 |
| `sig_P15t～P19t`, `sig_P23t` | 系统下发参数（周期、Kp、Ki、风扇等） |
| `sig_Pt` | 复用参数整包（并转发给从控） |
| `sig_Idzl` | 均流电流给定 |
| `sig_CLR` | 清故障命令 |
| `sig_HPwm` | H 桥 PWM 使能 |
| `sig_Dpwm` / `sig_Dsoft` | DC 工作/软启相关标志 |
| `sig_I1O～I3O` | 三相电流（主要来自从控） |
| `sig_Cerr` | 16 bit **通信/系统故障位图**（含总故障 bit15） |
| `sig_Dvft` | 16 bit **器件/温度等故障位图** |
| `sig_UhO`, `sig_UTh`, `sig_UBh` | 总压 / 上臂 / 下臂电压 |

### 7.3 从控通信 ZC（92～105）

| 信号 | 含义 |
|------|------|
| `sig_zcclk` | ZC 发送启动（同 20 kHz） |
| `sig_zcdtin` / `sig_zcdtout` | 收 43 / 发 21 |
| `sig_zcFiberT` / `sinFt` / `Finish` | 同 ZZ 一套语义 |
| `sig_T1O～T3O` | 从控温度原始 |
| `sig_T1s～T3s` | 缩放后塞进 ZZ 上行 |

### 7.4 采样（125～126）

| 信号 | 含义 |
|------|------|
| `sig_UdGY` | 直流过压预警 |
| `sig_T4O～T8O` | 本板五路温度 12 bit |

### 7.5 均流 + HB/DC PWM（166～187）— 简表

| 信号 | 含义 |
|------|------|
| `CH1_fI～CH3_fI` | 三相均流频率修正量（约 ±500） |
| `sig_HPwma/b` | HB 两臂开关命令（系统下发） |
| `sig_HPwmDa/b` | HB 死区后 |
| `sig_Dauto` / `sig_DPwm_new` | DC 自动运行 / 新 PWM 命令 |
| `sig_Fauto` | 自动频率爬升量（到 1500 才开均流） |
| `sig_DCpwm14a/b/c` | DC **工作** PWM 输出 |
| `sig_DCpwm14Da/b/c` | DC 工作死区后 |
| `sig_DBpwm14*` / `23*` | DC **Boost** PWM |
| `Driveou1` | Boost 三角波比较阈值 |
| `sig_HPwma_r/edge` 等 | LED 边沿检测（见 **7.6**） |
| `up_*`～`sig_zcc` | DC 工作三角波 + 同步（见 **7.6**） |

---

### 7.6 LED 边沿检测与 DC 三角波信号详解（第 179～187 行）

源码声明：

```vhdl
SIGNAL sig_HPwma_r, sig_DCpwm14a_r       : STD_LOGIC := '0';
SIGNAL sig_HPwma_edge, sig_DCpwm14a_edge : STD_LOGIC := '0';

SIGNAL up_a, up_b, up_c                  : STD_LOGIC;
SIGNAL cnt_a, cnt_b, cnt_c                : INTEGER RANGE -32767 TO 32767;
SIGNAL max_a, max_b, max_c                : INTEGER RANGE -32767 TO 32767;
SIGNAL new_max_a, new_max_b, new_max_c    : INTEGER RANGE -32767 TO 32767;
SIGNAL half_a, half_b, half_c            : INTEGER RANGE -32767 TO 32767;
SIGNAL sig_zca, sig_zcb, sig_zcc          : STD_LOGIC := '0';
```

下面分两组：**LED 边沿检测** 和 **DC 工作 PWM 三角波**。

---

#### A. LED 边沿检测：`sig_HPwma_r` / `sig_HPwma_edge` / `sig_DCpwm14a_r` / `sig_DCpwm14a_edge`

| 信号 | 类型 | 初值 | 谁用 | 干什么 |
|------|------|------|------|--------|
| `sig_HPwma_r` | `STD_LOGIC` | `'0'` | `P_Hled` | 保存 **上一拍** 的 `sig_HPwma` |
| `sig_HPwma_edge` | `STD_LOGIC` | `'0'` | `P_Hled` | 本拍检测到 **上升沿** 时为 `'1'` |
| `sig_DCpwm14a_r` | `STD_LOGIC` | `'0'` | `P_Dled` | 保存上一拍的 `sig_DCpwm14a` |
| `sig_DCpwm14a_edge` | `STD_LOGIC` | `'0'` | `P_Dled` | 本拍检测到上升沿时为 `'1'` |

**为什么需要 `_r` 和 `_edge`？**

LED 要显示「PWM 在工作」，不能只看电平一直为 1（那样灯会一直亮），而是看 **PWM 有没有在跳变**。  
做法：每个 50 MHz 时钟沿比较「当前值」和「上一拍存的值」：

```
本拍 sig_HPwma = 1，上一拍 sig_HPwma_r = 0  → 上升沿 → sig_HPwma_edge = 1
其它情况                                      → sig_HPwma_edge = 0
```

逻辑等价（`P_Hled` 里）：

```vhdl
sig_HPwma_r <= sig_HPwma;                    -- 先打一拍
IF (sig_HPwma='1') AND (sig_HPwma_r='0') THEN
  sig_HPwma_edge <= '1';
ELSE
  sig_HPwma_edge <= '0';
END IF;
```

| 进程 | 行号 | 监视信号 | 边沿信号 | 驱动 LED | 含义 |
|------|------|----------|----------|----------|------|
| `P_Hled` | 220～243 | `sig_HPwma` | `sig_HPwma_edge` | `F_LED3` | H 桥 PWM 在跳 → 灯闪 |
| `P_Dled` | 245～269 | `sig_DCpwm14a` | `sig_DCpwm14a_edge` | `F_LED4` | A 相 DC 工作 PWM 在跳 → 灯闪 |

**注意：**

- `_r` / `_edge` **只给 LED 用**，不参与功率驱动。  
- `sig_DCpwm14a` 是 A 相 DC **工作** PWM（来自 `PHASE_PROC`），不是 HB 的 `sig_HPwma`。  
- 边沿检测在 **50 MHz `CLKIN`** 域；PWM 频率远低于 50M，所以能数到边沿。

**LED3 闪烁节奏（`P_Hled`）：**

- 若 `sig_Dvft(15)=0`（HB 未报工作）→ 不闪  
- 每来一个 `sig_HPwma_edge`，内部计数；计满约 1200 次边沿 → 翻转 `led3_clk` → `F_LED3` 闪

**LED4 类似（`P_Dled`）：** 用 `sig_DCpwm14a_edge`，计满约 10000 次边沿翻转。

---

#### B. DC 工作 PWM 三角波：`up_*` / `cnt_*` / `max_*` / `new_max_*` / `half_*`

这组信号在 **120 MHz**（`sig_clkMHz`）域，由三个进程配合：

| 进程 | 行号 | 时钟 | 主要更新 |
|------|------|------|----------|
| `CALC_NEW_MAX` | 882～927 | 50 MHz `CLKIN` | `new_max_a/b/c` |
| `UPDATE_THRESHOLD` | 929～952 | 120 MHz | `max_*`、`half_*` |
| `PHASE_PROC` | 954～1017 | 120 MHz | `up_*`、`cnt_*`、`sig_DCpwm14a/b/c`、`sig_zca/b/c` |

**人话：** 三相各自一个三角波计数器；三角波周期由 `max_*` 决定；过 `half_*` 比较产生 PWM 和同步脉冲。

---

##### B.1 `new_max_a/b/c` — 算出来的「目标周期」

在 `CALC_NEW_MAX`（50 MHz）里，每个时钟沿算一次：

```text
new_max ≈ P15（系统给的周期基础） + Fauto（自动频偏） - CH_fI（均流修正）
```

再限幅到 **750～2000**。

| 量变大 | `new_max` 变化 | 对 PWM 的影响 |
|--------|----------------|---------------|
| `sig_P15t` 大 | 周期计数大 | 频率变低、周期变长 |
| `sig_Fauto` 大 | 同上 | 软启爬频 |
| `CH1_fI` 大（均流） | `new_max` 减小 | A 相频率略升（均流调节） |

`new_max_*` 是**目标值**，不会每个 120M 拍都直接改波形，避免周期突变毛刺。

---

##### B.2 `max_a/b/c` 与 `half_a/b/c` — 当前生效的周期与半周期

在 `UPDATE_THRESHOLD`（120 MHz）里：

- 只有当 `cnt_*` 到达 **0 或 max**（三角波折返点）时，才把 `new_max_*` 装入 `max_*`  
- 同时：`half_* <= new_max_* / 2`

| 信号 | 含义 |
|------|------|
| `max_a` | A 相三角波 **当前** 周期计数值（750～2000） |
| `half_a` | `max_a` 的一半，用作 **比较阈值** |

**为什么在折返点才更新？**  
若在三角波中间突然改 `max`，波形会撕开出尖峰；在顶点/底点改最安全。

---

##### B.3 `up_a/b/c` — 三角波方向（加还是减）

| `up_*` | `cnt_*` 怎么变 |
|--------|----------------|
| `'1'` | 每个 120M 拍 `cnt + 1`（爬坡） |
| `'0'` | 每个 120M 拍 `cnt - 1`（下坡） |

折返规则（`PHASE_PROC`）：

- `cnt <= 1` → 强制 `up='1'`，从 0 往上爬  
- `cnt >= max-1` → 强制 `up='0'`，从 max 往下走  

三相 **B/C 相复位时 cnt 初值不同**（215、270），实现 **错相**，不是三相同步三角波。

---

##### B.4 `cnt_a/b/c` — 三角波当前位置

| 属性 | 说明 |
|------|------|
| 类型 | `INTEGER`，范围 -32767～32767 |
| 时钟 | 120 MHz，在 `PHASE_PROC` 里更新 |
| 行为 | 在 0～`max_*` 之间来回走，形成三角波 |

示意（A 相，`max_a=1000`，`half_a=500`）：

```
cnt:  0 → 500 → 1000 → 500 → 0 → …
      爬坡      下坡
```

---

##### B.5 `sig_DCpwm14a/b/c` — DC 工作 PWM 输出

在 `PHASE_PROC` 里与 `half_*` 比较：

```vhdl
IF cnt_a >= half_a THEN
  sig_DCpwm14a <= '1';
ELSE
  sig_DCpwm14a <= '0';
END IF;
```

| 条件 | PWM 电平 | 占空比直觉 |
|------|----------|------------|
| `cnt < half` | `'0'` | 低电平段 |
| `cnt >= half` | `'1'` | 高电平段 |

`half = max/2` 时，占空比约 **50%**；若将来改比较规则，占空比会变。  
B/C 相同逻辑 → `sig_DCpwm14b/c`。

之后这些信号还会进 `SqDCPWM` 做死区 → `sig_DCpwm14Da/b/c`（见 07 篇）。

---

##### B.6 `sig_zca/b/c` — 三相同步脉冲（→ 引脚 `zc_a/b/c`）

**与 `sig_DCpwm14a/b/c` 在同一处赋值，逻辑完全相同：**

```vhdl
IF cnt_a >= half_a THEN
  sig_DCpwm14a <= '1';
  sig_zca      <= '1';
ELSE
  sig_DCpwm14a <= '0';
  sig_zca      <= '0';
END IF;
```

| 信号 | 去向 | 用途 |
|------|------|------|
| `sig_zca` | 端口 `zc_a` | 告诉从控：A 相载波已过半周期 |
| `sig_zcb` | 端口 `zc_b` | B 相同步 |
| `sig_zcc` | 端口 `zc_c` | C 相同步 |

**不是光纤数据帧**，是 **相位对齐用的同步线**，让从控与本单元 DC PWM 同相工作。

顶层还有：

```vhdl
zc_a <= sig_zca;
zc_b <= sig_zcb;
zc_c <= sig_zcc;
```

---

#### C. 这组信号关系总图

```
50 MHz  CALC_NEW_MAX
              ↓
         new_max_a/b/c  （目标周期，750～2000）
              ↓ 仅在 cnt 到 0/max 时装入
120 MHz  max_a/b/c, half_a/b/c
              ↓
120 MHz  PHASE_PROC
    up_*  → 控制 cnt 加/减
    cnt_* → 三角波位置
              ↓
    cnt >= half_* ?
         ├─ sig_DCpwm14a/b/c  → DC 工作 PWM → 死区 → 驱动（或调试脚）
         └─ sig_zca/b/c       → zc_a/b/c 引脚 → 从控同步
```

```
50 MHz  P_Hled / P_Dled
    sig_HPwma ──→ _r / _edge ──→ F_LED3
    sig_DCpwm14a ──→ _r / _edge ──→ F_LED4
```

---

#### D. 小白易错点（本组信号）

1. **`sig_HPwma_r` 不是 HB 驱动输出**，只是 LED 用的上一拍缓存。  
2. **`new_max` 和 `max` 不是同一个**：前者是目标，后者是当前生效周期。  
3. **`half = max/2`** 时 PWM 与 `sig_zca` 同高同低；改比较逻辑会一起变。  
4. **`cnt_a/b/c` 初值不同** → 三相错相，不要假设三相同步。  
5. **LED 边沿检测在 50M**，三角波在 **120M**，别混时钟域。  
6. `INTEGER RANGE -32767 TO 32767` 是 VHDL 类型范围，实际 `max` 只用 750～2000。

---

## 8. 组件 COMPONENT 全表

声明 = “我准备用的子模块长什么样”；真正接线在 `BEGIN` 后的 `PORT MAP`。

### 8.1 `sz_pll`（65～71）

| 端口 | 接到顶层 |
|------|----------|
| `refclk` | `CLKIN` |
| `rst` | `sig_RES` |
| `outclk_0` | `sig_clkMHz` |

50 MHz → ≈120 MHz。Quartus IP，一般不手改。

### 8.2 `TX_Comm`（108～121）

| GENERIC | 默认 | ZZ 实例 | ZC 实例 |
|---------|------|---------|---------|
| `DELAY` | 20 | 20 | 20 |
| `DtinN` | 41 | **54** | **43** |
| `DtOUT` | 51 | **51** | **21** |

| 端口 | 含义 |
|------|------|
| `RESET/CLK/TXclk` | 复位、50M、发送启动 |
| `FiberR` / `FiberT` | 光纤收 / 发 |
| `TXdtOut` / `TXdtIn` | 要发的并行包 / 收到的并行包 |
| `TXSinFt` / `TXFinish` | 单帧错 / 收成功 |

详解见 **03** 篇。顶层例化：`ZZ_COMM` **424～439**，`ZC_COMM` **608～624**（见 **04** / **05**）。

### 8.3 `AMC1305_16bit_Controller`（127～140）

双通道电压：SCLK×2、DOUT×2 → 三个 16 bit 数据 + 过压标志。

### 8.4 `AMC1035_5CH_Controller`（142～163）

五通道温度：SCLK×5、DOUT×5 → 五个 12 bit + `OUT_VALID`（顶层例化可能未接 VALID）。

---

## 9. 端口 ↔ 内部信号 对应关系

方便你从“板子脚”追到“代码变量”：

| 外部端口 | 行号 / 进程 | 主要内部去向 |
|----------|-------------|----------------|
| `CLKIN` | 9；进程见 **02** | 几乎所有 50M 进程；`sz_pll.refclk`（287～290） |
| `zz_r` | 11；`ZZ_COMM` 424～439 | `FiberR` → `sig_zzdtin` |
| `zz_t` | 12；439 | `NOT sig_zzFiberT` |
| `zc_r` | 11；`ZC_COMM` 608～624 | `FiberR` → `sig_zcdtin` |
| `zc_t` | 12；624 | `NOT sig_zcFiberT` |
| `zc_a/b/c` | 13；1150～1152 | `sig_zca/b/c` |
| `UAD*_CLK/DAT` | 15～16；`P_AMC1305` 1157～1167 | `sig_UTh/UBh/UhO/UdGY` |
| `F_TnCLK/OUT` | 34～35；`P_AMC1035` 1169～1186 | `sig_T4O`～`sig_T8O` |
| `FHS1～4` | 23～24；`PWM_HBbs` 1047～1077 | HB 死区后四管 |
| `F_FLT1～4` | 18～19；`Dv_Ft` 1259～1303 | 置位当前注释 |
| `FFAN_*` | 31～32；`TrFAN` 320～344 | `sig_P23t` 比较 |
| `F_LED1～4` | 37；见各进程 | `P_Hled` 220～243 / `P_Dled` 245～269 / 通信解码 |

总闭锁链（**201～202** 行并发赋值）：

```text
若干故障 → sig_Cerr(15)
sig_Bs = sig_RES OR sig_Cerr(15)  → 闭锁 PWM
```

---

## 10. 小白易错点 + 下一篇

1. **ENTITY 只有接口**，算法全在 ARCHITECTURE。  
2. **`sig_RES` 高有效**（`'1'`=复位中）。  
3. **`zz`/`zc` 别混**；`zc_a/b/c` 不是数据光纤。  
4. **发送脚相对模块内部取反**，示波器看引脚电平。  
5. **`FL*` 当前是调试引出**，不是完整 DC 驱动。  
6. **`F_FLT` 故障置位被注释**，和原理图对照时别误判。  
7. 声明区 SIGNAL 的 `:=` 只是**初值**，运行中改值用 `<=`。

---

## 下一篇

`02_复位时钟LED风扇逐句.md`：从 `BEGIN` 起，复位如何释放、时钟如何分频、LED/风扇如何动作。
