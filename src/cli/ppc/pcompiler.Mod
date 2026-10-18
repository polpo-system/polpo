MODULE pcompiler;  (** command-line compiler for PowerPC (32-bit), see rcompiler *)
  IMPORT rcompiler;

  PROCEDURE Compile*;
  BEGIN
    rcompiler.SetTarget("PPC", "POPV", "ppc", rcompiler.ppctag); rcompiler.CompileTarget
  END Compile;

  PROCEDURE Help*;
  BEGIN rcompiler.Help
  END Help;

END pcompiler.
