set_location_assignment PIN_N11   -to  CLKIN

#LED
set_location_assignment PIN_T3   -to  F_LED1
set_location_assignment PIN_T2   -to  F_LED2
set_location_assignment PIN_R2   -to  F_LED3
set_location_assignment PIN_R1   -to  F_LED4

#GX
set_location_assignment PIN_T13  -to   zz_t
set_location_assignment PIN_T12  -to   zz_r
set_location_assignment PIN_T10  -to   zc_t
set_location_assignment PIN_R11  -to   zc_r
set_location_assignment PIN_R9   -to   zc_a
set_location_assignment PIN_T8   -to   zc_b
set_location_assignment PIN_T7   -to   zc_c

#PWM
#HB
set_location_assignment PIN_A12  -to   FHOE_DRV
set_location_assignment PIN_A10  -to   FHRDY_12
set_location_assignment PIN_B11  -to   FHRDY_34
set_location_assignment PIN_A8   -to   FHS1_DRV
set_location_assignment PIN_A9   -to   FHS2_DRV
set_location_assignment PIN_A7   -to   FHS3_DRV
set_location_assignment PIN_B7   -to   FHS4_DRV
set_location_assignment PIN_A14  -to   F_FLT1
set_location_assignment PIN_A13  -to   F_FLT2
set_location_assignment PIN_A15  -to   F_FLT3
set_location_assignment PIN_B15  -to   F_FLT4
#LLC
set_location_assignment PIN_L15  -to   FLOE_DRV
set_location_assignment PIN_F15  -to   FL1S1_DRV
set_location_assignment PIN_G16  -to   FL1S2_DRV
set_location_assignment PIN_G15  -to   FL2S1_DRV
set_location_assignment PIN_H16  -to   FL2S2_DRV
set_location_assignment PIN_J16  -to   FL3S1_DRV
set_location_assignment PIN_K16  -to   FL3S2_DRV

#DC
set_location_assignment PIN_C16  -to   UAD1_CLK
set_location_assignment PIN_B16  -to   UAD1_DAT
set_location_assignment PIN_D16  -to   UAD2_CLK
set_location_assignment PIN_C15  -to   UAD2_DAT

#T
set_location_assignment PIN_E15  -to   F_T1CLK
set_location_assignment PIN_E16  -to   F_T1OUT
set_location_assignment PIN_R15  -to   F_T2CLK
set_location_assignment PIN_T15  -to   F_T2OUT
set_location_assignment PIN_R14  -to   F_T3CLK
set_location_assignment PIN_T14  -to   F_T3OUT
set_location_assignment PIN_A4   -to   F_T4CLK
set_location_assignment PIN_C4   -to   F_T4OUT
set_location_assignment PIN_B6   -to   F_T5CLK
set_location_assignment PIN_A5   -to   F_T5OUT

#FAN
set_location_assignment PIN_B3   -to   FFAN_PWM
set_location_assignment PIN_C3   -to   FFAN_COM
set_location_assignment PIN_A3   -to   FFAN_FB1

# I/O standard: all pins assigned in this file use 3.3-V LVCMOS
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to CLKIN
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to F_LED1
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to F_LED2
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to F_LED3
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to F_LED4
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to zz_t
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to zz_r
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to zc_t
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to zc_r
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to zc_a
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to zc_b
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to zc_c
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to FHOE_DRV
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to FHRDY_12
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to FHRDY_34
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to FHS1_DRV
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to FHS2_DRV
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to FHS3_DRV
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to FHS4_DRV
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to F_FLT1
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to F_FLT2
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to F_FLT3
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to F_FLT4
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to FLOE_DRV
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to FL1S1_DRV
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to FL1S2_DRV
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to FL2S1_DRV
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to FL2S2_DRV
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to FL3S1_DRV
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to FL3S2_DRV
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to UAD1_CLK
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to UAD1_DAT
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to UAD2_CLK
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to UAD2_DAT
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to F_T1CLK
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to F_T1OUT
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to F_T2CLK
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to F_T2OUT
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to F_T3CLK
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to F_T3OUT
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to F_T4CLK
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to F_T4OUT
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to F_T5CLK
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to F_T5OUT
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to FFAN_PWM
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to FFAN_COM
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to FFAN_FB1
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to FFAN_FB1
