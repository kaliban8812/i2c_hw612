library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity tb_i2c is
end entity tb_i2c;

architecture tb of tb_i2c is

    component i2c
        port (
            clk       : in std_logic;
            rst       : in std_logic;
            run_stb   : in std_logic;
            wr_bit    : in std_logic;                    -- write 0, read 1
            chip_addr : in std_logic_vector(6 downto 0); -- 6 bit of slave addres
            reg_addr  : in std_logic_vector(6 downto 0); -- 6 bit of regiter addres
            data_in   : in std_logic_vector(7 downto 0); -- 7 bit of data
            rdy_stb   : out std_logic;
            data_out  : out std_logic_vector(15 downto 0); -- two byte back
            scl       : inout std_logic;
            sda       : inout std_logic
        );
    end component i2c;

    signal clk       : std_logic := '0';
    signal rst       : std_logic;
    signal run_stb   : std_logic;
    signal wr_bit    : std_logic;                    -- write 0, read 1
    signal chip_addr : std_logic_vector(6 downto 0); -- 6 bit of slave addres
    signal reg_addr  : std_logic_vector(6 downto 0); -- 6 bit of regiter addres
    signal data_in   : std_logic_vector(7 downto 0); -- 7 bit of data
    signal rdy_stb   : std_logic;
    signal data_out  : std_logic_vector(15 downto 0); -- two byte back
    signal scl       : std_logic;
    signal sda       : std_logic := 'Z';

    constant CLK_PER : time := 20 ns;

    constant TEST_SLAVE_ADDR : std_logic_vector(6 downto 0) := "1010101";
    constant TEST_REG_ADDR   : std_logic_vector(6 downto 0) := "1110000";
    constant TEST_DATA       : std_logic_vector(7 downto 0) := "11110000";
    constant SENSOR_DATA_1   : std_logic_vector(7 downto 0) := "01110001";
    constant SENSOR_DATA_2   : std_logic_vector(7 downto 0) := "11001010";

    signal act_start : boolean := true;

    signal act_recieve_slave_outside : boolean := false;
    signal act_recieve_slave_inner   : boolean := true;
    --
    type fsm_statetype is (fsm_state_start, fsm_state_proove, fsm_state_recieve_slave, fsm_state_buf_send,
        fsm_state_stop, fsm_state_answer, fsm_state_master_not_ans, fsm_state_choose,
        fsm_state_start_2, fsm_state_send_data, fsm_state_send_data_2, fsm_state_master_ans); --, fsm_state_start_2); -- fsm
    signal fsm               : fsm_statetype := fsm_state_start;                          -- fsm
    signal sda_prev          : std_logic;
    signal scl_prev          : std_logic;
    signal recieved_data     : std_logic_vector(7 downto 0);
    signal bit_cnt           : integer range 0 to 7 := 7;
    signal recieved_data_cnt : integer range 0 to 4 := 0;
    signal read_detection    : boolean              := false;
begin
    -- clk gen
    clk <= not clk after CLK_PER / 2;

    sda <= 'H';
    scl <= 'H';

    IM_PROC : process -- INPUT_MASTER_TEST_DATA
    begin
        rst <= '0';
        wait for 10 * CLK_PER;
        rst <= '0';
        wait for 10 * CLK_PER;
        wr_bit    <= '1';
        chip_addr <= TEST_SLAVE_ADDR;
        reg_addr  <= TEST_REG_ADDR;
        data_in   <= TEST_DATA;
        run_stb   <= '1';
        wait for 1 * CLK_PER;
        run_stb <= '0';
        wait for 200 us;
        -- wr_bit    <= '1';
        -- chip_addr <= TEST_SLAVE_ADDR;
        -- reg_addr  <= TEST_REG_ADDR;
        -- data_in   <= TEST_DATA;
        -- run_stb   <= '1';
        -- wait for 1 * CLK_PER;
        -- run_stb <= '0';
        -- wait for 100 us;

        report "[INFO] : End simulation" severity failure;
    end process IM_PROC;

    RDY_PROC : process
    begin
        if rdy_stb = '1' then
            if (data_out and 16x"FFFF") = SENSOR_DATA_1 & SENSOR_DATA_2 then
                report "[DATA_OUT] - SUCCESS";
            else
                report "[DATA_OUT] - ERROR";
            end if;
        end if;
        wait for CLK_PER;
    end process RDY_PROC;

    MAIN_PROC : process
    begin
        sda_prev <= sda;
        scl_prev <= scl;
        case fsm is
            when fsm_state_start =>
                if scl = 'H' and sda_prev = 'H' and sda = '0' then
                    fsm               <= fsm_state_recieve_slave;
                    bit_cnt           <= 7;
                    read_detection    <= false;
                    recieved_data_cnt <= 0;
                    report "[START_DETECTED]";
                end if;

            when fsm_state_recieve_slave =>
                if scl_prev = '0' and scl = 'H' then
                    if bit_cnt = 0 then
                        bit_cnt <= 7;
                        fsm     <= fsm_state_proove;
                    else
                        bit_cnt <= bit_cnt - 1;
                    end if;
                    recieved_data(bit_cnt) <= sda;
                end if;

            when fsm_state_proove =>
                if recieved_data_cnt = 0 then
                    if (recieved_data and 8x"FF") = TEST_SLAVE_ADDR & '0' then
                        report "[TEST_SLAVE_ADDR] : SUCCESS ";
                    else
                        report "[TEST_SLAVE_ADDR] : ERROR ";
                    end if;
                elsif recieved_data_cnt = 1 then
                    if (recieved_data and 8x"FF") = TEST_REG_ADDR & '0' then
                        report "[TEST_REG_ADDR] : SUCCESS ";
                    else
                        report "[TEST_REG_ADDR] : ERROR ";
                    end if;
                elsif recieved_data_cnt = 2 then
                    if (recieved_data and 8x"FF") = TEST_DATA then
                        report "[TEST_DATA] : SUCCESS ";
                    else
                        report "[TEST_DATA] : ERROR ";
                    end if;
                elsif recieved_data_cnt = 3 then
                    if (recieved_data and 8x"FF") = TEST_SLAVE_ADDR & wr_bit then
                        report "[TEST_SLAVE_ADDR] : SUCCESS ";
                    else
                        report "[TEST_SLAVE_ADDR] : ERROR ";
                    end if;
                end if;
                fsm <= fsm_state_answer;

            when fsm_state_stop =>
                if sda_prev = '0' and sda = 'H' then
                    if scl = 'H' then
                        report "[STOP_DETECTED]";
                        fsm <= fsm_state_start;
                    else
                        report "[STOP_ERROR] : End simulation" severity failure;
                    end if;
                end if;

            when fsm_state_answer =>
                if scl_prev = 'H' and scl = '0' then
                    wait for 10 ns;
                    sda <= '0';
                elsif scl_prev = '0' and scl = 'H' then
                    wait for 10 ns;
                    sda <= 'Z';
                    fsm <= fsm_state_choose;
                end if;

            when fsm_state_choose =>
                if recieved_data_cnt = 2 and wr_bit = '0' then
                    fsm <= fsm_state_stop;
                elsif recieved_data_cnt = 1 and wr_bit = '1' then
                    fsm <= fsm_state_start_2;
                else
                    if read_detection = true then
                        fsm <= fsm_state_send_data;
                    else
                        fsm <= fsm_state_recieve_slave;
                    end if;
                end if;
                if recieved_data_cnt < 3 then
                    recieved_data_cnt <= recieved_data_cnt + 1;
                end if;

            when fsm_state_start_2 =>
                if scl = 'H' and sda_prev = 'H' and sda = '0' then
                    fsm               <= fsm_state_recieve_slave;
                    read_detection    <= true;
                    recieved_data_cnt <= recieved_data_cnt + 1;
                end if;

            when fsm_state_send_data =>
                if scl_prev = 'H' and scl = '0' then
                    if bit_cnt = 0 then
                        bit_cnt <= 7;
                        fsm     <= fsm_state_buf_send;
                    else
                        bit_cnt <= bit_cnt - 1;
                    end if;
                    if SENSOR_DATA_1(bit_cnt) = '0' then
                        sda <= '0';
                    else
                        sda <= 'Z';
                    end if;
                end if;

            when fsm_state_buf_send =>
                if scl_prev = '0' and scl = 'H' then
                    fsm <= fsm_state_master_ans;
                    sda <= 'Z';
                end if;

            when fsm_state_master_ans =>
                if scl_prev = '0' and scl = 'H' then
                    if sda = '0' then
                        fsm <= fsm_state_send_data_2;
                    else
                        report "[ERROR] : End simulation" severity failure;
                    end if;
                end if;

            when fsm_state_send_data_2 =>
                if scl_prev = 'H' and scl = '0' then
                    if bit_cnt = 0 then
                        bit_cnt <= 7;
                        fsm     <= fsm_state_master_ans;
                    else
                        bit_cnt <= bit_cnt - 1;
                    end if;
                    if SENSOR_DATA_2(bit_cnt) = '0' then
                        sda <= '0';
                    else
                        sda <= 'Z';
                    end if;
                end if;

            when fsm_state_master_not_ans =>
                if scl_prev = '0' and scl = 'H' then
                    if sda = 'H' then
                        fsm <= fsm_state_stop;
                    else
                        report "[ERROR] : End simulation" severity failure;
                    end if;
                end if;
        end case;
        wait for 1 ns;
    end process MAIN_PROC;

    -- components
    dut : i2c
    port map(
        clk       => clk,
        rst       => rst,
        run_stb   => run_stb,
        wr_bit    => wr_bit,
        chip_addr => chip_addr,
        reg_addr  => reg_addr,
        data_in   => data_in,
        rdy_stb   => rdy_stb,
        data_out  => data_out,
        scl       => scl,
        sda       => sda
    );

end architecture tb;