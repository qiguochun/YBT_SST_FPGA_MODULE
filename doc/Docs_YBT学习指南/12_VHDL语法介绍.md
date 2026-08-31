# VHDL 语法介绍（面向 Verilog 工程师）

> 独立语法手册：不依赖具体业务，但示例风格与 YBT 工程一致（`STD_LOGIC`、进程、INTEGER、老式 `CONV_*`）。  
> 读完本篇再看 `04_VHDL对照Verilog速成.md`，对照会更快。

---

## 目录

1. [语言特点与文件结构](#1-语言特点与文件结构)
2. [库与 USE](#2-库与-use)
3. [实体 ENTITY 与端口](#3-实体-entity-与端口)
4. [结构体 ARCHITECTURE](#4-结构体-architecture)
5. [数据类型](#5-数据类型)
6. [对象：SIGNAL / VARIABLE / CONSTANT](#6-对象signal--variable--constant)
7. [字面量与向量写法](#7-字面量与向量写法)
8. [运算符](#8-运算符)
9. [并发语句](#9-并发语句)
10. [顺序语句与 PROCESS](#10-顺序语句与-process)
11. [时钟、复位与边沿](#11-时钟复位与边沿)
12. [条件与分支](#12-条件与分支)
13. [循环](#13-循环)
14. [例化：COMPONENT / GENERIC / PORT MAP](#14-例化component--generic--port-map)
15. [常用类型转换](#15-常用类型转换)
16. [可综合子集与常见写法](#16-可综合子集与常见写法)
17. [注释、命名与风格](#17-注释命名与风格)
18. [易错清单](#18-易错清单)
19. [最小可综合模板](#19-最小可综合模板)

---

## 1. 语言特点与文件结构

VHDL（VHSIC Hardware Description Language）是 **强类型、偏冗长** 的硬件描述语言。和 Verilog 比：

| 特点 | 含义 |
|------|------|
| 强类型 | `'1'` 和 `"1"` 不是一类；INTEGER 和 VECTOR 不能直接混算，常要转换 |
| 接口与实现分离 | `ENTITY` 声明端口，`ARCHITECTURE` 写逻辑 |
| 并发 + 顺序 | Architecture 下语句默认并发；`PROCESS` 内才是顺序执行 |
| 大小写不敏感 | `Clk` 与 `clk` 是同一标识符（字符串字面量除外） |
| 赋值符号两种 | 信号 `<=`，变量/初值/GENERIC 默认值等用 `:=` |

一个典型 `.vhd` 文件顺序：

```text
LIBRARY / USE          -- 引入标准库
ENTITY ... PORT ...    -- 模块接口
ARCHITECTURE ... IS
    声明区             -- CONSTANT / SIGNAL / COMPONENT / 类型
BEGIN
    并发语句区         -- 赋值、例化、PROCESS、GENERATE
END;
```

扩展名常见 `.vhd` / `.vhdl`。Quartus / ModelSim 都认。

---

## 2. 库与 USE

```vhdl
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;      -- STD_LOGIC, STD_LOGIC_VECTOR, rising_edge
USE IEEE.NUMERIC_STD.ALL;         -- signed/unsigned、现代推荐算术库
```

YBT 工程额外用了 **老库**（能跑，但和新库混用要小心）：

```vhdl
USE IEEE.STD_LOGIC_arith.ALL;     -- CONV_INTEGER, CONV_STD_LOGIC_VECTOR
USE IEEE.STD_LOGIC_signed.ALL;    -- 把 VECTOR 当有符号
```

| 库 | 作用 |
|----|------|
| `STD_LOGIC_1164` | 九值逻辑 `U X 0 1 Z W L H -`，FPGA 设计几乎必用 |
| `NUMERIC_STD` | `unsigned`/`signed` 加减乘比较，**新代码推荐** |
| `STD_LOGIC_arith` | 非 IEEE 正式标准，但老工程极常见 |
| `STD_LOGIC_unsigned/signed` | 让 `STD_LOGIC_VECTOR` 直接加减 |

读 YBT：看到 `CONV_INTEGER` 就是 `arith` 库；自己新写模块尽量只用 `1164 + NUMERIC_STD`。

---

## 3. 实体 ENTITY 与端口

```vhdl
ENTITY 模块名 IS
    GENERIC (                 -- 可选：参数，≈ Verilog parameter
        WIDTH : INTEGER := 8
    );
    PORT (
        clk   : IN  STD_LOGIC;
        rst   : IN  STD_LOGIC;
        din   : IN  STD_LOGIC_VECTOR(WIDTH-1 DOWNTO 0);
        dout  : OUT STD_LOGIC_VECTOR(WIDTH-1 DOWNTO 0);
        ready : OUT STD_LOGIC
    );
END 模块名;
-- 也可写 END ENTITY 模块名;
```

### 端口方向

| 方向 | 含义 | 注意 |
|------|------|------|
| `IN` | 输入 | 实体内只能读 |
| `OUT` | 输出 | 标准 VHDL 里 **OUT 端口在实体内部不能再读** |
| `INOUT` | 双向 | 三态总线 |
| `BUFFER` | 可回读的输出 | 老写法；现多用内部 SIGNAL 再赋给 OUT |

YBT 习惯：需要又驱动又反馈时，先用内部 `SIGNAL xxx_reg`，最后 `端口 <= xxx_reg`（见 `TX_Comm` 的 `FiberT_reg`）。

### 端口列表语法

- 同一方向可合并：`F_FLT1, F_FLT2 : IN STD_LOGIC;`
- 最后一项 **没有分号** 在某些风格里仍写分号；以工具为准，YBT 末项后无逗号、有注释即可
- 向量范围多用 `N DOWNTO 0`（高位在左），与 Verilog `[N:0]` 同习惯

---

## 4. 结构体 ARCHITECTURE

```vhdl
ARCHITECTURE BEHAV OF 模块名 IS
    -- ========== 声明区 ==========
    CONSTANT MAX : INTEGER := 100;
    SIGNAL   cnt : INTEGER RANGE 0 TO MAX := 0;
    SIGNAL   q   : STD_LOGIC := '0';
BEGIN
    -- ========== 语句区（全部并发）==========
    q <= '1' WHEN cnt > 50 ELSE '0';

    PROCESS(clk)
    BEGIN
        IF rising_edge(clk) THEN
            cnt <= cnt + 1;
        END IF;
    END PROCESS;
END BEHAV;
```

要点：

- `OF 模块名` 必须对应某个 ENTITY
- 名字 `BEHAV` / `RTL` / `SYN` 可自定，本工程常用 `BEHAV`
- **声明区不能写可执行语句**；**BEGIN 后不能再声明 SIGNAL**（VARIABLE 只能在 PROCESS 里）

---

## 5. 数据类型

### 5.1 逻辑类（最常用）

```vhdl
STD_LOGIC                      -- 1 位
STD_LOGIC_VECTOR(7 DOWNTO 0)   -- 8 位总线
```

`STD_LOGIC` 取值不只 0/1，仿真里还有 `U`(未初始化)、`X`(冲突)、`Z`(高阻) 等。综合时主要关心 `0/1/Z`。

### 5.2 整数类

```vhdl
INTEGER                        -- 工具相关，常按 32 bit 理解
INTEGER RANGE 0 TO 255         -- 综合成 8 bit 量级，利于推断位宽
NATURAL                        -- INTEGER 子集，≥0
POSITIVE                       -- ≥1
```

YBT 里计数器、状态 `Step`、三角波 `cnt` 大量用 `INTEGER RANGE ...`。

### 5.3 布尔与其它

```vhdl
BOOLEAN     -- TRUE / FALSE，条件里可用，端口上少用
BIT         -- 仅 '0'/'1'，FPGA 工程几乎不用，改用 STD_LOGIC
```

### 5.4 有符号/无符号（NUMERIC_STD）

```vhdl
SIGNAL a : UNSIGNED(7 DOWNTO 0);
SIGNAL b : SIGNED(7 DOWNTO 0);
```

YBT 顶层较少直接用，多用 `STD_LOGIC_VECTOR` + `CONV_INTEGER` 转成 INTEGER 再算。

### 5.5 自定义类型（了解即可）

```vhdl
TYPE state_t IS (IDLE, RUN, DONE);
SIGNAL state : state_t := IDLE;

TYPE mem_t IS ARRAY (0 TO 15) OF STD_LOGIC_VECTOR(7 DOWNTO 0);
```

本工程状态机多用 `INTEGER` + `CASE`，而不是枚举类型。

---

## 6. 对象：SIGNAL / VARIABLE / CONSTANT

### 6.1 CONSTANT（常量）

```vhdl
CONSTANT NumHSQ : INTEGER := 192;
CONSTANT IDLE_CMD : STD_LOGIC_VECTOR(4 DOWNTO 0) := "10100";
```

综合期绑定，运行中不可改。≈ `localparam`。

### 6.2 SIGNAL（信号）

- 表示硬件连线或寄存器
- 跨进程、连端口都用它
- 在 PROCESS 里用 `<=` 赋值：**本进程内后面读到的仍是旧值**（类似 Verilog 非阻塞）

```vhdl
SIGNAL a, b : STD_LOGIC := '0';

PROCESS(clk)
BEGIN
    IF rising_edge(clk) THEN
        a <= b;
        b <= a;   -- 交换：因为用的都是进入进程时的旧值
    END IF;
END PROCESS;
```

### 6.3 VARIABLE（变量）

- 只能活在某个 PROCESS（或子程序）里
- `:=` **立即更新**
- 综合成组合逻辑中间量，或与 SIGNAL 配合推断寄存器

```vhdl
PROCESS(clk)
    VARIABLE cnt : INTEGER RANGE 0 TO 65535 := 0;
BEGIN
    IF rising_edge(clk) THEN
        cnt := cnt + 1;          -- 立刻 +1
        IF cnt >= 49999 THEN
            sig_RES <= '0';
        ELSE
            sig_RES <= '1';
        END IF;
    END IF;
END PROCESS;
```

### 6.4 对照表

| | CONSTANT | SIGNAL | VARIABLE |
|--|----------|--------|----------|
| 赋值 | `:=`（声明时） | `<=` | `:=` |
| 更新时机 | 编译期 | 进程挂起后 | 立刻 |
| 作用域 | 声明所在区 | Architecture | 仅该 PROCESS |
| 典型用途 | 参数、阈值 | 端口、跨进程、寄存器 | 计数器中间量、状态步 |

**黄金规则：** 要出进程或出模块 → SIGNAL；只在一个时钟进程里算着玩 → VARIABLE 很方便。

---

## 7. 字面量与向量写法

```vhdl
'0', '1'                 -- 单 bit（字符字面量）
"10110"                  -- 位串，长度=位数
B"1011_0000"             -- 二进制（可写下划线分隔）
X"A5"                    -- 十六进制 → 8 bit
O"17"                    -- 八进制
16#FF#                   -- 基于数制的 INTEGER 字面量

(OTHERS => '0')          -- 向量全 0
(OTHERS => '1')          -- 向量全 1
(0 => '1', OTHERS => '0')-- 仅 bit0 为 1
```

切片与拼接：

```vhdl
bus(7 DOWNTO 4)          -- 高半字节
bus(3 DOWNTO 0)
"0001" & data(11 DOWNTO 0)   -- 拼接，结果 16 bit
```

长度必须匹配：不能把 5 bit 的 `"10110"` 赋给 8 bit 向量（除非改写或补位）。

---

## 8. 运算符

### 8.1 逻辑（bit / vector）

| 运算 | VHDL | 注意 |
|------|------|------|
| 与 | `AND` | |
| 或 | `OR` | |
| 异或 | `XOR` | |
| 同或 | `XNOR` | |
| 非 | `NOT` | |
| 与非/或非 | `NAND` `NOR` | |

```vhdl
y <= (a AND b) OR (NOT c);
```

### 8.2 关系

```vhdl
=    /=     -- 等于 / 不等于
<  <=  >  >=
```

条件里写 `IF a = '1' THEN`，**没有** `==`。

### 8.3 算术

```vhdl
+  -  *  /  MOD  REM  ABS  **
```

在 `INTEGER` 上直接算最省事（YBT 风格）。在 `UNSIGNED`/`SIGNED` 上算需 `NUMERIC_STD`。

### 8.4 拼接与集合

```vhdl
a & b & c        -- 拼接（最易与 Verilog & 混淆！）
```

### 8.5 优先级（实用记忆）

1. `**` `ABS` `NOT`  
2. `* / MOD REM`  
3. `+ - &`  
4. 关系运算符  
5. `AND OR NAND NOR XOR XNOR`（逻辑运算符彼此同级，建议全程加括号）

---

## 9. 并发语句

写在 Architecture 的 `BEGIN` 下、PROCESS 外，**彼此并行**，谁先写谁后写不影响硬件语义。

### 9.1 简单并发赋值

```vhdl
zz_t <= NOT sig_zzFiberT;
sig_Bs <= sig_RES OR sig_Cerr(15);
```

≈ `assign`。

### 9.2 条件赋值（并发 IF）

```vhdl
y <= a WHEN sel = '1' ELSE b;
```

### 9.3 选择赋值（并发 CASE）

```vhdl
WITH opcode SELECT
    y <= a WHEN "00",
         b WHEN "01",
         c WHEN "10",
         d WHEN OTHERS;
```

### 9.4 例化、PROCESS、GENERATE

也都是并发“构件”：多个 PROCESS 同时存在，靠 SIGNAL 通信。

```vhdl
GEN_REG: FOR i IN 0 TO 3 GENERATE
    d(i) <= s(i) AND en;
END GENERATE;
```

YBT 顶层几乎不用 `GENERATE`，了解即可。

---

## 10. 顺序语句与 PROCESS

PROCESS 内部语句 **按书写顺序执行**（在一个仿真周期的该进程激活期间），用于描述时序逻辑或复杂组合逻辑。

```vhdl
进程名: PROCESS(敏感表)
    VARIABLE ...;          -- 可选
BEGIN
    -- IF / CASE / LOOP / 赋值
END PROCESS 进程名;
```

### 敏感表

| 写法 | 用途 |
|------|------|
| `PROCESS(clk)` | 同步时序，复位也同步 |
| `PROCESS(clk, rst)` | 异步复位 |
| `PROCESS(a, b, c)` | 组合逻辑，必须列全输入，否则仿真漏触发 |
| `PROCESS(ALL)` | VHDL-2008，自动全敏感；工具要支持 |

组合 PROCESS 漏敏感表是经典坑；时序 PROCESS 只列时钟（和异步复位）即可。

### 进程如何被唤醒

任一敏感信号变化 → 进程从 BEGIN 跑到 END → SIGNAL 的 `<=` 在进程结束时才更新 → 可能再次触发别的进程。

---

## 11. 时钟、复位与边沿

### 11.1 上升沿

```vhdl
IF rising_edge(clk) THEN
    ...
END IF;

-- 等价老写法
IF clk'EVENT AND clk = '1' THEN
```

下降沿：`falling_edge(clk)` 或 `clk'EVENT AND clk = '0'`。

### 11.2 同步复位

```vhdl
PROCESS(clk)
BEGIN
    IF rising_edge(clk) THEN
        IF rst = '1' THEN
            q <= '0';
        ELSE
            q <= d;
        END IF;
    END IF;
END PROCESS;
```

### 11.3 异步复位

```vhdl
PROCESS(clk, rst)
BEGIN
    IF rst = '1' THEN
        q <= '0';
    ELSIF rising_edge(clk) THEN
        q <= d;
    END IF;
END PROCESS;
```

YBT：内部 `sig_RES` 多为同步产生；不少进程写成 `IF sig_RES='1' THEN ... ELSIF rising_edge(...)`，把复位当异步高有效用。

### 11.4 边沿检测（单拍脉冲）

```vhdl
sig_r <= sig;
IF sig = '1' AND sig_r = '0' THEN
    pulse <= '1';
ELSE
    pulse <= '0';
END IF;
```

通信完成、PWM 边沿点灯都用这套。

---

## 12. 条件与分支

### 12.1 IF

```vhdl
IF cond1 THEN
    ...
ELSIF cond2 THEN
    ...
ELSE
    ...
END IF;
```

必须 `THEN`，必须 `END IF`。条件是 BOOLEAN；`a = '1'` 这种关系式结果就是 BOOLEAN。

### 12.2 CASE

```vhdl
CASE sel IS
    WHEN "00" => y <= a;
    WHEN "01" => y <= b;
    WHEN "10" | "11" => y <= c;   -- 多值
    WHEN OTHERS => y <= d;        -- 必须覆盖或写 OTHERS
END CASE;
```

- `WHEN OTHERS` 强烈建议写上  
- 分支里 `NULL;` 表示什么都不做（保持寄存器原值）

### 12.3 锁存推断（要避免的组合坑）

组合 PROCESS 里如果某条路径没给信号赋值，会推断 **Latch**。时序电路里通常不希望。

```vhdl
-- 坏例：en=0 时 y 没赋值 → latch
PROCESS(en, a)
BEGIN
    IF en = '1' THEN
        y <= a;
    END IF;
END PROCESS;

-- 好例：先默认再覆盖
PROCESS(en, a)
BEGIN
    y <= '0';
    IF en = '1' THEN
        y <= a;
    END IF;
END PROCESS;
```

时钟进程里故意不赋值 = 保持触发器，这是正常的。

---

## 13. 循环

可综合常用 `FOR`；`WHILE` 多用于测试台。

```vhdl
FOR i IN 0 TO 7 LOOP
    sum := sum + CONV_INTEGER(vec(i DOWNTO i));
END LOOP;
```

注意：

- 综合要求循环边界在编译期可确定  
- 不要在时钟进程里写巨大无界循环  
- `EXIT` / `NEXT` 可跳出/进入下一轮（慎用）

测试台延时（不可综合）：

```vhdl
WAIT FOR 10 ns;
WAIT UNTIL rising_edge(clk);
```

---

## 14. 例化：COMPONENT / GENERIC / PORT MAP

### 14.1 先声明 COMPONENT（YBT 风格）

```vhdl
ARCHITECTURE BEHAV OF SSTMC_FPGA IS
    COMPONENT TX_Comm
        GENERIC ( DELAY : INTEGER := 20; DtinN : INTEGER := 41; DtOUT : INTEGER := 51 );
        PORT (
            RESET : IN  STD_LOGIC;
            CLK   : IN  STD_LOGIC;
            ...
            TXFinish : OUT STD_LOGIC
        );
    END COMPONENT;
BEGIN
    U1: TX_Comm
        GENERIC MAP ( DELAY => 20, DtinN => 54, DtOUT => 51 )
        PORT MAP (
            RESET => sig_RES,
            CLK   => CLKIN,
            ...
            TXFinish => sig_zzFinish
        );
END BEHAV;
```

### 14.2 位置关联 vs 名字关联

```vhdl
PORT MAP (sig_RES, CLKIN, ...);           -- 按端口声明顺序，易错
PORT MAP (RESET => sig_RES, CLK => CLKIN); -- 按名字，推荐
```

### 14.3 开路与默认

```vhdl
PORT MAP (
    clk => clk,
    open_port => OPEN,          -- 输出不接
    din => (OTHERS => '0')
);
```

### 14.4 直接例化（VHDL-93 起，可不写 COMPONENT）

```vhdl
U1: ENTITY work.TX_Comm
    GENERIC MAP (...)
    PORT MAP (...);
```

YBT 用的是 COMPONENT 方式。

---

## 15. 常用类型转换

### 15.1 YBT / 老库风格

```vhdl
CONV_INTEGER(vector)                    -- VECTOR → INTEGER
CONV_STD_LOGIC_VECTOR(int_value, width) -- INTEGER → VECTOR
```

例：

```vhdl
sig_T1s <= CONV_STD_LOGIC_VECTOR(
    (CONV_INTEGER(sig_T1O) * 225 - 18118) / 16384,
    12
);
```

### 15.2 现代 NUMERIC_STD 风格（新代码建议）

```vhdl
USE IEEE.NUMERIC_STD.ALL;

to_integer(unsigned(v));
to_integer(signed(v));
std_logic_vector(to_unsigned(i, 8));
std_logic_vector(to_signed(i, 8));
unsigned(v);
signed(v);
```

### 15.3 不要做的事

- 把不同长度向量直接 `<=`  
- 假设 `STD_LOGIC_VECTOR` 自动有符号（取决于你 USE 了哪个库）  
- 在同一文件混用 `arith` 与 `NUMERIC_STD` 的 `+` 却不看警告

---

## 16. 可综合子集与常见写法

工具能综合成门电路的，大致是：

| 可综合 | 通常不可综合（仿真用） |
|--------|------------------------|
| ENTITY/ARCHITECTURE | `WAIT FOR` 时间延迟 |
| PROCESS + 时钟边沿 | 文件读写 |
| IF/CASE/FOR（定界） | 未约束的 `WHILE TRUE` |
| 例化、GENERATE | 实时打印为主的复杂行为 |
| `<=` `:=` 赋值 |  |

### 寄存器模板

```vhdl
PROCESS(clk)
BEGIN
    IF rising_edge(clk) THEN
        q <= d;
    END IF;
END PROCESS;
```

### 计数器模板

```vhdl
PROCESS(clk, rst)
BEGIN
    IF rst = '1' THEN
        cnt <= 0;
    ELSIF rising_edge(clk) THEN
        IF cnt = MAX THEN
            cnt <= 0;
        ELSE
            cnt <= cnt + 1;
        END IF;
    END IF;
END PROCESS;
```

### 整数状态机模板

```vhdl
PROCESS(clk, rst)
    VARIABLE step : INTEGER RANGE 0 TO 5 := 0;
BEGIN
    IF rst = '1' THEN
        step := 0;
    ELSIF rising_edge(clk) THEN
        CASE step IS
            WHEN 0 => IF start = '1' THEN step := 1; END IF;
            WHEN 1 => step := 2;
            WHEN 2 => step := 0;
            WHEN OTHERS => step := 0;
        END CASE;
    END IF;
END PROCESS;
```

---

## 17. 注释、命名与风格

```vhdl
-- 单行注释（VHDL 没有 /* */ 块注释，直到 VHDL-2008 部分工具支持）
```

YBT 可见风格：

- 信号前缀 `sig_`
- 端口大写或匈牙利式：`FHS1_DRV`、`CLKIN`
- 进程加标签：`P_reset:`、`ZZ_COMM:`、`TrFAN:`
- 分区用整行 `-- ===` 或中文注释标题

标识符：字母开头，可含字母数字下划线；不要连续下划线；不要以下划线结尾（部分规则）。

---

## 18. 易错清单

1. **`&` 当按位与** → 实际是拼接；与要用 `AND`  
2. **`==` `!=`** → 要用 `=` `/=`  
3. **`'1'` 赋给 VECTOR** → 类型不符；用 `"1"` 或补齐位宽  
4. **OUT 端口在内部再读** → 综合/分析报错；用中间 SIGNAL  
5. **同一 SIGNAL 两个 PROCESS 驱动** → 多驱动 / 线与冲突  
6. **组合 PROCESS 漏赋值** → 意外 Latch  
7. **敏感表漏输入** → 仿真与综合行为不一致  
8. **SIGNAL 当立刻更新用** → 同进程后读仍是旧值；要立刻更新用 VARIABLE  
9. **忘记 `END IF` / `END CASE` / `END PROCESS`** → 语法错，嵌套时尤甚  
10. **位宽变化后没改 `CONV_STD_LOGIC_VECTOR(..., width)`** → 截断或仿真报错  

---

## 19. 最小可综合模板

把下面存成 `blink.vhd` 即可在 Quartus 里练手：

```vhdl
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY blink IS
    PORT (
        clk : IN  STD_LOGIC;
        rst : IN  STD_LOGIC;
        led : OUT STD_LOGIC
    );
END blink;

ARCHITECTURE BEHAV OF blink IS
    SIGNAL cnt : INTEGER RANGE 0 TO 24999999 := 0;
    SIGNAL led_r : STD_LOGIC := '0';
BEGIN
    led <= led_r;

    PROCESS(clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF rst = '1' THEN
                cnt   <= 0;
                led_r <= '0';
            ELSIF cnt = 24999999 THEN
                cnt   <= 0;
                led_r <= NOT led_r;
            ELSE
                cnt <= cnt + 1;
            END IF;
        END IF;
    END PROCESS;
END BEHAV;
```

对照 Verilog 心智：`ENTITY/PORT` = 模块端口；`SIGNAL led_r` = `reg`；`PROCESS+rising_edge` = `always @(posedge)`；`led <= led_r` = `assign led = led_r`。

---

## 和本系列其它文档的关系

| 文档 | 侧重点 |
|------|--------|
| **本文件** | VHDL 语法本身，可当手册查 |
| `04_VHDL对照Verilog速成.md` | 每条语法对应 YBT 真实代码 |
| `06`～`09` | 不再讲语法，讲业务 |

建议：本文件扫一遍 → 精读 `04` → 打开 `SSTMC_FPGA.vhd` 对照进程读。
