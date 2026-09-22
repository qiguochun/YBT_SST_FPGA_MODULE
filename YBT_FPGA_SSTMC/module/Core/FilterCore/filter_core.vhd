--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   filter_core.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.22
--Description       :   滤波内核。封装高速（1 kHz）与低速（100 Hz）两路。
--                      高速：正/负母线。低速：正/负母线 + 温度。
--                      结构对齐 Rock FilterCore / LowSpeedFilterCore。
--------------------------------------------------------------------------------
--Version           :   Rev 0.0
--modifier          :
--Modify Date       :
--Modify Record     :
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity filter_core is
    generic (
        CLK_FREQ      : positive := 50_000_000;
        HS_FS         : positive := 78125;  -- 高速采样率，单位 Hz
        HS_WC_HZ      : positive := 1000;   -- 高速截止，单位 Hz
        LS_FS         : positive := 1000;   -- 低速采样率，单位 Hz
        LS_WC_HZ      : positive := 100;    -- 低速截止，单位 Hz
        HS_GUARD_BITS : natural  := 4;
        LS_GUARD_BITS : natural  := 8
    );
    port (
        -- Global Clock
        i_sys_clk         : in  std_logic;
        i_sys_rst         : in  std_logic;

        -- User Interface
        i_hs_sample_pulse : in  std_logic;
        i_ls_sample_pulse : in  std_logic;
        i_bus_pos         : in  signed(31 downto 0);
        i_bus_neg         : in  signed(31 downto 0);
        i_temp            : in  signed(31 downto 0);
        o_hs_bus_pos      : out signed(31 downto 0);
        o_hs_bus_neg      : out signed(31 downto 0);
        o_ls_bus_pos      : out signed(31 downto 0);
        o_ls_bus_neg      : out signed(31 downto 0);
        o_ls_temp         : out signed(31 downto 0)
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
            i_temp         => i_temp,
            o_bus_pos      => o_ls_bus_pos,
            o_bus_neg      => o_ls_bus_neg,
            o_temp         => o_ls_temp
        );

end architecture rtl;
