MODULE compiler;  (** 68020: compiler.Compile is the native compiler (see kcompiler) *)
  IMPORT kcompiler;

  PROCEDURE Compile*;
  BEGIN kcompiler.Compile
  END Compile;

  PROCEDURE Help*;
  BEGIN kcompiler.Help
  END Help;

END compiler.
