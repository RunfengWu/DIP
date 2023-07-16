onbreak {quit -f}
onerror {quit -f}

vsim -voptargs="+acc" -t 1ps -L xil_defaultlib -L xpm -L fifo_generator_v13_2_3 -L unisims_ver -L unimacro_ver -L secureip -lib xil_defaultlib xil_defaultlib.async_fifo_1024x32b xil_defaultlib.glbl

do {wave.do}

view wave
view structure
view signals

do {async_fifo_1024x32b.udo}

run -all

quit -force
