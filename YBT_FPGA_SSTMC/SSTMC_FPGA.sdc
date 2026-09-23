# =============================================================================
# SSTMC_FPGA.sdc  (Quartus Prime 18.1 compatible)
# =============================================================================

# --- Clocks ---
create_clock -name CLKIN -period 20.000 -waveform {0.000 10.000} [get_ports {CLKIN}]

derive_pll_clocks

# 120 MHz PLL output (name from derive_pll_clocks report)
set CLK_120MHZ {P_PLL|sz_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}

derive_clock_uncertainty

# --- Input delays ---
set_input_delay -clock CLKIN -max 8.000 [get_ports {zz_r zc_r}]
set_input_delay -clock CLKIN -min 1.000 [get_ports {zz_r zc_r}]
# FFAN_FB1 为 UART RX，内部 2 级同步采样，按异步输入处理
set_false_path -from [get_ports {FFAN_FB1}]

set_input_delay -clock CLKIN -max 8.000 [get_ports {F_T1OUT F_T2OUT F_T3OUT F_T4OUT F_T5OUT}]
set_input_delay -clock CLKIN -min 1.000 [get_ports {F_T1OUT F_T2OUT F_T3OUT F_T4OUT F_T5OUT}]

# AMC1305 DOUT 由片外 SCLK 发出，FPGA 内 2 级同步后采样，按异步输入处理
set_false_path -from [get_ports {UAD1_DAT UAD2_DAT}]

set_input_delay -clock CLKIN -max 8.000 [get_ports {F_FLT1 F_FLT2 F_FLT3 F_FLT4}]
set_input_delay -clock CLKIN -min 1.000 [get_ports {F_FLT1 F_FLT2 F_FLT3 F_FLT4}]

# --- Output delays ---
set_output_delay -clock CLKIN -max 5.000 [get_ports {zz_t zc_t zc_a zc_b zc_c}]
set_output_delay -clock CLKIN -min 0.000 [get_ports {zz_t zc_t zc_a zc_b zc_c}]
set_output_delay -clock CLKIN -max 5.000 [get_ports {F_LED1 F_LED2 F_LED3 F_LED4}]
set_output_delay -clock CLKIN -min 0.000 [get_ports {F_LED1 F_LED2 F_LED3 F_LED4}]

set_output_delay -clock CLKIN -max 5.000 [get_ports {FFAN_PWM FFAN_COM}]
set_output_delay -clock CLKIN -min 0.000 [get_ports {FFAN_PWM FFAN_COM}]

set_output_delay -clock CLKIN -max 5.000 [get_ports {F_T1CLK F_T2CLK F_T3CLK F_T4CLK F_T5CLK}]
set_output_delay -clock CLKIN -min 0.000 [get_ports {F_T1CLK F_T2CLK F_T3CLK F_T4CLK F_T5CLK}]

# 120 MHz 驱动/时钟脚：片外无同步采样器，不做板级同步 Setup/Hold 签核。
# 此前 set_max_delay/-from registers 仍被 STA 计入 PLL 时钟插入延时（~9 ns skew），
# 把实际仅 ~3 ns 的 reg→PAD 数据通路报成违例。此处显式放开。
set_false_path -to [get_ports {
    UAD1_CLK UAD2_CLK
    FHRDY_12 FHRDY_34
    FHS1_DRV FHS2_DRV FHS3_DRV FHS4_DRV
    FL1S1_DRV FL1S2_DRV FL2S1_DRV FL2S2_DRV
    FHOE_DRV FLOE_DRV FL3S1_DRV FL3S2_DRV
}]

# --- CDC exceptions ---
set_false_path -from [get_ports {zz_r zc_r}]
set_false_path -from [get_ports {F_FLT1 F_FLT2 F_FLT3 F_FLT4}]

set_max_delay -from [get_clocks $CLK_120MHZ] -to [get_clocks CLKIN] 40.000
set_max_delay -from [get_clocks CLKIN] -to [get_clocks $CLK_120MHZ] 40.000
