MODULE shell;

(** loksh — Linux Oberon Kommand Shell.
    Three modes decided at startup:
      args given  → run one command and exit  (loksh Module.Proc [params])
      no args, tty → cbreak with per-keypress echo and Tab completion
      no args, pipe → line-buffered batch mode

    Tab completion (Complete0) scans the object directories (obj/<arch>/ of the
    current directory and of the root) on every keypress: no startup cache, no
    rehash needed; it always reflects the latest compiled state. *)

IMPORT nIn := stdin, nOut := out, nTermios := termios, Kernel, Complete0,
  Modules, Oberon0, oberon, nTexts := texts, oocStrings;

CONST
  TAB = 9X;
  LF  = 0AX;
  CR  = 0DX;
  BS  = 8X;
  DEL = 7FX;
  ESC = 1BX;  (* start of VT100 escape sequence *)
  ETX = 3X;   (* Ctrl+C: cancel current line *)
  EOT = 4X;   (* Ctrl+D: exit if buffer empty *)

  MaxHist = 64;

VAR
  saved, reading, running: nTermios.Termios;  (* the terminal: at the start, reading a line, running a command *)
  entered: BOOLEAN;  (* Interactive ran before: entering it again means a command stopped *)
  (* command history *)
  hist:         ARRAY MaxHist OF ARRAY 256 OF CHAR;
  histCount:    INTEGER;   (* number of stored entries *)
  histIdx:      INTEGER;   (* browse position; -1 = not browsing *)
  histSaved:    ARRAY 256 OF CHAR;  (* line saved when browsing starts *)
  histSavedLen: INTEGER;

PROCEDURE Erase;
BEGIN nOut.Char(BS); nOut.Char(' '); nOut.Char(BS)
END Erase;

PROCEDURE CurLeft(n: INTEGER);
VAR i: INTEGER;
BEGIN i := 0; WHILE i < n DO nOut.Char(ESC); nOut.Char('['); nOut.Char('D'); INC(i) END
END CurLeft;

PROCEDURE CurRight(n: INTEGER);
VAR i: INTEGER;
BEGIN i := 0; WHILE i < n DO nOut.Char(ESC); nOut.Char('['); nOut.Char('C'); INC(i) END
END CurRight;

(* ---- Tab completion (Complete0) ------------------------------------- *)

PROCEDURE ReprintLine(VAR buf: ARRAY OF CHAR; len: INTEGER);
VAR i: INTEGER;
BEGIN
  nOut.Char(LF); nOut.String("> ");
  i := 0; WHILE i < len DO nOut.Char(buf[i]); INC(i) END
  (* caller must set cur := len after calling *)
END ReprintLine;

(* The first word is a command, the words after it file names: what all matches have in common is
   added; several matches are listed. *)
PROCEDURE TryComplete(VAR buf: ARRAY OF CHAR; VAR len: INTEGER);
VAR
  word, add: ARRAY 256 OF CHAR;
  i, start: INTEGER;
  cmd: BOOLEAN;
BEGIN
  start := 0; i := 0;
  WHILE i < len DO IF buf[i] = ' ' THEN start := i + 1 END; INC(i) END;
  cmd := TRUE; i := 0; WHILE i < start DO IF buf[i] # ' ' THEN cmd := FALSE END; INC(i) END;
  i := 0; WHILE start + i < len DO word[i] := buf[start + i]; INC(i) END; word[i] := 0X;
  IF cmd THEN Complete0.Command(word, add) ELSE Complete0.Path(word, add) END;
  i := 0;
  WHILE (add[i] # 0X) & (len < LEN(buf) - 1) DO nOut.Char(add[i]); buf[len] := add[i]; INC(len); INC(i) END;
  IF Complete0.n > 1 THEN
    nOut.Char(LF); i := 0;
    WHILE (i < Complete0.n) & (i < Complete0.MaxNames) DO nOut.String(Complete0.name[i]); nOut.Char(' '); INC(i) END;
    ReprintLine(buf, len)
  END
END TryComplete;

(* ---- command history ----------------------------------------------- *)

PROCEDURE AddHist(VAR buf: ARRAY OF CHAR; len: INTEGER);
VAR i: INTEGER;
BEGIN
  IF len = 0 THEN RETURN END;
  (* skip duplicate of most recent entry *)
  IF (histCount > 0) & oocStrings.Equal(hist[histCount - 1], buf) THEN RETURN END;
  IF histCount < MaxHist THEN
    COPY(buf, hist[histCount]); INC(histCount)
  ELSE
    i := 0; WHILE i < MaxHist - 1 DO hist[i] := hist[i + 1]; INC(i) END;
    COPY(buf, hist[MaxHist - 1])
  END
END AddHist;

PROCEDURE HistReplace(VAR buf: ARRAY OF CHAR; VAR len, cur: INTEGER; VAR src: ARRAY OF CHAR);
VAR i: INTEGER;
BEGIN
  CurRight(len - cur);  (* move terminal cursor to end before erasing *)
  WHILE len > 0 DO DEC(len); Erase END;
  COPY(src, buf);
  len := 0; WHILE buf[len] # 0X DO INC(len) END;
  i := 0; WHILE i < len DO nOut.Char(buf[i]); INC(i) END;
  cur := len
END HistReplace;

PROCEDURE HistUp(VAR buf: ARRAY OF CHAR; VAR len, cur: INTEGER);
BEGIN
  IF histCount = 0 THEN RETURN END;
  IF histIdx = -1 THEN
    COPY(buf, histSaved); histSavedLen := len;
    histIdx := histCount - 1
  ELSIF histIdx > 0 THEN
    DEC(histIdx)
  ELSE
    RETURN
  END;
  HistReplace(buf, len, cur, hist[histIdx])
END HistUp;

PROCEDURE HistDown(VAR buf: ARRAY OF CHAR; VAR len, cur: INTEGER);
BEGIN
  IF histIdx = -1 THEN RETURN END;
  IF histIdx < histCount - 1 THEN
    INC(histIdx);
    HistReplace(buf, len, cur, hist[histIdx])
  ELSE
    histIdx := -1;
    HistReplace(buf, len, cur, histSaved)
  END
END HistDown;

(* ---- cbreak input -------------------------------------------------- *)

PROCEDURE ReadLine(VAR buf: ARRAY OF CHAR; VAR len: INTEGER; VAR quit: BOOLEAN);
VAR ch: CHAR; ok: BOOLEAN; cur, i: INTEGER;
BEGIN
  len := 0; cur := 0; buf[0] := 0X; quit := FALSE; histIdx := -1;
  LOOP
    ok := nIn.ReadRaw(ch);
    IF ~ok OR (ch = EOT) THEN
      IF len = 0 THEN quit := TRUE END;
      nOut.Char(LF); EXIT
    ELSIF ch = ETX THEN
      len := 0; cur := 0; buf[0] := 0X; nOut.Char(LF); EXIT
    ELSIF (ch = CR) OR (ch = LF) THEN
      buf[len] := 0X;
      AddHist(buf, len);
      nOut.Char(LF); EXIT
    ELSIF (ch = BS) OR (ch = DEL) THEN
      IF cur > 0 THEN
        DEC(cur); DEC(len);
        i := cur; WHILE i < len DO buf[i] := buf[i+1]; INC(i) END;
        buf[len] := 0X;
        nOut.Char(BS);
        i := cur; WHILE i < len DO nOut.Char(buf[i]); INC(i) END;
        nOut.Char(' ');
        CurLeft(len - cur + 1)
      END
    ELSIF ch = TAB THEN
      buf[len] := 0X;
      CurRight(len - cur); cur := len;
      TryComplete(buf, len);
      buf[len] := 0X;
      cur := len
    ELSIF ch = ESC THEN
      ok := nIn.ReadRaw(ch);
      IF ok & (ch = '[') THEN
        ok := nIn.ReadRaw(ch);
        IF ok THEN
          IF    ch = 'A' THEN HistUp(buf, len, cur)
          ELSIF ch = 'B' THEN HistDown(buf, len, cur)
          ELSIF ch = 'C' THEN IF cur < len THEN CurRight(1); INC(cur) END
          ELSIF ch = 'D' THEN IF cur > 0  THEN CurLeft(1);  DEC(cur) END
          END
        END
      END
    ELSIF ch >= 20X THEN
      IF len < LEN(buf) - 1 THEN
        IF cur = len THEN
          buf[len] := ch; INC(len); INC(cur); nOut.Char(ch)
        ELSE
          i := len; WHILE i > cur DO buf[i] := buf[i-1]; DEC(i) END;
          buf[cur] := ch; INC(len); INC(cur);
          i := cur - 1; WHILE i < len DO nOut.Char(buf[i]); INC(i) END;
          CurLeft(len - cur)
        END;
        buf[len] := 0X
      END
    END
  END;
  buf[len] := 0X
END ReadLine;

(* ---- command execution --------------------------------------------- *)

PROCEDURE ShowModCmds(modname: ARRAY OF CHAR);
VAR
  m: Kernel.Module;
  mod: Modules.Module;
  i: INTEGER;
  help: BOOLEAN;  (* the module has a command Help *)

  PROCEDURE Find;
  BEGIN m := Kernel.modules; WHILE (m # NIL) & (m.name # modname) DO m := m.next END
  END Find;

BEGIN
  Find;
  IF m = NIL THEN mod := Modules.ThisMod(modname); Find END;  (* polpo: loaded, as a command of it would be; the object file was looked for as x86/<name>.Obj in the root *)
  IF m # NIL THEN
    nOut.String(modname); nOut.String(": no procedure specified."); nOut.Ln;
    i := 0; help := FALSE;
    WHILE i < LEN(m.cmds^) DO
      nOut.String("    "); nOut.String(modname); nOut.Char('.'); nOut.String(m.cmds[i].name); nOut.Ln;
      IF m.cmds[i].name = "Help" THEN help := TRUE END;
      INC(i)
    END;
    IF help THEN nOut.String(modname); nOut.String(".Help explains them."); nOut.Ln END
  ELSE
    nOut.String(modname); nOut.String(": module not found"); nOut.Ln
  END
END ShowModCmds;

PROCEDURE ShowCallError(cmd: ARRAY OF CHAR; res: INTEGER);
VAR modname: ARRAY 64 OF CHAR; i: INTEGER;
BEGIN
  nOut.String(Modules.resMsg); nOut.Ln;
  IF res = 5 THEN
    i := 0;
    WHILE (cmd[i] # 0X) & (cmd[i] # '.') DO modname[i] := cmd[i]; INC(i) END;
    modname[i] := 0X;
    ShowModCmds(modname)
  END
END ShowCallError;

PROCEDURE Exec(VAR buf: ARRAY OF CHAR);
VAR
  cmd, name: ARRAY 64 OF CHAR;
  params: ARRAY 256 OF CHAR;
  par: Oberon0.ParList;
  W: nTexts.Writer;
  i, j: INTEGER;
  res: INTEGER;
BEGIN
  IF (buf[0] = 0X) OR (buf[0] = '#') THEN RETURN END;
  i := 0;
  WHILE (buf[i] # 0X) & (buf[i] # ' ') DO INC(i) END;
  j := 0; WHILE j < i DO cmd[j] := buf[j]; INC(j) END; cmd[j] := 0X;
  (* no dot: show exported procedures instead of failing with error 5 *)
  j := 0; WHILE (cmd[j] # 0X) & (cmd[j] # '.') DO INC(j) END;
  IF cmd[j] = 0X THEN ShowModCmds(cmd); RETURN END;
  WHILE buf[i] = ' ' DO INC(i) END;
  j := 0; WHILE buf[i] # 0X DO params[j] := buf[i]; INC(j); INC(i) END; params[j] := 0X;
  NEW(par); NEW(par.text); nTexts.Open(par.text, ""); par.pos := 0;
  IF params[0] # 0X THEN
    nTexts.OpenWriter(W); nTexts.WriteString(W, params); nTexts.Append(par.text, W.buf)
  END;
  COPY(cmd, name);
  Oberon0.Call(name, par, FALSE, res);
  IF res # 0 THEN ShowCallError(cmd, res) END
END Exec;

PROCEDURE LineLoop;
VAR line: ARRAY 256 OF CHAR; quit: BOOLEAN;
BEGIN
  nIn.Open;
  quit := FALSE;
  WHILE ~quit DO
    nOut.String("> ");
    nIn.Line(line);
    IF ~nIn.Done THEN quit := TRUE
    ELSIF oocStrings.Equal(line, "quit") OR oocStrings.Equal(line, "exit") THEN
      quit := TRUE
    ELSE
      Exec(line)
    END
  END
END LineLoop;

(* ---- entry point --------------------------------------------------- *)


(* the interactive shell; also where the kernel goes after a trap or Ctrl+C in a command
   (Kernel.InstallLoop: a fresh stack), so the shell goes on with the next line *)
PROCEDURE Interactive;
VAR buf: ARRAY 256 OF CHAR; len: INTEGER; r: LONGINT; quit: BOOLEAN;
BEGIN
  IF entered THEN
    nOut.Ln; nOut.String("loksh: the command stopped (Ctrl+C, or a trap: Kernel.Log has the details)"); nOut.Ln;
    Oberon0.Stopped  (* the cleanups of the commands (Oberon0.OnStop) *)
  END;
  entered := TRUE; quit := FALSE;
  WHILE ~quit DO
    nOut.String("> ");
    r := nTermios.Set(0, reading);
    ReadLine(buf, len, quit);
    r := nTermios.Set(0, running);
    IF ~quit & (len > 0) THEN
      IF oocStrings.Equal(buf, "quit") OR oocStrings.Equal(buf, "exit") THEN
        quit := TRUE
      ELSE
        Exec(buf)
      END
    END
  END;
  r := nTermios.Leave(0, saved);
  Kernel.Shutdown(0)
END Interactive;

PROCEDURE Run*;
VAR
  buf: ARRAY 256 OF CHAR;
  arg: ARRAY 256 OF CHAR;
  cmd, name: ARRAY 64 OF CHAR;
  par: Oberon0.ParList;
  W: nTexts.Writer;
  len: INTEGER;
  i, firstArg: LONGINT;
  r: LONGINT;
  res: INTEGER;
  quit: BOOLEAN;
BEGIN
  firstArg := 1;
  IF Kernel.NoOfArgs > firstArg THEN
    Kernel.GetArg(firstArg, cmd);
    IF (cmd[0] = "-") & (cmd[1] = "P") THEN INC(firstArg); Kernel.GetArg(firstArg, cmd) END
  END;
  IF Kernel.NoOfArgs > firstArg THEN
    IF oocStrings.Equal(cmd, "--help") OR oocStrings.Equal(cmd, "-h") THEN
      nOut.String("loksh - Linux Oberon Kommand Shell"); nOut.Ln;
      nOut.Ln;
       nOut.String("Usage:"); nOut.Ln;
       nOut.String("  loksh                     interactive shell with Tab completion"); nOut.Ln;
       nOut.String("  loksh Module.Proc [args]  run one command and exit"); nOut.Ln;
       nOut.String("  loksh -Ppath/ Module.Proc load modules from path/"); nOut.Ln;
       nOut.String("  loksh < script            run commands from a file"); nOut.Ln;
      nOut.Ln;
      nOut.String("Interactive keys:"); nOut.Ln;
      nOut.String("  Tab     complete module name, procedure name or file name"); nOut.Ln;
      nOut.String("  Ctrl+C  cancel current line; while a command runs: stop the command"); nOut.Ln;
      nOut.String("  Ctrl+D  exit"); nOut.Ln;
      nOut.String("  quit / exit"); nOut.Ln;
       Kernel.Shutdown(0)
    ELSIF oocStrings.Equal(cmd, "shell.Run") THEN
      nOut.String("shell.Run is started automatically; omit it from the command line."); nOut.Ln;
      Kernel.Shutdown(1)
    END;
    nTexts.OpenWriter(W);
    i := firstArg + 1;
    WHILE i < Kernel.NoOfArgs DO
      Kernel.GetArg(i, arg);
      nTexts.WriteString(W, arg);
      IF i < Kernel.NoOfArgs - 1 THEN nTexts.Write(W, " ") END;
      INC(i)
    END;
    i := 0; WHILE (cmd[i] # 0X) & (cmd[i] # '.') DO INC(i) END;
    IF cmd[i] = 0X THEN ShowModCmds(cmd); Kernel.Shutdown(0) END;
    NEW(par); NEW(par.text); nTexts.Open(par.text, ""); par.pos := 0;
    nTexts.Append(par.text, W.buf);
    COPY(cmd, name);
    Oberon0.Call(name, par, FALSE, res);
    IF res # 0 THEN ShowCallError(cmd, res) END;
    Kernel.Shutdown(0)
  ELSE
    r := nTermios.EnterCbreak(0, saved);
    IF r # 0 THEN
      LineLoop;
      Kernel.Shutdown(0)
    END;
    (* reading a line: Ctrl+C is a key (cancel the line); running a command: Ctrl+C stops the
       command (a trap) and the shell goes on, as after any trap in a command *)
    r := nTermios.Get(0, running); reading := running; EXCL(reading.lflag, nTermios.isig);
    Kernel.InstallLoop(Interactive);
    Interactive
  END
END Run;

END shell.
