MODULE ByteOrderTest;  (** loksh ByteOrderTest.Run: the numbers of files are little-endian on every port *)

(* Files writes INTEGER, LONGINT, SET, REAL and LONGREAL with their least significant byte first,
   on little- and big-endian machines alike, and reads them back. The bytes written are compared
   with the expected ones, then read back with the Read procedures. *)

IMPORT Files, out;

VAR fails, checks: LONGINT;

PROCEDURE Check(what: ARRAY OF CHAR; ok: BOOLEAN);
BEGIN
  INC(checks);
  IF ~ok THEN INC(fails); out.String("ByteOrderTest: failed: "); out.String(what); out.Ln END
END Check;

(* the next n bytes of R are the hex digits of s, two per byte *)
PROCEDURE Bytes(VAR R: Files.Rider; what, s: ARRAY OF CHAR);
VAR i, d: INTEGER; ch: CHAR; ok: BOOLEAN;

  PROCEDURE Hex(c: CHAR): INTEGER;
  BEGIN IF c <= "9" THEN RETURN ORD(c) - ORD("0") ELSE RETURN ORD(c) - ORD("A") + 10 END
  END Hex;

BEGIN
  ok := TRUE; i := 0;
  WHILE s[i] # 0X DO
    Files.Read(R, ch); d := Hex(s[i]) * 16 + Hex(s[i+1]);
    IF ORD(ch) # d THEN ok := FALSE END;
    INC(i, 2)
  END;
  Check(what, ok)
END Bytes;

PROCEDURE Run*;
VAR f: Files.File; R: Files.Rider; i: INTEGER; l: LONGINT; set: SET; x: REAL; y: LONGREAL;
BEGIN
  fails := 0; checks := 0;
  f := Files.New("zq_order.bin"); Files.Set(R, f, 0);
  Files.WriteInt(R, -2); Files.WriteInt(R, 1234H);
  Files.WriteLInt(R, 12345678H); Files.WriteLInt(R, -2);
  Files.WriteSet(R, {0, 9, 31});
  Files.WriteReal(R, 1.5); Files.WriteLReal(R, 1.5D0); Files.WriteLReal(R, -0.1D0);
  Files.WriteNum(R, 300);
  Files.Register(f);
  f := Files.Old("zq_order.bin"); Files.Set(R, f, 0);
  Bytes(R, "WriteInt -2", "FEFF"); Bytes(R, "WriteInt 1234H", "3412");
  Bytes(R, "WriteLInt 12345678H", "78563412"); Bytes(R, "WriteLInt -2", "FEFFFFFF");
  Bytes(R, "WriteSet {0, 9, 31}", "01020080");
  Bytes(R, "WriteReal 1.5", "0000C03F");
  Bytes(R, "WriteLReal 1.5", "000000000000F83F");
  Bytes(R, "WriteLReal -0.1", "9A9999999999B9BF");
  Bytes(R, "WriteNum 300", "AC02");
  Files.Set(R, f, 0);
  Files.ReadInt(R, i); Check("ReadInt -2", i = -2);
  Files.ReadInt(R, i); Check("ReadInt 1234H", i = 1234H);
  Files.ReadLInt(R, l); Check("ReadLInt 12345678H", l = 12345678H);
  Files.ReadLInt(R, l); Check("ReadLInt -2", l = -2);
  Files.ReadSet(R, set); Check("ReadSet", set = {0, 9, 31});
  Files.ReadReal(R, x); Check("ReadReal", x = 1.5);
  Files.ReadLReal(R, y); Check("ReadLReal 1.5", y = 1.5D0);
  Files.ReadLReal(R, y); Check("ReadLReal -0.1", y = -0.1D0);
  Files.ReadNum(R, l); Check("ReadNum 300", l = 300);
  Files.Close(f); Files.Delete("zq_order.bin", i);
  out.String("ByteOrderTest: "); out.Int(checks, 0); out.String(" checks, "); out.Int(fails, 0); out.String(" failed"); out.Ln
END Run;

END ByteOrderTest.
