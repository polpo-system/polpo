MODULE asciicoder;  (** AsciiCoder in the console: files as plain text, for mail, and back *)

(* asciicoder.Code [%] out.txt file ...   codes the files into the text file out.txt, after the
                                          line "AsciiCoder.DecodeFiles [%] file ... ~"
                                          (% compresses first)
   asciicoder.Decode in.txt [dir]         decodes the files of such a text (made here, or by
                                          AsciiCoder.CodeFiles in the desktop) into dir
   The code is the one of AsciiCoder of ETH Oberon (AsciiCoder0): 64 characters from "0", lines
   of 76 characters. *)

IMPORT Files, Texts := Texts0, texts, AsciiCoder0, out;

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
PROCEDURE Store(t: Texts.Text; VAR name: ARRAY OF CHAR);
VAR f: Files.File; w: Files.Rider; r: Texts.Reader; ch: CHAR;
BEGIN
  f := Files.New(name); Files.Set(w, f, 0); Texts.OpenReader(r, t, 0); Texts.Read(r, ch);
  WHILE ~r.eot DO IF ch = 0DX THEN Files.Write(w, 0AX) ELSE Files.Write(w, ch) END; Texts.Read(r, ch) END;
  Files.Register(f)
END Store;

PROCEDURE Code*;
VAR A: texts.Reader; arg, dest: Name; names: ARRAY MaxFiles OF Name; n, i: INTEGER; compress: BOOLEAN;
  t: Texts.Text; W: Texts.Writer; f, f1: Files.File;
BEGIN
  texts.OpenArgs(A); compress := FALSE; dest := ""; n := 0;
  WHILE texts.Arg(A, arg) DO
    IF arg = "%" THEN compress := TRUE
    ELSIF dest = "" THEN COPY(arg, dest)
    ELSIF n < MaxFiles THEN COPY(arg, names[n]); INC(n)
    END
  END;
  IF (dest = "") OR (n = 0) THEN out.String("usage: asciicoder.Code [%] out.txt file ..."); out.Ln; RETURN END;
  NEW(t); Texts.Open(t, ""); Texts.OpenWriter(W);
  Texts.WriteString(W, "AsciiCoder.DecodeFiles "); IF compress THEN Texts.WriteString(W, "% ") END;
  i := 0; WHILE i < n DO Texts.WriteString(W, names[i]); Texts.Write(W, " "); INC(i) END;
  Texts.Write(W, "~"); Texts.WriteLn(W); Texts.WriteLn(W); Texts.Append(t, W.buf);
  i := 0;
  WHILE i < n DO
    f := Files.Old(names[i]);
    IF f = NIL THEN out.String("asciicoder: no "); out.String(names[i]); out.String(", stopped"); out.Ln; RETURN END;
    IF compress THEN f1 := Files.New(""); AsciiCoder0.Compress(f, f1); f := f1 END;
    AsciiCoder0.Code(f, t); INC(i)
  END;
  Store(t, dest);
  out.String("asciicoder: "); out.Int(n, 0); out.String(" files in "); out.String(dest); out.String(", ");
  out.Int(t.len, 0); out.String(" characters"); out.Ln
END Code;

PROCEDURE Decode*;
VAR A: texts.Reader; src, dir, path: Name; t: Texts.Text; S: Texts.Scanner; names: ARRAY MaxFiles OF Name;
  n, i: INTEGER; compress, ok: BOOLEAN; pos: LONGINT; f, f1: Files.File;
BEGIN
  texts.OpenArgs(A);
  IF ~texts.Arg(A, src) THEN out.String("usage: asciicoder.Decode in.txt [dir]"); out.Ln; RETURN END;
  IF ~texts.Arg(A, dir) THEN dir := "" ELSIF dir[0] # 0X THEN Append(dir, "/") END;
  IF Files.Old(src) = NIL THEN out.String("asciicoder: no "); out.String(src); out.Ln; RETURN END;
  NEW(t); Texts.Open(t, src); Texts.OpenScanner(S, t, 0); Texts.Scan(S);
  WHILE ~S.eot & ~((S.class = Texts.Name) & (S.s = "AsciiCoder.DecodeFiles")) DO Texts.Scan(S) END;
  IF S.eot THEN out.String("asciicoder: no AsciiCoder.DecodeFiles in "); out.String(src); out.Ln; RETURN END;
  Texts.Scan(S); compress := (S.class = Texts.Char) & (S.c = "%"); IF compress THEN Texts.Scan(S) END;
  n := 0;
  WHILE ((S.class = Texts.Name) OR (S.class = Texts.String)) & (n < MaxFiles) DO COPY(S.s, names[n]); INC(n); Texts.Scan(S) END;
  IF ~((S.class = Texts.Char) & (S.c = "~")) THEN out.String("asciicoder: the list of files does not end with ~"); out.Ln; RETURN END;
  pos := Texts.Pos(S); ok := TRUE; i := 0;
  WHILE ok & (i < n) DO
    COPY(dir, path); Append(path, names[i]);
    IF compress THEN f := Files.New("") ELSE f := Files.New(path) END;
    AsciiCoder0.Decode(t, pos, f, ok);
    IF ok THEN
      IF compress THEN f1 := Files.New(path); AsciiCoder0.Expand(f, f1); f := f1 END;
      Files.Register(f); out.String("asciicoder: "); out.String(path); out.String(", "); out.Int(Files.Length(f), 0); out.String(" bytes"); out.Ln
    ELSE out.String("asciicoder: the code of "); out.String(names[i]); out.String(" is damaged"); out.Ln
    END;
    INC(i)
  END
END Decode;

END asciicoder.
