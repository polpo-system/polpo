MODULE TOMLTest;  (* TOMLTest.Dump file: the sections and fields TOML reads, for comparing *)
IMPORT texts, Files, TOML, out;

PROCEDURE Dump*;
VAR A: texts.Reader; name: ARRAY 256 OF CHAR; f: Files.File; R: Files.Rider; buf: POINTER TO ARRAY OF CHAR;
  n, i: LONGINT; doc: TOML.Doc; s: TOML.Section; fl: TOML.Field; it: TOML.Item;
BEGIN
  texts.OpenArgs(A);
  IF ~texts.Arg(A, name) THEN out.String("usage: TOMLTest.Dump file"); out.Ln; RETURN END;
  f := Files.Old(name); IF f = NIL THEN out.String("no file"); out.Ln; RETURN END;
  n := Files.Length(f); NEW(buf, n + 1); Files.Set(R, f, 0);
  i := 0; WHILE i < n DO Files.Read(R, buf[i]); INC(i) END; buf[n] := 0X;
  doc := TOML.Parse(buf^);
  s := doc.first;
  WHILE s # NIL DO
    fl := s.first;
    WHILE fl # NIL DO
      out.String(s.name); out.String(" | "); out.String(fl.key); out.String(" | "); out.Int(fl.kind, 0); out.String(" | ");
      IF fl.kind = TOML.Array THEN
        it := fl.items; WHILE it # NIL DO out.Char("<"); out.String(it.value); out.Char(">"); it := it.next END
      ELSE out.Char("<"); out.String(fl.value); out.Char(">")
      END;
      out.Ln; fl := fl.next
    END;
    s := s.next
  END;
  out.String("errors "); out.Int(doc.errors, 0);
  IF doc.errors > 0 THEN out.String(" line "); out.Int(doc.errorLine, 0); out.String(": "); out.String(doc.error) END;
  out.Ln
END Dump;

END TOMLTest.
