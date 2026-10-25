MODULE OocTest;  (** loksh OocTest.Run: the OOC library on this port (strings, conversions, math, time) *)

IMPORT SYSTEM, Ascii, Strings := oocStrings, Strings2, LongStrings, oocUnicode, IntStr, RealStr, LRealStr, ConvTypes,
  LowReal, LowLReal, RealMath, LRealMath, ComplexMath, JulianDay, SysClock, out;

VAR fails, checks: LONGINT;

PROCEDURE Check(what: ARRAY OF CHAR; ok: BOOLEAN);
BEGIN
  INC(checks);
  IF ~ok THEN INC(fails); out.String("OocTest: failed: "); out.String(what); out.Ln END
END Check;

PROCEDURE Near(x, y, eps: LONGREAL): BOOLEAN;
BEGIN RETURN ABS(x - y) <= eps
END Near;

PROCEDURE Strs;
VAR s: ARRAY 32 OF CHAR; found: BOOLEAN; pos: INTEGER;
BEGIN
  s := "ab"; Strings.Append("cd", s); Check("oocStrings.Append", s = "abcd");
  Strings.Extract("hello", 1, 3, s); Check("oocStrings.Extract", s = "ell");
  Strings.FindNext("lo", "hello", 0, found, pos); Check("oocStrings.FindNext", found & (pos = 3));
  s := "abc"; Strings.Insert("XY", 1, s); Check("oocStrings.Insert", s = "aXYbc");
  Check("Strings2.PosChar", Strings2.PosChar("x", "abxc") = 2);
  Check("Ascii.dle is 10X, soh 01X", (Ascii.dle = 10X) & (Ascii.soh = 01X) & (Ascii.dc1 = 11X))
END Strs;

PROCEDURE Longs;
VAR l, m: ARRAY 32 OF oocUnicode.LONGCHAR; s: ARRAY 32 OF CHAR; found: BOOLEAN; pos: LONGINT;
BEGIN
  LongStrings.Long("abc", l); Check("LongStrings.Long", (LongStrings.Length(l) = 3) & (l[1] = ORD("b")));
  Check("LongStrings.Equal8", LongStrings.Equal8(l, "abc") & ~LongStrings.Equal8(l, "abd"));
  l[1] := 0531H; LongStrings.Append8("de", l);  (* U+0531, ARMENIAN CAPITAL LETTER AYB *)
  Check("LongStrings.Append8", (LongStrings.Length(l) = 5) & (l[1] = 0531H) & (l[4] = ORD("e")));
  LongStrings.Short(l, "?", s); Check("LongStrings.Short", s = "a?cde");
  LongStrings.Long("cd", m); LongStrings.FindNext(m, l, 0, found, pos);
  Check("LongStrings.FindNext", found & (pos = 2));
  LongStrings.Delete(l, 1, 2); LongStrings.Short(l, "?", s); Check("LongStrings.Delete", s = "ade");
  LongStrings.Capitalize(l); LongStrings.Short(l, "?", s); Check("LongStrings.Capitalize", s = "ADE");
  l[0] := 0FFFFH; l[1] := 0; Check("LongStrings: units up to 0FFFFH", (l[0] = 65535) & (LongStrings.Length(l) = 1))
END Longs;

PROCEDURE Convs;
VAR s: ARRAY 64 OF CHAR; i: LONGINT; r: REAL; x: LONGREAL; res: ConvTypes.ConvResults;
BEGIN
  IntStr.StrToInt("-12345", i, res); Check("IntStr.StrToInt", (res = IntStr.strAllRight) & (i = -12345));
  IntStr.StrToInt("99999999999", i, res); Check("IntStr.StrToInt out of range", res = IntStr.strOutOfRange);
  IntStr.IntToStr(2147483647, s); Check("IntStr.IntToStr", s = "2147483647");
  IntStr.IntToStr(MIN(LONGINT), s); Check("IntStr.IntToStr MIN(LONGINT)", s = "-2147483648");
  IntStr.StrToInt("-2147483648", i, res); Check("IntStr.StrToInt MIN(LONGINT)", (res = IntStr.strAllRight) & (i = MIN(LONGINT)));
  IntStr.StrToInt("-2147483649", i, res); Check("IntStr.StrToInt below MIN(LONGINT)", res = IntStr.strOutOfRange);
  RealStr.StrToReal("3.25", r, res); Check("RealStr.StrToReal", (res = RealStr.strAllRight) & (r = 3.25));
  RealStr.RealToFixed(3.14159, 2, s); Check("RealStr.RealToFixed", s = "3.14");
  LRealStr.StrToReal("1.5E2", x, res); Check("LRealStr.StrToReal", (res = LRealStr.strAllRight) & (x = 150.0D0));
  LRealStr.RealToFixed(2.5D0, 1, s); Check("LRealStr.RealToFixed", s = "2.5");
  LRealStr.RealToFloat(1234.5678D0, 15, s); LRealStr.StrToReal(s, x, res);
  Check("LRealStr round trip", (res = LRealStr.strAllRight) & Near(x, 1234.5678D0, 1.0D-10))
END Convs;

PROCEDURE Maths;
VAR h, l, k: LONGINT; y: LONGREAL; z: ComplexMath.COMPLEX;
BEGIN
  Check("LowReal.small = 2^-126", SYSTEM.VAL(LONGINT, LowReal.small) = 800000H);
  y := LowLReal.small; SYSTEM.GET(SYSTEM.ADR(y), l); SYSTEM.GET(SYSTEM.ADR(y) + 4, h);
  IF LowLReal.isBigEndian THEN k := l; l := h; h := k END;  (* the high word first *)
  Check("LowLReal.small = 2^-1022", (h = 100000H) & (l = 0));
  Check("LowReal.scale", LowReal.scale(1.5, -3) = 0.1875);
  Check("LowReal.intpart", LowReal.intpart(-7.75) = -7.0);
  Check("LowReal.round", LowReal.round(123.4375, 5) = 124.0);
  Check("RealMath.sqrt", Near(RealMath.sqrt(2.0), 1.41421356D0, 1.0D-6));
  Check("RealMath.arcsin", Near(RealMath.arcsin(0.9), 1.11976951D0, 1.0D-6));
  Check("RealMath.arccos after an error", (RealMath.arcsin(2.0) # 0.0) & Near(RealMath.arccos(0.9), 0.45102681D0, 1.0D-6));
  Check("RealMath.tan(pi/2)", Near(RealMath.tan(1.5707964) / 1.0D7, -2.2877332D0, 1.0D-4));
  Check("LRealMath.exp", Near(LRealMath.exp(1.0D0), 2.718281828459045D0, 1.0D-14));
  Check("LRealMath.ln", Near(LRealMath.ln(10.0D0), 2.302585092994046D0, 1.0D-14));
  Check("LRealMath.sqrt", Near(LRealMath.sqrt(2.0D0), 1.4142135623730951D0, 1.0D-15));
  Check("LRealMath.tan(-pi) > 0", (LRealMath.tan(-3.141592653589793D0) > 0.0D0) & (LRealMath.tan(-3.141592653589793D0) < 1.0D-15));
  Check("LRealMath.tan(pi/2)", Near(LRealMath.tan(1.5707963267948966D0) / 1.0D16, 1.6331D0, 1.0D-3));
  z := ComplexMath.CMPLX(3.0, 4.0); Check("ComplexMath.abs", Near(ComplexMath.abs(z), 5.0D0, 1.0D-6))
END Maths;

PROCEDURE Times;
VAR d, m: SHORTINT; y: INTEGER; sec, usec: LONGINT;
BEGIN
  Check("JulianDay.DateToJD", JulianDay.DateToJD(1, 1, 2000) = 2451544.5D0);
  JulianDay.DaysToDate(JulianDay.DateToDays(29, 2, 2024), d, m, y);
  Check("JulianDay.DaysToDate", (d = 29) & (m = 2) & (y = 2024));
  Check("SysClock.GetTimeOfDay", (SysClock.GetTimeOfDay(sec, usec) = 0) & (sec > 1700000000) & (usec >= 0) & (usec < 1000000))
END Times;

PROCEDURE Run*;
BEGIN
  fails := 0; checks := 0;
  Strs; Longs; Convs; Maths; Times;
  out.String("OocTest: "); out.Int(checks, 0); out.String(" checks, "); out.Int(fails, 0); out.String(" failed"); out.Ln
END Run;

END OocTest.
