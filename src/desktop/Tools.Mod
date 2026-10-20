MODULE Tools;  (** the tool texts of polpo in a viewer, each ready to open with a click *)

(* Tools.Open makes a text with a line for every tool text in tools/ of the root (the system's and
   those the packages installed), sorted by name: Edit.Open X.Tool and the first line of the text,
   which says what the tool is for. Recipes (their first line starts with #) are left out. *)

IMPORT Display, Texts, Oberon, FileDir, Root;

TYPE
  Name = POINTER TO NameDesc;
  NameDesc = RECORD
    name: ARRAY 64 OF CHAR;
    next: Name
  END;

VAR W: Texts.Writer; names: Name;

(* X.Tool into the sorted list names *)
PROCEDURE Entry(name: ARRAY OF CHAR; time, date, size: LONGINT; VAR flags: SET);
VAR t, p, q: Name; i, j, k: INTEGER;
BEGIN
  i := 0; j := 0;
  WHILE name[i] # 0X DO IF name[i] = "/" THEN j := i + 1 END; INC(i) END;
  NEW(t); k := 0;
  WHILE (name[j] # 0X) & (k < LEN(t.name) - 1) DO t.name[k] := name[j]; INC(j); INC(k) END;
  t.name[k] := 0X;
  p := NIL; q := names;
  WHILE (q # NIL) & (q.name < t.name) DO p := q; q := q.next END;
  t.next := q; IF p = NIL THEN names := t ELSE p.next := t END
END Entry;

(* the first line of the text name that is not empty *)
PROCEDURE FirstLine(VAR name, line: ARRAY OF CHAR);
VAR T: Texts.Text; R: Texts.Reader; ch: CHAR; i: INTEGER;
BEGIN
  NEW(T); Texts.Open(T, name); Texts.OpenReader(R, T, 0); Texts.Read(R, ch);
  WHILE ~R.eot & (ch <= " ") DO Texts.Read(R, ch) END;
  i := 0;
  WHILE ~R.eot & (ch # 0DX) & (ch # 0AX) & (i < LEN(line) - 1) DO
    IF ch = 9X THEN ch := " " END;
    line[i] := ch; INC(i); Texts.Read(R, ch)
  END;
  line[i] := 0X
END FirstLine;

(** Tools.Open: a viewer with the tool texts; a middle click on Edit.Open opens one *)
PROCEDURE Open*;
VAR T: Texts.Text; n: Name; mask: ARRAY 256 OF CHAR; line: ARRAY 100 OF CHAR;
BEGIN
  names := NIL; Root.Join("tools/*.Tool", mask); FileDir.Enumerate(mask, {}, Entry);
  NEW(T); Texts.Open(T, "");
  n := names;
  WHILE n # NIL DO
    FirstLine(n.name, line);
    IF line[0] # "#" THEN
      Texts.WriteString(W, "Edit.Open "); Texts.WriteString(W, n.name); Texts.Write(W, 9X);
      Texts.WriteString(W, line); Texts.WriteLn(W)
    END;
    n := n.next
  END;
  names := NIL; Texts.Append(T, W.buf);
  IF Oberon.OpenText # NIL THEN Oberon.OpenText("Tools", T, Display.Width, 400) END  (* wide: in the user track *)
END Open;

BEGIN Texts.OpenWriter(W)
END Tools.
