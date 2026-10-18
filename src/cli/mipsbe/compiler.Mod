MODULE compiler;  (** MIPS big-endian: compiler.Compile is the native compiler (see mbcompiler) *)
  IMPORT mbcompiler;

  PROCEDURE Compile*;
  BEGIN mbcompiler.Compile
  END Compile;

  PROCEDURE Help*;
  BEGIN mbcompiler.Help
  END Help;

END compiler.
