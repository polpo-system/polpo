MODULE termios;

IMPORT Kernel, Linux0, SYSTEM;

CONST
  (* ioctl request codes *)
  TCGETS*  = 5401H;  (* read current terminal settings  — tcgetattr(3) *)
  TCSETS*  = 5402H;  (* write settings immediately      — tcsetattr TCSANOW *)
  TCSETSW* = 5403H;  (* write after draining output     — TCSADRAIN *)
  TCSETSF* = 5404H;  (* write after flushing input      — TCSAFLUSH *)

  (* c_lflag bit numbers — use with INCL / EXCL on Termios.lflag *)
  ISIG*   = 0;   (* generate signals for Ctrl+C, Ctrl+Z *)
  ICANON* = 1;   (* canonical (line-buffered) input mode *)
  ECHO*   = 3;   (* echo input characters back to terminal *)
  ECHOE*  = 4;   (* echo erase as backspace-space-backspace *)
  ECHOK*  = 5;   (* echo newline after kill character *)
  IEXTEN* = 15;  (* enable implementation-defined input processing *)

  (* c_cc array indices *)
  VINTR*  = 0;   (* interrupt character (Ctrl+C) *)
  VQUIT*  = 1;   (* quit character (Ctrl+\) *)
  VERASE* = 2;   (* erase character (Backspace / Del) *)
  VKILL*  = 3;   (* kill-line character (Ctrl+U) *)
  VEOF*   = 4;   (* end-of-file character (Ctrl+D) *)
  VTIME*  = 5;   (* read timeout in tenths of a second (0 = none) *)
  VMIN*   = 6;   (* minimum characters before read returns *)
  VSTART* = 8;   (* XON resume character (Ctrl+Q) *)
  VSTOP*  = 9;   (* XOFF pause character (Ctrl+S) *)
  VSUSP*  = 10;  (* suspend character (Ctrl+Z) *)

TYPE
  (* Maps directly onto Linux struct termios (36 bytes total):
       4 × SET  (iflag/oflag/cflag/lflag, each 4 bytes)
       1 × CHAR (line discipline, 1 byte)
      19 × CHAR (c_cc control characters, 19 bytes)            *)
  Termios* = RECORD
    iflag*, oflag*, cflag*, lflag*: SET;
    line*: CHAR;
    cc*: ARRAY 19 OF CHAR;
    ccMips: ARRAY 12 OF CHAR  (* polpo: MIPS has 23 control characters, room for the kernel *)
  END;

VAR
  savedTerminal: Termios;
  cbreak: BOOLEAN;
  (* polpo: MIPS and PowerPC number ioctls, VMIN/VTIME and some flags differently *)
  getReq, setReq, winReq, vmin, vtime, iexten, icanon, ixon: LONGINT;
  isig*: LONGINT;  (** the bit of ISIG in lflag on this machine *)

(* Read terminal settings for file descriptor fd into t.
   Returns 0 on success, negative errno on failure. *)
PROCEDURE Get*(fd: LONGINT; VAR t: Termios): LONGINT;
BEGIN RETURN Linux0.IOCtl0(fd, getReq, SYSTEM.ADR(t))
END Get;

(* Write terminal settings for file descriptor fd from t (takes effect immediately).
   Returns 0 on success, negative errno on failure. *)
PROCEDURE Set*(fd: LONGINT; VAR t: Termios): LONGINT;
BEGIN RETURN Linux0.IOCtl0(fd, setReq, SYSTEM.ADR(t))
END Set;

(* Kernel.Shutdown also invokes this after signals and traps. *)
PROCEDURE Restore;
VAR r: LONGINT;
BEGIN
  IF cbreak THEN
    r := Set(0, savedTerminal); cbreak := FALSE
  END
END Restore;

(* Switch fd to cbreak mode: characters delivered one at a time, no echo.
   ISIG (Ctrl+C / Ctrl+Z) is preserved.
   Saves the original settings in 'saved'; call Leave to restore.
   Returns 0 on success, negative errno on failure. *)
PROCEDURE EnterCbreak*(fd: LONGINT; VAR saved: Termios): LONGINT;
VAR t: Termios; r: LONGINT;
BEGIN
  r := Get(fd, saved);
  IF r = 0 THEN
    t := saved;
    EXCL(t.lflag, icanon);  (* no line buffering *)
    EXCL(t.lflag, ECHO);    (* no automatic echo *)
    t.cc[vmin]  := 1X;      (* return after every character *)
    t.cc[vtime] := 0X;      (* no read timeout *)
    r := Set(fd, t);
    IF r = 0 THEN
      savedTerminal := saved; cbreak := TRUE;
      Kernel.InstallTermHandler(Restore)
    END
  END;
  RETURN r
END EnterCbreak;

(* Restore terminal settings previously saved by EnterCbreak.
   Returns 0 on success, negative errno on failure. *)
PROCEDURE Leave*(fd: LONGINT; VAR saved: Termios): LONGINT;
VAR r: LONGINT;
BEGIN
  r := Set(fd, saved);
  IF r = 0 THEN cbreak := FALSE END;
  RETURN r
END Leave;

(** polpo: reads with t return what has arrived within tenths tenths of a second, maybe nothing *)
PROCEDURE Timeout*(VAR t: Termios; tenths: LONGINT);
BEGIN
  t.cc[vmin] := 0X; t.cc[vtime] := CHR(tenths)
END Timeout;

(** polpo: raw mode for full screen programs: no line buffering, echo or signals (^C, ^Z,
  ^S, ^Q, ^V are keys), Enter is CR, one character at a time *)
PROCEDURE MakeRaw*(VAR t: Termios);
BEGIN
  EXCL(t.lflag, icanon); EXCL(t.lflag, ECHO); EXCL(t.lflag, isig); EXCL(t.lflag, iexten);
  EXCL(t.iflag, ixon); EXCL(t.iflag, 8 (* ICRNL *));
  t.cc[vmin] := 1X; t.cc[vtime] := 0X
END MakeRaw;

(** polpo: the size of the terminal of fd; FALSE if unknown *)
PROCEDURE WinSize*(fd: LONGINT; VAR rows, cols: LONGINT): BOOLEAN;
VAR ws: ARRAY 4 OF INTEGER;
BEGIN
  IF (Linux0.IOCtl0(fd, winReq, SYSTEM.ADR(ws[0])) = 0) & (ws[0] > 0) & (ws[1] > 0) THEN
    rows := ws[0]; cols := ws[1]; RETURN TRUE
  END;
  RETURN FALSE
END WinSize;

BEGIN
  cbreak := FALSE;
  icanon := ICANON; isig := ISIG; ixon := 10;
  IF (Linux0.ARCH = "MIPS") OR (Linux0.ARCH = "MIPSBE") THEN
    getReq := 540DH; setReq := 540EH; winReq := 40087468H; vmin := 4; vtime := 5; iexten := 8
  ELSIF Linux0.ARCH = "PPC" THEN  (* c_cc starts at offset 16, in line: VMIN 5, VTIME 7 are cc[4], cc[6] *)
    getReq := 402C7413H; setReq := 802C7414H; winReq := 40087468H; vmin := 4; vtime := 6;
    iexten := 10; icanon := 8; isig := 7; ixon := 9
  ELSE
    getReq := TCGETS; setReq := TCSETS; winReq := 5413H; vmin := VMIN; vtime := VTIME; iexten := IEXTEN
  END
END termios.
