MODULE TOMLTest;  (* TOMLTest.Dump file: the sections and fields TOML reads, for comparing *)
IMPORT Texts, Files, TOML, Out;

PROCEDURE Dump*;
VAR A: Texts.Reader; name: ARRAY 256 OF CHAR; f: Files.File; R: Files.Rider; buf: POINTER TO ARRAY OF CHAR;
  n, i: LONGINT; doc: TOML.Doc; s: TOML.Section; fl: TOML.Field; it: TOML.Item;
BEGIN
  Texts.OpenArgs(A);
  IF ~Texts.Arg(A, name) THEN Out.String("usage: TOMLTest.Dump file"); Out.Ln; RETURN END;
  f := Files.Old(name); IF f = NIL THEN Out.String("no file"); Out.Ln; RETURN END;
  n := Files.Length(f); NEW(buf, n + 1); Files.Set(R, f, 0);
  i := 0; WHILE i < n DO Files.Read(R, buf[i]); INC(i) END; buf[n] := 0X;
  doc := TOML.Parse(buf^);
  s := doc.first;
  WHILE s # NIL DO
    fl := s.first;
    WHILE fl # NIL DO
      Out.String(s.name); Out.String(" | "); Out.String(fl.key); Out.String(" | "); Out.Int(fl.kind, 0); Out.String(" | ");
      IF fl.kind = TOML.Array THEN
        it := fl.items; WHILE it # NIL DO Out.Char("<"); Out.String(it.value); Out.Char(">"); it := it.next END
      ELSE Out.Char("<"); Out.String(fl.value); Out.Char(">")
      END;
      Out.Ln; fl := fl.next
    END;
    s := s.next
  END;
  Out.String("errors "); Out.Int(doc.errors, 0);
  IF doc.errors > 0 THEN Out.String(" line "); Out.Int(doc.errorLine, 0); Out.String(": "); Out.String(doc.error) END;
  Out.Ln
END Dump;

END TOMLTest.
