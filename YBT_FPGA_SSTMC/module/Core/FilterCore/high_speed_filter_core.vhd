--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   high_speed_filter_core.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.22
--Description       :   高速滤波核。正、负母线电压各一路一阶 Tustin 低通。
--                      截止 1 kHz（WC=6283 rad/s），采样默认 78125 Hz，
--                      对齐 AMC1305 Sinc3 OSR=256 @ 20 MHz。
--------------------------------------------------------------------------------
--Version           :   Rev 0.0
--modifier          :
--Modify Date       :
--Modify Record     :
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity high_speed_filter_core is
    generic (
        CLK_FREQ   : positive := 50_000_000;
        FS         : positive := 78125;   -- 采样率，单位 Hz
        WC_HZ      : positive := 1000;    -- 截止频率，单位 Hz
        GUARD_BITS : natural  := 4
    );
    port (
        -- Global Clock
        i_sys_clk      : in  std_logic;
        i_sys_rst      : in  std_logic;

        -- User Interface
        i_sample_pulse : in  std_logic;  -- 与 ADC/抽取更新对齐的单周期脉冲
        i_bus_pos      : in  signed(31 downto 0);
        i_bus_neg      : in  signed(31 downto 0);
        o_bus_pos      : out signed(31 downto 0);
        o_bus_neg      : out signed(31 downto 0)
    );
end entity high_speed_filter_core;

architecture rtl of high_speed_filter_core is

    -- WC = 2*pi*f ≈ 6283 @ 1 kHz；整数避免 real 进 RTL
    constant WC_RAD : integer := (6283 * WC_HZ) / 1000;

begin

    U_LPF_BUS_POS : entity work.lpf_tustin
        generic map (
            TRI_MODE   => 0,
            WC         => WC_RAD,
            FS         => FS,
            CLK_FREQ   => CLK_FREQ,
            GUARD_BITS => GUARD_BITS
        )
        port map (
            i_sys_clk      => i_sys_clk,
            i_sys_rst      => i_sys_rst,
            i_input        => i_bus_pos,
            i_sample_pulse => i_sample_pulse,
            o_output       => o_bus_pos
        );

    U_LPF_BUS_NEG : entity work.lpf_tustin
        generic map (
            TRI_MODE   => 0,
            WC         => WC_RAD,
            FS         => FS,
            CLK_FREQ   => CLK_FREQ,
            GUARD_BITS => GUARD_BITS
        )
        port map (
            i_sys_clk      => i_sys_clk,
            i_sys_rst      => i_sys_rst,
            i_input        => i_bus_neg,
            i_sample_pulse => i_sample_pulse,
            o_output       => o_bus_neg
        );

end architecture rtl;
