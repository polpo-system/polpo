MODULE compiler;  (** command-line version *)
  IMPORT
    OPP, OPB, OPV, OPT, OPS, OPC, OPL, OPO, OPM, Kernel, Root, Texts := texts, Oberon := Oberon0, Out := out;

  CONST
    NoBreakPC = -1;
    module = OPS.module; ident = OPS.ident; period = OPS.period;

  PROCEDURE SignOn;
  BEGIN
    Out.String("Oberon Portable Compiler / nw, rc, nm, tk, prk"); Out.Ln;
    Out.String(OPP.SignOnMessage); Out.Ln;
  END SignOn;

  PROCEDURE ParseOptions(VAR name, options, path, pref, extension: ARRAY OF CHAR;
                         VAR codeOpt, parserOpt: SET);
  VAR i, j, k: LONGINT; ch: CHAR;
  BEGIN
    codeOpt := OPM.DefaultCodeOpt;
    parserOpt := OPM.DefaultParserOpt;
    i := 0;
    path[0] := 0X;
    pref[0] := 0X;
    COPY(".Obj", extension);

    LOOP
      ch := options[i]; INC(i);
      IF ch = 0X THEN EXIT
      ELSIF ch = "x" THEN codeOpt := codeOpt / {OPM.inxchk}
      ELSIF ch = "v" THEN codeOpt := codeOpt / {OPM.ovflchk}
      ELSIF ch = "t" THEN codeOpt := codeOpt / {OPM.typchk}
      ELSIF ch = "p" THEN codeOpt := codeOpt / {OPM.ptrinit}
      ELSIF ch = "a" THEN codeOpt := codeOpt / {OPM.assert}
      ELSIF ch = "z" THEN codeOpt := codeOpt / {OPM.fullstackinit}
      ELSIF ch = "q" THEN codeOpt := codeOpt / {OPM.trace}
      ELSIF ch = "s" THEN parserOpt := parserOpt / {OPM.newsf}
      ELSIF ch = "i" THEN parserOpt := parserOpt / {OPM.symInObj}  (* polpo: the symbol file inside the .Obj *)
      ELSIF ch = "S" THEN parserOpt := parserOpt / {OPM.systemchk}
      ELSIF ch = "n" THEN parserOpt := parserOpt / {OPM.nofiles}
      ELSIF ch = "e" THEN parserOpt := parserOpt / {OPM.extsf}
      ELSIF ch = "f" THEN parserOpt := parserOpt / {OPM.findpc}
      ELSIF ch = "w" THEN parserOpt := parserOpt / {OPM.warning}
      ELSIF ch = "X" THEN parserOpt := parserOpt + {OPM.prefix}
      ELSIF ch = "2" THEN parserOpt := parserOpt / {OPM.oberon2}
      ELSIF ch = "1" THEN parserOpt := parserOpt / {OPM.oberon1}
      ELSIF ch = "T" THEN parserOpt := parserOpt / {OPM.traceprocs}
      ELSIF ch = "." THEN
        j := 0;
        WHILE (ch # 0X) & (ch # " ") DO
          extension[j] := ch;
          ch := options[i];
          INC(j); INC(i)
        END;
        extension[j] := 0X
      ELSIF ch = "P" THEN
        ch := options[i]; INC(i);
        k := 0;
        WHILE (ch # 0X) & (ch # " ") DO
          path[k] := ch; INC(k);
          ch := options[i]; INC(i)
        END;
        path[k] := 0X
      ELSIF ch = "O" THEN
        ch := options[i]; INC(i);
        k := 0;
        WHILE (ch # 0X) & (ch # " ") DO
          pref[k] := ch; INC(k);
          ch := options[i]; INC(i)
        END;
        pref[k] := 0X
      END
    END;

    IF OPM.prefix IN parserOpt THEN
      i := -1;
      REPEAT
        INC(i); pref[i] := name[i]
      UNTIL (name[i] = 0X) OR (name[i] = ".");
      IF name[i] # "." THEN i := 0 ELSE INC(i) END;
      pref[i] := 0X
    END;
    IF path[0] = 0X THEN Root.Obj("x86", path) END;
  END ParseOptions;

  PROCEDURE WriteMsg(source: Texts.Reader);
  VAR sym: SHORTINT;
  BEGIN
    Out.String(" compiling ");
    OPM.Init({}, {}, source, Oberon.Log);
    OPS.Get(sym);

    IF sym = module THEN
      OPS.Get(sym);
      IF sym = ident THEN
        Out.String(OPM.outputPath);
        Out.String(OPM.outputPrefix);
        OPS.Get(sym);
        Out.String(OPS.name);

        WHILE sym = period DO
          Out.Char(".");
          OPS.Get(sym);
          IF sym = ident THEN
            Out.String(OPS.name);
            OPS.Get(sym)
          END;
        END;

        IF OPM.extension # ".Obj" THEN
          Out.String(OPM.extension)
        END
      END
    END
  END WriteMsg;

  PROCEDURE OutputLog;
  (* Output the contents of Oberon.Log to console *)
  VAR R: Texts.Reader; ch: CHAR;
  BEGIN
    Texts.OpenReader(R, Oberon.Log, 0);
    Texts.Read(R, ch);
    WHILE ~R.eot DO
      Out.Char(ch);
      Texts.Read(R, ch)
    END
  END OutputLog;

  PROCEDURE Module*(source: Texts.Reader; name, options: ARRAY OF CHAR;
                    breakpc: LONGINT; VAR error: BOOLEAN);
  VAR
    codeOpt, parserOpt: SET;
    extSF, newSF: BOOLEAN;
    p: OPT.Node;
    modName: OPS.Name;
  BEGIN
    ParseOptions(name, options, OPM.outputPath, OPM.outputPrefix,
                 OPM.extension, codeOpt, parserOpt);
    WriteMsg(source);

    OPM.Init(codeOpt, parserOpt, source, Oberon.Log);
    OPS.ch := " ";
    OPB.typSize := OPV.TypSize;
    OPV.Init(breakpc);
    newSF := OPM.newsf IN parserOpt;
    extSF := OPM.extsf IN parserOpt;

    OPP.Module(p, modName);

    IF OPM.noerr THEN
      OPL.Init;
      OPM.errpos := 0;
      OPM.Begin(modName);

      IF OPM.noerr THEN
        OPT.Export(modName, newSF, extSF);
        OPV.AdrAndSize(OPT.topScope);

        IF newSF THEN
          Out.String(" new symbol file")
        ELSIF extSF THEN
          Out.String(" extended symbol file")
        END;

        IF OPM.noerr THEN
          OPM.errpos := 0;
          OPC.Init;
          OPV.Module(p);

          IF OPM.noerr THEN
            OPL.OutCode(modName);
            IF OPM.noerr THEN
              Out.String("   ");
              Out.Int(OPO.pc, 1)
            END
          END
        END;
        OPL.Close
      END
    END;

    OPT.CloseScope;
    OPT.Close;
    
    (* Output any messages/errors from Oberon.Log *)
    IF ~OPM.noerr THEN
      OutputLog
    END;
    
    Out.Ln;
    error := ~OPM.noerr;
    OPM.outputPath := "!";
    OPM.outputPrefix := "!"
  END Module;

  PROCEDURE CompileFile*(name, opt: ARRAY OF CHAR; VAR error: BOOLEAN);
  VAR
    t: Texts.Text;
    r: Texts.Reader;
  BEGIN
    NEW(t);
    Texts.Open(t, name);

    IF t.len # 0 THEN
      Texts.OpenReader(r, t, 0);
      Out.String(name);
      OPS.Init;
      Module(r, name, opt, NoBreakPC, error)
    ELSE
      Out.String(name);
      Out.String(" not found");
      Out.Ln;
      error := TRUE
    END
  END CompileFile;


PROCEDURE Help*;
BEGIN
  Out.String("Oberon Portable Compiler - Command Line Version"); Out.Ln;
  Out.Ln;
  Out.String("USAGE:"); Out.Ln;
  Out.String("  compiler.Compile [options] file1.Mod [file2.Mod ...]"); Out.Ln;
  Out.Ln;
  Out.String("OPTIONS:"); Out.Ln;
  Out.String("  Runtime Checks (prefix with / or \\ to disable):"); Out.Ln;
  Out.String("    /x   Disable index checking"); Out.Ln;
  Out.String("    /v   Disable overflow checking"); Out.Ln;
  Out.String("    /t   Disable type checking"); Out.Ln;
  Out.String("    /p   Disable pointer initialization"); Out.Ln;
  Out.String("    /a   Disable assertions"); Out.Ln;
  Out.String("    /z   Disable full stack initialization"); Out.Ln;
  Out.String("    /q   Disable trace"); Out.Ln;
  Out.Ln;
  Out.String("  Symbol Files:"); Out.Ln;
  Out.String("    /s   Generate new symbol file"); Out.Ln;
  Out.String("    /i   Symbol file inside the .Obj (Native Oberon), not a separate .Sym"); Out.Ln;
  Out.String("    /e   Generate extended symbol file"); Out.Ln;
  Out.Ln;
  Out.String("  Language Modes:"); Out.Ln;
  Out.String("    /1   Oberon-1 mode"); Out.Ln;
  Out.String("    /2   Oberon-2 mode"); Out.Ln;
  Out.Ln;
  Out.String("  Other Options:"); Out.Ln;
  Out.String("    /S   Enable system checking"); Out.Ln;
  Out.String("    /n   No files mode"); Out.Ln;
  Out.String("    /f   Find PC mode"); Out.Ln;
  Out.String("    /w   Enable warnings"); Out.Ln;
  Out.String("    /X   Use module name as prefix"); Out.Ln;
  Out.String("    /T   Trace procedures"); Out.Ln;
  Out.Ln;
  Out.String("  Output Control:"); Out.Ln;
  Out.String("    /.ext      Set output extension (e.g., /.Obj)"); Out.Ln;
  Out.String("    /Ppath     Set output path (e.g., /Pobj/x86/)"); Out.Ln;
  Out.String("    /Oprefix   Set output prefix"); Out.Ln;
  Out.Ln;
  Out.String("EXAMPLES:"); Out.Ln;
  Out.String("  Compile with default options:"); Out.Ln;
  Out.String("    compiler.Compile Test.Mod"); Out.Ln;
  Out.Ln;
  Out.String("  Compile with new symbol file:"); Out.Ln;
  Out.String("    compiler.Compile /s MyModule.Mod"); Out.Ln;
  Out.Ln;
  Out.String("  Compile multiple files without checks:"); Out.Ln;
  Out.String("    compiler.Compile /x /v /t File1.Mod File2.Mod"); Out.Ln;
  Out.Ln;
  Out.String("  Compile to specific directory:"); Out.Ln;
  Out.String("    compiler.Compile /Pobj/x86/ Test.Mod"); Out.Ln;
  Out.Ln;
END Help;


PROCEDURE Compile*;
VAR
  S: Texts.Scanner;
  name: ARRAY 64 OF CHAR;
  globalOpt, localOpt: ARRAY 64 OF CHAR;
  error: BOOLEAN;
  i, j: INTEGER;
BEGIN
  error := FALSE;
  globalOpt[0] := 0X;

  (* Read from Oberon parameter text, NOT from command line *)
  Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
  Texts.Scan(S);

  (* Check for help request or no arguments *)
  IF S.class = Texts.Inval THEN
    Help;
    RETURN
  END;
  
  (* Check for help options *)
  IF S.class = Texts.Name THEN
    IF (S.s = "/help") OR (S.s = "/h") OR (S.s = "/?") OR 
       (S.s = "\help") OR (S.s = "\h") OR (S.s = "\?") OR
       (S.s = "-help") OR (S.s = "-h") OR (S.s = "--help") THEN
      Help;
      RETURN
    END
  END;

  (* Process arguments from scanner - fixed loop structure *)
  WHILE (S.class # Texts.Inval) & ~error DO
    IF S.class = Texts.Name THEN
      COPY(S.s, name);

      (* Check if it's an option (starts with \ or /) *)
      IF (name[0] = "\") OR (name[0] = "/") THEN
        (* Extract option - shift left by 1 *)
        i := 0;
        WHILE name[i+1] # 0X DO
          name[i] := name[i+1];
          INC(i)
        END;
        name[i] := 0X;

        (* Append to globalOpt *)
        j := 0;
        WHILE globalOpt[j] # 0X DO INC(j) END;
        i := 0;
        WHILE name[i] # 0X DO
          globalOpt[j] := name[i];
          INC(i); INC(j)
        END;
        globalOpt[j] := 0X
      ELSE
        (* It's a filename - compile it *)
        COPY(globalOpt, localOpt);
        CompileFile(name, localOpt, error)
      END
    END;

    Texts.Scan(S)
  END
END Compile;

BEGIN
  SignOn
END compiler.
