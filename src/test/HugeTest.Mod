MODULE HugeTest;  (** loksh HugeTest.Run: HUGEINT, 64-bit integers, as the compilers of every port compile them *)

(* On the 32-bit ports the compilers compile the operations of HUGEINT into calls of HugeInt. The checks: literals
  decimal and hexadecimal, constant expressions, the operations on a table of pairs (sum, difference, product,
  quotient and remainder, the last two for divisors > 0), comparisons where only the low words differ, LONG,
  SHORT, ABS, ODD, ASH, INC, DEC, MIN, MAX, SIZE, SYSTEM.VAL, mixed with smaller integers and with reals,
  parameters, functions returning a HUGEINT (recursive, through procedure variables, imported from HugeTest0),
  records, arrays and open arrays of HUGEINT, temporaries in long expressions and loops. *)

IMPORT SYSTEM, out, HugeTest0;

CONST
  Two32 = 4294967296;
  K1 = Two32 * 2147483647 + (Two32 - 1);  (* MAX(HUGEINT) *)
  K2 = -K1 - 1;  (* MIN(HUGEINT) *)
  K3 = 10000000000 DIV 3;  (* 3333333333 *)
  K4 = 10000000000 MOD 7;  (* 4 *)
  K5 = 10000000000 DIV 10;  (* 1000000000, a LONGINT *)

  K7 = ASH(Two32, 8);  (* LONG(1) is an INTEGER *)
  K8 = -ASH(Two32 * 3, 29);  (* -6917529027641081856 *)
  K9 = 0FFFFFFFFFFFFFFFFH;  (* -1 *)
  K10 = 0123456789ABCDEFH;

TYPE
  Rec = RECORD c: CHAR; h: HUGEINT; s: SHORTINT; g: HUGEINT END;
  Totals = POINTER TO ARRAY OF HUGEINT;

VAR
  checks, failed: LONGINT;
  global: HUGEINT;
  fn: HugeTest0.Fn;

PROCEDURE Str(x: HUGEINT; VAR s: ARRAY OF CHAR);
VAR d: ARRAY 24 OF CHAR; i, k: LONGINT; neg: BOOLEAN;
BEGIN
  neg := x < 0; i := 0;
  IF x = MIN(HUGEINT) THEN COPY("-9223372036854775808", s); RETURN END;
  IF neg THEN x := -x END;
  REPEAT d[i] := CHR(SHORT(x MOD 10) + ORD("0")); x := x DIV 10; INC(i) UNTIL x = 0;
  k := 0; IF neg THEN s[0] := "-"; k := 1 END;
  WHILE i > 0 DO DEC(i); s[k] := d[i]; INC(k) END;
  s[k] := 0X
END Str;

PROCEDURE Check(what: ARRAY OF CHAR; ok: BOOLEAN);
BEGIN
  INC(checks);
  IF ~ok THEN INC(failed); out.String("FAIL "); out.String(what); out.Ln END
END Check;

PROCEDURE Equal(what: ARRAY OF CHAR; x, y: HUGEINT);
VAR s: ARRAY 32 OF CHAR;
BEGIN
  INC(checks);
  IF x # y THEN
    INC(failed); out.String("FAIL "); out.String(what); out.String(": "); Str(x, s); out.String(s);
    out.String(", not "); Str(y, s); out.String(s); out.Ln
  END
END Equal;

PROCEDURE V(a, b, sum, diff, prod, quot, rem: HUGEINT);
VAR s: ARRAY 32 OF CHAR; w: ARRAY 64 OF CHAR;
BEGIN
  Str(a, w); Str(b, s); COPY(w, s);
  Equal("sum", a + b, sum); Equal("difference", a - b, diff); Equal("product", a * b, prod);
  IF b > 0 THEN Equal("quotient", a DIV b, quot); Equal("remainder", a MOD b, rem);
    Equal("quotient * divisor + remainder", (a DIV b) * b + a MOD b, a)
  END;
  Check("compare", ((a < b) = (b > a)) & ((a <= b) = ~(a > b)) & ((a = b) = (a - b = 0)) & ((a # b) = (diff # 0)))
END V;

PROCEDURE Pairs;
BEGIN
    V(1, 1, 2, 0, 1, 1, 0);
    V(4294967295, 1, 4294967296, 4294967294, 4294967295, 4294967295, 0);
    V(-4294967296, 1, -4294967295, -4294967297, -4294967296, -4294967296, 0);
    V(9223372036854775807, -1, 9223372036854775806, MIN(HUGEINT), -9223372036854775807, 0, 0);
    V(-9223372036854775807, 1, -9223372036854775806, MIN(HUGEINT), -9223372036854775807, -9223372036854775807, 0);
    V(123456789012345, 678901, 123456789691246, 123456788333444, -8418782851277725235, 181847999, 643246);
    V(-123456789012345, 678901, -123456788333444, -123456789691246, 8418782851277725235, -181848000, 35655);
    V(2147483647, 2147483647, 4294967294, 0, 4611686014132420609, 1, 0);
    V(-2147483648, 2147483647, -1, -4294967295, -4611686016279904256, -2, 2147483646);
    V(4294967296, 4294967296, 8589934592, 0, 0, 1, 0);
    V(-1, 4294967295, 4294967294, -4294967296, -4294967295, -1, 4294967294);
    V(1000000007, 998244353, 1998244360, 1755654, 998244359987710471, 1, 1755654);
    V(-77777777777777, 3, -77777777777774, -77777777777780, -233333333333331, -25925925925926, 1);
    V(5000000000, -7, 4999999993, 5000000007, -35000000000, 0, 0);
    V(3037000499, 3037000499, 6074000998, 0, 9223372030926249001, 1, 0);
    V(-3037000499, 3037000500, 1, -6074000999, -9223372033963249500, -1, 1);
    V(65535, 65537, 131072, -2, 4294967295, 0, 65535);
    V(-65536, 65536, 0, -131072, -4294967296, -1, 0);
    V(4611686018427387904, 3, 4611686018427387907, 4611686018427387901, -4611686018427387904, 1537228672809129301, 1);
    V(-4611686018427387904, 5, -4611686018427387899, -4611686018427387909, -4611686018427387904, -922337203685477581, 1);
    V(915533473134040693, -434388602399, 915533038745438294, 915533907522643092, -7297486907750407723, 0, 0);
    V(2487740162300132742, 616427369520, 2487740778727502262, 2487739545872763222, -7070345039780200160, 4035739, 186460857462);
    V(-8042200428764931522, -912289280662, -8042201341054212184, -8042199516475650860, -8277286743887379540, 0, 0);
    V(5166499419593367711, 980409743692, 5166500400003111403, 5166498439183624019, -8454009396844243404, 5269734, 859328349783);
    V(7767899424256262256, -507082793848, 7767898917173468408, 7767899931339056104, -1755888832765461632, 0, 0);
    V(-2480724440120465443, -502357041697, -2480724942477507140, -2480723937763423746, -1135855402295344509, 0, 0);
    V(-5220669377662112268, 752912174479, -5220668624749937789, -5220670130574286747, -2013545801530831028, -6933969, 299897864883);
    V(6151567057627032848, 444847040379, 6151567502474073227, 6151566612779992469, -1789094521060026704, 13828499, 204593071727);
    V(1569340318782520025, -79095036268, 1569340239687483757, 1569340397877556293, 6276284768058317684, 0, 0);
    V(7912649765528884551, 132527231312, 7912649898056115863, 7912649633001653239, 3024270493466189104, 59705840, 97171622471);
    V(-3966834623821927126, 1018179810242, -3966833605642116884, -3966835642001737368, 6105110422271825876, -3896006, 25959766326);
    V(-7590501365206009213, -804015320909, -7590502169221330122, -7590500561190688304, 5585539188242078105, 0, 0);
    V(7325131299924215486, 189064998768, 7325131488989214254, 7325131110859216718, -7738229956957547232, 38743984, 12696803774);
    V(4958335192954120588, -576072079135, 4958334616882041453, 4958335769026199723, 8956736396618195980, 0, 0);
    V(-8394370807752918241, 128765850083, -8394370678987068158, -8394370936518768324, 1767899012087241597, -65190972, 119564132435);
    V(-3510967715139935428, -626734638535, -3510968341874573963, -3510967088405296893, 3343362646770643036, 0, 0);
END Pairs;

PROCEDURE Literals;
VAR h: HUGEINT;
BEGIN
  h := 9223372036854775807; Equal("MAX literal", h, MAX(HUGEINT)); Equal("K1", K1, MAX(HUGEINT));
  h := -9223372036854775807; DEC(h); Equal("MIN", h, MIN(HUGEINT)); Equal("K2", K2, MIN(HUGEINT));
  Equal("hex", 7FFFFFFFFFFFFFFFH, MAX(HUGEINT)); Equal("hex 2^32", 100000000H, Two32);
  Equal("K9", K9, -1); Equal("K10", K10, 81985529216486895);
  Equal("K3", K3, 3333333333); Equal("K4", K4, 4); Check("K5 a LONGINT", K5 = 1000000000);
  Equal("K7", K7, 1099511627776); Equal("K8", K8, -6917529027641081856);
  Check("SIZE", SIZE(HUGEINT) = 8);
  Equal("imported constant", HugeTest0.Big, 1234567890123456789);
  Equal("imported constant 2", HugeTest0.Small, -5000000000)
END Literals;

PROCEDURE Compare;
VAR a, b: HUGEINT; s: SHORTINT;
BEGIN
  a := 4294967295; b := 1;  (* low words with the top bit *)
  Check("low unsigned >", a > b); Check("low unsigned <", b < a); Check(">=", a >= b); Check("<=", ~(a <= b));
  a := -4294967296; b := -1;
  Check("negative <", a < b); Check("negative #", a # b); Check("= self", a = a);
  a := 2147483648; b := -2147483648;
  Check("2^31 > -2^31", a > b); Check("-2^31 = LONGINT", b = MIN(LONGINT));
  Check("mixed with LONGINT", a > MAX(LONGINT)); s := -5; Check("mixed with SHORTINT", -a < s)
END Compare;

PROCEDURE Conversions;
VAR h: HUGEINT; l: LONGINT; i: INTEGER; s: SHORTINT; r: REAL; x: LONGREAL;
BEGIN
  l := MIN(LONGINT); h := LONG(l); Equal("LONG", h, -2147483648);
  h := l; Equal("LONGINT := ", h, -2147483648);
  i := -300; h := i; Equal("INTEGER :=", h, -300);
  s := -7; h := s * Two32; Equal("SHORTINT * Two32", h, -30064771072);
  h := 4294967297; l := SHORT(h); Check("SHORT", l = 1);
  h := -4294967297; l := SHORT(h); Check("SHORT negative", l = -1);
  l := SHORT(LONG(5)); Check("SHORT(LONG(5))", l = 5);
  h := 1; h := h * 1000000 * 1000000 * 1000000; x := h; Check("LONGREAL :=", x = 1.0D18);
  r := h; Check("REAL :=", ABS(r - 1.0E18) < 1.0E12);
  x := h / 4; Check("/", ABS(x - 2.5E17) < 1.0E11);
  x := h + 0.5D0; Check("+ LONGREAL", x = 1.0D18);
  h := 3FF0000000000000H; x := SYSTEM.VAL(LONGREAL, h); Check("VAL", x = 1.0D0);
  x := 2.0D0; h := SYSTEM.VAL(HUGEINT, x); Equal("VAL back", h, 4611686018427387904)
END Conversions;

PROCEDURE Ops;
VAR h, g: HUGEINT; l: LONGINT; i: INTEGER;
BEGIN
  h := 4294967295; INC(h); Equal("INC", h, Two32); DEC(h); Equal("DEC", h, 4294967295);
  INC(h, 1); Equal("INC 1", h, Two32); INC(h, -1); Equal("INC -1", h, 4294967295);
  l := MIN(LONGINT); INC(h, l); Equal("INC LONGINT", h, 2147483647); DEC(h, l); Equal("DEC LONGINT", h, 4294967295);
  g := 5000000000; INC(h, g); Equal("INC HUGEINT", h, 9294967295); DEC(h, g); Equal("DEC HUGEINT", h, 4294967295);
  INC(h, 5000000000); Equal("INC constant", h, 9294967295); DEC(h, h); Equal("DEC self", h, 0);
  h := -9; Equal("ABS", ABS(h), 9); Check("ODD", ODD(h)); h := Two32 + 2; Check("~ODD", ~ODD(h));
  Equal("unary minus", -h, -4294967298); h := MIN(HUGEINT); Equal("ABS MIN", ABS(h), MIN(HUGEINT));
  h := 3; Equal("ASH 40", ASH(h, 40), 3298534883328); Equal("ASH 63", ASH(h, 63), MIN(HUGEINT));
  h := -3298534883328; l := -40; Equal("ASH -40", ASH(h, l), -3); l := -100; Equal("ASH -100", ASH(h, l), -1);
  l := 33; Equal("ASH 33", ASH(h, l), 0); h := 1; Equal("ASH 32", ASH(h, 32), Two32);
  i := 1000; h := 123456789012; Equal("* INTEGER", h * i, 123456789012000);
  Equal("DIV INTEGER", h DIV i, 123456789); Equal("MOD INTEGER", h MOD i, 12);
  h := -7; Equal("-7 DIV 2", h DIV 2, -4); Equal("-7 MOD 2", h MOD 2, 1);
  h := MIN(HUGEINT); Equal("MIN DIV 2", h DIV 2, -4611686018427387904); Equal("MIN MOD 3", h MOD 3, 1);
  h := MAX(HUGEINT); Equal("MAX DIV MAX", h DIV MAX(HUGEINT), 1); Equal("MAX MOD 10", h MOD 10, 7);
  h := 1000000007; g := 998244353; Equal("product of primes", h * g, 998244359987710471);
  Equal("long expression", (h + g) * (h - g) DIV (g MOD 1000 + 1) - ABS(-h) * 2, 9908242100583);
  l := 7; Equal("LONGINT first", l - h, -1000000000); Equal("LONGINT * HUGEINT", l * h, 7000000049)
END Ops;

PROCEDURE Value(x: HUGEINT): HUGEINT;
BEGIN x := x * 2; RETURN x
END Value;

PROCEDURE Var(VAR x: HUGEINT; y: HUGEINT);
BEGIN x := x + y
END Var;

PROCEDURE Max(a, b: HUGEINT): HUGEINT;
BEGIN IF a > b THEN RETURN a ELSE RETURN b END
END Max;

PROCEDURE Fib(n: LONGINT): HUGEINT;
BEGIN
  IF n < 2 THEN RETURN n ELSE RETURN Fib(n - 1) + Fib(n - 2) END
END Fib;

PROCEDURE FibI(n: LONGINT): HUGEINT;
VAR a, b, c: HUGEINT;
BEGIN
  a := 0; b := 1;
  WHILE n > 0 DO c := a + b; a := b; b := c; DEC(n) END;
  RETURN a
END FibI;

PROCEDURE Calls;
VAR h, g: HUGEINT; p: HugeTest0.Pair;
BEGIN
  h := 3000000000; g := Value(h); Equal("value parameter", h, 3000000000); Equal("value result", g, 6000000000);
  Var(h, g); Equal("VAR parameter", h, 9000000000); Var(h, -1); Equal("VAR with LONGINT", h, 8999999999);
  Equal("LONGINT argument", Value(MAX(LONGINT)), 4294967294);
  Equal("nested calls", Max(Value(h), Max(FibI(50), 7)) + Value(1), 17999999998 + 2);
  Equal("Fib(20)", Fib(20), 6765); Equal("FibI(90)", FibI(90), 2880067194370816120);
  Equal("imported function", HugeTest0.Fact(20), 2432902008176640000);
  Equal("imported variable", HugeTest0.h, -5000000000);
  fn := HugeTest0.Twice; Equal("procedure variable", fn(4611686018427387903), 9223372036854775806);
  Equal("imported procedure variable", HugeTest0.twice(-21), -42);
  p.c := "x"; p.h := 77; h := HugeTest0.Swap(p, 88); Equal("Swap", h, 77); Equal("Swap field", p.h, 88);
  Check("call in a condition", (Fib(10) = 55) & (Value(Fib(10)) > 109))
END Calls;

PROCEDURE Structures;
VAR r: Rec; a: ARRAY 3 OF HUGEINT; t: Totals; i: LONGINT; sum: HUGEINT;
BEGIN
  r.c := "a"; r.h := -1; r.s := 5; r.g := Two32;
  Check("record layout", (r.c = "a") & (r.s = 5)); Equal("record field", r.h + r.g, 4294967295);
  a[0] := 1; a[1] := a[0] * Two32; a[2] := a[1] * (Two32 DIV 3);
  Equal("array", a[2], 6148914689804861440);
  NEW(t, 256); i := 0;
  WHILE i < 256 DO t[i] := i; t[i] := t[i] * Two32 + i; INC(i) END;
  sum := 0; i := 0; WHILE i < 256 DO INC(sum, t[i]); INC(t[i], 1); INC(i) END;
  Equal("open array sum", sum, 32640 * Two32 + 32640); Equal("open array element", t[255], 255 * Two32 + 256)
END Structures;

PROCEDURE Loops;
VAR i: LONGINT; s, x: HUGEINT;
BEGIN
  s := 0; i := 1;
  WHILE s < 1000000000000 DO s := s + LONG(i) * i; INC(i) END;
  Check("WHILE", i = 14423); Equal("sum of squares", s, 1000000892595);
  x := 1; i := 0;
  REPEAT x := x * 3; INC(i) UNTIL x > MAX(HUGEINT) DIV 3;
  Check("REPEAT", i = 39); Equal("3^39", x, 4052555153018976267)
END Loops;

PROCEDURE Run*;
BEGIN
  checks := 0; failed := 0;
  Literals; Pairs; Compare; Conversions; Ops; Calls; Structures; Loops;
  Equal("global", global, -1);
  out.String("HugeTest: "); out.Int(checks, 0); out.String(" checks, "); out.Int(failed, 0); out.String(" failed"); out.Ln
END Run;

BEGIN global := MIN(LONGINT); global := global + MAX(LONGINT)
END HugeTest.
