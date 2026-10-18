(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE In; (** portable *)  (* based on module from "Programming in Oberon" *)

(** Stream oriented text input. Module In encapsulates the parameter scanning process of commands. *)

IMPORT Texts, Oberon;

VAR
  Done*: BOOLEAN;  (** Has the last scan operation been successful? *)
  S: Texts.Scanner;

(** Initializes the parameter scanner. The parameter stream is assumed to be the selection when ^ is scanned,
the marked text viewer when * is scanned; otherwise the text that follows the command itself. *)
PROCEDURE Open*;
VAR beg, end, time: LONGINT; T: Texts.Text;
BEGIN
  Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);  Texts.Scan(S);
  IF (S.class = Texts.Char) & (S.c = "^") THEN
    Oberon.GetSelection(T, beg, end, time);
    IF time # -1 THEN Texts.OpenScanner(S, T, beg); Done := TRUE
    ELSE Done := FALSE
    END
  ELSIF (S.class = Texts.Char) & (S.c = "*") THEN
    T := Oberon.MarkedText();
    IF T # NIL THEN Texts.OpenScanner(S, T, 0); Done := TRUE
    ELSE Done := FALSE
    END
  ELSE
    T := Oberon.Par.text; Texts.OpenScanner(S, T, Oberon.Par.pos); Done := TRUE
  END
END Open;

(** Scan a single character. The character returned is the character immediately following the last scanned token.*)
PROCEDURE Char*(VAR ch: CHAR);
BEGIN
  IF Done THEN ch := S.nextCh; Done := ~S.eot; Texts.Read(S, S.nextCh) END
END Char;

(** Scan an integer. *)
PROCEDURE Int*(VAR i: INTEGER);
BEGIN
  IF Done THEN
    Texts.Scan(S);
    IF (S.class = Texts.Int) & (MIN(INTEGER) <= S.i) & (S.i <= MAX(INTEGER)) THEN
      i := SHORT(S.i)
    ELSE
      Done := FALSE
    END
  END
END Int;

(** Scan a long integer. *)
PROCEDURE LongInt* (VAR i: LONGINT);
BEGIN
  IF Done THEN
    Texts.Scan(S);
    IF S.class = Texts.Int THEN i := S.i ELSE Done := FALSE END
  END
END LongInt;

(** Scan a real number. *)
PROCEDURE Real* (VAR x: REAL);
BEGIN
  IF Done THEN Texts.Scan(S);
    IF S.class = Texts.Real THEN x := S.x
    ELSIF S.class = Texts.Int THEN x := S.i
    ELSE Done := FALSE
    END
  END
END Real;

(** Scan a long real number. *)
PROCEDURE LongReal* (VAR y: LONGREAL);
BEGIN
  IF Done THEN
    Texts.Scan(S);
    IF S.class = Texts.LongReal THEN y := S.y
    ELSIF S.class = Texts.Real THEN y := S.x
    ELSIF S.class = Texts.Int THEN y := S.i
    ELSE Done := FALSE
    END
  END
END LongReal;

(** Scan a name. The syntax of a name is the same as that of the module Texts scanner. *)
PROCEDURE Name* (VAR name: ARRAY OF CHAR);
BEGIN
  IF Done THEN
    Texts.Scan(S);
    IF S.class = Texts.Name THEN COPY(S.s, name)
    ELSE Done := FALSE
    END
  END
END Name;

(** Scan a double quoted string. The quotes are not returned. *)
PROCEDURE String* (VAR str: ARRAY OF CHAR);
BEGIN
  IF Done THEN
    Texts.Scan(S);
    IF (S.class = Texts.String) OR (S.class = Texts.Name) THEN COPY(S.s, str)
    ELSE Done := FALSE
    END
  END
END String;

BEGIN
  Done := FALSE
END In.
