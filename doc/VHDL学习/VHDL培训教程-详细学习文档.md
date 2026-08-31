# VHDL 培训教程 — 超详细学习文档

> **文档来源**：根据《VHDL培训教程》PPT 整理扩展  
> **编写单位**：浙江大学电子信息技术研究所 · 电子设计自动化(EDA)培训中心  
> **原始作者**：王勇  
> **适用对象**：数字电路设计初学者、FPGA/ASIC 入门工程师、EDA 课程学员  

---

## 目录

1. [课程总览与学习路线](#1-课程总览与学习路线)
2. [第一讲：VHDL 简介及其结构](#2-第一讲vhdl-简介及其结构)
3. [第二讲：对象、操作符与数据类型](#3-第二讲对象操作符与数据类型)
4. [第三讲：控制语句及模块](#4-第三讲控制语句及模块)
5. [第四讲：状态机的设计](#5-第四讲状态机的设计)
6. [VHDL 上机指导](#6-vhdl-上机指导)
7. [综合练习与常见错误](#7-综合练习与常见错误)
8. [附录：速查表](#8-附录速查表)

---

## 1. 课程总览与学习路线

### 1.1 欢迎与课程目标

本教程系统介绍 **VHDL（VHSIC Hardware Description Language，超高速集成电路硬件描述语言）**，帮助读者从零开始掌握用形式化语言描述、仿真和综合数字硬件系统的能力。

**通过本课学习，您将了解：**

1. VHDL 的基本概念
2. VHDL 的基本结构
3. VHDL 的设计初步
4. 对象、操作符与数据类型
5. 控制语句与模块化设计
6. 状态机设计方法

### 1.2 四讲内容结构

| 讲次 | 主题 | 核心内容 |
|------|------|----------|
| 第一讲 | VHDL 简介及其结构 | Entity、Architecture、Library、Package |
| 第二讲 | 对象、操作符、数据类型 | Constant/Variable/Signal、类型定义、运算符 |
| 第三讲 | 控制语句及模块 | Process、Block、If/Case/Loop、并行赋值 |
| 第四讲 | 状态机的设计 | Moore/Mealy、同步状态机、状态图 |

### 1.3 推荐学习顺序

```
概念理解 → 语法结构 → 简单组合逻辑 → 时序逻辑 → 模块化 → 状态机 → 上机仿真
```

**建议实践路径：**

- 第 1 周：半加器、全加器、与门、或门、异或门
- 第 2 周：多路选择器、译码器、计数器
- 第 3 周：状态机（序列检测、交通灯控制器）
- 第 4 周：Active-VHDL 完整仿真流程

---

## 2. 第一讲：VHDL 简介及其结构

### 2.1 什么是 VHDL？

**VHDL** 全称 **VHSIC Hardware Description Language**。

- **VHSIC** = **Very High Speed Integrated Circuit**（超高速集成电路）
- 起源于 **20 世纪 80 年代**，最初由 **美国国防部** 推动开发
- 是 **电子设计自动化（EDA）** 的关键技术之一，要求用 **形式化方法** 描述硬件系统

**核心思想**：用软件式的语言，描述硬件的结构和行为，再通过仿真验证、综合工具映射到 FPGA/ASIC。

#### 示例：用自然语言 vs 用 VHDL 描述一个与门

| 描述方式 | 内容 |
|----------|------|
| 自然语言 | "当输入 A 和 B 都为 1 时，输出 Y 为 1，否则为 0" |
| VHDL | `Y <= A and B;` |

---

### 2.2 VHDL 与 Verilog HDL 对比

PPT 中给出了两种主流 HDL 的对比，这是工程选型时的重要参考。

| 对比项 | VHDL | Verilog HDL |
|--------|------|-------------|
| 标准化 | 1987 年 IEEE 1076（VHDL87）；1993 年修订（VHDL93） | 1995 年成为 IEEE 标准 |
| 优点 | **功能强大、通用性强、类型严格** | **简单、易学易用** |
| 缺点 | **较难学习** | 功能不如 VHDL 强大，早期仿真工具较少 |
| 典型应用 | 航空航天、军工、欧洲/学术体系 | 北美商用 IC、ASIC 前端 |

#### 举例说明"强类型"差异

**VHDL（强类型，不允许隐式混用）：**

```vhdl
signal a : bit;
signal b : integer;
-- 错误：a <= b;  -- 类型不匹配，编译报错
```

**Verilog（弱类型，更灵活但也更易出错）：**

```verilog
reg a;
integer b;
// 某些情况下可隐式转换，但可能隐藏 bug
```

> **学习建议**：初学者先掌握 VHDL 的严格类型系统，再学 Verilog 会更容易理解硬件建模的本质。

---

### 2.3 VHDL 发展历史

| 年份/版本 | 说明 |
|-----------|------|
| 1980 年代 | 美国国防部项目启动，用于复杂系统集成 |
| **1987** | **IEEE 1076** 发布，称 **VHDL87** |
| **1993** | 标准修订，称 **VHDL93**（增加了更多语法特性） |

**版本差异举例（VHDL93 增强）：**

```vhdl
-- VHDL93 支持更灵活的文件操作和共享变量等特性
-- 现代综合工具普遍支持 VHDL-93 及 IEEE 1076.3 等扩展
```

---

### 2.4 VHDL 在电子系统设计中的应用

电子系统可以从不同 **抽象层次** 描述，VHDL 可以覆盖其中多个层次：

| 层次 | 英文 | 描述内容 | 举例 |
|------|------|----------|------|
| 1 | **行为级（Behavioral）** | 算法、功能意图 | `if reset='1' then count <= 0;` |
| 2 | **RTL 级（Register Transfer Level）** | 寄存器 + 组合逻辑数据通路 | 计数器、CPU 数据通路 |
| 3 | **逻辑门级（Gate Level）** | 与或非门网络 | `Y <= A and B;` |
| 4 | **版图级（Layout）** | 物理几何形状 | 一般由后端工具生成，较少手写 |

#### 同一功能的多层次描述示例：2 分频器

**行为级描述（强调功能）：**

```vhdl
process(clk)
begin
  if rising_edge(clk) then
    q <= not q;  -- 每个时钟沿翻转
  end if;
end process;
```

**RTL 级描述（强调寄存器传输）：**

```vhdl
process(clk)
begin
  if rising_edge(clk) then
    q <= d;      -- d 是 q 的反相，形成反馈
  end if;
end process;
```

**门级描述（强调逻辑门）：**

```vhdl
-- 使用基本门实例化（实际工程中较少这样写）
inv_inst : inverter port map(q, d);
dff_inst : dff port map(clk, d, q);
```

> **工程实践**：现代 FPGA 设计 **90% 以上在 RTL 级** 完成，综合工具自动映射到门级和版图。

---

### 2.5 如何使用 VHDL 描述硬件实体

VHDL 描述硬件的核心结构是 **Entity（实体）+ Architecture（构造体）** 的组合：

```
        ┌─────────────────────────────────┐
        │           ENTITY                │
        │   定义"黑盒"对外的端口接口       │
        └───────────────┬─────────────────┘
                        │
        ┌───────────────▼─────────────────┐
        │        ARCHITECTURE             │
        │   描述"黑盒"内部的实现方式        │
        └─────────────────────────────────┘
```

---

### 2.6 ENTITY（实体）详解

#### 2.6.1 格式

```vhdl
entity 实体名 is
  [generic ( ... );]   -- 可选：类属参数
  port (
    端口名1 : 方向 类型;
    端口名N : 方向 类型
  );
end entity 实体名;
```

#### 2.6.2 端口方向说明

| 方向 | 含义 | 赋值规则（PPT 要点） |
|------|------|----------------------|
| **in** | 输入 | **不能**出现在 `<=` 或 `:=` 的 **左边** |
| **out** | 输出 | **不能**出现在 `<=` 或 `:=` 的 **右边** |
| **inout** | 双向 | 可读可写，用于总线 |
| **buffer** | 缓冲输出 | 可出现在 `<=` 或 `:=` 的 **两边**（可反馈） |
| **linkage** | 连接 | 较少使用 |

#### 2.6.3 端口声明示例

```vhdl
port (
  A, B : in  bit;
  Sum, Carry : out bit
);
```

等价于：

```vhdl
port (
  A    : in  bit;
  B    : in  bit;
  Sum  : out bit;
  Carry: out bit
);
```

---

### 2.7 例子一：半加器（HalfAdd）

半加器是最经典的入门例子：**两个 1 位输入，输出和与进位**。

| 输入 A | 输入 B | 和 Sum | 进位 Carry |
|--------|--------|--------|------------|
| 0 | 0 | 0 | 0 |
| 0 | 1 | 1 | 0 |
| 1 | 0 | 1 | 0 |
| 1 | 1 | 0 | 1 |

**逻辑表达式：**
- `Sum = A xor B`
- `Carry = A and B`

#### 完整 VHDL 代码（根据 PPT 例子重构）

**Entity 部分：**

```vhdl
library ieee;
use ieee.std_logic_1164.all;

entity HalfAdd is
  port (
    A, B   : in  std_logic;
    Sum    : out std_logic;
    Carry  : out std_logic
  );
end entity HalfAdd;
```

**Architecture 部分：**

```vhdl
architecture Behavioral of HalfAdd is
begin
  Sum   <= A xor B;
  Carry <= A and B;
end architecture Behavioral;
```

#### 逐行讲解

| 代码 | 说明 |
|------|------|
| `library ieee;` | 引用 IEEE 标准库 |
| `use ieee.std_logic_1164.all;` | 使用 std_logic 类型（比 bit 更常用） |
| `entity HalfAdd is` | 声明实体名 HalfAdd |
| `port (...)` | 定义对外接口 |
| `architecture Behavioral of HalfAdd is` | 构造体名 Behavioral，属于实体 HalfAdd |
| `Sum <= A xor B;` | 并行赋值：异或得到和 |
| `Carry <= A and B;` | 并行赋值：与运算得到进位 |

#### 仿真测试平台（Testbench）示例

```vhdl
entity tb_HalfAdd is
end tb_HalfAdd;

architecture sim of tb_HalfAdd is
  signal A, B, Sum, Carry : std_logic;
begin
  uut: entity work.HalfAdd
    port map (A => A, B => B, Sum => Sum, Carry => Carry);

  stim: process
  begin
    A <= '0'; B <= '0'; wait for 10 ns;
    A <= '0'; B <= '1'; wait for 10 ns;
    A <= '1'; B <= '0'; wait for 10 ns;
    A <= '1'; B <= '1'; wait for 10 ns;
    wait;
  end process;
end sim;
```

**预期波形：**

```
时间   A  B  Sum  Carry
0ns    0  0   0     0
10ns   0  1   1     0
20ns   1  0   1     0
30ns   1  1   0     1
```

---

### 2.8 例子二：全加器（FullAdd）— 学习模块调用

全加器在半加器基础上增加了 **进位输入 Cin**，是 PPT 中"学习如何调用现有模块"的重点例子。

| Cin | A | B | Sum | Cout |
|-----|---|---|-----|------|
| 0 | 0 | 0 | 0 | 0 |
| 0 | 0 | 1 | 1 | 0 |
| 0 | 1 | 0 | 1 | 0 |
| 0 | 1 | 1 | 0 | 1 |
| 1 | 0 | 0 | 1 | 0 |
| 1 | 0 | 1 | 0 | 1 |
| 1 | 1 | 0 | 0 | 1 |
| 1 | 1 | 1 | 1 | 1 |

#### 方法一：直接用逻辑方程

```vhdl
entity FullAdd is
  port (
    A, B, Cin : in  std_logic;
    Sum, Cout : out std_logic
  );
end entity FullAdd;

architecture Dataflow of FullAdd is
begin
  Sum  <= A xor B xor Cin;
  Cout <= (A and B) or (A and Cin) or (B and Cin);
end architecture Dataflow;
```

#### 方法二：调用两个半加器（层次化设计，PPT 重点）

**Step 1：声明半加器元件（Component）**

```vhdl
architecture Structural of FullAdd is
  component HalfAdd
    port (
      A, B  : in  std_logic;
      Sum   : out std_logic;
      Carry : out std_logic
    );
  end component;

  signal s1, c1, c2 : std_logic;
begin
  HA1: HalfAdd port map (A => A,  B => B,  Sum => s1, Carry => c1);
  HA2: HalfAdd port map (A => s1, B => Cin, Sum => Sum, Carry => c2);
  Cout <= c1 or c2;
end architecture Structural;
```

**结构示意图：**

```
    A ──┬──► [HalfAdd HA1] ──► s1 ──┬──► [HalfAdd HA2] ──► Sum
    B ──┘              │              │
                       c1             Cin
                        │              │
                        └─── OR ◄── c2 ─┘
                              │
                            Cout
```

> **设计思想**：大系统 = 小模块互连。这是 VHDL 层次化设计的核心。

---

### 2.9 ARCHITECTURE（构造体）详解

#### 2.9.1 格式

```vhdl
architecture 构造体名 of 实体名 is
  -- 定义语句：内部信号、常数、元件、数据类型、函数等
  signal internal_sig : bit;
  constant DELAY : time := 5 ns;
begin
  -- 并行处理语句：process、block、并发赋值、元件例化等
  internal_sig <= A and B;
end architecture 构造体名;
```

#### 2.9.2 构造体的作用

- Entity 只说明 **"是什么接口"**
- Architecture 说明 **"内部怎么实现"**
- **同一 Entity 可以有多个 Architecture**（如行为级、结构级各一份）

#### 举例：同一与门的两种构造体

**行为级（Behavioral）：**

```vhdl
architecture behav of and_gate is
begin
  Y <= A and B;
end behav;
```

**结构级（Structural）：**

```vhdl
architecture struct of and_gate is
  component nand_gate ...
  component inv ...
begin
  -- 用 NAND + INV 搭建 AND
end struct;
```

---

### 2.10 VHDL 中的设计单元（可独立编译）

PPT 指出，除 Entity 和 Architecture 外，还有三个可 **独立编译** 的设计单元：

| 设计单元 | 作用 | 类比 |
|----------|------|------|
| **Package（包）** | 存放信号定义、常数、数据类型、元件声明、函数/过程声明 | C 语言头文件 `.h` |
| **Package Body（包体）** | 实现 Package 中声明的函数和过程 | C 语言 `.c` 实现 |
| **Configuration（配置）** | 描述层与层之间的连接关系、Entity 与 Architecture 的绑定 | 编译链接配置 |

#### Package 示例

```vhdl
-- 包声明
package my_types is
  type state_type is (S0, S1, S2, S3);
  constant MAX_COUNT : integer := 15;
  function increment(x : integer) return integer;
end package my_types;

-- 包体
package body my_types is
  function increment(x : integer) return integer is
  begin
    return x + 1;
  end function;
end package body my_types;
```

**使用方式：**

```vhdl
library work;
use work.my_types.all;

signal current_state : state_type := S0;
```

---

### 2.11 Library（库）的概念

PPT 强调：VHDL 文件编译后，结果存放在特定目录，该目录的 **逻辑名称就是 Library**。

| 库名 | 说明 |
|------|------|
| **STD** | VHDL 标准库（如 `standard`、`textio`） |
| **IEEE** | IEEE 标准扩展库（如 `std_logic_1164`、`numeric_std`） |
| **面向 ASIC 的库** | 不同工艺厂商提供 |
| **公司自定义库** | 企业内部 IP 库 |
| **用户自己的库（work）** | 默认工作库，存放当前工程编译结果 |

#### 常用引用模板

```vhdl
library ieee;
use ieee.std_logic_1164.all;    -- std_logic, std_logic_vector
use ieee.numeric_std.all;      -- 有符号/无符号运算

library std;
use std.textio.all;              -- 文件读写、报告输出
```

#### 编译与库的关系示例

```
文件: HalfAdd.vhd  ──compile──►  work.HalfAdd(entity)
文件: FullAdd.vhd  ──compile──►  work.FullAdd(entity)
                                      │
                                      └── FullAdd 内部 reference work.HalfAdd
```

---

### 2.12 VHDL 结构关系总图

```
Library（库）
  ├── Package（包集合）
  │     └── Package Body（包体）
  ├── Entity（实体）
  │     └── Architecture（构造体）
  │           ├── Block（块）
  │           ├── Process（进程）
  │           └── Subprogram（子程序：Function / Procedure）
  └── Configuration（配置）
```

---

### 2.13 第一讲小结

| 要点 | 内容 |
|------|------|
| VHDL 是什么 | 硬件描述语言，支持多层次抽象 |
| 核心结构 | Entity + Architecture |
| 端口方向 | in / out / inout / buffer |
| 模块化 | Component + Port Map |
| 可复用 | Library + Package |

**下一讲预告**：VHDL 中的对象、操作符、数据类型

---

## 3. 第二讲：对象、操作符与数据类型

### 3.1 对象（Object）概述

**对象**是对客观实体的抽象和概括。VHDL 中有三类对象：

| 对象类型 | 赋值符号 | 能否被重新赋值 | 更新时机 | 典型用途 |
|----------|----------|----------------|----------|----------|
| **Constant（常量）** | `:=`（初始化） | ❌ 不可 | 编译时固定 | 延时、位宽、状态编码 |
| **Variable（变量）** | `:=` | ✅ 可以 | **立即更新** | Process 内部临时计算 |
| **Signal（信号）** | `<=` | ✅ 可以 | **进程挂起后更新** | 硬件连线、寄存器 |

#### 三者的本质区别（极其重要！）

```vhdl
process
  variable v : integer := 0;
  signal   s : integer := 0;  -- 注意：signal 不能写在 process 内！此处仅为对比说明
begin
  v := v + 1;   -- v 立刻变成 1
  s <= s + 1;   -- s 在本 delta cycle 内仍为旧值，进程结束才更新
end process;
```

**PPT 经典问题：Z 和 Y 最终取什么值？**

```vhdl
process
  variable M, N : integer := 0;
begin
  M := 1;
  N := M;       -- N 立即 = 1
  -- 若用 signal：M <= 1; N <= M; 则 N 取的是 M 的旧值 0！
end process;
```

**答案（variable）**：M=1, N=1  
**答案（若用 signal）**：M=1, N=0（因为 signal 赋值不立即生效）

---

### 3.2 对象定义示例

#### 3.2.1 Variable 示例

```vhdl
process
  variable x, y : integer;
begin
  x := 10;
  y := x + 5;    -- y 立即 = 15
end process;
```

#### 3.2.2 Constant 示例

```vhdl
constant Vcc   : real := 5.0;
constant WIDTH : integer := 8;
constant RESET : std_logic := '1';
```

#### 3.2.3 Signal 示例

```vhdl
signal clk, reset : bit;
signal data_bus   : std_logic_vector(7 downto 0);
```

---

### 3.3 对象的使用规则（PPT 强调）

| 规则 | 说明 |
|------|------|
| **Variable** | 只能定义在 **Process** 和 **Subprogram**（Function/Procedure）**内部** |
| **Signal** | 只能定义在 **Process/Subprogram 外部**（Architecture、Block 等） |

#### 正确 vs 错误示例

```vhdl
architecture rtl of example is
  signal count : integer := 0;   -- ✅ 正确：在 architecture 中
begin
  process(clk)
    variable temp : integer;     -- ✅ 正确：在 process 中
  begin
    ...
  end process;
end rtl;

-- ❌ 错误：signal 不能写在 process 内部
-- ❌ 错误：variable 不能写在 architecture 直接子级
```

---

### 3.4 对象的属性（Attribute）

类似于面向对象语言（VB、C++）中的属性访问：`对象'属性`

#### 3.4.1 Signal 常用属性

| 属性 | 返回类型 | 含义 |
|------|----------|------|
| `'event` | boolean | 信号发生变化时返回 **true** |
| `'last_value` | 信号类型 | 本次变化 **之前** 的值 |
| `'last_event` | time | 距上次变化的时间间隔 |
| `'delayed(t)` | 信号类型 | 延迟 t 时间后的值 |
| `'stable(t)` | boolean | t 时间内无变化返回 **true** |
| `'transaction` | bit | 每次变化翻转一次（'0'↔'1'） |

#### 3.4.2 举例：检测时钟上升沿（PPT 例子）

```vhdl
-- 判断 clk 上升沿
if (clk'event) and (clk = '1') and (clk'last_value = '0') then
  -- 上升沿到达，执行寄存器更新
  q <= d;
end if;
```

```vhdl
-- 判断 clk 下降沿
if (clk'event) and (clk = '0') and (clk'last_value = '1') then
  -- 下降沿操作
end if;
```

> **现代写法**（IEEE 1164）：`if rising_edge(clk) then ...`

#### 3.4.3 属性应用：延时赋值

```vhdl
-- B 延时 10ns 后赋给 A
A <= B'delayed(10 ns);
```

#### 3.4.4 属性应用：稳定性检测

```vhdl
if B'stable(10 ns) then
  -- B 在 10ns 内没有变化
end if;
```

#### 3.4.5 多驱动源问题（PPT 重点）

```vhdl
-- 信号 Z 有两个驱动源 A 和 B
-- Z 必须定义为允许多驱动的类型（如 std_logic），否则非法
signal Z : std_logic;
Z <= A;  -- 驱动源 1
Z <= B;  -- 驱动源 2（需 resolution function，std_logic 自带）
```

**要点**：`std_ulogic` 只允许 **一个驱动源**；`std_logic` 允许多驱动（有 resolution）。

---

### 3.5 VHDL 的十种标准类型

| 序号 | 类型 | 说明 | 示例 |
|------|------|------|------|
| 1 | **bit** | 二值：`'0'`, `'1'` | `signal a : bit := '0';` |
| 2 | **bit_vector** | 位向量 | `"1010"` |
| 3 | **boolean** | `true`, `false` | `signal flag : boolean;` |
| 4 | **time** | 时间 | `10 ns`, `100 ms`, `3 s` |
| 5 | **character** | 字符 | `'A'`, `'0'` |
| 6 | **string** | 字符串 | `"my design"`, `"error!"` |
| 7 | **integer** | 32 位整数 | `-100`, `0`, `99999` |
| 8 | **real** | 浮点，-1.0E38 ~ +1.0E38 | `3.14`, `2.718` |
| 9 | **natural** | 自然数（≥0） | `0`, `1`, `100` |
| 10 | **positive** | 正整数（≥1） | `1`, `2`, `100` |
| 11 | **severity_level** | 配合 assert | `note`, `warning`, `error`, `failure` |

> 使用这十种以外的类型，需 **自行定义** 或 **引用 Library/Package**。

#### 3.5.1 类型赋值示例

**例子一：bit 与 bit_vector**

```vhdl
signal a : bit := '1';
signal bus : bit_vector(3 downto 0) := "1010";
bus(0) <= '1';           -- 位选择
bus <= "0000";           -- 整体赋值
```

**例子二：integer 运算**

```vhdl
signal count : integer range 0 to 255 := 0;
count <= count + 1;
```

**例子三：time 类型（仿真用）**

```vhdl
constant T_clk : time := 20 ns;
wait for T_clk;
```

**例子四：boolean 用于条件**

```vhdl
signal enable : boolean := false;
if enable then
  ...
end if;
```

**例子五：string 用于 report**

```vhdl
report "Simulation started" severity note;
report "Value out of range!" severity error;
```

> **注意（PPT）**：引用时间时，有的编译器要求 **数值与单位之间有空格**：`1 ns` ✅，`1ns` ❌

---

### 3.6 集合操作与连接操作符

#### 3.6.1 连接操作符 `&`

```vhdl
signal a, b : std_logic;
signal c : std_logic_vector(1 downto 0);
c <= a & b;                    -- 拼接两位
c <= '0' & a;                  -- 高位补 0
```

#### 3.6.2 集合操作 `()`

```vhdl
signal word : std_logic_vector(7 downto 0);
signal nibble : std_logic_vector(3 downto 0);
nibble <= word(7 downto 4);    -- 取高 4 位
```

#### 3.6.3 采用 others

```vhdl
signal bus : std_logic_vector(7 downto 0);
bus <= (others => '0');                    -- 全部置 0
bus <= (7 => '1', others => '0');          -- 仅 bit7 为 1
bus <= (1 downto 0 => "11", others => '0'); -- 低 2 位为 11
```

---

### 3.7 用户自定义类型

**通用格式：**

```vhdl
type 类型名 is 数据类型定义;
```

#### 3.7.1 枚举类型（Enumerated）

```vhdl
type week is (sun, mon, tue, wed, thu, fri, sat);
type state_type is (idle, read, write, done);
signal today : week := mon;
```

#### 3.7.2 整数型与实数型（带范围约束）

```vhdl
type day_of_week is range 1 to 7;
type current_amp is range -1.0e4 to 1.0e4;
signal d : day_of_week := 1;
```

#### 3.7.3 数组类型（Array）

```vhdl
type week_hours is array (1 to 7) of integer;
type matrix is array (1 to 7) of week_hours;  -- 二维数组
signal hours : week_hours := (1,2,3,4,5,6,7);
```

#### 3.7.4 时间类型（带单位）

```vhdl
type delay_time is range -1E18 to 1E18
  units
    fs;
    ps = 1000 fs;
    ns = 1000 ps;
    us = 1000 ns;
    ms = 1000 us;
    sec = 1000 ms;
  end units;
```

#### 3.7.5 记录类型（Record）

PPT 例子：

```vhdl
type order is record
  id       : integer;
  date_str : string(1 to 10);
  security : boolean;
end record;

signal order1 : order;
signal flag   : boolean;

order1 <= (3423, "1999/07/07", true);
flag   <= order1.security;   -- 访问记录成员
```

---

### 3.8 IEEE 1164 标准类型（工程必用）

定义在 `ieee.std_logic_1164` 包中，位于 **IEEE 库**。

| 类型 | 驱动源数量 | 说明 |
|------|------------|------|
| **std_ulogic** | 仅 1 个 | 九态逻辑，不可多驱动 |
| **std_logic** | 可多个 | 带 resolution，可用于总线 |
| **std_ulogic_vector** | — | 向量版 |
| **std_logic_vector** | — | 向量版（最常用） |

**九态逻辑值：**

| 符号 | 含义 |
|------|------|
| `'U'` | Uninitialized（未初始化） |
| `'X'` | Unknown（未知/冲突） |
| `'0'` | 强 0 |
| `'1'` | 强 1 |
| `'Z'` | 高阻 |
| `'W'` | 弱未知 |
| `'L'` | 弱 0 |
| `'H'` | 弱 1 |
| `'-'` | Don't care |

**引用方式：**

```vhdl
library ieee;
use ieee.std_logic_1164.all;

signal a : std_logic := '0';
signal bus : std_logic_vector(7 downto 0) := (others => '0');
```

#### 练习：下面哪一个是正确的？

```vhdl
-- A
signal x : std_ulogic;
x <= '0';
x <= '1';  -- ❌ 两个驱动源，std_ulogic 不允许

-- B
signal y : std_logic;
y <= '0';
y <= 'Z';  -- ✅ std_logic 可以（总线场景）

-- C
signal z : bit_vector(3 downto 0);
z <= "1010";  -- ✅
z <= 10;      -- ❌ 不能把 integer 直接赋给 bit_vector
```

**正确答案：B 和 C 的第一条正确；A 错误；C 第二条错误。**

---

### 3.9 VHDL 中的操作符

#### 3.9.1 逻辑操作符

| 操作符 | 含义 | 适用类型 |
|--------|------|----------|
| `and` | 与 | boolean, bit, std_logic |
| `or` | 或 | 同上 |
| `nand` | 与非 | 同上 |
| `nor` | 或非 | 同上 |
| `xor` | 异或 | 同上 |
| `xnor` | 同或 | 同上 |
| `not` | 非 | 同上 |

**应用示例：**

```vhdl
signal y : std_logic;
y <= (a and b) or (c and not d);
y <= a xor b xor cin;
```

#### 3.9.2 关系操作符

| 操作符 | 含义 |
|--------|------|
| `=` | 等于 |
| `/=` | 不等于 |
| `<` `>` `<=` `>=` | 大小比较 |

```vhdl
if count = MAX then ...
if a /= b then ...
```

#### 3.9.3 数学运算符

| 操作符 | 含义 | 适用 |
|--------|------|------|
| `+` `-` `*` | 加减乘 | integer, real |
| `/` `mod` `rem` | 除、模、余 | integer |
| `**` | 幂 | integer |
| `abs`, `sll`, `srl`, `sla`, `sra`, `rol`, `ror` | 绝对值、移位、旋转 | 位向量 |

```vhdl
signal sum : integer;
sum <= a + b;
signal shifted : std_logic_vector(7 downto 0);
shifted <= bus sll 2;  -- 逻辑左移 2 位
```

---

### 3.10 操作符应用要点（PPT 强调）

| 要点 | 说明 |
|------|------|
| **强类型** | 不同类型之间 **不能** 直接运算，需 **类型转换** |
| **vector ≠ number** | `"1010"` 是 bit_vector，不是整数 10 |
| **array ≠ number** | 数组整体不能当数字用 |

#### 类型转换示例

```vhdl
library ieee;
use ieee.numeric_std.all;

signal v : std_logic_vector(3 downto 0) := "1010";
signal n : unsigned(3 downto 0);
signal i : integer;

n <= unsigned(v);           -- std_logic_vector → unsigned
i <= to_integer(unsigned(v)); -- → integer，值为 10
v <= std_logic_vector(to_unsigned(5, 4));  -- integer → vector
```

#### 错误示例

```vhdl
signal a : bit_vector(3 downto 0);
signal b : integer;
-- a <= b;        -- ❌ 类型不匹配
-- a <= a + 1;    -- ❌ bit_vector 不能直接用 +
```

---

### 3.11 第二讲小结

| 对象 | 符号 | 作用域 | 更新 |
|------|------|--------|------|
| Constant | `:=` | 全局/局部 | 不变 |
| Variable | `:=` | Process 内 | 立即 |
| Signal | `<=` | Process 外 | 延迟 |

**下一讲预告**：VHDL 中的控制语句及模块

---

## 4. 第三讲：控制语句及模块

### 4.1 并发 vs 顺序（PPT 核心概念）

| 类型 | 英文 | 执行特点 | 适用位置 |
|------|------|----------|----------|
| **并行处理** | Concurrent | 与书写顺序无关，**同时生效** | Architecture、Block |
| **顺序处理** | Sequential | 按书写顺序 **依次执行** | Process、Function、Procedure |

**结构关系：**

```
Architecture 中的语句          → 并行
  ├── Block 中的语句           → 并行
  ├── Process 中的语句         → 顺序
  └── Subprogram 中的语句      → 顺序
```

#### 对比示例

**并发（三条同时生效）：**

```vhdl
architecture rtl of ex is
begin
  y1 <= a and b;    -- 这三条没有先后顺序
  y2 <= c or d;     -- 仿真中同一时刻都执行
  y3 <= e xor f;
end rtl;
```

**顺序（有先后）：**

```vhdl
process(a, b)
  variable temp : bit;
begin
  temp := a;        -- 第 1 步
  temp := temp and b; -- 第 2 步
  y <= temp;        -- 第 3 步
end process;
```

---

### 4.2 Block（块）结构

#### 4.2.1 格式

```vhdl
块名 : block [ (布尔表达式) ]
  [定义语句]
begin
  [并行处理语句]
  [ guarded 信号赋值 ]  -- 仅当布尔表达式为 true 时生效
end block 块名;
```

#### 4.2.2 条件 Block 示例（PPT）

```vhdl
myblock1 : block (clk = '1')   -- 仅当 clk='1' 时块内 guarded 语句有效
  signal qin : bit := '0';
begin
  qout <= guarded qin;
end block myblock1;
```

#### 4.2.3 Block 延时示例

```vhdl
Myblock : block
begin
  clr <= '1' after 10 ns;
  clr <= '0' after 20 ns;
end block Myblock;
-- 10ns 后 clr=1，20ns 后 clr=0
```

> **注意**：若两条赋值间隔短于信号稳定时间，可能出现 **不稳定状态**（PPT 特别强调）。

---

### 4.3 Process（进程）结构

#### 4.3.1 格式

```vhdl
process [ (敏感信号列表) ]
  [定义语句]
begin
  [顺序处理语句]
end process;
```

#### 4.3.2 敏感信号列表原则（PPT 重点）

> **在 Process 中，其值被引用的 signal 应当出现在敏感信号列表中。**

```vhdl
-- ✅ 正确
process (clk, reset, d)
begin
  if reset = '1' then
    q <= '0';
  elsif clk'event and clk = '1' then
    q <= d;
  end if;
end process;

-- ❌ 错误：缺少 d
process (clk, reset)
begin
  q <= d;  -- d 变化时 process 不会重启
end process;
```

#### 4.3.3 Process 示例

```vhdl
process (clk, qin)
  variable temp : bit := '0';
begin
  temp := qin;
  qout <= temp;
end process;
```

#### 4.3.4 Process 与 Wait 的等价关系

```vhdl
-- 以下两种写法等价：
process (a, b)
begin
  y <= a and b;
end process;

process
begin
  wait on a, b;    -- 等待 a 或 b 变化
  y <= a and b;
end process;
```

> **错误**：若 process 已有敏感信号列表，则 **不能再使用 wait 语句**。

#### 4.3.5 无 Wait 且无敏感列表的 Process

```vhdl
process
begin
  y <= a and b;
end process;
-- 会循环执行！通常不是期望行为
```

---

### 4.4 Subprogram：Function 与 Procedure

#### 4.4.1 Function（函数）

```vhdl
function 函数名 (参数1, 参数2 : 类型) return 返回类型 is
  [定义语句]
begin
  [顺序语句]
  return 返回值;
end function;
```

**PPT 例子（判断两 bit 是否相等）：**

```vhdl
function is_equal (a, b : bit) return boolean is
  variable flag : boolean;
begin
  if (a = b) then
    flag := true;
  else
    flag := false;
  end if;
  return flag;
end function is_equal;
```

**调用：**

```vhdl
signal result : boolean;
result <= is_equal(x, y);
```

#### 4.4.2 Procedure（过程）

```vhdl
procedure 过程名 (参数1 : in 类型; 参数2 : out 类型) is
begin
  [顺序语句]
end procedure;
```

**PPT 例子：**

```vhdl
procedure max_bit (a, b : in bit; flag : out boolean) is
begin
  if a = b then
    flag := true;
  else
    flag := false;
  end if;
end procedure max_bit;
```

**Function vs Procedure：**

| | Function | Procedure |
|---|----------|-----------|
| 返回值 | 必须有 return | 通过 out/inout 参数 |
| 调用方式 | `x <= func(a,b)` | `proc(a, b, result)` |
| 用途 | 表达式、纯计算 | 多输出、过程化操作 |

---

### 4.5 顺序语句详解

#### 4.5.1 Wait 语句

| 形式 | 功能 |
|------|------|
| `wait;` | 无限等待（挂起 forever） |
| `wait on 信号列表;` | 等待列表中任一信号变化 |
| `wait until 条件;` | 等待条件为 true |
| `wait for 时间;` | 等待指定时间 |

**功能**：Wait 使进程 **挂起**，此时 **signal 开始更新**；条件满足后继续。

**示例：产生周期 100 ns 的时钟**

```vhdl
process
begin
  clk <= '0';
  wait for 50 ns;
  clk <= '1';
  wait for 50 ns;
end process;
```

**Wait 示例：**

```vhdl
process (a, b)
begin
  y <= a and b;
end process;
-- 等价于 wait on a,b 后赋值
```

#### 4.5.2 Assert 语句

```vhdl
assert 条件 [report "信息"] [severity 级别];
```

- 条件为 **true**：继续执行
- 条件为 **false**：输出错误信息

```vhdl
assert (sum = 100) report "sum /= 100" severity error;
assert (count < MAX) report "Counter overflow" severity warning;
```

**severity 级别**：`note` < `warning` < `error` < `failure`

#### 4.5.3 If 语句

```vhdl
if 条件 then
  语句;
[elsif 条件 then
  语句;]
[else
  语句;]
end if;
```

**示例：带复位的 D 触发器**

```vhdl
process (clk, reset)
begin
  if reset = '1' then
    q <= '0';
  elsif clk'event and clk = '1' then
    q <= d;
  end if;
end process;
```

**示例：4 选 1 多路器（if 版）**

```vhdl
process (sel, a, b, c, d_in)
begin
  if sel = "00" then
    y <= a;
  elsif sel = "01" then
    y <= b;
  elsif sel = "10" then
    y <= c;
  else
    y <= d_in;
  end if;
end process;
```

#### 4.5.4 Case 语句

```vhdl
case 表达式 is
  when 值1 => 语句;
  when 值2 | 值3 => 语句;
  when others => 语句;
end case;
```

**两大原则（PPT 强调）：**

1. **完全性**：所有可能取值都要覆盖，可用 `others`
2. **唯一性**：同一取值只能出现一次

**示例：3-8 译码器**

```vhdl
process (addr)
begin
  case addr is
    when "000" => y <= "00000001";
    when "001" => y <= "00000010";
    when "010" => y <= "00000100";
    when "011" => y <= "00001000";
    when "100" => y <= "00010000";
    when "101" => y <= "00100000";
    when "110" => y <= "01000000";
    when "111" => y <= "10000000";
    when others => y <= (others => '0');
  end case;
end process;
```

#### 4.5.5 For Loop 语句

```vhdl
for 循环变量 in 范围 loop
  顺序语句;
end loop;
```

**示例：累加**

```vhdl
variable sum : integer := 0;
for i in 1 to 10 loop
  sum := sum + i;
end loop;
```

**next 与 exit：**

```vhdl
for i in 1 to 10 loop
  sum := sum + 1;
  next when sum = 100;   -- 跳过本次循环
  exit when sum = 100;   -- 结束整个循环
end loop;
```

#### 4.5.6 While 语句

```vhdl
while 条件 loop
  顺序语句;
end loop;
```

**示例：**

```vhdl
variable i : integer := 0;
while i < 10 loop
  i := i + 1;
end loop;
```

---

### 4.6 并行处理语句（Concurrent Statement）

#### 4.6.1 信号赋值 `<=`

- 可用于 **顺序语句**（Process 内）和 **并行语句**（Architecture/Block 内）
- **并行使用时**：右边为 **敏感信号**，变化即重新执行
- **顺序使用时**：按进程顺序执行，无"敏感"概念

```vhdl
-- 并行：a 或 b 变化，y 自动更新
y <= a and b;

-- 带延时
c <= (a xor b) after 10 ns;
```

#### 4.6.2 条件信号赋值（When-Else）

```vhdl
目的信号 <= 表达式1 when 条件1 else
            表达式2 when 条件2 else
            表达式3;
```

**PPT 例子：4 选 1 MUX**

```vhdl
sel <= b & a;
q <= ain  when sel = "00" else
     bin  when sel = "01" else
     cin  when sel = "10" else
     din  when sel = "11" else
     'X';
```

> **最后的 else 项是必须的**，以满足完全性和唯一性。

#### 4.6.3 选择信号赋值（With-Select-When）

```vhdl
with 表达式 select
  目的信号 <= 表达式1 when 条件1,
              表达式2 when 条件2,
              表达式n when others;
```

**PPT 例子：**

```vhdl
with sel select
  q <= ain when "00",
       bin when "01",
       cin when "10",
       din when "11",
       'X' when others;
```

#### When-Else vs With-Select 对比

| 特性 | When-Else | With-Select |
|------|-----------|-------------|
| 语法 | 链式 else | 单一表达式匹配 |
| 优先级 | 从上到下 | 并行选择 |
| 必须 others/else | else 必须 | others 必须 |

---

### 4.7 Generic（类属）语句

用于 **参数化设计**，类似模板参数。

**PPT 例子：可配置延时的与门**

```vhdl
entity and2 is
  generic (
    rise : time := 10 ns
  );
  port (
    a, b : in  bit;
    c      : out bit
  );
end entity and2;

architecture behav of and2 is
begin
  c <= (a and b) after rise;
end architecture behav;
```

**例化时指定 Generic：**

```vhdl
U1 : and2 generic map (rise => 5 ns)
         port map (a => x, b => y, c => z);
```

**更多 Generic 应用：**

```vhdl
entity counter is
  generic (
    WIDTH : integer := 8;
    MAX   : integer := 255
  );
  port (
    clk, reset : in  std_logic;
    count      : out std_logic_vector(WIDTH-1 downto 0)
  );
end entity counter;
```

---

### 4.8 顺序 vs 并行语句总结（PPT）

| 语句类型 | 只能用于 |
|----------|----------|
| wait, assert, if, case, for-loop, while | Process、Function、Procedure |
| 条件信号赋值（when-else）、选择信号赋值（with-select） | Architecture、Block |
| 元件例化（port map） | Architecture、Block |

---

### 4.9 第三讲综合示例：8 位计数器

```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity counter8 is
  port (
    clk, reset, enable : in  std_logic;
    count              : out std_logic_vector(7 downto 0)
  );
end entity counter8;

architecture rtl of counter8 is
  signal cnt : unsigned(7 downto 0) := (others => '0');
begin
  process (clk, reset)
  begin
    if reset = '1' then
      cnt <= (others => '0');
    elsif rising_edge(clk) then
      if enable = '1' then
        cnt <= cnt + 1;
      end if;
    end if;
  end process;
  count <= std_logic_vector(cnt);
end architecture rtl;
```

---

### 4.10 第三讲小结

| 模块 | 类型 | 用途 |
|------|------|------|
| Process | 顺序 | 时序逻辑、复杂组合 |
| Block | 并行 | 分组、guard 条件 |
| Function | 顺序 | 返回值计算 |
| Procedure | 顺序 | 过程化操作 |
| When-Else / With-Select | 并行 | 多路选择 |

**结束语（PPT）**：祝贺您完成了 VHDL 基本内容的学习，希望您在实践过程中能学到更多！

**下一讲预告**：状态机的设计

---

## 5. 第四讲：状态机的设计

### 5.1 概念

**状态机（Finite State Machine, FSM）** 是一类 **极其重要的时序电路**，是许多数字系统的 **核心部件**。

**典型应用：**
- 交通灯控制器
- UART 发送/接收
- CPU 控制单元
- 序列检测器
- 电梯控制

---

### 5.2 状态机概述

状态机在任意时刻处于 **有限个状态** 之一，根据 **当前状态** 和 **输入** 决定 **下一状态** 和 **输出**。

---

### 5.3 状态机的结构（PPT）

```
                    ┌──────────────┐
        输入 ──────►│  状态译码器   │──────► 下一状态
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │  状态寄存器   │◄──── 时钟
                    │ (当前状态)    │
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │  输出译码器   │──────► 输出信号
                    └──────────────┘
```

| 部件 | 功能 |
|------|------|
| **状态译码器** | 组合逻辑，确定 **下一状态** |
| **状态寄存器** | 存储 **当前状态**，时钟边沿更新 |
| **输出译码器** | 组合逻辑，确定 **输出信号** |

---

### 5.4 状态机的基本操作

1. **状态转换**：下一状态由译码器根据 **当前状态 + 输入条件** 决定
2. **输出生成**：输出由译码器根据 **当前状态（± 输入）** 决定

---

### 5.5 状态机的时序

| 类型 | 特点 | 综合建议 |
|------|------|----------|
| **同步时序状态机** | 状态转换由 **时钟边沿** 触发 | ✅ **推荐使用** |
| **异步时序状态机** | 状态转移 **不依赖时钟** | ⚠️ 易产生毛刺，难综合 |

> **PPT 强调**：可综合的状态机设计 **应使用同步状态机**。

---

### 5.6 状态机的类型：Moore vs Mealy

| 类型 | 输出依赖 | 特点 |
|------|----------|------|
| **Moore（莫尔）** | **仅当前状态** | 输出比 Mealy 晚一个周期，更稳定 |
| **Mealy（米里）** | **当前状态 + 输入** | 响应更快，状态数可能更少 |

#### 举例：检测输入序列 "101"

**Moore 型**：输出仅当进入"检测到"状态时置 1

```
状态: S0 --1--> S1 --0--> S2 --1--> S3(输出=1)
```

**Mealy 型**：在 S2 状态且输入=1 时，输出立即为 1

```
状态: S0 --1--> S1 --0--> S2 --1--> (输出=1, 回 S0)
```

#### VHDL 模板：Moore 型

```vhdl
type state_type is (S0, S1, S2, S3);
signal current_state, next_state : state_type;

-- 状态寄存器（同步）
process (clk, reset)
begin
  if reset = '1' then
    current_state <= S0;
  elsif rising_edge(clk) then
    current_state <= next_state;
  end if;
end process;

-- 次态逻辑（组合）
process (current_state, input)
begin
  case current_state is
    when S0 => if input = '1' then next_state <= S1; else next_state <= S0; end if;
    when S1 => if input = '0' then next_state <= S2; else next_state <= S1; end if;
    when S2 => if input = '1' then next_state <= S3; else next_state <= S0; end if;
    when S3 => next_state <= S0;
  end case;
end process;

-- 输出逻辑（Moore：仅依赖 current_state）
process (current_state)
begin
  case current_state is
    when S3    => output <= '1';
    when others => output <= '0';
  end case;
end process;
```

#### VHDL 模板：Mealy 型

```vhdl
process (current_state, input)
begin
  output <= '0';  -- 默认值
  case current_state is
    when S2 => if input = '1' then output <= '1'; end if;
    when others => null;
  end case;
end process;
```

---

### 5.7 状态机的表达方式

三种方法 **等价，可相互转换**：

| 方法 | 说明 | 适用场景 |
|------|------|----------|
| **状态图** | 圆圈=状态，箭头=转移 | 设计初期 |
| **状态表** | 表格：现态+输入→次态+输出 | 规范文档 |
| **流程图** | 流程框图 | 与软件流程对接 |

---

### 5.8 例子：三进制计数器（PPT）

状态：`S0 → S1 → S2 → S0 → ...`

```vhdl
type ternary_state is (S0, S1, S2);
signal state, nstate : ternary_state;

process (clk, reset)
begin
  if reset = '1' then
    state <= S0;
  elsif rising_edge(clk) then
    state <= nstate;
  end if;
end process;

process (state)
begin
  case state is
    when S0 => nstate <= S1;
    when S1 => nstate <= S2;
    when S2 => nstate <= S0;
  end case;
end process;
```

**状态图：**

```
    ┌───┐     ┌───┐     ┌───┐
    │S0 │────►│S1 │────►│S2 │
    └───┘     └───┘     └───┘
      ▲                   │
      └───────────────────┘
```

---

### 5.9 例子：序列检测器（1110010）（PPT）

检测输入位流中是否出现序列 **1110010**，检测到则输出 1。

**设计步骤：**

1. 列出所有前缀状态：ε, 1, 11, 111, 1110, 11100, 111001, 1110010
2. 画状态转移图
3. 编写 VHDL

**简化状态定义：**

```vhdl
type seq_state is (
  ST0,   -- 未匹配
  ST1,   -- 收到 1
  ST11,  -- 收到 11
  ST111, -- 收到 111
  ST1110,
  ST11100,
  ST111001,
  ST1110010  -- 完整匹配
);
```

**次态逻辑示例（部分）：**

```vhdl
process (state, din)
begin
  nstate <= ST0;  -- 默认
  case state is
    when ST0 =>
      if din = '1' then nstate <= ST1; else nstate <= ST0; end if;
    when ST1 =>
      if din = '1' then nstate <= ST11; else nstate <= ST0; end if;
    when ST11 =>
      if din = '1' then nstate <= ST111; else nstate <= ST0; end if;
    -- ... 继续补充
    when ST1110010 =>
      dout <= '1';  -- Mealy 可在此输出
      nstate <= ST0;
    when others => nstate <= ST0;
  end case;
end process;
```

**测试向量：**

```
输入: 1 1 1 0 0 1 0 1 1 1 0 0 1 0
                ↑ 检测到 1110010
输出: 0 0 0 0 0 0 0 1 0 0 0 0 0 0
```

---

### 5.10 状态机设计最佳实践

| 实践 | 说明 |
|------|------|
| 使用枚举类型 | `type state_type is (...)` 可读性好 |
| 三段式结构 | 寄存器 + 次态逻辑 + 输出逻辑 |
| 同步复位 | `if reset='1' then state <= INIT;` |
| 完整 case | 必须有 `others` 分支 |
| 默认赋值 | 组合 process 开头给输出默认值，避免 latch |
| One-Hot 编码 | 状态多时考虑，利于 FPGA |

---

### 5.11 第四讲小结

| 概念 | 要点 |
|------|------|
| 结构 | 状态寄存器 + 两个译码器 |
| 同步 vs 异步 | 优先同步 |
| Moore | 输出只看状态 |
| Mealy | 输出看状态+输入 |
| 表达 | 状态图、状态表、流程图等价 |

---

## 6. VHDL 上机指导

### 6.1 编译和仿真工具

PPT 推荐：
- **OR-CAD** 或 **ACTIVE-VHDL**
- 本次培训采用 **ACTIVE-VHDL**

### 6.2 Active-VHDL 自带教程

- **目录**：`..\Active VHDL\book\Avhdl.htm`
- 建议首次使用前通读该 HTML 教程

### 6.3 典型上机流程

```
1. 新建工程 (Project)
      ↓
2. 添加 VHDL 源文件 (Entity + Architecture)
      ↓
3. 编译 (Compile) — 检查语法
      ↓
4. 编写 Testbench
      ↓
5. 仿真 (Simulate) — 查看波形
      ↓
6. （可选）综合 (Synthesize) — 映射到 FPGA
```

### 6.4 第一个上机实验：半加器

**步骤：**

1. 新建 `HalfAdd.vhd`，写入第一讲半加器代码
2. 新建 `tb_HalfAdd.vhd`，写入 testbench
3. Compile All
4. Simulate → 添加信号到波形窗口
5. Run 100 ns，验证真值表

**常见问题：**

| 问题 | 解决 |
|------|------|
| 编译报错 "library ieee not found" | 检查 VHDL 版本，确认 IEEE 库路径 |
| 波形全为 U | 检查 testbench 是否产生激励 |
| 无波形 | 确认 simulate 的是 testbench |

---

## 7. 综合练习与常见错误

### 7.1 综合练习

#### 练习 1：2-4 译码器

输入 2 位 `addr`，输出 4 位 one-hot `y`。

<details>
<summary>参考答案</summary>

```vhdl
entity decoder2to4 is
  port (
    addr : in  std_logic_vector(1 downto 0);
    y    : out std_logic_vector(3 downto 0)
  );
end entity;

architecture rtl of decoder2to4 is
begin
  with addr select
    y <= "0001" when "00",
         "0010" when "01",
         "0100" when "10",
         "1000" when "11",
         (others => '0') when others;
end architecture;
```

</details>

#### 练习 2：可加载计数器

带 `load`、`load_value`、`enable`、`reset`。

#### 练习 3：Mealy 型 "1101" 序列检测器

#### 练习 4：交通灯控制器（红 30s、绿 25s、黄 5s）

---

### 7.2 常见错误汇总

| 错误 | 原因 | 修正 |
|------|------|------|
| `signal` 写在 process 内 | 违反作用域规则 | 移到 architecture |
| `variable` 写在 architecture | 违反作用域规则 | 移到 process 内 |
| 敏感列表遗漏 | 仿真与综合不一致 | 补全所有读取的 signal |
| process 内既有敏感列表又有 wait | 语法冲突 | 二选一 |
| case 缺少 others | 产生 latch | 加 `when others` |
| `1ns` 无空格 | 部分工具不支持 | 改为 `1 ns` |
| bit_vector 与 integer 混用 | 强类型 | 使用 `numeric_std` 转换 |
| 多驱动 std_ulogic | 仅允许单驱动 | 改用 std_logic |

---

## 8. 附录：速查表

### 8.1 端口方向速查

```
in     → 只读
out    → 只写
inout  → 读写
buffer → 可反馈
```

### 8.2 赋值符号

```
:=   → constant 初始化、variable 赋值
<=   → signal 赋值
=>   → port map / generic map 关联
```

### 8.3 常用 IEEE 库

```vhdl
use ieee.std_logic_1164.all;   -- 九态逻辑
use ieee.numeric_std.all;      -- unsigned/signed 运算
use ieee.std_logic_arith.all;  -- 旧版，不推荐新项目
use ieee.std_logic_unsigned.all;
```

### 8.4 进程模板（寄存器）

```vhdl
process (clk, reset)
begin
  if reset = '1' then
    q <= '0';
  elsif rising_edge(clk) then
    q <= d;
  end if;
end process;
```

### 8.5 状态机模板（三段式）

```vhdl
-- 1. 状态寄存器
-- 2. 次态逻辑 (combinational)
-- 3. 输出逻辑 (Moore/Mealy)
```

---

## 结语

本学习文档基于《VHDL培训教程》PPT 系统整理，并在各章节补充了大量 **示例代码、真值表、对比表格和设计实践**，旨在帮助读者：

1. **理解** VHDL 的设计哲学与结构层次  
2. **掌握** Entity/Architecture、对象类型、控制语句、状态机  
3. **实践** 从半加器到序列检测器的完整设计流程  
4. **上手** Active-VHDL 仿真环境  

> **PPT 结束语**：祝贺您完成了 VHDL 基本内容的学习，希望您在实践过程中能学到更多！

---

**文档信息**

| 项目 | 内容 |
|------|------|
| 来源 | VHDL培训教程.ppt |
| 单位 | 浙江大学电子信息技术研究所 · EDA培训中心 |
| 联系人 | 王勇，TEL: 7951949 或 7951712 |
| EMAIL | wangy@isee.zju.edu.cn |
| 整理日期 | 2026-08-27 |
