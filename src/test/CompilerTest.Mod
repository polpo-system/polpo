MODULE CompilerTest;  (** loksh CompilerTest.Run: code generator bugs fixed in polpo, on this port *)

(* Each case failed on at least one port before its fix (2026-09-30):
   x86: a DIV/MOD result moved to its hinted register was lost (ASH(1, i MOD 15));
   ARM: a dividend with a DIV in its index (a[i DIV 15] DIV k); global arrays of records whose
   size is not a power of 2, indexed by a variable;
   MIPS: RETURN x DIV y, RETURN x MOD y, RETURN ODD(...);
   RISC-V: b := i = 5 destroyed i;
   ROP2 (RISC-V, MIPS, ARMv7): a record copy from a VAR parameter at an offset beyond the
   immediate range; 8 VAR record arguments in a frame over 512 KB;
   RISC-V, MIPS: the end of a block move loop computed from a register reused for its length
   (w.cur := w.issuer copied nothing, or ran over memory);
   ARMv7: SYSTEM.MOVE counted its length down in the register of the variable that held it (the
   desktop sent X a request of the wrong length and hung), and copied a byte for a length of 0;
   RISC-V: b := x >= y (and unsigned, CHAR) was always TRUE: SLT, then XORI -1 instead of 1
   (2026-10-06, Coco/R of ETH found it);
   ARMv7: IN with a variable element and a shift by a variable count used R0 as scratch and
   destroyed a function result in it: F(t) # (t IN s), ASH(F(5), n) (2026-10-06);
   ARM: calls of a forward declared procedure with a nested procedure, made before its body,
   went to the nested procedure (DelNode of the ETH Coco/R, 2026-10-06);
   RISC-V: SYSTEM.MOVE loaded one byte ahead and read the byte after its source, a fault when the
   source ends a mapping (Files growing a mapped file, 2026-10-06). A fault there ends the run
   without the last line;
   ARM: RETURN f(x) of a REAL kept a VFP register; after 15 of them in a module it did not compile
   (out of registers, err 216; RealMath of OOC, 2026-10-06);
   ARM: a constant relation (1 = 1, SYSTEM.VAL(LONGINT, c) = n) as a value or in & and OR gave
   the condition NV, not an instruction on ARMv6 and later: SIGILL (2026-10-06);
   ARMv7: a call inside a designator of a later parameter, P(3, a[F(x)]), overwrote the registers
   of the parameters before it, which were stored early (the Scheme of Ceres Oberon, 2026-10-13);
   x86: a constant FALSE right of & (TRUE right of OR) under ~ trapped in the compiler, and with
   the constant TRUE (FALSE) the jumps of the left operand were lost in IF and WHILE (2026-10-14);
   ARMv7: in P(F(1), G(2), H(3)) the first parameter was H's result: the register of F's result was
   freed when G returned and H did not save it (2026-10-14);
   ARM, ROP2: in Sum(n: Node), Sum(n.left) inside WITH n: Pair was refused (err 113): the parameter
   of the call was checked against the narrowed type of n (2026-10-14);
   ARM: RETURN F(x) left R0 as the preferred register of the next GetReg, and RETURN a[i] of an
   open array in the next procedure stopped the compiler (division by zero, 2026-10-14);
   ARMv7: an index of a two-dimensional open array took the size of a row as a stale constant, not
   the register it was in: a[r, 3], a[r] as an open array argument (2026-10-14);
   ARM: LEN(a, n) of an open array parameter read the length from the elements of the array, not
   from beside its address; LEN(a) was right (2026-10-14);
   ARM: p^ of a POINTER TO ARRAY OF ARRAY passed to an open array parameter: loading the first length
   freed the register of p^, the second length was loaded into it and the address read after it
   came from there (a trap, 2026-10-14);
   all: the constant MIN(LONGINT) DIV (-1) or MOD (-1) stopped the compiler (division overflow on the
   host); since then DIV and MOD want a divisor > 0 on all ports, as in Oberon-07: a constant one <= 0
   is err 237, a variable one traps (10); x86 and ARM gave odd results for negative ones (2026-10-14);
   all: CAP cleared bit 5 of any character, CAP("7") was 17X and CAP("{") "["; only "a".."z"
   change now, folded and at run time (2026-10-14);
   x86: SHORT(x) of a LONGREAL stayed in full precision in the FPU, LONG(SHORT(x)) was x (2026-10-14);
   all: real literals were made with floating point arithmetic: 1.0D23 one unit in the last place off,
   3.4E38 and 1.7D308 too large, denormal numbers refused or 0; DecReal rounds them once (2026-10-14);
   x86, ROP2: the constant ENTIER(2147483647.5D0) was refused, the value was compared before ENTIER;
   ARM: ENTIER of a constant was not folded at all (2026-10-14);
   ARM: the constants are flushed into the code every 4 KB, with a branch over them; a flush between
   computing an offset from pc and the instruction reading PC moved the instruction away from its
   offset (a string assignment wrote into the code, Tetris), and the conditional branch of IF and
   WHILE took its position before a flush, the compiler stopped in FixLink; ENTIER truncated and
   subtracted 1 from any negative value, ENTIER(-2.0) was -3; FOR on a variable of an enclosing
   procedure compared and increased it through a register freed after the first assignment (PPM
   crashed) (2026-10-15);
   ARM: forward declarations of local procedures were refused (err 38);
   ARMv7: the registers live across a call were saved just above its arguments, and a call in its
   arguments with more arguments of its own overwrote them, x.f := Max(1, G(H(x, "s"))) stored
   through the length of "s" (WebNav, 2026-10-20). *)

IMPORT SYSTEM, Linux0, out;

TYPE
  Small = RECORD a: LONGINT; pad: ARRAY 4 OF CHAR; b: LONGINT END;  (* 12 bytes *)
  N = RECORD len: LONGINT; d: ARRAY 280 OF LONGINT END;
  M = RECORD m: N; minv: LONGINT; r2: N; one: N END;  (* one at offset 2252 *)
  Big = RECORD len: LONGINT; data: ARRAY 32768 OF CHAR END;
  Info = RECORD a, b, c, d, e, f, g, h: Big; bits: LONGINT END;  (* as TLSX509.CertInfo *)
  Work = POINTER TO RECORD cur, issuer: Info END;
  WNode = POINTER TO WNodeDesc; WNodeDesc = RECORD END;
  WPair = POINTER TO WPairDesc; WPairDesc = RECORD (WNodeDesc) left, right: WNode END;
  WLeaf = POINTER TO WLeafDesc; WLeafDesc = RECORD (WNodeDesc) value: LONGINT END;
  Saved = POINTER TO SavedDesc; SavedDesc = RECORD a, b, c: LONGINT END;

VAR
  cells: POINTER TO RECORD r: ARRAY 10 OF LONGINT END; cellx: LONGINT;
  fails, checks: LONGINT;
  g: ARRAY 3 OF Small;
  flag: BOOLEAN;
  row: ARRAY 4 OF INTEGER;
  grid: ARRAY 3, 4 OF INTEGER;
  pg0: ARRAY 64 OF CHAR; pstr: ARRAY 150, 6 OF CHAR; pg1: ARRAY 64 OF CHAR; ppad: ARRAY 8 OF LONGINT;
  pif: ARRAY 300 OF LONGINT;
  forLimit: INTEGER;

PROCEDURE Check(what: ARRAY OF CHAR; ok: BOOLEAN);
BEGIN
  INC(checks);
  IF ~ok THEN INC(fails); out.String("FAIL "); out.String(what); out.Ln END
END Check;

PROCEDURE ^Twice(x: LONGINT): LONGINT;

PROCEDURE CallTwice(x: LONGINT): LONGINT;
BEGIN RETURN Twice(x)
END CallTwice;

PROCEDURE Twice(x: LONGINT): LONGINT;
  PROCEDURE Nested(y: LONGINT): LONGINT;
  BEGIN RETURN y + 1000
  END Nested;
BEGIN
  IF x < 0 THEN RETURN Nested(x) END;
  RETURN 2 * x
END Twice;

PROCEDURE Id(x: LONGINT): LONGINT;
BEGIN RETURN x
END Id;

PROCEDURE InSet(t: INTEGER): BOOLEAN;
BEGIN RETURN t IN {8, 9, 10, 12, 13}
END InSet;

PROCEDURE Div(x, y: LONGINT): LONGINT;
BEGIN RETURN x DIV y
END Div;

PROCEDURE Mod(x, y: LONGINT): LONGINT;
BEGIN RETURN x MOD y
END Mod;

PROCEDURE OddBit(x, s: LONGINT): BOOLEAN;
BEGIN RETURN ODD(x DIV ASH(1, s))
END OddBit;

PROCEDURE CopyOne(VAR a: N; epos, elen: LONGINT; VAR mod: M; VAR res: N);
BEGIN res := mod.one
END CopyOne;

PROCEDURE Eight(VAR a, b, c, d, e, f, h, i: Big);
BEGIN a.len := 1; i.len := 8
END Eight;

PROCEDURE Frame;
VAR a, b, c, d, e, f, h, i, j, k, l, m, n, o, p, q: Big;
BEGIN
  Eight(a, b, c, d, e, f, h, i);
  Check("8 VAR records in a 512 KB frame", (a.len = 1) & (i.len = 8))
END Frame;

PROCEDURE BlockMove;
VAR w: Work;
BEGIN
  NEW(w); w.issuer.h.data[3] := "B"; w.issuer.bits := 5; w.cur.h.data[3] := "-";
  w.cur := w.issuer;
  Check("w.cur := w.issuer, 256 KB on the heap", (w.cur.h.data[3] = "B") & (w.cur.bits = 5))
END BlockMove;

(* the length n stays after SYSTEM.MOVE (as in Input.InternAtom); a length of 0 copies nothing *)
PROCEDURE Moved(name: ARRAY OF CHAR; VAR zero: BOOLEAN): LONGINT;
VAR b: ARRAY 16 OF LONGINT; n, k: LONGINT; c: ARRAY 4 OF CHAR;
BEGIN
  n := 0; WHILE (n < LEN(name)) & (name[n] # 0X) & (n < 48) DO INC(n) END;
  SYSTEM.MOVE(SYSTEM.ADR(name[0]), SYSTEM.ADR(b[0]), n);
  c[0] := "x"; k := 0; SYSTEM.MOVE(SYSTEM.ADR(name[0]), SYSTEM.ADR(c[0]), k); zero := c[0] = "x";
  RETURN n
END Moved;

(* constant relations as values *)
PROCEDURE ConstRel(): BOOLEAN;
CONST c = 1.5;
VAR b: BOOLEAN; i: LONGINT;
BEGIN
  i := 5; b := (1 = 1) & ~(1 = 2) & ((i = 5) & (1 = 1)) & ((1 = 2) OR (i = 5)) & ~((1 = 2) OR (i = 6));
  RETURN b & (SYSTEM.VAL(LONGINT, c) = 3FC00000H)
END ConstRel;

(* 16 times RETURN of a REAL function result (each kept a register on ARM) *)
PROCEDURE Sq(x: REAL): REAL; BEGIN RETURN x * x END Sq;
PROCEDURE RF1(x: REAL): REAL; BEGIN RETURN Sq(x) END RF1;
PROCEDURE RF2(x: REAL): REAL; BEGIN RETURN Sq(x) END RF2;
PROCEDURE RF3(x: REAL): REAL; BEGIN RETURN Sq(x) END RF3;
PROCEDURE RF4(x: REAL): REAL; BEGIN RETURN Sq(x) END RF4;
PROCEDURE RF5(x: REAL): REAL; BEGIN RETURN Sq(x) END RF5;
PROCEDURE RF6(x: REAL): REAL; BEGIN RETURN Sq(x) END RF6;
PROCEDURE RF7(x: REAL): REAL; BEGIN RETURN Sq(x) END RF7;
PROCEDURE RF8(x: REAL): REAL; BEGIN RETURN Sq(x) END RF8;
PROCEDURE RF9(x: REAL): REAL; BEGIN RETURN Sq(x) END RF9;
PROCEDURE RF10(x: REAL): REAL; BEGIN RETURN Sq(x) END RF10;
PROCEDURE RF11(x: REAL): REAL; BEGIN RETURN Sq(x) END RF11;
PROCEDURE RF12(x: REAL): REAL; BEGIN RETURN Sq(x) END RF12;
PROCEDURE RF13(x: REAL): REAL; BEGIN RETURN Sq(x) END RF13;
PROCEDURE RF14(x: REAL): REAL; BEGIN RETURN Sq(x) END RF14;
PROCEDURE RF15(x: REAL): REAL; BEGIN RETURN Sq(x) END RF15;
PROCEDURE RF16(x: REAL): REAL; BEGIN RETURN Sq(x) END RF16;

(* bytes that end exactly at the end of a mapping, the page after it unmapped *)
PROCEDURE True(): BOOLEAN; BEGIN RETURN TRUE END True;
PROCEDURE Minus(): LONGINT; BEGIN RETURN -1 END Minus;
PROCEDURE NotAnd(): BOOLEAN; BEGIN RETURN ~True() & (Minus() < 0) END NotAnd;  (* FALSE *)
PROCEDURE OrRel(): BOOLEAN; BEGIN RETURN ~True() OR (Minus() > 0) END OrRel;    (* FALSE *)

PROCEDURE EndOfMap(): BOOLEAN;
VAR page, n, r: LONGINT; buf: ARRAY 64 OF CHAR;
BEGIN
  page := Linux0.Mmap20(0, 2 * Linux0.PageSize, 3, Linux0.MAPPRIVATE + Linux0.MAPANONYMOUS, -1, 0);
  r := Linux0.Munmap0(page + Linux0.PageSize, Linux0.PageSize);
  SYSTEM.PUT(page + Linux0.PageSize - 1, "z");
  n := 1;
  WHILE n <= 64 DO SYSTEM.MOVE(page + Linux0.PageSize - n, SYSTEM.ADR(buf[0]), n); INC(n) END;
  r := Linux0.Munmap0(page, Linux0.PageSize);
  RETURN buf[63] = "z"
END EndOfMap;

(* five parameters, the later ones with calls inside an index: ARMv7 stored the first ones in their
   registers before those calls and the calls overwrote them *)
PROCEDURE Five(t: SHORTINT; a, b, c, d: LONGINT): LONGINT;
BEGIN RETURN t * 10000 + a * 1000 + b * 100 + c * 10 + d
END Five;

PROCEDURE CallInIndex(): BOOLEAN;
VAR i: INTEGER;
BEGIN
  NEW(cells); i := 0; WHILE i < 10 DO cells.r[i] := i; INC(i) END;
  cellx := 3;
  RETURN Five(3, cells.r[Id(1)], cells.r[Id(cellx + 1)], cells.r[Id(cellx)], 2) = 31432
END CallInIndex;

(* every parameter a call: ARMv7 moved the second result out of the result register, which freed
   that register though the first result was restored into it; the third call then overwrote it *)
PROCEDURE Three(a, b, c: REAL): REAL;
BEGIN RETURN a * 100 + b * 10 + c
END Three;

PROCEDURE AllCalls(): BOOLEAN;
BEGIN RETURN (Five(1, Id(2), Id(3), Id(4), Id(5)) = 12345) & (Three(Sq(1.0), Sq(2.0), Sq(3.0)) = 149.0)
END AllCalls;

(* RETURN F(x) followed by RETURN a[i] of an open array *)
PROCEDURE RetCall(x: LONGINT): LONGINT;
BEGIN RETURN Id(x)
END RetCall;

PROCEDURE OpenElem(VAR a: ARRAY OF INTEGER; i: LONGINT): LONGINT;
BEGIN RETURN a[i]
END OpenElem;

(* rows of a two-dimensional open array *)
PROCEDURE RowSum(VAR row: ARRAY OF INTEGER): LONGINT;
VAR i, s: LONGINT;
BEGIN s := 0; i := 0; WHILE i < LEN(row) DO s := s + row[i]; INC(i) END; RETURN s
END RowSum;

PROCEDURE OpenRows(VAR a: ARRAY OF ARRAY OF INTEGER; r: LONGINT): BOOLEAN;
  PROCEDURE Inner(): LONGINT;
  BEGIN RETURN a[1, 2]
  END Inner;
BEGIN RETURN (a[r, 3] = 23) & (RowSum(a[r]) = 86) & (Inner() = 12)
END OpenRows;

(* LEN with a dimension, also from a nested procedure *)
PROCEDURE Lens(VAR a: ARRAY OF ARRAY OF INTEGER): BOOLEAN;
  PROCEDURE Inner(): LONGINT;
  BEGIN RETURN LEN(a, 1) * 10 + LEN(a, 0)
  END Inner;
BEGIN RETURN (LEN(a, 1) = 4) & (LEN(a, 0) = 3) & (LEN(a) = 3) & (Inner() = 43)
END Lens;

(* an open array on the heap passed to an open array parameter *)
PROCEDURE HeapArg(): BOOLEAN;
VAR p: POINTER TO ARRAY OF ARRAY OF INTEGER;
BEGIN NEW(p, 3, 4); p[2, 3] := 23; p[2, 0] := 63; RETURN Lens(p^) & (RowSum(p[2]) = 86)
END HeapArg;

(* CAP of characters that are not letters *)
PROCEDURE CapOnly(): BOOLEAN;
CONST seven = CAP("7");
VAR c, d, e: CHAR;
BEGIN c := "{"; d := "z"; e := "@";
  RETURN (seven = "7") & (CAP(c) = "{") & (CAP(d) = "Z") & (CAP(e) = "@") & (CAP("a") = "A")
END CapOnly;

(* SHORT of a LONGREAL inside an expression is rounded to REAL *)
PROCEDURE ShortReal(): BOOLEAN;
VAR x, y: LONGREAL; r: REAL;
BEGIN x := 0.1D0; r := SHORT(x); y := LONG(SHORT(x));
  RETURN (y = LONG(r)) & (SHORT(x) * 1.0D0 = LONG(r)) & (y # x)
END ShortReal;

(* real literals, correctly rounded, also at the ends of the range *)
(* the high and low words of x, in the byte order of the machine *)
PROCEDURE Words(VAR x: LONGREAL; VAR hi, lo: LONGINT);
VAR w: LONGINT; c: CHAR;
BEGIN
  w := 1; SYSTEM.GET(SYSTEM.ADR(w), c);
  IF c = 0X THEN SYSTEM.GET(SYSTEM.ADR(x), hi); SYSTEM.GET(SYSTEM.ADR(x) + 4, lo)
  ELSE SYSTEM.GET(SYSTEM.ADR(x), lo); SYSTEM.GET(SYSTEM.ADR(x) + 4, hi)
  END
END Words;

PROCEDURE Literals(): BOOLEAN;
VAR x: LONGREAL; r: REAL; lo, hi, b: LONGINT; ok: BOOLEAN;
BEGIN
  x := 1.0D23; Words(x, hi, lo);
  ok := (hi = 44B52D02H) & (lo = 0C7E14AF6H);
  x := 4.9406564584124654D-324; Words(x, hi, lo);
  ok := ok & (hi = 0) & (lo = 1);
  x := 1.7976931348623157D308; Words(x, hi, lo);
  ok := ok & (hi = 7FEFFFFFH) & (lo = -1);
  r := 3.4E38; SYSTEM.GET(SYSTEM.ADR(r), b); ok := ok & (b = 7F7FC99EH);
  r := 1.4E-45; SYSTEM.GET(SYSTEM.ADR(r), b); ok := ok & (b = 1);
  RETURN ok
END Literals;

(* ENTIER of constants near the ends of LONGINT *)
PROCEDURE ConstEntier(): BOOLEAN;
CONST a = ENTIER(2147483647.5D0); b = ENTIER(-2147483648.0D0); c = ENTIER(-0.5); d = ENTIER(2.5E0);
BEGIN RETURN (a = MAX(LONGINT)) & (b = MIN(LONGINT)) & (c = -1) & (d = 2)
END ConstEntier;

(* the procedure called inside a WITH on its own parameter: its parameter keeps the declared type *)
PROCEDURE WSum(n: WNode): LONGINT;
VAR s: LONGINT;
BEGIN
  IF n IS WPair THEN WITH n: WPair DO s := WSum(n.left) + WSum(n.right) END
  ELSE s := n(WLeaf).value
  END;
  RETURN s
END WSum;

PROCEDURE WithSelf(): BOOLEAN;
VAR p, q: WPair; a, b, c: WLeaf;
BEGIN
  NEW(a); a.value := 1; NEW(b); b.value := 20; NEW(c); c.value := 300;
  NEW(q); q.left := b; q.right := c; NEW(p); p.left := a; p.right := q;
  RETURN WSum(p) = 321
END WithSelf;

(* the constant operands are kept by the parser (side effects of the other one) *)
PROCEDURE ConstCond(b, d: BOOLEAN): BOOLEAN;
VAR r: BOOLEAN; n: INTEGER;
BEGIN r := b & ~(b & FALSE) & ~(d OR TRUE) = FALSE;
  n := 0; IF d & ~(b & FALSE) THEN n := 1 END;
  IF b & TRUE THEN INC(n, 2) END;
  RETURN r & (n = 2) & (b OR ~(b OR TRUE)) & ~(d & ~(d & FALSE))
END ConstCond;

PROCEDURE VarEntier(): BOOLEAN;  (* ARM: ENTIER of a negative whole number was 1 too small *)
VAR r: REAL; d: LONGREAL; a, b, c, e: LONGINT;
BEGIN
  r := -2.0; a := ENTIER(r); r := -2.5; b := ENTIER(r); d := -3.0D0; c := ENTIER(d);
  d := -2147483648.0D0; e := ENTIER(d);
  RETURN (a = -2) & (b = -3) & (c = -3) & (e = MIN(LONGINT))
END VarEntier;

PROCEDURE OuterFor(): LONGINT;  (* ARM: FOR on a variable of the enclosing procedure, a limit from a global *)
VAR i, n: INTEGER;
  PROCEDURE Inner;
  BEGIN
    n := 0; FOR i := 0 TO forLimit DO INC(n) END
  END Inner;
BEGIN
  Inner; RETURN n
END OuterFor;

PROCEDURE PoolFill;  (* ARM: 150 string assignments, the constants are flushed inside one of them
  (the six ppad lines place the flush where the old code lost a string) *)
BEGIN
  ppad[0] := 0; ppad[1] := 1; ppad[2] := 2; ppad[3] := 3; ppad[4] := 4; ppad[5] := 5;
  pstr[0] := "-----"; pstr[1] := "-----"; pstr[2] := "-----"; pstr[3] := "-----"; pstr[4] := "-----"; pstr[5] := "-----"; pstr[6] := "-----"; pstr[7] := "-----"; pstr[8] := "-----"; pstr[9] := "-----";
  pstr[10] := "-----"; pstr[11] := "-----"; pstr[12] := "-----"; pstr[13] := "-----"; pstr[14] := "-----"; pstr[15] := "-----"; pstr[16] := "-----"; pstr[17] := "-----"; pstr[18] := "-----"; pstr[19] := "-----";
  pstr[20] := "-----"; pstr[21] := "-----"; pstr[22] := "-----"; pstr[23] := "-----"; pstr[24] := "-----"; pstr[25] := "-----"; pstr[26] := "-----"; pstr[27] := "-----"; pstr[28] := "-----"; pstr[29] := "-----";
  pstr[30] := "-----"; pstr[31] := "-----"; pstr[32] := "-----"; pstr[33] := "-----"; pstr[34] := "-----"; pstr[35] := "-----"; pstr[36] := "-----"; pstr[37] := "-----"; pstr[38] := "-----"; pstr[39] := "-----";
  pstr[40] := "-----"; pstr[41] := "-----"; pstr[42] := "-----"; pstr[43] := "-----"; pstr[44] := "-----"; pstr[45] := "-----"; pstr[46] := "-----"; pstr[47] := "-----"; pstr[48] := "-----"; pstr[49] := "-----";
  pstr[50] := "-----"; pstr[51] := "-----"; pstr[52] := "-----"; pstr[53] := "-----"; pstr[54] := "-----"; pstr[55] := "-----"; pstr[56] := "-----"; pstr[57] := "-----"; pstr[58] := "-----"; pstr[59] := "-----";
  pstr[60] := "-----"; pstr[61] := "-----"; pstr[62] := "-----"; pstr[63] := "-----"; pstr[64] := "-----"; pstr[65] := "-----"; pstr[66] := "-----"; pstr[67] := "-----"; pstr[68] := "-----"; pstr[69] := "-----";
  pstr[70] := "-----"; pstr[71] := "-----"; pstr[72] := "-----"; pstr[73] := "-----"; pstr[74] := "-----"; pstr[75] := "-----"; pstr[76] := "-----"; pstr[77] := "-----"; pstr[78] := "-----"; pstr[79] := "-----";
  pstr[80] := "-----"; pstr[81] := "-----"; pstr[82] := "-----"; pstr[83] := "-----"; pstr[84] := "-----"; pstr[85] := "-----"; pstr[86] := "-----"; pstr[87] := "-----"; pstr[88] := "-----"; pstr[89] := "-----";
  pstr[90] := "-----"; pstr[91] := "-----"; pstr[92] := "-----"; pstr[93] := "-----"; pstr[94] := "-----"; pstr[95] := "-----"; pstr[96] := "-----"; pstr[97] := "-----"; pstr[98] := "-----"; pstr[99] := "-----";
  pstr[100] := "-----"; pstr[101] := "-----"; pstr[102] := "-----"; pstr[103] := "-----"; pstr[104] := "-----"; pstr[105] := "-----"; pstr[106] := "-----"; pstr[107] := "-----"; pstr[108] := "-----"; pstr[109] := "-----";
  pstr[110] := "-----"; pstr[111] := "-----"; pstr[112] := "-----"; pstr[113] := "-----"; pstr[114] := "-----"; pstr[115] := "-----"; pstr[116] := "-----"; pstr[117] := "-----"; pstr[118] := "-----"; pstr[119] := "-----";
  pstr[120] := "-----"; pstr[121] := "-----"; pstr[122] := "-----"; pstr[123] := "-----"; pstr[124] := "-----"; pstr[125] := "-----"; pstr[126] := "-----"; pstr[127] := "-----"; pstr[128] := "-----"; pstr[129] := "-----";
  pstr[130] := "-----"; pstr[131] := "-----"; pstr[132] := "-----"; pstr[133] := "-----"; pstr[134] := "-----"; pstr[135] := "-----"; pstr[136] := "-----"; pstr[137] := "-----"; pstr[138] := "-----"; pstr[139] := "-----";
  pstr[140] := "-----"; pstr[141] := "-----"; pstr[142] := "-----"; pstr[143] := "-----"; pstr[144] := "-----"; pstr[145] := "-----"; pstr[146] := "-----"; pstr[147] := "-----"; pstr[148] := "-----"; pstr[149] := "-----";
END PoolFill;

PROCEDURE PoolStrings(): BOOLEAN;
VAR i, ok: LONGINT; guards: BOOLEAN;
BEGIN
  i := 0; WHILE i < 64 DO pg0[i] := "g"; pg1[i] := "g"; INC(i) END;
  PoolFill;
  guards := TRUE; i := 0; WHILE i < 64 DO IF (pg0[i] # "g") OR (pg1[i] # "g") THEN guards := FALSE END; INC(i) END;
  ok := 0; i := 0; WHILE i < 150 DO IF pstr[i] = "-----" THEN INC(ok) END; INC(i) END;
  RETURN guards & (ok = 150)
END PoolStrings;

PROCEDURE PoolIfs(): LONGINT;  (* ARM: 300 IF with constants from the pool, a flush comes in a branch *)
VAR n: LONGINT;
BEGIN
  n := 0;
  ppad[0] := 0; ppad[1] := 1; ppad[2] := 2;  (* so that a flush comes in a branch with the old OBE.CFJ *)
  IF pif[0] = 100001 THEN INC(n) END;
  IF pif[1] = 100008 THEN INC(n) END;
  IF pif[2] = 100015 THEN INC(n) END;
  IF pif[3] = 100022 THEN INC(n) END;
  IF pif[4] = 100029 THEN INC(n) END;
  IF pif[5] = 100036 THEN INC(n) END;
  IF pif[6] = 100043 THEN INC(n) END;
  IF pif[7] = 100050 THEN INC(n) END;
  IF pif[8] = 100057 THEN INC(n) END;
  IF pif[9] = 100064 THEN INC(n) END;
  IF pif[10] = 100071 THEN INC(n) END;
  IF pif[11] = 100078 THEN INC(n) END;
  IF pif[12] = 100085 THEN INC(n) END;
  IF pif[13] = 100092 THEN INC(n) END;
  IF pif[14] = 100099 THEN INC(n) END;
  IF pif[15] = 100106 THEN INC(n) END;
  IF pif[16] = 100113 THEN INC(n) END;
  IF pif[17] = 100120 THEN INC(n) END;
  IF pif[18] = 100127 THEN INC(n) END;
  IF pif[19] = 100134 THEN INC(n) END;
  IF pif[20] = 100141 THEN INC(n) END;
  IF pif[21] = 100148 THEN INC(n) END;
  IF pif[22] = 100155 THEN INC(n) END;
  IF pif[23] = 100162 THEN INC(n) END;
  IF pif[24] = 100169 THEN INC(n) END;
  IF pif[25] = 100176 THEN INC(n) END;
  IF pif[26] = 100183 THEN INC(n) END;
  IF pif[27] = 100190 THEN INC(n) END;
  IF pif[28] = 100197 THEN INC(n) END;
  IF pif[29] = 100204 THEN INC(n) END;
  IF pif[30] = 100211 THEN INC(n) END;
  IF pif[31] = 100218 THEN INC(n) END;
  IF pif[32] = 100225 THEN INC(n) END;
  IF pif[33] = 100232 THEN INC(n) END;
  IF pif[34] = 100239 THEN INC(n) END;
  IF pif[35] = 100246 THEN INC(n) END;
  IF pif[36] = 100253 THEN INC(n) END;
  IF pif[37] = 100260 THEN INC(n) END;
  IF pif[38] = 100267 THEN INC(n) END;
  IF pif[39] = 100274 THEN INC(n) END;
  IF pif[40] = 100281 THEN INC(n) END;
  IF pif[41] = 100288 THEN INC(n) END;
  IF pif[42] = 100295 THEN INC(n) END;
  IF pif[43] = 100302 THEN INC(n) END;
  IF pif[44] = 100309 THEN INC(n) END;
  IF pif[45] = 100316 THEN INC(n) END;
  IF pif[46] = 100323 THEN INC(n) END;
  IF pif[47] = 100330 THEN INC(n) END;
  IF pif[48] = 100337 THEN INC(n) END;
  IF pif[49] = 100344 THEN INC(n) END;
  IF pif[50] = 100351 THEN INC(n) END;
  IF pif[51] = 100358 THEN INC(n) END;
  IF pif[52] = 100365 THEN INC(n) END;
  IF pif[53] = 100372 THEN INC(n) END;
  IF pif[54] = 100379 THEN INC(n) END;
  IF pif[55] = 100386 THEN INC(n) END;
  IF pif[56] = 100393 THEN INC(n) END;
  IF pif[57] = 100400 THEN INC(n) END;
  IF pif[58] = 100407 THEN INC(n) END;
  IF pif[59] = 100414 THEN INC(n) END;
  IF pif[60] = 100421 THEN INC(n) END;
  IF pif[61] = 100428 THEN INC(n) END;
  IF pif[62] = 100435 THEN INC(n) END;
  IF pif[63] = 100442 THEN INC(n) END;
  IF pif[64] = 100449 THEN INC(n) END;
  IF pif[65] = 100456 THEN INC(n) END;
  IF pif[66] = 100463 THEN INC(n) END;
  IF pif[67] = 100470 THEN INC(n) END;
  IF pif[68] = 100477 THEN INC(n) END;
  IF pif[69] = 100484 THEN INC(n) END;
  IF pif[70] = 100491 THEN INC(n) END;
  IF pif[71] = 100498 THEN INC(n) END;
  IF pif[72] = 100505 THEN INC(n) END;
  IF pif[73] = 100512 THEN INC(n) END;
  IF pif[74] = 100519 THEN INC(n) END;
  IF pif[75] = 100526 THEN INC(n) END;
  IF pif[76] = 100533 THEN INC(n) END;
  IF pif[77] = 100540 THEN INC(n) END;
  IF pif[78] = 100547 THEN INC(n) END;
  IF pif[79] = 100554 THEN INC(n) END;
  IF pif[80] = 100561 THEN INC(n) END;
  IF pif[81] = 100568 THEN INC(n) END;
  IF pif[82] = 100575 THEN INC(n) END;
  IF pif[83] = 100582 THEN INC(n) END;
  IF pif[84] = 100589 THEN INC(n) END;
  IF pif[85] = 100596 THEN INC(n) END;
  IF pif[86] = 100603 THEN INC(n) END;
  IF pif[87] = 100610 THEN INC(n) END;
  IF pif[88] = 100617 THEN INC(n) END;
  IF pif[89] = 100624 THEN INC(n) END;
  IF pif[90] = 100631 THEN INC(n) END;
  IF pif[91] = 100638 THEN INC(n) END;
  IF pif[92] = 100645 THEN INC(n) END;
  IF pif[93] = 100652 THEN INC(n) END;
  IF pif[94] = 100659 THEN INC(n) END;
  IF pif[95] = 100666 THEN INC(n) END;
  IF pif[96] = 100673 THEN INC(n) END;
  IF pif[97] = 100680 THEN INC(n) END;
  IF pif[98] = 100687 THEN INC(n) END;
  IF pif[99] = 100694 THEN INC(n) END;
  IF pif[100] = 100701 THEN INC(n) END;
  IF pif[101] = 100708 THEN INC(n) END;
  IF pif[102] = 100715 THEN INC(n) END;
  IF pif[103] = 100722 THEN INC(n) END;
  IF pif[104] = 100729 THEN INC(n) END;
  IF pif[105] = 100736 THEN INC(n) END;
  IF pif[106] = 100743 THEN INC(n) END;
  IF pif[107] = 100750 THEN INC(n) END;
  IF pif[108] = 100757 THEN INC(n) END;
  IF pif[109] = 100764 THEN INC(n) END;
  IF pif[110] = 100771 THEN INC(n) END;
  IF pif[111] = 100778 THEN INC(n) END;
  IF pif[112] = 100785 THEN INC(n) END;
  IF pif[113] = 100792 THEN INC(n) END;
  IF pif[114] = 100799 THEN INC(n) END;
  IF pif[115] = 100806 THEN INC(n) END;
  IF pif[116] = 100813 THEN INC(n) END;
  IF pif[117] = 100820 THEN INC(n) END;
  IF pif[118] = 100827 THEN INC(n) END;
  IF pif[119] = 100834 THEN INC(n) END;
  IF pif[120] = 100841 THEN INC(n) END;
  IF pif[121] = 100848 THEN INC(n) END;
  IF pif[122] = 100855 THEN INC(n) END;
  IF pif[123] = 100862 THEN INC(n) END;
  IF pif[124] = 100869 THEN INC(n) END;
  IF pif[125] = 100876 THEN INC(n) END;
  IF pif[126] = 100883 THEN INC(n) END;
  IF pif[127] = 100890 THEN INC(n) END;
  IF pif[128] = 100897 THEN INC(n) END;
  IF pif[129] = 100904 THEN INC(n) END;
  IF pif[130] = 100911 THEN INC(n) END;
  IF pif[131] = 100918 THEN INC(n) END;
  IF pif[132] = 100925 THEN INC(n) END;
  IF pif[133] = 100932 THEN INC(n) END;
  IF pif[134] = 100939 THEN INC(n) END;
  IF pif[135] = 100946 THEN INC(n) END;
  IF pif[136] = 100953 THEN INC(n) END;
  IF pif[137] = 100960 THEN INC(n) END;
  IF pif[138] = 100967 THEN INC(n) END;
  IF pif[139] = 100974 THEN INC(n) END;
  IF pif[140] = 100981 THEN INC(n) END;
  IF pif[141] = 100988 THEN INC(n) END;
  IF pif[142] = 100995 THEN INC(n) END;
  IF pif[143] = 101002 THEN INC(n) END;
  IF pif[144] = 101009 THEN INC(n) END;
  IF pif[145] = 101016 THEN INC(n) END;
  IF pif[146] = 101023 THEN INC(n) END;
  IF pif[147] = 101030 THEN INC(n) END;
  IF pif[148] = 101037 THEN INC(n) END;
  IF pif[149] = 101044 THEN INC(n) END;
  IF pif[150] = 101051 THEN INC(n) END;
  IF pif[151] = 101058 THEN INC(n) END;
  IF pif[152] = 101065 THEN INC(n) END;
  IF pif[153] = 101072 THEN INC(n) END;
  IF pif[154] = 101079 THEN INC(n) END;
  IF pif[155] = 101086 THEN INC(n) END;
  IF pif[156] = 101093 THEN INC(n) END;
  IF pif[157] = 101100 THEN INC(n) END;
  IF pif[158] = 101107 THEN INC(n) END;
  IF pif[159] = 101114 THEN INC(n) END;
  IF pif[160] = 101121 THEN INC(n) END;
  IF pif[161] = 101128 THEN INC(n) END;
  IF pif[162] = 101135 THEN INC(n) END;
  IF pif[163] = 101142 THEN INC(n) END;
  IF pif[164] = 101149 THEN INC(n) END;
  IF pif[165] = 101156 THEN INC(n) END;
  IF pif[166] = 101163 THEN INC(n) END;
  IF pif[167] = 101170 THEN INC(n) END;
  IF pif[168] = 101177 THEN INC(n) END;
  IF pif[169] = 101184 THEN INC(n) END;
  IF pif[170] = 101191 THEN INC(n) END;
  IF pif[171] = 101198 THEN INC(n) END;
  IF pif[172] = 101205 THEN INC(n) END;
  IF pif[173] = 101212 THEN INC(n) END;
  IF pif[174] = 101219 THEN INC(n) END;
  IF pif[175] = 101226 THEN INC(n) END;
  IF pif[176] = 101233 THEN INC(n) END;
  IF pif[177] = 101240 THEN INC(n) END;
  IF pif[178] = 101247 THEN INC(n) END;
  IF pif[179] = 101254 THEN INC(n) END;
  IF pif[180] = 101261 THEN INC(n) END;
  IF pif[181] = 101268 THEN INC(n) END;
  IF pif[182] = 101275 THEN INC(n) END;
  IF pif[183] = 101282 THEN INC(n) END;
  IF pif[184] = 101289 THEN INC(n) END;
  IF pif[185] = 101296 THEN INC(n) END;
  IF pif[186] = 101303 THEN INC(n) END;
  IF pif[187] = 101310 THEN INC(n) END;
  IF pif[188] = 101317 THEN INC(n) END;
  IF pif[189] = 101324 THEN INC(n) END;
  IF pif[190] = 101331 THEN INC(n) END;
  IF pif[191] = 101338 THEN INC(n) END;
  IF pif[192] = 101345 THEN INC(n) END;
  IF pif[193] = 101352 THEN INC(n) END;
  IF pif[194] = 101359 THEN INC(n) END;
  IF pif[195] = 101366 THEN INC(n) END;
  IF pif[196] = 101373 THEN INC(n) END;
  IF pif[197] = 101380 THEN INC(n) END;
  IF pif[198] = 101387 THEN INC(n) END;
  IF pif[199] = 101394 THEN INC(n) END;
  IF pif[200] = 101401 THEN INC(n) END;
  IF pif[201] = 101408 THEN INC(n) END;
  IF pif[202] = 101415 THEN INC(n) END;
  IF pif[203] = 101422 THEN INC(n) END;
  IF pif[204] = 101429 THEN INC(n) END;
  IF pif[205] = 101436 THEN INC(n) END;
  IF pif[206] = 101443 THEN INC(n) END;
  IF pif[207] = 101450 THEN INC(n) END;
  IF pif[208] = 101457 THEN INC(n) END;
  IF pif[209] = 101464 THEN INC(n) END;
  IF pif[210] = 101471 THEN INC(n) END;
  IF pif[211] = 101478 THEN INC(n) END;
  IF pif[212] = 101485 THEN INC(n) END;
  IF pif[213] = 101492 THEN INC(n) END;
  IF pif[214] = 101499 THEN INC(n) END;
  IF pif[215] = 101506 THEN INC(n) END;
  IF pif[216] = 101513 THEN INC(n) END;
  IF pif[217] = 101520 THEN INC(n) END;
  IF pif[218] = 101527 THEN INC(n) END;
  IF pif[219] = 101534 THEN INC(n) END;
  IF pif[220] = 101541 THEN INC(n) END;
  IF pif[221] = 101548 THEN INC(n) END;
  IF pif[222] = 101555 THEN INC(n) END;
  IF pif[223] = 101562 THEN INC(n) END;
  IF pif[224] = 101569 THEN INC(n) END;
  IF pif[225] = 101576 THEN INC(n) END;
  IF pif[226] = 101583 THEN INC(n) END;
  IF pif[227] = 101590 THEN INC(n) END;
  IF pif[228] = 101597 THEN INC(n) END;
  IF pif[229] = 101604 THEN INC(n) END;
  IF pif[230] = 101611 THEN INC(n) END;
  IF pif[231] = 101618 THEN INC(n) END;
  IF pif[232] = 101625 THEN INC(n) END;
  IF pif[233] = 101632 THEN INC(n) END;
  IF pif[234] = 101639 THEN INC(n) END;
  IF pif[235] = 101646 THEN INC(n) END;
  IF pif[236] = 101653 THEN INC(n) END;
  IF pif[237] = 101660 THEN INC(n) END;
  IF pif[238] = 101667 THEN INC(n) END;
  IF pif[239] = 101674 THEN INC(n) END;
  IF pif[240] = 101681 THEN INC(n) END;
  IF pif[241] = 101688 THEN INC(n) END;
  IF pif[242] = 101695 THEN INC(n) END;
  IF pif[243] = 101702 THEN INC(n) END;
  IF pif[244] = 101709 THEN INC(n) END;
  IF pif[245] = 101716 THEN INC(n) END;
  IF pif[246] = 101723 THEN INC(n) END;
  IF pif[247] = 101730 THEN INC(n) END;
  IF pif[248] = 101737 THEN INC(n) END;
  IF pif[249] = 101744 THEN INC(n) END;
  IF pif[250] = 101751 THEN INC(n) END;
  IF pif[251] = 101758 THEN INC(n) END;
  IF pif[252] = 101765 THEN INC(n) END;
  IF pif[253] = 101772 THEN INC(n) END;
  IF pif[254] = 101779 THEN INC(n) END;
  IF pif[255] = 101786 THEN INC(n) END;
  IF pif[256] = 101793 THEN INC(n) END;
  IF pif[257] = 101800 THEN INC(n) END;
  IF pif[258] = 101807 THEN INC(n) END;
  IF pif[259] = 101814 THEN INC(n) END;
  IF pif[260] = 101821 THEN INC(n) END;
  IF pif[261] = 101828 THEN INC(n) END;
  IF pif[262] = 101835 THEN INC(n) END;
  IF pif[263] = 101842 THEN INC(n) END;
  IF pif[264] = 101849 THEN INC(n) END;
  IF pif[265] = 101856 THEN INC(n) END;
  IF pif[266] = 101863 THEN INC(n) END;
  IF pif[267] = 101870 THEN INC(n) END;
  IF pif[268] = 101877 THEN INC(n) END;
  IF pif[269] = 101884 THEN INC(n) END;
  IF pif[270] = 101891 THEN INC(n) END;
  IF pif[271] = 101898 THEN INC(n) END;
  IF pif[272] = 101905 THEN INC(n) END;
  IF pif[273] = 101912 THEN INC(n) END;
  IF pif[274] = 101919 THEN INC(n) END;
  IF pif[275] = 101926 THEN INC(n) END;
  IF pif[276] = 101933 THEN INC(n) END;
  IF pif[277] = 101940 THEN INC(n) END;
  IF pif[278] = 101947 THEN INC(n) END;
  IF pif[279] = 101954 THEN INC(n) END;
  IF pif[280] = 101961 THEN INC(n) END;
  IF pif[281] = 101968 THEN INC(n) END;
  IF pif[282] = 101975 THEN INC(n) END;
  IF pif[283] = 101982 THEN INC(n) END;
  IF pif[284] = 101989 THEN INC(n) END;
  IF pif[285] = 101996 THEN INC(n) END;
  IF pif[286] = 102003 THEN INC(n) END;
  IF pif[287] = 102010 THEN INC(n) END;
  IF pif[288] = 102017 THEN INC(n) END;
  IF pif[289] = 102024 THEN INC(n) END;
  IF pif[290] = 102031 THEN INC(n) END;
  IF pif[291] = 102038 THEN INC(n) END;
  IF pif[292] = 102045 THEN INC(n) END;
  IF pif[293] = 102052 THEN INC(n) END;
  IF pif[294] = 102059 THEN INC(n) END;
  IF pif[295] = 102066 THEN INC(n) END;
  IF pif[296] = 102073 THEN INC(n) END;
  IF pif[297] = 102080 THEN INC(n) END;
  IF pif[298] = 102087 THEN INC(n) END;
  IF pif[299] = 102094 THEN INC(n) END;
  RETURN n
END PoolIfs;

PROCEDURE PoolBranches(): BOOLEAN;
VAR i: LONGINT;
BEGIN
  i := 0; WHILE i < 300 DO IF i MOD 3 = 0 THEN pif[i] := 100001 + i * 7 ELSE pif[i] := 0 END; INC(i) END;
  RETURN PoolIfs() = 100
END PoolBranches;

PROCEDURE LocalForward(n: LONGINT): LONGINT;
VAR base: LONGINT;

  PROCEDURE ^Odd(k: LONGINT): LONGINT;

  PROCEDURE Even(k: LONGINT): LONGINT;
  BEGIN
    IF k = 0 THEN RETURN base ELSE RETURN Odd(k - 1) + 1 END
  END Even;

  PROCEDURE Odd(k: LONGINT): LONGINT;
  BEGIN
    IF k = 0 THEN RETURN base + 1000 ELSE RETURN Even(k - 1) + 10 END
  END Odd;

BEGIN base := 7; RETURN Even(n)
END LocalForward;

PROCEDURE Larger(x, y: LONGINT): LONGINT;
BEGIN IF x > y THEN RETURN x ELSE RETURN y END
END Larger;

PROCEDURE SavedLen(p: Saved; s: ARRAY OF CHAR): LONGINT;
VAR i: LONGINT;
BEGIN i := 0; WHILE s[i] # 0X DO INC(i) END; RETURN i + p.a
END SavedLen;

PROCEDURE SavedAcross(): BOOLEAN;
VAR r: Saved;
BEGIN
  NEW(r); r.a := 5; r.b := 0; r.c := 0;
  r.c := Larger(1, Id(SavedLen(r, "colspan")));
  RETURN (r.a = 5) & (r.b = 0) & (r.c = 12)
END SavedAcross;

(* ARMv7 (software division): the result of F in R0 was overwritten by the divisor *)
PROCEDURE CallDiv(a, b: LONGINT): BOOLEAN;
BEGIN RETURN (Id(a) DIV b = 14) & (Id(a) MOD b = 2) & ODD(Id(0CE00H) DIV b) & ~ODD(Id(0CE00H) DIV (b * 37449))
END CallDiv;

PROCEDURE Run*;
VAR i, j, k, bit, x: LONGINT; arr: ARRAY 20 OF LONGINT; a, r: N; mm: M; c: CHAR;
BEGIN
  fails := 0; checks := 0;
  i := 47;
  Check("ASH(1, i MOD 15)", ASH(1, i MOD 15) = 4);
  Check("ASH(i, i DIV 3)", ASH(LONG(3), i DIV 3) = 98304);
  bit := 50; k := 4; arr[3] := 100;
  Check("a[bit DIV 15] DIV k", arr[bit DIV 15] DIV k = 25);
  Check("a[bit MOD 47] DIV a[bit DIV 15]", arr[bit MOD 47] DIV arr[bit DIV 15] = 1);
  j := 1; g[0].a := 10; g[1].a := 11; g[2].a := 12; g[0].b := 20; g[1].b := 21; g[2].b := 22;
  Check("global array of 12 byte records", (g[j].a = 11) & (g[j].b = 21));
  Check("RETURN x DIV y", (Div(-7, 2) = -4) & (Div(7, 2) = 3));
  Check("RETURN x MOD y", (Mod(-7, 2) = 1) & (Mod(7, 3) = 1));
  Check("RETURN ODD(x DIV ASH(1, s))", OddBit(5, 2) & ~OddBit(5, 1));
  x := 5; flag := x = 5;
  Check("b := x = 5 keeps x", flag & (x = 5));
  x := 5; flag := x # 5;
  Check("b := x # 5 keeps x", ~flag & (x = 5));
  x := -1; flag := x >= 0;
  Check("b := x >= 0, x = -1", ~flag);
  x := 3; flag := x >= 3;
  Check("b := x >= 3, x = 3", flag);
  c := "A"; flag := c >= "a";
  Check("b := c >= 'a', c = 'A'", ~flag);
  flag := c >= "A";
  Check("b := c >= 'A', c = 'A'", flag);
  j := 0; i := 0;
  WHILE i < 16 DO IF InSet(SHORT(i)) # (SHORT(i) IN {8, 9, 10, 12, 13}) THEN INC(j) END; INC(i) END;
  Check("F(t) # (t IN s)", j = 0);
  x := 3; Check("ASH(F(5), n)", ASH(Id(5), x) = 40);
  x := -1; Check("ASH(F(8), -n)", ASH(Id(8), x) = 4);
  Check("forward procedure with a nested one", CallTwice(21) = 42);
  mm.one.len := 7; r.len := 0; CopyOne(a, 0, 1, mm, r);
  Check("record copy from a VAR parameter at offset 2252", r.len = 7);
  Frame;
  BlockMove;
  Check("SYSTEM.MOVE keeps its length variable", Moved("OberonProperty", flag) = 14);
  Check("SYSTEM.MOVE of 0 bytes copies nothing", flag);
  Check("SYSTEM.MOVE up to the end of a mapping", EndOfMap());
  Check("constant relations as values", ConstRel());
  Check("RETURN ~F() & (G() < 0), the result of G in the result register", ~NotAnd() & ~OrRel());
  Check("16 RETURN of a REAL function result", (RF1(3.0) = 9.0) & (RF16(2.0) = 4.0) & (RF8(RF9(1.5)) = 5.0625));
  Check("calls inside the index of a later parameter", CallInIndex());
  Check("constant FALSE and TRUE as operands of & and OR, under ~", ConstCond(TRUE, FALSE));
  Check("every parameter a call", AllCalls());
  Check("a call of the procedure itself inside a WITH on its parameter", WithSelf());
  row[2] := 77; Check("RETURN a[i] of an open array after RETURN F(x)", (RetCall(5) = 5) & (OpenElem(row, 2) = 77));
  i := 0; WHILE i < 3 DO j := 0; WHILE j < 4 DO grid[i, j] := SHORT(10 * i + j); INC(j) END; INC(i) END;
  Check("rows of a two-dimensional open array", OpenRows(grid, 2));
  Check("LEN(a, n) of an open array", Lens(grid));
  Check("an open array on the heap as an open array argument", HeapArg());
  x := -7; k := 3; Check("DIV and MOD of a negative dividend: floor", (x DIV k = -3) & (x MOD k = 2) & (x DIV 2 = -4)
    & (x MOD 2 = 1) & ((-7) DIV 3 = -3) & ((-7) MOD 3 = 2) & (MIN(LONGINT) DIV 3 = -715827883) & (MIN(LONGINT) MOD 3 = 1));
  Check("CAP changes only lower-case letters", CapOnly());
  Check("SHORT of a LONGREAL in an expression", ShortReal());
  Check("real literals", Literals());
  Check("ENTIER of constants", ConstEntier());
  Check("ENTIER of negative variables", VarEntier());
  forLimit := 5; Check("FOR on a variable of the enclosing procedure", OuterFor() = 6);
  Check("string assignments around a flush of the constants", PoolStrings());
  Check("conditional branches around a flush of the constants", PoolBranches());
  Check("forward declaration of a local procedure", (LocalForward(0) = 7) & (LocalForward(3) = 1019));
  Check("registers saved across a call whose arguments call with more arguments", SavedAcross());
  Check("DIV and MOD of a function result by a variable", CallDiv(100, 7));
  out.String("CompilerTest: "); out.Int(checks, 0); out.String(" checks, "); out.Int(fails, 0); out.String(" failed"); out.Ln
END Run;

END CompilerTest.
