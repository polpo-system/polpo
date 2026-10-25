MODULE acompiler;  (** command-line frontend of the ARM compiler *)
  IMPORT
    OBS, OBP, OBC, OC := OBM, Texts, Oberon := Oberon0, Out := out, logs;

  VAR HW: Texts.Writer;  (* see Head *)
    find: BOOLEAN; breakpc: LONGINT;  (* /f pc: find the source position of pc *)

  PROCEDURE SignOn;
  BEGIN
    Out.String("ARM Compiler  NW 14.12.93 / as 2.12.98 / prk 09.12.99 / pm / polpo"); Out.Ln
  END SignOn;


  (* polpo: the name of the file being compiled; in the desktop straight into the log, before what
    the compiler writes there itself (out keeps a line until its end) *)
  PROCEDURE Head(s: ARRAY OF CHAR);
  BEGIN
    IF Out.writer = NIL THEN Out.String(s) ELSE Texts.WriteString(HW, s); Texts.Append(Oberon.Log, HW.buf) END
  END Head;

  PROCEDURE CompileFile(name, opt: ARRAY OF CHAR; VAR error: BOOLEAN);
    VAR t: Texts.Text; pos: LONGINT;
  BEGIN
    NEW(t); Texts.Open(t, name);
    Head(name);
    IF t.len # 0 THEN
      OBP.SetDefaults; OBP.ParseOptions(opt);
      IF find THEN OBP.SetTrapPC(breakpc) END;
      pos := Oberon.Log.len;
      OBP.CompilationUnit(t, 0);
      logs.Show(pos);
      IF find THEN  (* where the scanner was when the code reached pc: the statement ends before it *)
        IF OBC.foundPos >= 0 THEN logs.ShowPC(name, t, OBC.foundPos, breakpc)
        ELSE Out.String("  pc not found"); Out.Ln
        END
      END;
      error := OBS.scanerr
    ELSE
      Head(" not found"); Out.Ln;
      error := TRUE
    END;
    Oberon.Collect
  END CompileFile;

  PROCEDURE Help*;
  BEGIN
    Out.String("USAGE:"); Out.Ln;
    Out.String("  acompiler.Compile [options] file1.Mod [file2.Mod ...]"); Out.Ln;
    Out.Ln;
    Out.String("Options (prefix with / or \, each toggles its default):"); Out.Ln;
    Out.String("  /x       index checks (on)"); Out.Ln;
    Out.String("  /t       type checks (on)"); Out.Ln;
    Out.String("  /z       clear local pointers (on)"); Out.Ln;
    Out.String("  /v       overflow checks (off)"); Out.Ln;
    Out.String("  /s       allow new symbol file"); Out.Ln;
    Out.String("  /n       do not write output files"); Out.Ln;
    Out.String("  /a       constant block statistics"); Out.Ln;
    Out.String("  /Pdir/   symbol and object file prefix (default obj/arm/)"); Out.Ln;
    Out.String("  /f pc    find the statement of pc (the PC of a trap): file:line:column, no object"); Out.Ln;
    Out.Ln;
    Out.String("Options apply to the files that follow them."); Out.Ln
  END Help;

  PROCEDURE Compile*;
    VAR
      S: Texts.Scanner;
      name: ARRAY 64 OF CHAR;
      opt: ARRAY 64 OF CHAR;
      error: BOOLEAN;
      i, j: INTEGER;
  BEGIN
    error := FALSE; opt[0] := 0X; find := FALSE; breakpc := 0;
    Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
    Texts.Scan(S);
    IF S.class # Texts.Name THEN Help; RETURN END;
    WHILE ((S.class = Texts.Name) OR (S.class = Texts.Int)) & ~error DO
      IF S.class = Texts.Int THEN name := ""; breakpc := S.i ELSE COPY(S.s, name) END;
      IF name = "" THEN
      ELSIF name = "/f" THEN find := ~find
      ELSIF (name = "/h") OR (name = "-h") OR (name = "--help") OR (name = "/help") THEN
        Help; RETURN
      ELSIF (name[0] = "/") OR (name[0] = "\") THEN
        j := 0; WHILE opt[j] # 0X DO INC(j) END;
        i := 1;
        WHILE (name[i] # 0X) & (j < LEN(opt)-2) DO opt[j] := name[i]; INC(i); INC(j) END;
        opt[j] := " "; opt[j+1] := 0X
      ELSE
        CompileFile(name, opt, error)
      END;
      Texts.Scan(S)
    END;
    OC.prefix := ""
  END Compile;

BEGIN
  Texts.OpenWriter(HW); SignOn
END acompiler.
