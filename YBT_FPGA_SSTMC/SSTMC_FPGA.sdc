# =============================================================================
# SSTMC_FPGA.sdc  (Quartus Prime 18.1 compatible)
# =============================================================================

# --- Clocks ---
create_clock -name CLKIN -period 20.000 -waveform {0.000 10.000} [get_ports {CLKIN}]

derive_pll_clocks

# 120 MHz PLL output (name from derive_pll_clocks report)
set CLK_120MHZ {P_PLL|sz_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}

# AMC1305 RAM gated clock: ~15 MHz (120 MHz / 8), avoid auto-derive 1 GHz
create_clock -name AMC1305_CLKram -period 66.667 -waveform {0.000 33.333} \
    [get_nets {AMC1305_16bit_Controller:P_AMC1305|CLKram}]

derive_clock_uncertainty

# --- Input delays ---
set_input_delay -clock CLKIN -max 8.000 [get_ports {zz_r zc_r}]
set_input_delay -clock CLKIN -min 1.000 [get_ports {zz_r zc_r}]
# FFAN_FB1 为 UART RX，内部 2 级同步采样，按异步输入处理
set_false_path -from [get_ports {FFAN_FB1}]

set_input_delay -clock CLKIN -max 8.000 [get_ports {F_T1OUT F_T2OUT F_T3OUT F_T4OUT F_T5OUT}]
set_input_delay -clock CLKIN -min 1.000 [get_ports {F_T1OUT F_T2OUT F_T3OUT F_T4OUT F_T5OUT}]

set_input_delay -clock [get_clocks $CLK_120MHZ] -max 8.000 [get_ports {UAD1_DAT UAD2_DAT}]
set_input_delay -clock [get_clocks $CLK_120MHZ] -min 1.000 [get_ports {UAD1_DAT UAD2_DAT}]

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

set_output_delay -clock [get_clocks $CLK_120MHZ] -max 5.000 [get_ports {UAD1_CLK UAD2_CLK}]
set_output_delay -clock [get_clocks $CLK_120MHZ] -min 0.000 [get_ports {UAD1_CLK UAD2_CLK}]

set_output_delay -clock [get_clocks $CLK_120MHZ] -max 5.000 [get_ports {FHRDY_12 FHRDY_34}]
set_output_delay -clock [get_clocks $CLK_120MHZ] -min 0.000 [get_ports {FHRDY_12 FHRDY_34}]
set_output_delay -clock [get_clocks $CLK_120MHZ] -max 5.000 [get_ports {FHS1_DRV FHS2_DRV FHS3_DRV FHS4_DRV}]
set_output_delay -clock [get_clocks $CLK_120MHZ] -min 0.000 [get_ports {FHS1_DRV FHS2_DRV FHS3_DRV FHS4_DRV}]
set_output_delay -clock [get_clocks $CLK_120MHZ] -max 5.000 [get_ports {FL1S1_DRV FL1S2_DRV FL2S1_DRV FL2S2_DRV}]
set_output_delay -clock [get_clocks $CLK_120MHZ] -min 0.000 [get_ports {FL1S1_DRV FL1S2_DRV FL2S1_DRV FL2S2_DRV}]
set_output_delay -clock [get_clocks $CLK_120MHZ] -max 5.000 [get_ports {FHOE_DRV FLOE_DRV FL3S1_DRV FL3S2_DRV}]
set_output_delay -clock [get_clocks $CLK_120MHZ] -min 0.000 [get_ports {FHOE_DRV FLOE_DRV FL3S1_DRV FL3S2_DRV}]

# --- CDC exceptions ---
set_false_path -from [get_ports {zz_r zc_r}]
set_false_path -from [get_ports {F_FLT1 F_FLT2 F_FLT3 F_FLT4}]

set_max_delay -from [get_clocks $CLK_120MHZ] -to [get_clocks CLKIN] 40.000
set_max_delay -from [get_clocks CLKIN] -to [get_clocks $CLK_120MHZ] 40.000

# CLKram is generated in 120 MHz domain; relax cross-domain checks to divclk
set_false_path -from [get_clocks AMC1305_CLKram] -to [get_clocks $CLK_120MHZ]
set_false_path -from [get_clocks $CLK_120MHZ] -to [get_clocks AMC1305_CLKram]
