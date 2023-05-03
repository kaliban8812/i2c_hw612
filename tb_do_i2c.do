transcript on

vlib work

vcom -2008 -work work E:/YandexDisk/Prog/projects/i2c/i2c.vhd
vcom -2008 -work work E:/YandexDisk/Prog/projects/i2c/tb_i2c.vhd

vsim work.tb_i2c

add wave -position end  sim:/tb_i2c/clk      
add wave -position end  sim:/tb_i2c/rst      
add wave -position end  sim:/tb_i2c/run_stb  
add wave -position end  sim:/tb_i2c/wr_bit   
add wave -position end  sim:/tb_i2c/chip_addr
add wave -position end  sim:/tb_i2c/reg_addr 
add wave -position end  sim:/tb_i2c/data_in  
add wave -position end  sim:/tb_i2c/rdy_stb  
add wave -position end  sim:/tb_i2c/data_out 
add wave -position end  sim:/tb_i2c/scl      
add wave -position end  sim:/tb_i2c/sda   

add wave -position end  sim:/tb_i2c/dut/i2c_fsm       
add wave -position end  sim:/tb_i2c/dut/i2c_clk_en
add wave -position end  sim:/tb_i2c/dut/i2c_data_array
add wave -position end  sim:/tb_i2c/dut/i2c_array_cnt
add wave -position end  sim:/tb_i2c/dut/i2c_bit_cnt
add wave -position end  sim:/tb_i2c/dut/i2c_fe_pointer
add wave -position end  sim:/tb_i2c/dut/error_detected
add wave -position end  sim:/tb_i2c/fsm

add wave -position end  sim:/tb_i2c/dut/clk_stb

run -all
wave zoom full