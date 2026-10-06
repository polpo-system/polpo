
# x86 host: bin/x86/loksh.  ARM: bin/arm/loksh, run through qemu-arm unless
# this machine is ARM.

X86 = bin/x86/loksh

HOSTARCH := $(shell uname -m)
ifneq ($(filter arm% aarch64,$(HOSTARCH)),)
ARM = bin/arm/loksh
ACOMPILE = $(ARM) compiler.Compile
APORTIA = $(ARM) portia.Build
ARMV7 = bin/armv7/loksh
else
ARM = qemu-arm bin/arm/loksh
ACOMPILE = $(X86) acompiler.Compile
APORTIA = $(X86) portia.Build /arm
ARMV7 = qemu-arm bin/armv7/loksh
endif

ifneq ($(filter riscv32,$(HOSTARCH)),)
RISCV = bin/riscv/loksh
else
RISCV = qemu-riscv32 bin/riscv/loksh
endif

ifneq ($(filter mips,$(HOSTARCH)),)
MIPS = bin/mips/loksh
else
MIPS = qemu-mipsel bin/mips/loksh
endif

# ---- x86 ----

fast:
		$(X86) < tools/build.Tool

# the Display and Input of the desktop: xterm sixel or X11, the packages display-sixel and
# display-x11; portia builds the one asked for, replaces the other and records it
#sixel:
#		$(X86) compiler.Compile /x src/desktop/POLPO.SXL.Display.Mod
#		$(X86) compiler.Compile /s src/desktop/POLPO.SXL.Input.Mod
#
#x11:
#		$(X86) compiler.Compile /x src/desktop/POLPO.Display.Mod
#		$(X86) compiler.Compile /s src/desktop/POLPO.Input.Mod

sixel:
		$(X86) portia.Build /y display-sixel

x11:
		$(X86) portia.Build /y display-x11

# ---- ARM ----

# cross compile the ARM system on x86
arm:
		$(X86) < tools/arm-cross.Tool
		$(X86) < tools/arm.Tool
		mv bin/arm/loksh.new bin/arm/loksh

# build the ARM system with the ARM compiler: natively on ARM, under qemu-arm elsewhere
arm-native:
		$(ARM) < tools/arm.Tool
		mv bin/arm/loksh.new bin/arm/loksh

# start the ARM desktop / console
arm-run:
		$(ARM) System.Init

arm-shell:
		$(ARM)

# select the ARM Display and Input: xterm sixel or X11 (portia: natively on ARM, cross on x86)
#arm-sixel:
#		$(ACOMPILE) /x src/desktop/POLPO.SXL.Display.Mod
#		$(ACOMPILE) /s src/desktop/POLPO.SXL.Input.Mod
#
#arm-x11:
#		$(ACOMPILE) /x src/desktop/POLPO.Display.Mod
#		$(ACOMPILE) /s src/desktop/POLPO.Input.Mod

arm-sixel:
		$(APORTIA) /y display-sixel

arm-x11:
		$(APORTIA) /y display-x11

# ---- RISC-V (RV32) ----

# cross compile the RISC-V system on x86
riscv:
		$(X86) < tools/rop2-cross.Tool
		$(X86) < tools/riscv.Tool
		mv bin/riscv/loksh.new bin/riscv/loksh

# build the RISC-V system with the RISC-V compiler: natively on RV32, under qemu-riscv32 elsewhere
riscv-native:
		$(RISCV) < tools/riscv.Tool
		mv bin/riscv/loksh.new bin/riscv/loksh

# start the RISC-V desktop / console (qemu-riscv32 unless this machine is RV32)
riscv-run:
		$(RISCV) System.Init

riscv-shell:
		$(RISCV)

# select the Display and Input: xterm sixel or X11 (portia, cross on x86)
riscv-sixel:
		$(X86) portia.Build /riscv /y display-sixel

riscv-x11:
		$(X86) portia.Build /riscv /y display-x11

# ---- MIPS (32-bit little-endian) ----

# cross compile the MIPS system on x86
mips:
		$(X86) < tools/rop2-cross.Tool
		$(X86) < tools/mips.Tool
		mv bin/mips/loksh.new bin/mips/loksh

# build the MIPS system with the MIPS compiler: natively on MIPS, under qemu-mipsel elsewhere
mips-native:
		$(MIPS) < tools/mips.Tool
		mv bin/mips/loksh.new bin/mips/loksh

# start the MIPS desktop / console (qemu-mipsel unless this machine is MIPS)
mips-run:
		$(MIPS) System.Init

mips-shell:
		$(MIPS)

# select the Display and Input: xterm sixel or X11 (portia, cross on x86)
mips-sixel:
		$(X86) portia.Build /mips /y display-sixel

mips-x11:
		$(X86) portia.Build /mips /y display-x11

# ---- ARMv7 (OP2 compiler; make arm is for older ARM processors) ----

# cross compile the ARMv7 system on x86
armv7:
		$(X86) < tools/rop2-cross.Tool
		$(X86) < tools/armv7.Tool
		mv bin/armv7/loksh.new bin/armv7/loksh

# build the ARMv7 system with the ARMv7 compiler: natively on ARM, under qemu-arm elsewhere
armv7-native:
		$(ARMV7) < tools/armv7.Tool
		mv bin/armv7/loksh.new bin/armv7/loksh

# start the ARMv7 desktop / console (qemu-arm unless this machine is ARM)
armv7-run:
		$(ARMV7) System.Init

armv7-shell:
		$(ARMV7)

# select the Display and Input: xterm sixel or X11 (portia, cross on x86)
armv7-sixel:
		$(X86) portia.Build /armv7 /y display-sixel

armv7-x11:
		$(X86) portia.Build /armv7 /y display-x11

.PHONY: fast sixel x11 arm arm-native arm-run arm-shell arm-sixel arm-x11 riscv riscv-native riscv-run riscv-shell riscv-sixel riscv-x11 mips mips-native mips-run mips-shell mips-sixel mips-x11 armv7 armv7-native armv7-run armv7-shell armv7-sixel armv7-x11
