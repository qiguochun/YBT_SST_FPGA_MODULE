# ModelSim do-file for amc1035_5ch_controller_tb
# Usage (from this directory):
#   vsim -c -do run_amc1035_tb.do

if {[file exists work]} {
    vdel -lib work -all
}
vlib work

vcom -2008 ../../amc1035_5ch_controller.vhd
vcom -2008 amc1035_5ch_controller_tb.vhd

vsim -t 1ps work.amc1035_5ch_controller_tb
run -all
quit -f
