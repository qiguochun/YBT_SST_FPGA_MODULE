# ENTITY 与 ARCHITECTURE：内外二分

> 核心心智模型：VHDL 把模块拆成**外部接口（ENTITY）**与**内部实现（ARCHITECTURE）**。  
> 调用者只认 ENTITY；实现可替换、可多版本并存。

---

## 1. 黑盒与白盒

| 部分 | 角色 | 类比 | 外界是否可见 |
|------|------|------|--------------|
| **ENTITY** | 接口契约：方向、类型、GENERIC | 数据手册 / 引脚图 | 可见 |
| **ARCHITECTURE** | 功能实现：算法、RTL、连线 | 内部电路版图 | 不可见（对调用者） |

**关键优势**：一个 ENTITY 可对应多个 ARCHITECTURE（高性能 / 低功耗 / 行为仿真模型）。通过 `CONFIGURATION` 选定实现，顶层例化代码无需改动——这是 VHDL 软核复用的基础。

```vhdl
ENTITY 实体名 IS
  GENERIC ( 常量名 : 数据类型 := 默认值; );
  PORT    ( 端口名 : 端口模式 数据类型 [:= 初始值]; );
END ENTITY 实体名;   -- 可简写 END 实体名;

ARCHITECTURE 构造体名 OF 实体名 IS
  -- 声明区：SIGNAL / COMPONENT / CONSTANT / 类型 ...
BEGIN
  -- 并行语句区：PROCESS、并发赋值、例化、GENERATE
END ARCHITECTURE 构造体名;
```

---

## 2. ENTITY：外部接口

### 2.1 GENERIC（类属）——静态配置

- 向内部传递**编译期/例化期静态参数**（位宽、上限、延时裕量等），不是运行时信号。
- 例化用 `GENERIC MAP`；决定硬件展开规模（如 WIDTH=8 → 8 个触发器）。
- 在 PROCESS 内**只能读，不能写**。

### 2.2 PORT MODE——信号方向（工程雷区）

| 模式 | 构造体内部 | 顶层外部 | 硬件本质 | 陷阱 |
|------|------------|----------|----------|------|
| **IN** | 只读，不可出现在赋值左侧 | 外部驱动内部 | 输入引脚 | 读到的是外部实时电平 |
| **OUT** | 只写；VHDL-2008 前内部不可回读 | 内部驱动外部 | 输出 | 计数器等需“读输出”时纯 OUT 会踩坑 |
| **INOUT** | 读写，需配合 `'Z'` 释放 | 双向 | 三态总线 | 多驱动冲突；不用时必须高阻 |
| **BUFFER** | 内部可读当前驱动值 | 内部驱动外部 | 带反馈输出 | 外部不能再驱动；多个 BUFFER 不宜直接互连 |

**实践建议**：新代码可用 VHDL-2008 的 OUT 回读；为兼容与可读性，反馈输出仍可用中间 SIGNAL，或明确使用 BUFFER。

### 2.3 常见端口类型

| 类型 | 来源 | 用途 |
|------|------|------|
| `BIT` / `BIT_VECTOR` | 标准 | 极简 0/1 仿真 |
| `STD_LOGIC` / `STD_LOGIC_VECTOR` | `STD_LOGIC_1164` | **最常用**，含 Z/W/L/H/- 等九值 |
| `SIGNED` / `UNSIGNED` | `NUMERIC_STD` | 有符号/无符号算术 |

---

## 3. ARCHITECTURE：内部实现

### 3.1 声明区要点

- **SIGNAL**：内部连线；`<=` 有 δ 延迟，下一仿真快照才更新。
- **SHARED VARIABLE**：跨进程共享，综合支持差，慎用。
- **COMPONENT**：待例化的子模块声明。

### 3.2 三种描述风格

| 风格 | 载体 | 抽象级 | 硬件映射 |
|------|------|--------|----------|
| **行为 Behavioral** | `PROCESS` + IF/CASE/LOOP | 算法级 | 组合或时序（看敏感表/时钟） |
| **数据流 Dataflow** | 并发 `<=`、`WHEN…ELSE`、`WITH…SELECT` | RTL | 门/MUX 连线 |
| **结构 Structural** | 例化 + `GENERATE` | 网表级 | 子模块拓扑连接 |

**工程惯例**：顶层偏结构（搭积木），子模块偏行为/数据流（写算法）。大型设计多为混合式。

行为示例（D 触发器）：

```vhdl
PROCESS(clk, rst)
BEGIN
  IF rst = '1' THEN
    q <= '0';
  ELSIF rising_edge(clk) THEN
    q <= d;   -- δ 延迟后更新
  END IF;
END PROCESS;
```

数据流示例（2 选 1）：

```vhdl
q <= a WHEN sel = '0' ELSE b;
```

结构示例：

```vhdl
U1: AND2 PORT MAP (a => sig1, b => sig2, c => out_sig);
```

---

## 4. CONFIGURATION：绑定实现

在不改 ENTITY/ARCHITECTURE 源码的前提下，指定“用哪个构造体 / 哪个子实体的哪个版本”：

```vhdl
CONFIGURATION cfg_name OF 顶层实体名 IS
  FOR 选中的构造体名
    FOR 例化标签 : 子元件名
      USE ENTITY 库.子实体(子构造体);
    END FOR;
  END FOR;
END CONFIGURATION;
```

典型用途：同一接口在行为模型（快仿真）与门级网表（精确时序）之间切换。

---

## 5. 易混细节（面试 / 工程雷区）

### 5.1 SIGNAL vs VARIABLE

| | SIGNAL | VARIABLE |
|--|--------|----------|
| 语义 | 硬件连线 / 驱动源 | 进程内临时存储 |
| 赋值 | `<=`，有 δ 延迟 | `:=`，立即生效 |
| 作用域 | 构造体 / 端口 / 进程声明 | 当前 PROCESS / 子程序 |
| 综合 | 寄存器、连线、组合节点 | 常折叠为组合临时节点或锁存 |

**铁律**：PORT 本质是特殊 SIGNAL；不能把端口直接当 VARIABLE 用，需经中间 SIGNAL。

### 5.2 并发区 vs 顺序区

- `ARCHITECTURE` 的 `BEGIN…END`：**只能**放并行语句（PROCESS、例化、并发赋值、GENERATE）。
- `PROCESS` / `FUNCTION` / `PROCEDURE` 内：**只能**放顺序语句（IF、CASE、LOOP、变量赋值）。
- PROCESS 本身是并行的；内部代码是顺序的 → 硬件 = 多个进程并发协作。

### 5.3 PORT MAP

- 位置关联：`PORT MAP (sig1, sig2)` —— 顺序必须对齐，易错。
- **命名关联（推荐）**：`PORT MAP (port_a => sig1, port_b => sig2)`。

### 5.4 GENERATE

配合 GENERIC 批量复制硬件，是参数化 IP 的核心机制（`FOR … GENERATE`）。

---

## 6. 综合 vs 仿真

| 语境 | ENTITY | ARCHITECTURE |
|------|--------|--------------|
| **综合** | PORT→I/O；GENERIC→面积/结构展开 | PROCESS→触发器/LUT；并发赋值→连线；WAIT 受限 |
| **仿真** | 严格检查端口方向 | 遵循 δ 延迟；`AFTER`/`TRANSPORT` 等仅仿真有效 |

---

## 7. 完整示例：参数化同步清零计数器

```vhdl
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY param_counter IS
  GENERIC (
    WIDTH : INTEGER := 8
  );
  PORT (
    clk   : IN     STD_LOGIC;
    rst_n : IN     STD_LOGIC;  -- 低有效异步复位
    en    : IN     STD_LOGIC;
    cnt   : BUFFER STD_LOGIC_VECTOR(WIDTH-1 DOWNTO 0)  -- BUFFER 便于内部回读
  );
END ENTITY param_counter;

ARCHITECTURE rtl OF param_counter IS
  SIGNAL cnt_next : UNSIGNED(WIDTH-1 DOWNTO 0);
BEGIN
  -- 数据流：下一状态组合逻辑
  cnt_next <= UNSIGNED(cnt) + 1 WHEN (en = '1') ELSE UNSIGNED(cnt);

  -- 行为：寄存器打拍
  PROC_REG : PROCESS(clk, rst_n)
  BEGIN
    IF rst_n = '0' THEN
      cnt <= (OTHERS => '0');
    ELSIF rising_edge(clk) THEN
      cnt <= STD_LOGIC_VECTOR(cnt_next);
    END IF;
  END PROCESS PROC_REG;
END ARCHITECTURE rtl;
```

例化复用：

```vhdl
U_CNT: param_counter
  GENERIC MAP (WIDTH => 16)
  PORT MAP (
    clk   => clk,
    rst_n => rst_n,
    en    => en,
    cnt   => cnt_bus
  );
```

外部只看见 `clk/rst_n/en/cnt`；内部 `cnt_next` 对调用者透明。

> 等价现代写法：`cnt` 用 `OUT`，内部用 `SIGNAL cnt_r` 回读，再 `cnt <= cnt_r;` 驱动端口，可避免 BUFFER。

---

## 8. 工程价值（一句话版）

1. **并行工程**：接口定稿后，实现与 Testbench 可同时推进。  
2. **IP 保护**：可只交付 ENTITY + 加密/网表，隐藏 ARCHITECTURE。  
3. **多层次统一**：行为模型 → RTL → 结构网表，同一语言、不同 ARCHITECTURE 迭代。

---

## 可继续展开

- PROCESS 敏感列表细节  
- WAIT 语句用法  
- VITAL 时序仿真包  
