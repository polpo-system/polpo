# Math and MathL of ETH Oberon, for polpo

`Math` (REAL) and `MathL` (LONGREAL) of Native Oberon 2.3.6: `sin`, `cos`, `arctan`, `sqrt`,
`ln`, `exp`, and the constants `e` and `pi`.

    src/Math.Mod, src/MathL.Mod          portable: the rational approximations of Native
                                         Oberon for machines without a coprocessor
    src/x86/Math.Mod, src/x86/MathL.Mod  x86: the x87 code of Native Oberon (fsin, fyl2x ...)
    test/MathTest.Mod                    MathTest.Run: the functions against known values

Both are generated from the files of Native Oberon: there `Kernel.copro` chose the x87 code
at run time; here the constant `copro` is TRUE in the x86 files, and the portable files have
the x87 procedures and the branches using them removed. The interface is the same.

The portable code builds floating point numbers with SYSTEM (exponent bits of IEEE single
and double): it assumes little-endian machines, which all polpo architectures are.

On x86 the x87 versions are about 25% faster (2 million sin, exp and sqrt of MathL: 0.44 s
against 0.57 s); the results agree to the precision checked by MathTest (1E-5 for REAL,
1E-10 for LONGREAL).

Install with portia: `portia.Install math` (the x86 files on x86, the portable ones on ARM,
ARMv7, RISC-V and MIPS); `portia.Test math`.

The license is GPL-3 (`LICENSE`); the code comes from ETH Oberon, whose license (`LICENSE.ETH`)
asks to keep its copyright notice and conditions, which `LICENSE.ETH` does.
