set BIT_FILE "E:/Everything_with_VIVADO/GEMM_final_DSP/GEMM_final_DSP.runs/impl_1/GEMM_DSP_BD_wrapper.bit"
set PSU_INIT "E:/VITIS_2022/GEMM_final_DSP/hw/psu_init.tcl"
set ELF_FILE "E:/VITIS_2022/GEMM_DSP/Debug/GEMM_DSP.elf"

catch {disconnect}
connect
targets

puts "===== RESET SYSTEM ====="
targets -set -filter {name =~ "PSU"}
rst -system
after 8000

puts "===== PROGRAM FPGA ====="
fpga -file $BIT_FILE
after 3000

puts "===== PSU INIT ====="
source $PSU_INIT
psu_init
after 2000

puts "===== REMOVE PS-PL ISOLATION ====="
catch {psu_ps_pl_isolation_removal}
catch {psu_ps_pl_reset_config}
catch {psu_post_config}
after 2000

puts "===== RESET A53 #0 ====="
targets -set -filter {name =~ "Cortex-A53 #0"}
rst -processor
after 1000

puts "===== DOWNLOAD ELF ====="
dow $ELF_FILE
after 1000

puts "===== RUN APP ====="
con
