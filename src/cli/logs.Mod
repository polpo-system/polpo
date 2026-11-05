MODULE logs;  (** the log of the console commands *)

(** Compilers and other tools of the ETH system write their messages into Oberon0.Log. In the
  console nobody sees that text, so a console command shows what it added:

    pos := Oberon0.Log.len; ... (the tool writes into the log) ...; logs.Show(pos)

  In the desktop Out writes into the log as well, where the messages are already: Show writes
  nothing there. *)

IMPORT Texts, Oberon := Oberon0, Out;

(** Write what was appended to the log since pos with Out, line ends as Out.Ln; nothing in the
  desktop *)
PROCEDURE Show*(pos: LONGINT);
VAR R: Texts.Reader; ch: CHAR; end: LONGINT;
BEGIN
  end := Oberon.Log.len;
  IF (Out.writer = NIL) & (end > pos) THEN
    Texts.OpenReader(R, Oberon.Log, pos);
    WHILE pos < end DO
      Texts.Read(R, ch); INC(pos);
      IF ch = 0DX THEN Out.Ln ELSE Out.Char(ch) END
    END
  END
END Show;

(** Write "name:line:column: pc n" for the statement the compilers found for pc (option /f):
  pos is where they stopped, after the statement; the line and column are those of the last
  character before pos that is not blank *)
PROCEDURE ShowPC*(name: ARRAY OF CHAR; T: Texts.Text; pos, pc: LONGINT);
VAR R: Texts.Reader; ch: CHAR; i, line, col, l, c: LONGINT;
BEGIN
  line := 1; col := 1; l := 1; c := 1; i := 0;
  IF pos > T.len THEN pos := T.len END;
  Texts.OpenReader(R, T, 0);
  WHILE i < pos DO
    Texts.Read(R, ch); INC(i);
    IF (ch = 0DX) OR (ch = 0AX) THEN INC(line); col := 1
    ELSE
      IF (ch # " ") & (ch # 09X) THEN l := line; c := col END;
      INC(col)
    END
  END;
  Out.String(name); Out.Char(":"); Out.Int(l, 0); Out.Char(":"); Out.Int(c, 0);
  Out.String(": pc "); Out.Int(pc, 0); Out.Ln
END ShowPC;

END logs.
