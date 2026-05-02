# nexys_a7.xdc: constraint file for a7


# clock signal: 100 MHz crystal
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports clk]

# reset: SW0
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports reset]

#option adaptive or normal
set_property -dict {PACKAGE_PIN M13 IOSTANDARD LVCMOS33} [get_ports {sw[0]}] 
set_property -dict {PACKAGE_PIN L16 IOSTANDARD LVCMOS33} [get_ports {sw[1]}]

## pushbuttons: BTNC / BTNU / BTNL / BTNR / BTND
set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33} [get_ports btnc]
set_property -dict {PACKAGE_PIN M18 IOSTANDARD LVCMOS33} [get_ports btnu]
set_property -dict {PACKAGE_PIN P17 IOSTANDARD LVCMOS33} [get_ports btnl]
set_property -dict {PACKAGE_PIN M17 IOSTANDARD LVCMOS33} [get_ports btnr]
set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS33} [get_ports btnd]



##  VGA connector
## red[3:0]
set_property -dict {PACKAGE_PIN A3  IOSTANDARD LVCMOS33} [get_ports {vga_r[0]}]
set_property -dict {PACKAGE_PIN B4  IOSTANDARD LVCMOS33} [get_ports {vga_r[1]}]
set_property -dict {PACKAGE_PIN C5  IOSTANDARD LVCMOS33} [get_ports {vga_r[2]}]
set_property -dict {PACKAGE_PIN A4  IOSTANDARD LVCMOS33} [get_ports {vga_r[3]}]
## green[3:0]
set_property -dict {PACKAGE_PIN C6  IOSTANDARD LVCMOS33} [get_ports {vga_g[0]}]
set_property -dict {PACKAGE_PIN A5  IOSTANDARD LVCMOS33} [get_ports {vga_g[1]}]
set_property -dict {PACKAGE_PIN B6  IOSTANDARD LVCMOS33} [get_ports {vga_g[2]}]
set_property -dict {PACKAGE_PIN A6  IOSTANDARD LVCMOS33} [get_ports {vga_g[3]}]
## blue[3:0]
set_property -dict {PACKAGE_PIN B7  IOSTANDARD LVCMOS33} [get_ports {vga_b[0]}]
set_property -dict {PACKAGE_PIN C7  IOSTANDARD LVCMOS33} [get_ports {vga_b[1]}]
set_property -dict {PACKAGE_PIN D7  IOSTANDARD LVCMOS33} [get_ports {vga_b[2]}]
set_property -dict {PACKAGE_PIN D8  IOSTANDARD LVCMOS33} [get_ports {vga_b[3]}]
## sync
set_property -dict {PACKAGE_PIN B11 IOSTANDARD LVCMOS33} [get_ports vga_hs]
set_property -dict {PACKAGE_PIN B12 IOSTANDARD LVCMOS33} [get_ports vga_vs]

##  7-segment display
## seg[6:0] = {a,b,c,d,e,f,g}, all active LOW
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {seg[0]}] ;# CA
set_property -dict {PACKAGE_PIN R10 IOSTANDARD LVCMOS33} [get_ports {seg[1]}] ;# CB
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports {seg[2]}] ;# CC
set_property -dict {PACKAGE_PIN K13 IOSTANDARD LVCMOS33} [get_ports {seg[3]}] ;# CD
set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS33} [get_ports {seg[4]}] ;# CE
set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVCMOS33} [get_ports {seg[5]}] ;# CF
set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS33} [get_ports {seg[6]}] ;# CG
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports dp]

## an[7:0] - digit anodes, active LOW
set_property -dict {PACKAGE_PIN J17 IOSTANDARD LVCMOS33} [get_ports {an[0]}]
set_property -dict {PACKAGE_PIN J18 IOSTANDARD LVCMOS33} [get_ports {an[1]}]
set_property -dict {PACKAGE_PIN T9  IOSTANDARD LVCMOS33} [get_ports {an[2]}]
set_property -dict {PACKAGE_PIN J14 IOSTANDARD LVCMOS33} [get_ports {an[3]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {an[4]}]
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports {an[5]}]
set_property -dict {PACKAGE_PIN K2  IOSTANDARD LVCMOS33} [get_ports {an[6]}]
set_property -dict {PACKAGE_PIN U13 IOSTANDARD LVCMOS33} [get_ports {an[7]}]

##  configuration / housekeeping
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
