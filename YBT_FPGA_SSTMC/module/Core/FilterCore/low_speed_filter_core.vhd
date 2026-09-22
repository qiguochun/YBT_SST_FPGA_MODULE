--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   low_speed_filter_core.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.22
--Description       :   低速滤波核。正、负母线电压与温度各一路一阶 Tustin 低通。
--                      截止 100 Hz（WC=628 rad/s），采样默认 1 kHz。
--                      底层 lpf_tustin 使用舍入（非截断）、保护位与饱和算术，
--                      抑制 IIR 直流偏置与极限环。
--------------------------------------------------------------------------------
--Version           :   Rev 0.0
--modifier          :
--Modify Date       :
--Modify Record     :
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity low_speed_filter_core is
    generic (
        CLK_FREQ   : positive := 50_000_000;
        FS         : positive := 1000;    -- 采样率，单位 Hz（可用 1 ms 脉冲）
        WC_HZ      : positive := 100;     -- 截止频率，单位 Hz
        GUARD_BITS : natural  := 8        -- 低速反馈更敏感，保护位多于高速
    );
    port (
        -- Global Clock
        i_sys_clk      : in  std_logic;
        i_sys_rst      : in  std_logic;

        -- User Interface
        i_sample_pulse : in  std_logic;  -- 建议接 delay_core 的 1 ms 脉冲
        i_bus_pos      : in  signed(31 downto 0);
        i_bus_neg      : in  signed(31 downto 0);
        i_temp         : in  signed(31 downto 0);
        o_bus_pos      : out signed(31 downto 0);
        o_bus_neg      : out signed(31 downto 0);
        o_temp         : out signed(31 downto 0)
    );
end entity low_speed_filter_core;

architecture rtl of low_speed_filter_core is

    -- WC = 2*pi*f ≈ 628 @ 100 Hz
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

    U_LPF_TEMP : entity work.lpf_tustin
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
            i_input        => i_temp,
            i_sample_pulse => i_sample_pulse,
            o_output       => o_temp
        );

end architecture rtl;
