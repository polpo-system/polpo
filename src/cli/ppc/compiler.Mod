MODULE compiler;  (** PowerPC: compiler.Compile is the native compiler (see pcompiler) *)
  IMPORT pcompiler;

  PROCEDURE Compile*;
  BEGIN pcompiler.Compile
  END Compile;

  PROCEDURE Help*;
  BEGIN pcompiler.Help
  END Help;

END compiler.
