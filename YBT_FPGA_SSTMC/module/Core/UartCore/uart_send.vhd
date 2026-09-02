--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   uart_send.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.01
--Description       :   UART 异步串行发送模块（仅 TX）。
--                      帧格式：1 起始位 + 8 数据位(LSB 先发) + 1 停止位，无校验。
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

entity uart_send is
    generic (
        CLK_FREQ : positive := 50_000_000;  -- 系统时钟频率，单位 Hz
        UART_BPS : positive := 115_200      -- 串口波特率，单位 bps
    );
    port (
        -- Global Clock
        i_sys_clk      : in  std_logic;
        i_sys_rst      : in  std_logic;  -- 异步复位，高有效

        -- User Interface
        i_uart_en      : in  std_logic;                     -- 发送使能，上升沿启动
        i_uart_din     : in  std_logic_vector(7 downto 0);  -- 待发送并行数据
        o_uart_tx_busy : out std_logic;                     -- 发送忙标志
        o_uart_txd     : out std_logic                      -- UART 串行输出，空闲为高
    );
end entity uart_send;

architecture rtl of uart_send is

    -- 每位占用时钟周期数，派生自 CLK_FREQ / UART_BPS
    constant BPS_CNT : positive := CLK_FREQ / UART_BPS;

    -- 停止位提前结束偏移（约 BPS_CNT/16），用于位宽精度对齐
    constant STOP_EARLY_OFFSET : natural := BPS_CNT / 16;      -- 停止位提前结束偏移（约 BPS_CNT*1/16），停止位提前结束，下一字节起始位可稍早拉低

    -- UART 帧位序号：0=起始位, 1~8=数据位, 9=停止位
    constant BIT_STOP : natural := 9;

    signal r_uart_en_d0 : std_logic := '0';                    -- 发送使能同步打拍寄存器0（原始输入，第一级同步）
    signal r_uart_en_d1 : std_logic := '0';                    -- 发送使能同步打拍寄存器1（防止亚稳态，第二级同步）
    signal r_clk_cnt    : unsigned(15 downto 0) := (others => '0'); -- 位时序计数器（采样点计数）
    signal r_tx_cnt     : unsigned(3 downto 0) := (others => '0'); -- 位计数器（数据位计数，满8位后进STOP状态）
    signal r_tx_flag    : std_logic := '0'; -- 发送标志（高电平有效，表示正在发送）
    signal r_tx_data    : std_logic_vector(7 downto 0) := (others => '0'); -- 发送数据（8位数据暂存，边发边右移）
    signal r_uart_txd   : std_logic := '1'; -- 串行输出（高电平有效，表示空闲）

    signal w_en_flag : std_logic; -- 发送使能标志（w_en_flag = (not r_uart_en_d1) and r_uart_en_d0）

begin
    o_uart_tx_busy <= r_tx_flag;    -- 发送忙标志（高电平有效，表示正在发送）
    o_uart_txd     <= r_uart_txd;   -- 串行输出（低电平有效，表示发送数据）
    w_en_flag      <= (not r_uart_en_d1) and r_uart_en_d0; -- 发送使能标志（w_en_flag = (not r_uart_en_d1) and r_uart_en_d0）

    -- ===================== i_uart_en 同步打拍 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_uart_en_d0 <= '0';
            r_uart_en_d1 <= '0';
        elsif rising_edge(i_sys_clk) then
            r_uart_en_d0 <= i_uart_en;
            r_uart_en_d1 <= r_uart_en_d0;
        end if;
    end process;

    -- ===================== 发送启动 / 结束 =====================
    -- 上升沿置位 r_tx_flag 并锁存数据；停止位中途提前结束
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_tx_flag <= '0';
            r_tx_data <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if w_en_flag = '1' then
                r_tx_flag <= '1';
                r_tx_data <= i_uart_din;
            elsif (r_tx_cnt = BIT_STOP) and
                  (r_clk_cnt = BPS_CNT - STOP_EARLY_OFFSET) then
                r_tx_flag <= '0';
                r_tx_data <= (others => '0');
            end if;
        end if;
    end process;

    -- ===================== 位时序计数 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_clk_cnt <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if r_tx_flag = '1' then
                if r_clk_cnt < BPS_CNT - 1 then
                    r_clk_cnt <= r_clk_cnt + 1;
                else
                    r_clk_cnt <= (others => '0');
                end if;
            else
                r_clk_cnt <= (others => '0');
            end if;
        end if;
    end process;

    -- ===================== 位序号计数 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_tx_cnt <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if r_tx_flag = '1' then
                if r_clk_cnt = BPS_CNT - 1 then
                    r_tx_cnt <= r_tx_cnt + 1;
                end if;
            else
                r_tx_cnt <= (others => '0');
            end if;
        end if;
    end process;

    -- ===================== 串行波形输出 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_uart_txd <= '1';
        elsif rising_edge(i_sys_clk) then
            if r_tx_flag = '1' then
                case to_integer(r_tx_cnt) is
                    when 0      => r_uart_txd <= '0';            -- 起始位
                    when 1      => r_uart_txd <= r_tx_data(0);   -- D0 LSB
                    when 2      => r_uart_txd <= r_tx_data(1);
                    when 3      => r_uart_txd <= r_tx_data(2);
                    when 4      => r_uart_txd <= r_tx_data(3);
                    when 5      => r_uart_txd <= r_tx_data(4);
                    when 6      => r_uart_txd <= r_tx_data(5);
                    when 7      => r_uart_txd <= r_tx_data(6);
                    when 8      => r_uart_txd <= r_tx_data(7);   -- D7 MSB
                    when 9      => r_uart_txd <= '1';            -- 停止位
                    when others => r_uart_txd <= '1';
                end case;
            else
                r_uart_txd <= '1';
            end if;
        end if;
    end process;

end architecture rtl;
