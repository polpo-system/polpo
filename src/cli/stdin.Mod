(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE stdin; (** portable *)

(** CLI stdin reader. Same interface as In (ETH Oberon) but reads from standard input
    instead of Oberon.Par.text. For commands running in UI Oberon use the In module. *)

IMPORT Linux0, SYSTEM;

VAR
  Done*: BOOLEAN;
  nextch: CHAR;
  readstate: INTEGER;

CONST
  pending = 0;  (* at start of input or after consuming a line ending; nextch undefined *)
  ready   = 1;  (* nextch holds the next character *)
  eof     = 2;  (* end of file *)

PROCEDURE ReadChar;
VAR n: LONGINT;
BEGIN
  n := Linux0.Read0(0, SYSTEM.ADR(nextch), 1);
  IF n = 1 THEN readstate := ready ELSE readstate := eof END
END ReadChar;

(* Read exactly one byte from stdin without touching the internal state machine.
   Returns TRUE on success. For use with cbreak mode where every keypress matters. *)
PROCEDURE ReadRaw*(VAR ch: CHAR): BOOLEAN;
VAR n: LONGINT;
BEGIN
  n := Linux0.Read0(0, SYSTEM.ADR(ch), 1);
  RETURN n = 1
END ReadRaw;

PROCEDURE StartRead;
BEGIN IF readstate = pending THEN ReadChar END
END StartRead;

PROCEDURE StartAndSkip;
BEGIN
  StartRead;
  WHILE (readstate = ready) & (nextch <= " ") & (nextch # 0AX) & (nextch # 0DX) DO ReadChar END
END StartAndSkip;

PROCEDURE Open*;
BEGIN readstate := pending; Done := TRUE
END Open;

PROCEDURE Char*(VAR ch: CHAR);
BEGIN
  StartRead;
  Done := readstate = ready;
  IF Done THEN
    ch := nextch;
    IF ch = 0AX THEN readstate := pending ELSE ReadChar END
  ELSE
    ch := 0X
  END
END Char;

PROCEDURE Line*(VAR line: ARRAY OF CHAR);
VAR i: INTEGER;
BEGIN
  StartRead; i := 0; Done := readstate = ready;
  WHILE (readstate = ready) & (nextch # 0DX) & (nextch # 0AX) & (i < LEN(line) - 1) DO
    line[i] := nextch; INC(i); ReadChar
  END;
  line[i] := 0X;
  IF (readstate = ready) & (nextch = 0DX) THEN ReadChar END;
  IF (readstate = ready) & (nextch = 0AX) THEN readstate := pending END
END Line;

PROCEDURE Name*(VAR name: ARRAY OF CHAR);
VAR i: INTEGER;
BEGIN
  StartAndSkip;
  i := 0;
  Done := (readstate = ready) & (nextch > " ");
  IF Done THEN
    WHILE (readstate = ready) & (nextch > " ") & (i < LEN(name) - 1) DO
      name[i] := nextch; INC(i); ReadChar
    END
  END;
  name[i] := 0X
END Name;

PROCEDURE Int*(VAR i: LONGINT);
VAR neg: BOOLEAN;
BEGIN
  StartAndSkip;
  Done := readstate = ready;
  IF Done THEN
    i := 0; neg := nextch = "-";
    IF neg OR (nextch = "+") THEN ReadChar END;
    Done := (readstate = ready) & (nextch >= "0") & (nextch <= "9");
    IF Done THEN
      WHILE (readstate = ready) & (nextch >= "0") & (nextch <= "9") DO
        i := i * 10 + (ORD(nextch) - ORD("0")); ReadChar
      END;
      IF neg THEN i := -i END
    END
  END
END Int;

BEGIN
  nextch    := 0X;
  readstate := pending;
  Done      := TRUE
END stdin.
