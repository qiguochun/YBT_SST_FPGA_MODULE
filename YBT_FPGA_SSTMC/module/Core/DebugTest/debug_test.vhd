--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   debug_test.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.01
--Description       :   调试数据帧打包模块。将 PARAM_COUNT 路 DATA_WIDTH 位监测
--                      数据打包为固定帧，按字节输出给 uart_send。
--                      帧格式：帧头 A5 5A FE 01 + 数据区 + 帧尾 00 00 80 7F。
--                      默认 16 路 × 32bit 整数（小端），总帧长 72 字节。
--                      配合 VOFA+ 插件 SstmcFrame（定长帧头 + uint32）使用。
--                      Rev 0.3：32 位整数字段；帧刷新周期 10ms（50MHz/500000）。
--------------------------------------------------------------------------------
--Version           :   Rev 0.3
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
        DATA_WIDTH  : positive := 32   -- 每路数据位宽，单位 bit（uint32 整数）
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
    constant DATA_BYTES : positive := DATA_WIDTH / 8;  -- 每路监测数据占用字节数
    constant FRAME_LEN  : positive := HDR_BYTES + PARAM_COUNT * DATA_BYTES + TAIL_BYTES;
    constant FRAME_PERIOD_CNT : positive := 500_000;   -- 帧周期计数器，10ms 刷新一次帧数据（50MHz/500000）
    constant BYTE_TICK_CNT    : positive := 550;        -- 字节发送节拍，约 11us 尝试发送一字节

    type t_data_byte_array is array (0 to PARAM_COUNT * DATA_BYTES - 1) of std_logic_vector(7 downto 0);

    signal r_byte_tick  : unsigned(31 downto 0) := (others => '0');
    signal r_frame_cnt  : unsigned(31 downto 0) := (others => '0');
    signal r_data_sel   : unsigned(15 downto 0) := (others => '0');
    signal r_tx_rd_en   : std_logic_vector(1 downto 0) := (others => '0');
    signal r_data_bytes : t_data_byte_array := (others => (others => '0'));
    signal r_tx_byte    : std_logic_vector(7 downto 0) := (others => '0');
    signal r_tx_en      : std_logic := '0';
    signal r_arm_send   : std_logic := '0';
    signal r_build_idx  : unsigned(1 downto 0) := (others => '0');
    signal r_building   : std_logic := '0';

    signal w_tx_rd_en_edge : std_logic;
    signal w_sel_byte      : std_logic_vector(7 downto 0);

begin

    o_tx_len        <= std_logic_vector(to_unsigned(FRAME_LEN, 16));
    o_tx_en         <= r_tx_en;
    o_tx_data       <= r_tx_byte;
    w_tx_rd_en_edge <= r_tx_rd_en(0) and (not r_tx_rd_en(1));

    -- 帧头/帧尾常量选择 + 数据区索引（32:1 × 8bit，替代 256bit 宽总线取字节）
    process (r_data_sel, r_data_bytes)
        variable v_sel : integer;
    begin
        v_sel := to_integer(r_data_sel);
        if v_sel < HDR_BYTES then
            case v_sel is
                when 0      => w_sel_byte <= x"A5";
                when 1      => w_sel_byte <= x"5A";
                when 2      => w_sel_byte <= x"FE";
                when 3      => w_sel_byte <= x"01";
                when others => w_sel_byte <= (others => '0');
            end case;
        elsif v_sel >= FRAME_LEN - TAIL_BYTES then
            case v_sel - (FRAME_LEN - TAIL_BYTES) is
                when 0      => w_sel_byte <= x"00";
                when 1      => w_sel_byte <= x"00";
                when 2      => w_sel_byte <= x"80";
                when 3      => w_sel_byte <= x"7F";
                when others => w_sel_byte <= (others => '0');
            end case;
        else
            if v_sel < FRAME_LEN then
                w_sel_byte <= r_data_bytes(v_sel - HDR_BYTES);
            else
                w_sel_byte <= (others => '0');
            end if;
        end if;
    end process;

    -- 发送握手：先锁存字节，下一拍再拉高 o_tx_en（配合 uart_send 内部 2 级使能打拍）
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_tx_en    <= '0';
            r_tx_byte  <= (others => '0');
            r_arm_send <= '0';
        elsif rising_edge(i_sys_clk) then
            r_tx_en <= '0';
            if r_arm_send = '1' then
                r_tx_en    <= '1';
                r_arm_send <= '0';
            elsif (r_byte_tick = 0) and (i_tx_rd_en = '0') and (r_data_sel < FRAME_LEN) then
                r_tx_byte  <= w_sel_byte;
                r_arm_send <= '1';
            end if;
        end if;
    end process;

    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_tx_rd_en <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            r_tx_rd_en(1 downto 0) <= r_tx_rd_en(0) & i_tx_rd_en;
        end if;
    end process;

    -- 帧周期末尾分 4 拍拆分监测数据（每拍 4 路），在下一帧发送数据区前完成更新
    process (i_sys_clk, i_sys_rst)
        variable v_base : integer;
        variable v_idx  : integer;
    begin
        if i_sys_rst = '1' then
            r_data_bytes <= (others => (others => '0'));
            r_build_idx  <= (others => '0');
            r_building   <= '0';
        elsif rising_edge(i_sys_clk) then
            if r_frame_cnt = FRAME_PERIOD_CNT - 1 then
                r_building  <= '1';
                r_build_idx <= (others => '0');
            elsif r_building = '1' then
                -- i_buf 低位是 CH0：v_idx=0 取 [31:0]，线上按 CH0→CH15 发送
                v_base := to_integer(r_build_idx) * 4;
                for j in 0 to 3 loop
                    v_idx := v_base + j;
                    if v_idx < PARAM_COUNT then
                        for b in 0 to DATA_BYTES - 1 loop
                            r_data_bytes(v_idx * DATA_BYTES + b) <=
                                i_buf(v_idx * DATA_WIDTH + b * 8 + 7 downto v_idx * DATA_WIDTH + b * 8);
                        end loop;
                    end if;
                end loop;

                if r_build_idx = "11" then
                    r_building <= '0';
                else
                    r_build_idx <= r_build_idx + 1;
                end if;
            end if;
        end if;
    end process;

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
