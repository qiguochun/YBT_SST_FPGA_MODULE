# 08 — 电压 / 温度采样与保护 逐句（小白向）

涉及文件：

- `AMC1305_16bit_Controller.vhd`
- `AMC1035_5CH_Controller.vhd`
- `SSTMC_FPGA.vhd` 中例化（1157～1186）、`P_GZSC`（1188～1255）、`Dv_Ft`（1259～1303）

| 行号 | 块 |
|------|-----|
| 1157～1167 | `P_AMC1305` |
| 1169～1186 | `P_AMC1035` |
| 1188～1255 | `P_GZSC` |
| 1259～1303 | `Dv_Ft` |

---

## 1. 电压模块 AMC1305（人话）

芯片是隔离 ΔΣ 调制器：FPGA 提供 SCLK，读 DOUT 比特流，**统计一段时间高电平占比** ≈ 模拟量。

### 1.1 生成 20 MHz 左右 SCLK（120 MHz 域）

```vhdl
var_cnt := var_cnt + 1;
WHEN 1 => sclk_internal <= '1';
WHEN 4 => sclk_internal <= '0';
WHEN 6 => var_cnt := 0;
```

周期 6 拍 → 120M/6 = **20 MHz**。两路 ADC 共用。

### 1.2 输入打两拍同步

`AMC*_DOUT` → `CH*_dout_sync1` → `sync2`，后面用 sync2。

### 1.3 过采样计数（OSR=20000）

在特定相位采样：

- DOUT=1 → 高电平计数 +1  
- `osr_cnt` 到 20000：

```vhdl
DATA_OUT_reg <= CONV_STD_LOGIC_VECTOR(H_level_cnt - OSR_VAL/2, 16);
```

减去半量程得到有符号偏移量，`DATA_VALID=1` 一拍。

### 1.4 滑动平均 `P_Ulpf` + 双口 RAM

用 `RAM_16_2048` 存最近 `NUMD=20` 个点：

- 新样本进、旧样本出  
- 累加和 / 20 → 平滑后的 `DATA_16BIT1/2`  
- `DATA_16BIT3` = 两路之和（总压相关）  
- 滞回比较 → `OUT_UdGY`（过压预警标志）

顶层连接：

```text
DATA_16BIT1 → sig_UTh（上）
DATA_16BIT2 → sig_UBh（下）
DATA_16BIT3 → sig_UhO（总）
OUT_UdGY    → sig_UdGY
```

---

## 2. 温度模块 AMC1035（人话）

五路结构与电压类似，但：

- 时钟域 **50 MHz**  
- 输出 **12 bit**  
- 结束时有标定公式，例如：

```vhdl
CH1_out <= CONV_STD_LOGIC_VECTOR(((CH1_Hcnt-10000)*785-5797)/16384, 12);
```

把原始计数换成工程温度量纲（系数由标定得到）。

顶层：`DATA_CH1～5` → `sig_T4O`～`sig_T8O`。

---

## 2.5 顶层 AMC 例化（1157～1186）

| 例化名 | 行号 | 输出信号 |
|--------|------|----------|
| `P_AMC1305` | 1157～1167 | `sig_UTh`、`sig_UBh`、`sig_UhO`、`sig_UdGY` |
| `P_AMC1035` | 1169～1186 | `sig_T4O`～`sig_T8O` |

---

## 3. 顶层保护 `P_GZSC`（1188～1255）

每约 **2500** 个 50M 周期（≈50 µs，与 20k 同数量级）检查一次：

### 过压

```vhdl
IF sig_UdGY='1' THEN
  计数到 800 → sig_Cerr(10)<='1';  -- 过压故障锁定
ELSE
  计数清零
END IF;
```

需要过压标志**持续一段时间**才置故障，防抖。

### 过温（T4～T8）

常量：

```vhdl
T1safeACT=162; T1safeRES=142;  -- 动作/恢复阈值（滞回）
T2safeACT=176; T2safeRES=156;
TsafeTimer=60000;              -- 超时计数
```

温度 > ACT → 计数；达到 `TsafeTimer` → 对应 `sig_Dvft(7～11)=1`。  
温度 < RES → 计数清零（滞回，避免在阈值附近抖）。

---

## 4. 器件故障 `Dv_Ft`（1259～1303）

`F_FLT1～4` 为低并持续 `NumFI`（180 拍 ≈ 3.6 µs）本应：

```vhdl
-- sig_Dvft(0) <= '1';   -- 注意：当前被注释！
```

**现状：计数逻辑还在，故障置位被注释 → 这些硬件故障暂时不会进入总故障。**  
读代码/调现场时要知道这一点。

---

## 5. 故障如何变成闭锁

```text
sig_Cerr(10) 过压
sig_Dvft(7～11) 过温
sig_Cerr(6) ZZ通信
sig_Cerr(0) ZC通信（还受 OpenF 门控）
sig_Dzgz 从控重故障（门控）
...
        OR
         ↓
   sig_Cerr(15) 总故障
         ↓
   sig_Bs = RES OR Cerr(15) → PWM 闭锁（源码 **201～202** 行）
```

---

## 6. 小白易错点

1. **ΔΣ 不是 SPI 读寄存器**，是比特定时计数。  
2. **电压有滑动平均**，温度公式有标定系数，别当裸计数用。  
3. **过压/过温都有时间滤波 + 滞回**。  
4. **`F_FLT` 置故障代码被注释**，和原理图对照时别误判。

---

## 系列收尾

回到 `00_模块总览与阅读指南.md` 按顺序复读；帧格式细节还可对照：

- `Docs_YBT学习指南/08_光纤通信帧与命令字.md`
- `Docs_YBT学习指南/09_PWM均流保护与风扇.md`

若某一段（例如 `BS_DC` 每个 Step、或 `ZZ_Decodeout` 某一 CASE）还要**纯逐行编号讲解**，指定进程名即可继续加细文档。
