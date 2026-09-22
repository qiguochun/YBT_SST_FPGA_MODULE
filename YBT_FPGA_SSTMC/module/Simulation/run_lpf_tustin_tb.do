# ModelSim do-file for lpf_tustin_tb
# Usage (from this directory):
#   vsim -c -do run_lpf_tustin_tb.do

if {[file exists work]} {
    vdel -lib work -all
}
vlib work

vcom -2008 ../Core/FilterCore/lpf_tustin.vhd
vcom -2008 lpf_tustin_tb.vhd

vsim -t 1ps work.lpf_tustin_tb
run -all
quit -f
