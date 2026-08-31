set_global_assignment -entity "sz_pll" -library "lib_sz_pll" -name IP_TOOL_NAME "altera_pll"
set_global_assignment -entity "sz_pll" -library "lib_sz_pll" -name IP_TOOL_VERSION "18.1"
set_global_assignment -entity "sz_pll" -library "lib_sz_pll" -name IP_TOOL_ENV "mwpim"
set_global_assignment -library "lib_sz_pll" -name SPD_FILE [file join $::quartus(sip_path) "sz_pll.spd"]

set_global_assignment -library "lib_sz_pll" -name MISC_FILE [file join $::quartus(sip_path) "sz_pll_sim/sz_pll.vho"]
