MODULE TbpBase;  (** base types with type-bound procedures for TbpTest (x86: compile with /2) *)

TYPE
  Shape* = POINTER TO ShapeDesc;
  ShapeDesc* = RECORD
    name*: ARRAY 16 OF CHAR;
    calls*: LONGINT
  END;

  Square* = POINTER TO SquareDesc;
  SquareDesc* = RECORD (ShapeDesc)
    side*: LONGINT
  END;

  Counter* = RECORD
    n*: LONGINT
  END;

PROCEDURE (s: Shape) Area*(): LONGINT;
BEGIN INC(s.calls); RETURN 0
END Area;

PROCEDURE (s: Shape) Hidden(): LONGINT;  (* not exported: its slot must stay in extensions elsewhere *)
BEGIN RETURN 7
END Hidden;

PROCEDURE (s: Shape) Kind*(): LONGINT;
BEGIN RETURN 1
END Kind;

PROCEDURE (s: Shape) Twice*(): LONGINT;  (* calls the dynamic Area *)
BEGIN RETURN 2 * s.Area()
END Twice;

PROCEDURE (s: Shape) Secret*(): LONGINT;  (* calls the hidden one *)
BEGIN RETURN s.Hidden()
END Secret;

PROCEDURE (s: Square) Area*(): LONGINT;
BEGIN INC(s.calls); RETURN s.side * s.side
END Area;

PROCEDURE (s: Square) Kind*(): LONGINT;
BEGIN RETURN 10 + s.Kind^()
END Kind;

PROCEDURE (VAR c: Counter) Add*(d: LONGINT);
BEGIN INC(c.n, d)
END Add;

PROCEDURE (VAR c: Counter) Value*(): LONGINT;
BEGIN RETURN c.n
END Value;

PROCEDURE NewSquare*(side: LONGINT): Square;
VAR s: Square;
BEGIN NEW(s); s.side := side; s.name := "square"; RETURN s
END NewSquare;

END TbpBase.
