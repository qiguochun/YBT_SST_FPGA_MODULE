--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   llc_pwm_gen.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.01
--Description       :   LLC 全桥 PWM 发生器
--                      占空比反推有效死区 deadtime_eff = half - on_width；
--                      原边脉冲位于半周末尾；SR 嵌在原边开通窗口内。
--------------------------------------------------------------------------------
--Version           :   Rev 0.0
--modifier          :   Qigc
--Modify Date       :   2026.09.01
--Modify Record     :  
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity llc_pwm_gen is
    generic (
        CLK_FREQ : positive := 120_000_000  -- 系统时钟频率，单位 Hz
    );
    port (
        -- Global Clock
        i_sys_clk    : in  std_logic;                     -- 系统时钟，与 CLK_FREQ 一致（默认 120 MHz）
        i_sys_rst    : in  std_logic;                     -- 异步复位，高有效

        -- User Interface（假定与 i_sys_clk 同域；周期边界采样）
        i_pwm_en     : in  std_logic;                     -- PWM 总使能，低电平关断 8 路输出
        i_pwm_period : in  std_logic_vector(12 downto 0); -- 开关周期，单位 clk（80kHz=1500，20kHz=6000）
        i_pwm_duty   : in  std_logic_vector(9 downto 0);  -- 占空比，0～1023 对应 0～50%（×period 后 >>11）
        i_sr_en      : in  std_logic;                     -- 同步整流使能，内部双拍同步

        -- Gate Drive Outputs
        o_pwm1       : out std_logic;                       -- 原边 S1_1，1=开通
        o_pwm2       : out std_logic;                       -- 原边 S1_2
        o_pwm3       : out std_logic;                       -- 原边 S1_3
        o_pwm4       : out std_logic;                       -- 原边 S1_4
        o_pwm5       : out std_logic;                       -- 副边 SR S1_5
        o_pwm6       : out std_logic;                       -- 副边 SR S1_6
        o_pwm7       : out std_logic;                       -- 副边 SR S1_7
        o_pwm8       : out std_logic                        -- 副边 SR S1_8
    );
end entity llc_pwm_gen;

architecture rtl of llc_pwm_gen is

    constant F_CMD_MAX          : positive := 80_000;    --频率最大80K
    constant F_CMD_MIN          : positive := 20_000;    --频率最小20K
    constant F_SR_TRAIL_HIGH_HZ : positive := 33_500;    --SR高频阈值33.5K

    constant PERIOD_WIDTH       : positive := 13;                      -- 最大 6000 clk @20kHz
    constant DUTY_WIDTH         : positive := 10;                      -- 占空比位宽10位
    constant DUTY_SHIFT         : positive := 11;                        -- 归一化分母 2048=2^11
    constant DUTY_PROD_WIDTH    : positive := DUTY_WIDTH + PERIOD_WIDTH; -- duty×period 乘积位宽

    -- ===================== 由 （综合期求值，无运行时除法器） =====================
    constant PERIOD_MIN         : positive := CLK_FREQ / F_CMD_MAX;       
    constant PERIOD_MAX         : positive := CLK_FREQ / F_CMD_MIN;       
    constant PERIOD_HALF_MIN    : positive := PERIOD_MIN / 2;           

    constant PERIOD_TRAIL_HIGH  : positive := CLK_FREQ / F_SR_TRAIL_HIGH_HZ; -- 派生自 CLK_FREQ；33.5kHz 锚点

    constant DEADTIME_PRIMARY   : positive := CLK_FREQ / 5_000_000;     -- 原边死区下限，200 ns→24clk@120MHz
    constant SR_LEAD            : positive := CLK_FREQ / 2_000_000;      -- SR 相对原边延迟，0.5 us→60clk
    constant SR_TRAIL_SHORT     : positive := CLK_FREQ / 2_000_000;      -- SR 早关（高频），0.5 us
    constant SR_TRAIL_LONG      : positive := CLK_FREQ / 100_000;        -- SR 早关（低频），10 us

    constant MIN_PULSE          : positive := 21;                         -- 最短有效脉宽，21 clk（≈175 ns@120MHz）
    constant DUTY_OFF_TH         : positive := 41;                          -- 占空比过低关断阈值，≈0.02×2048

    -- ===================== unsigned 比较常数（派生自上列 positive 常量） =====================
    constant U_PERIOD_MIN        : unsigned(PERIOD_WIDTH - 1 downto 0) := to_unsigned(PERIOD_MIN, PERIOD_WIDTH); -- 最小周期
    constant U_PERIOD_MAX        : unsigned(PERIOD_WIDTH - 1 downto 0) := to_unsigned(PERIOD_MAX, PERIOD_WIDTH); -- 最大周期
    constant U_PERIOD_HALF_MIN   : unsigned(PERIOD_WIDTH - 1 downto 0) := to_unsigned(PERIOD_HALF_MIN, PERIOD_WIDTH); -- 最小周期的一半
    constant U_PERIOD_TRAIL_HIGH : unsigned(PERIOD_WIDTH - 1 downto 0) := to_unsigned(PERIOD_TRAIL_HIGH, PERIOD_WIDTH); -- 高频阈值

    constant U_DEADTIME          : unsigned(PERIOD_WIDTH - 1 downto 0) := to_unsigned(DEADTIME_PRIMARY, PERIOD_WIDTH); -- 原边死区下限
    constant U_SR_LEAD           : unsigned(PERIOD_WIDTH - 1 downto 0) := to_unsigned(SR_LEAD, PERIOD_WIDTH); -- SR 相对原边延迟
    constant U_MIN_PULSE         : unsigned(PERIOD_WIDTH - 1 downto 0) := to_unsigned(MIN_PULSE, PERIOD_WIDTH); -- 最短有效脉宽

    constant U_SR_TRAIL_SHORT    : unsigned(PERIOD_WIDTH - 1 downto 0) := to_unsigned(SR_TRAIL_SHORT, PERIOD_WIDTH); -- SR 早关（高频）
    constant U_SR_TRAIL_LONG     : unsigned(PERIOD_WIDTH - 1 downto 0) := to_unsigned(SR_TRAIL_LONG, PERIOD_WIDTH); -- SR 早关（低频）
    constant U_INIT_DEADTIME_EFF  : unsigned(PERIOD_WIDTH - 1 downto 0) := to_unsigned(PERIOD_HALF_MIN - MIN_PULSE, PERIOD_WIDTH); -- 有效死区起点

    subtype T_CNT is unsigned(PERIOD_WIDTH - 1 downto 0); -- 时序计数器

    -- ===================== 时序寄存器 =====================
    signal r_cycle_cnt    : T_CNT     := (others => '0');              -- 载波计数器，0～period-1
    signal r_pwm_period   : T_CNT     := U_PERIOD_MIN;                -- 当前开关周期（clk）
    signal r_half_period  : T_CNT     := U_PERIOD_HALF_MIN;            -- 当前半周期（clk）
    signal r_deadtime_eff : T_CNT     := U_INIT_DEADTIME_EFF;          -- 有效死区起点（占空比反推）
    signal r_pri_neg_on   : T_CNT     := U_PERIOD_HALF_MIN + U_DEADTIME; -- 负半周原边开通起点
    
    signal r_pwm_run_d    : std_logic := '0';                          -- w_pwm_run 延迟一拍，用于上升沿检测
    signal r_sr_en_d0     : std_logic := '0';                          -- i_sr_en 同步第一级
    signal r_sr_en_d1     : std_logic := '0';                          -- i_sr_en 同步第二级

    signal r_sr_pos_on    : T_CNT := (others => '0');                  -- SR 正半周开通起点
    signal r_sr_pos_off   : T_CNT := (others => '0');                  -- SR 正半周关断起点
    signal r_sr_neg_on    : T_CNT := (others => '0');                  -- SR 负半周开通起点
    signal r_sr_neg_off   : T_CNT := (others => '0');                  -- SR 负半周关断起点

    signal r_pwm1         : std_logic := '0';
    signal r_pwm2         : std_logic := '0';
    signal r_pwm3         : std_logic := '0';
    signal r_pwm4         : std_logic := '0';
    signal r_pwm5         : std_logic := '0';
    signal r_pwm6         : std_logic := '0';
    signal r_pwm7         : std_logic := '0';
    signal r_pwm8         : std_logic := '0';

    -- ===================== 组合逻辑 =====================
    signal w_pwm_run    : std_logic;    -- PWM 运行标志
    signal w_period_end : std_logic;    -- 周期结束标志
    signal w_reload     : std_logic;    -- 装载使能标志
    signal w_sr_en_sync : std_logic;    -- SR 使能同步标志

begin

    -- 输出寄存器化（Moore），避免毛刺直达 IO
    o_pwm1 <= r_pwm1;
    o_pwm2 <= r_pwm2;
    o_pwm3 <= r_pwm3;
    o_pwm4 <= r_pwm4;
    o_pwm5 <= r_pwm5;
    o_pwm6 <= r_pwm6;
    o_pwm7 <= r_pwm7;
    o_pwm8 <= r_pwm8;

    w_sr_en_sync <= r_sr_en_d1;

    -- ===================== 运行标志 / 周期结束 / 装载使能 =====================
    process (all)
        variable v_pwm_run    : std_logic;
        variable v_period_end : std_logic;
    begin
        v_pwm_run := '0';
        if (i_pwm_en = '1') and (unsigned(i_pwm_duty) >= DUTY_OFF_TH) then
            v_pwm_run := '1';
        end if;
        w_pwm_run <= v_pwm_run;

        v_period_end := '0';
        if r_cycle_cnt = (r_pwm_period - 1) then
            v_period_end := '1';
        end if;
        w_period_end <= v_period_end;

        w_reload <= '0';
        if (v_pwm_run = '1') and ((v_period_end = '1') or (r_pwm_run_d = '0')) then
            w_reload <= '1';
        end if;
    end process;

    -- ===================== i_sr_en 双拍同步 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_sr_en_d0 <= '0';
            r_sr_en_d1 <= '0';
        elsif rising_edge(i_sys_clk) then
            r_sr_en_d0 <= i_sr_en;
            r_sr_en_d1 <= r_sr_en_d0;
        end if;
    end process;

    -- ===================== 载波计数 + 周期边界锁存参数 =====================
    process (i_sys_clk, i_sys_rst)
        variable v_period     : T_CNT;      --本周期开关长度
        variable v_half       : T_CNT;      --本周期半周期长度
        variable v_on_width   : T_CNT;      --本周期原边开通宽度
        variable v_on_max     : T_CNT;      --本周期原边开通最大宽度，[MIN_PULSE, half - DEADTIME]
        variable v_dead_eff   : T_CNT;      --本周期有效死区长度，deadtime_eff = half - on_width，下限 DEADTIME_PRIMARY

        variable v_trail      : T_CNT;      --本周期SR早关长度
        variable v_sr_pos_on  : T_CNT;      --本周期SR正半周开通起点
        variable v_sr_pos_off : T_CNT;      --本周期SR正半周关断起点
        variable v_sr_neg_on  : T_CNT;      --本周期SR负半周开通起点
        variable v_sr_neg_off : T_CNT;      --本周期SR负半周关断起点
        variable v_prod       : unsigned(DUTY_PROD_WIDTH - 1 downto 0); -- 占空比×周期乘积  
    begin
        if i_sys_rst = '1' then
            r_cycle_cnt    <= (others => '0');
            r_pwm_run_d    <= '0';
            r_pwm_period   <= U_PERIOD_MIN;
            r_half_period  <= U_PERIOD_HALF_MIN;
            r_deadtime_eff <= U_INIT_DEADTIME_EFF;
            r_pri_neg_on   <= U_PERIOD_HALF_MIN + U_DEADTIME;
            r_sr_pos_on    <= (others => '0');
            r_sr_pos_off   <= (others => '0');
            r_sr_neg_on    <= (others => '0');
            r_sr_neg_off   <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            r_pwm_run_d <= w_pwm_run;

            if w_pwm_run = '0' then
                r_cycle_cnt <= (others => '0');
            elsif w_period_end = '1' then
                r_cycle_cnt <= (others => '0');
            else
                r_cycle_cnt <= r_cycle_cnt + 1;       --载波计数器加1
            end if;

            if w_reload = '1' then
                -- 周期限幅
                v_period := unsigned(i_pwm_period);
                if v_period < U_PERIOD_MIN then
                    v_period := U_PERIOD_MIN;
                elsif v_period > U_PERIOD_MAX then
                    v_period := U_PERIOD_MAX;             --周期限幅，最大周期
                end if;

                v_half := shift_right(v_period, 1);       --本周期半周期长度，period >> 1

                -- on_width = duty × period >> 11，限幅 [MIN_PULSE, half - DEADTIME]
                v_on_max := v_half - U_DEADTIME;          --原边开通最大宽度，half - DEADTIME
                if v_on_max < U_MIN_PULSE then            --原边开通最小宽度，MIN_PULSE
                    v_on_max := U_MIN_PULSE;
                end if;

                v_prod := unsigned(i_pwm_duty) * v_period;
                v_on_width := resize(shift_right(v_prod, DUTY_SHIFT), PERIOD_WIDTH); -- 占空比×周期乘积 >> 11，最终位数得到13位
                if v_on_width < U_MIN_PULSE then
                    v_on_width := U_MIN_PULSE;
                elsif v_on_width > v_on_max then
                    v_on_width := v_on_max;               --原边开通宽度限幅，[MIN_PULSE, on_max]
                end if;

                -- deadtime_eff = half - on_width，下限 DEADTIME_PRIMARY
                v_dead_eff := v_half - v_on_width;
                if v_dead_eff < U_DEADTIME then
                    v_dead_eff := U_DEADTIME;
                end if;

                -- SR trail：≥33.5kHz(period≤3582)→0.5us；<33.5kHz→10us
                if v_period <= U_PERIOD_TRAIL_HIGH then
                    v_trail := U_SR_TRAIL_SHORT;            -- 0.5 us，60 clk@120MHz
                else
                    v_trail := U_SR_TRAIL_LONG;             -- 10 us，1200 clk@120MHz
                end if;

                -- SR 正半周：[deadtime_eff + SR_LEAD, half - trail)
                v_sr_pos_on  := v_dead_eff + U_SR_LEAD;
                v_sr_pos_off := v_half - v_trail;
                if v_sr_pos_off <= (v_sr_pos_on + U_MIN_PULSE) then
                    v_sr_pos_off := v_sr_pos_on + U_MIN_PULSE;
                end if;
                if v_sr_pos_off > v_half then
                    v_sr_pos_off := v_half;
                end if;

                -- SR 负半周：[half + deadtime_eff + SR_LEAD, period - trail)
                v_sr_neg_on  := v_half + v_dead_eff + U_SR_LEAD;
                v_sr_neg_off := v_period - v_trail;
                if v_sr_neg_off <= (v_sr_neg_on + U_MIN_PULSE) then
                    v_sr_neg_off := v_sr_neg_on + U_MIN_PULSE;
                end if;
                if v_sr_neg_off > v_period then
                    v_sr_neg_off := v_period;
                end if;

                -- 锁存本周期全部比较阈值（出波进程仅做比较）
                r_pwm_period   <= v_period;
                r_half_period  <= v_half;
                r_deadtime_eff <= v_dead_eff;
                r_pri_neg_on   <= v_half + v_dead_eff;
                r_sr_pos_on    <= v_sr_pos_on;
                r_sr_pos_off   <= v_sr_pos_off;
                r_sr_neg_on    <= v_sr_neg_on;
                r_sr_neg_off   <= v_sr_neg_off;
            end if;
        end if;
    end process;

    -- ===================== 8 路门极波形输出 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_pwm1 <= '0';
            r_pwm2 <= '0';
            r_pwm3 <= '0';
            r_pwm4 <= '0';
            r_pwm5 <= '0';
            r_pwm6 <= '0';
            r_pwm7 <= '0';
            r_pwm8 <= '0';
        elsif rising_edge(i_sys_clk) then
            if w_pwm_run = '0' then
                r_pwm1 <= '0';
                r_pwm2 <= '0';
                r_pwm3 <= '0';
                r_pwm4 <= '0';
                r_pwm5 <= '0';
                r_pwm6 <= '0';
                r_pwm7 <= '0';
                r_pwm8 <= '0';
            else
                -- 原边正半周：[deadtime_eff, half)
                if (r_cycle_cnt >= r_deadtime_eff) and (r_cycle_cnt < r_half_period) then
                    r_pwm1 <= '1';
                    r_pwm4 <= '1';
                else
                    r_pwm1 <= '0';
                    r_pwm4 <= '0';
                end if;

                -- 原边负半周：[pri_neg_on, period)
                if (r_cycle_cnt >= r_pri_neg_on) and (r_cycle_cnt < r_pwm_period) then
                    r_pwm2 <= '1';
                    r_pwm3 <= '1';
                else
                    r_pwm2 <= '0';
                    r_pwm3 <= '0';
                end if;

                -- 副边 SR 正半周
                if (w_sr_en_sync = '1') and
                   (r_sr_pos_off > r_sr_pos_on) and
                   (r_cycle_cnt >= r_sr_pos_on) and
                   (r_cycle_cnt < r_sr_pos_off) then
                    r_pwm5 <= '1';
                    r_pwm8 <= '1';
                else
                    r_pwm5 <= '0';
                    r_pwm8 <= '0';
                end if;

                -- 副边 SR 负半周
                if (w_sr_en_sync = '1') and
                   (r_sr_neg_off > r_sr_neg_on) and
                   (r_cycle_cnt >= r_sr_neg_on) and
                   (r_cycle_cnt < r_sr_neg_off) then
                    r_pwm6 <= '1';
                    r_pwm7 <= '1';
                else
                    r_pwm6 <= '0';
                    r_pwm7 <= '0';
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
