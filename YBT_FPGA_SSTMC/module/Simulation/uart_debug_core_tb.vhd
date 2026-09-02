--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   uart_debug_core_tb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.01
--Description       :   uart_debug_core 模块级仿真 Testbench。
--                      覆盖 TX 监测输出与 RX 命令帧（AA 55 ... 55 AA）解析。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--modifier          :
--Modify Date       :
--Modify Record     :
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity uart_debug_core_tb is
end entity uart_debug_core_tb;

architecture sim of uart_debug_core_tb is

    constant CLK_PERIOD   : time     := 20 ns;   -- 50 MHz
    constant PARAM_COUNT  : positive := 16;
    constant DATA_WIDTH   : positive := 32;
    constant RST_HOLD     : time     := 200 ns;
    constant BIT_PERIOD   : time     := 8681 ns; -- 约 1/115200 s
    constant SIM_RUN_TIME : time     := 5 ms;

    signal i_sys_clk  : std_logic := '0';
    signal i_sys_rst  : std_logic := '1';
    signal i_mon_buf  : std_logic_vector(PARAM_COUNT * DATA_WIDTH - 1 downto 0) := (others => '0');
    signal o_uart_txd : std_logic;
    signal i_uart_rxd : std_logic := '1';

    signal o_cmd_frame_vld  : std_logic;
    signal o_cmd_frame_err  : std_logic;
    signal o_cmd_start_addr : std_logic_vector(7 downto 0);
    signal o_cmd_length     : std_logic_vector(7 downto 0);
    signal o_cmd_data_wr_en : std_logic;
    signal o_cmd_data_idx   : std_logic_vector(7 downto 0);
    signal o_cmd_data_word  : std_logic_vector(15 downto 0);

    -- 发送一字节到 i_uart_rxd（8N1）
    procedure uart_send_byte (
        signal rxd : out std_logic;
        constant data : in std_logic_vector(7 downto 0)
    ) is
    begin
        rxd <= '0';
        wait for BIT_PERIOD;
        for i in 0 to 7 loop
            rxd <= data(i);
            wait for BIT_PERIOD;
        end loop;
        rxd <= '1';
        wait for BIT_PERIOD;
    end procedure;

begin

    -- ===================== 被测模块例化 =====================
    U_DUT : entity work.uart_debug_core
        generic map (
            CLK_FREQ    => 50_000_000,
            UART_BPS    => 115_200,
            PARAM_COUNT => PARAM_COUNT,
            DATA_WIDTH  => DATA_WIDTH
        )
        port map (
            -- Global Clock
            i_sys_clk  => i_sys_clk,
            i_sys_rst  => i_sys_rst,
            -- TX
            i_mon_buf  => i_mon_buf,
            o_uart_txd => o_uart_txd,
            -- RX
            i_uart_rxd       => i_uart_rxd,
            o_cmd_frame_vld  => o_cmd_frame_vld,
            o_cmd_frame_err  => o_cmd_frame_err,
            o_cmd_start_addr => o_cmd_start_addr,
            o_cmd_length     => o_cmd_length,
            o_cmd_data_wr_en => o_cmd_data_wr_en,
            o_cmd_data_idx   => o_cmd_data_idx,
            o_cmd_data_word  => o_cmd_data_word
        );

    -- ===================== 50 MHz 时钟产生 =====================
    i_sys_clk <= not i_sys_clk after CLK_PERIOD / 2;

    -- ===================== 激励向量 =====================
    stimulus : process
    begin
        i_sys_rst <= '1';
        i_mon_buf <= (others => '0');
        i_uart_rxd <= '1';
        wait for RST_HOLD;

        i_sys_rst              <= '0';
        i_mon_buf(15 downto 0) <= x"0001";
        wait for 50 us;

        -- 发送命令帧：AA 55 | Addr=0x10 | Len=2 | Data0=0x1234 | Data1=0xABCD | 55 AA
        uart_send_byte(i_uart_rxd, x"AA");
        uart_send_byte(i_uart_rxd, x"55");
        uart_send_byte(i_uart_rxd, x"10");
        uart_send_byte(i_uart_rxd, x"02");
        uart_send_byte(i_uart_rxd, x"34");  -- Data0 低字节
        uart_send_byte(i_uart_rxd, x"12");  -- Data0 高字节
        uart_send_byte(i_uart_rxd, x"CD");  -- Data1 低字节
        uart_send_byte(i_uart_rxd, x"AB");  -- Data1 高字节
        uart_send_byte(i_uart_rxd, x"55");
        uart_send_byte(i_uart_rxd, x"AA");

        wait for SIM_RUN_TIME;
        wait;
    end process;

end architecture sim;
