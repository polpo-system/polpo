MODULE out;  (** deprecated: import Out. out stays for the packages that still import it and writes
  through Out. Its Hex(x, w) is the one of Kernel.WriteHex: 8 digits padded with blanks to w, or 2 digits
  for a negative w; Out.Hex(i) is ETH's, a blank and 8 digits, and Out.HexDigits(x, n) OO2C's. *)

IMPORT Out;

PROCEDURE Char*(c: CHAR);
BEGIN Out.Char(c)
END Char;

PROCEDURE String*(s: ARRAY OF CHAR);
BEGIN Out.String(s)
END String;

PROCEDURE Ln*;
BEGIN Out.Ln
END Ln;

PROCEDURE Int*(x, w: LONGINT);
BEGIN Out.Int(x, w)
END Int;

PROCEDURE Hex*(x, w: LONGINT);
VAR buf: ARRAY 10 OF CHAR; i, j: LONGINT;
BEGIN
  IF w >= 0 THEN j := 8 ELSE j := 2; w := -w END;
  FOR i := j+1 TO w DO Out.Char(" ") END;
  FOR i := j-1 TO 0 BY -1 DO
    buf[i] := CHR(x MOD 10H + 48);
    IF buf[i] > "9" THEN buf[i] := CHR(ORD(buf[i]) - 48 + 65 - 10) END;
    x := x DIV 10H
  END;
  buf[j] := 0X; Out.String(buf)
END Hex;

END out.
