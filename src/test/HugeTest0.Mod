MODULE HugeTest0;  (* exports for HugeTest: HUGEINT through a symbol file *)

CONST
  Big* = 1234567890123456789;
  Small* = -5000000000;

TYPE
  Fn* = PROCEDURE (x: HUGEINT): HUGEINT;
  Pair* = RECORD c*: CHAR; h*: HUGEINT END;

VAR
  h*: HUGEINT;
  twice*: Fn;

PROCEDURE Twice*(x: HUGEINT): HUGEINT;
BEGIN RETURN x + x
END Twice;

(* n! *)
PROCEDURE Fact*(n: LONGINT): HUGEINT;
BEGIN
  IF n <= 1 THEN RETURN 1 ELSE RETURN n * Fact(n - 1) END
END Fact;

PROCEDURE Swap*(VAR p: Pair; x: HUGEINT): HUGEINT;
VAR t: HUGEINT;
BEGIN t := p.h; p.h := x; RETURN t
END Swap;

BEGIN h := Small; twice := Twice
END HugeTest0.
