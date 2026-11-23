MODULE ReadOnlyTest;  (** ReadOnlyTest.Run: read-only exports (-) of another module, read here *)

(* Writing them here is a compilation error (76), so this module only reads them; their module changes them. *)

IMPORT Out, B := ReadOnlyBase;

TYPE
  Point3 = POINTER TO Point3Desc;
  Point3Desc = RECORD (B.PointDesc) z: LONGINT END;

VAR fails, checks: LONGINT;

PROCEDURE Check(what: ARRAY OF CHAR; ok: BOOLEAN);
BEGIN
  INC(checks);
  IF ~ok THEN INC(fails); Out.String("FAIL "); Out.String(what); Out.Ln END
END Check;

PROCEDURE Sum(t: ARRAY OF LONGINT): LONGINT;
  VAR i, s: LONGINT;
BEGIN
  s := 0; i := 0;
  WHILE i < LEN(t) DO INC(s, t[i]); INC(i) END;
  RETURN s
END Sum;

PROCEDURE Run*;
  VAR p: B.Point; q: Point3; r: B.Pair; s: ARRAY 16 OF CHAR; n: LONGINT;
BEGIN
  fails := 0; checks := 0;
  n := B.count; B.Count; B.Count; Check("a variable, changed by its module", B.count = n + 2);
  Check("a string", B.name = "base");
  COPY(B.name, s); Check("copied", s = "base");
  Check("a record", (B.pair.a = 5) & (B.pair.b = 6));
  B.SetPair(7, 8); Check("the record, changed by its module", (B.pair.a = 7) & (B.pair.b = 8));
  r := B.pair; Check("the record assigned to a variable here", (r.a = 7) & (r.b = 8));
  r.b := 1; Check("a writable field of it", (r.a = 7) & (r.b = 1));
  Check("an array passed by value", Sum(B.table) = 10);
  p := B.NewPoint(1, 2); Check("fields", (p.x = 1) & (p.y = 2));
  B.Move(p, 3, 4); Check("the fields, changed by their module", (p.x = 4) & (p.y = 6));
  p.tag := 9; Check("a writable field beside them", (p.tag = 9) & (p.x = 4));
  B.origin.tag := 3; Check("a field through a read-only pointer", B.origin.tag = 3);
  B.origin^.tag := 4; Check("the same, dereferenced", B.origin^.tag = 4);
  NEW(q); q.z := 5; B.Move(q, 1, 2); Check("an extension here", (q.x = 1) & (q.y = 2) & (q.z = 5));
  q.z := q.x + q.y; Check("its own field from the read-only ones", q.z = 3);
  Out.String("ReadOnlyTest: "); Out.Int(checks, 0); Out.String(" checks, "); Out.Int(fails, 0); Out.String(" failed"); Out.Ln
END Run;

END ReadOnlyTest.
