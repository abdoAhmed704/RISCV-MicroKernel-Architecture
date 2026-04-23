vlib work

vlog *.sv

vsim -voptargs=+acc work.top_tb

add wave *



run -all