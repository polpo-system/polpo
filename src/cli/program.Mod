MODULE program;  (** program.Make: a static Linux program of Oberon modules, for any of polpo's ports *)

(* Make compiles the sources it is given with the compiler of the target, adds a start module of its
  own (ProgMain: it imports progstart, the program's module and Kernel, and ends with
  Kernel.Shutdown(1)), links them with the linker of the target and removes the start module
  again. The linkers take the modules the program imports from obj/<arch>/ of the current
  directory, then from the root's. The program needs no polpo tree to run, unless it loads modules
  or reads files of the tree (fonts, Oberon.Text). *)

IMPORT SYSTEM, Kernel, Linux0, Files, Root, Texts, Oberon0, Out;

CONST
  MaxNames = 32;
  Stub = "ProgMain";

TYPE
  Name = ARRAY 256 OF CHAR;

VAR
  arch: ARRAY 8 OF CHAR;
  cap: Texts.Writer;  (* what the compilers and linkers wrote while they ran *)
  capLog: LONGINT;  (* the length of Oberon0.Log before them *)

PROCEDURE Usage;
BEGIN
  Out.String("usage: program.Make [/arch a] [/out file] [/main Module.Command] name ..."); Out.Ln;
  Out.String("  a static Linux program of the modules; program.Help tells more"); Out.Ln
END Usage;

PROCEDURE Help*;
BEGIN
  Out.String("program.Make [/arch a] [/out file] [/main Module.Command] name ..."); Out.Ln;
  Out.String("  makes a static Linux program. Each name is a source X.Mod, compiled for the"); Out.Ln;
  Out.String("  target (into obj/<arch>/ of the current directory), or a compiled module."); Out.Ln;
  Out.String("  The last module is the program: its body runs when the program starts, after"); Out.Ln;
  Out.String("  the bodies of the modules it imports, and the program ends after it."); Out.Ln;
  Out.String("  /main Module.Command  the program then calls the command, with the program's"); Out.Ln;
  Out.String("                        arguments as its parameters (as loksh Module.Command)"); Out.Ln;
  Out.String("  /out file             the program's file; the module's name without it"); Out.Ln;
  Out.String("  /arch a               x86, arm, armv7, riscv, mips, mipsbe, ppc or m68k;"); Out.Ln;
  Out.String("                        this machine's without it"); Out.Ln;
  Out.String("  A trap in the program is shown on the standard error; the exit status is then 2."); Out.Ln;
  Out.Ln;
  Out.String("examples:"); Out.Ln;
  Out.String("  program.Make hello.Mod                      the program hello of module hello"); Out.Ln;
  Out.String("  program.Make /main fs.Ls /out ls            ls as a program of its own"); Out.Ln;
  Out.String("  program.Make /arch riscv /out hello.rv hello.Mod"); Out.Ln
END Help;

PROCEDURE Append(VAR s: ARRAY OF CHAR; t: ARRAY OF CHAR);
VAR i, j: LONGINT;
BEGIN
  i := 0; WHILE s[i] # 0X DO INC(i) END;
  j := 0; WHILE (t[j] # 0X) & (i < LEN(s) - 1) DO s[i] := t[j]; INC(i); INC(j) END;
  s[i] := 0X
END Append;

PROCEDURE Ends(VAR s: ARRAY OF CHAR; t: ARRAY OF CHAR): BOOLEAN;
VAR i, j: LONGINT;
BEGIN
  i := 0; WHILE s[i] # 0X DO INC(i) END;
  j := 0; WHILE t[j] # 0X DO INC(j) END;
  IF j > i THEN RETURN FALSE END;
  WHILE (j > 0) & (s[i-1] = t[j-1]) DO DEC(i); DEC(j) END;
  RETURN j = 0
END Ends;

PROCEDURE HostArch(VAR a: ARRAY OF CHAR);
BEGIN
  IF Linux0.ARCH = "X86" THEN COPY("x86", a) ELSIF Linux0.ARCH = "ARM" THEN COPY("arm", a)
  ELSIF Linux0.ARCH = "RISC-V" THEN COPY("riscv", a) ELSIF Linux0.ARCH = "MIPS" THEN COPY("mips", a)
  ELSIF Linux0.ARCH = "MIPSBE" THEN COPY("mipsbe", a) ELSIF Linux0.ARCH = "PPC" THEN COPY("ppc", a)
  ELSIF Linux0.ARCH = "M68K" THEN COPY("m68k", a)
  ELSE COPY("armv7", a)
  END
END HostArch;

PROCEDURE Known(VAR a: ARRAY OF CHAR): BOOLEAN;
BEGIN
  RETURN (a = "x86") OR (a = "arm") OR (a = "armv7") OR (a = "riscv") OR (a = "mips") OR (a = "mipsbe")
    OR (a = "ppc") OR (a = "m68k")
END Known;

PROCEDURE Compiler(VAR cmd: ARRAY OF CHAR);
BEGIN
  IF arch = "x86" THEN COPY("compiler.Compile", cmd) ELSIF arch = "arm" THEN COPY("acompiler.Compile", cmd)
  ELSIF arch = "armv7" THEN COPY("a7compiler.Compile", cmd) ELSIF arch = "riscv" THEN COPY("rvcompiler.Compile", cmd)
  ELSIF arch = "mips" THEN COPY("mcompiler.Compile", cmd) ELSIF arch = "mipsbe" THEN COPY("mbcompiler.Compile", cmd)
  ELSIF arch = "ppc" THEN COPY("pcompiler.Compile", cmd) ELSE COPY("kcompiler.Compile", cmd)
  END
END Compiler;

(* the option of rlinker for arch *)
PROCEDURE RTarget(VAR opt: ARRAY OF CHAR);
BEGIN
  IF arch = "armv7" THEN COPY("/a", opt) ELSIF arch = "riscv" THEN COPY("/v", opt)
  ELSIF arch = "mips" THEN COPY("/m", opt) ELSIF arch = "mipsbe" THEN COPY("/b", opt)
  ELSIF arch = "ppc" THEN COPY("/w", opt) ELSE COPY("/k", opt)
  END
END RTarget;

PROCEDURE Exists(name: ARRAY OF CHAR): BOOLEAN;
VAR full: Name; flags: SET;
BEGIN RETURN Files.Exists(name, full, flags)
END Exists;

(* the object directory of arch in the current directory: "obj/<arch>/" *)
PROCEDURE LocalObj(VAR dir: ARRAY OF CHAR);
BEGIN COPY("obj/", dir); Append(dir, arch); Append(dir, "/")
END LocalObj;

(* the object file name for module m, without ".Obj", for the x86 linker: in obj/x86/ of the
  current directory, else in the root's *)
PROCEDURE ObjPath(m: ARRAY OF CHAR; VAR path: ARRAY OF CHAR);
VAR obj: Name;
BEGIN
  LocalObj(path); Append(path, m); COPY(path, obj); Append(obj, ".Obj");
  IF ~Exists(obj) THEN Root.RootObj(arch, path); Append(path, m) END
END ObjPath;

(* the name of the module in the source file: the name after MODULE *)
PROCEDURE ModuleName(file: ARRAY OF CHAR; VAR m: ARRAY OF CHAR): BOOLEAN;
VAR T: Texts.Text; S: Texts.Scanner; n: INTEGER;
BEGIN
  m[0] := 0X;
  IF Files.Old(file) = NIL THEN RETURN FALSE END;
  NEW(T); Texts.Open(T, file); Texts.OpenScanner(S, T, 0); Texts.Scan(S); n := 0;
  WHILE ~S.eot & ~((S.class = Texts.Name) & (S.s = "MODULE")) & (n < 1000) DO Texts.Scan(S); INC(n) END;
  IF (S.class = Texts.Name) & (S.s = "MODULE") THEN
    Texts.Scan(S);
    IF S.class = Texts.Name THEN COPY(S.s, m) END
  END;
  RETURN m[0] # 0X
END ModuleName;

PROCEDURE Capture(VAR s: ARRAY OF CHAR; len: LONGINT);
VAR i: LONGINT;
BEGIN i := 0; WHILE i < len DO Texts.Write(cap, s[i]); INC(i) END
END Capture;

(* what the compilers and linkers wrote, after they failed *)
PROCEDURE ShowCaptured;
VAR T: Texts.Text; R: Texts.Reader; ch: CHAR;
BEGIN
  IF (Oberon0.Log # NIL) & (Oberon0.Log.len > capLog) THEN
    Texts.OpenReader(R, Oberon0.Log, capLog); Texts.Read(R, ch);
    WHILE ~R.eot DO IF ch = 0DX THEN Out.Ln ELSE Out.Char(ch) END; Texts.Read(R, ch) END;
    Out.Ln
  END;
  NEW(T); Texts.Open(T, ""); Texts.Append(T, cap.buf);
  Texts.OpenReader(R, T, 0); Texts.Read(R, ch);
  WHILE ~R.eot DO IF ch = 0DX THEN Out.Ln ELSE Out.Char(ch) END; Texts.Read(R, ch) END
END ShowCaptured;

(* run "cmd args" with its output captured *)
PROCEDURE Run(cmd, args: ARRAY OF CHAR): BOOLEAN;
VAR par: Oberon0.ParList; W: Texts.Writer; old: Out.Writer; res: INTEGER;
BEGIN
  Texts.OpenWriter(W); Texts.WriteString(W, args); Texts.WriteString(W, " ~");
  NEW(par); NEW(par.text); Texts.Open(par.text, ""); Texts.Append(par.text, W.buf); par.pos := 0;
  old := Out.writer; Out.writer := Capture;
  Oberon0.Call(cmd, par, FALSE, res);
  Out.writer := old;
  IF res # 0 THEN Out.String("program: cannot run "); Out.String(cmd); Out.Ln END;
  RETURN res = 0
END Run;

PROCEDURE Delete(name: ARRAY OF CHAR);
VAR res: INTEGER;
BEGIN IF Exists(name) THEN Files.Delete(name, res) END
END Delete;

(* compile file into obj/<arch>/ of the current directory; m is its module *)
PROCEDURE Compile(file: ARRAY OF CHAR; VAR m: ARRAY OF CHAR): BOOLEAN;
VAR cmd: ARRAY 32 OF CHAR; args, obj: Name;
BEGIN
  IF ~ModuleName(file, m) THEN Out.String("program: no module in "); Out.String(file); Out.Ln; RETURN FALSE END;
  LocalObj(obj); Append(obj, m); Append(obj, ".Obj"); Delete(obj);
  Compiler(cmd); args := "/s "; Append(args, file);
  IF ~Run(cmd, args) OR ~Exists(obj) THEN
    ShowCaptured; Out.String("program: "); Out.String(file); Out.String(" did not compile"); Out.Ln;
    RETURN FALSE
  END;
  RETURN TRUE
END Compile;

PROCEDURE Line(VAR R: Files.Rider; s: ARRAY OF CHAR);  (* an apostrophe is written as a quote mark *)
VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE s[i] # 0X DO
    IF s[i] = "'" THEN Files.Write(R, 22X) ELSE Files.Write(R, s[i]) END;
    INC(i)
  END;
  Files.Write(R, 0AX)
END Line;

(* the source of the start module, in file: the program is the body of main, or the command cmd
  (Module.Command) called with the program's arguments *)
PROCEDURE WriteStub(file, main, cmd: ARRAY OF CHAR);
VAR f: Files.File; R: Files.Rider; s: Name; i: LONGINT; cmdMod: Name;
BEGIN
  f := Files.New(file); Files.Set(R, f, 0);
  Line(R, "MODULE ProgMain;");
  s := "IMPORT progstart, Kernel";
  IF cmd # "" THEN
    Append(s, ", Texts0, Oberon0");
    i := 0; WHILE (cmd[i] # 0X) & (cmd[i] # ".") DO cmdMod[i] := cmd[i]; INC(i) END; cmdMod[i] := 0X;
    IF (main # "") & (main # cmdMod) THEN Append(s, ", "); Append(s, main) END;
    Append(s, ", "); Append(s, cmdMod)
  ELSE Append(s, ", "); Append(s, main)
  END;
  Append(s, ";"); Line(R, s);
  IF cmd # "" THEN
    Line(R, "VAR W: Texts0.Writer; arg: ARRAY 256 OF CHAR; i: LONGINT; par: Oberon0.ParList;");
    Line(R, "BEGIN");
    Line(R, "  Texts0.OpenWriter(W); i := 1;");
    Line(R, "  WHILE i < Kernel.NoOfArgs DO");
    Line(R, "    Kernel.GetArg(i, arg); Texts0.WriteString(W, arg);");
    Line(R, "    IF i < Kernel.NoOfArgs - 1 THEN Texts0.Write(W, 20X) END;");
    Line(R, "    INC(i)");
    Line(R, "  END;");
    Line(R, "  NEW(par); NEW(par.text); Texts0.Open(par.text, ''); Texts0.Append(par.text, W.buf); par.pos := 0;");
    Line(R, "  Oberon0.Par := par;");
    s := "  "; Append(s, cmd); Append(s, ";"); Line(R, s)
  ELSE Line(R, "BEGIN")
  END;
  Line(R, "  Kernel.Shutdown(1)");
  Line(R, "END ProgMain.");
  Files.Register(f)
END WriteStub;

PROCEDURE Link(out: ARRAY OF CHAR): BOOLEAN;
VAR args, p: Name; opt: ARRAY 4 OF CHAR; ok: BOOLEAN;
BEGIN
  Delete(out);
  IF arch = "x86" THEN
    COPY(out, args); Append(args, " /refs /integrate 8049000H ");
    ObjPath("Linux0", p); Append(args, p); Append(args, " ");
    ObjPath("Kernel", p); Append(args, p); Append(args, " ");
    LocalObj(p); Append(p, Stub); Append(args, p);
    ok := Run("linker.Link", args);
    COPY(out, p); Append(p, ".Link"); Delete(p)  (* the linker's log *)
  ELSIF arch = "arm" THEN
    args := "/q "; Append(args, out); Append(args, " "); Append(args, Stub);
    ok := Run("alinker.Link", args)
  ELSE
    RTarget(opt); COPY(opt, args); Append(args, " "); Append(args, out);
    Append(args, " Linux0 Kernel "); Append(args, Stub);
    ok := Run("rlinker.Link", args)
  END;
  IF ~ok OR ~Exists(out) THEN ShowCaptured; Out.String("program: "); Out.String(out); Out.String(" was not linked"); Out.Ln; RETURN FALSE END;
  RETURN TRUE
END Link;

(* the size of the file; read with Linux0: Files.Old would map it for writing, and a file open for writing
  cannot be run while it is *)
PROCEDURE Size(name: ARRAY OF CHAR): LONGINT;
VAR fd, n, len: LONGINT; buf: ARRAY 4096 OF CHAR;
BEGIN
  len := 0; fd := Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR(name[0]), Linux0.ORDonly, 0);
  IF fd < 0 THEN RETURN -1 END;
  REPEAT n := Linux0.Read0(fd, SYSTEM.ADR(buf[0]), LEN(buf)); IF n > 0 THEN INC(len, n) END UNTIL n <= 0;
  n := Linux0.Close0(fd);
  RETURN len
END Size;

PROCEDURE Make*;
VAR A: Texts.Reader; s, out, main, cmd, m, dir, stubMod, stubObj, stubSym: Name;
  names: ARRAY MaxNames OF Name; n, i, res: INTEGER; ok, madeObj, madeDir, sources: BOOLEAN; len: LONGINT;
BEGIN
  HostArch(arch); out := ""; cmd := ""; n := 0; ok := TRUE;
  Texts.OpenArgs(A);
  WHILE ok & Texts.Arg(A, s) DO
    IF s = "/arch" THEN ok := Texts.Arg(A, arch)
    ELSIF s = "/out" THEN ok := Texts.Arg(A, out)
    ELSIF s = "/main" THEN ok := Texts.Arg(A, cmd)
    ELSIF s[0] = "/" THEN Out.String("program: unknown option "); Out.String(s); Out.Ln; RETURN
    ELSIF n < MaxNames THEN COPY(s, names[n]); INC(n)
    ELSE Out.String("program: more than 32 names"); Out.Ln; RETURN
    END
  END;
  IF ~ok OR (n = 0) & (cmd = "") THEN Usage; RETURN END;
  IF ~Known(arch) THEN Out.String("program: no port "); Out.String(arch); Out.Ln; RETURN END;
  i := 0; WHILE (cmd[i] # 0X) & (cmd[i] # ".") DO INC(i) END;
  IF (cmd # "") & (cmd[i] = 0X) THEN Out.String("program: /main takes Module.Command"); Out.Ln; RETURN END;

  (* obj/<arch>/ of the current directory, for the objects of the sources and of the start module *)
  madeObj := FALSE; madeDir := FALSE;
  IF ~Exists("obj") THEN Files.CreateDirectory("obj", res); madeObj := TRUE END;
  dir := "obj/"; Append(dir, arch);
  IF ~Exists(dir) THEN Files.CreateDirectory(dir, res); madeDir := TRUE END;
  IF ~Exists(dir) THEN Out.String("program: cannot make "); Out.String(dir); Out.Ln; RETURN END;

  Texts.OpenWriter(cap);
  IF Oberon0.Log # NIL THEN capLog := Oberon0.Log.len ELSE capLog := 0 END;
  main := ""; i := 0; sources := FALSE;
  WHILE ok & (i < n) DO
    IF Ends(names[i], ".Mod") THEN ok := Compile(names[i], m); sources := TRUE ELSE COPY(names[i], m) END;
    COPY(m, main); INC(i)
  END;
  IF ok THEN
    IF out = "" THEN
      IF main # "" THEN COPY(main, out)
      ELSE i := 0; WHILE cmd[i] # "." DO out[i] := cmd[i]; INC(i) END; out[i] := 0X
      END
    END;
    LocalObj(stubMod); Append(stubMod, Stub); COPY(stubMod, stubObj); COPY(stubMod, stubSym);
    Append(stubMod, ".Mod"); Append(stubObj, ".Obj"); Append(stubSym, ".Sym");
    WriteStub(stubMod, main, cmd);
    ok := Compile(stubMod, m) & Link(out);
    Delete(stubMod); Delete(stubObj); Delete(stubSym)
  END;
  (* the directories made here stay when they hold the objects of the sources *)
  IF madeDir & (~ok OR ~sources) THEN Files.RemoveDirectory(dir, FALSE, res) END;
  IF madeObj & (~ok OR ~sources) THEN Files.RemoveDirectory("obj", FALSE, res) END;
  IF ok THEN
    len := Size(out);
    Out.String("program: "); Out.String(out); Out.String(" ("); Out.String(arch);
    IF len >= 0 THEN Out.String(", "); Out.Int(len, 0); Out.String(" bytes") END;
    Out.String(")"); Out.Ln
  END
END Make;

END program.
