MODULE rcompiler;  (** command-line frontend of the ROP2 compilers: MIPS, RISC-V, ARMv7, PowerPC *)
(* after RCompiler (ROP2), RC 6.3.89 / 17.6.93, p.m. 2017-06-12 *)
  IMPORT
    OPM := ROPM, OPT := ROPT, OPP := ROPP, Modules, Linux0, Root,
    Texts, Oberon := Oberon0, Out := out, logs;

  CONST
    mipstag* = 0F9X; armv7tag* = 0FBX; riscvtag* = 0FDX; mipsbetag* = 0F8X; ppctag* = 0F7X;
    (* compiler options *)
    inxchk = 0; ovflchk = 1; ranchk = 2; typchk = 3; newsf = 4; ptrinit = 5;
    intprinf = 6; assert = 7; findpc = 8; extsf = 9; softdiv = 10; bigend = 11;
    defopt = {inxchk, typchk, ptrinit, assert};

  VAR
    dir*: ARRAY 256 OF CHAR;  (** object and symbol file directory *)
    HW: Texts.Writer;  (* see Head *)
    tag: CHAR;  (* object file tag of the target *)
    target: ARRAY 32 OF CHAR;  (* name of the target *)
    backend: ARRAY 32 OF CHAR;  (* back end module: VOPV, MOPV, AOPV *)
    init, module: Modules.Command;  (* its Init and Module *)
    targetopt: SET;  (* default options of the target *)

  PROCEDURE SignOn;
  BEGIN
    Out.String(target); Out.String(" Compiler  ROP2 RC 10.2.94 / p.m. 2016-11-22 / polpo"); Out.Ln
  END SignOn;

  (* Load the back end module and find its Init and Module commands. *)
  PROCEDURE LoadBackend(): BOOLEAN;
    VAR m: Modules.Module;
  BEGIN
    m := Modules.ThisMod(backend); init := NIL; module := NIL;
    IF m # NIL THEN init := Modules.ThisCommand(m, "Init"); module := Modules.ThisCommand(m, "Module") END;
    IF (init = NIL) OR (module = NIL) THEN
      Out.String(backend); Out.String(": back end not found"); Out.Ln; RETURN FALSE
    END;
    SignOn;
    RETURN TRUE
  END LoadBackend;


  (** Compile the text read by source with the option characters in options. *)
  PROCEDURE Module*(VAR source: Texts.Reader; options: ARRAY OF CHAR; VAR error: BOOLEAN);
    VAR ch: CHAR; i: INTEGER; ext, new: BOOLEAN;
  BEGIN
    OPM.opt := defopt / targetopt; OPM.OFtag := tag; COPY(dir, OPM.Dir); i := 0;
    REPEAT
      ch := options[i]; INC(i);
      IF ch = "x" THEN OPM.opt := OPM.opt / {inxchk}
      ELSIF ch = "v" THEN OPM.opt := OPM.opt / {ovflchk}
      ELSIF ch = "r" THEN OPM.opt := OPM.opt / {ranchk}
      ELSIF ch = "t" THEN OPM.opt := OPM.opt / {typchk}
      ELSIF ch = "s" THEN OPM.opt := OPM.opt / {newsf}
      ELSIF ch = "p" THEN OPM.opt := OPM.opt / {ptrinit}
      ELSIF ch = "i" THEN OPM.opt := OPM.opt / {intprinf}
      ELSIF ch = "a" THEN OPM.opt := OPM.opt / {assert}
      ELSIF ch = "e" THEN OPM.opt := OPM.opt / {extsf}
      ELSIF ch = "d" THEN OPM.opt := OPM.opt / {softdiv}
      END
    UNTIL ch = 0X;
    OPM.Init(source, Oberon.Log);
    OPP.Module(OPT.prog, OPM.opt);
    IF OPM.noerr THEN
      init; OPT.Export(ext, new);
      IF OPM.noerr THEN
        module;
        IF OPM.noerr THEN
          IF new OR ext THEN OPM.RegisterNewSym END;
          IF new THEN OPM.LogWStr(" new symbol file")
          ELSIF ext THEN OPM.LogWStr(" extended symbol file")
          END;
          OPM.LogWNum(4*OPM.pc, 8); OPM.LogWNum(-OPM.sb, 8)
        ELSE OPM.DeleteNewSym
        END
      END
    END;
    OPT.Close;
    OPM.LogWLn; error := ~OPM.noerr
  END Module;

  (* polpo: the name of the file being compiled; in the desktop straight into the log, before what
    the compiler writes there itself (out keeps a line until its end) *)
  PROCEDURE Head(s: ARRAY OF CHAR);
  BEGIN
    IF Out.writer = NIL THEN Out.String(s) ELSE Texts.WriteString(HW, s); Texts.Append(Oberon.Log, HW.buf) END
  END Head;

  PROCEDURE CompileFile(name, opt: ARRAY OF CHAR; VAR error: BOOLEAN);
    VAR t: Texts.Text; r: Texts.Reader; pos: LONGINT;
  BEGIN
    NEW(t); Texts.Open(t, name);
    Head(name);
    IF t.len # 0 THEN
      Head("  compiling  "); Head(dir);
      pos := Oberon.Log.len;
      Texts.OpenReader(r, t, 0);
      Module(r, opt, error);
      logs.Show(pos)
    ELSE
      Head(" not found"); Out.Ln; error := TRUE
    END;
    Oberon.Collect
  END CompileFile;

  PROCEDURE Help*;
  BEGIN
    Out.String("USAGE:"); Out.Ln;
    Out.String("  rcompiler.Compile [/v | /m | /a] [options] file1.Mod [file2.Mod ...]"); Out.Ln;
    Out.String("  (mcompiler.Compile, rvcompiler.Compile, pcompiler.Compile: MIPS, RISC-V, PowerPC)"); Out.Ln;
    Out.Ln;
    Out.String("Target (default: the host architecture):"); Out.Ln;
    Out.String("  /v       RISC-V, obj/riscv/"); Out.Ln;
    Out.String("  /m       MIPS, obj/mips/"); Out.Ln;
    Out.String("  /a       ARMv7, obj/armv7/"); Out.Ln;
    Out.String("  /w       PowerPC (32-bit), obj/ppc/"); Out.Ln;
    Out.Ln;
    Out.String("Options (prefix with / or \, each toggles its default):"); Out.Ln;
    Out.String("  /x       index checks (on)"); Out.Ln;
    Out.String("  /t       type checks (on)"); Out.Ln;
    Out.String("  /p       pointer initialization (on)"); Out.Ln;
    Out.String("  /a       assertions (on)"); Out.Ln;
    Out.String("  /v       overflow checks (off)"); Out.Ln;
    Out.String("  /r       range checks (off)"); Out.Ln;
    Out.String("  /s       allow new symbol file"); Out.Ln;
    Out.String("  /e       allow extended symbol file"); Out.Ln;
    Out.String("  /d       software division (ARMv7: on, /d selects hardware sdiv)"); Out.Ln;
    Out.String("  /Pdir/   symbol and object file directory (default obj/<target>/)"); Out.Ln;
    Out.Ln;
    Out.String("Options apply to the files that follow them."); Out.Ln
  END Help;

  (** Select the target: back end module, architecture (object directory obj/<arch>/, see Root)
    and object file tag. *)
  PROCEDURE SetTarget*(name, backendMod, arch: ARRAY OF CHAR; objTag: CHAR);
  BEGIN
    COPY(name, target); COPY(backendMod, backend); Root.Obj(arch, dir); tag := objTag;
    (* ARMv7: software division by default, Cortex-A8 and A9 have no divide instruction *)
    IF name = "ARMv7" THEN targetopt := {softdiv}
    ELSIF (name = "MIPSBE") OR (name = "PPC") THEN targetopt := {bigend}  (* polpo: big-endian *)
    ELSE targetopt := {}
    END
  END SetTarget;

  PROCEDURE SetHostTarget;
  BEGIN
    IF Linux0.ARCH = "PPC" THEN SetTarget("PPC", "POPV", "ppc", ppctag)
    ELSIF Linux0.ARCH = "MIPSBE" THEN SetTarget("MIPSBE", "MOPV", "mipsbe", mipsbetag)
    ELSIF Linux0.ARCH = "MIPS" THEN SetTarget("MIPS", "MOPV", "mips", mipstag)
    ELSIF Linux0.ARCH = "ARMv7" THEN SetTarget("ARMv7", "AOPV", "armv7", armv7tag)
    ELSE SetTarget("RISC-V", "VOPV", "riscv", riscvtag)
    END
  END SetHostTarget;

  (** Compile with the target selected by SetTarget (or options /v, /m, /a, /w). *)
  PROCEDURE CompileTarget*;
    VAR
      S: Texts.Scanner;
      name, opt: ARRAY 64 OF CHAR;
      error, loaded: BOOLEAN;
      i, j: INTEGER;
  BEGIN
    error := FALSE; loaded := FALSE; opt[0] := 0X;
    Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
    Texts.Scan(S);
    IF S.class # Texts.Name THEN Help; RETURN END;
    WHILE (S.class = Texts.Name) & ~error DO
      COPY(S.s, name);
      IF (name = "/h") OR (name = "-h") OR (name = "--help") OR (name = "/help") THEN
        Help; RETURN
      ELSIF name = "/v" THEN SetTarget("RISC-V", "VOPV", "riscv", riscvtag)
      ELSIF name = "/m" THEN SetTarget("MIPS", "MOPV", "mips", mipstag)
      ELSIF name = "/a" THEN SetTarget("ARMv7", "AOPV", "armv7", armv7tag)
      ELSIF name = "/w" THEN SetTarget("PPC", "POPV", "ppc", ppctag)
      ELSIF ((name[0] = "/") OR (name[0] = "\")) & (name[1] = "P") THEN
        i := 2; WHILE (name[i] # 0X) & (i-2 < LEN(dir)-1) DO dir[i-2] := name[i]; INC(i) END;
        dir[i-2] := 0X
      ELSIF (name[0] = "/") OR (name[0] = "\") THEN
        j := 0; WHILE opt[j] # 0X DO INC(j) END;
        i := 1;
        WHILE (name[i] # 0X) & (j < LEN(opt)-1) DO opt[j] := name[i]; INC(i); INC(j) END;
        opt[j] := 0X
      ELSE
        IF ~loaded THEN loaded := LoadBackend(); error := ~loaded END;
        IF ~error THEN CompileFile(name, opt, error) END
      END;
      Texts.Scan(S)
    END
  END CompileTarget;

  (** Compile for the host architecture unless /v, /m, /a or /w is given. *)
  PROCEDURE Compile*;
  BEGIN
    SetHostTarget; CompileTarget
  END Compile;

BEGIN
  Texts.OpenWriter(HW); SetHostTarget
END rcompiler.
