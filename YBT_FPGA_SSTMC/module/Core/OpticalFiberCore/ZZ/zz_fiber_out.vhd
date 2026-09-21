--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   zz_fiber_out.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.16
--Description       :   ZZ 光纤输出：组帧上发给主控 FPGA。
--                      20 kHz 上升沿刷新 51 bit 上行帧，14 路子帧轮询。
--------------------------------------------------------------------------------
--Version           :   Rev 0.3
--modifier          :   Qigc
--Modify Date       :   2026.09.16
--Modify Record     :   帧时钟上升沿当拍组帧，去掉多余边沿寄存器
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity zz_fiber_out is
    generic (
        DT_OUT : positive := 51  -- 上行帧宽：单元主控 -> 系统
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;  -- 异步复位，高有效
        i_tx_clk  : in  std_logic;  -- 20 kHz 帧时钟

        -- Uplink Payload
        i_cerr  : in  std_logic_vector(15 downto 0);
        i_cerr6 : in  std_logic;  -- 本链路 ZZ 通信故障，插入帧内 bit6
        i_dvft  : in  std_logic_vector(11 downto 0);
        i_uho   : in  std_logic_vector(15 downto 0);
        i_uth   : in  std_logic_vector(15 downto 0);
        i_ubh   : in  std_logic_vector(15 downto 0);
        i_i1o   : in  std_logic_vector(15 downto 0);
        i_i2o   : in  std_logic_vector(15 downto 0);
        i_i3o   : in  std_logic_vector(15 downto 0);
        i_t1s   : in  std_logic_vector(11 downto 0);
        i_t2s   : in  std_logic_vector(11 downto 0);
        i_t3s   : in  std_logic_vector(11 downto 0);
        i_t4o   : in  std_logic_vector(11 downto 0);
        i_t5o   : in  std_logic_vector(11 downto 0);
        i_t6o   : in  std_logic_vector(11 downto 0);
        i_t7o   : in  std_logic_vector(11 downto 0);
        i_t8o   : in  std_logic_vector(11 downto 0);

        -- Frame to PHY
        o_dt_out : out std_logic_vector(DT_OUT - 1 downto 0)
    );
end entity zz_fiber_out;

architecture rtl of zz_fiber_out is

    constant HDR_FAULT    : std_logic_vector(4 downto 0) := "01101";
    constant HDR_OK       : std_logic_vector(4 downto 0) := "10110";
    constant SUBFRAME_NUM : natural := 14;

    signal r_dt_out   : std_logic_vector(DT_OUT - 1 downto 0) := (others => '0');
    signal r_tx_clk_d : std_logic := '0';
    signal r_sub_cnt  : integer range 0 to SUBFRAME_NUM - 1 := 0;

begin

    o_dt_out <= r_dt_out;

    -- ===================== 上行组帧 =====================
    -- bit50~46: 帧头  bit45~32: 故障  bit31~16: 高压侧电压  bit15~0: 子帧
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_dt_out   <= (others => '0');
            r_tx_clk_d <= '0';
            r_sub_cnt  <= 0;
        elsif rising_edge(i_sys_clk) then
            if (i_tx_clk = '1') and (r_tx_clk_d = '0') then
                if i_cerr(15) = '1' then
                    r_dt_out(50 downto 46) <= HDR_FAULT;
                else
                    r_dt_out(50 downto 46) <= HDR_OK;
                end if;
                r_dt_out(45 downto 32) <= i_cerr(13 downto 7) & i_cerr6 & i_cerr(5 downto 0);
                r_dt_out(31 downto 16) <= i_uho;

                case r_sub_cnt is
                    when 0 =>
                        r_dt_out(15 downto 0) <= "0001" & i_i1o(15 downto 4);
                    when 1 =>
                        r_dt_out(15 downto 0) <= "0010" & i_i2o(15 downto 4);
                    when 2 =>
                        r_dt_out(15 downto 0) <= "0011" & i_i3o(15 downto 4);
                    when 3 =>
                        r_dt_out(15 downto 0) <= "0100" & i_dvft;
                    when 4 =>
                        r_dt_out(15 downto 0) <= "0101" & i_uth(15 downto 4);
                    when 5 =>
                        r_dt_out(15 downto 0) <= "0110" & i_ubh(15 downto 4);
                    when 6 =>
                        r_dt_out(15 downto 0) <= "0111" & i_t1s;
                    when 7 =>
                        r_dt_out(15 downto 0) <= "1000" & i_t2s;
                    when 8 =>
                        r_dt_out(15 downto 0) <= "1001" & i_t3s;
                    when 9 =>
                        r_dt_out(15 downto 0) <= "1010" & i_t4o;
                    when 10 =>
                        r_dt_out(15 downto 0) <= "1011" & i_t5o;
                    when 11 =>
                        r_dt_out(15 downto 0) <= "1100" & i_t6o;
                    when 12 =>
                        r_dt_out(15 downto 0) <= "1101" & i_t7o;
                    when 13 =>
                        r_dt_out(15 downto 0) <= "1110" & i_t8o;
                    when others =>
                        null;
                end case;

                if r_sub_cnt = SUBFRAME_NUM - 1 then
                    r_sub_cnt <= 0;
                else
                    r_sub_cnt <= r_sub_cnt + 1;
                end if;
            end if;

            r_tx_clk_d <= i_tx_clk;
        end if;
    end process;

end architecture rtl;
