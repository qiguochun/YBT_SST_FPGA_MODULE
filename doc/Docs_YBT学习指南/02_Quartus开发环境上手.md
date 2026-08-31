# 02 — Quartus 开发环境上手（对照 Vivado）

YBT 使用 **Intel Quartus Prime 18.1 Standard Edition**（工程 `.qsf` 里写明）。你熟悉的是 **Vivado**，下面按“同一件事两边怎么做”来记。

---

## 1. 工具链对照

| 你在 Vivado 里做的事 | Quartus 对应 |
|----------------------|--------------|
| 打开 `.xpr` | 打开 `.qpf`（`SSTMC_FPGA.qpf`） |
| Sources / Hierarchy | Project Navigator 里的 Files / Hierarchy |
| Constraints `.xdc` | 引脚/器件写在 `.qsf`；时序约束用 `.sdc`（本工程几乎没单独 SDC） |
| IP Catalog / Clock Wizard | MegaWizard / IP Catalog → `sz_pll`、`RAM_16_2048` |
| Run Synthesis | Processing → Start Compilation（综合+适配+时序一次跑完） |
| Implementation | 包含在 Compilation 的 Fitter 步骤 |
| Generate Bitstream | 输出 `output_files/SSTMC_FPGA.sof`（SRAM）和 `.pof`（配置器件） |
| Hardware Manager | Tools → Programmer（USB-Blaster） |
| Tcl Console | `.tcl` / `quartus_sh`；本工程有 `YBT_FPGA_SSTMC.tcl` |
| ModelSim 仿真 | EDA Tool Settings 指向 ModelSim-Altera (VHDL) |

综合一次大约覆盖：Analysis & Synthesis → Fitter → Assembler → Timing Analyzer。

---

## 2. 打开本工程

1. 安装 Quartus Prime **18.1 Standard**（版本尽量一致，Cyclone V 在 18.1 上验证过）。
2. File → Open Project → 选择：

   `YBT_FPGA_SSTMC20260817_fan/SSTMC_FPGA.qpf`

3. 确认：
   - Family：Cyclone V
   - Device：`5CEBA2F17C8`
   - Top：`SSTMC_FPGA`

顶层、源文件列表都在 `SSTMC_FPGA.qsf` 末尾：

```
VHDL_FILE TX_Comm.vhd
VHDL_FILE RAM_16_2048.vhd
VHDL_FILE AMC1305_16bit_Controller.vhd
VHDL_FILE AMC1035_5CH_Controller.vhd
VHDL_FILE SSTMC_FPGA.vhd
QIP_FILE  sz_pll.qip
QIP_FILE  RAM_16_2048.qip
```

`.cmp` 是元件声明文件（类似 Verilog 的 component 头），给原理图/例化用；本工程顶层已手写 `COMPONENT`，主要还是靠 `.vhd`。

---

## 3. 工程设置里和 Rock 差异最大的几项

打开 Assignments → Device / Settings：

| 项 | 本工程值 | 含义 |
|----|----------|------|
| Family / Device | Cyclone V / `5CEBA2F17C8` | FBGA-256，C8 速度档，商用 0～85℃ |
| Configuration scheme | Active Serial x4 | 上电从 EPCQ 加载 |
| Configuration device | EPCQ16A | 16 Mbit 配置 Flash |
| Active Serial Clock | 100 MHz | 配置时钟 |
| Configuration VCCIO | 3.3 V | 配置口电平 |
| Unused pins | Weak pull-up, input tri-stated | 未用脚上拉 |
| EDA simulation | ModelSim-Altera (VHDL) | 仿真语言 VHDL |
| Test bench | `SSTMC_FPGA_vhd_tst` | `simulation/modelsim/SSTMC_FPGA.vht` |

Vivado 里 `set_property PACKAGE_PIN` 写在 XDC；Quartus 里是：

```
set_location_assignment PIN_N11 -to CLKIN
set_location_assignment PIN_T3  -to F_LED1
...
```

全部引脚表见 `03_芯片与引脚说明.md`。

---

## 4. 日常工作流（对照你在 Rock 的习惯）

### 4.1 改代码

- 直接改 `.vhd`，保存。
- Quartus 不会像 Vivado 那样强制 “Add Sources”；文件已在 `.qsf` 里即可。
- **新增文件**必须：Project → Add/Remove Files，或手改 `.qsf` 加一行 `VHDL_FILE xxx.vhd`。

### 4.2 综合编译

Processing → Start Compilation（快捷键常为 Ctrl+L）。

关注：

- Flow Summary：有无 Error
- Fitter：引脚是否按 `.qsf` 锁住
- Timing Analyzer：本工程 PWM 跑 120 MHz，改逻辑后要看 slack

输出在 `output_files/`：

| 文件 | 用途 |
|------|------|
| `SSTMC_FPGA.sof` | JTAG 临时下载到 FPGA SRAM，掉电丢失 |
| `*.pof` | 烧到 EPCQ，上电自动加载 |
| `*.rpt` | 资源、时序、引脚报告 |
| `*.jdi` | 在线调试信号表 |

### 4.3 下载

1. Tools → Programmer
2. Hardware：USB-Blaster（驱动需单独装）
3. 加文件：
   - 调试：`SSTMC_FPGA.sof` → Program/Configure
   - 固化：对 EPCQ 用 `.pof`（或 Convert Programming Files 生成 jic）

对照 Vivado Hardware Manager 的 bitstream 下载；SOF ≈ bit，POF ≈ 烧到板载 Flash。

### 4.4 仿真

`.qsf` 已指定：

- Tool：ModelSim-Altera (VHDL)
- Testbench：`simulation/modelsim/SSTMC_FPGA.vht`
- Run time：`1 s`

Tools → Run Simulation Tool → RTL Simulation。

注意：顶层含 PLL IP，仿真要按 `sz_pll_sim/` 下的 `msim_setup.tcl` 加载仿真模型，否则 PLL 输出可能一直为 X。

---

## 5. IP 怎么看（对照 Clock Wizard / Block Memory）

### PLL：`sz_pll`

- 输入 `refclk` = `CLKIN` 50 MHz
- 输出 `outclk_0` = `sig_clkMHz`（工程按 **120 MHz** 使用）
- 复位 `rst` 接内部 `sig_RES`

改频：打开 `sz_pll.qip` 对应 MegaWizard，不要直接手改 `sz_pll.vhd` 生成代码。

### RAM：`RAM_16_2048`

- 16 bit 宽、深度 2048（地址 11 bit）
- 被 `AMC1305_16bit_Controller` 用来做 20 点滑动平均的环形缓冲
- 实际只用到 `NUMD=20` 个地址

---

## 6. VHDL 编译习惯 vs Verilog

| Verilog / Vivado | VHDL / Quartus |
|------------------|----------------|
| `timescale` 仿真用 | 仿真精度在 EDA 设置里（本工程 1 ps） |
| `` `include `` / `` `define `` | 本工程不用 package，常量写在实体 architecture 里 |
| 模块名 = 文件名习惯 | **实体名**必须和例化一致；文件名建议相同 |
| always @(*) 组合 | `PROCESS` 无时钟 / 并发赋值 `<=` |
| 大小写不敏感（多数工具） | **VHDL 对标识符大小写不敏感**，但字符串/字符字面量敏感 |
| 未初始化寄存器 X | 本工程大量 `:= '0'` 初值，仿真较友好 |

Quartus 对 `IEEE.STD_LOGIC_arith` + `IEEE.STD_LOGIC_signed` + `NUMERIC_STD` **同时 use** 是老写法，本工程就是这样。新代码建议只用 `NUMERIC_STD`，但改本工程时**保持原风格**，避免运算符重载冲突。

---

## 7. 和 Rock 工程并行时的注意点

- 两套工具可同时装：Vivado 管 Rock，Quartus 管 YBT。
- USB-Blaster（Altera）和 Platform Cable / Digilent（Xilinx）不是同一套驱动。
- 不要把 YBT 的 `.vhd` 丢进 Vivado 当顶层——器件、IP、引脚全部不兼容。
- 若以后要把某段 YBT 算法迁到 Rock：算法（PI、三角波、死区）可迁，**光纤帧和 AMC ΔΣ 驱动必须按硬件重写**。

下一篇：`03_芯片与引脚说明.md`。
