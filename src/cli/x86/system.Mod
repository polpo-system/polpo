MODULE system;

IMPORT SYSTEM, Kernel, Mods := Modules, Oberon0, Texts, Out := out;

PROCEDURE ShowModules*;
VAR m: Kernel.Module; dsize, csize, count, total: LONGINT;
BEGIN
  m := Kernel.modules; count := 0; total := 0;
  WHILE m # NIL DO
    dsize := m.sb - SYSTEM.ADR(m.data[0]);
    csize := LEN(m.data^) - dsize;
    Out.String(m.name); Out.Char(9X);
    Out.Int(dsize + csize + LEN(m.code^), 1); Out.Char(9X);
    Out.Int(m.refcnt, 1); Out.Ln;
    INC(total, dsize + csize + LEN(m.code^)); INC(count);
    m := m.next
  END;
  IF count > 1 THEN
    Out.String("TOTAL"); Out.Char(9X); Out.Int(total, 1); Out.Char(9X);
    Out.Int(count, 1); Out.Ln
  END
END ShowModules;

PROCEDURE Free*;
VAR S: Texts.Scanner; name: ARRAY 64 OF CHAR; all: BOOLEAN;
BEGIN
  Texts.OpenScanner(S, Oberon0.Par.text, Oberon0.Par.pos); Texts.Scan(S);
  IF S.class # Texts.Name THEN
    Out.String("usage: system.Free Module [*] ..."); Out.Ln; RETURN
  END;
  WHILE S.class = Texts.Name DO
    COPY(S.s, name); Texts.Scan(S); all := FALSE;
    IF (S.class = Texts.Char) & (S.c = "*") THEN all := TRUE; Texts.Scan(S) END;
    IF (name = "shell") OR (name = "system") THEN
      Out.String(name); Out.String(" is part of the active console"); Out.Ln
    ELSE
      Mods.Free(name, all);
      IF Mods.res = 0 THEN
        Out.String(name); Out.String(" unloaded")
      ELSE
        Out.String(Mods.resMsg)
      END;
      Out.Ln
    END
  END
END Free;

BEGIN
END system.
