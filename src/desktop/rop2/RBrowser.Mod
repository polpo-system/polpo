MODULE RBrowser;  (** the desktop browser of the ROP2 ports (ARMv7, RISC-V, MIPS) *)

(* RBrowser.ShowDef module [\d] [\e]   the interface of module in a viewer (module.Def)
   RBrowser.ShowDef ^                 of the selected name
   \d with offsets, addresses and sizes, \e with the fields of the base types of records ("/" as
   well as "\"). The definition is written by the console browser of the port (browser.Definition),
   from Browser of OLR ROP2: the same text as browser.ShowDef in the console. x86 has XBrowser, ARM
   ABrowser. *)

IMPORT browser, Texts, Oberon;

VAR W: Texts.Writer;

PROCEDURE ShowDef*;
VAR S: Texts.Scanner; text, T: Texts.Text; beg, end, time: LONGINT; name, title, dir: ARRAY 64 OF CHAR;
  detail, ext: BOOLEAN; i: INTEGER;
BEGIN
  Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
  IF (S.class = Texts.Char) & (S.c = "^") THEN
    Oberon.GetSelection(text, beg, end, time);
    IF time >= 0 THEN Texts.OpenScanner(S, text, beg); Texts.Scan(S) ELSE RETURN END
  END;
  IF S.class # Texts.Name THEN RETURN END;
  i := 0; WHILE (S.s[i] # 0X) & (S.s[i] # ".") DO name[i] := S.s[i]; INC(i) END; name[i] := 0X;  (* Module or Module.Name *)
  detail := FALSE; ext := FALSE; Texts.Scan(S);
  IF (S.class = Texts.Char) & ((S.c = Oberon.OptionChar) OR (S.c = "/") OR (S.c = "\")) THEN
    Texts.Scan(S);
    IF S.class = Texts.Name THEN
      i := 0;
      WHILE S.s[i] # 0X DO
        IF S.s[i] = "d" THEN detail := TRUE ELSIF S.s[i] = "e" THEN ext := TRUE END;
        INC(i)
      END
    END
  END;
  NEW(T); Texts.Open(T, "");
  IF browser.Definition(name, detail, ext, T) THEN
    COPY(name, title); i := 0; WHILE title[i] # 0X DO INC(i) END;
    title[i] := "."; title[i+1] := "D"; title[i+2] := "e"; title[i+3] := "f"; title[i+4] := 0X;
    Oberon.OpenText(title, T, 400, 200)
  ELSE
    browser.Dir(dir);
    Texts.WriteString(W, "RBrowser: no "); Texts.WriteString(W, name); Texts.WriteString(W, ".Sym in ");
    Texts.WriteString(W, dir); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
  END
END ShowDef;

BEGIN
  Texts.OpenWriter(W)
END RBrowser.
