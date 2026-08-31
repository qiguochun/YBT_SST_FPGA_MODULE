# 06 — 顶层 SSTMC_FPGA 走读

文件：`YBT_FPGA_SSTMC20260817_fan/SSTMC_FPGA.vhd`（**1306 行**，行号核对：2026-08-31）。  
按源码注释分区 0～9 读，并标出关键 SIGNAL 与行号。

| 行号 | 分区 | 详解文档 |
|------|------|----------|
| 1～188 | ENTITY + 声明 | `SSTMC逐句解析/01` |
| 189～344 | 复位 / 时钟 / LED / 风扇 | `SSTMC逐句解析/02` |
| 348～548 | ZZ 系统通信 | `SSTMC逐句解析/04` |
| 552～684 | ZC 从控通信 | `SSTMC逐句解析/05` |
| 688～878 | 均流 + Boost 软启 | `SSTMC逐句解析/06` |
| 882～1152 | DC 工作 PWM + HB/DC 死区 | `SSTMC逐句解析/07` |
| 1157～1303 | 采样 + 保护 + FLT | `SSTMC逐句解析/08` |
| 1306 | `END BEHAV` | — |

---

## 1. 文件头：库、实体、关键常量

| 行号 | 内容 |
|------|------|
| 1～5 | `LIBRARY` / `USE` |
| 7～39 | `ENTITY` 端口 |
| 41 | `ARCHITECTURE` 开始 |
| 43～45 | `BS_MAXCNT`、`BS_MDUCNT`、`D_AUTO_OFF_DELAY_CNT` |
| 47～49 | `NumFI`、`NumHSQ`、`NumDSQ` |
| 51～55 | `T1safeACT/RES`、`T2safeACT/RES`、`TsafeTimer` |
| 74～76 | `zz_DELAY`、`zz_dtIN`、`zz_dtOUT` |
| 93～95 | `zc_DELAY`、`zc_dtIN`、`zc_dtOUT` |

```vhdl
CONSTANT BS_MAXCNT : INTEGER := 750;     -- 80 kHz = 120M / 2 / 750
CONSTANT BS_MDUCNT : INTEGER := 13653;   -- 定义了但顶层未使用
CONSTANT D_AUTO_OFF_DELAY_CNT : INTEGER := 10000;  -- D 停机延迟，50M 下 200 µs

CONSTANT NumFI  : INTEGER := 180;        -- FLT 滤波 180/50M = 3.6 µs
CONSTANT NumHSQ : INTEGER := 192;        -- HB 死区 192/120M = 1.6 µs
CONSTANT NumDSQ : INTEGER := 24;         -- DC 死区 24/120M = 200 ns

CONSTANT T1safeACT : INTEGER := 162;     -- 温度动作阈值（T4~T6）
CONSTANT T1safeRES : INTEGER := 142;     -- 回差恢复
CONSTANT T2safeACT : INTEGER := 176;     -- T7~T8
CONSTANT T2safeRES : INTEGER := 156;
CONSTANT TsafeTimer: INTEGER := 60000;   -- 过温确认：20 kHz 节拍下约 3 s
```

通信位宽：

| 链路 | DELAY（比特时间，50 MHz 拍） | 收 DtinN | 发 DtOUT |
|------|------------------------------|----------|----------|
| zz 系统↔主控 | 20 → 400 ns/bit | 54 | 51 |
| zc 主控↔从控 | 20 | 43 | 21 |

---

## 2. 开头的调试引脚（191～202 行）

```vhdl
FL1S1_DRV<=CLKIN;           -- 191
FL1S2_DRV<=sig_clk20KHz;    -- 192
FL2S1_DRV<=sig_HPwma;       -- 193
FL2S2_DRV<=sig_HPwmb;       -- 194
FL3S1_DRV<=sig_RES;         -- 195
FL3S2_DRV<=sig_clkMHz;      -- 196

sig_zzclk <= sig_clk20KHz;  -- 198
sig_zcclk <= sig_clk20KHz;  -- 199
```

以及若干故障位强制 0：**200** 行 `Dvft(13,14)`、`Cerr(5,13,14)`。

总故障与闭锁（**201～202**）：

```vhdl
sig_Cerr(15) <= (sig_Dzgz AND sig_OpenF) OR (sig_Cerr(0) AND sig_OpenF)
             OR sig_Cerr(6) OR sig_Cerr(10)
             OR sig_Dvft(0) OR ... OR sig_Dvft(11);
sig_Bs <= sig_RES OR sig_Cerr(15);
```

`OpenF` 在 DC 软启完成约 1 s 后才置 1，避免上电瞬间从控故障把单元打死。

---

## 3. 分区 0：LED（205～269）

| 进程 | 行号 | 作用 |
|------|------|------|
| `P_LEDRES` | 205～218 | 上电 250e6/50M ≈ 5 s 内 `sig_ledres = clk5Hz`，之后为 0 |
| `P_Hled` | 220～243 | 统计 HB PWM 边沿，约 1200 个边沿翻转 `led3`；总故障时灯灭 |
| `P_Dled` | 245～269 | DC PWM 边沿翻转 `led4`；叠加 CLR 闪、zz/zc 单次通信故障 |

`F_LED1/2` 不在这里，而在 zz/zc 解码进程里：每成功一帧计数，5000 帧翻一次灯。

---

## 4. 分区 1：复位、时钟、风扇（274～344）

| 进程/例化 | 行号 | 作用 |
|-----------|------|------|
| `P_reset` | 274～285 | 1 ms 内部复位 |
| `P_PLL` | 287～290 | 50→120 MHz |
| `P_CLK20KHZ` | 292～304 | 2500 分频，1～1250 为高 |
| `P_CLK5HZ` | 306～318 | 10e6 分频 |
| `TrFAN` | 320～344 | 三角波 0～1000 与 `P23t` 比较出风扇 PWM；故障/复位时 PWM='1' |

风扇：载波 25 kHz（50 MHz、0～1000 三角波，往返 2000 拍）。`FFAN_COM` 运行时为 1。

---

## 5. 分区 2：系统 ↔ 单元主控（zz）（348～548）

四个块，顺序固定：

| 块 | 行号 |
|----|------|
| `ZZ_sc` 发送组帧 | 348～390 |
| `ZZ_Error` 通信超时 → `Cerr(6)` | 392～422 |
| `ZZ_COMM` 例化 `TX_Comm` | 424～439 |
| `ZZ_Decodeout` 收帧解码 | 441～548 |

### 发送 51 bit 布局（`sig_zzdtout`）

```
[50:46]  总故障? "01101" : "10110"
[45:32]  Cerr(13:0)
[31:16]  UhO（合成直流电压）
[15:0]   时分复用，14 拍一轮：
         1 I1    2 I2    3 I3    4 Dvft(11:0)
         5 UTh   6 UBh   7 T1s   8 T2s   9 T3s
         10 T4   11 T5   12 T6   13 T7   14 T8
         低 12 位数据，高 4 位通道号 0001～1110
```

电流上报截断：`"0001" & I1O(15 DOWNTO 4)`，相当于右移 4 位后带通道号。

### 接收 54 bit 布局（`sig_zzdtin`）

```
[53:44]  10 bit 命令（高5=H，低5=D），需连续 5 帧相同
[43]     HPwma
[42]     HPwmb
[41:29]  Idzl 高 13 位，再拼 "000" 成 16 位
[28:16]  P15t 低 13 位，高位补 0
[15:0]   复用参数，连续 4 帧相同后按 [15:13] 写入：
         000 P16t  001 P17t  010 P18t  011 P19t  111 P23t
```

D 停机：收到 D 闭锁且正在 `Dauto` 时，不是立刻 `Dauto=0`，而是 `D_AUTO_OFF_DELAY_CNT` 后再关，避免突变。

---

## 6. 分区 3：单元主控 ↔ 从控（zc）（552～684）

| 块 | 行号 |
|----|------|
| `ZC_sc` | 552～574 |
| `ZC_Error` | 576～606 |
| `ZC_COMM` | 608～624 |
| `ZC_Decodeout` | 626～684 |

### 发送 21 bit

```
[20:16]  CLR或OpenCLR → "01001"
         否则若 Bs     → "10100" 闭锁
         否则若 DPwm_new → "11010"
         否则            → "10100"
[15:0]   sig_Pt（系统参数透传）
```

### 接收 43 bit

```
[42:38]  "01101" 从控总故障 Dzgz=1；"10110" 正常
[37:35]  电流通道号，[34:19] 为 I1/I2/I3
[18:16]  001/010/011 → T1/T2/T3 在 [15:0]
         100 → 从控故障位映射到 Cerr(4:1,9:7,11) 和 Dvft(6:4)
```

温度线性变换（从控原始值 → 上报系统的 12 bit）：

```
Txs = (TxO * 225 - 18118) / 16384
```

通信故障 `Cerr(0)`。从控数据在 `Cerr(0)=1` 时整段复位。

---

## 7. 分区 4：均流 `JLcon`（688～772）

仅当 `sig_Fauto=1500`（软启频率爬升结束）且未闭锁、未 CLR、`Dauto=1` 时运行。

```
ek = IxO - Idzl          限幅 ±2047
yk += P17t * ek          积分，限幅 ±6.4e8
uk = P16t * ek + yk/20000
fI = sat(uk/64, ±500)    去调 PWM 周期
```

这是离散 PI：`P16t≈Kp`，`P17t≈Ki`。输出 `CH1_fI` 等在分区 6 里 **减小周期计数值**（电流偏大则周期变短/频率变高，具体效果取决于变换器特性）。

---

## 8. 分区 5：DC Boost 软启（777～878）

### `BS_DC`（777～836）

| Step | 行为 |
|------|------|
| 0 | 等 `Dauto=1` |
| 1 | `Dsoft=1`，`var_Drive` 从 1000 每 64000 拍 +1，到 4900（约 5 s） |
| 2 | 等 1250 拍（25 µs），切 `Dpwm=1`，`Fauto=750` |
| 3 | 每 200000 拍 `Fauto+1`，到 1499 后置 1500，`OpenCLR=1` |
| 4 | 再等 50e6 拍（1 s），`OpenCLR=0`，`OpenF=1`（从控故障开始计入总故障） |
| 5 | 等 `Dauto=0` 回 0 |

`Driveou1 = var_Drive * 307 / 4096`，把 1000～4900 映射到三角波比较值。

### `BS_PWM`（838～878）

120 MHz，三路三角波 0～750，相位错开（初值 `MAX`、`MAX/3`、`MAX/3` 且 updown 不同）。  
`DBpwm14x`：cnt ≤ Drive 开通；`DBpwm23x`：cnt ≥ MAX-Drive 开通。交错 Boost。

---

## 9. 分区 6：DC 工作 PWM（变频）（882～1017）

| 进程 | 行号 |
|------|------|
| `CALC_NEW_MAX` | 882～927 |
| `UPDATE_THRESHOLD` | 929～952 |
| `PHASE_PROC` | 954～1017 |

```
new_max_x = P15t + Fauto - CHx_fI    限幅 [750, 2000]
```

只在三角波到顶/到底时把 `max_x/half_x` 换成新值，避免周期中途改阈值出毛刺。

`PHASE_PROC`：三路独立三角波，`cnt >= half` 时 `DCpwm14x=1` 且 `zca/b/c=1`。  
初值不同实现相移：`cnt_a=750, up=0`；`cnt_b=215, up=1`；`cnt_c=270, up=0`。

120 MHz、max=750 → 往返 1500 拍 → 80 kHz；max=2000 → 30 kHz。软启把 Fauto 从 750 加到 1500，等于把频率从高频拉向低频（再叠加 P15 和均流）。

---

## 10. 分区 7：死区与 HB 输出（1022～1152）

| 块 | 行号 |
|----|------|
| `SqHBPWM` | 1022～1044 |
| `FHOE_DRV <= '0'` | 1046 |
| `PWM_HBbs` | 1047～1077 |
| `SqDCPWM` | 1080～1111 |
| `FLOE_DRV <= '0'` | 1113 |
| `PWM_DCbs`（已注释） | 1114～1149 |
| `zc_a/b/c` 引出 | 1150～1152 |

`SqHBPWM`：输入变化后等 192 拍再跟随，得到 `HPwmDa/b`。

`PWM_HBbs`：

- CLR：RDY=1，管脚 0，`Dvft(15)=0`
- Bs：RDY=0，全关
- HPwm=1：RDY=1，互补+死区，`Dvft(15)=1`（LED3 用它表示 HB 在工作）
- 否则全关

`SqDCPWM` 同样做 24 拍死区，但 **`PWM_DCbs` 被注释**，死区结果目前不送到引脚。  
`zc_a/b/c` 在 **1150～1152** 接到相位输出。

---

## 11. 分区 8：采样与软件保护（1157～1255）

| 块 | 行号 |
|----|------|
| `P_AMC1305` | 1157～1167 |
| `P_AMC1035` | 1169～1186 |
| `P_GZSC` | 1188～1255 |

`P_GZSC` 每 2500 拍（20 kHz）跑一次：

- `UdGY` 连续 800 次（40 ms）→ `Cerr(10)` 过压
- 各温度 > ACT 则累加，到 `TsafeTimer=60000`（3 s）置 `Dvft(7~11)`；低于 RES 清计数（故障位需 CLR 才清）

子模块细节见 `SSTMC逐句解析/08`。

---

## 12. 分区 9：器件 FLT（1259～1303）

`Dv_Ft`：`F_FLT1~4` 低电平持续 180 拍本应置 `Dvft(0~3)`，**赋值被注释**，硬件驱动故障暂不参与 `Cerr(15)`。

---

## 13. 顶层 SIGNAL 速查

| 信号 | 含义 |
|------|------|
| `sig_RES` | 内部复位，高有效 |
| `sig_clkMHz` | 120 MHz |
| `sig_Bs` | 总闭锁 |
| `sig_CLR` | 系统清故障 |
| `sig_HPwm` | 允许 HB 输出 |
| `sig_HPwma/b` | HB 两桥臂命令 |
| `sig_Dauto` | DC 自动/工作使能（系统 D_PWM） |
| `sig_Dsoft` / `sig_Dpwm` | Boost 阶段 / 工作 PWM 阶段 |
| `sig_DPwm_new` | 转发给从控的“软启/工作”命令 |
| `sig_Fauto` | 周期附加项，750→1500 |
| `sig_OpenF` | 允许从控故障计入总故障 |
| `sig_Idzl` | 均流电流给定 |
| `sig_P15t` | DC 周期基值 |
| `sig_P16t/P17t` | 均流 Kp/Ki |
| `sig_P23t` | 风扇给定 |
| `sig_Cerr(*)` | 故障位图，15=总故障 |
| `sig_Dvft(*)` | 装置/温度/工作状态标志 |
| `CH1_fI` 等 | 均流对周期的修正 ±500 |

故障位细节见 `08_光纤通信帧与命令字.md`。

逐句详解见 **`SSTMC逐句解析/`** 系列（00 为总目录）。
