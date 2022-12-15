verilator \
-cc -exe --public --trace --savable \
--compiler msvc +define+SIMULATION=1 \
-O3 --x-assign fast --x-initial fast --noassert \
--converge-limit 6000 \
-Wno-fatal \
--top-module top sim.v \
../rtl/Homelab.v \
../rtl/dpram.sv \
../rtl/htpparser.v \
../rtl/tv80/tv80_alu.v \
../rtl/tv80/tv80_core.v \
../rtl/tv80/tv80_mcode.v \
../rtl/tv80/tv80_reg.v \
../rtl/tv80/tv80e.v \
../rtl/tv80/tv80n.v \
../rtl/tv80/tv80s.v
