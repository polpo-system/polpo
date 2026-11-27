MODULE ImportsTest;  (** loksh ImportsTest.Run: the variables, procedures and types of a module with more than 256
  exported names (ImportsBase), and deep indexing of its arrays on the heap *)

IMPORT B := ImportsBase, Out;

TYPE
  Item = POINTER TO ItemDesc;
  ItemDesc = RECORD (B.NodeDesc) extra: LONGINT END;
  Fn = PROCEDURE (x: LONGINT): LONGINT;

VAR fails, checks: LONGINT;

PROCEDURE Check(what: ARRAY OF CHAR; ok: BOOLEAN);
BEGIN
  INC(checks);
  IF ~ok THEN INC(fails); Out.String("FAIL "); Out.String(what); Out.Ln END
END Check;

(* four variables in registers and arrays of another module indexed by their elements, as in TeX: the
  ARMv7 compiler ran out of registers (err 215); it compiles such a module again with fewer register variables *)
PROCEDURE Deep(q: LONGINT): LONGINT;
  VAR p, v, x, y: LONGINT;
BEGIN
  p := q; v := p + 1; x := v + 1; y := x + 1;
  IF B.mem[q+1].int = 1073741824 THEN
    B.mem[q+1].int := B.fi[8+B.pb[B.eq[11338+B.cs-1].hh.rh]].int
  END;
  RETURN p + v + x + y
END Deep;

PROCEDURE Run*;
  VAR it: Item; n: B.Node; f: Fn; old: LONGINT;
BEGIN
  fails := 0; checks := 0;
  Check("the first variable", B.v0 = 0);
  Check("the 256th", B.v255 = 255);
  Check("the 257th", B.v256 = 256);
  Check("the last", B.v299 = 299);
  old := B.v299; B.v299 := 7; Check("the last, set here and read by its module", B.Last() = 7); B.v299 := old;
  Check("a procedure with an entry above 255", B.Twice(21) = 42);
  f := B.Twice; Check("the procedure as a value", f(5) = 10);
  NEW(it); it.value := 3; it.extra := 4; n := it;
  Check("an extension of a record type with an entry above 255", (n IS Item) & (n.value = 3) & (n(Item).extra = 4));
  NEW(n); Check("the record type itself", ~(n IS Item));
  B.cs := -11330; B.eq[7].hh.rh := 2; B.pb[2] := 3; B.fi[11].int := 77; B.mem[2].int := 1073741824;
  Check("deep indexing of arrays of another module", (Deep(1) = 10) & (B.mem[2].int = 77));
  Out.String("ImportsTest: "); Out.Int(checks, 0); Out.String(" checks, "); Out.Int(fails, 0); Out.String(" failed"); Out.Ln
END Run;

END ImportsTest.
