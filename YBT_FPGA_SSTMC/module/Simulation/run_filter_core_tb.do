# ModelSim do-file for filter_core_tb
# Usage (from this directory):
#   vsim -c -do run_filter_core_tb.do

if {[file exists work]} {
    vdel -lib work -all
}
vlib work

vcom -2008 ../Core/FilterCore/lpf_tustin.vhd
vcom -2008 ../Core/FilterCore/high_speed_filter_core.vhd
vcom -2008 ../Core/FilterCore/low_speed_filter_core.vhd
vcom -2008 ../Core/FilterCore/filter_core.vhd
vcom -2008 filter_core_tb.vhd

vsim -t 1ps work.filter_core_tb
run -all
quit -f
