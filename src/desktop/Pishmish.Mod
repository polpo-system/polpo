MODULE Pishmish;  (** a Gemini and Spartan browser in the desktop *)

(* Pishmish.Open url [/ident who] ~ opens a viewer with the page of url (gemini:// or spartan://),
   rendered: headings, links, list items, quotes and preformatted text in their fonts, in a
   Unicode font. A middle click on a link follows it in the same viewer; the menu has Back and
   Reload. Answers that are not a page are shown as text with commands to click: an input prompt
   (status 10, 11; a Spartan =: link) with a line "Pishmish.Send ... ~" to edit and click, a
   certificate request (60) with the identities ("Pishmish.Ident ..."), a file that is not text
   with "Pishmish.Save name ~". Servers are trusted on first use ($HOME/.gemini_hosts). The
   identity (/ident: a prefix of its fingerprint, its name or mail, see dcs) stays with the
   viewer for its next pages. tools/Pishmish.Tool has commands to click. *)

IMPORT Input, Objects, Display, Texts, Fonts, Oberon, MenuViewers, TextFrames,
  TLSIdentity, Gemini0, Gemtext0;

CONST
  Menu = "System.Close System.Copy System.Grow Pishmish.Back Pishmish.Reload Edit.Search Edit.Store";
  MaxURL = Gemini0.MaxURL;
  LinkCol = 3; PromptCol = 9; QuoteCol = 12; ErrorCol = 1; NoteCol = 12;  (* palette colours *)
  Middle = 1;  (* mouse buttons: 2 left, 1 middle, 0 right *)

TYPE
  Link = POINTER TO LinkDesc;
  LinkDesc = RECORD
    beg, end: LONGINT;           (* in the text *)
    url: ARRAY MaxURL OF CHAR;   (* absolute *)
    prompt: BOOLEAN;             (* Spartan =: : asks for input *)
    next: Link
  END;

  History = POINTER TO HistoryDesc;
  HistoryDesc = RECORD url: ARRAY MaxURL OF CHAR; next: History END;

  Page = POINTER TO PageDesc;  (* the state of a viewer *)
  PageDesc = RECORD
    text: Texts.Text;
    menu: Texts.Text;
    frame: TextFrames.Frame;     (* where the page is shown *)
    url: ARRAY MaxURL OF CHAR;   (* shown *)
    input: ARRAY MaxURL OF CHAR; (* the URL that asked for input *)
    who: ARRAY 256 OF CHAR;      (* the identity, "" for none *)
    identity: TLSIdentity.Identity;
    links: Link;
    back: History;
    last: Gemini0.Response;      (* for Save *)
    next: Page
  END;

VAR
  W: Texts.Writer;
  pages: Page;
  fText, fBold, fItalic, fH1, fH2, fH3, fPre, fSmall: Fonts.Font;
  width: LONGINT;           (* of the text area of the viewer being written, in pixels; 0: no wrapping *)
  column, columns, indent: LONGINT;  (* wrapping: the column, the columns of the font, the indent of continuations *)

(* ----- small things ----- *)

PROCEDURE Len(VAR a: ARRAY OF CHAR): LONGINT;
VAR i: LONGINT;
BEGIN i := 0; WHILE (i < LEN(a)) & (a[i] # 0X) DO INC(i) END; RETURN i
END Len;

PROCEDURE Log(a, b: ARRAY OF CHAR);
VAR L: Texts.Writer;
BEGIN
  Texts.OpenWriter(L); Texts.WriteString(L, "Pishmish: "); Texts.WriteString(L, a); Texts.WriteString(L, b);
  Texts.WriteLn(L); Texts.Append(Oberon.Log, L.buf)
END Log;

PROCEDURE Font(name: ARRAY OF CHAR; VAR f: Fonts.Font);
BEGIN
  f := Fonts.This(name);
  IF f = NIL THEN f := Fonts.Default END
END Font;

PROCEDURE Style(f: Fonts.Font; col: INTEGER);
BEGIN Texts.SetFont(W, f); Texts.SetColor(W, SHORT(col))
END Style;

(* the page of the viewer whose text is T *)
PROCEDURE PageOf(T: Texts.Text): Page;
VAR p: Page;
BEGIN
  p := pages; WHILE (p # NIL) & (p.text # T) DO p := p.next END;
  RETURN p
END PageOf;

(* the page of the viewer of the command (Oberon.Par.vwr), or of the star marker *)
PROCEDURE ThisPage(): Page;
VAR V: Display.Frame; F: Display.Frame;
BEGIN
  V := Oberon.Par.vwr;
  IF (V = NIL) OR ~(V IS MenuViewers.Viewer) THEN V := Oberon.MarkedViewer() END;
  IF (V # NIL) & (V IS MenuViewers.Viewer) & (V.dsc # NIL) THEN
    F := V.dsc.next;
    IF (F # NIL) & (F IS TextFrames.Frame) THEN RETURN PageOf(F(TextFrames.Frame).text) END
  END;
  RETURN NIL
END ThisPage;

(* the name in the menu of page: url *)
PROCEDURE SetName(p: Page; VAR url: ARRAY OF CHAR);
VAR R: Texts.Reader; ch: CHAR; n: LONGINT;
BEGIN
  IF p.menu = NIL THEN RETURN END;
  Texts.OpenReader(R, p.menu, 0); n := 0; Texts.Read(R, ch);
  WHILE ~R.eot & (ch # "|") DO INC(n); Texts.Read(R, ch) END;
  IF n > 0 THEN DEC(n) END;  (* the blank before | *)
  Texts.Delete(p.menu, 0, n);
  Texts.SetFont(W, Fonts.Default); Texts.SetColor(W, Display.FG); Texts.WriteString(W, url);
  Texts.Insert(p.menu, 0, W.buf)
END SetName;

(* ----- rendering ----- *)

(* the width of a character of the font f (the Ttyp0 fonts are monospaced) *)
PROCEDURE CharWidth(f: Fonts.Font): LONGINT;
VAR dx, x, y, w, h: INTEGER; pat: LONGINT;
BEGIN
  Fonts.GetChar(f, "m", dx, x, y, w, h, pat);
  IF dx <= 0 THEN dx := 8 END;
  RETURN dx
END CharWidth;

(* the next lines are written in the font f, continuations indented by ind columns *)
PROCEDURE Wrap(f: Fonts.Font; ind: LONGINT);
BEGIN
  IF width > 0 THEN columns := width DIV CharWidth(f) - 1 ELSE columns := MAX(LONGINT) END;
  IF columns < 20 THEN columns := 20 END;
  indent := ind
END Wrap;

PROCEDURE NewLine;
BEGIN Texts.WriteLn(W); column := 0
END NewLine;

(* writes s, broken at blanks so that no line is longer than columns; a word longer than a line
   is broken where it must be *)
PROCEDURE WriteWrapped(VAR s: ARRAY OF CHAR);
VAR i, j, n, k: LONGINT;
BEGIN
  i := 0;
  WHILE s[i] # 0X DO
    IF s[i] = " " THEN
      j := i + 1; n := 0;  (* the length of the next word, in characters *)
      WHILE (s[j] # 0X) & (s[j] # " ") DO IF (ORD(s[j]) < 80H) OR (ORD(s[j]) >= 0C0H) THEN INC(n) END; INC(j) END;
      IF (column + 1 + n > columns) & (column > indent) & (n < columns - indent) THEN
        NewLine; k := 0; WHILE k < indent DO Texts.Write(W, " "); INC(k) END; column := indent
      ELSE Texts.Write(W, " "); INC(column)
      END;
      INC(i)
    ELSE
      IF column >= columns THEN NewLine; k := 0; WHILE k < indent DO Texts.Write(W, " "); INC(k) END; column := indent END;
      Texts.Write(W, s[i]);
      IF (ORD(s[i]) < 80H) OR (ORD(s[i]) >= 0C0H) THEN INC(column) END;
      INC(i)
    END
  END
END WriteWrapped;

(* writes s, counting its columns, without wrapping (prefixes) *)
PROCEDURE WriteCounted(s: ARRAY OF CHAR);
VAR i: LONGINT;
BEGIN
  Texts.WriteString(W, s); i := 0;
  WHILE s[i] # 0X DO IF (ORD(s[i]) < 80H) OR (ORD(s[i]) >= 0C0H) THEN INC(column) END; INC(i) END
END WriteCounted;

PROCEDURE AddLink(p: Page; beg, end: LONGINT; VAR url: ARRAY OF CHAR; prompt: BOOLEAN);
VAR l, q: Link;
BEGIN
  NEW(l); l.beg := beg; l.end := end; COPY(url, l.url); l.prompt := prompt; l.next := NIL;
  IF p.links = NIL THEN p.links := l ELSE q := p.links; WHILE q.next # NIL DO q := q.next END; q.next := l END
END AddLink;

(* the text written so far into T, its length *)
PROCEDURE Flush(T: Texts.Text): LONGINT;
BEGIN Texts.Append(T, W.buf); RETURN T.len
END Flush;

(* the gemtext of r into the text of p, with its links *)
PROCEDURE Gemtext(p: Page; r: Gemini0.Response);
VAR S: Gemtext0.Scanner; L: Gemtext0.Line; abs: ARRAY MaxURL OF CHAR; beg, end: LONGINT; more: BOOLEAN; kind: LONGINT;
BEGIN
  Gemtext0.Open(S, r.body); more := FALSE; column := 0;
  IF p.frame # NIL THEN width := p.frame.W - p.frame.left - p.frame.right ELSE width := 0 END;
  WHILE Gemtext0.Next(S, L) DO
    kind := L.kind;
    IF ~more THEN  (* the start of a line *)
      column := 0;
      CASE kind OF
        Gemtext0.Heading1: Style(fH1, Display.FG); Wrap(fH1, 0)
      | Gemtext0.Heading2: Style(fH2, Display.FG); Wrap(fH2, 0)
      | Gemtext0.Heading3: Style(fH3, Display.FG); Wrap(fH3, 0)
      | Gemtext0.Item: Style(fText, Display.FG); Wrap(fText, 4); WriteCounted("  • ")
      | Gemtext0.Quote: Style(fItalic, QuoteCol); Wrap(fItalic, 2); WriteCounted("  ")
      | Gemtext0.Pre, Gemtext0.PreStart, Gemtext0.PreEnd: Style(fPre, Display.FG)
      | Gemtext0.Link, Gemtext0.Prompt:
          Style(fText, Display.FG); Wrap(fText, 2);
          WriteCounted("⇒ ")  (* a prompt: the same, in its colour *)
      ELSE Style(fText, Display.FG); Wrap(fText, 0)
      END
    END;
    IF (kind = Gemtext0.Link) OR (kind = Gemtext0.Prompt) THEN
      beg := Flush(p.text);
      IF kind = Gemtext0.Link THEN Style(fText, LinkCol) ELSE Style(fText, PromptCol) END;
      WriteWrapped(L.text);
      end := Flush(p.text);
      IF ~Gemini0.Resolve(r.url, L.url, abs) THEN COPY(L.url, abs) END;
      AddLink(p, beg, end, abs, kind = Gemtext0.Prompt);
      IF (Gemini0.Protocol(abs) = 0) THEN  (* another scheme: shown, not followed *)
        Style(fSmall, NoteCol); Texts.WriteString(W, "  "); Texts.WriteString(W, abs)
      END
    ELSIF (kind = Gemtext0.PreStart) OR (kind = Gemtext0.PreEnd) THEN
      (* the ``` lines are not shown; the alt text of the opening one is a small note *)
      IF L.text[0] # 0X THEN Style(fSmall, NoteCol); Texts.WriteString(W, L.text) END
    ELSIF kind = Gemtext0.Pre THEN Texts.WriteString(W, L.text)  (* as it is, not wrapped *)
    ELSE WriteWrapped(L.text)
    END;
    more := L.more;
    IF ~more & ~((kind = Gemtext0.PreStart) & (L.text[0] = 0X) OR (kind = Gemtext0.PreEnd) & (L.text[0] = 0X)) THEN
      NewLine
    END
  END;
  Texts.Append(p.text, W.buf)
END Gemtext;

(* another text type: as preformatted text *)
PROCEDURE Plain(p: Page; r: Gemini0.Response);
VAR c: Gemini0.Chunk; i: LONGINT; ch: CHAR;
BEGIN
  Style(fPre, Display.FG); c := r.body;
  WHILE c # NIL DO
    i := 0;
    WHILE i < c.len DO
      ch := c.data[i];
      IF ch = 0AX THEN Texts.WriteLn(W) ELSIF (ch >= " ") OR (ch = 09X) THEN Texts.Write(W, ch) END;
      INC(i)
    END;
    c := c.next
  END;
  Texts.Append(p.text, W.buf)
END Plain;

PROCEDURE Heading(s: ARRAY OF CHAR);
BEGIN Style(fH2, Display.FG); Texts.WriteString(W, s); Texts.WriteLn(W)
END Heading;

PROCEDURE Line(s: ARRAY OF CHAR);
BEGIN Style(fText, Display.FG); Wrap(fText, 0); column := 0; WriteWrapped(s); NewLine
END Line;

PROCEDURE Command(s, t: ARRAY OF CHAR);
BEGIN Style(fText, LinkCol); Texts.WriteString(W, s); Texts.WriteString(W, t); Texts.WriteLn(W)
END Command;

(* the identities, to log in with, as commands *)
PROCEDURE IdentityList;
VAR dir: ARRAY 1024 OF CHAR; id: Gemini0.Ident; short: ARRAY 17 OF CHAR; i: LONGINT;
BEGIN
  Gemini0.IdentsDir(dir); id := Gemini0.LoadIdents(dir);
  IF id = NIL THEN Line("You have no identity yet; make one:")
  ELSE Line("Log in with one of your identities (middle click):")
  END;
  Texts.WriteLn(W);
  WHILE id # NIL DO
    i := 0; WHILE i < 16 DO short[i] := id.fingerprint[i]; INC(i) END; short[16] := 0X;
    Style(fText, LinkCol); Texts.WriteString(W, "Pishmish.Ident "); Texts.WriteString(W, short);
    Style(fText, Display.FG); Texts.WriteString(W, "   "); Texts.WriteString(W, id.cn);
    IF id.mail[0] # 0X THEN Texts.WriteString(W, " <"); Texts.WriteString(W, id.mail); Texts.WriteString(W, ">") END;
    Texts.WriteLn(W); id := id.next
  END;
  Texts.WriteLn(W);
  Command("Pishmish.Ident none", "   without an identity");
  Command("DCS.NewIdent name mail@example.org ~", "   a new identity, then Pishmish.Reload")
END IdentityList;

(* the answer r, or the failure, into the text of p *)
PROCEDURE Render(p: Page; r: Gemini0.Response; ok: BOOLEAN);
VAR name: ARRAY 80 OF CHAR;
BEGIN
  Texts.Delete(p.text, 0, p.text.len); p.links := NIL; p.last := NIL;
  IF p.frame # NIL THEN width := p.frame.W - p.frame.left - p.frame.right ELSE width := 0 END;
  IF ~ok THEN
    Heading("No answer"); Style(fText, ErrorCol); Texts.WriteString(W, Gemini0.lastError); Texts.WriteLn(W);
    Texts.WriteLn(W); Command("Pishmish.Reload", "   tries again")
  ELSE
    COPY(r.url, p.url); SetName(p, p.url);
    CASE Gemini0.Kind(r) OF
      1:
        COPY(r.url, p.input);
        IF r.status = 11 THEN Heading("Sensitive input") ELSE Heading("Input") END;
        Line(r.meta); Texts.WriteLn(W);
        Line("Write your answer after the command, then middle click it:"); Texts.WriteLn(W);
        Command("Pishmish.Send ", " ~")
    | 2:
        p.last := r;
        IF Gemtext0.IsGemtext(r.meta) THEN Gemtext(p, r)
        ELSIF (r.meta[0] = "t") & (r.meta[1] = "e") & (r.meta[2] = "x") & (r.meta[3] = "t") & (r.meta[4] = "/") THEN Plain(p, r)
        ELSE
          Heading("A file"); Line(r.meta);
          Style(fText, Display.FG); Texts.WriteInt(W, r.length, 0); Texts.WriteString(W, " bytes"); Texts.WriteLn(W); Texts.WriteLn(W);
          Gemini0.NameForURL(r.url, name);
          Command("Pishmish.Save ", name)
        END;
        IF ~r.complete THEN Texts.WriteLn(W); Style(fText, ErrorCol); Texts.WriteString(W, "(the page is incomplete: the connection was cut)"); Texts.WriteLn(W) END
    | 6:
        Gemini0.StatusName(r.protocol, r.status, name); Heading(name); Line(r.meta); Texts.WriteLn(W);
        IdentityList
    ELSE
      Gemini0.StatusName(r.protocol, r.status, name); Heading(name);
      Style(fText, ErrorCol); Texts.WriteString(W, r.meta); Texts.WriteLn(W)
    END
  END;
  Texts.Append(p.text, W.buf);
  IF p.frame # NIL THEN TextFrames.RemoveCaret(p.frame); TextFrames.Show(p.frame, 0) END  (* a new page from its top *)
END Render;

(* loads url (with input) into the page p *)
PROCEDURE Load(p: Page; VAR url, input: ARRAY OF CHAR);
VAR o: Gemini0.Options; r: Gemini0.Response; ok: BOOLEAN;
BEGIN
  o := Gemini0.NewOptions(); o.identity := p.identity;
  ok := Gemini0.Fetch(url, input, o, r);
  IF ~ok THEN COPY(url, p.url); SetName(p, p.url) END;
  IF ok & r.firstUse THEN Log("trusting on first use the key of ", r.url) END;
  Render(p, r, ok)
END Load;

(* goes from the page of p to url *)
PROCEDURE Go(p: Page; VAR url: ARRAY OF CHAR);
VAR b: History; none: ARRAY 2 OF CHAR;
BEGIN
  IF p.url[0] # 0X THEN NEW(b); COPY(p.url, b.url); b.next := p.back; p.back := b END;
  none := ""; Load(p, url, none)
END Go;

(* a prompt for input to url (a Spartan =: link) in the page p *)
PROCEDURE Ask(p: Page; VAR url, label: ARRAY OF CHAR);
VAR b: History;
BEGIN
  IF p.url[0] # 0X THEN NEW(b); COPY(p.url, b.url); b.next := p.back; p.back := b END;
  Texts.Delete(p.text, 0, p.text.len); p.links := NIL; COPY(url, p.input);
  Heading("Input"); Line(label); Texts.WriteLn(W);
  Line("Write your answer after the command, then middle click it:"); Texts.WriteLn(W);
  Command("Pishmish.Send ", " ~");
  Texts.Append(p.text, W.buf);
  IF p.frame # NIL THEN TextFrames.RemoveCaret(p.frame); TextFrames.Show(p.frame, 0) END
END Ask;

(* ----- the viewer ----- *)

PROCEDURE LinkAt(p: Page; pos: LONGINT): Link;
VAR l: Link;
BEGIN
  l := p.links; WHILE (l # NIL) & ~((pos >= l.beg) & (pos < l.end)) DO l := l.next END;
  RETURN l
END LinkAt;

(* the frame handler: a middle click on a link follows it; the rest as in any text *)
PROCEDURE Handle(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR p: Page; l: Link; pos: LONGINT; keys, keysum: SET; X, Y: INTEGER; label: ARRAY 256 OF CHAR; R: Texts.Reader; i: LONGINT; ch: CHAR;
BEGIN
  WITH F: TextFrames.Frame DO
    IF (M IS Oberon.InputMsg) & (M(Oberon.InputMsg).id = Oberon.track) & (M(Oberon.InputMsg).keys = {Middle}) &
       (M(Oberon.InputMsg).X >= F.X + TextFrames.barW) THEN
      p := PageOf(F.text);
      IF p # NIL THEN
        pos := TextFrames.Pos(F, M(Oberon.InputMsg).X, M(Oberon.InputMsg).Y);
        l := LinkAt(p, pos);
        IF l # NIL THEN
          keysum := {Middle};
          REPEAT
            Input.Mouse(keys, X, Y); keysum := keysum + keys;
            Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, X, Y)
          UNTIL keys = {};
          IF keysum = {Middle} THEN
            IF Gemini0.Protocol(l.url) = 0 THEN Log("not a gemini:// or spartan:// link: ", l.url)
            ELSIF l.prompt THEN
              Texts.OpenReader(R, F.text, l.beg); i := 0;
              WHILE (i < l.end - l.beg) & (i < LEN(label) - 1) DO Texts.Read(R, ch); label[i] := ch; INC(i) END;
              label[i] := 0X; Ask(p, l.url, label)
            ELSE Go(p, l.url)
            END
          END;
          RETURN
        END
      END
    END;
    TextFrames.Handle(F, M)
  END
END Handle;

(* a new viewer with a page *)
PROCEDURE NewPage(): Page;
VAR p: Page; V: MenuViewers.Viewer; menu, F: TextFrames.Frame; X, Y: INTEGER;
BEGIN
  NEW(p); NEW(p.text); Texts.Open(p.text, ""); p.url := ""; p.input := ""; p.who := ""; p.identity := NIL;
  p.links := NIL; p.back := NIL; p.last := NIL; p.frame := NIL;
  p.next := pages; pages := p;
  menu := TextFrames.NewMenu("Pishmish", Menu); p.menu := menu.text;
  F := TextFrames.NewText(p.text, 0); F.handle := Handle; p.frame := F;
  IF Oberon.Par.vwr # NIL THEN Oberon.AllocateUserViewer(Oberon.Par.vwr.X, X, Y) ELSE Oberon.AllocateUserViewer(0, X, Y) END;
  V := MenuViewers.New(menu, F, TextFrames.menuH, X, Y);
  RETURN p
END NewPage;

(* p.identity := the identity who names ("" for none); FALSE if it names none or several *)
PROCEDURE UseIdentity(p: Page; VAR who: ARRAY OF CHAR): BOOLEAN;
VAR dir: ARRAY 1024 OF CHAR; id: Gemini0.Ident;
BEGIN
  p.identity := NIL; p.who := "";
  IF (who = "") OR (who = "none") THEN RETURN TRUE END;
  Gemini0.IdentsDir(dir); id := Gemini0.FindIdent(Gemini0.LoadIdents(dir), who);
  IF id = NIL THEN
    IF Gemini0.nCandidates > 1 THEN Log(who, " names several identities: give more of the fingerprint")
    ELSE Log("no identity named ", who)
    END;
    RETURN FALSE
  END;
  p.identity := Gemini0.LoadIdentity(id.cert, id.key);
  IF p.identity = NIL THEN Log(id.cert, Gemini0.lastError); RETURN FALSE END;
  COPY(id.fingerprint, p.who);
  Log("logged in as ", id.cn);
  RETURN TRUE
END UseIdentity;

(* url := the selection, up to a blank *)
PROCEDURE Selection(VAR url: ARRAY OF CHAR): BOOLEAN;
VAR T: Texts.Text; beg, end, time: LONGINT; R: Texts.Reader; ch: CHAR; i: LONGINT;
BEGIN
  Oberon.GetSelection(T, beg, end, time);
  IF time < 0 THEN RETURN FALSE END;
  Texts.OpenReader(R, T, beg); i := 0; Texts.Read(R, ch);
  WHILE (ch <= " ") & (Texts.Pos(R) <= end) DO Texts.Read(R, ch) END;
  WHILE (ch > " ") & (Texts.Pos(R) <= end) & (i < LEN(url) - 1) DO url[i] := ch; INC(i); Texts.Read(R, ch) END;
  url[i] := 0X;
  RETURN i > 0
END Selection;

(** Pishmish.Open url [/ident who] ~ (url ^: the selection): the page of url in a new viewer *)
PROCEDURE Open*;
VAR A: Texts.Reader; arg, url, who: ARRAY MaxURL OF CHAR; p: Page; none: ARRAY 2 OF CHAR;
BEGIN
  Texts.OpenArgs(A); url := ""; who := "";
  WHILE Texts.Arg(A, arg) DO
    IF arg = "/ident" THEN IF ~Texts.Arg(A, who) THEN who := "" END
    ELSIF url = "" THEN COPY(arg, url)
    END
  END;
  IF (url = "^") & ~Selection(url) THEN url := "" END;
  IF url = "" THEN Log("usage: Pishmish.Open url [/ident who] ~", ""); RETURN END;
  IF Gemini0.Protocol(url) = 0 THEN Log("not a gemini:// or spartan:// URL: ", url); RETURN END;
  p := NewPage();
  IF ~UseIdentity(p, who) THEN RETURN END;
  none := ""; Load(p, url, none)
END Open;

(** Pishmish.Back: the page before (in the menu of a Pishmish viewer) *)
PROCEDURE Back*;
VAR p: Page; url: ARRAY MaxURL OF CHAR; none: ARRAY 2 OF CHAR;
BEGIN
  p := ThisPage();
  IF (p # NIL) & (p.back # NIL) THEN COPY(p.back.url, url); p.back := p.back.next; none := ""; Load(p, url, none) END
END Back;

(** Pishmish.Reload: the page again *)
PROCEDURE Reload*;
VAR p: Page; url: ARRAY MaxURL OF CHAR; none: ARRAY 2 OF CHAR;
BEGIN
  p := ThisPage();
  IF (p # NIL) & (p.url[0] # 0X) THEN COPY(p.url, url); none := ""; Load(p, url, none) END
END Reload;

(** Pishmish.Send text ~: the answer to an input prompt of the page (written in it) *)
PROCEDURE Send*;
VAR p: Page; R: Texts.Reader; ch: CHAR; input: ARRAY MaxURL OF CHAR; url: ARRAY MaxURL OF CHAR; i: LONGINT; b: History;
BEGIN
  p := ThisPage();
  IF (p = NIL) OR (p.input[0] = 0X) THEN Log("Pishmish.Send answers an input prompt in a Pishmish viewer", ""); RETURN END;
  Texts.OpenReader(R, Oberon.Par.text, Oberon.Par.pos); i := 0; Texts.Read(R, ch);
  WHILE ~R.eot & (ch = " ") DO Texts.Read(R, ch) END;
  WHILE ~R.eot & (ch # "~") & (ch # 0DX) & (ch # 0AX) & (i < LEN(input) - 1) DO input[i] := ch; INC(i); Texts.Read(R, ch) END;
  WHILE (i > 0) & (input[i - 1] = " ") DO DEC(i) END;
  input[i] := 0X;
  COPY(p.input, url); p.input := "";
  IF p.url[0] # 0X THEN NEW(b); COPY(p.url, b.url); b.next := p.back; p.back := b END;
  Load(p, url, input)
END Send;

(** Pishmish.Ident who: log in with the identity who ("none": without one) and load the page again *)
PROCEDURE Ident*;
VAR A: Texts.Reader; who: ARRAY 256 OF CHAR; p: Page;
BEGIN
  p := ThisPage();
  IF p = NIL THEN Log("Pishmish.Ident works in a Pishmish viewer", ""); RETURN END;
  Texts.OpenArgs(A);
  IF ~Texts.Arg(A, who) THEN who := "none" END;
  IF UseIdentity(p, who) THEN Reload END
END Ident;

(** Pishmish.Save name: the file of the page (shown as "A file") to name *)
PROCEDURE Save*;
VAR A: Texts.Reader; name: ARRAY 256 OF CHAR; p: Page;
BEGIN
  p := ThisPage();
  IF (p = NIL) OR (p.last = NIL) THEN Log("Pishmish.Save saves the file of a Pishmish viewer", ""); RETURN END;
  Texts.OpenArgs(A);
  IF ~Texts.Arg(A, name) THEN Gemini0.NameForURL(p.last.url, name) END;
  IF Gemini0.Save(p.last, name) THEN Log("saved ", name) ELSE Log("", Gemini0.lastError) END
END Save;

BEGIN
  Texts.OpenWriter(W); pages := NIL;
  Font("Ttyp0-16-Unicode.Scn.Fnt", fText); Font("Ttyp0-16b-Unicode.Scn.Fnt", fBold);
  Font("Ttyp0-16i-Unicode.Scn.Fnt", fItalic); Font("Ttyp0-30b-Unicode.Scn.Fnt", fH1);
  Font("Ttyp0-22b-Unicode.Scn.Fnt", fH2); Font("Ttyp0-18b-Unicode.Scn.Fnt", fH3);
  Font("Ttyp0-16-Unicode.Scn.Fnt", fPre); Font("Ttyp0-13-Unicode.Scn.Fnt", fSmall)
END Pishmish.
