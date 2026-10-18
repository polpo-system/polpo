MODULE mbcompiler;  (** command-line compiler for MIPS big-endian, see rcompiler *)
  IMPORT rcompiler;

  PROCEDURE Compile*;
  BEGIN
    rcompiler.SetTarget("MIPSBE", "MOPV", "mipsbe", rcompiler.mipsbetag); rcompiler.CompileTarget
  END Compile;

  PROCEDURE Help*;
  BEGIN rcompiler.Help
  END Help;

END mbcompiler.
