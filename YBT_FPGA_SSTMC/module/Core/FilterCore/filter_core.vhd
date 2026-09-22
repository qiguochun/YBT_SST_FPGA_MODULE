--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   filter_core.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.22
--Description       :   滤波内核。高速（800 Hz）：正/负母线。
--                      低速（100 Hz）：正/负母线 + 五路温度 T4～T8。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--modifier          :   Qigc
--Modify Date       :   2026.09.23
--Modify Record     :   低速温度扩为 5 路
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity filter_core is
    generic (
        CLK_FREQ      : positive := 50_000_000;
        HS_FS         : positive := 78125;
        HS_WC_HZ      : positive := 800;
        LS_FS         : positive := 1000;
        LS_WC_HZ      : positive := 100;
        HS_GUARD_BITS : natural  := 4;
        LS_GUARD_BITS : natural  := 8
    );
    port (
        i_sys_clk         : in  std_logic;
        i_sys_rst         : in  std_logic;
        i_hs_sample_pulse : in  std_logic;
        i_ls_sample_pulse : in  std_logic;
        i_bus_pos         : in  signed(31 downto 0);
        i_bus_neg         : in  signed(31 downto 0);
        i_temp1           : in  signed(31 downto 0);
        i_temp2           : in  signed(31 downto 0);
        i_temp3           : in  signed(31 downto 0);
        i_temp4           : in  signed(31 downto 0);
        i_temp5           : in  signed(31 downto 0);
        o_hs_bus_pos      : out signed(31 downto 0);
        o_hs_bus_neg      : out signed(31 downto 0);
        o_ls_bus_pos      : out signed(31 downto 0);
        o_ls_bus_neg      : out signed(31 downto 0);
        o_ls_temp1        : out signed(31 downto 0);
        o_ls_temp2        : out signed(31 downto 0);
        o_ls_temp3        : out signed(31 downto 0);
        o_ls_temp4        : out signed(31 downto 0);
        o_ls_temp5        : out signed(31 downto 0)
    );
end entity filter_core;

architecture rtl of filter_core is
begin

    U_HIGH_SPEED : entity work.high_speed_filter_core
        generic map (
            CLK_FREQ   => CLK_FREQ,
            FS         => HS_FS,
            WC_HZ      => HS_WC_HZ,
            GUARD_BITS => HS_GUARD_BITS
        )
        port map (
            i_sys_clk      => i_sys_clk,
            i_sys_rst      => i_sys_rst,
            i_sample_pulse => i_hs_sample_pulse,
            i_bus_pos      => i_bus_pos,
            i_bus_neg      => i_bus_neg,
            o_bus_pos      => o_hs_bus_pos,
            o_bus_neg      => o_hs_bus_neg
        );

    U_LOW_SPEED : entity work.low_speed_filter_core
        generic map (
            CLK_FREQ   => CLK_FREQ,
            FS         => LS_FS,
            WC_HZ      => LS_WC_HZ,
            GUARD_BITS => LS_GUARD_BITS
        )
        port map (
            i_sys_clk      => i_sys_clk,
            i_sys_rst      => i_sys_rst,
            i_sample_pulse => i_ls_sample_pulse,
            i_bus_pos      => i_bus_pos,
            i_bus_neg      => i_bus_neg,
            i_temp1        => i_temp1,
            i_temp2        => i_temp2,
            i_temp3        => i_temp3,
            i_temp4        => i_temp4,
            i_temp5        => i_temp5,
            o_bus_pos      => o_ls_bus_pos,
            o_bus_neg      => o_ls_bus_neg,
            o_temp1        => o_ls_temp1,
            o_temp2        => o_ls_temp2,
            o_temp3        => o_ls_temp3,
            o_temp4        => o_ls_temp4,
            o_temp5        => o_ls_temp5
        );

end architecture rtl;
