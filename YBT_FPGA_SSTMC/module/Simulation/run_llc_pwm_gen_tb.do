# ModelSim do-file for llc_pwm_gen_tb
# GUI:  vsim -do run_llc_pwm_gen_tb.do
# Batch: vsim -c -do run_llc_pwm_gen_tb.do

if {[file exists work]} {
    vdel -lib work -all
}
vlib work

vcom -2008 ../Core/PwmCore/llc_pwm_gen.vhd
vcom -2008 llc_pwm_gen_tb.vhd

vsim -t 1ps work.llc_pwm_gen_tb

# ---- 波形：TB 端口 + DUT 关键内部信号 ----
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {TB ports}
add wave -noupdate /llc_pwm_gen_tb/i_sys_clk
add wave -noupdate /llc_pwm_gen_tb/i_sys_rst
add wave -noupdate /llc_pwm_gen_tb/i_pwm_en
add wave -noupdate /llc_pwm_gen_tb/i_sr_en
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/i_pwm_period
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/i_pwm_duty
add wave -noupdate -radix decimal /llc_pwm_gen_tb/i_phase_clk
add wave -noupdate /llc_pwm_gen_tb/o_pwm1
add wave -noupdate /llc_pwm_gen_tb/o_pwm2
add wave -noupdate /llc_pwm_gen_tb/o_pwm3
add wave -noupdate /llc_pwm_gen_tb/o_pwm4
add wave -noupdate /llc_pwm_gen_tb/o_pwm5
add wave -noupdate /llc_pwm_gen_tb/o_pwm6
add wave -noupdate /llc_pwm_gen_tb/o_pwm7
add wave -noupdate /llc_pwm_gen_tb/o_pwm8

add wave -noupdate -divider {DUT internals}
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/U_DUT/r_cnt_m
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/U_DUT/r_cnt_s
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/U_DUT/r_period
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/U_DUT/r_half
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/U_DUT/r_dead
add wave -noupdate -radix decimal /llc_pwm_gen_tb/U_DUT/r_phase
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/U_DUT/r_sh_tbphs
add wave -noupdate /llc_pwm_gen_tb/U_DUT/w_run

add wave -noupdate -divider {Random cmd}
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/m_cmd_freq
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/m_cmd_period
add wave -noupdate -radix decimal /llc_pwm_gen_tb/m_cmd_phase

add wave -noupdate -divider {Per-cycle measure}
add wave -noupdate -radix decimal /llc_pwm_gen_tb/m_idx
add wave -noupdate -radix decimal /llc_pwm_gen_tb/m_ph14
add wave -noupdate -radix decimal /llc_pwm_gen_tb/m_ph23
add wave -noupdate -radix decimal /llc_pwm_gen_tb/m_dt12
add wave -noupdate -radix decimal /llc_pwm_gen_tb/m_dt34

add wave -noupdate -divider {pwm1-4 high cnt}
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/m_hi1_cnt
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/m_hi2_cnt
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/m_hi3_cnt
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/m_hi4_cnt
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/m_hi1_w
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/m_hi2_w
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/m_hi3_w
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/m_hi4_w

configure wave -namecolwidth 220
configure wave -valuecolwidth 80
WaveRestoreZoom {0 ps} {200 us}

run 100 ms
wave zoom full
