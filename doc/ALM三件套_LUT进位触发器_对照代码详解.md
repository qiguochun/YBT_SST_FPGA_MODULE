# ALM 三件套详解：LUT / 进位链 / 触发器 —— 对照 VHDL 代码

> 目标：看懂一个 ALM 里三块结构各自干什么，以及它们在代码里通常长什么样。  
> 语言以本工程常用的 **VHDL** 为例。

---

## 0. 先记住总关系

综合工具（Quartus）会把你的 VHDL **拆开、重组**，塞进很多个 ALM：

```text
你写的 VHDL
    │
    ▼
Quartus 综合
    │
    ├── 组合逻辑部分 ──► 主要进 LUT（查找表）
    ├── 加减/计数进位 ──► 常走 ALM 里的加法/进位结构
    └── 时钟沿保存的值 ──► 进触发器（寄存器）
```

不是“一行代码对应一个 ALM”，而是“一种写法倾向消耗某类结构”。

---

## 1. 查找表 LUT：组合逻辑的万能小计算器

### 1.1 LUT 是什么（大白话）

**LUT = Look-Up Table（查找表）**

可以把它想成一张“事先填好答案的真值表”：

- 输入几根线（0/1）
- 立刻查表输出结果
- **不依赖时钟**，输入变，输出跟着变（有微小门延时）

所以凡是“当前输入立刻决定输出、不需要记住历史”的逻辑，都主要靠 LUT。

### 1.2 LUT 能干什么

| 能力 | 例子 |
|------|------|
| 基本门 | 与、或、非、异或 |
| 选择 | 二选一、多路选择 |
| 比较 | 相等、更大、更小 |
| 位操作 | 拼接、截取、按位与或 |
| 小运算 | 很小位宽的复杂组合函数 |
| 译码/编码 | case 分支产生控制信号 |

### 1.3 在代码里怎么呈现

#### （1）逻辑运算符 —— 最典型的 LUT

```vhdl
y <= a and b;           -- 与
y <= a or b;            -- 或
y <= not a;             -- 非
y <= a xor b;           -- 异或
sel_n <= not sel;
```

这些都会变成组合逻辑，综合进 LUT。

#### （2）条件选择（when/else、with/select）—— LUT 做多路器

```vhdl
-- 二选一
y <= a when sel = '1' else b;

-- 多路选择
with sel select
  y <= d0 when "00",
       d1 when "01",
       d2 when "10",
       d3 when others;
```

硬件直觉：这就是 **MUX（选择器）**，主要由 LUT 实现。

#### （3）比较 —— LUT（较大位宽会用多级/进位相关结构辅助）

```vhdl
eq  <= '1' when (a = b) else '0';
gt  <= '1' when (unsigned(a) > unsigned(b)) else '0';
```

#### （4）组合 process（敏感列表无时钟）—— 整段都是组合，倾向 LUT

```vhdl
process(a, b, sel)
begin
  if sel = '1' then
    y <= a;
  else
    y <= b;
  end if;
end process;
```

注意：组合 process 必须把用到的输入都写进敏感列表，且每个分支都要给 `y` 赋值，否则容易推出锁存器（latch，新手雷区）。

#### （5）纯组合函数/并发语句

```vhdl
byte_en <= "1111" when we = '1' else "0000";
flag    <= '1' when (state = S_DONE and ready = '1') else '0';
```

---

## 2. 加法 / 进位相关结构：专门加速“算数进位”

### 2.1 为什么加减要特殊对待？

普通加减不只是“每位自己算完就结束”，还有 **进位**：

```text
  1 1 1 1
+ 0 0 0 1
---------
  0 0 0 0  并产生进位链一路传过去
```

若只用普通 LUT 硬拼很长的加法，进位路径会又慢又差。  
所以 ALM 里有 **专用进位链/加法相关结构**，让加减、计数更快更稳。

### 2.2 这类结构常对应什么功能？

| 功能 | 说明 |
|------|------|
| 加法 / 减法 | `a+b`、`a-b` |
| 计数器 +1/-1 | 最常见 |
| 累加 | `acc <= acc + x` |
| 比较器的一部分 | 某些幅度比较会借进位链优化 |
| 简单算术表达式 | 小位宽算术乘除外的算术 |

> 大位宽乘法更常进 **DSP 块**，不是主要靠这个进位链。

### 2.3 在代码里怎么呈现

#### （1）直接写加减

```vhdl
sum  <= std_logic_vector(unsigned(a) + unsigned(b));
diff <= std_logic_vector(unsigned(a) - unsigned(b));
```

综合后：算术部分走加法/进位结构，结果若再打拍则进触发器。

#### （2）计数器（超高频出现）

```vhdl
signal cnt : unsigned(7 downto 0) := (others => '0');

process(clk)
begin
  if rising_edge(clk) then
    if rst = '1' then
      cnt <= (others => '0');
    else
      cnt <= cnt + 1;   -- “+1”吃进位链；存 cnt 吃触发器
    end if;
  end if;
end process;
```

这里一次用到两样：

- `cnt + 1` → 加法/进位  
- `cnt <= ...` 在时钟沿更新 → 触发器

#### （3）累加器

```vhdl
process(clk)
begin
  if rising_edge(clk) then
    acc <= acc + unsigned(data_in);
  end if;
end process;
```

#### （4）到点比较（计数满）

```vhdl
if cnt = 99 then
  cnt <= (others => '0');
  tick <= '1';
else
  cnt <= cnt + 1;
  tick <= '0';
end if;
```

- `cnt + 1`：进位/加法  
- `cnt = 99`：比较（多由 LUT，也可能被优化）  
- `cnt/tick` 赋值：触发器

---

## 3. 触发器（寄存器）：专门“记住”上拍结果

### 3.1 触发器是什么

触发器（Flip-Flop / Register）做一件事：

> 在时钟边沿，把输入采样并保存，直到下一个有效边沿。

所以它解决的是：**时间上的记忆**。

没有触发器，电路只是“当前输入 → 当前输出”的即时逻辑；  
有了触发器，才能做状态机、计数、流水线、同步设计。

### 3.2 触发器能干什么

| 能力 | 例子 |
|------|------|
| 保存数据 | 打拍、暂存 |
| 同步设计 | 所有寄存器跟同一时钟 |
| 状态机状态 | `state` 寄存器 |
| 流水线 | 把长逻辑拆成多拍 |
| 消抖/延迟 | 把信号延后 N 拍 |
| 分频计数 | 计数器本体 |

### 3.3 在代码里怎么呈现（最重要）

#### （1）标准时钟进程 —— 触发器的“身份证”

```vhdl
process(clk)
begin
  if rising_edge(clk) then
    q <= d;
  end if;
end process;
```

看到 `rising_edge(clk)` / `falling_edge(clk)`，就基本意味着：**这里在推寄存器（触发器）**。

#### （2）带复位

```vhdl
process(clk)
begin
  if rising_edge(clk) then
    if rst = '1' then
      q <= '0';
    else
      q <= d;
    end if;
  end if;
end process;
```

#### （3）状态机的 state —— 典型触发器

```vhdl
type state_t is (S_IDLE, S_RUN, S_DONE);
signal state : state_t := S_IDLE;

process(clk)
begin
  if rising_edge(clk) then
    if rst = '1' then
      state <= S_IDLE;
    else
      case state is
        when S_IDLE =>
          if start = '1' then
            state <= S_RUN;
          end if;
        when S_RUN =>
          if finish = '1' then
            state <= S_DONE;
          end if;
        when S_DONE =>
          state <= S_IDLE;
      end case;
    end if;
  end if;
end process;
```

拆解：

- `state` 本身：触发器记住“现在在哪个状态”  
- `case state ...` 里组合判断下一状态/输出：LUT  
- 若有计数配合：再加进位链

#### （4）把组合结果“打一拍”（流水/对齐）

```vhdl
-- 组合
sum_comb <= std_logic_vector(unsigned(a) + unsigned(b));

-- 打拍存住
process(clk)
begin
  if rising_edge(clk) then
    sum_r <= sum_comb;  -- 触发器
  end if;
end process;
```

这非常常见：LUT/加法先算出组合结果，触发器在时钟沿锁存。

#### （5）移位寄存器（一串触发器）

```vhdl
process(clk)
begin
  if rising_edge(clk) then
    shreg <= shreg(6 downto 0) & din;  -- 8 级移位
  end if;
end process;
```

每位都是触发器；也可被综合成更高效的移位结构，但概念上就是一串记忆单元。

---

## 4. 三块如何在一段真实代码里同时出现

看这段“迷你采集控制”：

```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mini_ctrl is
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;
    start  : in  std_logic;
    din    : in  std_logic_vector(7 downto 0);
    dout   : out std_logic_vector(7 downto 0);
    done   : out std_logic
  );
end entity;

architecture rtl of mini_ctrl is
  type state_t is (S_IDLE, S_ACC, S_DONE);
  signal state : state_t := S_IDLE;
  signal cnt   : unsigned(3 downto 0) := (others => '0');
  signal acc   : unsigned(7 downto 0) := (others => '0');
  signal done_i: std_logic := '0';
begin

  -- 输出可再经组合逻辑整理（LUT）
  done <= done_i;
  dout <= std_logic_vector(acc);

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state  <= S_IDLE;          -- 触发器
        cnt    <= (others => '0'); -- 触发器
        acc    <= (others => '0'); -- 触发器
        done_i <= '0';             -- 触发器
      else
        case state is              -- 状态译码：LUT
          when S_IDLE =>
            done_i <= '0';
            if start = '1' then    -- 条件：LUT
              acc   <= unsigned(din);
              cnt   <= (others => '0');
              state <= S_ACC;
            end if;

          when S_ACC =>
            acc <= acc + unsigned(din); -- 加法/进位 + 触发器锁存
            cnt <= cnt + 1;             -- 计数进位 + 触发器
            if cnt = 7 then             -- 比较：LUT
              state  <= S_DONE;
              done_i <= '1';
            end if;

          when S_DONE =>
            state <= S_IDLE;

        end case;
      end if;
    end if;
  end process;

end architecture;
```

对照表：

| 代码片段 | 主要进 ALM 的哪部分 |
|----------|---------------------|
| `case state is` / `if start` / `if cnt=7` | **LUT** |
| `acc + ...` / `cnt + 1` | **加法/进位结构** |
| `state/cnt/acc/done_i <= ...` 在 `rising_edge` 里 | **触发器** |
| `done <= done_i` 这类直连/简单赋值 | 可能几乎不占，或极简 LUT |

---

## 5. 一张“写法 → 硬件”速查表

| 你在 VHDL 里看到 | 多半在推什么硬件 |
|------------------|------------------|
| `and/or/xor/not` | LUT |
| `when...else` / `with...select` | LUT（MUX） |
| 无时钟的 `process(a,b,...)` | LUT（组合） |
| `a + b` / `a - b` | 加法/进位（+ 可能的 LUT 收尾） |
| `cnt <= cnt + 1` | 进位链 + 触发器 |
| `rising_edge(clk)` 里的信号赋值 | 触发器 |
| `type state_t is ...; signal state` | 触发器（状态）+ LUT（转移条件） |
| `a * b`（较宽） | 更常进 **DSP**，不是 ALM 主角 |
| `信号数组深度很大` 当 RAM 用 | 更常进 **M10K/MLAB**，不是一堆触发器（若写法正确） |

---

## 6. 新手最容易混的 3 件事

### 6.1 “有 if 就是触发器吗？”

不是。  
关键看有没有 **时钟边沿**。

```vhdl
-- 组合 if：LUT
y <= a when sel='1' else b;

-- 时序 if：触发器
if rising_edge(clk) then
  y <= a;
end if;
```

### 6.2 “加法是不是只占进位链，不占触发器？”

不一定。  
- 只写并发 `sum <= a + b;`：主要是组合加法（进位链/LUT），**不自动变寄存器**  
- 写在 `rising_edge` 里：`sum <= a + b;`：加法结果被触发器锁存

### 6.3 “一个 ALM 只能干一件事吗？”

不是。  
一个 ALM 常可同时提供一部分 LUT 能力 + 触发器；综合器会打包塞紧。  
你不用手工分配，只要写出清晰的 RTL。

---

## 7. 用一句话收束

- **LUT**：算“现在该是什么”（组合）  
- **进位/加法结构**：又快又好地做加减计数  
- **触发器**：在时钟沿把结果“记住”，形成状态与节拍  

对应到代码阅读口诀：

```text
看到逻辑符 / when-else / 组合process     → 想 LUT
看到 +  -  计数                           → 想进位链
看到 rising_edge(clk) 里的信号赋值       → 想触发器
```

---

## 8. 建议你马上做的练习（10 分钟）

打开你工程任意控制模块（如通信或 ADC 控制），用荧光笔规则标：

1. 所有 `rising_edge` 赋值 → 标“触发器”  
2. 所有 `+`/`-`/计数 → 标“进位”  
3. 其余 `if/case/and/or/比较` → 标“LUT”

标完一遍，ALM 三件套就会从“概念”变成“看见代码就能对上硬件”。

如果你愿意，把某段 `TX_Comm.vhd` 或顶层里你看不懂的 30 行贴出来，我可以按行帮你标：每一句主要落在 LUT、进位，还是触发器。
