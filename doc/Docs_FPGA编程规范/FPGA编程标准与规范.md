# FPGA 编程标准与规范

| 项目 | 内容 |
|------|------|
| 适用范围 | 公司 FPGA 项目（Verilog / VHDL） |
| 版本 | Rev 1.5 |
| 日期 | 2026-09-01 |

---

## 目录

1. [总则](#1-总则)
2. [工程目录结构](#2-工程目录结构)
3. [文件命名](#3-文件命名)
4. [文件头模板](#4-文件头模板)
5. [命名规范](#5-命名规范)
6. [Port 声明风格](#6-port-声明风格)
7. [代码分区与注释](#7-代码分区与注释)
8. [时序与组合逻辑](#8-时序与组合逻辑)
9. [状态机编码](#9-状态机编码)
10. [模块实例化](#10-模块实例化)
11. [编译宏与条件编译](#11-编译宏与条件编译)
12. [时钟域交叉与长链路打拍](#12-时钟域交叉cdc与长链路打拍)
13. [仿真规范](#13-仿真规范)
14. [约束文件规范](#14-约束文件规范)
15. [第三方与移植代码](#15-第三方与移植代码处理)
16. [Verilog ↔ VHDL 对照](#16-verilog--vhdl-对照速查)
17. [VHDL-2008 语法强制要求](#17-vhdl-2008-语法强制要求)
18. [代码审查检查清单](#18-代码审查检查清单)
19. [修订记录](#19-修订记录)

---

## 1. 总则

### 1.1 设计目标

- 代码应**可读、可综合、可仿真、可维护**。
- 同一工程内命名、格式、目录结构保持统一。
- 新代码必须遵循本规范。
- 第三方或移植代码可保留原风格，但**接口 Wrapper 必须对齐本规范**。

### 1.2 语言选用

| 场景 | 推荐语言 | 说明 |
|------|----------|------|
| 用户 RTL | Verilog-2001（`.v`）或 **VHDL-2008**（`.vhd`） | 按工程约定二选一，**同一工程内不混用** |
| Testbench | Verilog / SystemVerilog / VHDL-2008 | 放在 `Sim/`，与 RTL 分离 |
| IP 核生成物 | 工具自动生成 | 不手工修改，不纳入本规范 |

> **VHDL 强制标准**：新代码统一按 **VHDL-2008** 编写；工程综合 / 仿真工具须开启 VHDL-2008（详见 [§17](#17-vhdl-2008-语法强制要求)）。禁止按 VHDL-87 / 93 旧习惯新写代码。

### 1.3 禁止事项

下列条目为硬性约束，审查不通过不得合入。

#### 代码与风格

| 禁止项 | 说明 |
|--------|------|
| RTL 中使用延时 | 禁止 `#delay`、VHDL `after`；仅 TB 可用 |
| Latch | 组合逻辑须完整 `case` / `if-else`，含 `default` / `else` |
| 多驱动 | 禁止多驱动同一信号（含 `inout` 滥用） |
| 时序阻塞赋值 | Verilog 时序逻辑禁止阻塞 `=`；VHDL 时序用 `SIGNAL <=`，勿用 VARIABLE 冒充对外寄存器 |
| 无注释魔数 | 常量须命名并注释物理含义 |
| 缩进混用 | 禁止 Tab 与空格混用，统一 **4 空格** |
| 组合环路 | 禁止 combinational loop |
| 不完整敏感列表 | Verilog 用 `always @(*)`；VHDL-2008 组合逻辑用 `process(all)`，禁止漏列敏感表 |

#### 时钟与复位

| 禁止项 | 说明 |
|--------|------|
| 门控时钟 | 用时钟使能（`ce` / `iClkEn`）代替对时钟线做与或 |
| 分频当全局时钟 | 计数器分频时钟须走全局时钟资源，或改为使能脉冲 |
| 异步释放未同步 | 须**异步复位、同步释放** |
| 复位路径重组合 | 禁止在复位释放路径上挂重组合逻辑 |

#### 跨域与接口

| 禁止项 | 说明 |
|--------|------|
| 跨域直采多 bit | 须 FIFO / 握手 / 灰码 |
| 片内滥用三态 | 三态仅用于芯片 IO；片内用 mux |
| 顶层端口无约束 | 管脚与电平标准必须完整 |

#### 可综合性

| 禁止项 | 说明 |
|--------|------|
| 仿真专用类型进 RTL | 禁止可综合 RTL 使用 `real` / `time` / 文件 I/O / 打印语句 |
| 依赖未定义行为 | 禁止依赖竞态、`X`/`U` 或“碰巧正确” |
| VHDL 旧库 / 旧写法 | 禁止 `std_logic_arith` / `std_logic_unsigned` / `std_logic_signed`；禁止对 `std_logic_vector` 直接做算术；统一 `numeric_std`（算术用 `unsigned` / `signed`） |
| VHDL 旧例化方式 | 新代码禁止仅靠 COMPONENT 声明例化；优先**直接实体例化**（`entity work.xxx`） |
| VHDL 旧敏感表 | 组合 Process 禁止手写不完整敏感表；须用 `process(all)` |

#### 浮点数

| 禁止项 | 说明 |
|--------|------|
| RTL 直接浮点类型 | 禁止 `real` / `float` / `double` 及浮点四则运算 |
| TB 算法照搬 RTL | `real` 验证通过后须改为定点或浮点 IP |
| 隐式混算 | 浮点与定点/整数须显式转换，并注释 Q 格式或 IEEE 754 位宽 |
| 手写类浮点长组合 | 除法/开方/三角函数须用 IP、查表、CORDIC 或定点迭代，并流水化 |

**确需浮点时的强制要求：**

1. 统一使用**浮点运算 IP**，注明：单/双精度、流水线级数、延迟拍数、舍入模式。
2. 接口用 `std_logic_vector` / `logic` 承载编码位，**不得**使用 `real` 端口。
3. 控制、采样、保护、PID 等实时路径**优先定点**（`signed` + Q 格式）；浮点仅用于非实时、低带宽或软件协同场景。
4. 比较、判零、溢出按 IP 文档处理 NaN / Inf / denormal，禁止默认“等于 0”。
5. 仿真可用 `real` 作黄金模型，但与 RTL 接口须通过位向量对齐，RTL 内不得混用。

### 1.4 注意事项（强烈建议）

#### 时钟与时序

- 优先用 PLL / MMCM / IP 产生时钟；模块间优先同频 + 时钟使能，少造额外时钟域。
- 高扇出网络（复位、使能、清零）评估是否需打拍或缓冲复制。
- 长组合链路、跨模块级联中间**打一拍**（见 [§12.2](#122-长时钟--信号链路打拍)）。
- 关键路径优先寄存器输出（Moore），减少毛刺传到异步输入或 IO。
- 同一路径慎混用上升沿 / 下降沿；双沿采样须书面说明。

#### 复位与上电

- 复位极性在工程内统一；外部低有效复位进入 FPGA 后同步到各时钟域。
- 寄存器初值可用声明初值或复位赋值，但仿真与综合行为须一致。
- 有 PLL 时，业务逻辑应在 `locked` 有效并延时释放复位后再工作。

#### CDC 与亚稳态

- 单 bit 跨域至少两级同步器；同步器输出勿再做复杂组合后跨回源域。
- 控制脉冲跨域用握手或脉冲展宽，勿假设单周期脉冲在另一域仍有效。
- 灰码跨域时，位宽与读写指针约束须完整。

#### 资源与结构

- 大数组 / 延迟线优先推断或例化 BRAM / FIFO。
- 乘加、DSP 运算注意流水线级数，与厂商原语 / IP 对齐。
- `case` 分支尽量互斥、完备；并行 `if` 注意优先级综合结果。
- 避免在 `always` / `process` 中写无法综合的死循环。

#### IO 与约束

- 异步输入（按键、外部中断等）必须同步后再进状态机。
- 输出到异步外设的控制信号建议寄存器输出，避免毛刺。
- 时序约束覆盖所有真实时钟；`set_false_path` / `set_multicycle_path` 慎用，使用须注释理由。
- 管脚、电平、上下拉与原理图一致，变更时同步改约束。

#### 仿真与可调试性

- RTL 与 TB 分层；TB 可用 `#delay`，不可反向污染可综合代码。
- 关键用例覆盖：复位、边界计数、满/空、跨域、故障注入。
- 片上调试统一 probe 命名，避免随意 `keep` 影响布局布线。

#### 可维护性

- 位宽变更时同步改参数、常量、端口与实例化，防止隐式截断。
- 有符号 / 无符号运算显式标明，避免无意零扩展 / 符号扩展。
- 第三方 IP 用 Wrapper 隔离；内部命名可不改，接口必须符合本规范。

---

## 2. 工程目录结构

```text
<ProjectName>/
├── Dev/<ProjectName>/          # IDE 工程（Vivado / Quartus 等）
├── Doc/                         # 方案文档、原理图
├── Sim/                         # 模块级仿真
│   └── <ModuleName>Tb/
│       ├── Bench/               # Testbench 源码
│       ├── Script/              # 仿真脚本
│       ├── DataFile/            # 激励数据
│       ├── Macro/               # 仿真宏定义
│       └── Model/               # 行为模型
└── Src/
    ├── Core/                    # IP 核（PLL、FIFO、RAM 等）
    ├── Ucf/                     # 约束（XDC / SDC 等）
    └── UserCode/                # 用户手写 RTL
        ├── <ProjectName>.v(hd)  # 顶层
        ├── FunctionDefine.h     # 全局宏（Verilog 工程）
        └── <Feature>Core/       # 功能模块目录
```

**组织原则**

1. 每个功能域一个目录，目录名与模块名一致，通常以 `Core` 结尾（如 `ProtectCore/`、`FilterCore/`）。
2. IP 与用户逻辑分离：`Src/Core/` 为工具生成，`Src/UserCode/` 为手写。
3. 仿真与 RTL 分离：`Sim/` 通过相对路径引用源码。
4. 约束集中管理：`<Top>_Pins.*` + `<Top>_Timing.*`。

---

## 3. 文件命名

| 类型 | 规则 | 示例 |
|------|------|------|
| 顶层 | 与工程名一致 | `<ProjectName>.v` / `<ProjectName>.vhd` |
| 功能模块（Verilog） | PascalCase，与 module 名一致 | `ProtectCore.v`、`FilterCore.v` |
| 功能模块（VHDL） | snake_case，与 entity 名一致 | `uart_send.vhd`、`filter_core.vhd` |
| 功能目录 | PascalCase + `Core` | `ProtectCore/`、`UartCore/` |
| 全局头文件 | PascalCase + `.h` | `FunctionDefine.h` |
| Testbench | `<Module>Tb.v` / `<module>_tb.vhd` | `ProtectCoreTb.v` |
| 约束 | `<Top>_<Type>.xdc` / `.sdc` | `<Top>_Pins.xdc` |
| 扩展名 | 统一小写 | 禁止 `.V` 等大写混用 |

---

## 4. 文件头模板

### 4.1 Verilog

```verilog
//------------------------------------------------------------------------------
//Project Name      :   <ProjectName>
//Moudle Name       :   <ModuleName>.v
//Original Author   :   <Author>
//Creation Date     :   YYYY.MM.DD
/*Description       :   <模块功能简述>
*/
//------------------------------------------------------------------------------
//Version           :   Rev 0.1
//modifier          :
//Modify Date       :
/*Modify Record     :
*/
//------------------------------------------------------------------------------
```

> **说明**：`Moudle` 为历史固定拼写，全项目保持一致，不改为 `Module`。

### 4.2 VHDL

字段与 Verilog 一致。VHDL 仅支持 `--` 行注释，写法如下：

```vhdl
--------------------------------------------------------------------------------
--Project Name      :   <ProjectName>
--Moudle Name       :   <ModuleName>.vhd
--Original Author   :   <Author>
--Creation Date     :   YYYY.MM.DD
--Description       :   <模块功能简述>
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--modifier          :
--Modify Date       :
--Modify Record     :
--------------------------------------------------------------------------------
```

### 4.3 约束文件

结构与 Verilog 相同；XDC 用 `##`，SDC 用 `#`：

```tcl
##------------------------------------------------------------------------------
##Project Name      :   <ProjectName>
##Moudle Name       :   <Top>_Pins.xdc
##Original Author   :   <Author>
##Creation Date     :   YYYY.MM.DD
##Description       :   管脚分配约束
##------------------------------------------------------------------------------
```

---

## 5. 命名规范

### 5.1 信号前缀

采用匈牙利前缀，Verilog / VHDL 语义对应如下：

| 前缀 | 含义 | Verilog | VHDL |
|------|------|---------|------|
| `i` / `i_` | 输入端口 | `iSysClk` | `i_sys_clk` |
| `o` / `o_` | 输出端口 | `oSysLed` | `o_uart_txd` |
| `io` / `io_` | 双向端口 | `ioEthPhyMdio` | `io_swd_data` |
| `w` / `w_` | 内部组合 / 连线 | `wPllLocked` | `w_en_flag` |
| `r` / `r_` | 内部时序寄存器 | `rCurrentState` | `r_tx_flag` |
| `v_` | VHDL VARIABLE | — | `v_byte`、`v_idx` |

- **Verilog**：前缀后直接接 PascalCase（`iSysClk`）。
- **VHDL**：前缀后接下划线 + snake_case（`i_sys_clk`）。

### 5.2 VHDL 对象类型与前缀

VHDL 没有 `wire` / `reg`。`r_` / `w_` 仅为命名约定，必须与综合行为一致。

| 关键字 | 作用域 | 赋值 | 典型用途 | 推荐前缀 |
|--------|--------|------|----------|----------|
| PORT | Entity 接口 | 外部驱动 | `i_sys_clk` | `i_` / `o_` / `io_` |
| GENERIC | Entity 参数 | 例化绑定 | `CLK_FREQ` | 全大写 |
| CONSTANT | Architecture / Package | 不可改 | `FRAME_LEN` | 全大写 |
| SIGNAL（时序） | Architecture | `<=` | 时钟沿更新 | `r_` |
| SIGNAL（组合） | Architecture | `<=` | 并发 / 组合 | `w_` |
| VARIABLE | Process / Function | `:=`（立即） | 循环、中间值 | `v_` |
| TYPE / SUBTYPE | 类型定义 | — | `state_type` | 类型名大写 |

**易错点**

1. VARIABLE 不用 `r_` / `w_`，统一用 `v_`。
2. 在时钟 Process 内赋值的 SIGNAL 必须用 `r_`，不能叫 `w_`。
3. CONSTANT / GENERIC 不用 `r_` / `w_`，用全大写。
4. `r_` = 时钟沿更新，`w_` = 组合 / 并发赋值。

### 5.3 GENERIC 与 CONSTANT

语义必须区分；命名可共用全大写。

| 对比项 | GENERIC | CONSTANT |
|--------|---------|----------|
| 声明位置 | ENTITY 接口 | ARCHITECTURE / PACKAGE 内部 |
| 上层可否覆盖 | 能（`GENERIC MAP`） | 不能 |
| 作用 | 可配置参数 | 固定或派生常量 |
| Verilog 对应 | `parameter` | `localparam` |

```vhdl
-- ENTITY：外部可配置
generic (
    CLK_FREQ : positive := 50_000_000;
    UART_BPS : positive := 2_000_000
);

-- ARCHITECTURE：由 GENERIC 派生
constant BPS_CNT : positive := CLK_FREQ / UART_BPS;  -- 派生自 CLK_FREQ, UART_BPS
```
| 对象 | 命名 | 示例 |
|------|------|------|
| GENERIC | 全大写 | `CLK_FREQ`、`PARAM_COUNT` |
| CONSTANT | 全大写 | `FRAME_LEN`、`BPS_CNT` |

派生关系用注释标明来源。本地常量若与子模块 GENERIC 易混，可加模块前缀区分。

### 5.4 模块 / Entity 命名

| 语言 | 风格 | 示例 |
|------|------|------|
| Verilog module | PascalCase | `ProtectCore`、`UartSend` |
| VHDL entity | snake_case | `protect_core`、`uart_send` |
| 功能域后缀 | `Core` | `SysCore`、`FilterCore`、`UartCore` |

### 5.5 实例化命名

```verilog
SysPllCore      U_SysPllCore   ( ... );
FilterCore      U_FilterCoreA  ( ... );   // A/B 双路对称
SignedDivision  U_Division_Ref ( ... );
```

```vhdl
U_UART_SEND : entity work.uart_send
    generic map (
        CLK_FREQ => CLK_FREQ
    )
    port map (
        i_sys_clk      => i_sys_clk,
        i_sys_rst      => i_sys_rst,
        i_uart_en      => w_uart_en,
        i_uart_din     => w_uart_din,
        o_uart_tx_busy => w_uart_tx_busy,
        o_uart_txd     => o_uart_txd
    );
```
- 实例名以 `U_` 为前缀。
- 双路对称设计用 `A` / `B` 后缀区分。

### 5.6 时钟与节拍信号

| 信号 | 含义 |
|------|------|
| `iSysClk` / `i_sys_clk` | 模块工作时钟 |
| `iSysClkIn` | 外部晶振输入 |
| `wSysClk1` ~ `wSysClkN` | PLL 输出时钟网 |
| `iCnt1Us` / `oDelay1Us` | 1 µs 脉冲（统一时基模块产生） |
| `iCnt1Ms` / `oDelay1Ms` | 1 ms 脉冲 |
| `iSysClk1SPulse` | 1 s 脉冲 |

> **要求**：禁止各模块自行做 µs / ms 分频，统一使用公共时基模块的节拍信号。

### 5.7 复位信号

| 信号 | 极性 | 含义 |
|------|------|------|
| `iSysRst` / `i_sys_rst` | 高有效 | 同步 / 异步复位输入 |
| `oRstP` | 高有效 | 正逻辑复位输出（为 1 表示保持复位） |
| `oRstN` | 低有效 | 负逻辑复位输出 |
| `iPllLocked` | — | PLL 锁定，参与异步复位同步释放 |
| `iRstP` | 高有效 | 正逻辑复位输入 |

**推荐复位策略**

1. PLL 未锁定时保持复位。
2. 锁定后按 `iCnt1Us` 计数延时再释放（延时按工程定义）。
3. 仿真通过 `SIMULATION_EN` 缩短复位时间。

```verilog
`ifdef SIMULATION_EN
    localparam RESET_TIME = 20'd50;
`else
    localparam RESET_TIME = 20'd50000;   // 例：50 ms @ 1 µs tick
`endif
```

### 5.8 有符号量

```verilog
input  wire signed [15:0] iSampleData;
localparam signed [15:0] SAMPLE_MAX = 16'sd3360;
reg signed [31:0] rOffset;
```

```vhdl
i_sample : in signed(15 downto 0);
constant SAMPLE_MAX : signed(15 downto 0) := to_signed(3360, 16);
```
### 5.9 状态机命名

- 状态常量：大写 + 下划线（`IDLE`、`BUSY`、`DONE`）。
- 状态寄存器：`rCurrentState` / `rNextState`（Verilog），或 `r_state` / `r_next_state`（VHDL）。
- VHDL-2008 推荐用枚举类型 `type t_state is (...)`（见 [§17.5](#175-状态机vhdl-2008)）。

### 5.10 参数与常量

```verilog
parameter CLK_FREQ  = 100;             // 单位 MHz（Verilog 惯例）
parameter TIMEOUT_S = 5;               // 单位 s
localparam COUNT_1MS = 10'd1000;
localparam signed [15:0] SAMPLE_MAX = 16'sd3360;
```

```vhdl
generic (
    CLK_FREQ : positive := 50_000_000;  -- 单位 Hz（VHDL 惯例）
    UART_BPS : positive := 2_000_000
);
constant BPS_CNT : positive := CLK_FREQ / UART_BPS;
```
> **注意**：Verilog 中 `CLK_FREQ` 习惯以 **MHz** 为单位；VHDL 中习惯以 **Hz** 为单位。注释必须写明单位。

---

## 6. Port 声明风格

### 6.1 Verilog

```verilog
module ProtectCore#(
    parameter CLK_FREQ  = 8'd100,   // MHz
    parameter TIMEOUT_S = 10'd5     // s
)(
    //Global Clock
    input   wire                    iSysClk,
    input   wire                    iRstP,
    input   wire                    iSysClk1SPulse,

    //User Interface
    input   wire signed [15:0]      iSampleData,   // 采样数据
    output  wire                    oFault,
    output  wire        [15:0]      oFaultInfo
);
```

**规则**

1. `#(` 参数块紧跟 module 名。
2. Port 按功能分组，组间空行，组首用英文注释（如 `//Global Clock`）。
3. 每端口一行，类型 / 位宽 / 名称列对齐，行末逗号。
4. 新代码显式写 `input wire` / `output wire`。
5. 业务注释用中文；管脚注释可附硬件位号。

### 6.2 VHDL（VHDL-2008）

```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_send is
    generic (
        CLK_FREQ : positive := 50_000_000;
        UART_BPS : positive := 2_000_000
    );
    port (
        i_sys_clk      : in  std_logic;
        i_sys_rst      : in  std_logic;
        i_uart_en      : in  std_logic;
        i_uart_din     : in  std_logic_vector(7 downto 0);
        o_uart_tx_busy : out std_logic;
        o_uart_txd     : out std_logic
    );
end entity uart_send;

architecture rtl of uart_send is
    constant BPS_CNT : positive := CLK_FREQ / UART_BPS;
    signal r_tx_flag : std_logic := '0';
begin
    -- ...
end architecture rtl;
```

**规则**

1. `library` / `use` 置于文件头之后；仅允许 `ieee.std_logic_1164` 与 `ieee.numeric_std`（必要时可加 `numeric_std_unsigned`，仍禁止 Synopsys 旧包）。
2. 关键字推荐**小写**；标识符按本规范前缀命名。
3. Port 方向对齐，每行一个端口，行末分号。
4. Architecture 统一命名为 `rtl`；推荐写全 `end entity` / `end architecture`。
5. 对外端口默认 `std_logic` / `std_logic_vector`；算术内部用 `unsigned` / `signed`，边界处显式转换。
6. VHDL-2008 允许读取 `out` 端口；一般仍推荐内部 `r_` / `w_` 再驱动输出，结构更清晰。

---

## 7. 代码分区与注释

### 7.1 Verilog 分区标记

```verilog
//-------------------------------Code Start Here--------------------------------
//******************************************************************************
// 内部参数定义
localparam COUNT_1S = 10'd1000;
//******************************************************************************
```

### 7.2 注释语言

| 位置 | 语言 |
|------|------|
| 文件头标签 | 英文（Verilog / VHDL 统一字段） |
| 业务逻辑说明 | 中文 |
| Port 分组 | 英文 |
| 修改记录 | 中文 |

### 7.3 VHDL 进程分区

```vhdl
    -- ===================== i_uart_en 同步打拍 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_uart_en_d0 <= '0';
            r_uart_en_d1 <= '0';
        elsif rising_edge(i_sys_clk) then
            r_uart_en_d0 <= i_uart_en;
            r_uart_en_d1 <= r_uart_en_d0;
        end if;
    end process;
```

---

## 8. 时序与组合逻辑

### 8.1 赋值规则

| 场景 | Verilog | VHDL |
|------|---------|------|
| 时序逻辑 | 非阻塞 `<=` | `SIGNAL <=` |
| 组合逻辑 | 阻塞 `=` 或 `assign` | 并发 `SIGNAL <=` 或组合 Process |
| VARIABLE | — | `:=`（立即生效） |

### 8.2 Always / Process 风格

```verilog
// 时序：推荐带复位
always @(posedge iSysClk or posedge iSysRst) begin
    if (iSysRst)
        rCurrentState <= IDLE;
    else
        rCurrentState <= rNextState;
end

// 组合：次态逻辑
always @(*) begin
    case (rCurrentState)
        IDLE:    rNextState = BUSY;
        BUSY:    rNextState = DONE;
        default: rNextState = IDLE;
    endcase
end
```

```vhdl
-- 时序：异步复位、同步释放风格示例
process (i_sys_clk, i_sys_rst)
begin
    if i_sys_rst = '1' then
        r_tx_flag <= '0';
    elsif rising_edge(i_sys_clk) then
        r_tx_flag <= '1';
    end if;
end process;

-- 组合：VHDL-2008 推荐 process(all)，避免漏敏感表
process (all)
begin
    case r_state is
        when IDLE  => w_next_state <= BUSY;
        when BUSY  => w_next_state <= DONE;
        when others => w_next_state <= IDLE;
    end case;
end process;
```

### 8.3 SIGNAL 与 VARIABLE 选型（VHDL）

| 场景 | 选用 |
|------|------|
| 模块内连线、跨 Process 通信 | `SIGNAL` |
| 时钟沿更新的寄存器 | `SIGNAL` + `r_` |
| 组合逻辑输出 | `SIGNAL` + `w_` |
| Function 内中间计算 | `VARIABLE` + `v_` |
| Process 内 for 循环计数 | `VARIABLE` + `v_` |
| 同一周期内读旧写新并立即使用 | `VARIABLE`（`SIGNAL` 做不到） |

### 8.4 初始化

```verilog
reg [9:0] rCount        = 10'd0;
reg [1:0] rCurrentState = 2'd0;
```

```vhdl
signal r_clk_cnt : unsigned(15 downto 0) := (others => '0');
signal r_tx_flag : std_logic := '0';
```

### 8.5 位宽与字面量

**Verilog**

- 显式标注位宽：`rRstCnt[7:0] <= 8'd0;`
- 全位宽赋值：`'d0`、`1'b0`、`8'hFF`、`16'sd3360`
- 位宽计算：`$clog2()` 或自定义 `clogb2()` function

**VHDL-2008**

- 计数 / 算术优先 `unsigned` / `signed`，端口边界再转 `std_logic_vector`
- 字面量示例：`x"FF"`、`to_unsigned(100, 8)`、`to_signed(-5, 16)`、`(others => '0')`
- 位宽计算：`integer(ceil(log2(real(N))))` 仅用于常量推导；或预计算后写入 `constant`
- 禁止对 `std_logic_vector` 直接 `+` / `-` / `*`（须先转为 `unsigned` / `signed`）

---

## 9. 状态机编码

### 9.1 推荐风格

二进制编码 + 双 / 三 always 块：

```verilog
localparam IDLE = 2'b00;
localparam BUSY = 2'b01;
localparam DONE = 2'b10;

reg [1:0] rCurrentState = 2'd0;
reg [1:0] rNextState    = 2'd0;

// 1) 状态寄存器（时序）
// 2) 次态逻辑（组合 always @(*)）
// 3) 输出逻辑（时序，按 rCurrentState 分支）
```

### 9.2 规范要求

1. 必须包含 `default` 分支，防止生成 latch。
2. 状态数 ≤ 4 用二进制；> 8 且速度要求高时可用 One-Hot（须注释说明）。
3. 输出建议寄存器化（Moore 型），减少毛刺。

---

## 10. 模块实例化

### 10.1 Verilog

```verilog
ProtectCore #(
    .CLK_FREQ  (100),
    .TIMEOUT_S (5)
) U_ProtectCore (
    //Global Clock
    .iSysClk        (wSysClk1),
    .iRstP          (wRstP),
    .iSysClk1SPulse (wDelay1S),
    //User Interface
    .iSampleData    (wSampleData),
    .oFault         (wFault)
);
```

**规则**

1. Port map 按功能分组，与模块声明分组一致。
2. 端口名与连线名列对齐。
3. 参数映射使用 `.ParamName (Value)`，显式写出。

### 10.2 VHDL-2008（直接实体例化）

```vhdl
U_PROTECT_CORE : entity work.protect_core
    generic map (
        CLK_FREQ  => 100_000_000,
        TIMEOUT_S => 5
    )
    port map (
        -- Global Clock
        i_sys_clk         => w_sys_clk1,
        i_rst_p           => w_rst_p,
        i_sys_clk_1s_pulse=> w_delay_1s,
        -- User Interface
        i_sample_data     => w_sample_data,
        o_fault           => w_fault
    );
```

**规则**

1. 新代码优先 `entity work.<name>` **直接例化**，无需先写 `component`。
2. 仅对接无法直接例化的第三方 IP / 加密网表时，才允许 `component`。
3. `generic map` / `port map` 按功能分组、列对齐，禁止位置关联。

---

## 11. 编译宏与条件编译

### 11.1 全局宏文件

```verilog
//`define BOOTMODE
```

### 11.2 常用宏

| 宏 | 用途 |
|----|------|
| `SIMULATION_EN` | 仿真时缩短复位时间；编译加 `+define+SIMULATION_EN` |
| `BOOTMODE` | 启动模式分支 |
| `SIM` | 特定模块仿真分支 |

### 11.3 Include

```verilog
`include "FunctionDefine.h"
```

---

## 12. 时钟域交叉（CDC）与长链路打拍

### 12.1 CDC 基本要求

1. 单 bit 跨域：至少 **2 级同步器**。
2. 多 bit 跨域：使用 FIFO 或握手协议，禁止直接采样。
3. PLL 锁定信号须同步后再参与复位逻辑。
4. 每个时钟域独立实例化时基模块与复位模块。

### 12.2 长时钟 / 信号链路打拍

组合逻辑或扇出链路过长时，中间必须**打一拍**（插入寄存器），避免关键路径违例：

1. 多级组合（比较、加减乘除、宽总线译码等）串联时，中间级用 `r_` 打断。
2. 跨模块级联、高扇出控制 / 数据信号，在接收端或中间节点打拍后再使用。
3. 打拍后评估对握手、状态机、保护响应时间的影响，必要时调整下游逻辑。
4. 审查结合时序报告（WNS / 关键路径级数），对长路径强制补寄存器。

---

## 13. 仿真规范

### 13.1 目录与命名

```text
Sim/<ModuleName>Tb/
├── Bench/<ModuleName>Tb.v
└── Script/Do.tcl
```

### 13.2 Testbench 模板要点

```verilog
`timescale 1ns/1ns

module ModuleNameTb;

    parameter PERIOD_SYS = 10;
    reg rSysClk = 1'b0;

    always #(PERIOD_SYS/2) rSysClk = ~rSysClk;

    ModuleName dut ( ... );

endmodule
```

### 13.3 仿真编译

1. Verilog：必须定义 `+define+SIMULATION_EN`（或工程约定的等效仿真宏）。
2. VHDL：仿真库与综合库均设为 VHDL-2008；TB 不得污染可综合代码。
3. TB 信号命名建议与 RTL 对齐。
4. 平台级仿真可用 SystemVerilog TB。

---

## 14. 约束文件规范

### 14.1 文件组织

| 文件 | 内容 |
|------|------|
| `<Top>_Pins.xdc` / `.sdc` | 管脚、电平标准、上下拉 |
| `<Top>_Timing.xdc` / `.sdc` | 时钟定义、时序例外 |
| IP 核目录下约束 | IP 自带，不手工修改 |

### 14.2 管脚约束示例（XDC）

```tcl
##------------------------------------------------------------------------------
#Global
set_property PACKAGE_PIN <PIN> [get_ports iSysClkIn]
set_property IOSTANDARD LVCMOS33 [get_ports iSysClkIn]
set_property PULLUP true [get_ports oUartTxd]
```

### 14.3 时序约束示例（XDC）

```tcl
create_clock -period 20.000 -name iSysClkIn -waveform {0.000 10.000} \
    [get_ports iSysClkIn]
```

**规则**

1. Port 名与 RTL 顶层严格一致。
2. 按功能分组，与 RTL Port 分组对应。
3. 每个 port 必须指定电平标准（如 `IOSTANDARD`）。

---

## 15. 第三方与移植代码处理

| 来源 | 命名风格 | 示例 |
|------|----------|------|
| 自有 Verilog | PascalCase + `i/o/r/w` | `ProtectCore.v` |
| 第三方代码 | 允许保留原风格 | `udp_tx.v` |
| 自有 VHDL | snake_case + `i_/o_/r_/w_/v_`（VHDL-2008） | `uart_send.vhd` |

**规范**

1. 第三方模块内部不强制改名。
2. 新建 Wrapper 层必须使用项目前缀规范，且 Wrapper 本身按 VHDL-2008 编写。
3. Verilog → VHDL 移植时：统一 snake_case + 下划线前缀，并改为 VHDL-2008 写法（`numeric_std`、`process(all)`、直接例化等）。

---

## 16. Verilog ↔ VHDL 对照速查

| 项目 | Verilog | VHDL-2008 |
|------|---------|-----------|
| 语言版本 | Verilog-2001 | **VHDL-2008**（强制） |
| 模块名 | `ProtectCore` | `protect_core` |
| 时钟输入 | `iSysClk` | `i_sys_clk` |
| 复位 | `iSysRst`（高有效） | `i_sys_rst`（高有效） |
| 内部寄存器 | `rCurrentState` | `r_current_state` |
| 内部连线 | `wPllLocked` | `w_pll_locked` |
| 局部变量 | — | `v_byte`（variable） |
| 可配置参数 | `parameter CLK_FREQ` | `generic CLK_FREQ` |
| 内部常量 | `localparam FRAME_LEN` | `constant FRAME_LEN` |
| 架构名 | — | `rtl` |
| 时钟频率参数 | `CLK_FREQ = 100`（MHz） | `CLK_FREQ = 50_000_000`（Hz） |
| 组合敏感表 | `always @(*)` | `process(all)` |
| 边沿检测 | `posedge clk` | `rising_edge(clk)` |
| 算术类型 | `signed` / 整型 | `signed` / `unsigned`（`numeric_std`） |
| 例化方式 | `U_Xxx ModuleName (...)` | `U_XXX : entity work.xxx ...` |
| 文件头 | `//Moudle Name` | `--Moudle Name`（同字段，`--` 注释） |
| 顶层分区注释 | `//Global Clock` | `-- ===================== 系统时钟` |

---

## 17. VHDL-2008 语法强制要求

本章约束**全部新写 VHDL**。遗留文件逐步改造；新增模块不得再按 VHDL-87 / 93 旧习惯编写。

### 17.1 工具与版本

1. 工程综合、仿真必须启用 **VHDL-2008**（Quartus / Vivado / ModelSim / Questa 等均需勾选或脚本指定）。
2. 文件扩展名统一 `.vhd`。
3. 关键字推荐小写；同一文件内大小写风格不得混用。

### 17.2 允许 / 禁止的库

| 类型 | 内容 |
|------|------|
| 允许 | `ieee.std_logic_1164.all`、`ieee.numeric_std.all` |
| 按需 | `ieee.math_real`（仅常量计算 / TB）、`ieee.numeric_std_unsigned`（确有需要时） |
| 禁止 | `std_logic_arith`、`std_logic_unsigned`、`std_logic_signed` 等 Synopsys 旧包；RTL 禁用文件 I/O 类包 |

### 17.3 必须采用的现代写法

| 场景 | 旧写法（禁止新用） | 新写法（必须） |
|------|--------------------|----------------|
| 组合 Process 敏感表 | 手写易漏列的信号列表 | `process(all)` |
| 时钟边沿 | `clk'event and clk = '1'` | `rising_edge(clk)` / `falling_edge(clk)` |
| 算术 | 对 `std_logic_vector` 直接加减 | `unsigned` / `signed` + `numeric_std` |
| 例化 | 仅 COMPONENT + 位置关联 | `entity work.xxx` + 命名关联 |
| 读 out 端口 | 必须改用 `buffer` | VHDL-2008 可读 `out`；仍推荐内部信号驱动输出 |

### 17.4 类型与转换

```vhdl
-- 端口：std_logic / std_logic_vector
-- 内部算术：unsigned / signed
signal r_cnt     : unsigned(7 downto 0) := (others => '0');
signal w_cnt_slv : std_logic_vector(7 downto 0);

w_cnt_slv <= std_logic_vector(r_cnt);
r_cnt     <= unsigned(i_cnt_slv);
```

1. 端口层保持 `std_logic` / `std_logic_vector`，便于对接 IP。
2. 加减乘比较在 `unsigned` / `signed` 上完成，边界显式转换。
3. 禁止隐式依赖厂商对 `std_logic_vector` 算术的扩展。

### 17.5 状态机（VHDL-2008）

```vhdl
type t_state is (IDLE, BUSY, DONE);
signal r_state      : t_state := IDLE;
signal w_next_state : t_state;

-- 状态寄存器
process (i_sys_clk, i_sys_rst)
begin
    if i_sys_rst = '1' then
        r_state <= IDLE;
    elsif rising_edge(i_sys_clk) then
        r_state <= w_next_state;
    end if;
end process;

-- 次态组合
process (all)
begin
    case r_state is
        when IDLE   => w_next_state <= BUSY;
        when BUSY   => w_next_state <= DONE;
        when others => w_next_state <= IDLE;
    end case;
end process;
```

推荐用**枚举类型**描述状态，由综合器编码；若需指定编码，再改用 `std_logic_vector` 并注释编码方式。

### 17.6 仿真（VHDL-2008）

1. TB 可使用 `wait for`、`report`、`assert`；不得进入可综合 RTL。
2. 可用 2008 的 `to_string` 等增强便于打印（仅 TB）。
3. 时钟生成示例：

```vhdl
constant CLK_PERIOD : time := 20 ns;
signal i_sys_clk : std_logic := '0';

i_sys_clk <= not i_sys_clk after CLK_PERIOD / 2;
```

### 17.7 与遗留代码共存

| 情况 | 处理 |
|------|------|
| 新模块 | 必须 VHDL-2008 + 本章要求 |
| 旧模块小改 | 触及文件时尽量改为 `process(all)`、`numeric_std`、直接例化 |
| 第三方 IP | Wrapper 用新语法；IP 内部不改 |

---

## 18. 代码审查检查清单

提交前逐项确认，全部通过方可合入。

### 文档与风格

- [ ] 文件头完整（含版本历史）
- [ ] 命名符合 `i/o/io/r/w`（VHDL 另含 `v_`）
- [ ] Port 按功能分组、列对齐
- [ ] 扩展名小写，缩进 4 空格

### 逻辑与可综合性

- [ ] 无 latch、无组合环路、无多驱动；时序逻辑非阻塞赋值
- [ ] 无门控时钟；分频时钟未滥用为全局时钟
- [ ] 状态机含 `default` / `others` 分支
- [ ] 魔数已用 `localparam` / `constant` 定义并注释物理含义
- [ ] 可综合 RTL 未使用 `real` / 浮点运算；若用浮点 IP，位宽 / 延迟 / 舍入已文档化

### VHDL-2008 专项

- [ ] 工程已启用 VHDL-2008；未使用 87/93 旧习惯新写代码
- [ ] 仅使用 `std_logic_1164` + `numeric_std`（无 Synopsys 旧包）
- [ ] 算术使用 `unsigned` / `signed`，未对 `std_logic_vector` 直接运算
- [ ] 组合逻辑使用 `process(all)`；时钟边沿使用 `rising_edge` / `falling_edge`
- [ ] 例化使用 `entity work.xxx` 命名关联（第三方例外已说明）
- [ ] `generic` 与 `constant` 语义正确；`variable` 使用 `v_` 且仅在 process / function 内

### 时钟、复位与 CDC

- [ ] 跨时钟域已处理（单 bit 同步 / 多 bit FIFO 或握手）
- [ ] 长链路已中间打拍
- [ ] 复位极性统一；异步复位、同步释放；PLL locked 后再释放业务复位
- [ ] 异步输入已同步；输出控制信号已寄存器化（必要时）

### 约束与仿真

- [ ] 顶层端口约束完整（管脚 + 电平标准）
- [ ] 仿真可通过（`+define+SIMULATION_EN` 或工程等效宏）
- [ ] 符合 [§1.3](#13-禁止事项)、[§1.4](#14-注意事项强烈建议)、[§17](#17-vhdl-2008-语法强制要求)

---

## 19. 修订记录

| 版本 | 日期 | 说明 |
|------|------|------|
| Rev 1.0 | 2026-09-01 | 初版：覆盖 Verilog / VHDL；SIGNAL / VARIABLE、GENERIC / CONSTANT 约定 |
| Rev 1.1 | 2026-09-01 | 去工程化；补充长链路打拍审查项 |
| Rev 1.2 | 2026-09-01 | 扩充禁止事项与注意事项 |
| Rev 1.3 | 2026-09-01 | 新增浮点数禁止与使用约束 |
| Rev 1.4 | 2026-09-01 | 全文排版与表述优化：目录、表格化禁止项、清单分组、文字精炼 |
| Rev 1.5 | 2026-09-01 | 全文统一 VHDL-2008：强制新语法、直接例化、`process(all)`、`numeric_std`；新增 §17 |
