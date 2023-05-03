-- Filename     : protocol.vhd
-- Author       : Vladimir Lavrov
-- Date         : 21.09.2020
-- Annotation   : i2c for hw-612 1 Mhz
-- Version      : 0.1
-- Mod.Data     : 21.09.2020
-- Note         : use 1 Mhz for both chips
-- x0 - acc_X; x1 - acc_Y; x2 - acc_Z;
-- x3 - gyr_X; x4 - gyr_Y; x5 - gyr_Z;
-- x6 - temp; 
-- x7 - mag_X; x8 - mag_Y; x9 - mag_Z;
------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity i2c is
    port (
        clk : in std_logic;
        rst : in std_logic;

        run_stb : in std_logic;
        sensor  : in std_logic_vector(3 downto 0);

        rdy_stb  : out std_logic;
        data_out : out std_logic_vector(15 downto 0); -- two byte back
        busy     : out std_logic;
        sao      : out std_logic;

        scl : inout std_logic;
        sda : inout std_logic
    );
end entity i2c;

architecture rtl of i2c is

    -- clk  
    constant CLK_CONST : integer := 63;--124;               -- 50MHz/((CLK_CONST+1)*4)= 100 КHz 
    signal clk_stb     : std_logic;                    -- two strobs re and fe
    signal clk_cnt     : integer range 0 to CLK_CONST; -- counter for clk divider

    --i2c_
    type i2c_fsm_statetype is (
        i2c_state_idle, i2c_state_start, i2c_state_write, i2c_state_ask,
        i2c_state_read, i2c_state_response, i2c_state_not_response, i2c_state_stop); -- fsm
    signal i2c_fsm        : i2c_fsm_statetype := i2c_state_idle;
    signal i2c_clk_en     : std_logic;
    constant I2C_BIT_MAX  : integer := 7;
    constant I2C_DATA_MAX : integer := 2;
    type i2c_data_array_type is array (0 to I2C_DATA_MAX) of std_logic_vector(I2C_BIT_MAX downto 0);
    signal i2c_data_array  : i2c_data_array_type;
    signal i2c_array_cnt   : integer range 0 to I2C_DATA_MAX;
    signal i2c_bit_cnt     : integer range 0 to I2C_BIT_MAX;
    signal i2c_scl_pointer : boolean := false;
    signal i2c_sda_pointer : boolean := true;
    signal error_detected  : std_logic;
    constant I2C_WRITE_BIT : std_logic := '0';
    constant I2C_READ_BIT  : std_logic := '1';
    signal i2c_rdy_mgr_stb : std_logic;
    -- mgr
    signal mgr_write_not_read : std_logic;                    -- write 0, read 1
    signal mgr_chip_addr      : std_logic_vector(6 downto 0); -- 7 bit of slave addres
    signal mgr_reg_addr       : std_logic_vector(6 downto 0); -- 7 bit of regiter addres
    signal mgr_data_in        : std_logic_vector(7 downto 0); -- 8 bit of data
    signal mgr_run_i2c_stb    : std_logic;
    type mgr_fsm_statetype is (mgr_state_ini, mgr_state_idle, mgr_state_wait); -- fsm
    signal mgr_fsm : mgr_fsm_statetype := mgr_state_ini;
    -- registers and addresses
    constant ID_MPU_9250   : std_logic_vector(6 downto 0) := 7x"68";
    constant ADDR_ACL_X_H  : std_logic_vector(6 downto 0) := 7x"3B";
    constant ADDR_ACL_Y_H  : std_logic_vector(6 downto 0) := 7x"3D";
    constant ADDR_ACL_Z_H  : std_logic_vector(6 downto 0) := 7x"3F";
    constant ADDR_GYR_X_H  : std_logic_vector(6 downto 0) := 7x"43";
    constant ADDR_GYR_Y_H  : std_logic_vector(6 downto 0) := 7x"45";
    constant ADDR_GYR_Z_H  : std_logic_vector(6 downto 0) := 7x"47";
    constant ADDR_TEMP_H   : std_logic_vector(6 downto 0) := 7x"41";
    constant COMMAND_BLANK : std_logic_vector(7 downto 0) := 8x"00";
    type mgr_state_ini_type is array (natural range <>) of std_logic_vector(22 downto 0);
    constant MGR_INI_ADDR : mgr_state_ini_type := (
    I2C_READ_BIT & ID_MPU_9250 & 7x"75" & COMMAND_BLANK,
    I2C_READ_BIT & ID_MPU_9250 & 7x"75" & COMMAND_BLANK
    );
    signal mgr_ini_cnt   : integer range 0 to (MGR_INI_ADDR'LENGTH - 1) := 0;
    signal mgr_first_act : boolean                                      := true;

begin

    sao <= '0';

    MGR_PROC : process (clk, rst)
    begin
        if rst = '0' then -- не забыть поменять
            mgr_fsm       <= mgr_state_ini;
            mgr_first_act <= true;
            mgr_ini_cnt   <= 0;
            busy          <= '1';
            rdy_stb       <= '0';
        elsif rising_edge(clk) then
            case mgr_fsm is
                when mgr_state_ini =>
                    if mgr_first_act then
                        mgr_run_i2c_stb    <= '1';
                        mgr_first_act      <= false;
                        busy               <= '1';
                        mgr_write_not_read <= MGR_INI_ADDR(mgr_ini_cnt)(22);
                        mgr_chip_addr      <= MGR_INI_ADDR(mgr_ini_cnt)(21 downto 15);
                        mgr_reg_addr       <= MGR_INI_ADDR(mgr_ini_cnt)(14 downto 8);
                        mgr_data_in        <= MGR_INI_ADDR(mgr_ini_cnt)(7 downto 0);
                    else
                        mgr_run_i2c_stb <= '0';
                        if i2c_rdy_mgr_stb = '1' then
                            if mgr_ini_cnt = MGR_INI_ADDR'LENGTH - 1 then
                                mgr_fsm <= mgr_state_idle;
                            else
                                mgr_ini_cnt <= mgr_ini_cnt + 1;
                            end if;
                            mgr_first_act <= true;
                        end if;
                    end if;

                when mgr_state_idle =>
                    if mgr_first_act then
                        rdy_stb <= '0';
                        busy    <= '0';
                        if run_stb = '1' then
                            mgr_run_i2c_stb    <= '1';
                            mgr_first_act      <= false;
                            busy               <= '1';
                            mgr_write_not_read <= I2C_READ_BIT;
                            case sensor is
                                when 4x"0" =>
                                    mgr_chip_addr <= ID_MPU_9250;
                                    mgr_reg_addr  <= ADDR_ACL_X_H;
                                when 4x"1" =>
                                    mgr_chip_addr <= ID_MPU_9250;
                                    mgr_reg_addr  <= ADDR_ACL_Y_H;
                                when 4x"2" =>
                                    mgr_chip_addr <= ID_MPU_9250;
                                    mgr_reg_addr  <= ADDR_ACL_Z_H;
                                when 4x"3" =>
                                    mgr_chip_addr <= ID_MPU_9250;
                                    mgr_reg_addr  <= ADDR_GYR_X_H;
                                when 4x"4" =>
                                    mgr_chip_addr <= ID_MPU_9250;
                                    mgr_reg_addr  <= ADDR_GYR_Y_H;
                                when 4x"5" =>
                                    mgr_chip_addr <= ID_MPU_9250;
                                    mgr_reg_addr  <= ADDR_GYR_Z_H;
                                when 4x"6" =>
                                    mgr_chip_addr <= ID_MPU_9250;
                                    mgr_reg_addr  <= ADDR_TEMP_H;
                                when 4x"7" =>
                                    mgr_chip_addr <= ID_MPU_9250;
                                    mgr_reg_addr  <= ADDR_TEMP_H;
                                when 4x"8" =>
                                    mgr_chip_addr <= ID_MPU_9250;
                                    mgr_reg_addr  <= ADDR_TEMP_H;
                                when 4x"9" =>
                                    mgr_chip_addr <= ID_MPU_9250;
                                    mgr_reg_addr  <= ADDR_TEMP_H;
                                when others =>
                                    mgr_chip_addr <= ID_MPU_9250;
                                    mgr_reg_addr  <= ADDR_TEMP_H;
                            end case;
                        end if;
                    else
                        if i2c_rdy_mgr_stb = '1' then
                            mgr_first_act <= true;
                            rdy_stb       <= '1';
                        end if;
                    end if;

                when others =>
            end case;
        end if;
    end process MGR_PROC;

    I2C_PROC : process (clk, rst)
    begin
        if rst = '0' then -- не забыть поменять
            i2c_fsm        <= i2c_state_idle;
            i2c_clk_en     <= '0';
            scl            <= 'Z';
            sda            <= 'Z';
            error_detected <= '0';
        elsif rising_edge(clk) then
            case i2c_fsm is

                when i2c_state_idle =>
                    if mgr_run_i2c_stb = '1' then
                        i2c_fsm           <= i2c_state_start;
                        i2c_clk_en        <= '1';
                        i2c_data_array(0) <= mgr_chip_addr & I2C_WRITE_BIT;
                        i2c_data_array(1) <= mgr_reg_addr & I2C_WRITE_BIT;
                        i2c_bit_cnt       <= I2C_BIT_MAX;
                        i2c_array_cnt     <= 0;
                        i2c_scl_pointer   <= true;
                        i2c_sda_pointer   <= false;
                        if mgr_write_not_read = '0' then
                            i2c_data_array(2) <= mgr_data_in;
                        else
                            i2c_data_array(2) <= mgr_chip_addr & I2C_READ_BIT;
                        end if;
                    else
                        i2c_clk_en <= '0';
                    end if;
                    scl             <= 'Z';
                    sda             <= 'Z';
                    error_detected  <= '0';
                    i2c_rdy_mgr_stb <= '0';

                when i2c_state_start =>
                    if clk_stb = '1' then
                        sda     <= '0';
                        i2c_fsm <= i2c_state_write;
                    end if;

                when i2c_state_write =>
                    if clk_stb = '1' then
                        if i2c_scl_pointer then
                            if i2c_sda_pointer then
                                i2c_scl_pointer <= false;
                                i2c_sda_pointer <= false;
                                if i2c_data_array(i2c_array_cnt)(i2c_bit_cnt) = '0' then
                                    sda <= '0';
                                else
                                    sda <= 'Z';
                                end if;
                            else
                                scl             <= '0';
                                i2c_sda_pointer <= true;
                            end if;
                        else
                            if i2c_sda_pointer then
                                i2c_scl_pointer <= true;
                                i2c_sda_pointer <= false;
                                if i2c_bit_cnt = 0 then
                                    i2c_bit_cnt <= I2C_BIT_MAX;
                                    i2c_fsm     <= i2c_state_ask;
                                else
                                    i2c_bit_cnt <= i2c_bit_cnt - 1;
                                end if;
                            else
                                scl             <= 'Z';
                                i2c_sda_pointer <= true;
                            end if;
                        end if;
                    end if;

                when i2c_state_ask =>
                    if clk_stb = '1' then
                        if i2c_scl_pointer then
                            if i2c_sda_pointer then
                                sda             <= 'Z';
                                i2c_scl_pointer <= false;
                                i2c_sda_pointer <= false;
                            else
                                scl             <= '0';
                                i2c_sda_pointer <= true;
                            end if;
                        else
                            if i2c_sda_pointer then
                                i2c_scl_pointer <= true;
                                i2c_sda_pointer <= false;
                                if i2c_array_cnt = I2C_DATA_MAX then
                                    i2c_array_cnt <= 0;
                                    if i2c_data_array(2)(0) = I2C_WRITE_BIT then
                                        i2c_fsm <= i2c_state_stop;
                                    else
                                        i2c_fsm <= i2c_state_read;
                                    end if;
                                elsif i2c_array_cnt = I2C_DATA_MAX - 1 and i2c_data_array(2)(0) = I2C_READ_BIT then
                                    i2c_fsm       <= i2c_state_start;
                                    i2c_array_cnt <= i2c_array_cnt + 1;
                                else
                                    i2c_fsm       <= i2c_state_write;
                                    i2c_array_cnt <= i2c_array_cnt + 1;
                                end if;
                            else
                                scl <= 'Z';
                                if sda = '0' then
                                    i2c_sda_pointer <= true;
                                else
                                    error_detected <= '1';
                                    i2c_fsm        <= i2c_state_idle;
                                end if;
                            end if;
                        end if;
                    end if;

                when i2c_state_read =>
                    if clk_stb = '1' then
                        if i2c_scl_pointer then
                            if i2c_sda_pointer then
                                i2c_scl_pointer <= false;
                                i2c_sda_pointer <= false;
                            else
                                scl             <= '0';
                                sda             <= 'Z';
                                i2c_sda_pointer <= true;
                            end if;
                        else
                            if i2c_sda_pointer then
                                i2c_scl_pointer <= true;
                                if i2c_bit_cnt = 0 then
                                    i2c_bit_cnt <= I2C_BIT_MAX;
                                    if i2c_array_cnt = 1 then
                                        i2c_fsm <= i2c_state_not_response;
                                    else
                                        i2c_fsm <= i2c_state_response;
                                    end if;
                                    i2c_array_cnt <= i2c_array_cnt + 1;
                                else
                                    i2c_bit_cnt <= i2c_bit_cnt - 1;
                                end if;
                            else
                                scl                                        <= 'Z';
                                i2c_data_array(i2c_array_cnt)(i2c_bit_cnt) <= sda;
                                i2c_sda_pointer                            <= true;
                            end if;
                        end if;
                    end if;

                when i2c_state_response =>
                    if clk_stb = '1' then
                        if i2c_scl_pointer then
                            scl             <= '0';
                            sda             <= '0';
                            i2c_scl_pointer <= false;
                        else
                            scl             <= 'Z';
                            i2c_scl_pointer <= true;
                            i2c_fsm         <= i2c_state_read;
                        end if;
                    end if;

                when i2c_state_not_response =>
                    if clk_stb = '1' then
                        if i2c_scl_pointer then
                            scl             <= '0';
                            i2c_scl_pointer <= false;
                        else
                            scl             <= 'Z';
                            i2c_scl_pointer <= true;
                            if sda = '0' then
                                error_detected <= '1';
                                i2c_fsm        <= i2c_state_idle;
                            else
                                i2c_fsm <= i2c_state_stop;
                            end if;
                        end if;
                    end if;

                when i2c_state_stop =>
                    if clk_stb = '1' then
                        sda             <= 'Z';
                        i2c_fsm         <= i2c_state_idle;
                        i2c_rdy_mgr_stb <= '1';
                        data_out        <= i2c_data_array(0) & i2c_data_array(1);
                    end if;

                when others =>
                    i2c_fsm <= i2c_state_idle;
            end case;
        end if;
    end process I2C_PROC;
    -- clock divider process 
    CLK_PROC : process (clk, rst)
    begin
        if rst = '0' then -- не забыть поменять
            clk_cnt <= 0;
            clk_stb <= '0';
        elsif rising_edge(clk) then
            if i2c_clk_en = '1' then
                if clk_cnt = CLK_CONST then
                    clk_cnt <= 0;
                    clk_stb <= '1';
                else
                    clk_cnt <= clk_cnt + 1;
                    clk_stb <= '0';
                end if;
            else
                clk_cnt <= 0;
                clk_stb <= '0';
            end if;
        end if;
    end process CLK_PROC;

end architecture rtl;