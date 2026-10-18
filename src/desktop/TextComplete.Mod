MODULE TextComplete;  (** Tab completion in the text frames of the desktop (TextFrames, ScriptFrames) *)

(** Word completes the word before pos as the shell does (Complete0): the first word of a line as a
  command, then as a file name, other words the other way round. What all matches have in common is
  inserted at pos with the attributes of W; several matches are listed in the log. *)

IMPORT Texts, Fonts, Oberon, Complete0;

CONST CR = 0DX;

VAR LW: Texts.Writer;
  unique*: BOOLEAN;  (** the last Word had one match: the word is complete now *)

(** The number of characters inserted at pos, or -1 when there is nothing to complete (a Tab is
  wanted: no word before pos, pos inside a word, or the word is complete). *)
PROCEDURE Word*(T: Texts.Text; pos: LONGINT; VAR W: Texts.Writer): LONGINT;
VAR R: Texts.Reader; word, add: ARRAY 256 OF CHAR; beg, p: LONGINT; i, len: INTEGER; ch: CHAR; cmd: BOOLEAN;
BEGIN
  unique := FALSE;
  IF pos < T.len THEN
    Texts.OpenReader(R, T, pos); Texts.Read(R, ch);
    IF (R.lib IS Fonts.Font) & (ch > " ") THEN RETURN -1 END  (* inside a word *)
  END;
  beg := pos; len := 0;
  LOOP
    IF (beg = 0) OR (len = LEN(word) - 1) THEN EXIT END;
    Texts.OpenReader(R, T, beg - 1); Texts.Read(R, ch);
    IF ~(R.lib IS Fonts.Font) OR (ch <= " ") OR (ch = 22X) THEN EXIT END;
    DEC(beg); INC(len)
  END;
  IF len = 0 THEN RETURN -1 END;
  Texts.OpenReader(R, T, beg); i := 0;
  WHILE i < len DO Texts.Read(R, word[i]); INC(i) END;
  word[i] := 0X;
  cmd := TRUE; p := beg;
  LOOP
    IF p = 0 THEN EXIT END;
    Texts.OpenReader(R, T, p - 1); Texts.Read(R, ch);
    IF (ch = CR) OR (ch = 0AX) THEN EXIT END;
    IF ~(R.lib IS Fonts.Font) OR (ch > " ") THEN cmd := FALSE; EXIT END;
    DEC(p)
  END;
  IF cmd THEN Complete0.Command(word, add); IF Complete0.n = 0 THEN Complete0.Path(word, add) END
  ELSE Complete0.Path(word, add); IF Complete0.n = 0 THEN Complete0.Command(word, add) END
  END;
  unique := Complete0.n = 1;
  IF (add = "") & (Complete0.n <= 1) THEN RETURN -1 END;
  i := 0; WHILE add[i] # 0X DO INC(i) END;
  IF i > 0 THEN Texts.WriteString(W, add); Texts.Insert(T, pos, W.buf) END;
  IF Complete0.n > 1 THEN
    len := 0;
    WHILE (len < Complete0.n) & (len < Complete0.MaxNames) DO
      Texts.WriteString(LW, Complete0.name[len]); Texts.Write(LW, " "); INC(len)
    END;
    Texts.WriteLn(LW); Texts.Append(Oberon.Log, LW.buf)
  END;
  RETURN i
END Word;

BEGIN Texts.OpenWriter(LW); unique := FALSE
END TextComplete.
