--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   uart_recv.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.01
--Description       :   UART 异步串行接收模块（仅 RX）。
--                      帧格式：1 起始位 + 8 数据位(LSB 先) + 1 停止位，无校验。
--                      起始位下降沿后半位对齐采样，每位中点取数。
--                      默认时钟 50 MHz、波特率 115200 bps。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--modifier          :
--Modify Date       :
--Modify Record     :
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_recv is
    generic (
        CLK_FREQ : positive := 50_000_000;  -- 系统时钟频率，单位 Hz
        UART_BPS : positive := 115_200      -- 串口波特率，单位 bps
    );
    port (
        -- Global Clock
        i_sys_clk      : in  std_logic;
        i_sys_rst      : in  std_logic;  -- 异步复位，高有效

        -- User Interface
        i_uart_rxd     : in  std_logic;                     -- UART 串行输入，空闲为高
        o_uart_rx_vld  : out std_logic;                     -- 接收完成单周期脉冲
        o_uart_rx_data : out std_logic_vector(7 downto 0)   -- 接收到的并行数据
    );
end entity uart_recv;

architecture rtl of uart_recv is

    -- 每位占用时钟周期数，派生自 CLK_FREQ / UART_BPS
    constant BPS_CNT : positive := CLK_FREQ / UART_BPS;

    -- 半位延时，用于起始位中点对齐
    constant BPS_HALF : positive := BPS_CNT / 2;

    type t_state is (IDLE, START, DATA, STOP);
    signal r_state : t_state := IDLE;

    signal r_rxd_d0   : std_logic := '1';                       -- 同步打拍寄存器0（原始输入，第一级同步）
    signal r_rxd_d1   : std_logic := '1';                       -- 同步打拍寄存器1（防止亚稳态，第二级同步）
    signal r_clk_cnt  : unsigned(15 downto 0) := (others => '0'); -- 位时序计数器（采样点计数）
    signal r_bit_cnt  : unsigned(2 downto 0) := (others => '0'); -- 位计数器（数据位计数，满8位后进STOP状态）
    signal r_rx_shift : std_logic_vector(7 downto 0) := (others => '0'); -- 接收移位寄存器（8位数据暂存，边收边右移拼字节）
    signal r_rx_data  : std_logic_vector(7 downto 0) := (others => '0'); -- 接收到的并行数据（拼字节完成，等待输出）
    signal r_rx_vld   : std_logic := '0'; -- 接收完成单周期脉冲

    signal w_rxd_neg : std_logic; -- 下降沿检测信号（起始位下降沿，触发从IDLE进入START状态）

begin

    o_uart_rx_vld  <= r_rx_vld;
    o_uart_rx_data <= r_rx_data;
    w_rxd_neg      <= (not r_rxd_d0) and r_rxd_d1; -- 下降沿检测逻辑（r_rxd_d0 为原始输入，r_rxd_d1 为同步后的稳定值）

    -- ===================== RXD 同步打拍 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_rxd_d0 <= '1';
            r_rxd_d1 <= '1';
        elsif rising_edge(i_sys_clk) then
            r_rxd_d0 <= i_uart_rxd;
            r_rxd_d1 <= r_rxd_d0;
        end if;
    end process;

    -- ===================== 接收状态机 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_state    <= IDLE;
            r_clk_cnt  <= (others => '0');
            r_bit_cnt  <= (others => '0');
            r_rx_shift <= (others => '0');
            r_rx_data  <= (others => '0');
            r_rx_vld   <= '0';
        elsif rising_edge(i_sys_clk) then
            r_rx_vld <= '0';

            case r_state is
                when IDLE =>
                    r_clk_cnt <= (others => '0');
                    r_bit_cnt <= (others => '0');
                    if w_rxd_neg = '1' then
                        r_state <= START;
                    end if;

                when START =>
                    -- 等待半位，确认仍为低再进入数据位
                    if r_clk_cnt = BPS_HALF - 1 then
                        r_clk_cnt <= (others => '0');
                        if r_rxd_d1 = '0' then    -- 确认起始位仍为低，进入数据位
                            r_state <= DATA;
                        else
                            r_state <= IDLE;  -- 毛刺，放弃，重新进入IDLE状态
                        end if;
                    else
                        r_clk_cnt <= r_clk_cnt + 1;
                    end if;

                when DATA =>
                    if r_clk_cnt = BPS_CNT - 1 then
                        r_clk_cnt  <= (others => '0');
                        r_rx_shift <= r_rxd_d1 & r_rx_shift(7 downto 1);
                        if r_bit_cnt = 7 then
                            r_bit_cnt <= (others => '0');
                            r_state   <= STOP;
                        else
                            r_bit_cnt <= r_bit_cnt + 1;
                        end if;
                    else
                        r_clk_cnt <= r_clk_cnt + 1;
                    end if;

                when STOP =>
                    if r_clk_cnt = BPS_CNT - 1 then
                        r_clk_cnt <= (others => '0');
                        r_state   <= IDLE;
                        if r_rxd_d1 = '1' then    -- 确认停止位仍为高，拼字节完成，输出数据
                            r_rx_data <= r_rx_shift;
                            r_rx_vld  <= '1';
                        end if;
                    else
                        r_clk_cnt <= r_clk_cnt + 1;
                    end if;

                when others =>
                    r_state <= IDLE;
            end case;
        end if;
    end process;

end architecture rtl;
