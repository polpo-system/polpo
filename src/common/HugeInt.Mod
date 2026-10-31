MODULE HugeInt;  (** HUGEINT on the 32-bit ports: the compilers compile its operations into calls of this module *)

(* A HUGEINT is a 64-bit integer in two's complement, two words in the byte order of the machine; the code
  generators see it as an ARRAY 2 OF LONGINT (Huge). The functions taking a VAR r write their result into r
  and return the address of r, which the compiler uses as the value of the expression; r is a temporary
  variable of the calling procedure. Results wrap around modulo 2^64. Div and Mod take a divisor > 0 and floor
  the quotient, as DIV and MOD of LONGINT; another divisor stops the program with trap 10.

  Pack, Unpack and the functions ending in Ovf serve the compilers to compute constant expressions: they tell
  when the result does not fit. Str writes a number in decimal. *)

IMPORT SYSTEM;

TYPE
  Huge* = ARRAY 2 OF LONGINT;
  Limbs = ARRAY 8 OF LONGINT;  (* 16 bits each, the lowest first *)

VAR
  L, H: LONGINT;  (* index of the low and of the high word *)
  zero: LONGINT;  (* the divisor that makes a division by a divisor <= 0 trap *)
  two32: LONGREAL;

PROCEDURE Pack*(VAR r: Huge; lo, hi: LONGINT);
BEGIN r[L] := lo; r[H] := hi
END Pack;

PROCEDURE Unpack*(VAR a: Huge; VAR lo, hi: LONGINT);
BEGIN lo := a[L]; hi := a[H]
END Unpack;

(* x < y as numbers without sign *)
PROCEDURE ULess(x, y: LONGINT): BOOLEAN;
BEGIN
  IF (x < 0) = (y < 0) THEN RETURN x < y ELSE RETURN y < 0 END
END ULess;

PROCEDURE Not(x: LONGINT): LONGINT;
BEGIN RETURN SYSTEM.VAL(LONGINT, -SYSTEM.VAL(SET, x))
END Not;

PROCEDURE Low16(x: LONGINT): LONGINT;
BEGIN RETURN SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, x) * {0..15})
END Low16;

PROCEDURE Sum(VAR r: Huge; alo, ahi, blo, bhi: LONGINT);
VAR lo: LONGINT;
BEGIN
  lo := alo + blo; IF ULess(lo, alo) THEN INC(ahi) END;
  r[L] := lo; r[H] := ahi + bhi
END Sum;

PROCEDURE Make*(VAR r: Huge; lo, hi: LONGINT): LONGINT;
BEGIN r[L] := lo; r[H] := hi; RETURN SYSTEM.ADR(r)
END Make;

PROCEDURE Long*(VAR r: Huge; x: LONGINT): LONGINT;
BEGIN
  r[L] := x; IF x < 0 THEN r[H] := -1 ELSE r[H] := 0 END;
  RETURN SYSTEM.ADR(r)
END Long;

(** the low word: SHORT *)
PROCEDURE Short*(VAR a: Huge): LONGINT;
BEGIN RETURN a[L]
END Short;

(** r := lo, hi: the assignment of a constant *)
PROCEDURE Set*(VAR r: Huge; lo, hi: LONGINT);
BEGIN r[L] := lo; r[H] := hi
END Set;

(** r := x *)
PROCEDURE SetL*(VAR r: Huge; x: LONGINT);
BEGIN
  r[L] := x; IF x < 0 THEN r[H] := -1 ELSE r[H] := 0 END
END SetL;

PROCEDURE Add*(VAR r, a, b: Huge): LONGINT;
BEGIN Sum(r, a[L], a[H], b[L], b[H]); RETURN SYSTEM.ADR(r)
END Add;

PROCEDURE Sub*(VAR r, a, b: Huge): LONGINT;
VAR lo, hi: LONGINT;
BEGIN
  lo := b[L]; hi := b[H];
  Sum(r, a[L], a[H], Not(lo), Not(hi)); Sum(r, r[L], r[H], 1, 0); RETURN SYSTEM.ADR(r)
END Sub;

PROCEDURE Neg*(VAR r, a: Huge): LONGINT;
BEGIN Sum(r, Not(a[L]), Not(a[H]), 1, 0); RETURN SYSTEM.ADR(r)
END Neg;

PROCEDURE Abs*(VAR r, a: Huge): LONGINT;
BEGIN
  IF a[H] < 0 THEN Sum(r, Not(a[L]), Not(a[H]), 1, 0) ELSE r[L] := a[L]; r[H] := a[H] END;
  RETURN SYSTEM.ADR(r)
END Abs;

(** INC(a, b) *)
PROCEDURE Inc*(VAR a, b: Huge);
BEGIN Sum(a, a[L], a[H], b[L], b[H])
END Inc;

(** DEC(a, b) *)
PROCEDURE Dec*(VAR a, b: Huge);
VAR lo, hi: LONGINT;
BEGIN
  lo := b[L]; hi := b[H];
  Sum(a, a[L], a[H], Not(lo), Not(hi)); Sum(a, a[L], a[H], 1, 0)
END Dec;

(** INC(a, x) *)
PROCEDURE IncL*(VAR a: Huge; x: LONGINT);
BEGIN
  IF x < 0 THEN Sum(a, a[L], a[H], x, -1) ELSE Sum(a, a[L], a[H], x, 0) END
END IncL;

(** DEC(a, x) *)
PROCEDURE DecL*(VAR a: Huge; x: LONGINT);
BEGIN
  IF x < 0 THEN Sum(a, a[L], a[H], Not(x), 0) ELSE Sum(a, a[L], a[H], Not(x), -1) END;
  Sum(a, a[L], a[H], 1, 0)
END DecL;

PROCEDURE ToLimbs(lo, hi: LONGINT; VAR x: Limbs);
VAR i: LONGINT;
BEGIN
  x[0] := Low16(lo); x[1] := SYSTEM.LSH(lo, -16); x[2] := Low16(hi); x[3] := SYSTEM.LSH(hi, -16);
  i := 4; WHILE i < 8 DO x[i] := 0; INC(i) END
END ToLimbs;

(* z := x * y; x and y below 2^64 *)
PROCEDURE MulU(VAR x, y, z: Limbs);
VAR i, j, p, c: LONGINT;
BEGIN
  i := 0; WHILE i < 8 DO z[i] := 0; INC(i) END;
  i := 0;
  WHILE i < 4 DO
    j := 0;
    WHILE j < 4 DO
      p := x[i] * y[j];  (* below 2^32, the bits of the product *)
      INC(z[i + j], Low16(p)); INC(z[i + j + 1], SYSTEM.LSH(p, -16));
      INC(j)
    END;
    INC(i)
  END;
  c := 0; i := 0;
  WHILE i < 8 DO INC(z[i], c); c := SYSTEM.LSH(z[i], -16); z[i] := Low16(z[i]); INC(i) END
END MulU;

PROCEDURE Mul*(VAR r, a, b: Huge): LONGINT;
VAR x, y, z: Limbs;
BEGIN
  ToLimbs(a[L], a[H], x); ToLimbs(b[L], b[H], y); MulU(x, y, z);
  r[L] := z[0] + SYSTEM.LSH(z[1], 16); r[H] := z[2] + SYSTEM.LSH(z[3], 16);
  RETURN SYSTEM.ADR(r)
END Mul;

(* q, r := n DIV d, n MOD d for numbers without sign; 0 < d < 2^63 *)
PROCEDURE DivU(nlo, nhi, dlo, dhi: LONGINT; VAR qlo, qhi, rlo, rhi: LONGINT);
VAR i, x, c: LONGINT; t: Huge;
BEGIN
  IF (nhi = 0) & (nlo >= 0) & (dhi = 0) & (dlo > 0) THEN
    qlo := nlo DIV dlo; qhi := 0; rlo := nlo MOD dlo; rhi := 0
  ELSIF (dhi = 0) & (dlo > 0) & (dlo <= 8000H) THEN  (* by 16 bits: each step below 2^31 *)
    c := SYSTEM.LSH(nhi, -16); qhi := c DIV dlo; c := c MOD dlo;
    x := c * 10000H + Low16(nhi); qhi := qhi * 10000H + x DIV dlo; c := x MOD dlo;
    x := c * 10000H + SYSTEM.LSH(nlo, -16); qlo := x DIV dlo; c := x MOD dlo;
    x := c * 10000H + Low16(nlo); qlo := qlo * 10000H + x DIV dlo;
    rlo := x MOD dlo; rhi := 0
  ELSE
    qlo := 0; qhi := 0; rlo := 0; rhi := 0; i := 0;
    WHILE i < 64 DO
      rhi := SYSTEM.LSH(rhi, 1) + SYSTEM.LSH(rlo, -31); rlo := SYSTEM.LSH(rlo, 1) + SYSTEM.LSH(nhi, -31);
      nhi := SYSTEM.LSH(nhi, 1) + SYSTEM.LSH(nlo, -31); nlo := SYSTEM.LSH(nlo, 1);
      qhi := SYSTEM.LSH(qhi, 1) + SYSTEM.LSH(qlo, -31); qlo := SYSTEM.LSH(qlo, 1);
      IF ULess(dhi, rhi) OR (rhi = dhi) & ~ULess(rlo, dlo) THEN  (* r >= d; r < 2d < 2^64 *)
        Sum(t, rlo, rhi, Not(dlo), Not(dhi)); Sum(t, t[L], t[H], 1, 0); rlo := t[L]; rhi := t[H];
        INC(qlo)
      END;
      INC(i)
    END
  END
END DivU;

(* q, r := a DIV b, a MOD b *)
PROCEDURE DivMod(VAR a, b: Huge; VAR qlo, qhi, rlo, rhi: LONGINT);
VAR blo, bhi: LONGINT; t: Huge;
BEGIN
  blo := b[L]; bhi := b[H];
  IF (bhi < 0) OR (bhi = 0) & (blo = 0) THEN qlo := 1 DIV zero END;
  IF a[H] >= 0 THEN DivU(a[L], a[H], blo, bhi, qlo, qhi, rlo, rhi)
  ELSE  (* a = -n - 1: a DIV b = -(n DIV b) - 1, a MOD b = b - 1 - n MOD b *)
    DivU(Not(a[L]), Not(a[H]), blo, bhi, qlo, qhi, rlo, rhi);
    qlo := Not(qlo); qhi := Not(qhi);
    Sum(t, blo, bhi, -1, -1); Sum(t, t[L], t[H], Not(rlo), Not(rhi)); Sum(t, t[L], t[H], 1, 0);
    rlo := t[L]; rhi := t[H]
  END
END DivMod;

PROCEDURE Div*(VAR r, a, b: Huge): LONGINT;
VAR qlo, qhi, rlo, rhi: LONGINT;
BEGIN DivMod(a, b, qlo, qhi, rlo, rhi); r[L] := qlo; r[H] := qhi; RETURN SYSTEM.ADR(r)
END Div;

PROCEDURE Mod*(VAR r, a, b: Huge): LONGINT;
VAR qlo, qhi, rlo, rhi: LONGINT;
BEGIN DivMod(a, b, qlo, qhi, rlo, rhi); r[L] := rlo; r[H] := rhi; RETURN SYSTEM.ADR(r)
END Mod;

(** r := ASH(a, n) *)
PROCEDURE Ash*(VAR r, a: Huge; n: LONGINT): LONGINT;
VAR lo, hi: LONGINT;
BEGIN
  lo := a[L]; hi := a[H];
  IF n >= 64 THEN lo := 0; hi := 0
  ELSIF n >= 32 THEN hi := SYSTEM.LSH(lo, n - 32); lo := 0
  ELSIF n > 0 THEN hi := SYSTEM.LSH(hi, n) + SYSTEM.LSH(lo, n - 32); lo := SYSTEM.LSH(lo, n)
  ELSIF n = 0 THEN
  ELSIF n > -32 THEN lo := SYSTEM.LSH(lo, n) + SYSTEM.LSH(hi, 32 + n); hi := ASH(hi, n)
  ELSIF n > -64 THEN lo := ASH(hi, n + 32); hi := ASH(hi, -31)
  ELSE lo := ASH(hi, -31); hi := lo
  END;
  r[L] := lo; r[H] := hi; RETURN SYSTEM.ADR(r)
END Ash;

(** -1, 0 or 1 when a <, = or > b *)
PROCEDURE Cmp*(VAR a, b: Huge): LONGINT;
BEGIN
  IF a[H] < b[H] THEN RETURN -1
  ELSIF a[H] > b[H] THEN RETURN 1
  ELSIF a[L] = b[L] THEN RETURN 0
  ELSIF ULess(a[L], b[L]) THEN RETURN -1
  ELSE RETURN 1
  END
END Cmp;

(** a as LONGREAL, rounded to the nearest *)
PROCEDURE Real*(VAR a: Huge): LONGREAL;
VAR x: LONGREAL;
BEGIN
  x := a[H] * two32;
  IF a[L] < 0 THEN RETURN x + (a[L] + two32) ELSE RETURN x + a[L] END
END Real;

(** r := a + b; TRUE if the sum does not fit *)
PROCEDURE AddOvf*(VAR r, a, b: Huge): BOOLEAN;
VAR sa, sb: BOOLEAN;
BEGIN
  sa := a[H] < 0; sb := b[H] < 0; Sum(r, a[L], a[H], b[L], b[H]);
  RETURN (sa = sb) & ((r[H] < 0) # sa)
END AddOvf;

(** r := a - b; TRUE if the difference does not fit *)
PROCEDURE SubOvf*(VAR r, a, b: Huge): BOOLEAN;
VAR sa, sb: BOOLEAN; adr: LONGINT;
BEGIN
  sa := a[H] < 0; sb := b[H] < 0; adr := Sub(r, a, b);
  RETURN (sa # sb) & ((r[H] < 0) # sa)
END SubOvf;

(** r := a * b; TRUE if the product does not fit *)
PROCEDURE MulOvf*(VAR r, a, b: Huge): BOOLEAN;
VAR x, y, z: Limbs; neg, ovf: BOOLEAN; lo, hi: LONGINT; t: Huge;
BEGIN
  neg := (a[H] < 0) # (b[H] < 0);
  lo := Abs(t, a); ToLimbs(t[L], t[H], x); lo := Abs(t, b); ToLimbs(t[L], t[H], y);
  MulU(x, y, z);
  lo := z[0] + SYSTEM.LSH(z[1], 16); hi := z[2] + SYSTEM.LSH(z[3], 16);
  ovf := (z[4] # 0) OR (z[5] # 0) OR (z[6] # 0) OR (z[7] # 0) OR
    (hi < 0) & ~(neg & (hi = MIN(LONGINT)) & (lo = 0));
  IF neg THEN Sum(r, Not(lo), Not(hi), 1, 0) ELSE r[L] := lo; r[H] := hi END;
  RETURN ovf
END MulOvf;

(** r := -a; TRUE if a is MIN(HUGEINT) *)
PROCEDURE NegOvf*(VAR r, a: Huge): BOOLEAN;
VAR ovf: BOOLEAN; adr: LONGINT;
BEGIN
  ovf := (a[H] = MIN(LONGINT)) & (a[L] = 0); adr := Neg(r, a); RETURN ovf
END NegOvf;

(** r := ASH(a, n); TRUE if a shift to the left loses bits *)
PROCEDURE AshOvf*(VAR r, a: Huge; n: LONGINT): BOOLEAN;
VAR t: Huge; adr, lo, hi: LONGINT;
BEGIN
  lo := a[L]; hi := a[H]; adr := Ash(r, a, n);
  IF n <= 0 THEN RETURN FALSE
  ELSIF n >= 64 THEN RETURN (lo # 0) OR (hi # 0)
  ELSE adr := Ash(t, r, -n); RETURN (t[L] # lo) OR (t[H] # hi)
  END
END AshOvf;

(** a in decimal *)
PROCEDURE Str*(VAR a: Huge; VAR s: ARRAY OF CHAR);
VAR d: ARRAY 24 OF CHAR; i, k, lo, hi, qlo, qhi, rlo, rhi: LONGINT; neg: BOOLEAN;
BEGIN
  lo := a[L]; hi := a[H]; neg := hi < 0; i := 0;
  IF neg THEN lo := Not(lo); hi := Not(hi) END;  (* -a - 1, below 2^63 *)
  REPEAT
    DivU(lo, hi, 10, 0, qlo, qhi, rlo, rhi);
    IF neg THEN  (* the lowest digit of -a, from -a - 1 *)
      INC(rlo); neg := FALSE;
      IF rlo = 10 THEN rlo := 0; INC(qlo); IF qlo = 0 THEN INC(qhi) END END
    END;
    d[i] := CHR(rlo + ORD("0")); INC(i); lo := qlo; hi := qhi
  UNTIL (lo = 0) & (hi = 0);
  k := 0;
  IF a[H] < 0 THEN IF k < LEN(s) - 1 THEN s[k] := "-"; INC(k) END END;
  WHILE i > 0 DO DEC(i); IF k < LEN(s) - 1 THEN s[k] := d[i]; INC(k) END END;
  s[k] := 0X
END Str;

PROCEDURE Init;
VAR x: LONGINT; c: CHAR;
BEGIN
  x := 1; SYSTEM.GET(SYSTEM.ADR(x), c);
  IF c = 1X THEN L := 0; H := 1 ELSE L := 1; H := 0 END;
  zero := 0; two32 := 4.0D0 * 1073741824.0D0
END Init;

BEGIN Init
END HugeInt.
