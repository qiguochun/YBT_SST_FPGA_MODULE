--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   zz_fiber_core.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.16
--Description       :   系统控制 <-> 单元主控（ZZ）光纤通信封装。
--                      例化 zz_fiber_out（上发）、zz_fiber_in（接收解析）及 TX_Comm PHY。
--------------------------------------------------------------------------------
--Version           :   Rev 0.3
--modifier          :   Qigc
--Modify Date       :   2026.09.16
--Modify Record     :   按 VHDL-2008 规范整改：端口 snake_case、r_/w_ 命名
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity zz_fiber_core is
    generic (
        CLK_FREQ : positive := 50_000_000;  -- 系统时钟频率，单位 Hz
        DELAY    : positive := 20;          -- PHY 每 bit 时钟数，400 ns @ 50 MHz
        DT_IN    : positive := 70;          -- 下行帧宽：系统 -> 单元主控
        DT_OUT   : positive := 51           -- 上行帧宽：单元主控 -> 系统
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;  -- 异步复位，高有效
        i_tx_clk  : in  std_logic;  -- 20 kHz 帧时钟
        i_led_res : in  std_logic;  -- LED 复位闪烁节拍

        -- Fiber PHY
        i_fiber_r : in  std_logic;  -- 系统侧光纤接收
        o_fiber_t : out std_logic;  -- 系统侧光纤发送（已取反）

        -- Uplink Payload   (本板转发给系统主控的参数)
        i_cerr : in  std_logic_vector(15 downto 0);
        i_dvft : in  std_logic_vector(11 downto 0);
        i_uho  : in  std_logic_vector(15 downto 0);
        i_uth  : in  std_logic_vector(15 downto 0);
        i_ubh  : in  std_logic_vector(15 downto 0);
        i_i1o  : in  std_logic_vector(15 downto 0);
        i_i2o  : in  std_logic_vector(15 downto 0);
        i_i3o  : in  std_logic_vector(15 downto 0);
        i_t1s  : in  std_logic_vector(11 downto 0);
        i_t2s  : in  std_logic_vector(11 downto 0);
        i_t3s  : in  std_logic_vector(11 downto 0);
        i_t4o  : in  std_logic_vector(11 downto 0);
        i_t5o  : in  std_logic_vector(11 downto 0);
        i_t6o  : in  std_logic_vector(11 downto 0);
        i_t7o  : in  std_logic_vector(11 downto 0);
        i_t8o  : in  std_logic_vector(11 downto 0);

        -- Downlink Decoded  (系统主控下发给本板的参数)
        o_clr      : out std_logic;
        o_hpwm     : out std_logic;
        o_dauto    : out std_logic;
        o_dpwm_new : out std_logic;
        o_hpwma    : out std_logic;
        o_hpwmb    : out std_logic;
        o_idzl     : out std_logic_vector(15 downto 0);
        o_p15t     : out std_logic_vector(15 downto 0);
        o_p16t     : out std_logic_vector(15 downto 0);
        o_p17t     : out std_logic_vector(15 downto 0);
        o_p18t     : out std_logic_vector(15 downto 0);
        o_p19t     : out std_logic_vector(15 downto 0);
        o_p23t     : out std_logic_vector(15 downto 0);
        o_pt       : out std_logic_vector(15 downto 0);
        o_duty     : out std_logic_vector(15 downto 0);

        -- Status
        o_cerr6  : out std_logic;                            -- ZZ 光纤通信故障
        o_sin_ft : out std_logic;                            -- 单次通信故障脉冲
        o_dt_in  : out std_logic_vector(DT_IN - 1 downto 0); -- 下行原始帧（调试）
        o_led    : out std_logic                             -- F_LED1 通信心跳
    );
end entity zz_fiber_core;

architecture rtl of zz_fiber_core is

    signal w_dt_in   : std_logic_vector(DT_IN - 1 downto 0) := (others => '0');
    signal w_dt_out  : std_logic_vector(DT_OUT - 1 downto 0) := (others => '0');
    signal w_fiber_t : std_logic := '0';
    signal w_finish  : std_logic := '0';
    signal w_cerr6   : std_logic := '0';

begin

    o_fiber_t <= not w_fiber_t;
    o_cerr6   <= w_cerr6;
    o_dt_in   <= w_dt_in;

    U_ZZ_FIBER_OUT : entity work.zz_fiber_out
        generic map (
            DT_OUT => DT_OUT
        )
        port map (
            -- Global Clock
            i_sys_clk => i_sys_clk,
            i_sys_rst => i_sys_rst,
            i_tx_clk  => i_tx_clk,
            -- Uplink Payload
            i_cerr    => i_cerr,
            i_cerr6   => w_cerr6,
            i_dvft    => i_dvft,
            i_uho     => i_uho,
            i_uth     => i_uth,
            i_ubh     => i_ubh,
            i_i1o     => i_i1o,
            i_i2o     => i_i2o,
            i_i3o     => i_i3o,
            i_t1s     => i_t1s,
            i_t2s     => i_t2s,
            i_t3s     => i_t3s,
            i_t4o     => i_t4o,
            i_t5o     => i_t5o,
            i_t6o     => i_t6o,
            i_t7o     => i_t7o,
            i_t8o     => i_t8o,
            -- Frame to PHY
            o_dt_out  => w_dt_out
        );

    U_ZZ_FIBER_IN : entity work.zz_fiber_in
        generic map (
            CLK_FREQ => CLK_FREQ,
            DT_IN    => DT_IN
        )
        port map (
            -- Global Clock
            i_sys_clk  => i_sys_clk,
            i_sys_rst  => i_sys_rst,
            i_led_res  => i_led_res,
            -- PHY Receive
            i_fiber_r  => i_fiber_r,
            i_dt_in    => w_dt_in,
            i_finish   => w_finish,
            -- Downlink Decoded
            o_clr      => o_clr,             --系统复位
            o_hpwm     => o_hpwm,            --H桥PWM使能
            o_dauto    => o_dauto,           --LLC自动运行，关断时候走200us延时，等待副边可靠关断
            o_dpwm_new => o_dpwm_new,

            o_hpwma    => o_hpwma,           --H桥PWM A
            o_hpwmb    => o_hpwmb,           --H桥PWM B

            o_idzl     => o_idzl,            --LLC均流给定
            o_p15t     => o_p15t,            --LLC开关频率
            -------------参数设置---------------------------------------------
            o_p16t     => o_p16t,
            o_p17t     => o_p17t,
            o_p18t     => o_p18t,
            o_p19t     => o_p19t,
            o_p23t     => o_p23t,
            o_pt       => o_pt,              
            o_duty     => o_duty,            --LLC占空比
            -- Status
            o_cerr6    => w_cerr6,           --ZZ光纤通信故障
            o_led      => o_led              --F_LED1 通信心跳
        );

    -- TX_Comm 为遗留 PHY，端口名保留原风格
    U_ZZ_COMM : entity work.TX_Comm
        generic map (
            DELAY => DELAY,
            DtinN => DT_IN,
            DtOUT => DT_OUT
        )
        port map (
            RESET    => i_sys_rst,
            CLK      => i_sys_clk,
            TXclk    => i_tx_clk,              -- 20 kHz 帧时钟
            FiberR   => i_fiber_r,             --光纤接收
            TXdtIn   => w_dt_in,               --下行原始帧（本板收到的下行帧）
            TXdtOut  => w_dt_out,              --上行原始帧（本板要发送的上行帧）
            FiberT   => w_fiber_t,             --光纤发送（已取反）
            TXSinFt  => o_sin_ft,              --单次通信故障脉冲（收到帧头帧尾错误后置1丢弃本脉冲）
            TXFinish => w_finish               --通信完成标志（一帧收完后会置位该标志）
        );

end architecture rtl;
