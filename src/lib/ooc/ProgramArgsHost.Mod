MODULE ProgramArgsHost;  (* the arguments of ProgramArgs: those of the command, from Oberon.Par (polpo) *)

(* polpo has no argv for a command: loksh Module.Command a b and Module.Command a b ~ in the
   desktop give the command its arguments in Oberon.Par. Argument 0 is the name of the command
   (the word before them in the desktop; in the console, where Oberon.Par has the arguments
   only, the second word of /proc/self/cmdline), the others are split as by texts.Arg: blanks
   between them, "..." for one with blanks, the end of the line or ~ after the last. They are
   read again when Oberon.Par changes: a module stays loaded for the next commands. voc reads
   argv. *)

IMPORT SYSTEM, Linux0, Texts := Texts0, texts, Oberon := Oberon0;

CONST MaxArgs = 64; MaxLen = 256;

TYPE Byte* = SYSTEM.BYTE;

VAR
  args: ARRAY MaxArgs OF ARRAY MaxLen OF CHAR;
  n: LONGINT;
  text: Texts.Text; pos: LONGINT;  (* the Oberon.Par the arguments are from *)

PROCEDURE Len(VAR s: ARRAY OF CHAR): LONGINT;
VAR i: LONGINT;
BEGIN i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END; RETURN i
END Len;

(* the command name: the last word before pos *)
PROCEDURE Name(t: Texts.Text; pos: LONGINT; VAR s: ARRAY OF CHAR);
VAR R: texts.Reader; ch: CHAR; buf: ARRAY MaxLen OF CHAR; from, i, k, j: LONGINT;
BEGIN
  s[0] := 0X; from := pos - (MaxLen - 1); IF from < 0 THEN from := 0 END;
  texts.OpenReader(R, t, from); i := 0;
  WHILE i < pos - from DO texts.Read(R, ch); buf[i] := ch; INC(i) END;
  WHILE (i > 0) & ((buf[i-1] = " ") OR (buf[i-1] = 09X)) DO DEC(i) END;
  k := i; WHILE (k > 0) & (buf[k-1] > " ") DO DEC(k) END;
  j := 0; WHILE k < i DO s[j] := buf[k]; INC(j); INC(k) END; s[j] := 0X
END Name;

(* argument 1 of the process (the command of loksh Module.Command ...) *)
PROCEDURE CmdLine(VAR s: ARRAY OF CHAR);
VAR fd, n, r, i, k: LONGINT; buf: ARRAY 512 OF CHAR; name: ARRAY 20 OF CHAR;
BEGIN
  s[0] := 0X; name := "/proc/self/cmdline";
  fd := Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR(name[0]), Linux0.ORDonly, 0);
  IF fd <= 0 THEN RETURN END;
  n := Linux0.Read0(fd, SYSTEM.ADR(buf[0]), LEN(buf) - 1); r := Linux0.Close0(fd);
  IF n <= 0 THEN RETURN END;
  buf[n] := 0X; i := 0; WHILE (i < n) & (buf[i] # 0X) DO INC(i) END;  (* after argv[0] *)
  INC(i); k := 0; WHILE (i < n) & (buf[i] # 0X) & (k < LEN(s) - 1) DO s[k] := buf[i]; INC(i); INC(k) END;
  s[k] := 0X
END CmdLine;

PROCEDURE Update;
VAR R: texts.Reader;
BEGIN
  IF Oberon.Par = NIL THEN n := 0; text := NIL; RETURN END;
  IF (Oberon.Par.text = text) & (Oberon.Par.pos = pos) & (text # NIL) THEN RETURN END;
  text := Oberon.Par.text; pos := Oberon.Par.pos; n := 0;
  IF text = NIL THEN RETURN END;
  Name(text, pos, args[0]); IF args[0] = "" THEN CmdLine(args[0]) END;
  n := 1;
  texts.OpenReader(R, text, pos);
  WHILE (n < MaxArgs) & texts.Arg(R, args[n]) DO INC(n) END
END Update;

PROCEDURE Count* (): LONGINT;
BEGIN Update; RETURN n
END Count;

PROCEDURE Length* (index: LONGINT): LONGINT;
BEGIN
  Update; ASSERT((index >= 0) & (index < n));
  RETURN Len(args[index])
END Length;

PROCEDURE Get* (index, offset: LONGINT; VAR ch: Byte);
BEGIN
  Update; ASSERT((index >= 0) & (index < n));
  ch := args[index][offset]
END Get;

PROCEDURE IsEol* (ch: Byte): BOOLEAN;
BEGIN RETURN SYSTEM.VAL(CHAR, ch) = 0AX
END IsEol;

BEGIN
  n := 0; text := NIL; pos := -1
END ProgramArgsHost.
