MODULE asciicoder;  (** AsciiCoder in the console: files as plain text, for mail, and back *)

(* asciicoder.Code [%] out.txt file ...   codes the files into the text file out.txt, after the
                                          line "AsciiCoder.DecodeFiles [%] file ... ~"
                                          (% compresses first)
   asciicoder.Decode in.txt [dir]         decodes the files of such a text (made here, or by
                                          AsciiCoder.CodeFiles in the desktop) into dir
   The code is the one of AsciiCoder of ETH Oberon (AsciiCoder0): 64 characters from "0", lines
   of 76 characters. *)

IMPORT Files, Texts0, Texts, AsciiCoder0, Out;

CONST MaxFiles = 64;

TYPE Name = ARRAY 256 OF CHAR;

PROCEDURE Append(VAR s: ARRAY OF CHAR; t: ARRAY OF CHAR);
VAR i, j: LONGINT;
BEGIN
  i := 0; WHILE s[i] # 0X DO INC(i) END;
  j := 0; WHILE (t[j] # 0X) & (i < LEN(s) - 1) DO s[i] := t[j]; INC(i); INC(j) END;
  s[i] := 0X
END Append;

(* the text t as a plain file name (CR as LF) *)
PROCEDURE Store(t: Texts0.Text; VAR name: ARRAY OF CHAR);
VAR f: Files.File; w: Files.Rider; r: Texts0.Reader; ch: CHAR;
BEGIN
  f := Files.New(name); Files.Set(w, f, 0); Texts0.OpenReader(r, t, 0); Texts0.Read(r, ch);
  WHILE ~r.eot DO IF ch = 0DX THEN Files.Write(w, 0AX) ELSE Files.Write(w, ch) END; Texts0.Read(r, ch) END;
  Files.Register(f)
END Store;

PROCEDURE Code*;
VAR A: Texts.Reader; arg, dest: Name; names: ARRAY MaxFiles OF Name; n, i: INTEGER; compress: BOOLEAN;
  t: Texts0.Text; W: Texts0.Writer; f, f1: Files.File;
BEGIN
  Texts.OpenArgs(A); compress := FALSE; dest := ""; n := 0;
  WHILE Texts.Arg(A, arg) DO
    IF arg = "%" THEN compress := TRUE
    ELSIF dest = "" THEN COPY(arg, dest)
    ELSIF n < MaxFiles THEN COPY(arg, names[n]); INC(n)
    END
  END;
  IF (dest = "") OR (n = 0) THEN Out.String("usage: asciicoder.Code [%] out.txt file ..."); Out.Ln; RETURN END;
  NEW(t); Texts0.Open(t, ""); Texts0.OpenWriter(W);
  Texts0.WriteString(W, "AsciiCoder.DecodeFiles "); IF compress THEN Texts0.WriteString(W, "% ") END;
  i := 0; WHILE i < n DO Texts0.WriteString(W, names[i]); Texts0.Write(W, " "); INC(i) END;
  Texts0.Write(W, "~"); Texts0.WriteLn(W); Texts0.WriteLn(W); Texts0.Append(t, W.buf);
  i := 0;
  WHILE i < n DO
    f := Files.Old(names[i]);
    IF f = NIL THEN Out.String("asciicoder: no "); Out.String(names[i]); Out.String(", stopped"); Out.Ln; RETURN END;
    IF compress THEN f1 := Files.New(""); AsciiCoder0.Compress(f, f1); f := f1 END;
    AsciiCoder0.Code(f, t); INC(i)
  END;
  Store(t, dest);
  Out.String("asciicoder: "); Out.Int(n, 0); Out.String(" files in "); Out.String(dest); Out.String(", ");
  Out.Int(t.len, 0); Out.String(" characters"); Out.Ln
END Code;

PROCEDURE Decode*;
VAR A: Texts.Reader; src, dir, path: Name; t: Texts0.Text; S: Texts0.Scanner; names: ARRAY MaxFiles OF Name;
  n, i: INTEGER; compress, ok: BOOLEAN; pos: LONGINT; f, f1: Files.File;
BEGIN
  Texts.OpenArgs(A);
  IF ~Texts.Arg(A, src) THEN Out.String("usage: asciicoder.Decode in.txt [dir]"); Out.Ln; RETURN END;
  IF ~Texts.Arg(A, dir) THEN dir := "" ELSIF dir[0] # 0X THEN Append(dir, "/") END;
  IF Files.Old(src) = NIL THEN Out.String("asciicoder: no "); Out.String(src); Out.Ln; RETURN END;
  NEW(t); Texts0.Open(t, src); Texts0.OpenScanner(S, t, 0); Texts0.Scan(S);
  WHILE ~S.eot & ~((S.class = Texts0.Name) & (S.s = "AsciiCoder.DecodeFiles")) DO Texts0.Scan(S) END;
  IF S.eot THEN Out.String("asciicoder: no AsciiCoder.DecodeFiles in "); Out.String(src); Out.Ln; RETURN END;
  Texts0.Scan(S); compress := (S.class = Texts0.Char) & (S.c = "%"); IF compress THEN Texts0.Scan(S) END;
  n := 0;
  WHILE ((S.class = Texts0.Name) OR (S.class = Texts0.String)) & (n < MaxFiles) DO COPY(S.s, names[n]); INC(n); Texts0.Scan(S) END;
  IF ~((S.class = Texts0.Char) & (S.c = "~")) THEN Out.String("asciicoder: the list of files does not end with ~"); Out.Ln; RETURN END;
  pos := Texts0.Pos(S); ok := TRUE; i := 0;
  WHILE ok & (i < n) DO
    COPY(dir, path); Append(path, names[i]);
    IF compress THEN f := Files.New("") ELSE f := Files.New(path) END;
    AsciiCoder0.Decode(t, pos, f, ok);
    IF ok THEN
      IF compress THEN f1 := Files.New(path); AsciiCoder0.Expand(f, f1); f := f1 END;
      Files.Register(f); Out.String("asciicoder: "); Out.String(path); Out.String(", "); Out.Int(Files.Length(f), 0); Out.String(" bytes"); Out.Ln
    ELSE Out.String("asciicoder: the code of "); Out.String(names[i]); Out.String(" is damaged"); Out.Ln
    END;
    INC(i)
  END
END Decode;

END asciicoder.
