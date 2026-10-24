MODULE cat;
(** Deprecated: use Texts.Show and Texts.ShowPlain.
    cat.Cat [-p] file... shows Oberon texts on the terminal, -p without fonts and colours. *)

IMPORT Texts, Oberon := Oberon0;

PROCEDURE Cat*;
VAR S: Texts.Scanner; rich: BOOLEAN;
BEGIN
  rich := TRUE;
  Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
  WHILE (S.class IN {Texts.Name, Texts.String}) OR (S.class = Texts.Char) & (S.c = "-") DO
    IF S.class = Texts.Char THEN
      Texts.Scan(S);
      IF (S.class = Texts.Name) & (S.s[0] = "p") THEN rich := FALSE END
    ELSE Texts.ShowFile(S.s, rich)
    END;
    Texts.Scan(S)
  END
END Cat;

END cat.
