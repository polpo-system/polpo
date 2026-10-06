MODULE Crypt0;  (** the ciphers of Crypt0 of the Voyager project (Heidelberg) and of oarc, for .Arc *)

(* Plugged into Compress0 by name, like CompressCrypt (see there):
     arc.Add \C Crypt0.Install "key" archive.Arc file ...      the cipher of Voyager's Crypt0
     arc.Add \C Crypt0.InstallMod "key" archive.Arc file ...   oarc -c mod (its default)
     arc.Add \C Crypt0.InstallXor "key" archive.Arc file ...   oarc -c xor
   All three use a stream of the Park-Miller generator, seeded with the characters of the key and
   stepped with one of them for each byte; the byte is the plain byte plus (minus to decrypt) the
   stream, or XOR it. Voyager steps through the key MOD (length - 1), so its last character
   only seeds the stream, and a key of one character stopped it with a division by zero: here such
   a key works as with InstallMod. oarc (github.com/norayr/oarc, for voc) reads and writes the
   same archives: oarc -c heidelberg is Install. Toy ciphers, for compatibility, not secrecy. *)

IMPORT Files, Compress := Compress0;

CONST
  Voyager = 0; Mod = 1; Xor = 2;
  DefaultSeed = 871491;

VAR
  cipher: INTEGER;
  seed, keylen, cur: LONGINT;  (* keylen: the length of the key - 1 *)

PROCEDURE Length(VAR s: ARRAY OF CHAR): LONGINT;
VAR i: LONGINT;
BEGIN i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END; RETURN i
END Length;

(* a step of the generator of Park and Miller, after adding inc *)
PROCEDURE ParkMiller(VAR s: LONGINT; inc: CHAR): LONGINT;
CONST a = 16807; m = 2147483647; q = m DIV a; r = m MOD a;
BEGIN
  IF ORD(inc) < m - s THEN s := s + ORD(inc) ELSE s := s - m + ORD(inc) END;
  s := a * (s MOD q) - r * (s DIV q);
  IF s < 0 THEN s := s + m END;
  RETURN s DIV 0FFFFH
END ParkMiller;

PROCEDURE Seed(VAR key: ARRAY OF CHAR);
VAR n, x: LONGINT;
BEGIN
  seed := DefaultSeed; keylen := Length(key) - 1; IF keylen < 0 THEN keylen := 0 END;
  cur := 0; n := keylen;
  WHILE n >= 0 DO x := ParkMiller(seed, key[n]); DEC(n) END
END Seed;

PROCEDURE Next(VAR key: ARRAY OF CHAR): LONGINT;  (* the next byte of the stream *)
BEGIN
  IF keylen = 0 THEN cur := 0
  ELSIF cipher = Voyager THEN cur := (cur + 1) MOD keylen
  ELSE cur := (cur + 1) MOD (keylen + 1)
  END;
  RETURN ParkMiller(seed, key[cur]) MOD 256
END Next;

PROCEDURE XorByte(a, b: LONGINT): LONGINT;
VAR x, bit: LONGINT;
BEGIN
  x := 0; bit := 1;
  WHILE bit < 256 DO IF ODD(a) # ODD(b) THEN INC(x, bit) END; a := a DIV 2; b := b DIV 2; bit := bit * 2 END;
  RETURN x
END XorByte;

PROCEDURE Code(VAR Rin: Files.Rider; nIn: LONGINT; VAR Rout: Files.Rider; VAR key: ARRAY OF CHAR; sign: LONGINT; VAR res: INTEGER);
VAR i, k: LONGINT; ch: CHAR;
BEGIN
  Seed(key); i := 0;
  WHILE ~Rin.eof & (i < nIn) DO
    Files.Read(Rin, ch); k := Next(key);
    IF cipher = Xor THEN Files.Write(Rout, CHR(XorByte(ORD(ch), k)))
    ELSE Files.Write(Rout, CHR((ORD(ch) + sign * k + 256) MOD 256))
    END;
    INC(i)
  END;
  IF i = nIn THEN res := Compress.Done ELSE res := Compress.ErrorInArchive END
END Code;

PROCEDURE Decrypt(VAR Rin: Files.Rider; nIn: LONGINT; VAR Rout: Files.Rider; key: ARRAY OF CHAR; VAR res: INTEGER);
BEGIN Code(Rin, nIn, Rout, key, -1, res)
END Decrypt;

PROCEDURE Encrypt(VAR Rin: Files.Rider; nIn: LONGINT; VAR Rout: Files.Rider; key: ARRAY OF CHAR; VAR res: INTEGER);
BEGIN Code(Rin, nIn, Rout, key, 1, res)
END Encrypt;

PROCEDURE Set(c: INTEGER);
BEGIN cipher := c; Compress.Decrypt := Decrypt; Compress.Encrypt := Encrypt
END Set;

PROCEDURE Install*;
BEGIN Set(Voyager)
END Install;

PROCEDURE InstallMod*;
BEGIN Set(Mod)
END InstallMod;

PROCEDURE InstallXor*;
BEGIN Set(Xor)
END InstallXor;

END Crypt0.
