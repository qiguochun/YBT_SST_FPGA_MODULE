# ModelSim do-file for amc1305_16bit_controller_tb
# Usage (from this directory):
#   vsim -c -do run_amc1305_tb.do

if {[file exists work]} {
    vdel -lib work -all
}
vlib work

vcom -2008 ../../amc1305_16bit_controller.vhd
vcom -2008 amc1305_16bit_controller_tb.vhd

vsim -t 1ps work.amc1305_16bit_controller_tb
run -all
quit -f
