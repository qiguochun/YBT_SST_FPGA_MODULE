LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.all;
USE IEEE.STD_LOGIC_arith.all;
USE IEEE.STD_LOGIC_signed.all;
USE IEEE.NUMERIC_STD.all;

ENTITY AMC1035_5CH_Controller IS
    PORT(
        RESET        : IN  STD_LOGIC;
        CLK_50MHZ   : IN  STD_LOGIC;
        
        -- 5通道调制时钟输出
        AMC_SCLK1    : OUT STD_LOGIC;
        AMC_SCLK2    : OUT STD_LOGIC;
        AMC_SCLK3    : OUT STD_LOGIC;
        AMC_SCLK4    : OUT STD_LOGIC;
        AMC_SCLK5    : OUT STD_LOGIC;
        
        -- 5通道数据输入
        AMC_DOUT1    : IN  STD_LOGIC;
        AMC_DOUT2    : IN  STD_LOGIC;
        AMC_DOUT3    : IN  STD_LOGIC;
        AMC_DOUT4    : IN  STD_LOGIC;
        AMC_DOUT5    : IN  STD_LOGIC;
        
        -- 5通道16位输出
        DATA_CH1     : OUT STD_LOGIC_VECTOR(11 downto 0);
        DATA_CH2     : OUT STD_LOGIC_VECTOR(11 downto 0);
        DATA_CH3     : OUT STD_LOGIC_VECTOR(11 downto 0);
        DATA_CH4     : OUT STD_LOGIC_VECTOR(11 downto 0);
        DATA_CH5     : OUT STD_LOGIC_VECTOR(11 downto 0);
        
        OUT_VALID    : OUT STD_LOGIC  -- 数据有效标志
    );
END AMC1035_5CH_Controller;

ARCHITECTURE BEHAV OF AMC1035_5CH_Controller IS

CONSTANT OSR_VAL      : INTEGER := 20000;

-- 时钟分频
SIGNAL clk_div_cnt    : INTEGER RANGE 0 TO 15;
SIGNAL sclk_internal  : STD_LOGIC := '0';

-- 5通道同步打拍
SIGNAL CH1_d1, CH1_d2 : STD_LOGIC;
SIGNAL CH2_d1, CH2_d2 : STD_LOGIC;
SIGNAL CH3_d1, CH3_d2 : STD_LOGIC;
SIGNAL CH4_d1, CH4_d2 : STD_LOGIC;
SIGNAL CH5_d1, CH5_d2 : STD_LOGIC;

-- 计数与输出
SIGNAL osr_cnt        : INTEGER RANGE 0 TO OSR_VAL;

SIGNAL CH1_Hcnt       : INTEGER RANGE 0 TO OSR_VAL;
SIGNAL CH2_Hcnt       : INTEGER RANGE 0 TO OSR_VAL;
SIGNAL CH3_Hcnt       : INTEGER RANGE 0 TO OSR_VAL;
SIGNAL CH4_Hcnt       : INTEGER RANGE 0 TO OSR_VAL;
SIGNAL CH5_Hcnt       : INTEGER RANGE 0 TO OSR_VAL;

SIGNAL CH1_out        : STD_LOGIC_VECTOR(11 downto 0);
SIGNAL CH2_out        : STD_LOGIC_VECTOR(11 downto 0);
SIGNAL CH3_out        : STD_LOGIC_VECTOR(11 downto 0);
SIGNAL CH4_out        : STD_LOGIC_VECTOR(11 downto 0);
SIGNAL CH5_out        : STD_LOGIC_VECTOR(11 downto 0);

SIGNAL valid          : STD_LOGIC;

BEGIN

DATA_CH1 <= CH1_out;
DATA_CH2 <= CH2_out;
DATA_CH3 <= CH3_out;
DATA_CH4 <= CH4_out;
DATA_CH5 <= CH5_out;
OUT_VALID <= valid;

-- 5路共用时钟
AMC_SCLK1 <= sclk_internal;
AMC_SCLK2 <= sclk_internal;
AMC_SCLK3 <= sclk_internal;
AMC_SCLK4 <= sclk_internal;
AMC_SCLK5 <= sclk_internal;

-- 时钟分频生成 SCLK
PROCESS(RESET, CLK_50MHZ)
VARIABLE cnt : INTEGER RANGE 0 TO 15 := 0;
BEGIN
    IF RESET = '1' THEN
        cnt := 0;
        sclk_internal <= '0';
    ELSIF rising_edge(CLK_50MHZ) THEN
        cnt := cnt + 1;
        CASE cnt IS
            WHEN 1  => sclk_internal <= '1';
            WHEN 6  => sclk_internal <= '0';
            WHEN 10 => cnt := 0;
            WHEN OTHERS => NULL;
        END CASE;
    END IF;
	clk_div_cnt<=cnt;
END PROCESS;

-- CH1 同步
PROCESS(RESET, CLK_50MHZ)
BEGIN
    IF RESET = '1' THEN
        CH1_d1 <= '0'; CH1_d2 <= '0';
    ELSIF rising_edge(CLK_50MHZ) THEN
        CH1_d1 <= AMC_DOUT1;
        CH1_d2 <= CH1_d1;
    END IF;
END PROCESS;

-- CH2 同步
PROCESS(RESET, CLK_50MHZ)
BEGIN
    IF RESET = '1' THEN
        CH2_d1 <= '0'; CH2_d2 <= '0';
    ELSIF rising_edge(CLK_50MHZ) THEN
        CH2_d1 <= AMC_DOUT2;
        CH2_d2 <= CH2_d1;
    END IF;
END PROCESS;

-- CH3 同步
PROCESS(RESET, CLK_50MHZ)
BEGIN
    IF RESET = '1' THEN
        CH3_d1 <= '0'; CH3_d2 <= '0';
    ELSIF rising_edge(CLK_50MHZ) THEN
        CH3_d1 <= AMC_DOUT3;
        CH3_d2 <= CH3_d1;
    END IF;
END PROCESS;

-- CH4 同步
PROCESS(RESET, CLK_50MHZ)
BEGIN
    IF RESET = '1' THEN
        CH4_d1 <= '0'; CH4_d2 <= '0';
    ELSIF rising_edge(CLK_50MHZ) THEN
        CH4_d1 <= AMC_DOUT4;
        CH4_d2 <= CH4_d1;
    END IF;
END PROCESS;

-- CH5 同步
PROCESS(RESET, CLK_50MHZ)
BEGIN
    IF RESET = '1' THEN
        CH5_d1 <= '0'; CH5_d2 <= '0';
    ELSIF rising_edge(CLK_50MHZ) THEN
        CH5_d1 <= AMC_DOUT5;
        CH5_d2 <= CH5_d1;
    END IF;
END PROCESS;

-- 5通道积分采样（OSR=20000）
PROCESS(RESET, CLK_50MHZ)
BEGIN
    IF RESET = '1' THEN
        osr_cnt  <= 0;
        valid    <= '0';
        CH1_Hcnt <= 0;
        CH2_Hcnt <= 0;
        CH3_Hcnt <= 0;
        CH4_Hcnt <= 0;
        CH5_Hcnt <= 0;
        CH1_out  <= (others => '0');
        CH2_out  <= (others => '0');
        CH3_out  <= (others => '0');
        CH4_out  <= (others => '0');
        CH5_out  <= (others => '0');
    ELSIF rising_edge(CLK_50MHZ) THEN
        valid <= '0';

        IF clk_div_cnt = 0 AND sclk_internal = '0' THEN
            -- 高电平计数
            IF CH1_d2 = '1' THEN CH1_Hcnt <= CH1_Hcnt + 1; END IF;
            IF CH2_d2 = '1' THEN CH2_Hcnt <= CH2_Hcnt + 1; END IF;
            IF CH3_d2 = '1' THEN CH3_Hcnt <= CH3_Hcnt + 1; END IF;
            IF CH4_d2 = '1' THEN CH4_Hcnt <= CH4_Hcnt + 1; END IF;
            IF CH5_d2 = '1' THEN CH5_Hcnt <= CH5_Hcnt + 1; END IF;

            osr_cnt <= osr_cnt + 1;

            -- 完成一次采样
            IF osr_cnt = OSR_VAL THEN
                -- CH1_out <= CONV_STD_LOGIC_VECTOR(CH1_Hcnt - 10000, 16);
                -- CH2_out <= CONV_STD_LOGIC_VECTOR(CH2_Hcnt - 10000, 16);
                -- CH3_out <= CONV_STD_LOGIC_VECTOR(CH3_Hcnt - 10000, 16);
                -- CH4_out <= CONV_STD_LOGIC_VECTOR(CH4_Hcnt - 10000, 16);
                -- CH5_out <= CONV_STD_LOGIC_VECTOR(CH5_Hcnt - 10000, 16);
                CH1_out <= CONV_STD_LOGIC_VECTOR(((CH1_Hcnt - 10000)*785-5797)/16384, 12);
                CH2_out <= CONV_STD_LOGIC_VECTOR(((CH2_Hcnt - 10000)*785-5797)/16384, 12);
                CH3_out <= CONV_STD_LOGIC_VECTOR(((CH3_Hcnt - 10000)*785-5797)/16384, 12);
                CH4_out <= CONV_STD_LOGIC_VECTOR(((CH4_Hcnt - 10000)*938-14089)/16384, 12);
                CH5_out <= CONV_STD_LOGIC_VECTOR(((CH5_Hcnt - 10000)*938-14089)/16384, 12);              
                valid <= '1';
                osr_cnt  <= 0;
                CH1_Hcnt <= 0;
                CH2_Hcnt <= 0;
                CH3_Hcnt <= 0;
                CH4_Hcnt <= 0;
                CH5_Hcnt <= 0;
            END IF;
        END IF;
    END IF;
END PROCESS;

END BEHAV;