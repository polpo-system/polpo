MODULE ReadOnlyBase;  (** read-only exports (-) for ReadOnlyTest *)

TYPE
  Point* = POINTER TO PointDesc;
  PointDesc* = RECORD
    x-, y-: LONGINT;
    tag*: LONGINT
  END;

  Pair* = RECORD a-, b*: LONGINT END;

VAR
  count-: LONGINT;
  name-: ARRAY 16 OF CHAR;
  pair-: Pair;
  origin-: Point;
  table-: ARRAY 4 OF LONGINT;

PROCEDURE Count*;
BEGIN INC(count)
END Count;

PROCEDURE Move*(p: Point; dx, dy: LONGINT);
BEGIN INC(p.x, dx); INC(p.y, dy)
END Move;

PROCEDURE NewPoint*(x, y: LONGINT): Point;
  VAR p: Point;
BEGIN NEW(p); p.x := x; p.y := y; p.tag := 0; RETURN p
END NewPoint;

PROCEDURE SetPair*(a, b: LONGINT);
BEGIN pair.a := a; pair.b := b
END SetPair;

BEGIN
  count := 0; name := "base"; origin := NewPoint(0, 0);
  table[0] := 1; table[1] := 2; table[2] := 3; table[3] := 4;
  SetPair(5, 6)
END ReadOnlyBase.
