MODULE Args;  (** the arguments of the program, with the interface of voc's Args *)

(* For the modules shared with voc. Argument 0 is the program; in loksh Module.Command a b the
  arguments are loksh, Module.Command, a and b, in a program made by program.Make the program
  and its arguments. *)

IMPORT Kernel, Platform;

VAR
  argc*: INTEGER;  (** the number of arguments, the program included *)

(** argument n, or val unchanged when there are fewer *)
PROCEDURE Get*(n: INTEGER; VAR val: ARRAY OF CHAR);
BEGIN
  IF (n >= 0) & (n < argc) THEN Kernel.GetArg(n, val) END
END Get;

(** argument n as a decimal number, with an optional "-"; val unchanged when it has no digits *)
PROCEDURE GetInt*(n: INTEGER; VAR val: LONGINT);
VAR s: ARRAY 64 OF CHAR; k, d, i: LONGINT;
BEGIN
  s := ""; Get(n, s); i := 0;
  IF s[0] = "-" THEN i := 1 END;
  k := 0; d := ORD(s[i]) - ORD("0");
  WHILE (d >= 0) & (d <= 9) DO k := k * 10 + d; INC(i); d := ORD(s[i]) - ORD("0") END;
  IF s[0] = "-" THEN k := -k; DEC(i) END;
  IF i > 0 THEN val := k END
END GetInt;

(** the number of the first argument equal to s, argc when there is none *)
PROCEDURE Pos*(s: ARRAY OF CHAR): INTEGER;
VAR i: INTEGER; arg: ARRAY 256 OF CHAR;
BEGIN
  i := 0; arg := ""; Get(i, arg);
  WHILE (i < argc) & (s # arg) DO INC(i); arg := ""; Get(i, arg) END;
  RETURN i
END Pos;

PROCEDURE GetEnv*(var: ARRAY OF CHAR; VAR val: ARRAY OF CHAR);
BEGIN Platform.GetEnv(var, val)
END GetEnv;

PROCEDURE getEnv*(var: ARRAY OF CHAR; VAR val: ARRAY OF CHAR): BOOLEAN;
BEGIN RETURN Platform.getEnv(var, val)
END getEnv;

BEGIN
  argc := SHORT(Kernel.NoOfArgs)
END Args.
