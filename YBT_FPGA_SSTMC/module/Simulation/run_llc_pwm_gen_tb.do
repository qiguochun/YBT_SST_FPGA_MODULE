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
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/U_DUT/r_cycle_cnt
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/U_DUT/r_pwm_period
add wave -noupdate /llc_pwm_gen_tb/U_DUT/w_pwm_run
add wave -noupdate /llc_pwm_gen_tb/U_DUT/w_reload
add wave -noupdate /llc_pwm_gen_tb/U_DUT/r_reload_busy
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/U_DUT/r_reload_stage
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/U_DUT/r_pipe_dead
add wave -noupdate -radix unsigned /llc_pwm_gen_tb/U_DUT/r_pipe_on_w
add wave -noupdate -radix decimal /llc_pwm_gen_tb/U_DUT/r_pipe_phase

configure wave -namecolwidth 220
configure wave -valuecolwidth 80
WaveRestoreZoom {0 ps} {200 us}

run -all
wave zoom full
