MODULE TbpTest;  (** TbpTest.Run: type-bound procedures, here and across modules (x86: compile with /2) *)

IMPORT Out, TbpBase;

TYPE
  Circle = POINTER TO CircleDesc;
  CircleDesc = RECORD (TbpBase.ShapeDesc)
    r: LONGINT
  END;

  Cube = POINTER TO CubeDesc;
  CubeDesc = RECORD (TbpBase.SquareDesc) END;

  Twin = RECORD (TbpBase.Counter)
    adds: LONGINT
  END;

  A = POINTER TO ADesc;
  ADesc = RECORD x: LONGINT END;
  B = POINTER TO BDesc;
  BDesc = RECORD (ADesc) END;
  C = POINTER TO CDesc;
  CDesc = RECORD (BDesc) END;

  Vec = RECORD x, y: REAL END;

VAR fails, checks: LONGINT;

PROCEDURE Check(what: ARRAY OF CHAR; ok: BOOLEAN);
BEGIN
  INC(checks);
  IF ~ok THEN INC(fails); Out.String("FAIL "); Out.String(what); Out.Ln END
END Check;

PROCEDURE (c: Circle) Area*(): LONGINT;
BEGIN INC(c.calls); RETURN 3 * c.r * c.r
END Area;

PROCEDURE (c: Circle) Diameter(): LONGINT;  (* a new method beside the hidden one of the base *)
BEGIN RETURN 2 * c.r
END Diameter;

PROCEDURE (c: Cube) Area*(): LONGINT;
BEGIN RETURN 6 * c.Area^()
END Area;

PROCEDURE (VAR t: Twin) Add*(d: LONGINT);
BEGIN INC(t.adds); t.Add^(d); t.Add^(d)
END Add;

PROCEDURE ^ (a: A) Name(VAR s: ARRAY OF CHAR);

PROCEDURE (a: A) Level(): LONGINT;
BEGIN RETURN 1
END Level;

PROCEDURE (a: A) Describe(): LONGINT;  (* uses the forward declared Name and the dynamic Level *)
VAR s: ARRAY 8 OF CHAR;
BEGIN a.Name(s); RETURN 10 * a.Level() + ORD(s[0]) - ORD("a")
END Describe;

PROCEDURE (a: A) Name(VAR s: ARRAY OF CHAR);
BEGIN COPY("a", s)
END Name;

PROCEDURE (b: B) Level(): LONGINT;
BEGIN RETURN 2
END Level;

PROCEDURE (b: B) Name(VAR s: ARRAY OF CHAR);
BEGIN COPY("b", s)
END Name;

PROCEDURE (c: C) Level(): LONGINT;
BEGIN RETURN 1 + c.Level^()
END Level;

PROCEDURE (a: A) Sum(p1, p2, p3, p4, p5, p6, p7, p8: LONGINT): LONGINT;  (* more arguments than registers *)
BEGIN RETURN a.x + p1 + 2*p2 + 3*p3 + 4*p4 + 5*p5 + 6*p6 + 7*p7 + 8*p8
END Sum;

PROCEDURE (VAR v: Vec) Len2(): REAL;
BEGIN RETURN v.x * v.x + v.y * v.y
END Len2;

PROCEDURE (VAR v: Vec) Scale(f: REAL);
BEGIN v.x := v.x * f; v.y := v.y * f
END Scale;

PROCEDURE (c: Circle) Grow;  (* without a parameter list *)
BEGIN INC(c.r)
END Grow;

PROCEDURE (VAR v: Vec) Zero;
BEGIN v.x := 0.0; v.y := 0.0
END Zero;

PROCEDURE AddVia(VAR c: TbpBase.Counter; d: LONGINT);  (* the dynamic type comes with the VAR record *)
BEGIN c.Add(d)
END AddVia;

PROCEDURE Run*;
VAR s: TbpBase.Shape; sq: TbpBase.Square; ci: Circle; cu: Cube; t: Twin; k: TbpBase.Counter;
  a: A; b: B; c: C; pa: POINTER TO Vec; v: Vec; shapes: ARRAY 3 OF TbpBase.Shape; i, sum: LONGINT;
BEGIN
  fails := 0; checks := 0;
  sq := TbpBase.NewSquare(4); s := sq;
  Check("Area of a square", s.Area() = 16);
  Check("Kind with a super call", s.Kind() = 11);
  Check("Twice calls the dynamic Area", s.Twice() = 32);
  NEW(ci); ci.r := 2; s := ci;
  Check("Area overridden in another module", s.Area() = 12);
  Check("Kind inherited from the imported base", s.Kind() = 1);
  Check("a hidden method of the imported base", s.Secret() = 7);
  Check("a new method beside it", (ci.Diameter() = 4) & (ci.Secret() = 7));
  Check("a field of the base type", ci.calls = 1);
  NEW(cu); cu.side := 2; s := cu;
  Check("super call into the imported type", s.Area() = 24);
  Check("Kind of the imported extension", s.Kind() = 11);
  Check("a type guard", s(TbpBase.Square).Area() = 24);
  shapes[0] := sq; shapes[1] := ci; shapes[2] := cu; sum := 0;
  FOR i := 0 TO 2 DO sum := sum + shapes[i].Area() END;
  Check("calls through an array", sum = 16 + 12 + 24);
  Check("two calls in one expression", sq.Area() + ci.Area() = 28);
  k.n := 0; k.Add(5); Check("a VAR record receiver", k.Value() = 5);
  t.n := 0; t.adds := 0; t.Add(3); Check("an override with two super calls", (t.n = 6) & (t.adds = 1));
  AddVia(t, 2); Check("the dynamic type of a VAR record", (t.n = 10) & (t.adds = 2));
  AddVia(k, 2); Check("the static type of a VAR record", k.n = 7);
  NEW(a); NEW(b); NEW(c);
  Check("three levels", (a.Level() = 1) & (b.Level() = 2) & (c.Level() = 3));
  Check("a forward declared method", (a.Describe() = 10) & (b.Describe() = 21) & (c.Describe() = 31));
  a.x := 100; Check("eight arguments", a.Sum(1, 2, 3, 4, 5, 6, 7, 8) = 100 + 204);
  v.x := 3.0; v.y := 4.0; Check("a REAL result", v.Len2() = 25.0);
  NEW(pa); pa^ := v; pa^.Scale(2.0); Check("a call on p^", (pa.x = 6.0) & (pa.y = 8.0) & (pa^.Len2() = 100.0));
  IF s IS Cube THEN WITH s: Cube DO Check("WITH", s.Area() = 24) END ELSE Check("WITH", FALSE) END;
  WITH s: Circle DO i := 1 | s: Cube DO i := 2 ELSE i := 3 END; Check("WITH with two guards", i = 2);
  s := sq; WITH s: Circle DO i := 1 | s: Cube DO i := 2 ELSE i := 3 END; Check("WITH ELSE", i = 3);
  ci.Grow; Check("a call without parameters", ci.r = 3);
  v.Zero; Check("the same with a VAR receiver", (v.x = 0.0) & (v.y = 0.0));
  Out.String("TbpTest: "); Out.Int(checks, 0); Out.String(" checks, "); Out.Int(fails, 0); Out.String(" failed"); Out.Ln
END Run;

END TbpTest.
