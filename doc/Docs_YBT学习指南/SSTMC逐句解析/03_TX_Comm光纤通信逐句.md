# 03 — TX_Comm 光纤通信 逐句（小白向）

源文件：`YBT_FPGA_SSTMC20260817_fan/TX_Comm.vhd`（**219 行**）  
顶层例化：`ZZ_COMM` **424～439**（`04` 篇）、`ZC_COMM` **608～624**（`05` 篇）

| 行号 | 块 |
|------|-----|
| 1～20 | ENTITY |
| 22～41 | ARCHITECTURE 声明 + 内部信号 |
| 45～47 | 端口并发赋值 `FiberT` / `TXSinFt` / `TXFinish` |
| 49～60 | 输入同步 |
| 62～124 | 发送 |
| 126～217 | 接收 |
| 219 | `END BEHAV` |

---

## 0. 这个模块干什么（人话）

**不是 UART。**  
它按固定比特时间，发送/接收一帧：

```
帧头图案 → 数据比特（高位先） → 偶校验位 → 帧尾图案
```

- `TXclk` 变高 → 启动发一帧  
- 光纤收到合法帧 → `TXdtIn` 更新，`TXFinish` 脉冲一下  
- 头/尾/校验错 → `TXSinFt=1`

比特时间：`DELAY` 个 `CLK` 周期。本工程 `DELAY=20`，`CLK=50MHz` → **400 ns/bit**。

---

## 1. ENTITY + GENERIC（第 1～20 行）

```vhdl
ENTITY TX_Comm IS
GENERIC(
    DELAY : INTEGER := 20;     -- 每个比特持续多少个 CLK
    DtinN : INTEGER := 41;     -- 接收数据位宽
    DtOUT : INTEGER := 51);    -- 发送数据位宽
PORT(
    RESET    : IN  STD_LOGIC;
    CLK      : IN  STD_LOGIC;
    TXclk    : IN  STD_LOGIC;  -- 发送启动（接 20kHz）
    FiberR   : IN  STD_LOGIC;  -- 光纤收
    TXdtIn   : OUT STD_LOGIC_VECTOR(DtinN-1 DOWNTO 0); -- 收齐的数据
    TXdtOut  : IN  STD_LOGIC_VECTOR(DtOUT-1 DOWNTO 0); -- 要发的数据
    FiberT   : OUT STD_LOGIC;  -- 光纤发
    TXSinFt  : OUT STD_LOGIC;  -- 单次通信故障
    TXFinish : OUT STD_LOGIC   -- 收成功脉冲
);
END TX_Comm;
```

| GENERIC | ZZ 例化 | ZC 例化 |
|---------|---------|---------|
| DELAY | 20 | 20 |
| DtinN（收） | 54 | 43 |
| DtOUT（发） | 51 | 21 |

---

## 2. 内部信号（24～41 行）——两套状态机

| 信号 | 属于 | 作用 |
|------|------|------|
| `outstep` | 发送 | 发送状态 0～22 |
| `outdelay` | 发送 | 比特内拍计数 0～DELAY-1 |
| `outdttemp` | 发送 | 待发数据锁存 |
| `evendo` | 发送 | 偶校验累计 |
| `FiberT_reg` | 发送 | 实际驱动光纤的寄存器 |
| `instep` | 接收 | 接收状态 |
| `indttemp` | 接收 | 收到的移位数据 |
| `evendi` | 接收 | 接收偶校验 |
| `rx_r1/rx_r2` | 同步 | FiberR 打两拍 |
| `txclk_r` | 同步 | TXclk 打一拍 |

```vhdl
FiberT   <= FiberT_reg;   -- 端口由内部寄存器驱动（可回读）
TXSinFt  <= TXSinFt_reg;
TXFinish <= TXFinish_reg;
```

---

## 3. 输入同步进程（49～60 行）

```vhdl
PROCESS(CLK, RESET)
BEGIN
  IF RESET='1' THEN
    rx_r1<='0'; rx_r2<='0'; txclk_r<='0';
  ELSIF RISING_EDGE(CLK) THEN
    rx_r1   <= FiberR;   -- 第 1 拍
    rx_r2   <= rx_r1;    -- 第 2 拍（后面采样用 rx_r2）
    txclk_r <= TXclk;
  END IF;
END PROCESS;
```

**为什么打拍？** 外部光纤异步信号进 FPGA，先同步，减少亚稳态；接收采样用稳定后的 `rx_r2`。

---

## 4. 发送进程（62～124 行）逐状态

### 4.1 比特节拍器

每个 CLK：

```vhdl
IF outdelay < DELAY-1 THEN outdelay <= outdelay+1;
ELSE outdelay <= 0;
END IF;
```

`outdelay` 从 0 数到 DELAY-1 再清零 → **一个比特时间**。  
状态跳转多在 `outdelay=DELAY-1`（比特末尾）发生。

### 4.2 状态机表

| outstep | 做什么 |
|---------|--------|
| **0** | 等 `txclk_r=1`，然后 `FiberT=1`，进 1 |
| **1～8** | 发帧头图案：按状态置 1/0（见下） |
| **9** | 再发一个 `1`，装载 `outdttemp<=TXdtOut`，`outcount<=DtOUT-1`，校验清 0 |
| **10** | 从高位到低位发数据；发完后发 `evendo` 校验位，进 11 |
| **11～21** | 发帧尾图案 |
| **22** | 等 `txclk_r=0` 回到 0（避免 20kHz 高电平期间连发） |

### 4.3 帧头发出的电平（状态 1～9）

在比特边界置位的 `FiberT_reg` 序列约为：

```
状态1→9: 1,1,0,0,1,0,1,0,1
```

收端按期望检查（见接收）。

### 4.4 数据 + 偶校验（状态 10）关键句

```vhdl
FiberT_reg <= outdttemp(outcount);           -- 发当前位
IF outdttemp(outcount)='1' THEN
  evendo <= NOT evendo;                      -- 每遇到 1 翻转 → 偶校验
END IF;
outcount <= outcount - 1;                    -- 下一位（高→低）
-- outcount 减完后：
FiberT_reg <= evendo;  outstep<=11;          -- 发校验位
```

**偶校验**：整帧数据里 `1` 的个数为偶数时，校验位使总 `1` 个数仍为偶。

### 4.5 帧尾（11～21）

发出类似：`1 0 1 1 0 1 0 0 1 1 0`（每位持续 DELAY 拍）。

---

## 5. 接收进程（126～217 行）逐状态

### 5.1 找帧头开头（状态 0）

```vhdl
WHEN 0 =>
  IF rx_r2='1' THEN
    IF indelay < DELAY/2 THEN indelay<=indelay+1;
    ELSE instep<=1; indelay<=0;   -- 等到半比特再进状态1（采样居中）
    END IF;
  ELSE indelay<=0;
  END IF;
```

检测到线变高后，先等约半个比特，再对齐采样点。

### 5.2 核对帧头（状态 1～9）

每个比特末：若 `rx_r2` 不等于期望值 → `instep<=0; TXSinFt_reg<='1'`（报错回空闲）。

期望大致：`1,0,0,1,0,1,0,1` 再加状态 9 的 `1`。

### 5.3 收数据（状态 10）

```vhdl
indttemp(incount) <= rx_r2;
IF rx_r2='1' THEN evendi <= NOT evendi; END IF;
IF incount>0 THEN incount<=incount-1; ELSE instep<=11; END IF;
```

从高位往低位填满 `DtinN` 位。

### 5.4 校验 + 帧尾（11～21）

- 状态 11：校验位必须等于 `evendi`  
- 12～20：核对帧尾每一位  
- 状态 21 成功：

```vhdl
TXdtIn      <= indttemp;   -- 输出整帧数据
TXSinFt_reg <= '0';        -- 清错误
TXFinish_reg<= '1';        -- 完成脉冲
```

- 状态 22：下一比特时间把 `TXFinish` 清 0，回状态 0  

---

## 6. 和顶层怎么接（对照）

系统侧（ZZ，**424～439**）：

```vhdl
ZZ_COMM: TX_Comm
  GENERIC MAP(DELAY=>20, DtinN=>54, DtOUT=>51)
  PORT MAP(
    RESET=>sig_RES, CLK=>CLKIN, TXclk=>sig_clk20KHz,
    FiberR=>zz_r, TXdtIn=>sig_zzdtin, TXdtOut=>sig_zzdtout,
    FiberT=>sig_zzFiberT, TXSinFt=>sig_zzsinFt, TXFinish=>sig_zzFinish);
zz_t <= NOT sig_zzFiberT;   -- 439 行，板级极性取反！
```

看示波器时：模块内部 `FiberT` 和引脚 `zz_t` **相位相反**。

---

## 7. 时序关系（一张图）

```
sig_clk20KHz  ____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾\____
                 ↑
            顶层装好 TXdtOut
                 ↓
            TX_Comm 发完整帧（很多 bit × 400ns）
                 ↓
            对端收到 → 本模块收齐 → TXFinish 脉冲
                 ↓
            顶层 ZZ_Decodeout / ZC_Decodeout 解码
```

---

## 8. 小白易错点

1. **不是波特率 UART**，是固定 DELAY 计数的比特帧。  
2. **`TXSinFt` 出错后常保持 1**，直到某次成功收帧才清（或复位）。  
3. **收发两个 PROCESS 并行**，一根收一根发，可同时进行。  
4. **顶层对 FiberT 取反**，波形对比要以引脚为准。

---

## 下一篇

`04_ZZ系统通信逐句.md`：顶层如何组 51 位上行帧、如何解码 54 位下行命令。
