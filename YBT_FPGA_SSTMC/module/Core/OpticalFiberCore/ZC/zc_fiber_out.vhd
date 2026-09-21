--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   zc_fiber_out.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.16
--Description       :   ZC 光纤输出：组帧下发给单元接口 FPGA。
--                      20 kHz 上升沿刷新 21 bit 下行帧。
--------------------------------------------------------------------------------
--Version           :   Rev 0.3
--modifier          :   Qigc
--Modify Date       :   2026.09.16
--Modify Record     :   帧时钟上升沿当拍组帧，去掉多余边沿寄存器
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity zc_fiber_out is
    generic (
        DT_OUT : positive := 21  -- 下行帧宽：单元主控 -> 接口
    );
    port (
        -- Global Clock
        i_sys_clk  : in  std_logic;
        i_sys_rst  : in  std_logic;  -- 异步复位，高有效
        i_tx_clk   : in  std_logic;  -- 20 kHz 帧时钟

        -- Command to ZC
        i_clr      : in  std_logic;
        i_open_clr : in  std_logic;
        i_bs       : in  std_logic;
        i_dpwm_new : in  std_logic;
        i_pt       : in  std_logic_vector(15 downto 0);

        -- Frame to PHY
        o_dt_out   : out std_logic_vector(DT_OUT - 1 downto 0)
    );
end entity zc_fiber_out;

architecture rtl of zc_fiber_out is

    constant CMD_CLR  : std_logic_vector(4 downto 0) := "01001";
    constant CMD_PROT : std_logic_vector(4 downto 0) := "10100";
    constant CMD_DPWM : std_logic_vector(4 downto 0) := "11010";

    signal r_dt_out   : std_logic_vector(DT_OUT - 1 downto 0) := (others => '0');
    signal r_tx_clk_d : std_logic := '0';

begin

    o_dt_out <= r_dt_out;

    -- ===================== 下行组帧 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_tx_clk_d <= '0';
            r_dt_out   <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if (i_tx_clk = '1') and (r_tx_clk_d = '0') then
                if (i_clr = '1') or (i_open_clr = '1') then
                    r_dt_out(20 downto 16) <= CMD_CLR;
                elsif (i_bs = '0') and (i_dpwm_new = '1') then
                    r_dt_out(20 downto 16) <= CMD_DPWM;
                else
                    r_dt_out(20 downto 16) <= CMD_PROT;  -- 保护或默认
                end if;
                r_dt_out(15 downto 0) <= i_pt;
            end if;

            r_tx_clk_d <= i_tx_clk;
        end if;
    end process;

end architecture rtl;
