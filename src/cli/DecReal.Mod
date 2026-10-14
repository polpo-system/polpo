MODULE DecReal;  (** decimal numbers to REAL and LONGREAL, correctly rounded *)

(* The scanners of the compilers made a real literal from its digits with floating point arithmetic
   and were a few units in the last place off (1.0D23), refused literals near the ends of the range
   (3.4E38, 1.7D308) and the denormal numbers. Here the value digits * 10^e is computed exactly with
   big integers and rounded once, to the nearest value, ties to even, as IEEE 754 wants.
   Only 32 bit integers, for all of polpo's compilers. *)

IMPORT SYSTEM;

CONST
  ok* = 0; overflow* = 1; underflow* = 2;  (** results: underflow is a value # 0 that rounds to 0 *)
  Base = 8000H;  (* limbs of 15 bits: a limb times a limb fits in 31 bits *)
  Limbs = 128;  (* 1920 bits: 10^424 and the bits of a quotient *)
  MaxMag = 400;  (* beyond 10^400 (or below 10^-400) the value is out of range anyway *)

TYPE
  Big = RECORD n: LONGINT; d: ARRAY Limbs OF LONGINT END;  (* d[0] the lowest limb, n limbs used *)

PROCEDURE Set(VAR a: Big; v: LONGINT);  (* 0 <= v < Base*Base *)
BEGIN a.n := 0;
  WHILE v > 0 DO a.d[a.n] := v MOD Base; v := v DIV Base; INC(a.n) END
END Set;

PROCEDURE MulAdd(VAR a: Big; m, c: LONGINT);  (* a := a*m + c, 0 <= m, c < Base *)
VAR i, t: LONGINT;
BEGIN i := 0;
  WHILE i < a.n DO t := a.d[i] * m + c; a.d[i] := t MOD Base; c := t DIV Base; INC(i) END;
  WHILE c > 0 DO a.d[a.n] := c MOD Base; c := c DIV Base; INC(a.n) END;
  WHILE (a.n > 0) & (a.d[a.n-1] = 0) DO DEC(a.n) END
END MulAdd;

PROCEDURE BitLen(VAR a: Big): LONGINT;
VAR top, b: LONGINT;
BEGIN
  IF a.n = 0 THEN RETURN 0 END;
  top := a.d[a.n-1]; b := 0; WHILE top > 0 DO top := top DIV 2; INC(b) END;
  RETURN (a.n-1) * 15 + b
END BitLen;

PROCEDURE Bit(VAR a: Big; i: LONGINT): BOOLEAN;
BEGIN
  IF (i < 0) OR (i DIV 15 >= a.n) THEN RETURN FALSE END;
  RETURN ODD(a.d[i DIV 15] DIV ASH(1, i MOD 15))
END Bit;

PROCEDURE Shl(VAR a: Big; k: LONGINT);  (* a := a * 2^k *)
VAR i, w, b: LONGINT;
BEGIN
  IF a.n = 0 THEN RETURN END;
  w := k DIV 15; b := k MOD 15;
  IF w > 0 THEN
    i := a.n - 1; WHILE i >= 0 DO a.d[i+w] := a.d[i]; DEC(i) END;
    i := 0; WHILE i < w DO a.d[i] := 0; INC(i) END;
    INC(a.n, w)
  END;
  IF b > 0 THEN MulAdd(a, ASH(1, b), 0) END
END Shl;

PROCEDURE Shr(VAR a, r: Big; k: LONGINT);  (* r := a DIV 2^k *)
VAR i: LONGINT;
BEGIN r.n := 0; i := BitLen(a) - 1;
  WHILE i >= k DO MulAdd(r, 2, 0); IF Bit(a, i) THEN MulAdd(r, 1, 1) END; DEC(i) END
END Shr;

PROCEDURE Cmp(VAR a, b: Big): LONGINT;
VAR i: LONGINT;
BEGIN
  IF a.n # b.n THEN RETURN a.n - b.n END;
  i := a.n - 1; WHILE (i >= 0) & (a.d[i] = b.d[i]) DO DEC(i) END;
  IF i < 0 THEN RETURN 0 ELSE RETURN a.d[i] - b.d[i] END
END Cmp;

PROCEDURE Sub(VAR a, b: Big);  (* a := a - b, a >= b *)
VAR i, c, t: LONGINT;
BEGIN i := 0; c := 0;
  WHILE i < a.n DO
    t := a.d[i] - c; IF i < b.n THEN DEC(t, b.d[i]) END;
    IF t < 0 THEN INC(t, Base); c := 1 ELSE c := 0 END;
    a.d[i] := t; INC(i)
  END;
  WHILE (a.n > 0) & (a.d[a.n-1] = 0) DO DEC(a.n) END
END Sub;

PROCEDURE Div(VAR a, b, q: Big; VAR rest: BOOLEAN);  (* q := a DIV b, rest: a MOD b # 0 *)
VAR r: Big; i: LONGINT;
BEGIN q.n := 0; r.n := 0; i := BitLen(a) - 1;
  WHILE i >= 0 DO
    MulAdd(r, 2, 0); IF Bit(a, i) THEN MulAdd(r, 1, 1) END;
    MulAdd(q, 2, 0); IF Cmp(r, b) >= 0 THEN Sub(r, b); MulAdd(q, 1, 1) END;
    DEC(i)
  END;
  rest := r.n # 0
END Div;

(* digits * 10^e, rounded to p significant bits with exponents emin..emax (IEEE: p = 53, emin = -1022);
   the result in m (p bits for a normal number, fewer for a denormal one) and the binary exponent ex *)
PROCEDURE Round(VAR dig: ARRAY OF CHAR; n: LONGINT; sticky: BOOLEAN; e, p, emin, emax: LONGINT;
  VAR m: Big; VAR ex: LONGINT): INTEGER;
VAR q, t: Big; i, s, bl, shift: LONGINT; rest, up: BOOLEAN;
BEGIN
  q.n := 0; i := 0;
  WHILE i < n DO MulAdd(q, 10, ORD(dig[i]) - ORD("0")); INC(i) END;
  m.n := 0; ex := 0;
  IF q.n = 0 THEN RETURN ok END;
  bl := n; WHILE (bl > 0) & (dig[n - bl] = "0") DO DEC(bl) END;  (* the significant digits *)
  IF bl + e > MaxMag THEN RETURN overflow ELSIF bl + e < -MaxMag THEN RETURN underflow END;
  s := 0;
  IF e >= 0 THEN
    WHILE e > 0 DO MulAdd(q, 10, 0); DEC(e) END
  ELSE  (* q * 2^s DIV 10^-e, with at least p + 3 bits *)
    Set(t, 1); WHILE e < 0 DO MulAdd(t, 10, 0); INC(e) END;
    s := BitLen(t) - BitLen(q) + p + 3; IF s < 0 THEN s := 0 END;
    Shl(q, s); m := q; Div(m, t, q, rest); sticky := sticky OR rest
  END;
  (* the value is (q + a fraction, # 0 if sticky) * 2^-s *)
  bl := BitLen(q); ex := bl - 1 - s;
  IF ex > emax THEN RETURN overflow END;
  IF ex >= emin THEN shift := bl - p ELSE shift := emin - p + 1 + s END;
  IF shift <= 0 THEN m := q; Shl(m, -shift)
  ELSE
    Shr(q, m, shift);
    rest := sticky; i := 0; WHILE ~rest & (i < shift - 1) DO rest := Bit(q, i); INC(i) END;
    up := Bit(q, shift - 1) & (rest OR Bit(m, 0));
    IF up THEN MulAdd(m, 1, 1);
      IF BitLen(m) > p THEN Shr(m, t, 1); m := t; INC(ex) END
    END
  END;
  IF ex > emax THEN RETURN overflow END;
  IF m.n = 0 THEN RETURN underflow END;
  IF (BitLen(m) = p) & (ex < emin) THEN ex := emin END;  (* the largest denormal number rounded up to 2^emin *)
  RETURN ok
END Round;

PROCEDURE Bits(VAR m: Big; from, to: LONGINT): LONGINT;  (* bits from..to-1 of m as an integer, to - from <= 32 *)
VAR s: SET; i: LONGINT;
BEGIN s := {}; i := from;
  WHILE i < to DO IF Bit(m, i) THEN INCL(s, i - from) END; INC(i) END;
  RETURN SYSTEM.VAL(LONGINT, s)
END Bits;

(** x := the integer of the decimal digits dig[0..n-1] times 10^e, correctly rounded. sticky: digits
   after these were left out, not all 0. underflow and overflow give 0 *)
PROCEDURE Long*(VAR dig: ARRAY OF CHAR; n: LONGINT; sticky: BOOLEAN; e: LONGINT; VAR x: LONGREAL): INTEGER;
VAR m: Big; ex, lo, hi, res: LONGINT;
BEGIN
  res := Round(dig, n, sticky, e, 53, -1022, 1023, m, ex);
  lo := 0; hi := 0;
  IF (res = ok) & (m.n # 0) THEN
    lo := Bits(m, 0, 32); hi := Bits(m, 32, 52);
    IF BitLen(m) = 53 THEN INC(hi, ASH(ex + 1023, 20)) END  (* else a denormal number: exponent field 0 *)
  END;
  SYSTEM.PUT(SYSTEM.ADR(x), lo); SYSTEM.PUT(SYSTEM.ADR(x) + 4, hi);
  RETURN SHORT(res)
END Long;

(** the same for a REAL, rounded once from the decimal value *)
PROCEDURE Short*(VAR dig: ARRAY OF CHAR; n: LONGINT; sticky: BOOLEAN; e: LONGINT; VAR x: REAL): INTEGER;
VAR m: Big; ex, b, res: LONGINT;
BEGIN
  res := Round(dig, n, sticky, e, 24, -126, 127, m, ex);
  b := 0;
  IF (res = ok) & (m.n # 0) THEN
    b := Bits(m, 0, 23);
    IF BitLen(m) = 24 THEN INC(b, ASH(ex + 127, 23)) END
  END;
  SYSTEM.PUT(SYSTEM.ADR(x), b);
  RETURN SHORT(res)
END Short;

END DecReal.
