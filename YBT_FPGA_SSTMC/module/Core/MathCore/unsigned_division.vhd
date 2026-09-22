--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   unsigned_division.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   无符号整数除法（比较-减法移位除法）。
--                      工作寄存器比被除数+除数多 1 位，避免部分余数左移丢位。
--                      i_start 上升沿启动；除数为 0 时不进入运算，
--                      当拍拉高 o_done / o_div_zero，商和余数清零。
--
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--modifier          :   Qigc
--Modify Date       :   2026.09.21
--Modify Record     :   部分余数加 1 位；除零指示；start 上升沿采样
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity unsigned_division is
    generic (
        WIDTH_DVD : positive := 16;
        WIDTH_DVS : positive := 8
    );
    port (
        -- Global Clock
        i_sys_clk   : in  std_logic;
        i_sys_rst   : in  std_logic;

        -- User Interface
        i_start     : in  std_logic;
        i_dividend  : in  std_logic_vector(WIDTH_DVD - 1 downto 0);
        i_divisor   : in  std_logic_vector(WIDTH_DVS - 1 downto 0);
        o_quotient  : out std_logic_vector(WIDTH_DVD - 1 downto 0);
        o_remainder : out std_logic_vector(WIDTH_DVS - 1 downto 0);
        o_done      : out std_logic;
        o_busy      : out std_logic;
        o_div_zero  : out std_logic
    );
end entity unsigned_division;

architecture rtl of unsigned_division is

    function clog2(n : positive) return natural is
        variable v_tmp : natural := n;
        variable v_log : natural := 0;
    begin
        while v_tmp > 1 loop
            v_tmp := v_tmp / 2;
            v_log := v_log + 1;
        end loop;
        return v_log;
    end function;

    constant CNT_WIDTH : natural := clog2(WIDTH_DVD);
    -- 部分余数 WIDTH_DVS+1 位 + 被除数 WIDTH_DVD 位
    constant W_WORK    : natural := WIDTH_DVD + WIDTH_DVS + 1;

    type t_state is (IDLE, BUSY);
    signal r_state : t_state := IDLE;

    signal r_done             : std_logic := '0';
    signal r_busy             : std_logic := '0';
    signal r_div_zero         : std_logic := '0';
    signal r_start_d          : std_logic := '0';
    signal r_quotient         : unsigned(WIDTH_DVD - 1 downto 0) := (others => '0');
    signal r_remainder        : unsigned(WIDTH_DVS - 1 downto 0) := (others => '0');
    signal r_temp_dvd_shifted : unsigned(W_WORK - 1 downto 0) := (others => '0');
    signal r_quotient_buf     : unsigned(WIDTH_DVD - 1 downto 0) := (others => '0');
    signal r_divisor          : unsigned(WIDTH_DVS - 1 downto 0) := (others => '0');
    signal r_cycle_cnt        : unsigned(CNT_WIDTH downto 0) := (others => '0');

begin

    o_quotient  <= std_logic_vector(r_quotient);
    o_remainder <= std_logic_vector(r_remainder);
    o_done      <= r_done;
    o_busy      <= r_busy;
    o_div_zero  <= r_div_zero;

    process (i_sys_clk, i_sys_rst)
        variable v_shifted   : unsigned(W_WORK - 1 downto 0);
        variable v_high      : unsigned(WIDTH_DVS downto 0);
        variable v_new_high  : unsigned(WIDTH_DVS downto 0);
        variable v_quot_next : unsigned(WIDTH_DVD - 1 downto 0);
    begin
        if i_sys_rst = '1' then
            r_state            <= IDLE;
            r_done             <= '0';
            r_busy             <= '0';
            r_div_zero         <= '0';
            r_start_d          <= '0';
            r_temp_dvd_shifted <= (others => '0');
            r_quotient_buf     <= (others => '0');
            r_divisor          <= (others => '0');
            r_cycle_cnt        <= (others => '0');
            r_quotient         <= (others => '0');
            r_remainder        <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            r_start_d <= i_start;

            case r_state is
                when IDLE =>
                    r_done     <= '0';
                    r_busy     <= '0';
                    r_div_zero <= '0';
                    if (i_start = '1') and (r_start_d = '0') then
                        if unsigned(i_divisor) = 0 then
                            r_quotient  <= (others => '0');
                            r_remainder <= (others => '0');
                            r_done      <= '1';
                            r_div_zero  <= '1';
                        else
                            r_divisor          <= unsigned(i_divisor);
                            r_temp_dvd_shifted <= resize(unsigned(i_dividend), W_WORK);
                            r_quotient_buf     <= (others => '0');
                            r_cycle_cnt        <= (others => '0');
                            r_busy             <= '1';
                            r_state            <= BUSY;
                        end if;
                    end if;

                when BUSY =>
                    v_shifted := shift_left(r_temp_dvd_shifted, 1);
                    v_high    := v_shifted(W_WORK - 1 downto WIDTH_DVD);

                    if v_high >= r_divisor then
                        v_new_high  := v_high - r_divisor;
                        v_quot_next := shift_left(r_quotient_buf, 1) or to_unsigned(1, WIDTH_DVD);
                    else
                        v_new_high  := v_high;
                        v_quot_next := shift_left(r_quotient_buf, 1);
                    end if;

                    r_temp_dvd_shifted <= v_new_high & v_shifted(WIDTH_DVD - 1 downto 0);
                    r_quotient_buf     <= v_quot_next;
                    r_cycle_cnt        <= r_cycle_cnt + 1;
                    r_busy             <= '1';

                    if r_cycle_cnt = to_unsigned(WIDTH_DVD - 1, r_cycle_cnt'length) then
                        r_quotient  <= v_quot_next;
                        r_remainder <= v_new_high(WIDTH_DVS - 1 downto 0);
                        r_done      <= '1';
                        r_busy      <= '0';
                        r_state     <= IDLE;
                    end if;

                when others =>
                    r_state <= IDLE;
                    r_busy  <= '0';
            end case;
        end if;
    end process;

end architecture rtl;
