MODULE DecRealTest;  (** loksh DecRealTest.Run: DecReal.Long and Short, bit for bit *)

(* The expected bits are the decimal values rounded to nearest, ties to even, computed exactly with
   fractions; the results: 0 ok, 1 overflow, 2 underflow (a value # 0 that rounds to 0). The cases are
   the ends of the range, denormal numbers, halfway cases and literals that were off before. *)

IMPORT SYSTEM, DecReal, out;

VAR fails, checks: LONGINT;

(* the high and low words of x, in the byte order of the machine *)
PROCEDURE Words(VAR x: LONGREAL; VAR hi, lo: LONGINT);
VAR w: LONGINT; c: CHAR;
BEGIN
  w := 1; SYSTEM.GET(SYSTEM.ADR(w), c);
  IF c = 0X THEN SYSTEM.GET(SYSTEM.ADR(x), hi); SYSTEM.GET(SYSTEM.ADR(x) + 4, lo)
  ELSE SYSTEM.GET(SYSTEM.ADR(x), lo); SYSTEM.GET(SYSTEM.ADR(x) + 4, hi)
  END
END Words;

PROCEDURE L(dig: ARRAY OF CHAR; e, hi, lo: LONGINT; res: INTEGER);
VAR x: LONGREAL; h, l: LONGINT; r, n: INTEGER;
BEGIN n := 0; WHILE dig[n] # 0X DO INC(n) END;
  r := DecReal.Long(dig, n, FALSE, e, x); Words(x, h, l); INC(checks);
  IF (h # hi) OR (l # lo) OR (r # res) THEN INC(fails);
    out.String("FAIL Long "); out.String(dig); out.String("E"); out.Int(e, 0); out.String(": ");
    out.Hex(h, 8); out.Hex(l, 8); out.Int(r, 2); out.String(", expected "); out.Hex(hi, 8); out.Hex(lo, 8); out.Int(res, 2); out.Ln
  END
END L;

PROCEDURE S(dig: ARRAY OF CHAR; e, bits: LONGINT; res: INTEGER);
VAR x: REAL; b: LONGINT; r, n: INTEGER;
BEGIN n := 0; WHILE dig[n] # 0X DO INC(n) END;
  r := DecReal.Short(dig, n, FALSE, e, x); SYSTEM.GET(SYSTEM.ADR(x), b); INC(checks);
  IF (b # bits) OR (r # res) THEN INC(fails);
    out.String("FAIL Short "); out.String(dig); out.String("E"); out.Int(e, 0); out.String(": ");
    out.Hex(b, 8); out.Int(r, 2); out.String(", expected "); out.Hex(bits, 8); out.Int(res, 2); out.Ln
  END
END S;

PROCEDURE Run*;
BEGIN fails := 0; checks := 0;
  L("1", 0, 03FF00000H, 000000000H, 0);
  S("1", 0, 03F800000H, 0);
  L("11", 2, 040913000H, 000000000H, 0);
  S("11", 2, 044898000H, 0);
  L("123456", -3, 0405EDD2FH, 01A9FBE77H, 0);
  S("123456", -3, 042F6E979H, 0);
  L("1", 23, 044B52D02H, 0C7E14AF6H, 0);
  S("1", 23, 065A96816H, 0);
  L("1", 22, 04480F0CFH, 0064DD592H, 0);
  S("1", 22, 064078678H, 0);
  L("34", 37, 047EFF933H, 0C78CDFADH, 0);
  S("34", 37, 07F7FC99EH, 0);
  L("17", 307, 07FEE42D1H, 030773B76H, 0);
  S("17", 307, 000000000H, 1);
  L("49406564584124654", -340, 000000000H, 000000001H, 0);
  S("49406564584124654", -340, 000000000H, 2);
  L("14", -46, 0369FF868H, 0BF4D956AH, 0);
  S("14", -46, 000000001H, 0);
  L("22250738585072014", -324, 000100000H, 000000000H, 0);
  S("22250738585072014", -324, 000000000H, 2);
  L("117549435", -46, 0380FFFFFH, 0FF9FDBA8H, 0);
  S("117549435", -46, 000800000H, 0);
  L("1", -310, 000001268H, 08B70E62BH, 0);
  S("1", -310, 000000000H, 2);
  L("1", -307, 00031FA18H, 02C40C60DH, 0);
  S("1", -307, 000000000H, 2);
  L("1", -38, 0380B38FBH, 09DAA78E4H, 0);
  S("1", -38, 0006CE3EEH, 0);
  L("0", -400, 000000000H, 000000000H, 0);
  S("0", -400, 000000000H, 0);
  L("1", -400, 000000000H, 000000000H, 2);
  S("1", -400, 000000000H, 2);
  L("898846567431158", 293, 07FE00000H, 000000000H, 0);
  S("898846567431158", 293, 000000000H, 1);
  L("17976931348623157", 292, 07FEFFFFFH, 0FFFFFFFFH, 0);
  S("17976931348623157", 292, 000000000H, 1);
  L("17976931348623159", 292, 000000000H, 000000000H, 1);
  S("17976931348623159", 292, 000000000H, 1);
  L("18", 307, 000000000H, 000000000H, 1);
  S("18", 307, 000000000H, 1);
  L("5", -324, 000000000H, 000000001H, 0);
  S("5", -324, 000000000H, 2);
  L("24703282292062327", -340, 000000000H, 000000000H, 2);
  S("24703282292062327", -340, 000000000H, 2);
  L("24703282292062328", -340, 000000000H, 000000001H, 0);
  S("24703282292062328", -340, 000000000H, 2);
  L("340282356779733661637539395458142568447", 0, 047EFFFFFH, 0F0000000H, 0);
  S("340282356779733661637539395458142568447", 0, 07F7FFFFFH, 0);
  L("340282356779733661637539395458142568448", 0, 047EFFFFFH, 0F0000000H, 0);
  S("340282356779733661637539395458142568448", 0, 000000000H, 1);
  L("1", 39, 048078287H, 0F49C4A1DH, 0);
  S("1", 39, 000000000H, 1);
  L("1", -45, 03696D601H, 0AD376AB9H, 0);
  S("1", -45, 000000001H, 0);
  L("7", -46, 0368FF868H, 0BF4D956AH, 0);
  S("7", -46, 000000000H, 2);
  L("8", -46, 0369244CEH, 0242C5561H, 0);
  S("8", -46, 000000001H, 0);
  L("3141592653589793", -15, 0400921FBH, 054442D18H, 0);
  S("3141592653589793", -15, 040490FDBH, 0);
  L("2718281828459045", -15, 04005BF0AH, 08B145769H, 0);
  S("2718281828459045", -15, 0402DF854H, 0);
  L("1", -1, 03FB99999H, 09999999AH, 0);
  S("1", -1, 03DCCCCCDH, 0);
  L("3", -1, 03FD33333H, 033333333H, 0);
  S("3", -1, 03E99999AH, 0);
  L("2147483648", 0, 041E00000H, 000000000H, 0);
  S("2147483648", 0, 04F000000H, 0);
  L("9007199254740993", 0, 043400000H, 000000000H, 0);
  S("9007199254740993", 0, 05A000000H, 0);
  L("9007199254740995", 0, 043400000H, 000000002H, 0);
  S("9007199254740995", 0, 05A000000H, 0);
  L("1", 400, 000000000H, 000000000H, 1);
  S("1", 400, 000000000H, 1);
  L("1", -401, 000000000H, 000000000H, 2);
  S("1", -401, 000000000H, 2);
  L("12345678901234567890123", -30, 03E4A831BH, 0D731A289H, 0);
  S("12345678901234567890123", -30, 0325418DFH, 0);
  out.String("DecRealTest: "); out.Int(checks, 0); out.String(" checks, "); out.Int(fails, 0); out.String(" failed"); out.Ln
END Run;

END DecRealTest.
