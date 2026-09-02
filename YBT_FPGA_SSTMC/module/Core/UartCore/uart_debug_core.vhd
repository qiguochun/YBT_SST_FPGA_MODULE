--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   uart_debug_core.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.01
--Description       :   调试 UART 封装顶层。
--                      TX：debug_test + uart_send，监测数据上行。
--                      RX：uart_recv + uart_cmd_parser，上位机命令下行解析框架。
--                      默认：50 MHz、115200 bps、16 路 × 16bit。
--                      暂不绑定物理引脚；地址业务解析后续补充。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--modifier          :
--Modify Date       :
--Modify Record     :
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity uart_debug_core is
    generic (
        CLK_FREQ       : positive := 50_000_000;  -- 系统时钟频率，单位 Hz
        UART_BPS       : positive := 115_200;     -- 串口波特率，单位 bps
        PARAM_COUNT    : positive := 16;          -- 监测参数路数（TX）
        DATA_WIDTH     : positive := 16;          -- 每路数据位宽，单位 bit（TX）
        MAX_DATA_WORDS : positive := 64           -- 单帧最大命令数据字个数（RX）
    );
    port (
        -- Global Clock
        i_sys_clk  : in  std_logic;
        i_sys_rst  : in  std_logic;  -- 异步复位，高有效；统一送至子模块

        -- TX Monitor Interface
        i_mon_buf  : in  std_logic_vector(PARAM_COUNT * DATA_WIDTH - 1 downto 0);
        o_uart_txd : out std_logic;  -- UART 串行发送（内部信号，暂不绑引脚）

        -- RX Command Interface
        i_uart_rxd     : in  std_logic;                      -- UART 串行接收（内部信号）
        o_cmd_frame_vld  : out std_logic;                    -- 命令帧解析成功脉冲
        o_cmd_frame_err  : out std_logic;                    -- 命令帧错误脉冲
        o_cmd_start_addr : out std_logic_vector(7 downto 0); -- 起始地址（业务含义待补）
        o_cmd_length     : out std_logic_vector(7 downto 0); -- 数据字个数 N
        o_cmd_data_wr_en : out std_logic;                    -- 数据字流式写出使能
        o_cmd_data_idx   : out std_logic_vector(7 downto 0); -- 数据字索引
        o_cmd_data_word  : out std_logic_vector(15 downto 0) -- 数据字 16bit
    );
end entity uart_debug_core;

architecture rtl of uart_debug_core is

    -- TX 握手
    signal w_uart_tx_en   : std_logic;
    signal w_uart_tx_busy : std_logic;
    signal w_uart_tx_data : std_logic_vector(7 downto 0);
    signal w_tx_len       : std_logic_vector(15 downto 0);

    -- RX 字节流
    signal w_uart_rx_vld  : std_logic;
    signal w_uart_rx_data : std_logic_vector(7 downto 0);

begin

    -- ===================== 调试数据帧打包（TX） =====================
    U_DEBUG_TEST : entity work.debug_test
        generic map (
            PARAM_COUNT => PARAM_COUNT,
            DATA_WIDTH  => DATA_WIDTH
        )
        port map (
            -- Global Clock
            i_sys_clk  => i_sys_clk,
            i_sys_rst  => i_sys_rst,
            -- User Interface
            i_tx_rd_en => w_uart_tx_busy,
            i_buf      => i_mon_buf,
            o_tx_data  => w_uart_tx_data,
            o_tx_len   => w_tx_len,
            o_tx_en    => w_uart_tx_en
        );

    -- ===================== UART 串行发送 =====================
    U_UART_SEND : entity work.uart_send
        generic map (
            CLK_FREQ => CLK_FREQ,
            UART_BPS => UART_BPS
        )
        port map (
            -- Global Clock
            i_sys_clk      => i_sys_clk,
            i_sys_rst      => i_sys_rst,
            -- User Interface
            i_uart_en      => w_uart_tx_en,
            i_uart_din     => w_uart_tx_data,
            o_uart_tx_busy => w_uart_tx_busy,
            o_uart_txd     => o_uart_txd
        );

    -- ===================== UART 串行接收 =====================
    U_UART_RECV : entity work.uart_recv
        generic map (
            CLK_FREQ => CLK_FREQ,
            UART_BPS => UART_BPS
        )
        port map (
            -- Global Clock
            i_sys_clk      => i_sys_clk,
            i_sys_rst      => i_sys_rst,
            -- User Interface
            i_uart_rxd     => i_uart_rxd,
            o_uart_rx_vld  => w_uart_rx_vld,
            o_uart_rx_data => w_uart_rx_data
        );

    -- ===================== 上位机命令帧解析（框架） =====================
    U_UART_CMD_PARSER : entity work.uart_cmd_parser
        generic map (
            MAX_DATA_WORDS => MAX_DATA_WORDS
        )
        port map (
            -- Global Clock
            i_sys_clk => i_sys_clk,
            i_sys_rst => i_sys_rst,
            -- Byte Stream
            i_byte_vld  => w_uart_rx_vld,
            i_byte_data => w_uart_rx_data,
            -- Parsed Fields
            o_frame_vld    => o_cmd_frame_vld,
            o_frame_err    => o_cmd_frame_err,
            o_start_addr   => o_cmd_start_addr,
            o_length       => o_cmd_length,
            o_data_wr_en   => o_cmd_data_wr_en,
            o_data_idx     => o_cmd_data_idx,
            o_data_word    => o_cmd_data_word
        );

end architecture rtl;
