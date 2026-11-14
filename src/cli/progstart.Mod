MODULE progstart;  (** the first module of a program made by program.Make *)

(* Its body runs before the bodies of the other modules of the program (they come after it in the
  image) and installs the trap handler of traps: a trap in the program is shown on the standard
  error, as in loksh, and the program ends with exit status 2. *)

IMPORT traps;

BEGIN
  traps.Install
END progstart.
