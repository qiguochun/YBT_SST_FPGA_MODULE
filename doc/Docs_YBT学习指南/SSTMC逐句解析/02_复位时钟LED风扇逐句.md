# 02 — 复位 / 时钟 / LED / 风扇 逐句（小白向）

源文件：`SSTMC_FPGA.vhd` **189～344** 行（`BEGIN` 在 189，风扇 `TrFAN` 止于 344）

| 行号 | 块 |
|------|-----|
| 191～202 | 并发赋值 |
| 205～269 | LED |
| 274～344 | 复位 / PLL / 分频 / 风扇 |

---

## 本篇目标

搞清楚四件事：

1. 上电后谁在复位、何时放开  
2. 50 MHz 怎么变成 120 MHz / 20 kHz / 5 Hz  
3. 四个 LED 为什么闪  
4. 风扇 PWM 怎么产生  

---

## 1. BEGIN 后立刻执行的并发赋值（191～202）

ARCHITECTURE 的 `BEGIN` 之后，**没有写在 PROCESS 里**的赋值都是**并发**的：一直生效，不排队。

### 1.1 调试把内部信号引出到 DC 驱动脚（191～196）

```vhdl
FL1S1_DRV <= CLKIN;
FL1S2_DRV <= sig_clk20KHz;
FL2S1_DRV <= sig_HPwma;
FL2S2_DRV <= sig_HPwmb;
FL3S1_DRV <= sig_RES;
FL3S2_DRV <= sig_clkMHz;
```

| 行 | 源码 | 接到的信号 |
|----|------|------------|
| 191 | `FL1S1_DRV` | `CLKIN` |
| 192 | `FL1S2_DRV` | `sig_clk20KHz` |
| 193 | `FL2S1_DRV` | `sig_HPwma` |
| 194 | `FL2S2_DRV` | `sig_HPwmb` |
| 195 | `FL3S1_DRV` | `sig_RES` |
| 196 | `FL3S2_DRV` | `sig_clkMHz` |

小白记住：**现在这些脚不一定是“DC PWM 输出”**。

### 1.2 通信用 20 kHz（198～199）

```vhdl
sig_zzclk <= sig_clk20KHz;
sig_zcclk <= sig_clk20KHz;
```

系统通信、从控通信共用同一个 20 kHz 心跳。

### 1.3 故障位清零 + 总故障 + 总闭锁（200～202）

```vhdl
sig_Dvft(13) <= '0'; ...   -- 若干位强制为 0（未使用）
sig_Cerr(15) <= (...很多故障的 OR...);  -- 单元总故障
sig_Bs <= sig_RES OR sig_Cerr(15);      -- 总闭锁
```

| 信号 | `'1'` 时意味着 |
|------|----------------|
| `sig_Cerr(15)` | 本单元认为自己有严重故障 |
| `sig_Bs` | **闭锁 PWM**（复位中或有总故障） |

---

## 2. LED 上电闪烁门控 `P_LEDRES`（205～218）

```vhdl
P_LEDRES: PROCESS(CLKIN)
  VARIABLE var_cnt    : INTEGER ... := 0;
  VARIABLE var_ledres : STD_LOGIC := '0';
BEGIN
  IF (CLKIN'EVENT AND CLKIN = '1') THEN   -- 50MHz 上升沿
    IF (var_cnt >= 250000000) THEN
      var_ledres := '0';                 -- 约 5 秒后关掉“上电闪烁期”
    ELSE
      var_cnt := var_cnt + 1;
      var_ledres := '1';
    END IF;
    sig_ledres <= sig_clk5Hz AND var_ledres;
  END IF;
END PROCESS;
```

| 概念 | 解释 |
|------|------|
| `CLKIN'EVENT AND CLKIN='1'` | 老写法的上升沿，等于 `rising_edge(CLKIN)` |
| `250000000 / 50e6` | ≈ **5 秒** |
| `sig_ledres` | 上电 5 秒内 = 5Hz 方波；之后为 0 |

用途：上电时 LED 闪几下，方便看板子活着。

---

## 3. HB 指示灯 `P_Hled`（220～243）

逐步：

1. `sig_HPwma_r <= sig_HPwma`：把 HB 开关打一拍存起来  
2. 若本拍为 1、上一拍为 0 → `sig_HPwma_edge='1'`（**上升沿检测**）  
3. 若 `sig_Dvft(15)='0'`（HB 未真正工作）→ 计数清零，灯不闪  
4. 否则每来 1200 个边沿翻转一次 `led3_clk`  
5. `F_LED3 <= (NOT (led3_clk XOR sig_ledres)) AND (NOT sig_Bs)`  

| 现象 | 含义 |
|------|------|
| LED3 闪 | H-PWM 在工作 |
| 总闭锁 `sig_Bs=1` | LED3 灭 |

---

## 4. DC 指示灯 `P_Dled`（245～269）

逻辑与 HB 灯类似，边沿来自 `sig_DCpwm14a`。

最终：

```vhdl
F_LED4 <= (NOT (...)) AND (NOT sig_zzsinFt) AND (NOT sig_zcsinFt);
```

任一光纤**单帧校验/头尾错误**（`sinFt`）为 1 → LED4 灭，便于发现通信毛刺。

---

## 5. 上电复位 `P_reset`（274～285）——必懂

```vhdl
P_reset: PROCESS(CLKIN)
  VARIABLE var_cnt : INTEGER RANGE 0 TO 65535 := 0;
BEGIN
  IF (CLKIN'EVENT AND CLKIN = '1') THEN
    IF (var_cnt >= 49999) THEN
      sig_RES <= '0';          -- 放开复位
    ELSE
      var_cnt := var_cnt + 1;
      sig_RES <= '1';          -- 仍在复位
    END IF;
  END IF;
END PROCESS;
```

| 计算 | 结果 |
|------|------|
| 计数到 49999 | 共约 50000 个 50M 周期 |
| 50000 / 50e6 | ≈ **1 ms** |

**约定（本工程）：`sig_RES='1'` 表示复位有效（高有效）**。  
很多模块里写 `IF sig_RES='1' THEN ...清零...`。

---

## 6. PLL 例化（287～290）

```vhdl
P_PLL: sz_pll PORT MAP(
  refclk   => CLKIN,        -- 50 MHz 进
  rst      => sig_RES,      -- 复位期间 PLL 按住
  outclk_0 => sig_clkMHz    -- ≈120 MHz 出
);
```

| 用途 | 说明 |
|------|------|
| `sig_clkMHz` | HB/DC 死区、三角波 PWM、电压采样快时钟 |

`sz_pll.vhd` 是 Quartus 生成的 IP，一般不用手改。

---

## 7. 20 kHz 分频 `P_CLK20KHZ`（292～304）

```vhdl
var_cnt := var_cnt + 1;
CASE var_cnt IS
  WHEN 1    => sig_clk20KHz <= '1';   -- 拉高
  WHEN 1251 => sig_clk20KHz <= '0';   -- 拉低
  WHEN 2500 => var_cnt := 0;          -- 周期结束
  WHEN OTHERS => NULL;
END CASE;
```

| 参数 | 计算 |
|------|------|
| 周期 | 2500 × (1/50MHz) = **50 µs** → **20 kHz** |
| 高电平 | 约 1250 拍 → 约 50% 占空 |

**整机心跳**：每 50 µs 上升沿附近会组一帧光纤数据、触发发送。

---

## 8. 5 Hz 分频 `P_CLK5HZ`（306～318）

同理：数到 10000000 一圈 → **5 Hz**，给 LED 慢闪。

---

## 9. 风扇 `TrFAN`（320～344）

### 复位/故障时

```vhdl
IF (sig_RES = '1' OR sig_Cerr(15) = '1') THEN
  FFAN_PWM <= '1';   -- 关断侧电平（依硬件）
```

总故障时风扇 PWM 固定，避免乱转。

### 正常时：三角波比较

1. `cnt1a` 在 0～1000 之间来回加减（三角波）  
2. 与 `sig_P23t`（系统下发的风扇给定）比较  
3. `CONV_INTEGER(sig_P23t) <= cnt1a` → `FFAN_PWM` 为 0 或 1  

这就是经典 **三角波 + 比较值 = PWM 占空比**。

`FFAN_COM <= '1'`：通信/使能常开。

---

## 10. 本篇数据流小结

```
CLKIN 50MHz
  ├─ P_reset     → sig_RES (1ms 后释放)
  ├─ sz_pll      → sig_clkMHz ≈120MHz
  ├─ P_CLK20KHZ  → sig_clk20KHz → zz/zc 心跳
  ├─ P_CLK5HZ    → sig_clk5Hz → LED
  ├─ P_LEDRES/Hled/Dled → F_LED*
  └─ TrFAN       → FFAN_PWM (给定来自 sig_P23t)
```

---

## 11. 小白易错点

1. **`sig_RES` 高有效**，和有些工程“低复位”相反。  
2. **`CLKIN'EVENT AND CLKIN='1'`** = 上升沿。  
3. **20 kHz 是通信节拍，不是功率开关频率本身**（功率开关多在 120 MHz 域做）。  
4. **`FL*` 当前是调试线**，别当正式 DC PWM 波形去理解拓扑。

---

## 下一篇

`03_TX_Comm光纤通信逐句.md`：独立文件，收发状态机从第 1 行讲到最后一行。
