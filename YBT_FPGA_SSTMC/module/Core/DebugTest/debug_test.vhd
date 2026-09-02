--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   debug_test.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.01
--Description       :   调试数据帧打包模块。将 PARAM_COUNT 路 DATA_WIDTH 位监测
--                      数据打包为固定帧，按字节输出给 uart_send。
--                      帧格式：帧头 A5 5A FE 01 + 数据区 + 帧尾 00 00 80 7F。
--                      默认 16 路 × 16bit，总帧长 40 字节。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--modifier          :
--Modify Date       :
--Modify Record     :
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity debug_test is
    generic (
        PARAM_COUNT : positive := 16;  -- 监测参数路数
        DATA_WIDTH  : positive := 16   -- 每路数据位宽，单位 bit
    );
    port (
        -- Global Clock
        i_sys_clk  : in  std_logic;
        i_sys_rst  : in  std_logic;  -- 异步复位，高有效

        -- User Interface
        i_tx_rd_en : in  std_logic;  -- 发送忙反馈，接 uart_send.o_uart_tx_busy
        i_buf      : in  std_logic_vector(PARAM_COUNT * DATA_WIDTH - 1 downto 0);
        o_tx_data  : out std_logic_vector(7 downto 0);   -- 当前待发送字节
        o_tx_len   : out std_logic_vector(15 downto 0);  -- 帧总字节数
        o_tx_en    : out std_logic                       -- 发送请求单周期脉冲
    );
end entity debug_test;

architecture rtl of debug_test is

    constant HDR_BYTES  : positive := 4;  -- 帧头字节数 = 4
    constant TAIL_BYTES : positive := 4;  -- 帧尾字节数 = 4
    constant DATA_BYTES : positive := DATA_WIDTH / 8;  -- 每路监测数据占用字节数 = DATA_WIDTH / 8
    constant FRAME_LEN : positive := HDR_BYTES + PARAM_COUNT * DATA_BYTES + TAIL_BYTES;  -- 帧总字节数 = 帧头 + 数据区 + 帧尾
    constant FRAME_PERIOD_CNT : positive := 100_000;   -- 帧周期计数器，2ms刷新一次帧数据
    constant BYTE_TICK_CNT : positive := 550;   -- 字节发送节拍计数器，每11us尝试发送一个字节

    signal r_byte_tick  : unsigned(31 downto 0) := (others => '0');     -- 字节发送节拍计数器
    signal r_frame_cnt  : unsigned(31 downto 0) := (others => '0');     -- 帧周期计数器

    signal r_data_sel   : unsigned(15 downto 0) := (others => '0');     -- 发送字节索引
    signal r_tx_rd_en   : std_logic_vector(1 downto 0) := (others => '0'); -- 发送忙反馈同步打拍
    signal r_buf        : std_logic_vector(PARAM_COUNT * DATA_WIDTH - 1 downto 0) := (others => '0'); -- 监测数据缓存
    signal r_tx_en      : std_logic := '0';     -- 发送请求单周期脉冲，给uart_send的启动脉冲寄存器

    signal w_tx_rd_en_edge : std_logic;     -- 发送忙反馈上升沿检测
    signal w_cache_byte    : std_logic_vector(7 downto 0);     -- 当前待发送字节，给uart_send的输入数据寄存器

    -- 按字节索引取帧内容（帧头 / 数据 / 帧尾）
    function f_get_cache_byte (
        sel : integer;     -- 字节索引
        buf : std_logic_vector     -- 监测数据缓存，给uart_send的输入数据寄存器
    ) return std_logic_vector is
        variable v_byte : std_logic_vector(7 downto 0) := (others => '0');     -- 当前待发送字节
        variable v_idx  : integer;     -- 字节索引
    begin
        if sel < HDR_BYTES then     -- 帧头字节
            case sel is
                when 0      => v_byte := x"A5";
                when 1      => v_byte := x"5A";
                when 2      => v_byte := x"FE";
                when 3      => v_byte := x"01";
                when others => v_byte := (others => '0');
            end case;
        elsif sel >= FRAME_LEN - TAIL_BYTES then
            case sel - (FRAME_LEN - TAIL_BYTES) is
                when 0      => v_byte := x"00";
                when 1      => v_byte := x"00";
                when 2      => v_byte := x"80";
                when 3      => v_byte := x"7F";
                when others => v_byte := (others => '0');
            end case;
        else
            -- 数据区：第 v_idx 路，小端序拆字节
            v_idx := (sel - HDR_BYTES) / DATA_BYTES;
            case (sel - HDR_BYTES) mod DATA_BYTES is
                when 0 =>
                    v_byte := buf(v_idx * DATA_WIDTH + 7 downto v_idx * DATA_WIDTH);
                when 1 =>
                    v_byte := buf(v_idx * DATA_WIDTH + 15 downto v_idx * DATA_WIDTH + 8);
                when others =>
                    v_byte := (others => '0');
            end case;
        end if;

        return v_byte;
    end function;

begin

    o_tx_len       <= std_logic_vector(to_unsigned(FRAME_LEN, 16));  --将帧总数转化为无符号的16进制数
    o_tx_en        <= r_tx_en;
    w_tx_rd_en_edge <= r_tx_rd_en(0) and (not r_tx_rd_en(1));     -- 发送忙反馈上升沿检测

    w_cache_byte <= f_get_cache_byte(to_integer(r_data_sel), r_buf);
    o_tx_data    <= w_cache_byte when (r_data_sel < FRAME_LEN) else (others => '0');

    -- ===================== o_tx_en 单周期脉冲 =====================
    -- r_byte_tick=0 且 UART 空闲时拉高一个时钟周期
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_tx_en <= '0';
        elsif rising_edge(i_sys_clk) then
            if (r_byte_tick = 0) and (r_data_sel < FRAME_LEN) and (i_tx_rd_en = '0') then -- 字节发送节拍计数器为0，字节索引小于帧总字节数，发送忙反馈为低
                r_tx_en <= '1';
            else
                r_tx_en <= '0';
            end if;
        end if;
    end process;

    -- ===================== i_tx_rd_en 同步打拍 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_tx_rd_en <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            r_tx_rd_en(1 downto 0) <= r_tx_rd_en(0) & i_tx_rd_en;  --相当于2位移位寄存器，将i_tx_rd_en打一拍
        end if;
    end process;

    -- ===================== 监测数据采样 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_buf <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if r_frame_cnt = FRAME_PERIOD_CNT - 1 then
                r_buf <= i_buf;  -- 将输入的监测数据缓存到r_buf中
            end if;
        end if;
    end process;

    -- ===================== 帧周期计数 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_frame_cnt <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if r_frame_cnt < FRAME_PERIOD_CNT - 1 then
                r_frame_cnt <= r_frame_cnt + 1;
            else
                r_frame_cnt <= (others => '0');
            end if;
        end if;
    end process;

    -- ===================== 字节发送节拍计数 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_byte_tick <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if r_byte_tick < BYTE_TICK_CNT - 1 then
                r_byte_tick <= r_byte_tick + 1;
            else
                r_byte_tick <= (others => '0');
            end if;
        end if;
    end process;

    -- ===================== 发送字节索引管理 =====================
    -- i_tx_rd_en 上升沿索引加 1；帧周期起始清零  UART刚从空闲变忙，准备下一个字节发送
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_data_sel <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if w_tx_rd_en_edge = '1' then
                r_data_sel <= r_data_sel + 1;
            elsif r_frame_cnt = 0 then
                r_data_sel <= (others => '0');
            end if;
        end if;
    end process;

end architecture rtl;
