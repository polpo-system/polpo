# Building polpo

polpo builds itself: each port's `bin/<arch>/loksh` holds its compiler and linker, and the x86
one also holds cross compilers for the other four ports. No C compiler or other toolchain is
needed. This note rebuilds everything from a checkout: the x86 system, the four other ports, and
the installed packages.

## What you need

- Linux on x86 (32-bit code; it runs on x86-64 kernels too), git and make.
- To run or test the other ports on x86: qemu user mode, `qemu-arm` (ARM and ARMv7),
  `qemu-riscv32`, `qemu-mipsel`, `qemu-mips` (big-endian MIPS) and `qemu-ppc`. Building them does not need
  qemu: they are cross compiled.

## The pieces

    bin/<arch>/loksh       the boot image of each port: Kernel, Files, the loader, the shell
    obj/<arch>/            the compiled modules (.Obj code, .Sym interface), loaded on demand
    tools/build.Tool       the x86 recipe; arm.Tool, armv7.Tool, riscv.Tool, mips.Tool, mipsbe.Tool,
                           ppc.Tool the others
    tools/arm-cross.Tool   the x86-hosted ARM cross compiler and linker
    tools/rop2-cross.Tool  the x86-hosted ROP2 cross compilers (ARMv7, RISC-V, MIPS in both byte
                           orders, PowerPC) and linker

A recipe is an Oberon text of commands, one per line: the compilations in the order of the
imports, then the link. `make` and its targets only feed a recipe to a loksh.

## Everything, step by step

From the polpo directory:

```
make > build-x86.log 2>&1                    # the x86 system: links bin/x86/loksh2
cp bin/x86/loksh2 bin/x86/loksh.new && mv bin/x86/loksh.new bin/x86/loksh
make arm   > build-arm.log 2>&1              # ARM (the Oberon-1 compiler, older ARM)
make armv7 > build-armv7.log 2>&1            # ARMv7
make riscv > build-riscv.log 2>&1            # RISC-V (32-bit)
make mips  > build-mips.log 2>&1             # MIPS (32-bit, little-endian)
make mipsbe > build-mipsbe.log 2>&1          # MIPS (32-bit, big-endian)
make ppc   > build-ppc.log 2>&1              # PowerPC (32-bit)
grep -a "err " build-*.log                   # nothing: all compiled
```

- `make` returns success even when a module fails to compile, so look into the logs: a
  compiler error is a line with `err` and its number. (The first line of each log, `module
  not found`, is the binary header of the recipe text; ignore it.)
- The x86 build links `bin/x86/loksh2` and leaves `bin/x86/loksh` alone, because loksh is the
  program running the build; the two commands after it put the new one in place (a plain `cp`
  fails while a loksh runs). The other ports link `bin/<arch>/loksh.new` and move it over.
- Each of `make arm`, `armv7`, `riscv`, `mips`, `mipsbe`, `ppc` first builds its cross compiler on
  x86, then the port. Build ARMv7, RISC-V, the two MIPS ports and PowerPC one after another, never at the same
  time: they all compile the same ROP2 cross compiler into `obj/x86/` first. `make arm` may run
  beside one of them.
- Build x86 first: the cross compilers of the ports run on the x86 system.

## Rebuilding a port with its own compiler

```
make arm-native        # ARM, with the ARM compiler: natively on ARM, on x86 under qemu-arm
make armv7-native
make riscv-native
make mips-native
make mipsbe-native
make ppc-native
```

This is how a port rebuilds itself on its own machine; on x86 it runs under qemu and is slow.
The objects are the same as the cross compiled ones (on MIPS and PowerPC to the byte, the linked
binary too), except that the ARM, ARMv7 and RISC-V
objects can differ in a few bytes of import keys.

## After a rebuild

- **Installed packages**: when the interface of a base module changed, packages compiled
  against the old one no longer load (`key inconsistency` or `imports incompatible version`).
  `portia.Upgrade` compiles them again, on each port, and `portia.Check` must then report 0
  problems:

  ```
  bin/x86/loksh portia.Upgrade /y
  qemu-arm bin/arm/loksh portia.Upgrade /y
  qemu-arm bin/armv7/loksh portia.Upgrade /y
  qemu-riscv32 bin/riscv/loksh portia.Upgrade /y
  qemu-mipsel bin/mips/loksh portia.Upgrade /y
  qemu-mips bin/mipsbe/loksh portia.Upgrade /y
  qemu-ppc bin/ppc/loksh portia.Upgrade /y
  bin/x86/loksh portia.Check                   # and the same on the other ports
  ```

- **Running loksh processes** (a desktop, a shell) keep the modules they loaded before the
  build and load new ones afterwards: restart them.
- **Trying the ports** on x86: `make arm-run` (and `armv7-run`, `riscv-run`, `mips-run`,
  `mipsbe-run`, `ppc-run`)
  starts that port's desktop under qemu, `make arm-shell` its console.

## When something goes wrong

- **A module's interface changed** (a new export; the compiler says `new symbol file`):
  every module importing it must be compiled again, so build the whole system, not one module.
- **The recipe compiles a module without `/s`** (Kernel, Files and Viewers in
  `tools/build.Tool`): that does not write a changed interface. After adding an export to one
  of them, compile it once with `/s` (`bin/x86/loksh compiler.Compile /s src/desktop/Viewers.Mod`),
  then run `make`.
- **loksh cannot load its shell any more** (`shell imports incompatible version of X`, a trap
  at start): a module the shell imports (texts, in, out, strings, Oberon0, ...) was compiled
  alone with a new interface. Take the old object back with `git checkout obj/x86/X.Obj`,
  then run the full build: it compiles X before the shell while loksh keeps its loaded
  modules.
- **X11 or the terminal**: the desktop's Display and Input exist for X11 and for terminals with
  sixel graphics. `make sixel` and `make x11` switch x86 between them, `make arm-sixel` and
  the like the other ports.

## A release

`make release V=1.2.0` writes the version and the date into `VERSION` (the desktop shows it when
it starts), commits it and tags the commit `v1.2.0`; then push the commit and the tag.
