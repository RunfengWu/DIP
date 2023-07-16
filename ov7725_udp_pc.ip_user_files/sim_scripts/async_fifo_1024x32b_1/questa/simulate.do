onbreak {quit -f}
onerror {quit -f}

vsim -t 1ps -lib xil_defaultlib async_fifo_1024x32b_opt

do {wave.do}

view wave
view structure
view signals

do {async_fifo_1024x32b.udo}

run -all

quit -force
