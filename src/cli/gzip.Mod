MODULE gzip;  (** gzip files in the console, with the zlib of ETH Oberon (GZReaders, GZWriters) *)

(* gzip.Compress file [file.gz]     compresses file (default output: file.gz)
   gzip.Decompress file.gz [file]   decompresses (default output: the name without .gz)
   The files are those of gzip (RFC 1952): the ones of gzip -d and tar -z. *)

IMPORT Files, GZReaders, GZWriters, texts, out;

CONST BufLen = 8192;

TYPE Name = ARRAY 256 OF CHAR;

PROCEDURE Len(VAR s: ARRAY OF CHAR): LONGINT;
VAR i: LONGINT;
BEGIN i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END; RETURN i
END Len;

PROCEDURE Args(VAR a, b: ARRAY OF CHAR): BOOLEAN;  (* the first argument, and the second if there is one *)
VAR A: texts.Reader;
BEGIN texts.OpenArgs(A); b[0] := 0X; RETURN texts.Arg(A, a) & (texts.Arg(A, b) OR TRUE)
END Args;

PROCEDURE Compress*;
VAR in, name: Name; f, g: Files.File; r: Files.Rider; w: GZWriters.Writer; buf: ARRAY BufLen OF CHAR; n, written, total: LONGINT;
BEGIN
  IF ~Args(in, name) THEN out.String("usage: gzip.Compress file [file.gz]"); out.Ln; RETURN END;
  IF name = "" THEN COPY(in, name); n := Len(name); name[n] := "."; name[n+1] := "g"; name[n+2] := "z"; name[n+3] := 0X END;
  f := Files.Old(in); IF f = NIL THEN out.String("gzip: no "); out.String(in); out.Ln; RETURN END;
  g := Files.New(name); GZWriters.Open(w, GZWriters.DefaultCompression, GZWriters.DefaultStrategy, g);
  Files.Set(r, f, 0); total := 0;
  LOOP
    Files.ReadBytes(r, buf, BufLen); n := BufLen - r.res;
    IF n <= 0 THEN EXIT END;
    GZWriters.WriteBytes(w, buf, 0, n, written); INC(total, n);
    IF r.res # 0 THEN EXIT END
  END;
  GZWriters.Close(w);
  IF w.res = GZWriters.Ok THEN
    Files.Register(g); out.String("gzip: "); out.String(name); out.String(", "); out.Int(total, 0); out.String(" bytes to ");
    out.Int(Files.Length(g), 0)
  ELSE out.String("gzip: compression failed, "); out.Int(w.res, 0)
  END;
  out.Ln
END Compress;

PROCEDURE Decompress*;
VAR in, name: Name; f, g: Files.File; w: Files.Rider; r: GZReaders.Reader; buf: ARRAY BufLen OF CHAR; n, total, i: LONGINT;
BEGIN
  IF ~Args(in, name) THEN out.String("usage: gzip.Decompress file.gz [file]"); out.Ln; RETURN END;
  IF name = "" THEN
    COPY(in, name); i := Len(name);
    IF (i > 3) & (name[i-3] = ".") & (name[i-2] = "g") & (name[i-1] = "z") THEN name[i-3] := 0X
    ELSE out.String("gzip: name the output (no .gz in "); out.String(in); out.String(")"); out.Ln; RETURN
    END
  END;
  f := Files.Old(in); IF f = NIL THEN out.String("gzip: no "); out.String(in); out.Ln; RETURN END;
  GZReaders.Open(r, f);
  IF r.res # GZReaders.Ok THEN out.String("gzip: "); out.String(in); out.String(" is not a gzip file"); out.Ln; RETURN END;
  g := Files.New(name); Files.Set(w, g, 0); total := 0;
  LOOP
    GZReaders.ReadBytes(r, buf, 0, BufLen, n);
    IF n > 0 THEN Files.WriteBytes(w, buf, n); INC(total, n) END;
    IF (n < BufLen) OR (r.res # GZReaders.Ok) THEN EXIT END
  END;
  IF (r.res = GZReaders.Ok) OR (r.res = GZReaders.StreamEnd) THEN
    Files.Register(g); out.String("gzip: "); out.String(name); out.String(", "); out.Int(total, 0); out.String(" bytes")
  ELSE out.String("gzip: "); out.String(in); out.String(" is damaged, "); out.Int(r.res, 0)
  END;
  GZReaders.Close(r); out.Ln
END Decompress;

END gzip.
