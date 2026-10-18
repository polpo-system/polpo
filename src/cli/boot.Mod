MODULE boot;  (** loksh as the first process of a Linux system *)

(** boot.Init [command] ~ is meant for a kernel started with loksh as its init program, as in the
  kernel command line  rdinit=/polpo/bin/x86/loksh -- boot.Init . It does what the first process of
  a Linux system must do before anything else runs:
    - mounts /proc, /sys, /dev (devtmpfs) and /tmp (tmpfs), making the directories when needed;
    - takes /dev/tty1 as its console and controlling terminal (the keyboard of the desktop);
    - loads the kernel modules listed in the file boot.modules of the polpo directory, one path
      per line, relative to the polpo directory or absolute; # starts a comment;
    - runs the command, System.Init (the desktop) when none is given.
  The first process must never end: when the command ends, or the desktop quits (System.Quit),
  boot syncs the disks and powers the machine off. *)

IMPORT SYSTEM, Linux0, Kernel, Files, Root, Oberon0, texts, out;

CONST
  MagicA = -18751827;  (* LINUX_REBOOT_MAGIC1, 0FEE1DEADH *)
  MagicB = 672274793;  (* LINUX_REBOOT_MAGIC2, 28121969H *)
  PowerOff = 4321FEDCH;  (* LINUX_REBOOT_CMD_POWER_OFF *)

VAR
  first: BOOLEAN;  (* Init ran: the machine goes off at the end *)

PROCEDURE Mount(src, dir, type: ARRAY OF CHAR);
VAR res: LONGINT; r: INTEGER;
BEGIN
  Files.CreateDirectory(dir, r);
  res := Linux0.Mount0(SYSTEM.ADR(src), SYSTEM.ADR(dir), SYSTEM.ADR(type), 0, 0);
  IF (res < 0) & (res # -16) THEN  (* -16: mounted already *)
    out.String("boot: mounting "); out.String(dir); out.String(" failed, error "); out.Int(-res, 0); out.Ln
  END
END Mount;

PROCEDURE Console;  (* /dev/tty1 as standard input, output and error, and controlling terminal *)
VAR fd, res, ctty: LONGINT;
BEGIN
  res := Linux0.Close0(0); res := Linux0.Close0(1); res := Linux0.Close0(2);
  res := Linux0.Setsid0();
  fd := Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR("/dev/tty1"), Linux0.ORDWR, 0);  (* 0 *)
  res := Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR("/dev/tty1"), Linux0.ORDWR, 0);  (* 1 *)
  res := Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR("/dev/tty1"), Linux0.ORDWR, 0);  (* 2 *)
  IF (Linux0.ARCH = "MIPS") OR (Linux0.ARCH = "MIPSBE") THEN ctty := 5480H ELSE ctty := 540EH END;  (* TIOCSCTTY *)
  IF fd >= 0 THEN res := Linux0.IOCtl0(fd, ctty, 0) END
END Console;

PROCEDURE Load(VAR path: ARRAY OF CHAR);  (* one kernel module *)
VAR full: ARRAY 256 OF CHAR; fd, res: LONGINT;
BEGIN
  IF path[0] = "/" THEN COPY(path, full) ELSE Root.Join(path, full) END;
  out.String("boot: module "); out.String(full);
  fd := Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR(full), 0, 0);
  IF fd < 0 THEN out.String(" not found")
  ELSE
    res := Linux0.FinitModule0(fd, SYSTEM.ADR(""), 0);
    IF (res < 0) & (res # -17) THEN out.String(" failed, error "); out.Int(-res, 0) END;  (* -17: loaded already *)
    res := Linux0.Close0(fd)
  END;
  out.Ln
END Load;

PROCEDURE Modules;  (* the modules of boot.modules *)
VAR f: Files.File; R: Files.Rider; line: ARRAY 256 OF CHAR; ch: CHAR; i: INTEGER;
BEGIN
  f := Files.Old("boot.modules");
  IF f # NIL THEN
    Files.Set(R, f, 0); Files.Read(R, ch);
    WHILE ~R.eof DO
      i := 0;
      WHILE ~R.eof & (ch # 0AX) & (ch # 0DX) DO
        IF i < LEN(line) - 1 THEN line[i] := ch; INC(i) END;
        Files.Read(R, ch)
      END;
      WHILE (i > 0) & (line[i-1] <= " ") DO DEC(i) END;
      line[i] := 0X;
      IF (i > 0) & (line[0] # "#") THEN Load(line) END;
      Files.Read(R, ch)
    END;
    Files.Close(f)
  END
END Modules;

PROCEDURE Off;  (* the termination handler: the first process does not end, the machine goes off *)
VAR res: LONGINT;
BEGIN
  IF first THEN
    res := Linux0.Sync0();
    res := Linux0.Reboot0(MagicA, MagicB, PowerOff, 0)
  END
END Off;

(** boot.Init [command] ~  set up the system as its first process, then run the command
  (System.Init when none is given); see the comment at the top *)
PROCEDURE Init*;
VAR A: texts.Reader; cmd: ARRAY 64 OF CHAR; par: Oberon0.ParList; res: INTEGER;
BEGIN
  texts.OpenArgs(A);
  IF ~texts.Arg(A, cmd) THEN cmd := "System.Init" END;
  Mount("proc", "/proc", "proc"); Mount("sysfs", "/sys", "sysfs");
  Mount("devtmpfs", "/dev", "devtmpfs"); Mount("tmpfs", "/tmp", "tmpfs");
  Console;
  out.String("boot: polpo as the first process, then "); out.String(cmd); out.Ln;
  Modules;
  first := TRUE; Kernel.InstallTermHandler(Off);
  NEW(par); NEW(par.text); texts.Open(par.text, ""); par.pos := 0;
  Oberon0.Call(cmd, par, FALSE, res);
  IF res # 0 THEN out.String("boot: "); out.String(cmd); out.String(" not found, error "); out.Int(res, 0); out.Ln END;
  Kernel.Shutdown(1)
END Init;

BEGIN
  first := FALSE
END boot.
