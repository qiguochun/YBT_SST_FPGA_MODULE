--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   uart_cmd_parser.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.01
--Description       :   上位机 UART 命令帧解析框架（不含业务地址含义）。
--                      帧格式（自定义）：
--                        | 帧头 2B | 起始地址 1B | 长度 1B | 数据区 | 帧尾 2B |
--                        帧头 : AA 55
--                        起始地址 : 1 字节（含义后续补充）
--                        长度   : 1 字节，表示后续 16bit 数据字个数 N
--                        数据区 : N × 2 字节，小端序（低字节在前）
--                        帧尾 : 55 AA
--                      本模块仅完成组帧校验与字段拆出；地址/数据业务解析预留。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--modifier          :
--Modify Date       :
--Modify Record     :
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_cmd_parser is
    generic (
        MAX_DATA_WORDS : positive := 64  -- 单帧最大 16bit 数据字个数
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;  -- 异步复位，高有效

        -- Byte Stream From uart_recv
        i_byte_vld  : in  std_logic;
        i_byte_data : in  std_logic_vector(7 downto 0);

        -- Parsed Frame Fields（业务映射后续补充）
        o_frame_vld    : out std_logic;                      -- 整帧校验通过脉冲
        o_frame_err    : out std_logic;                      -- 帧错误脉冲（长度非法/帧尾错误）
        o_start_addr   : out std_logic_vector(7 downto 0);   -- 起始地址
        o_length       : out std_logic_vector(7 downto 0);   -- 数据字个数 N
        o_data_wr_en   : out std_logic;                      -- 数据字写出使能（流式）
        o_data_idx     : out std_logic_vector(7 downto 0);   -- 当前数据字索引 0..N-1
        o_data_word    : out std_logic_vector(15 downto 0)   -- 当前 16bit 数据字
    );
end entity uart_cmd_parser;

architecture rtl of uart_cmd_parser is

    -- 自定义帧头 / 帧尾
    constant FRAME_HDR0 : std_logic_vector(7 downto 0) := x"AA";
    constant FRAME_HDR1 : std_logic_vector(7 downto 0) := x"55";
    constant FRAME_TAIL0 : std_logic_vector(7 downto 0) := x"55";
    constant FRAME_TAIL1 : std_logic_vector(7 downto 0) := x"AA";

    type t_state is (
        S_IDLE,
        S_HDR1,
        S_ADDR,
        S_LEN,
        S_DATA_LO,
        S_DATA_HI,
        S_TAIL0,
        S_TAIL1
    );

    signal r_state : t_state := S_IDLE;

    signal r_start_addr : std_logic_vector(7 downto 0) := (others => '0');
    signal r_length     : unsigned(7 downto 0) := (others => '0');
    signal r_word_cnt   : unsigned(7 downto 0) := (others => '0');
    signal r_data_lo    : std_logic_vector(7 downto 0) := (others => '0');

    signal r_frame_vld  : std_logic := '0';
    signal r_frame_err  : std_logic := '0';
    signal r_data_wr_en : std_logic := '0';
    signal r_data_idx   : unsigned(7 downto 0) := (others => '0');
    signal r_data_word  : std_logic_vector(15 downto 0) := (others => '0');

begin

    o_frame_vld  <= r_frame_vld;
    o_frame_err  <= r_frame_err;
    o_start_addr <= r_start_addr;
    o_length     <= std_logic_vector(r_length);
    o_data_wr_en <= r_data_wr_en;
    o_data_idx   <= std_logic_vector(r_data_idx);
    o_data_word  <= r_data_word;

    -- ===================== 帧解析状态机 =====================
    -- 收到完整合法帧后拉高 o_frame_vld 一拍；业务侧再根据地址解析
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_state      <= S_IDLE;
            r_start_addr <= (others => '0');
            r_length     <= (others => '0');
            r_word_cnt   <= (others => '0');
            r_data_lo    <= (others => '0');
            r_frame_vld  <= '0';
            r_frame_err  <= '0';
            r_data_wr_en <= '0';
            r_data_idx   <= (others => '0');
            r_data_word  <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            r_frame_vld  <= '0';
            r_frame_err  <= '0';
            r_data_wr_en <= '0';

            if i_byte_vld = '1' then
                case r_state is
                    when S_IDLE =>
                        if i_byte_data = FRAME_HDR0 then
                            r_state <= S_HDR1;
                        end if;

                    when S_HDR1 =>
                        if i_byte_data = FRAME_HDR1 then
                            r_state <= S_ADDR;
                        else
                            -- 容错：若再次收到 HDR0 则保持找第二字节
                            if i_byte_data = FRAME_HDR0 then
                                r_state <= S_HDR1;
                            else
                                r_state <= S_IDLE;
                            end if;
                        end if;

                    when S_ADDR =>
                        r_start_addr <= i_byte_data;
                        r_state      <= S_LEN;

                    when S_LEN =>
                        r_length   <= unsigned(i_byte_data);
                        r_word_cnt <= (others => '0');
                        if unsigned(i_byte_data) = 0 then
                            r_state <= S_TAIL0;
                        elsif unsigned(i_byte_data) > MAX_DATA_WORDS then
                            r_frame_err <= '1';
                            r_state     <= S_IDLE;
                        else
                            r_state <= S_DATA_LO;
                        end if;

                    when S_DATA_LO =>
                        r_data_lo <= i_byte_data;
                        r_state   <= S_DATA_HI;

                    when S_DATA_HI =>
                        r_data_word  <= i_byte_data & r_data_lo;
                        r_data_idx   <= r_word_cnt;
                        r_data_wr_en <= '1';
                        if r_word_cnt = r_length - 1 then
                            r_word_cnt <= (others => '0');
                            r_state    <= S_TAIL0;
                        else
                            r_word_cnt <= r_word_cnt + 1;
                            r_state    <= S_DATA_LO;
                        end if;

                    when S_TAIL0 =>
                        if i_byte_data = FRAME_TAIL0 then
                            r_state <= S_TAIL1;
                        else
                            r_frame_err <= '1';
                            r_state     <= S_IDLE;
                        end if;

                    when S_TAIL1 =>
                        if i_byte_data = FRAME_TAIL1 then
                            r_frame_vld <= '1';
                        else
                            r_frame_err <= '1';
                        end if;
                        r_state <= S_IDLE;

                    when others =>
                        r_state <= S_IDLE;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
