# 04 — VHDL 对照 Verilog 速成（只覆盖本工程写法）

目标：能读懂 YBT 里出现的 VHDL，而不是学完整语言。下面每条都尽量用 **本仓库真实代码** 对照。

---

## 1. 文件骨架

Verilog 模块：

```verilog
module uart_send (
    input  wire       clk,
    input  wire       rst,
    output reg  [7:0] data
);
    // ...
endmodule
```

VHDL 对应两段：**实体（接口）** + **结构体（实现）**。

```vhdl
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;           -- 逻辑类型 std_logic
USE IEEE.STD_LOGIC_arith.ALL;          -- CONV_INTEGER / CONV_STD_LOGIC_VECTOR（老库）
USE IEEE.STD_LOGIC_signed.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY SSTMC_FPGA IS                   -- = module 名
    PORT(
        CLKIN : IN  STD_LOGIC;
        zz_t  : OUT STD_LOGIC;
        ...
    );
END SSTMC_FPGA;

ARCHITECTURE BEHAV OF SSTMC_FPGA IS    -- = module 内部
    SIGNAL sig_RES : STD_LOGIC := '1'; -- = wire/reg
    CONSTANT NumHSQ : INTEGER := 192;  -- = localparam
    COMPONENT TX_Comm ... END COMPONENT;
BEGIN
    -- 并发语句、进程
END BEHAV;
```

记住：

| Verilog | VHDL（本工程） |
|---------|----------------|
| `module/endmodule` | `ENTITY/END` + `ARCHITECTURE/END` |
| `wire` / `reg` | 几乎都用 `SIGNAL`；进程里临时量用 `VARIABLE` |
| `localparam` | `CONSTANT` |
| `always @(posedge clk)` | `PROCESS` + `rising_edge(clk)` 或 `clk'EVENT AND clk='1'` |
| `assign y = a & b;` | 并发 `y <= a AND b;`（写在 BEGIN 下、PROCESS 外） |
| `parameter` 模块参数 | `GENERIC` |
| 例化 `.clk(clk)` | `PORT MAP(clk => clk)` |
| `'0` / `8'h3A` | `'0'` / `"00111010"` / `x"3A"`（本工程多用二进制位串） |

---

## 2. 类型：本工程实际用到的

| 类型 | 含义 | 对照 Verilog |
|------|------|--------------|
| `STD_LOGIC` | 1 bit，含 0/1/X/Z/U | `wire` / `reg` |
| `STD_LOGIC_VECTOR(n DOWNTO 0)` | 总线，**高位在左** | `[n:0]` |
| `INTEGER` / `INTEGER RANGE a TO b` | 算术用整数 | `integer` / 有范围可综合成有限位宽 |
| `BOOLEAN` | 本工程几乎不用 | — |

位宽例子：

```vhdl
SIGNAL sig_zzdtin : STD_LOGIC_VECTOR(zz_dtIN-1 DOWNTO 0);
-- zz_dtIN=54 → [53:0]
```

切片：`sig_zzdtin(53 DOWNTO 44)` = Verilog 的 `sig_zzdtin[53:44]`。

**字符 vs 位串：**

- `'1'` `'0'`：1 bit
- `"10110"`：5 bit 向量
- 不能把 `'1'` 直接赋给 VECTOR，要用 `"1"` 或拼接。

---

## 3. SIGNAL vs VARIABLE（最容易踩坑）

这是 VHDL 相对 Verilog 最大的思维差。

| | SIGNAL | VARIABLE |
|--|--------|----------|
| 声明位置 | Architecture 的 IS 区 | PROCESS 内部 |
| 赋值符 | `<=` | `:=` |
| 更新时机 | **进程结束后**才更新（像非阻塞） | **立刻**更新（像阻塞） |
| 能否出进程 | 能，可连到端口/其它进程 | 不能 |

Verilog：

```verilog
always @(posedge clk) begin
    a <= b;
    c <= a;     // 用的是旧 a
    d = a + 1;  // 阻塞，立刻
end
```

YBT 里典型混用（`P_reset`）：

```vhdl
P_reset:PROCESS(CLKIN)
    VARIABLE var_cnt : INTEGER RANGE 0 TO 65535 := 0;
BEGIN
    IF (CLKIN'EVENT AND CLKIN = '1') THEN
        IF (var_cnt >= 49999) THEN
            sig_RES <= '0';
        ELSE
            var_cnt := var_cnt + 1;   -- 立刻 +1
            sig_RES <= '1';
        END IF;
    END IF;
END PROCESS P_reset;
```

`var_cnt` 用变量才能在同一拍里判断“加完后是否溢出”；`sig_RES` 用信号输出。

经验：计数器、状态机 `Step` 本工程大量用 **VARIABLE**；对外端口和跨进程量用 **SIGNAL**。

---

## 4. 进程敏感表与时钟写法

本工程三种等价/近似写法都出现了：

```vhdl
IF (CLKIN'EVENT AND CLKIN = '1') THEN     -- 老写法
IF (RISING_EDGE(CLKIN)) THEN              -- 推荐，语义相同
ELSIF (sig_clkMHz'EVENT AND sig_clkMHz = '1') THEN
```

敏感表：

```vhdl
PROCESS(CLKIN)                 -- 只列时钟：同步时序（复位也同步）
PROCESS(sig_RES, CLKIN)        -- 异步复位：RESET='1' 分支不依赖时钟
PROCESS(sig_RES, FFAN_FB1, sig_Cerr(15), CLKIN)  -- 多信号异步条件
```

对照 Verilog：

```verilog
always @(posedge clk)                  // 同步
always @(posedge clk or posedge rst)   // 异步复位
```

**组合逻辑**在本工程很少单独开 PROCESS，多数直接并发赋值：

```vhdl
sig_Bs <= sig_RES OR sig_Cerr(15);
zz_t   <= NOT sig_zzFiberT;
```

= Verilog `assign sig_Bs = sig_RES | sig_Cerr[15];`

---

## 5. 运算符对照

| 运算 | Verilog | VHDL（本工程） |
|------|---------|----------------|
| 与或非 | `& \| ~` | `AND` `OR` `NOT` |
| 异或 | `^` | `XOR` |
| 相等 | `==` | `=` |
| 不等 | `!=` | `/=` |
| 拼接 | `{a,b}` | `a & b`（注意：`&` 在 VHDL 是拼接不是与） |
| 算术 | `+ - * /` | 同样；INTEGER 上直接算 |
| 移位 | `<<` | 本工程几乎不用，改用拼接/除法 |

**最关键：`&` 在 VHDL 是拼接。**

```vhdl
sig_zzdtout(15 DOWNTO 0) <= "0001" & sig_I1O(15 DOWNTO 4);
-- Verilog: {4'b0001, sig_I1O[15:4]}
```

逻辑与必须写 `AND`：

```vhdl
F_LED3 <= (NOT (led3_clk XOR sig_ledres)) AND (NOT sig_Bs);
```

---

## 6. 数字转换（本工程满地都是）

因为混用了 `STD_LOGIC_arith`：

| 函数 | 作用 | Verilog 近似 |
|------|------|--------------|
| `CONV_INTEGER(vec)` | 向量 → 整数 | `$signed(vec)` 再运算 |
| `CONV_STD_LOGIC_VECTOR(int, width)` | 整数 → 向量 | `int[width-1:0]` |

例子（温度标定）：

```vhdl
sig_T1s <= CONV_STD_LOGIC_VECTOR((CONV_INTEGER(sig_T1O)*225-18118)/16384, 12);
```

`/16384` 是除以 2^14，相当于算术右移 14 位，用来实现定标系数。

---

## 7. 例化：GENERIC MAP + PORT MAP

Verilog：

```verilog
TX_Comm #(
    .DELAY (20),
    .DtinN (54),
    .DtOUT (51)
) ZZ_COMM (
    .RESET   (sig_RES),
    .CLK     (CLKIN),
    .FiberT  (sig_zzFiberT)
);
```

VHDL：

```vhdl
ZZ_COMM: TX_Comm
GENERIC MAP(
    DELAY => zz_DELAY,
    DtinN => zz_dtIN,
    DtOUT => zz_dtOUT)
PORT MAP(
    RESET    => sig_RES,
    CLK      => CLKIN,
    TXclk    => sig_clk20KHz,
    FiberR   => zz_r,
    TXdtIn   => sig_zzdtin,
    TXdtOut  => sig_zzdtout,
    FiberT   => sig_zzFiberT,
    TXSinFt  => sig_zzsinFt,
    TXFinish => sig_zzFinish);
```

必须先在 Architecture 的 IS 区写 `COMPONENT TX_Comm ...`（或用直接例化，本工程用 COMPONENT）。

---

## 8. CASE / IF 与锁存

VHDL 的 `CASE` 必须覆盖，否则用 `WHEN OTHERS =>`：

```vhdl
CASE var_DecdC0(9 DOWNTO 5) IS
    WHEN "01001" => sig_CLR <= '1'; sig_HPwm <= '0';
    WHEN "10100" => sig_CLR <= '0'; sig_HPwm <= '0';
    WHEN "11010" => sig_CLR <= '0'; sig_HPwm <= '1';
    WHEN OTHERS  => NULL;     -- 保持原值（推断寄存器）
END CASE;
```

`NULL` = 什么都不做。在时钟进程里这会保持触发器原值，等价于 Verilog 不赋值。

`IF` 必须 `THEN` / `END IF`，嵌套全部显式结束，没有 `{ }`。

---

## 9. 边沿检测套路（和 Verilog 一模一样）

```vhdl
sig_zzclk_r <= sig_zzclk;
IF ((sig_zzclk = '1') AND (sig_zzclk_r = '0')) THEN
    sig_zzclk_edge <= '1';
ELSE
    sig_zzclk_edge <= '0';
END IF;
```

= Verilog：

```verilog
sig_zzclk_r <= sig_zzclk;
sig_zzclk_edge <= (sig_zzclk & ~sig_zzclk_r);
```

通信完成、PWM 边沿点灯都用这套。

---

## 10. 状态机两种形态（本工程都有）

**整数 Step + CASE**（均流、Boost 软启、AMC 滤波）：

```vhdl
VARIABLE Step : INTEGER RANGE 0 TO 7 := 0;
CASE Step IS
    WHEN 0 => IF cond THEN Step := 1; END IF;
    WHEN 1 => ...
    WHEN OTHERS => NULL;
END CASE;
```

**outstep/instep 0～22**（`TX_Comm` 比特协议）：本质是位时间状态机，每个状态等 `DELAY` 拍再跳。

对照 Rock 里常见的 `localparam S_IDLE=0; S_RUN=1;` + `case(state)`。

---

## 11. 并发语句 vs 进程冲突

同一 SIGNAL **不能**被两个 PROCESS 驱动（会变成多驱动）。  
本工程分区较清楚：每个 `sig_Cerr(i)` 基本只在一个进程写。

例外要注意：`sig_Cerr(15)` 是并发组合：

```vhdl
sig_Cerr(15) <= (sig_Dzgz AND sig_OpenF) OR ... ;
```

其它位在各 PROCESS 里赋值。这合法，因为是 **同一 VECTOR 的不同 bit** 分别驱动。

---

## 12. 读 YBT 时的翻译口诀

1. 看到 `PROCESS(clk)` → 当成 `always @(posedge clk)`。
2. 看到 `VARIABLE` 计数 → 当成阻塞赋值的中间量。
3. 看到 `<=` 在进程里 → 非阻塞，本拍读旧值。
4. 看到 `AND/OR/NOT/XOR` → 位运算；看到 `&` → **拼接**。
5. 看到 `CONV_*` → 在做定点标定或限幅。
6. 看到 `GENERIC MAP` → 参数化例化。
7. 顶层 `BEGIN` 里直接 `A<=B` → `assign`。

下一篇把这些语法放到系统功能上：`05_YBT系统功能与架构.md`。
