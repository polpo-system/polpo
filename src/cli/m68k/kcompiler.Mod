MODULE kcompiler;  (** command-line compiler for the 68020 and later, with an FPU, see rcompiler *)
  IMPORT rcompiler, KOPL;

  PROCEDURE Compile*;
  BEGIN
    rcompiler.SetTarget("M68K", "KOPV", "m68k", 0F6X); rcompiler.CompileTarget
  END Compile;

  PROCEDURE Dump*;  (** from now on also the code of each module into <module>.code (big-endian) *)
  BEGIN KOPL.dump := TRUE
  END Dump;

  PROCEDURE Help*;
  BEGIN rcompiler.Help
  END Help;

END kcompiler.
