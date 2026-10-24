MODULE logs;  (** the log of the console commands *)

(** Compilers and other tools of the ETH system write their messages into Oberon0.Log. In the
  console nobody sees that text, so a console command shows what it added:

    pos := Oberon0.Log.len; ... (the tool writes into the log) ...; logs.Show(pos)

  In the desktop out writes into the log as well, where the messages are already: Show writes
  nothing there. *)

IMPORT Texts, Oberon := Oberon0, out;

(** Write what was appended to the log since pos with out, line ends as out.Ln; nothing in the
  desktop *)
PROCEDURE Show*(pos: LONGINT);
VAR R: Texts.Reader; ch: CHAR; end: LONGINT;
BEGIN
  end := Oberon.Log.len;
  IF (out.writer = NIL) & (end > pos) THEN
    Texts.OpenReader(R, Oberon.Log, pos);
    WHILE pos < end DO
      Texts.Read(R, ch); INC(pos);
      IF ch = 0DX THEN out.Ln ELSE out.Char(ch) END
    END
  END
END Show;

END logs.
