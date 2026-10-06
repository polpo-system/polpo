MODULE Checksums;  (** MD5 (RFC 1321) and SHA-256 (FIPS 180-4) of files, as lowercase hex *)

(* For checking what portia downloads. 32 bit integers only (no HUGEINT on most polpo
   compilers), wrapping sums done in halves (as TLSBytes.Add32), so the module is the same for
   every port; files up to 2 GB. *)

IMPORT SYSTEM, Files;

CONST
  MD5* = 0; SHA256* = 1;  (** kinds *)

TYPE
  State = RECORD
    kind: LONGINT;
    h: ARRAY 8 OF LONGINT;
    buf: ARRAY 64 OF CHAR; n: LONGINT;  (* bytes waiting for a block *)
    bytes: LONGINT                      (* bytes hashed so far *)
  END;

VAR
  T, K: ARRAY 64 OF LONGINT;  (* the constants of MD5 and SHA-256 *)
  S: ARRAY 64 OF LONGINT;     (* the rotations of MD5 *)
  IV: ARRAY 8 OF LONGINT;     (* SHA-256 *)
  MIV: ARRAY 4 OF LONGINT;    (* MD5 *)

PROCEDURE Add(a, b: LONGINT): LONGINT;  (* a + b modulo 2^32 *)
VAR lo, hi: LONGINT;
BEGIN
  lo := a MOD 10000H + b MOD 10000H;
  hi := (a DIV 10000H + b DIV 10000H + lo DIV 10000H) MOD 10000H;
  IF hi >= 8000H THEN hi := hi - 10000H END;
  RETURN hi * 10000H + lo MOD 10000H
END Add;

PROCEDURE Xor(a, b: LONGINT): LONGINT;
BEGIN RETURN SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, a) / SYSTEM.VAL(SET, b))
END Xor;

PROCEDURE And(a, b: LONGINT): LONGINT;
BEGIN RETURN SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, a) * SYSTEM.VAL(SET, b))
END And;

PROCEDURE Or(a, b: LONGINT): LONGINT;
BEGIN RETURN SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, a) + SYSTEM.VAL(SET, b))
END Or;

PROCEDURE Not(a: LONGINT): LONGINT;
BEGIN RETURN SYSTEM.VAL(LONGINT, -SYSTEM.VAL(SET, a))
END Not;

PROCEDURE Rotl(x, n: LONGINT): LONGINT;
BEGIN RETURN SYSTEM.ROT(x, n)
END Rotl;

PROCEDURE Shr(x, n: LONGINT): LONGINT;
BEGIN RETURN SYSTEM.LSH(x, -n)
END Shr;

(* the 32 bit word of the bytes b[i..i+3], little endian (MD5) or big endian (SHA-256) *)
PROCEDURE Word(VAR b: ARRAY OF CHAR; i: LONGINT; big: BOOLEAN): LONGINT;
VAR b0, b1, b2, b3: LONGINT;
BEGIN
  IF big THEN b0 := ORD(b[i]); b1 := ORD(b[i+1]); b2 := ORD(b[i+2]); b3 := ORD(b[i+3])
  ELSE b0 := ORD(b[i+3]); b1 := ORD(b[i+2]); b2 := ORD(b[i+1]); b3 := ORD(b[i])
  END;
  IF b0 >= 128 THEN b0 := b0 - 256 END;
  RETURN ((b0 * 256 + b1) * 256 + b2) * 256 + b3
END Word;

PROCEDURE BlockMD5(VAR s: State; VAR b: ARRAY OF CHAR);
VAR X: ARRAY 16 OF LONGINT; a, bb, c, d, f, g, i, t: LONGINT;
BEGIN
  i := 0; WHILE i < 16 DO X[i] := Word(b, 4 * i, FALSE); INC(i) END;
  a := s.h[0]; bb := s.h[1]; c := s.h[2]; d := s.h[3];
  i := 0;
  WHILE i < 64 DO
    IF i < 16 THEN f := Or(And(bb, c), And(Not(bb), d)); g := i
    ELSIF i < 32 THEN f := Or(And(d, bb), And(Not(d), c)); g := (5 * i + 1) MOD 16
    ELSIF i < 48 THEN f := Xor(Xor(bb, c), d); g := (3 * i + 5) MOD 16
    ELSE f := Xor(c, Or(bb, Not(d))); g := (7 * i) MOD 16
    END;
    t := d; d := c; c := bb;
    bb := Add(bb, Rotl(Add(Add(a, f), Add(T[i], X[g])), S[i]));
    a := t; INC(i)
  END;
  s.h[0] := Add(s.h[0], a); s.h[1] := Add(s.h[1], bb); s.h[2] := Add(s.h[2], c); s.h[3] := Add(s.h[3], d)
END BlockMD5;

PROCEDURE BlockSHA(VAR s: State; VAR blk: ARRAY OF CHAR);
VAR W: ARRAY 64 OF LONGINT; a, b, c, d, e, f, g, h, t1, t2, s0, s1, i: LONGINT;
BEGIN
  i := 0; WHILE i < 16 DO W[i] := Word(blk, 4 * i, TRUE); INC(i) END;
  WHILE i < 64 DO
    s0 := Xor(Xor(Rotl(W[i-15], 25), Rotl(W[i-15], 14)), Shr(W[i-15], 3));
    s1 := Xor(Xor(Rotl(W[i-2], 15), Rotl(W[i-2], 13)), Shr(W[i-2], 10));
    W[i] := Add(Add(W[i-16], s0), Add(W[i-7], s1)); INC(i)
  END;
  a := s.h[0]; b := s.h[1]; c := s.h[2]; d := s.h[3]; e := s.h[4]; f := s.h[5]; g := s.h[6]; h := s.h[7];
  i := 0;
  WHILE i < 64 DO
    s1 := Xor(Xor(Rotl(e, 26), Rotl(e, 21)), Rotl(e, 7));
    t1 := Add(Add(h, s1), Add(Add(Xor(And(e, f), And(Not(e), g)), K[i]), W[i]));
    s0 := Xor(Xor(Rotl(a, 30), Rotl(a, 19)), Rotl(a, 10));
    t2 := Add(s0, Xor(Xor(And(a, b), And(a, c)), And(b, c)));
    h := g; g := f; f := e; e := Add(d, t1); d := c; c := b; b := a; a := Add(t1, t2);
    INC(i)
  END;
  s.h[0] := Add(s.h[0], a); s.h[1] := Add(s.h[1], b); s.h[2] := Add(s.h[2], c); s.h[3] := Add(s.h[3], d);
  s.h[4] := Add(s.h[4], e); s.h[5] := Add(s.h[5], f); s.h[6] := Add(s.h[6], g); s.h[7] := Add(s.h[7], h)
END BlockSHA;

PROCEDURE Block(VAR s: State);
BEGIN
  IF s.kind = MD5 THEN BlockMD5(s, s.buf) ELSE BlockSHA(s, s.buf) END;
  s.n := 0
END Block;

PROCEDURE Begin(VAR s: State; kind: LONGINT);
VAR i: LONGINT;
BEGIN
  s.kind := kind; s.n := 0; s.bytes := 0;
  IF kind = MD5 THEN i := 0; WHILE i < 4 DO s.h[i] := MIV[i]; INC(i) END
  ELSE i := 0; WHILE i < 8 DO s.h[i] := IV[i]; INC(i) END
  END
END Begin;

PROCEDURE Write(VAR s: State; VAR data: ARRAY OF CHAR; n: LONGINT);
VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE i < n DO
    s.buf[s.n] := data[i]; INC(s.n); INC(i);
    IF s.n = 64 THEN Block(s) END
  END;
  s.bytes := s.bytes + n
END Write;

PROCEDURE HexDigit(v: LONGINT): CHAR;
BEGIN IF v < 10 THEN RETURN CHR(ORD("0") + v) ELSE RETURN CHR(ORD("a") + v - 10) END
END HexDigit;

(* the padding and the length; hex := the digest *)
PROCEDURE End(VAR s: State; VAR hex: ARRAY OF CHAR);
VAR lo, hi, i, j, w, b, k, words: LONGINT; len: ARRAY 8 OF CHAR;
BEGIN
  hi := s.bytes DIV 20000000H;           (* the length in bits: hi, lo *)
  lo := (s.bytes MOD 10000000H) * 8;
  IF ODD(s.bytes DIV 10000000H) THEN lo := Add(lo, MIN(LONGINT)) END;
  s.buf[s.n] := 80X; INC(s.n);
  IF s.n > 56 THEN WHILE s.n < 64 DO s.buf[s.n] := 0X; INC(s.n) END; Block(s) END;
  WHILE s.n < 56 DO s.buf[s.n] := 0X; INC(s.n) END;
  i := 0;
  WHILE i < 4 DO  (* the length as bytes, low first *)
    len[i] := CHR(Shr(lo, 8 * i) MOD 256); len[4 + i] := CHR(Shr(hi, 8 * i) MOD 256); INC(i)
  END;
  IF s.kind = MD5 THEN i := 0; WHILE i < 8 DO s.buf[56 + i] := len[i]; INC(i) END
  ELSE i := 0; WHILE i < 8 DO s.buf[56 + i] := len[7 - i]; INC(i) END
  END;
  s.n := 64; Block(s);
  IF s.kind = MD5 THEN words := 4 ELSE words := 8 END;
  k := 0; i := 0;
  WHILE i < words DO
    w := s.h[i]; j := 0;
    WHILE j < 4 DO
      IF s.kind = MD5 THEN b := Shr(w, 8 * j) MOD 256 ELSE b := Shr(w, 24 - 8 * j) MOD 256 END;
      hex[k] := HexDigit(b DIV 16); hex[k+1] := HexDigit(b MOD 16); INC(k, 2); INC(j)
    END;
    INC(i)
  END;
  hex[k] := 0X
END End;

(** hex := the checksum of kind (MD5, SHA256) of the first n bytes of data *)
PROCEDURE Data*(kind: LONGINT; VAR data: ARRAY OF CHAR; n: LONGINT; VAR hex: ARRAY OF CHAR);
VAR s: State;
BEGIN
  Begin(s, kind); Write(s, data, n); End(s, hex)
END Data;

(** hex := the checksum of kind of the file name; FALSE if there is no such file *)
PROCEDURE File*(kind: LONGINT; name: ARRAY OF CHAR; VAR hex: ARRAY OF CHAR): BOOLEAN;
VAR s: State; f: Files.File; R: Files.Rider; buf: ARRAY 4096 OF CHAR; left, n: LONGINT;
BEGIN
  hex[0] := 0X;
  f := Files.Old(name); IF f = NIL THEN RETURN FALSE END;
  Begin(s, kind); Files.Set(R, f, 0); left := Files.Length(f);
  WHILE left > 0 DO
    n := left; IF n > LEN(buf) THEN n := LEN(buf) END;
    Files.ReadBytes(R, buf, n); n := n - R.res;
    IF n <= 0 THEN left := 0 ELSE Write(s, buf, n); left := left - n END
  END;
  Files.ReleaseRead(f);
  End(s, hex); RETURN TRUE
END File;

(** a checksum "md5:hex" or "sha256:hex" holds for the file name; FALSE also for another kind *)
PROCEDURE Matches*(VAR sum, name: ARRAY OF CHAR): BOOLEAN;
VAR kind, i, k: LONGINT; hex: ARRAY 72 OF CHAR; c: CHAR;
BEGIN
  IF (sum[0] = "m") & (sum[1] = "d") & (sum[2] = "5") & (sum[3] = ":") THEN kind := MD5; k := 4
  ELSIF (sum[0] = "s") & (sum[1] = "h") & (sum[2] = "a") & (sum[3] = "2") & (sum[4] = "5") & (sum[5] = "6") & (sum[6] = ":") THEN
    kind := SHA256; k := 7
  ELSE RETURN FALSE
  END;
  IF ~File(kind, name, hex) THEN RETURN FALSE END;
  i := 0;
  WHILE hex[i] # 0X DO
    c := sum[k + i]; IF (c >= "A") & (c <= "F") THEN c := CHR(ORD(c) + 32) END;
    IF c # hex[i] THEN RETURN FALSE END;
    INC(i)
  END;
  RETURN sum[k + i] = 0X
END Matches;

PROCEDURE Init;
BEGIN
  T[0] := -680876936; T[1] := -389564586; T[2] := 606105819; T[3] := -1044525330;
  T[4] := -176418897; T[5] := 1200080426; T[6] := -1473231341; T[7] := -45705983;
  T[8] := 1770035416; T[9] := -1958414417; T[10] := -42063; T[11] := -1990404162;
  T[12] := 1804603682; T[13] := -40341101; T[14] := -1502002290; T[15] := 1236535329;
  T[16] := -165796510; T[17] := -1069501632; T[18] := 643717713; T[19] := -373897302;
  T[20] := -701558691; T[21] := 38016083; T[22] := -660478335; T[23] := -405537848;
  T[24] := 568446438; T[25] := -1019803690; T[26] := -187363961; T[27] := 1163531501;
  T[28] := -1444681467; T[29] := -51403784; T[30] := 1735328473; T[31] := -1926607734;
  T[32] := -378558; T[33] := -2022574463; T[34] := 1839030562; T[35] := -35309556;
  T[36] := -1530992060; T[37] := 1272893353; T[38] := -155497632; T[39] := -1094730640;
  T[40] := 681279174; T[41] := -358537222; T[42] := -722521979; T[43] := 76029189;
  T[44] := -640364487; T[45] := -421815835; T[46] := 530742520; T[47] := -995338651;
  T[48] := -198630844; T[49] := 1126891415; T[50] := -1416354905; T[51] := -57434055;
  T[52] := 1700485571; T[53] := -1894986606; T[54] := -1051523; T[55] := -2054922799;
  T[56] := 1873313359; T[57] := -30611744; T[58] := -1560198380; T[59] := 1309151649;
  T[60] := -145523070; T[61] := -1120210379; T[62] := 718787259; T[63] := -343485551;
  K[0] := 1116352408; K[1] := 1899447441; K[2] := -1245643825; K[3] := -373957723;
  K[4] := 961987163; K[5] := 1508970993; K[6] := -1841331548; K[7] := -1424204075;
  K[8] := -670586216; K[9] := 310598401; K[10] := 607225278; K[11] := 1426881987;
  K[12] := 1925078388; K[13] := -2132889090; K[14] := -1680079193; K[15] := -1046744716;
  K[16] := -459576895; K[17] := -272742522; K[18] := 264347078; K[19] := 604807628;
  K[20] := 770255983; K[21] := 1249150122; K[22] := 1555081692; K[23] := 1996064986;
  K[24] := -1740746414; K[25] := -1473132947; K[26] := -1341970488; K[27] := -1084653625;
  K[28] := -958395405; K[29] := -710438585; K[30] := 113926993; K[31] := 338241895;
  K[32] := 666307205; K[33] := 773529912; K[34] := 1294757372; K[35] := 1396182291;
  K[36] := 1695183700; K[37] := 1986661051; K[38] := -2117940946; K[39] := -1838011259;
  K[40] := -1564481375; K[41] := -1474664885; K[42] := -1035236496; K[43] := -949202525;
  K[44] := -778901479; K[45] := -694614492; K[46] := -200395387; K[47] := 275423344;
  K[48] := 430227734; K[49] := 506948616; K[50] := 659060556; K[51] := 883997877;
  K[52] := 958139571; K[53] := 1322822218; K[54] := 1537002063; K[55] := 1747873779;
  K[56] := 1955562222; K[57] := 2024104815; K[58] := -2067236844; K[59] := -1933114872;
  K[60] := -1866530822; K[61] := -1538233109; K[62] := -1090935817; K[63] := -965641998;
  S[0] := 7; S[1] := 12; S[2] := 17; S[3] := 22; S[4] := 7; S[5] := 12; S[6] := 17; S[7] := 22; S[8] := 7; S[9] := 12; S[10] := 17; S[11] := 22; S[12] := 7; S[13] := 12; S[14] := 17; S[15] := 22;
  S[16] := 5; S[17] := 9; S[18] := 14; S[19] := 20; S[20] := 5; S[21] := 9; S[22] := 14; S[23] := 20; S[24] := 5; S[25] := 9; S[26] := 14; S[27] := 20; S[28] := 5; S[29] := 9; S[30] := 14; S[31] := 20;
  S[32] := 4; S[33] := 11; S[34] := 16; S[35] := 23; S[36] := 4; S[37] := 11; S[38] := 16; S[39] := 23; S[40] := 4; S[41] := 11; S[42] := 16; S[43] := 23; S[44] := 4; S[45] := 11; S[46] := 16; S[47] := 23;
  S[48] := 6; S[49] := 10; S[50] := 15; S[51] := 21; S[52] := 6; S[53] := 10; S[54] := 15; S[55] := 21; S[56] := 6; S[57] := 10; S[58] := 15; S[59] := 21; S[60] := 6; S[61] := 10; S[62] := 15; S[63] := 21;
  IV[0] := 1779033703; IV[1] := -1150833019; IV[2] := 1013904242; IV[3] := -1521486534;
  IV[4] := 1359893119; IV[5] := -1694144372; IV[6] := 528734635; IV[7] := 1541459225;
  MIV[0] := 1732584193; MIV[1] := -271733879; MIV[2] := -1732584194; MIV[3] := 271733878;
END Init;

BEGIN
  Init
END Checksums.
