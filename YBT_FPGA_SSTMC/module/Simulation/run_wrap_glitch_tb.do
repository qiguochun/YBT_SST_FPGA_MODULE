# Wrap-glitch check for llc_pwm_gen
set SIM_DIR D:/CODE/YGE/FPGA_MODULE/YBT_FPGA_SSTMC/module/Simulation
cd $SIM_DIR

if {[file exists work_glitch]} {
    vdel -lib work_glitch -all
}
vlib work_glitch
vmap work work_glitch

vcom -2008 $SIM_DIR/../Core/PwmCore/llc_pwm_gen.vhd
vcom -2008 $SIM_DIR/llc_pwm_wrap_glitch_tb.vhd

vsim -c -t 1ps work.llc_pwm_wrap_glitch_tb
run 2 ms
quit -f
