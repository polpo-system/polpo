MODULE CompressCrypt; (** portable *)  (* ejz   *)
(* the encryption of Compress (.Arc) of ETH Oberon System 3: each byte plus (decrypting) or minus
   (encrypting) a character of the key. It is plugged in by name, not imported:
     arc.Add \C CompressCrypt.Install "key" archive.Arc file ...   (console)
     Compress.Add \C CompressCrypt.Install "key" archive.Arc file ... ~   (System 3)
   Compress0.InstallCrypt loads the module and calls Install, which sets Compress0.Decrypt and
   Compress0.Encrypt; another cipher is another module with an Install command.
   polpo: Compress is Compress0, the length of the key without Strings. *)

  IMPORT Files, Compress := Compress0;

  PROCEDURE Length(VAR s: ARRAY OF CHAR): LONGINT;
    VAR i: LONGINT;
  BEGIN i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END; RETURN i
  END Length;

  PROCEDURE Decrypt(VAR Rin: Files.Rider; nIn: LONGINT; VAR Rout: Files.Rider; key: ARRAY OF CHAR; VAR res: INTEGER);
    VAR
      i, n: LONGINT;
      ch: CHAR;
  BEGIN
    n := Length(key); i := 0;
    WHILE i < nIn DO
      Files.Read(Rin, ch);
      Files.Write(Rout, CHR( (ORD(ch)+ORD(key[i MOD n])) MOD 256 ) );
      INC(i)
    END;
    res := Compress.Done
  END Decrypt;

  PROCEDURE Encrypt(VAR Rin: Files.Rider; nIn: LONGINT; VAR Rout: Files.Rider; key: ARRAY OF CHAR; VAR res: INTEGER);
    VAR
      i, n: LONGINT;
      ch: CHAR;
  BEGIN
    n := Length(key); i := 0;
    WHILE i < nIn DO
      Files.Read(Rin, ch);
      Files.Write(Rout, CHR( (ORD(ch)-ORD(key[i MOD n])) MOD 256 ) );
      INC(i)
    END;
    res := Compress.Done
  END Encrypt;

  PROCEDURE Install*;
  BEGIN
    Compress.Decrypt := Decrypt;
    Compress.Encrypt := Encrypt
  END Install;

END CompressCrypt.
