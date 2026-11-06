MODULE OutTest;  (** loksh OutTest.Run: Out.Hex, Out.HexDigits, Int and line ends, caught through Out.writer *)

IMPORT Out;

VAR buf: ARRAY 256 OF CHAR; len, checks, failed: LONGINT;

PROCEDURE Catch(VAR s: ARRAY OF CHAR; n: LONGINT);
VAR i: LONGINT;
BEGIN
  i := 0; WHILE (i < n) & (len < LEN(buf) - 1) DO buf[len] := s[i]; INC(len); INC(i) END;
  buf[len] := 0X
END Catch;

PROCEDURE Begin;
BEGIN len := 0; buf[0] := 0X; Out.writer := Catch
END Begin;

PROCEDURE Check(want: ARRAY OF CHAR);
VAR got: ARRAY 256 OF CHAR;
BEGIN
  Out.writer := NIL; COPY(buf, got); INC(checks);
  IF got # want THEN
    INC(failed); Out.String("FAIL: wanted '"); Out.String(want); Out.String("', got '"); Out.String(got);
    Out.String("'"); Out.Ln
  END
END Check;

PROCEDURE Run*;
VAR e: ARRAY 8 OF CHAR;
BEGIN
  checks := 0; failed := 0;
  Begin; Out.Hex(10); Check(" 0000000A");
  Begin; Out.Hex(255); Check(" 000000FF");
  Begin; Out.Hex(-1); Check(" FFFFFFFF");
  Begin; Out.Hex(MIN(LONGINT)); Check(" 80000000");
  Begin; Out.HexDigits(10, 2); Check("0A");
  Begin; Out.HexDigits(255, 2); Check("FF");
  Begin; Out.HexDigits(4096, 2); Check("1000");
  Begin; Out.HexDigits(10, 0); Check("0000000A");
  Begin; Out.HexDigits(10, -3); Check("0000000A");
  Begin; Out.HexDigits(10, 16); Check("000000000000000A");
  Begin; Out.HexDigits(1, 40); Check("0000000000000000000000000000000000000001");
  Begin; Out.HexDigits(-1, 2); Check("FFFFFFFF");
  Begin; Out.HexDigits(-2, 12); Check("0000FFFFFFFE");
  Begin; Out.HexDigits(MIN(LONGINT), 1); Check("80000000");
  Begin; Out.HexDigits(7FFFFFFFH, 1); Check("7FFFFFFF");
  Begin; Out.HexDigits(0, 1); Check("0");
  Begin; Out.HexDigits(0ABCDEFH, 1); Check("ABCDEF");
  Begin; Out.Int(-5, 4); Check("  -5");
  Begin; Out.Int(MIN(LONGINT), 0); Check(" -2147483648");
  e := "ab"; e[2] := 0AX; e[3] := 0AX; e[4] := 0X;
  Begin; Out.String("ab"); Out.Char(0DX); Out.Ln; Check(e);
  Out.String("OutTest: "); Out.Int(checks, 0); Out.String(" checks, "); Out.Int(failed, 0); Out.String(" failed");
  Out.Ln
END Run;

END OutTest.
