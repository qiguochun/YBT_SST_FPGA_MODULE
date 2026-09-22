--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   low_speed_filter_core.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.22
--Description       :   低速滤波核。正/负母线 + 五路温度（AMC1035 T4～T8）
--                      各一路一阶 Tustin 低通。截止 100 Hz，采样默认 1 kHz。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--modifier          :   Qigc
--Modify Date       :   2026.09.23
--Modify Record     :   温度由 1 路扩为 5 路（T4～T8）
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity low_speed_filter_core is
    generic (
        CLK_FREQ   : positive := 50_000_000;
        FS         : positive := 1000;
        WC_HZ      : positive := 100;
        GUARD_BITS : natural  := 8
    );
    port (
        i_sys_clk      : in  std_logic;
        i_sys_rst      : in  std_logic;
        i_sample_pulse : in  std_logic;
        i_bus_pos      : in  signed(31 downto 0);
        i_bus_neg      : in  signed(31 downto 0);
        i_temp1        : in  signed(31 downto 0);  -- T4
        i_temp2        : in  signed(31 downto 0);  -- T5
        i_temp3        : in  signed(31 downto 0);  -- T6
        i_temp4        : in  signed(31 downto 0);  -- T7
        i_temp5        : in  signed(31 downto 0);  -- T8
        o_bus_pos      : out signed(31 downto 0);
        o_bus_neg      : out signed(31 downto 0);
        o_temp1        : out signed(31 downto 0);
        o_temp2        : out signed(31 downto 0);
        o_temp3        : out signed(31 downto 0);
        o_temp4        : out signed(31 downto 0);
        o_temp5        : out signed(31 downto 0)
    );
end entity low_speed_filter_core;

architecture rtl of low_speed_filter_core is

    constant WC_RAD : integer := (6283 * WC_HZ) / 1000;

begin

    U_LPF_BUS_POS : entity work.lpf_tustin
        generic map (
            TRI_MODE => 0, WC => WC_RAD, FS => FS,
            CLK_FREQ => CLK_FREQ, GUARD_BITS => GUARD_BITS
        )
        port map (
            i_sys_clk => i_sys_clk, i_sys_rst => i_sys_rst,
            i_input => i_bus_pos, i_sample_pulse => i_sample_pulse,
            o_output => o_bus_pos
        );

    U_LPF_BUS_NEG : entity work.lpf_tustin
        generic map (
            TRI_MODE => 0, WC => WC_RAD, FS => FS,
            CLK_FREQ => CLK_FREQ, GUARD_BITS => GUARD_BITS
        )
        port map (
            i_sys_clk => i_sys_clk, i_sys_rst => i_sys_rst,
            i_input => i_bus_neg, i_sample_pulse => i_sample_pulse,
            o_output => o_bus_neg
        );

    U_LPF_TEMP1 : entity work.lpf_tustin
        generic map (
            TRI_MODE => 0, WC => WC_RAD, FS => FS,
            CLK_FREQ => CLK_FREQ, GUARD_BITS => GUARD_BITS
        )
        port map (
            i_sys_clk => i_sys_clk, i_sys_rst => i_sys_rst,
            i_input => i_temp1, i_sample_pulse => i_sample_pulse,
            o_output => o_temp1
        );

    U_LPF_TEMP2 : entity work.lpf_tustin
        generic map (
            TRI_MODE => 0, WC => WC_RAD, FS => FS,
            CLK_FREQ => CLK_FREQ, GUARD_BITS => GUARD_BITS
        )
        port map (
            i_sys_clk => i_sys_clk, i_sys_rst => i_sys_rst,
            i_input => i_temp2, i_sample_pulse => i_sample_pulse,
            o_output => o_temp2
        );

    U_LPF_TEMP3 : entity work.lpf_tustin
        generic map (
            TRI_MODE => 0, WC => WC_RAD, FS => FS,
            CLK_FREQ => CLK_FREQ, GUARD_BITS => GUARD_BITS
        )
        port map (
            i_sys_clk => i_sys_clk, i_sys_rst => i_sys_rst,
            i_input => i_temp3, i_sample_pulse => i_sample_pulse,
            o_output => o_temp3
        );

    U_LPF_TEMP4 : entity work.lpf_tustin
        generic map (
            TRI_MODE => 0, WC => WC_RAD, FS => FS,
            CLK_FREQ => CLK_FREQ, GUARD_BITS => GUARD_BITS
        )
        port map (
            i_sys_clk => i_sys_clk, i_sys_rst => i_sys_rst,
            i_input => i_temp4, i_sample_pulse => i_sample_pulse,
            o_output => o_temp4
        );

    U_LPF_TEMP5 : entity work.lpf_tustin
        generic map (
            TRI_MODE => 0, WC => WC_RAD, FS => FS,
            CLK_FREQ => CLK_FREQ, GUARD_BITS => GUARD_BITS
        )
        port map (
            i_sys_clk => i_sys_clk, i_sys_rst => i_sys_rst,
            i_input => i_temp5, i_sample_pulse => i_sample_pulse,
            o_output => o_temp5
        );

end architecture rtl;
