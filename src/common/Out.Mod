(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE Out; (** portable *)  (* based on module from "Programming in Oberon" *)

(** Simple output routines for writing text into the Oberon log or a seperate viewer. *)

IMPORT SYSTEM, Linux0, Texts0;

(* polpo: the output goes to the standard output in the console, and through writer in the desktop,
  where System points it at System.Log. Numbers are formatted as the desktop's Texts does it (Texts0).
  Hex is ETH Oberon's; HexDigits is OO2C's Out.Hex under its own name, for the modules shared with voc.
  The older console module out writes through this one and is deprecated. *)

TYPE
  Writer* = PROCEDURE (VAR s: ARRAY OF CHAR; len: LONGINT);

VAR
  writer*: Writer;  (** where the output goes: NIL is the standard output; System sets it to its log *)
  open*, close*: PROCEDURE;  (** set by the desktop: Open and Close *)
  W: Texts0.Writer; T: Texts0.Text;

PROCEDURE Write(VAR s: ARRAY OF CHAR; len: LONGINT);  (* the first len characters of s *)
  VAR n: LONGINT;
BEGIN
  IF writer # NIL THEN writer(s, len) ELSIF len > 0 THEN n := Linux0.Write0(1, SYSTEM.ADR(s[0]), len) END
END Write;

PROCEDURE Flush;  (* the characters of W, line ends as LF *)
  VAR R: Texts0.Reader; s: ARRAY 64 OF CHAR; i, n: LONGINT;
BEGIN
  Texts0.Append(T, W.buf); Texts0.OpenReader(R, T, 0); n := T.len; i := 0;
  WHILE n > 0 DO
    Texts0.Read(R, s[i]); IF s[i] = 0DX THEN s[i] := 0AX END; INC(i); DEC(n);
    IF (i = LEN(s) - 1) OR (n = 0) THEN s[i] := 0X; Write(s, i); i := 0 END
  END;
  Texts0.Delete(T, 0, T.len)
END Flush;

(** Write character. *)
PROCEDURE Char*(ch: CHAR);
  VAR s: ARRAY 2 OF CHAR;
BEGIN
  IF ch = 0DX THEN ch := 0AX END;
  s[0] := ch; s[1] := 0X; Write(s, 1)
END Char;

(** Write a string. *)
PROCEDURE String*(str: ARRAY OF CHAR);
  VAR len: LONGINT;
BEGIN
  len := 0; WHILE (len < LEN(str)) & (str[len] # 0X) DO INC(len) END;
  Write(str, len)
END String;

(** Write the integer i in n field positions. *)
PROCEDURE Int*(i, n: LONGINT);
BEGIN
  Texts0.WriteInt(W, i, n); Flush
END Int;

(** Write the integer i in hexadecimal with a leading space. *)
PROCEDURE Hex*(i: LONGINT);
BEGIN
  Texts0.WriteHex(W, i); Flush
END Hex;

(** Write x as an unsigned hexadecimal number with at least n digits, leading zeros where it needs fewer,
  and 8 digits for n <= 0 (OO2C's Out.Hex). *)
PROCEDURE HexDigits*(x, n: LONGINT);
  VAR m, i, d: LONGINT; s: ARRAY 33 OF CHAR;
BEGIN
  IF n <= 0 THEN n := 8 END;
  m := 1; WHILE (m < 8) & (SYSTEM.LSH(x, -4 * m) # 0) DO INC(m) END;  (* the digits x needs, unsigned *)
  WHILE n > LEN(s) - 1 DO Char("0"); DEC(n) END;
  IF n < m THEN n := m END;
  i := 0; WHILE i < n - m DO s[i] := "0"; INC(i) END;
  WHILE m > 0 DO
    DEC(m); d := SYSTEM.LSH(x, -4 * m) MOD 10H;
    IF d < 10 THEN s[i] := CHR(d + 30H) ELSE s[i] := CHR(d - 10 + 41H) END;
    INC(i)
  END;
  s[i] := 0X; String(s)
END HexDigits;

(** Write the real x in n field positions. *)
PROCEDURE Real*(x: REAL; n: INTEGER);
BEGIN
  Texts0.WriteReal(W, x, n); Flush
END Real;

(** Write the real x in n field positions in fixed point notation with f fraction digits. *)
PROCEDURE RealFix*(x: REAL; n, f: INTEGER);
BEGIN
  Texts0.WriteRealFix(W, x, n, f, 0); Flush
END RealFix;

(** Write the longreal x in n field positions. *)
PROCEDURE LongReal*(x: LONGREAL; n: INTEGER);
BEGIN
  Texts0.WriteLongReal(W, x, n); Flush
END LongReal;

(** Write the longreal x in n field positions in fixed point notation with f fraction digits. *)
PROCEDURE LongRealFix*(x: LONGREAL; n, f: INTEGER);
BEGIN
  Texts0.WriteLongRealFix(W, x, n, f, 0); Flush
END LongRealFix;

(** Write a carriage return (CR or end-of-line). *)
PROCEDURE Ln*;
BEGIN
  Char(0AX)
END Ln;

(** Open a separate viewer for output (in the desktop). *)
PROCEDURE Open*;
BEGIN
  IF open # NIL THEN open END
END Open;

(** Revert output to the system log (in the desktop). *)
PROCEDURE Close*;
BEGIN
  IF close # NIL THEN close END
END Close;

BEGIN
  writer := NIL; Texts0.OpenWriter(W); NEW(T); Texts0.Open(T, "")
END Out.

(** Remarks:

1. Out uses a Writer from module Texts to write output to the log. Writing output using
Out is slow because the log is updated after every procedure call. For fast and flexible
output, use module Texts.

2. Out.Open creates a new text and viewer for output.  Once this is done, output can
be sent to the system log again by executing Close.
*)
