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
   the condition NV, not an instruction on ARMv6 and later: SIGILL (2026-10-06). *)

IMPORT SYSTEM, Linux0, out;

TYPE
  Small = RECORD a: LONGINT; pad: ARRAY 4 OF CHAR; b: LONGINT END;  (* 12 bytes *)
  N = RECORD len: LONGINT; d: ARRAY 280 OF LONGINT END;
  M = RECORD m: N; minv: LONGINT; r2: N; one: N END;  (* one at offset 2252 *)
  Big = RECORD len: LONGINT; data: ARRAY 32768 OF CHAR END;
  Info = RECORD a, b, c, d, e, f, g, h: Big; bits: LONGINT END;  (* as TLSX509.CertInfo *)
  Work = POINTER TO RECORD cur, issuer: Info END;

VAR
  fails, checks: LONGINT;
  g: ARRAY 3 OF Small;
  flag: BOOLEAN;

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
  out.String("CompilerTest: "); out.Int(checks, 0); out.String(" checks, "); out.Int(fails, 0); out.String(" failed"); out.Ln
END Run;

END CompilerTest.
