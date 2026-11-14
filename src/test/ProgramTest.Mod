MODULE ProgramTest;  (* program.Make: programs made of a body, of a command, with a trap, run with fork
  and execve; on x86 also the ELF headers of the programs for the other ports. Run it in a scratch
  directory: it writes zq_* sources, programs, the directory zq_run and obj/<arch>/. *)

IMPORT SYSTEM, Kernel, Linux0, Files, Texts, Oberon0, Out;

TYPE
  Name = ARRAY 64 OF CHAR;

VAR
  checks, fails: LONGINT;
  host: ARRAY 8 OF CHAR;

PROCEDURE Check(what: ARRAY OF CHAR; ok: BOOLEAN);
BEGIN
  INC(checks);
  IF ~ok THEN INC(fails); Out.String("FAIL "); Out.String(what); Out.String(" (case "); Out.Int(checks, 0); Out.String(")"); Out.Ln END
END Check;

PROCEDURE Append(VAR s: ARRAY OF CHAR; t: ARRAY OF CHAR);
VAR i, j: LONGINT;
BEGIN
  i := 0; WHILE s[i] # 0X DO INC(i) END;
  j := 0; WHILE (t[j] # 0X) & (i < LEN(s) - 1) DO s[i] := t[j]; INC(i); INC(j) END;
  s[i] := 0X
END Append;

(* a source file of lines; an apostrophe is written as a quote mark *)
PROCEDURE Source(name: ARRAY OF CHAR; a, b, c, d, e: ARRAY OF CHAR);
VAR f: Files.File; R: Files.Rider;

  PROCEDURE Line(s: ARRAY OF CHAR);
  VAR i: LONGINT;
  BEGIN
    i := 0;
    WHILE s[i] # 0X DO
      IF s[i] = "'" THEN Files.Write(R, 22X) ELSE Files.Write(R, s[i]) END;
      INC(i)
    END;
    IF i > 0 THEN Files.Write(R, 0AX) END
  END Line;

BEGIN
  f := Files.New(name); Files.Set(R, f, 0);
  Line(a); Line(b); Line(c); Line(d); Line(e);
  Files.Register(f)
END Source;

PROCEDURE Make(args: ARRAY OF CHAR): BOOLEAN;
VAR par: Oberon0.ParList; W: Texts.Writer; res: INTEGER;
BEGIN
  Texts.OpenWriter(W); Texts.WriteString(W, args); Texts.WriteString(W, " ~");
  NEW(par); NEW(par.text); Texts.Open(par.text, ""); Texts.Append(par.text, W.buf); par.pos := 0;
  Oberon0.Call("program.Make", par, FALSE, res);
  RETURN res = 0
END Make;

(* the exit status of the program file run in the directory zq_run with the arguments a1 and a2
  ("" for none); -1 when it could not be started *)
PROCEDURE Exec(file, a1, a2: ARRAY OF CHAR): LONGINT;
VAR pid, r, st: LONGINT; path, dir, s1, s2: Name; argv: ARRAY 4 OF LONGINT; envp: ARRAY 1 OF LONGINT;
BEGIN
  path := "../"; Append(path, file); dir := "zq_run"; COPY(a1, s1); COPY(a2, s2);
  argv[0] := SYSTEM.ADR(path); argv[1] := 0; argv[2] := 0; argv[3] := 0;
  IF s1 # "" THEN argv[1] := SYSTEM.ADR(s1); IF s2 # "" THEN argv[2] := SYSTEM.ADR(s2) END END;
  envp[0] := 0;
  pid := Linux0.Fork0();
  IF pid = 0 THEN
    r := Linux0.ChDir0(SYSTEM.ADR(dir));
    r := Linux0.Execve0(SYSTEM.ADR(path), SYSTEM.ADR(argv), SYSTEM.ADR(envp));
    Linux0.Exit0(99)
  END;
  st := 0; r := Linux0.Waitpid0(pid, SYSTEM.ADR(st), 0);
  IF r # pid THEN RETURN -1 END;
  IF st MOD 128 # 0 THEN RETURN -1000 - st MOD 128 END;  (* a signal *)
  st := st DIV 256 MOD 256;
  IF st = 99 THEN RETURN -1 END;
  RETURN st
END Exec;

PROCEDURE Exists(name: ARRAY OF CHAR): BOOLEAN;
VAR full: Name; flags: SET;
BEGIN RETURN Files.Exists(name, full, flags)
END Exists;

(* the file is an executable ELF file of arch: its byte order and machine *)
PROCEDURE ELF(file, arch: ARRAY OF CHAR): BOOLEAN;
VAR fd, n: LONGINT; path: Name; b: ARRAY 20 OF CHAR; machine, want: LONGINT; big: BOOLEAN;
BEGIN  (* read with Linux0: Files.Old would map the file for writing, and then it cannot be run *)
  COPY(file, path); fd := Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR(path[0]), Linux0.ORDonly, 0);
  IF fd < 0 THEN RETURN FALSE END;
  n := Linux0.Read0(fd, SYSTEM.ADR(b[0]), 20); fd := Linux0.Close0(fd);
  IF n # 20 THEN RETURN FALSE END;
  IF (b[0] # 7FX) OR (b[1] # "E") OR (b[2] # "L") OR (b[3] # "F") OR (b[4] # 1X) THEN RETURN FALSE END;
  big := (arch = "mipsbe") OR (arch = "ppc") OR (arch = "m68k");
  IF big THEN machine := ORD(b[18]) * 256 + ORD(b[19]) ELSE machine := ORD(b[19]) * 256 + ORD(b[18]) END;
  IF arch = "x86" THEN want := 3 ELSIF (arch = "arm") OR (arch = "armv7") THEN want := 40
  ELSIF arch = "riscv" THEN want := 243 ELSIF (arch = "mips") OR (arch = "mipsbe") THEN want := 8
  ELSIF arch = "ppc" THEN want := 20 ELSE want := 4
  END;
  RETURN (big = (b[5] = 2X)) & (machine = want) & (ORD(b[16]) + ORD(b[17]) = 2)  (* ET_EXEC *)
END ELF;

PROCEDURE Delete(name: ARRAY OF CHAR);
VAR res: INTEGER;
BEGIN IF Exists(name) THEN Files.Delete(name, res) END
END Delete;

PROCEDURE Run*;
VAR st: LONGINT; i, res: INTEGER; arch, out, args: Name; archs: ARRAY 8 OF Name;
BEGIN
  checks := 0; fails := 0;
  IF Linux0.ARCH = "X86" THEN host := "x86" ELSIF Linux0.ARCH = "ARM" THEN host := "arm"
  ELSIF Linux0.ARCH = "RISC-V" THEN host := "riscv" ELSIF Linux0.ARCH = "MIPS" THEN host := "mips"
  ELSIF Linux0.ARCH = "MIPSBE" THEN host := "mipsbe" ELSIF Linux0.ARCH = "PPC" THEN host := "ppc"
  ELSIF Linux0.ARCH = "M68K" THEN host := "m68k" ELSE host := "armv7"
  END;
  Source("zq_proga.Mod", "MODULE ZqProgA; IMPORT Kernel, Files; VAR f: Files.File; R: Files.Rider;",
    "BEGIN f := Files.New('zq_proga.out'); Files.Set(R, f, 0); Files.Write(R, 'k'); Files.Register(f);",
    "  IF Kernel.NoOfArgs = 3 THEN Kernel.Shutdown(42) ELSE Kernel.Shutdown(43) END", "END ZqProgA.", "");
  Source("zq_progb.Mod", "MODULE ZqProgB; IMPORT Out;", "BEGIN Out.String('') END ZqProgB.", "", "", "");
  Source("zq_progc.Mod", "MODULE ZqProgC; IMPORT Kernel, Texts;",
    "PROCEDURE Run*; VAR A: Texts.Reader; s: ARRAY 32 OF CHAR;",
    "BEGIN Texts.OpenArgs(A); IF Texts.Arg(A, s) & (s = 'seven') THEN Kernel.Shutdown(7) ELSE Kernel.Shutdown(8) END",
    "END Run;", "END ZqProgC.");
  Source("zq_progd.Mod", "MODULE ZqProgD; VAR a: ARRAY 4 OF INTEGER; i: INTEGER;",
    "BEGIN i := 5; a[i] := 1", "END ZqProgD.", "", "");

  (* programs of this machine, run in zq_run *)
  IF ~Exists("zq_run") THEN Files.CreateDirectory("zq_run", res) END;
  Delete("zq_run/zq_proga.out"); Delete("zq_run/Kernel.Log");
  Check("program.Make runs", Make("/out zq_proga zq_proga.Mod"));
  Check("the body program", Exists("zq_proga") & ELF("zq_proga", host));
  st := Exec("zq_proga", "one", "two");
  IF st = -1 THEN
    Out.String("ProgramTest: programs of "); Out.String(host); Out.String(" cannot be started here, not run"); Out.Ln
  ELSE
    Check("its exit status from Kernel.Shutdown and its arguments", st = 42);
    Check("the file it wrote", Exists("zq_run/zq_proga.out"));
    Check("no Kernel.Log", ~Exists("zq_run/Kernel.Log"));
    Check("one argument fewer", Exec("zq_proga", "one", "") = 43);
    Check("a body that ends: status 0", Make("/out zq_progb zq_progb.Mod") & (Exec("zq_progb", "", "") = 0));
    Check("a command with the program's arguments",
      Make("/main ZqProgC.Run /out zq_progc zq_progc.Mod") & (Exec("zq_progc", "seven", "") = 7) & (Exec("zq_progc", "six", "") = 8));
    Check("a trap: status 2", Make("/out zq_progd zq_progd.Mod") & (Exec("zq_progd", "", "") = 2))
  END;

  (* programs of the other ports, made with the cross compilers of x86 *)
  IF host = "x86" THEN
    archs[0] := "arm"; archs[1] := "armv7"; archs[2] := "riscv"; archs[3] := "mips";
    archs[4] := "mipsbe"; archs[5] := "ppc"; archs[6] := "m68k";
    i := 0;
    WHILE i < 7 DO
      arch := archs[i]; out := "zq_proga."; Append(out, arch);
      args := "/arch "; Append(args, arch); Append(args, " /out "); Append(args, out); Append(args, " zq_proga.Mod");
      Delete(out);
      Check(arch, Make(args) & ELF(out, arch));
      INC(i)
    END
  END;
  Out.String("ProgramTest: "); Out.Int(checks, 0); Out.String(" checks, "); Out.Int(fails, 0); Out.String(" failed"); Out.Ln
END Run;

END ProgramTest.
