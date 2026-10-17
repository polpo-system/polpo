(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)
(*
  Peter Matthias
  2015-06-03  added "del-key"; Fixed overflow in Edit and other procedures by adding MulDiv
  2016-04-13  added Input.Copy in TrackSelection
  2016-09-04  fixed right mouse button positioning with 4k displays in Edit*
  
*)

MODULE TextFrames;  (** portable *) (* JG / pjm *)

  IMPORT Input, Modules, Objects, Display, Viewers, Fonts, Texts, Utf8, Oberon, MenuViewers, TextComplete;

  CONST CR = 0DX;
    replace = Display.replace; paint = Display.paint; invert = Display.invert;
    extend = Display.extend; reduce = Display.reduce;

  StandardMenu = "System.Close System.Copy System.Grow Edit.Search Edit.Store Edit.StorePlain";
  LogMenu = "System.Clear Edit.Locate Edit.Search Edit.Store";
  OpenCmd = "Edit.Open";
  
  Modern = FALSE;  (* enable "modern" look *)
  SmallDisplay = TRUE;  (* enable PDR's support for narrow displays *)
  MoveArea = TRUE;  (* show "move" icon at top left, and use clipping for caret *)
  
  TYPE
    Line = POINTER TO LineDesc;

    LineDesc = RECORD
      len: LONGINT;
        wid: INTEGER;
        eot: BOOLEAN;
        asr, dsr, h: INTEGER;  (* polpo: ascent, descent and height of the largest font of the line *)
        next: Line
    END;

    Location* = RECORD
        org*, pos*: LONGINT;
        dx*, x*, y*: INTEGER;
        lin: Line
    END;

    Frame* = POINTER TO FrameDesc;

    FrameDesc* = RECORD
        (Display.FrameDesc)
        text*: Texts.Text;
        org*: LONGINT;
        col*: INTEGER;
        lsp*: INTEGER;
        left*, right*, top*, bot*: INTEGER;
        markH*: INTEGER;
        time*: LONGINT;
        mark*, car*, sel*: INTEGER;
        carloc*: Location;
        selbeg*, selend*: Location;
        trailer: Line
    END;

    (*mark < 0: arrow mark
        mark = 0: no mark
        mark > 0: position mark*)

  VAR
    menuH*, barW*, left*, right*, top*, bot*, lsp*: INTEGER; (*standard sizes*)
    MarkColor, BarColor, MenuBG, TextBG, FullColor, mode: INTEGER;
    asr, dsr, selH, markW, eolW: INTEGER;
    spacing: LONGINT;  (* polpo: line spacing in percent of the line height, System.LineSpacing *)
    oldLeft, oldRight, oldTop, oldBot, oldLsp: INTEGER;  (* standard sizes before Rescale *)
    ch: CHAR;
    utfBuf: ARRAY 4 OF CHAR; utfLen, utfExp: INTEGER;
    utfLib: Objects.Library; utfCol, utfVoff: SHORTINT;
    W, KW: Texts.Writer; (*keyboard writer*)
    box: Fonts.Char;
    BoxPat: ARRAY 12 OF SET;
    hintPos: LONGINT;
    saved: Oberon.CaretMsg;
    (* polpo: keyboard editing *)
    anchorF: Frame; anchorPos: LONGINT;  (* start of a selection made with Shift and the cursor keys *)
    goalF: Frame; goalX: INTEGER;  (* column kept by consecutive up and down moves *)
    clipBuf: Texts.Buffer;  (* text copied with Ctrl+C or cut with Ctrl+X, with its looks *)
    hiddenF: Frame; hiddenPos: LONGINT;  (* the caret of hiddenF, scrolled out of view *)
    (* polpo: a block selection (Ctrl+B): the columns from x bAnX to bCarX (frame relative, as
       Location.x) on the lines from bAnLn (counted from 0) to the line of the caret *)
    blockF: Frame;  (* the frame with a block, or NIL *)
    bShown, bBusy: BOOLEAN;  (* the block is drawn; a block operation is changing the text *)
    bMarking: BOOLEAN;  (* the movement keys extend the block; after an edit or a copy they end it *)
    bAnLn: LONGINT; bAnX, bCarX: INTEGER;
    blockClip: Texts.Text;  (* a copied block: its rows separated by CR; NIL if the clipboard is a stretch *)

  PROCEDURE Min (i, j: INTEGER): INTEGER;
  BEGIN IF i >= j THEN RETURN j ELSE RETURN i END
  END Min;

  PROCEDURE Max (i, j: LONGINT): LONGINT;
  BEGIN IF i >= j THEN RETURN i ELSE RETURN j END
  END Max;

  (*------------------display support------------------------*)

  PROCEDURE ReplConst (col: INTEGER; F: Frame; X, Y, W, H: INTEGER; mode: INTEGER);
  BEGIN
    IF X + W <= F.X + F.W THEN Display.ReplConst(col, X, Y, W, H, mode)
    ELSIF X < F.X + F.W THEN Display.ReplConst(col, X, Y, F.X + F.W - X, H, mode)
    END
  END ReplConst;

(* (a*b) DIV c without over flow if c >=a or b *)

PROCEDURE MulDiv( a: LONGINT; b: INTEGER; c: LONGINT): LONGINT;
VAR d: LONGINT;
BEGIN
  d:= a MOD 8000H*b;
  a:= a DIV 8000H *b;
  WHILE a>=8000H DO
    a:=a DIV 2;  c:=c DIV 2;  d:= d DIV 2;
  END;
  RETURN (a*8000H+d) DIV c;
END MulDiv;

  PROCEDURE UpdateMark (F: Frame);
    VAR oldH: INTEGER;
  BEGIN
    oldH := F.markH; F.markH := SHORT(MulDiv(F.org, F.H , (F.text.len + 1)));
    IF (F.mark > 0) & (F.left >= barW) & (F.markH # oldH) THEN
      Display.ReplConst(F.col, F.X, F.Y + F.H - 1 - oldH, markW, 1, replace);
      Display.ReplConst(MarkColor, F.X, F.Y + F.H - 1 - F.markH, markW, 1, replace)
    END
  END UpdateMark;

  PROCEDURE GetCP (VAR R: Texts.Reader; VAR n: INTEGER): LONGINT;
  VAR R1: Texts.Reader; s: ARRAY 4 OF CHAR; u: Utf8.Char; c, need, i: INTEGER;
  BEGIN
    s[0] := ch; c := ORD(ch); need := 1;
    IF (c >= 0C2H) & (c < 0E0H) THEN need := 2
    ELSIF (c >= 0E0H) & (c < 0F0H) THEN need := 3
    ELSIF (c >= 0F0H) & (c <= 0F4H) THEN need := 4
    ELSIF c >= 080H THEN n := 1; RETURN -1
    END;
    R1 := R; i := 1;
    WHILE (i < need) & ~R1.eot DO Texts.Read(R1, s[i]); INC(i) END;
    IF (i = need) & Utf8.Ord(s, 0, u, n) THEN
      R := R1; RETURN u
    END;
    n := 1; RETURN -1
  END GetCP;

  PROCEDURE Width (VAR R: Texts.Reader; len: LONGINT): INTEGER;
    VAR pos, cp: LONGINT; ox, n: INTEGER; obj: Objects.Object; lib: Objects.Library;
  BEGIN pos := 0; ox := 0;
    WHILE (pos < len) & (R.lib # NIL) DO
      lib := R.lib; cp := GetCP(R, n);
      IF (lib # NIL) & (lib IS Fonts.Font) & (cp >= 0) & (cp < lib(Fonts.Font).maxRef) THEN
        lib.GetObj(lib, SHORT(cp), obj)
      ELSE obj := box
      END;
      IF ~(obj IS Fonts.Char) THEN obj := box END;
      ox := ox + obj(Fonts.Char).dx; INC(pos, n); Texts.Read(R, ch)
    END;
    RETURN ox
  END Width;

  PROCEDURE DisplayLine (F: Frame; L: Line;
    VAR R: Texts.Reader; X, Y: INTEGER; len: LONGINT);
    VAR NX, n: INTEGER; cp: LONGINT; obj: Objects.Object; lib: Objects.Library;
  BEGIN NX := F.X + F.W;
    WHILE (ch # CR) & (R.lib # NIL) DO
      lib := R.lib;
      cp := GetCP(R, n);
      IF (lib # NIL) & (lib IS Fonts.Font) & (cp >= 0) & (cp < lib(Fonts.Font).maxRef) THEN
        lib.GetObj(lib, SHORT(cp), obj)
      ELSE obj := box
      END;
      WITH obj: Fonts.Char DO
        IF X + obj.x + obj.w <= NX THEN
          Display.CopyPattern(R.col, obj.pat, X + obj.x, Y + obj.y, mode);
          X := X + obj.dx
        ELSE
          X := NX
        END;
      END;
      INC(len, n); Texts.Read(R, ch)
    END;
    L.len := len + 1; L.wid := X + eolW - (F.X + F.left);
    L.eot := R.eot; Texts.Read(R, ch)
  END DisplayLine;

  (* polpo: lines have the height of their largest font.
     The baseline of L.next is Step(L) below the one of L: the descent of L, the gap below L
     (System.LineSpacing percent of its height) and the ascent of L.next. *)

  (* metrics of the line starting at the current character ch of R; R and ch are unchanged *)
  PROCEDURE MeasureLine (VAR R: Texts.Reader; L: Line);
    VAR R1: Texts.Reader; c: CHAR; f: Fonts.Font;
  BEGIN
    R1 := R; c := ch; L.asr := 0; L.dsr := 0; L.h := 0;
    LOOP
      IF (R1.lib # NIL) & (R1.lib IS Fonts.Font) THEN
        f := R1.lib(Fonts.Font);
        IF f.maxY > L.asr THEN L.asr := f.maxY END;
        IF -f.minY > L.dsr THEN L.dsr := -f.minY END;
        IF f.height > L.h THEN L.h := f.height END
      END;
      IF (c = CR) OR (R1.lib = NIL) THEN EXIT END;
      Texts.Read(R1, c)
    END;
    IF L.h = 0 THEN L.asr := asr; L.dsr := dsr; L.h := Fonts.Default.height END
  END MeasureLine;

  PROCEDURE Gap (L: Line): INTEGER;
    VAR g: INTEGER;
  BEGIN
    g := SHORT(L.h * spacing DIV 100) - L.asr - L.dsr;
    IF g < 0 THEN g := 0 END;
    RETURN g
  END Gap;

  PROCEDURE Step (L: Line): INTEGER;
  BEGIN RETURN L.dsr + Gap(L) + L.next.asr
  END Step;

  (* append the lines of R after L (with baseline y, or L = F.trailer), as long as they fit *)
  PROCEDURE Fill (F: Frame; L: Line; y: INTEGER; VAR R: Texts.Reader);
    VAR N: Line; ny: INTEGER;
  BEGIN
    LOOP
      IF L.eot THEN EXIT END;
      NEW(N); MeasureLine(R, N);
      IF L = F.trailer THEN ny := F.Y + F.H - F.top - N.asr ELSE ny := y - L.dsr - Gap(L) - N.asr END;
      IF ny - N.dsr < F.Y + F.bot THEN EXIT END;
      L.next := N; L := N; y := ny;
      DisplayLine(F, L, R, F.X + F.left, y, 0)
    END;
    L.next := F.trailer
  END Fill;

  (* the last line shown and its baseline y; F.trailer if none *)
  PROCEDURE LastLine (F: Frame; VAR L: Line; VAR org: LONGINT; VAR y: INTEGER);
  BEGIN
    L := F.trailer; org := F.org; y := 0;
    WHILE L.next # F.trailer DO
      IF L = F.trailer THEN y := F.Y + F.H - F.top - L.next.asr ELSE y := y - Step(L) END;
      L := L.next; org := org + L.len
    END
  END LastLine;

  PROCEDURE Validate (T: Texts.Text; VAR org: LONGINT);
    VAR R: Texts.Reader; pos: LONGINT;
  BEGIN
    IF org > T.len THEN org := T.len
    ELSIF org > 0 THEN Texts.OpenReader(R, T, org - 1); Texts.Read(R, ch);
      IF ch # CR THEN
        pos := Max(org - 100, 0); Texts.OpenReader(R, T, pos);
        REPEAT Texts.Read(R, ch); INC(pos) UNTIL (pos = org) OR (ch = CR);
        org := pos
      END
    ELSE org := 0
    END
  END Validate;

  PROCEDURE Mark* (F: Frame; mark: INTEGER);
  BEGIN
    IF (mark >= 0) & (F.mark < 0) & (F.H >= 16) THEN
      Display.CopyPattern(F.col, Display.downArrow, F.X, F.Y, paint)
    ELSIF (mark <= 0) & (F.mark > 0) & (F.H > 0) & (F.left >= barW) THEN
      Display.ReplConst(F.col, F.X, F.Y + F.H - 1 - F.markH, markW, 1, replace)
    END;
    IF (mark > 0) & (F.H > 0) & (F.left >= barW) & (F.mark <= 0) THEN
      Display.ReplConst(MarkColor, F.X, F.Y + F.H - 1 - F.markH, markW, 1, replace)
    ELSIF (mark < 0) & (F.H >= 16) & (F.mark >= 0) THEN
      Display.CopyPattern(MarkColor, Display.downArrow, F.X, F.Y, paint)
    END;
    F.mark := mark;
  END Mark;

  PROCEDURE DrawIcon(F: Frame);
  BEGIN
    Display.ReplConst(MarkColor, F.X+3, F.Y+F.H-9, 6, 6, replace);
    IF Oberon.New THEN
      Display.ReplConst(F.col, F.X+5, F.Y+F.H-7, 2, 2, replace)
    END
  END DrawIcon;
  
  PROCEDURE Restore* (F: Frame);
    VAR R: Texts.Reader;
  BEGIN (*F.mark = 0*)
    IF blockF = F THEN blockF := NIL; bShown := FALSE END;  (* polpo: drawn anew, a block ends *)
    Display.ReplConst(F.col, F.X, F.Y, F.W, F.H, replace);
    IF F.left >= barW THEN
      Display.ReplConst(BarColor, F.X + barW - 1, F.Y, 1, F.H, replace)
    ELSIF MoveArea THEN
      DrawIcon(F)
    END;
    Validate(F.text, F.org);
    Texts.OpenReader(R, F.text, F.org); Texts.Read(R, ch);
    F.trailer.next := F.trailer; Fill(F, F.trailer, 0, R);
    F.markH := SHORT(MulDiv(F.org , F.H, (F.text.len + 1)))
  END Restore;

  PROCEDURE Suspend* (F: Frame);
  BEGIN (*F.mark = 0*)
    F.trailer.next := F.trailer
  END Suspend;

  PROCEDURE Extend* (F: Frame; newY: INTEGER);
    VAR R: Texts.Reader; L: Line;
    org: LONGINT; curY: INTEGER;
  BEGIN (*F.mark = 0*)
    Display.ReplConst(F.col, F.X, newY, F.W, F.Y - newY, replace);
    IF F.left >= barW THEN
      Display.ReplConst(BarColor, F.X + barW - 1, newY, 1, F.Y - newY, replace)
    ELSIF MoveArea THEN
      DrawIcon(F)
    END;
    F.H := F.H + F.Y - newY; F.Y := newY;
    IF F.trailer.next = F.trailer THEN Validate(F.text, F.org) END;
    LastLine(F, L, org, curY);
    Texts.OpenReader(R, F.text, org); Texts.Read(R, ch);
    Fill(F, L, curY, R);
    F.markH := SHORT(MulDiv(F.org, F.H, (F.text.len + 1)))
  END Extend;

  PROCEDURE Reduce* (F: Frame; newY: INTEGER);
    VAR L: Line; curY, ny, top: INTEGER;
  BEGIN (*F.mark = 0*)
    F.H := F.H + F.Y - newY; F.Y := newY;
    L := F.trailer; curY := 0;
    LOOP
      IF L.next = F.trailer THEN EXIT END;
      IF L = F.trailer THEN ny := F.Y + F.H - F.top - L.next.asr ELSE ny := curY - Step(L) END;
      IF ny - L.next.dsr < F.Y + F.bot THEN EXIT END;
      L := L.next; curY := ny
    END;
    L.next := F.trailer;
    IF L = F.trailer THEN top := F.Y + F.H ELSE top := curY - L.dsr END;
    IF top > F.Y THEN
      Display.ReplConst(F.col, F.X + F.left, F.Y, F.W - F.left, top - F.Y, replace)
    END;
    F.markH := SHORT(MulDiv(F.org, F.H, (F.text.len + 1)));
    Mark(F, 1)
  END Reduce;

  PROCEDURE ShowOrg (F: Frame; pos: LONGINT);
    VAR R: Texts.Reader; L, first: Line;
      org: LONGINT; curY, botY, Y0, shift: INTEGER;
  BEGIN
    IF F.trailer.next # F.trailer THEN Validate(F.text, pos);
      IF pos < F.org THEN Mark(F, 0);
        Display.ReplConst(F.col, F.X + F.left, F.Y, F.W - F.left, F.H, replace);
        botY := F.Y; F.Y := F.Y + F.H; F.H := 0;
        F.org := pos; F.trailer.next := F.trailer; Extend(F, botY);
        Mark(F, 1)
      ELSIF pos > F.org THEN
        org := F.org; L := F.trailer.next; curY := F.Y + F.H - F.top - L.asr;
        WHILE (L.next # F.trailer) & (org # pos) DO
          org := org + L.len; curY := curY - Step(L); L := L.next
        END;
        IF org = pos THEN
          F.org := org; F.trailer.next := L; Y0 := curY; first := L;
          shift := F.Y + F.H - F.top - L.asr - Y0;  (* the new first line moves up to the top *)
          WHILE L.next # F.trailer DO
            org := org + L.len; curY := curY - Step(L); L := L.next
          END;
          Display.CopyBlock
            (F.X + F.left, curY - L.dsr, F.W - F.left, Y0 + first.asr - (curY - L.dsr),
            F.X + F.left, curY - L.dsr + shift, replace);
          curY := curY + shift;
          IF curY - L.dsr > F.Y THEN
            Display.ReplConst(F.col, F.X + F.left, F.Y, F.W - F.left, curY - L.dsr - F.Y, replace)
          END;
          org := org + L.len;
          Texts.OpenReader(R, F.text, org); Texts.Read(R, ch);
          Fill(F, L, curY, R);
          UpdateMark(F)
        ELSE Mark(F, 0);
          Display.ReplConst(F.col, F.X + F.left, F.Y, F.W - F.left, F.H, replace);
          botY := F.Y; F.Y := F.Y + F.H; F.H := 0;
          F.org := pos; F.trailer.next := F.trailer; Extend(F, botY);
          Mark(F, 1)
        END
      END
    END
  END ShowOrg;

  PROCEDURE ^LocatePos (F: Frame; pos: LONGINT; VAR loc: Location);
  PROCEDURE ^FlipSelection (F: Frame; VAR beg, end: Location);
  PROCEDURE ^HideBlock (F: Frame);
  PROCEDURE ^ShowBlock (F: Frame);

  (* polpo: loc for the selection boundary pos, which may be outside the lines shown:
     drawn at the nearest visible place, the position is kept *)
  PROCEDURE SelLoc (F: Frame; pos: LONGINT; VAR loc: Location);
  BEGIN LocatePos(F, pos, loc); loc.pos := pos
  END SelLoc;

  (** Show the text from pos on; a selection stays selected (polpo) *)
  PROCEDURE Show* (F: Frame; pos: LONGINT);
    VAR keep, keepBlock: BOOLEAN; beg, end: LONGINT;
  BEGIN
    keep := F.sel # 0; keepBlock := (blockF = F) & bShown;
    IF keep THEN beg := F.selbeg.pos; end := F.selend.pos; FlipSelection(F, F.selbeg, F.selend); F.sel := 0 END;
    IF keepBlock THEN HideBlock(F) END;
    ShowOrg(F, pos);
    IF keep THEN
      SelLoc(F, beg, F.selbeg); SelLoc(F, end, F.selend); FlipSelection(F, F.selbeg, F.selend); F.sel := 1
    END;
    IF keepBlock THEN ShowBlock(F) END
  END Show;

  PROCEDURE LocateLine (F: Frame; y: INTEGER; VAR loc: Location);
    VAR L: Line; org: LONGINT; cury: INTEGER;
  BEGIN
    org := F.org; L := F.trailer.next; cury := F.H - F.top - L.asr;
    WHILE (L.next # F.trailer) & (cury - L.dsr - Gap(L) DIV 2 > y) DO
      org := org + L.len; cury := cury - Step(L); L := L.next
    END;
    loc.org := org; loc.lin := L; loc.y := cury
  END LocateLine;

  PROCEDURE SafeGetObj (VAR R: Texts.Reader; VAR n: INTEGER; VAR obj: Objects.Object);
  VAR lib: Objects.Library; cp: LONGINT;
  BEGIN
    lib := R.lib; cp := GetCP(R, n);
    IF (lib # NIL) & (lib IS Fonts.Font) & (cp >= 0) & (cp < lib(Fonts.Font).maxRef) THEN
      lib.GetObj(lib, SHORT(cp), obj)
    ELSE obj := box
    END;
    IF ~(obj IS Fonts.Char) THEN obj := box END
  END SafeGetObj;

  PROCEDURE NextPos(text: Texts.Text; pos: LONGINT): LONGINT;
  VAR R: Texts.Reader; n: INTEGER; cp: LONGINT;
  BEGIN
    IF pos >= text.len THEN RETURN text.len END;
    Texts.OpenReader(R, text, pos); Texts.Read(R, ch); cp := GetCP(R, n);
    INC(pos, n); IF pos > text.len THEN pos := text.len END; RETURN pos
  END NextPos;

  PROCEDURE PrevPos(text: Texts.Text; pos: LONGINT): LONGINT;
  VAR R: Texts.Reader; p: LONGINT; n: INTEGER; cp: LONGINT; c: CHAR;
  BEGIN
    IF pos <= 0 THEN RETURN 0 END;
    p := pos - 1; Texts.OpenReader(R, text, p); Texts.Read(R, c);
    WHILE (p > 0) & (ORD(c) >= 080H) & (ORD(c) < 0C0H) & (pos - p < 4) DO
      DEC(p); Texts.OpenReader(R, text, p); Texts.Read(R, c)
    END;
    Texts.OpenReader(R, text, p); Texts.Read(R, ch); cp := GetCP(R, n);
    IF (cp >= 0) & (p + n = pos) THEN RETURN p ELSE RETURN pos - 1 END
  END PrevPos;

  PROCEDURE LocateString (F: Frame; x, y: INTEGER; VAR loc: Location);
    VAR R: Texts.Reader;
      bpos, pos, lim: LONGINT;
      bx, ex, ox, n: INTEGER;
      obj: Objects.Object;
  BEGIN
    LocateLine(F, y, loc);
    lim := loc.org + loc.lin.len - 1;
    bpos := loc.org; bx := F.left;
    pos := loc.org; ox := F.left;
    Texts.OpenReader(R, F.text, loc.org); Texts.Read(R, ch);
    LOOP
      LOOP (*scan string*)
        IF (pos >= lim) OR (ch <= " ") THEN EXIT END;
        SafeGetObj(R, n, obj);
        INC(pos, n); ox := ox + obj(Fonts.Char).dx; Texts.Read(R, ch)
      END;
      ex := ox;
      LOOP (*scan gap*)
        IF (pos >= lim) OR (ch > " ") THEN EXIT END;
        SafeGetObj(R, n, obj);
        INC(pos, n); ox := ox + obj(Fonts.Char).dx; Texts.Read(R, ch)
      END;
      IF (pos >= lim) OR (ox > x) THEN EXIT END;
      SafeGetObj(R, n, obj);
      bpos := pos; bx := ox;
      INC(pos, n); ox := ox + obj(Fonts.Char).dx; Texts.Read(R, ch)
    END;
    loc.pos := bpos; loc.dx := ex - bx; loc.x := bx
  END LocateString;

  PROCEDURE LocateChar (F: Frame; x, y: INTEGER; VAR loc: Location);
    VAR R: Texts.Reader;
      pos, lim: LONGINT;
      ox, dx, n: INTEGER;
      obj: Objects.Object;
  BEGIN
    LocateLine(F, y, loc);
    lim := loc.org + loc.lin.len - 1;
    pos := loc.org; ox := F.left;
    Texts.OpenReader(R, F.text, loc.org); Texts.Read(R, ch);
    LOOP
      IF pos >= lim THEN dx := eolW; EXIT END;
      SafeGetObj(R, n, obj);
      dx := obj(Fonts.Char).dx;
      IF ox + dx > x THEN EXIT END;
      INC(pos, n); ox := ox + dx; Texts.Read(R, ch)
    END;
    loc.pos := pos; loc.dx := dx; loc.x := ox
  END LocateChar;

  PROCEDURE LocatePos (F: Frame; pos: LONGINT; VAR loc: Location);
    VAR R: Texts.Reader; L: Line; org: LONGINT; cury: INTEGER;  
  BEGIN
    org := F.org; L := F.trailer.next; cury := F.H - F.top - L.asr;
    WHILE (L.next # F.trailer) & (pos >= org + L.len) DO
      org := org + L.len; cury := cury - Step(L); L := L.next
    END;
    IF pos < org THEN pos := org
      ELSIF pos >= org + L.len THEN pos := org + L.len - 1
    END;
    Texts.OpenReader(R, F.text, org); Texts.Read(R, ch);
    loc.org := org; loc.pos := pos; loc.lin := L;
    loc.x := F.left + Width(R, pos - org); loc.y := cury
  END LocatePos;

  PROCEDURE Pos* (F: Frame; X, Y: INTEGER): LONGINT;
    VAR loc: Location;
  BEGIN LocateChar(F, X - F.X, Y - F.Y, loc);
    RETURN loc.pos
  END Pos;

  PROCEDURE FlipCaret (F: Frame);
  VAR ox, oy, ow, oh: INTEGER;
  BEGIN
    IF MoveArea THEN
      Display.GetClip(ox, oy, ow, oh);
      Display.SetClip(F.X, F.Y, F.W, F.H);
      Display.CopyPattern(FullColor, Display.hook, F.X + F.carloc.x, F.Y + F.carloc.y - 10, invert);
      Display.SetClip(ox, oy, ow, oh)
    ELSE
      IF (F.carloc.y >= 10) & (F.carloc.x + 12 < F.W) THEN
        Display.CopyPattern(FullColor, Display.hook, F.X + F.carloc.x, F.Y + F.carloc.y - 10, invert)
      END
    END
  END FlipCaret;

  PROCEDURE ^RemoveMarks (F: Frame);

  PROCEDURE SetCaret* (F: Frame; pos: LONGINT);
  BEGIN
    IF hiddenF = F THEN hiddenF := NIL END;
    IF F.car # 0 THEN FlipCaret(F); F.car := 0 END;
    LocatePos(F, pos, F.carloc);
    IF F.carloc.pos = pos THEN FlipCaret(F); F.car := 1
    ELSE
      Oberon.RemoveMarks(F.X, F.Y, F.W, F.H);
      Show(F, pos - 100); LocatePos(F, pos, F.carloc);
      IF F.carloc.pos = pos THEN FlipCaret(F); F.car := 1 END
    END
  END SetCaret;

  PROCEDURE TrackCaret* (F: Frame; X, Y: INTEGER; VAR keysum: SET);
    VAR loc: Location; keys: SET;
  BEGIN
    IF F.trailer.next # F.trailer THEN
      LocateChar(F, X - F.X, Y - F.Y, F.carloc);
      FlipCaret(F);
      keysum := {};
      REPEAT
        Input.Mouse(keys, X, Y);
        keysum := keysum + keys;
        Oberon.DrawCursor(Oberon.Mouse, Oberon.Mouse.marker, X, Y);
        LocateChar(F, X - F.X, Y - F.Y, loc);
        IF loc.pos # F.carloc.pos THEN FlipCaret(F); F.carloc := loc; FlipCaret(F) END
      UNTIL keys = {};
      F.car := 1
    END
  END TrackCaret;

  PROCEDURE RemoveCaret* (F: Frame);
  BEGIN IF F.car # 0 THEN FlipCaret(F); F.car := 0 END
  END RemoveCaret;

  PROCEDURE FlipSelection (F: Frame; VAR beg, end: Location);
    VAR L: Line; Y: INTEGER;
  BEGIN
    L := beg.lin; Y := F.Y + beg.y;  (* baselines; a line is selected from its descent to its ascent *)
    IF L = end.lin THEN
      ReplConst(FullColor, F, F.X + beg.x, Y - L.dsr, end.x - beg.x, L.asr + L.dsr, invert)
    ELSE
      ReplConst(FullColor, F, F.X + beg.x, Y - L.dsr, F.left + L.wid - beg.x, L.asr + L.dsr, invert);
      LOOP
        IF L.next = F.trailer THEN EXIT END;
        Y := Y - Step(L); L := L.next;
        IF L = end.lin THEN EXIT END;
        ReplConst(FullColor, F, F.X + F.left, Y - L.dsr, L.wid, L.asr + L.dsr, invert)
      END;
      IF L = end.lin THEN ReplConst(FullColor, F, F.X + F.left, Y - L.dsr, end.x - F.left, L.asr + L.dsr, invert) END
    END
  END FlipSelection;

  PROCEDURE SetSelection* (F: Frame; beg, end: LONGINT);
  BEGIN
    IF end <= beg THEN end := NextPos(F.text, beg) END;
    IF F.sel # 0 THEN FlipSelection(F, F.selbeg, F.selend); F.sel := 0 END;
    LocatePos(F, beg, F.selbeg); LocatePos(F, end, F.selend);
    IF (F.selbeg.pos # beg) & (F.selend.pos # end) THEN Show(F, beg) END;  (* polpo: nothing of it visible *)
    SelLoc(F, beg, F.selbeg); SelLoc(F, end, F.selend);
    FlipSelection(F, F.selbeg, F.selend); F.time := Input.Time(); F.sel := 1;
  END SetSelection;

  PROCEDURE TrackSelection* (F: Frame; X, Y: INTEGER; VAR keysum: SET);
    VAR loc: Location; modKeys, keys: SET; M: Oberon.SelectMsg; b, e, p, nb, ne: LONGINT;
  BEGIN
    Input.KeyState(modKeys);
    IF (Input.SHIFT IN modKeys) & (F.trailer.next # F.trailer) & ((F.sel # 0) OR (F.car # 0) OR (hiddenF = F)) THEN
      (* polpo: extend the selection to the mouse, or select from the caret, like xterm *)
      IF F.sel # 0 THEN b := F.selbeg.pos; e := F.selend.pos
      ELSIF F.car # 0 THEN b := F.carloc.pos; e := b
      ELSE b := hiddenPos; e := b
      END;
      anchorF := NIL; keysum := {};
      REPEAT
        Input.Mouse(keys, X, Y); keysum := keysum + keys;
        Oberon.DrawCursor(Oberon.Mouse, Oberon.Mouse.marker, X, Y);
        LocateChar(F, X - F.X, Y - F.Y, loc); p := loc.pos;
        IF p < b THEN nb := p; ne := e ELSE nb := b; ne := NextPos(F.text, p); IF ne < e THEN ne := e END END;
        IF (F.sel = 0) OR (nb # F.selbeg.pos) OR (ne # F.selend.pos) THEN
          IF F.sel # 0 THEN FlipSelection(F, F.selbeg, F.selend) END;
          SelLoc(F, nb, F.selbeg); SelLoc(F, ne, F.selend); FlipSelection(F, F.selbeg, F.selend); F.sel := 1
        END
      UNTIL keys = {};
      F.time := Input.Time(); F.sel := 1;
      RETURN
    END;
      IF F.trailer.next # F.trailer THEN
      IF F.sel # 0 THEN FlipSelection(F, F.selbeg, F.selend) END;
      LocateChar(F, X - F.X, Y - F.Y, loc);
      IF (F.sel # 0) & (loc.pos = F.selbeg.pos)
          & (F.selend.pos = NextPos(F.text, F.selbeg.pos)) THEN
        LocateChar(F, F.left, Y - F.Y, F.selbeg)
      ELSE F.selbeg := loc
      END;
      F.sel := 0;
      loc.pos := NextPos(F.text, loc.pos); loc.x := loc.x + loc.dx; F.selend := loc;
      FlipSelection(F, F.selbeg, F.selend);
        keysum := {};
      REPEAT 
          Input.Mouse(keys, X, Y);
        keysum := keysum + keys;
        Oberon.DrawCursor(Oberon.Mouse, Oberon.Mouse.marker, X, Y);
        LocateChar(F, X - F.X, Y - F.Y, loc);
        IF loc.pos < F.selbeg.pos THEN loc := F.selbeg END;
        loc.pos := NextPos(F.text, loc.pos); loc.x := loc.x + loc.dx;
        IF loc.pos < F.selend.pos THEN FlipSelection(F, loc, F.selend); F.selend := loc
        ELSIF loc.pos > F.selend.pos THEN FlipSelection(F, F.selend, loc); F.selend := loc
        END
      UNTIL keys = {};
       (* ps - 3.4.98 *)
        Input.KeyState(modKeys);
        IF Input.SHIFT IN modKeys THEN
          M.id := Oberon.get; M.F := NIL; M.sel := NIL; M.text := NIL; M.time := -1; Display.Broadcast(M);
          IF (M.time # -1) & (M.text = F.text) & (M.sel IS Frame) THEN
            IF M.beg > F.selbeg.pos THEN M.beg := F.selbeg.pos END;
            IF M.end < F.selend.pos THEN M.end := F.selend.pos END;
            FlipSelection(F, F.selbeg, F.selend);
            LocatePos(F, M.beg, F.selbeg); LocatePos(F, M.end, F.selend);
            FlipSelection(F, F.selbeg, F.selend);
            M.F := M.sel; M.id := Oberon.set; Display.Broadcast(M)
          END
        END;
        F.time := Input.Time(); F.sel := 1
      END;
  END TrackSelection;

  PROCEDURE RemoveSelection* (F: Frame);
  BEGIN IF F.sel # 0 THEN FlipSelection(F, F.selbeg, F.selend); F.sel := 0 END
  END RemoveSelection;

  PROCEDURE TrackLine* (F: Frame; X, Y: INTEGER; VAR org: LONGINT; VAR keysum: SET);
    VAR old, new: Location; keys: SET;
  BEGIN
        IF F.trailer.next # F.trailer THEN
        LocateLine(F, Y - F.Y, old);
        ReplConst(FullColor, F, F.X + F.left, F.Y + old.y - old.lin.dsr, old.lin.wid, 2, invert);
          keysum := {};
        REPEAT
          Input.Mouse(keys, X, Y);
          keysum := keysum + keys;
            Oberon.DrawCursor(Oberon.Mouse, Oberon.Mouse.marker, X, Y);
          LocateLine(F, Y - F.Y, new);
          IF new.org # old.org THEN
            ReplConst(FullColor, F, F.X + F.left, F.Y + old.y - old.lin.dsr, old.lin.wid, 2, invert);
            ReplConst(FullColor, F, F.X + F.left, F.Y + new.y - new.lin.dsr, new.lin.wid, 2, invert);
            old := new
          END
        UNTIL keys = {};
        ReplConst(FullColor, F, F.X + F.left, F.Y + new.y - new.lin.dsr, new.lin.wid, 2, invert);
        org := new.org
        ELSE org := -1
        END
  END TrackLine;

  PROCEDURE TrackWord* (F: Frame; X, Y: INTEGER; VAR pos: LONGINT; VAR keysum: SET);
    VAR old, new: Location; keys: SET;
  BEGIN
    IF F.trailer.next # F.trailer THEN
    LocateString(F, X - F.X, Y - F.Y, old);
    ReplConst(FullColor, F, F.X + old.x, F.Y + old.y - old.lin.dsr, old.dx, 2, invert);
      keysum := {};
      REPEAT
      Input.Mouse(keys, X, Y);
    keysum := keysum + keys;
      Oberon.DrawCursor(Oberon.Mouse, Oberon.Mouse.marker, X, Y);
      LocateString(F, X - F.X, Y - F.Y, new);
      IF new.pos # old.pos THEN
        ReplConst(FullColor, F, F.X + old.x, F.Y + old.y - old.lin.dsr, old.dx, 2, invert);
        ReplConst(FullColor, F, F.X + new.x, F.Y + new.y - new.lin.dsr, new.dx, 2, invert);
        old := new
      END
    UNTIL keys = {};
    ReplConst(FullColor, F, F.X + new.x, F.Y + new.y - new.lin.dsr, new.dx, 2, invert);
    pos := new.pos; hintPos := new.org
    ELSE pos := -1
    END
  END TrackWord;

  (*------------------message handling------------------------*)

  PROCEDURE RemoveMarks (F: Frame);
  BEGIN
    RemoveCaret(F); RemoveSelection(F);
    HideBlock(F); IF ~bBusy & (blockF = F) THEN blockF := NIL END  (* polpo: a block ends unless it changes the text itself *)
  END RemoveMarks;

  PROCEDURE GetAttr* (F: Frame; VAR s: ARRAY OF CHAR);
    VAR S: Texts.Scanner;
  BEGIN Texts.OpenScanner(S, F.text, 0); Texts.Scan(S); COPY(S.s, s)
  END GetAttr;

  PROCEDURE CallCmd (cmd: ARRAY OF CHAR; F: Frame; pos: LONGINT; new: BOOLEAN);
    VAR res: INTEGER; par: Oberon.ParList;
  BEGIN
    NEW(par); par.vwr := Viewers.This(F.X, F.Y);
    par.frame := F; par.text := F.text; par.pos := pos;
    Oberon.Call(cmd, par, new, res);
    IF res > 0 THEN
      Texts.WriteString(W, "Call error: ");
      Texts.WriteString(W, Modules.resMsg);
      Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
    END
  END CallCmd;

  PROCEDURE Call* (F: Frame; pos: LONGINT; new: BOOLEAN);
    VAR S: Texts.Scanner; i, h: INTEGER; hint: ARRAY 32 OF CHAR;
  BEGIN
    IF SmallDisplay THEN
      Texts.OpenScanner(S, F.text, pos); Texts.Scan(S); h := 0;
      IF ((S.class = Texts.Char) & (S.c = ".") OR (S.class = Texts.Name) & (S.s[0] = ".")) THEN
        (*find hint*)
        Texts.OpenScanner(S, F.text, hintPos);
        REPEAT
          Texts.Scan(S);
          IF S.class = Texts.Name THEN
            i := 0; WHILE (i < S.len) & (S.s[i] # ".") DO INC(i) END;
            IF (0 < i) & (i < S.len) THEN
              h := 0; REPEAT hint[h] := S.s[h]; INC(h) UNTIL h > i
            END
          END
        UNTIL Texts.Pos(S) > pos;
        IF (S.class = Texts.Char) & (S.c = ".") THEN Texts.Scan(S) END
      END;
      IF S.class = Texts.Name THEN
        IF h > 1 THEN  (*use hint*)
          i := S.len; IF S.s[0] = "." THEN DEC(h) END;
          REPEAT S.s[i+h] := S.s[i]; DEC(i) UNTIL (i = -1) OR (S.s[i+1] = ".");
          REPEAT DEC(h); S.s[h] := hint[h] UNTIL h = 0
        END;
        CallCmd(S.s, F, pos + S.len, new)
      END
    ELSE
      Texts.OpenScanner(S, F.text, pos); Texts.Scan(S);
      IF (S.line = 0) & (S.class = Texts.Name) THEN CallCmd(S.s, F, pos + S.len, new) END
    END
  END Call;

  (* ----- polpo: keyboard editing ----- *)

  PROCEDURE LineStart (T: Texts.Text; pos: LONGINT): LONGINT;
    VAR R: Texts.Reader; c: CHAR;
  BEGIN
    WHILE pos > 0 DO
      Texts.OpenReader(R, T, pos - 1); Texts.Read(R, c);
      IF c = CR THEN RETURN pos END;
      DEC(pos)
    END;
    RETURN 0
  END LineStart;

  PROCEDURE LineEnd (T: Texts.Text; pos: LONGINT): LONGINT;
    VAR R: Texts.Reader; c: CHAR;
  BEGIN
    Texts.OpenReader(R, T, pos); Texts.Read(R, c);
    WHILE ~R.eot & (c # CR) DO INC(pos); Texts.Read(R, c) END;
    RETURN pos
  END LineEnd;

  PROCEDURE Lines (F: Frame): INTEGER;  (* number of lines shown *)
    VAR L: Line; n: INTEGER;
  BEGIN
    n := 0; L := F.trailer.next;
    WHILE L # F.trailer DO INC(n); L := L.next END;
    RETURN n
  END Lines;

  (* ----- polpo: block selection ----- *)

  PROCEDURE LineNoAt (T: Texts.Text; pos: LONGINT): LONGINT;  (* the line of pos, from 0 *)
    VAR R: Texts.Reader; c: CHAR; n, p: LONGINT;
  BEGIN
    n := 0; p := 0; Texts.OpenReader(R, T, 0);
    WHILE p < pos DO Texts.Read(R, c); IF c = CR THEN INC(n) END; INC(p) END;
    RETURN n
  END LineNoAt;

  PROCEDURE LineStartNo (T: Texts.Text; n: LONGINT): LONGINT;  (* the start of line n, -1 beyond the end *)
    VAR p: LONGINT;
  BEGIN
    p := 0;
    WHILE (n > 0) & (p >= 0) DO p := LineEnd(T, p); IF p < T.len THEN INC(p) ELSE p := -1 END; DEC(n) END;
    RETURN p
  END LineStartNo;

  (* the position in the line starting at ls whose left edge is nearest to x (frame relative), and
     that edge in px; the line end if x lies beyond it *)
  PROCEDURE PosAtX (F: Frame; ls: LONGINT; x: INTEGER; VAR px: INTEGER): LONGINT;
    VAR R: Texts.Reader; pos: LONGINT; ox, dx, n: INTEGER; obj: Objects.Object;
  BEGIN
    pos := ls; ox := F.left;
    Texts.OpenReader(R, F.text, ls); Texts.Read(R, ch);
    LOOP
      IF R.eot OR (ch = CR) THEN EXIT END;
      SafeGetObj(R, n, obj); dx := obj(Fonts.Char).dx;
      IF ox + dx DIV 2 > x THEN EXIT END;
      INC(pos, n); ox := ox + dx; Texts.Read(R, ch)
    END;
    px := ox; RETURN pos
  END PosAtX;

  (* the x (frame relative) of the left edge of pos in its line *)
  PROCEDURE XAtPos (F: Frame; pos: LONGINT): INTEGER;
    VAR R: Texts.Reader; ls: LONGINT;
  BEGIN
    ls := LineStart(F.text, pos);
    Texts.OpenReader(R, F.text, ls); Texts.Read(R, ch);
    RETURN F.left + Width(R, pos - ls)
  END XAtPos;

  PROCEDURE EndX (F: Frame; ls: LONGINT): INTEGER;  (* the x of the end of the line starting at ls *)
  BEGIN RETURN XAtPos(F, LineEnd(F.text, ls))
  END EndX;

  (* the block of F: its first and last line, its columns l to r *)
  PROCEDURE BlockArea (F: Frame; VAR first, last: LONGINT; VAR l, r: INTEGER);
    VAR cl: LONGINT;
  BEGIN
    cl := LineNoAt(F.text, F.carloc.pos);
    IF bAnLn <= cl THEN first := bAnLn; last := cl ELSE first := cl; last := bAnLn END;
    IF bAnX <= bCarX THEN l := bAnX; r := bCarX ELSE l := bCarX; r := bAnX END
  END BlockArea;

  (* invert the block where it is shown; a block of width 0 is a thin bar on the lines that reach it *)
  PROCEDURE FlipBlock (F: Frame);
    VAR L: Line; org, ln, first, last, b: LONGINT; y, l, r, bx, ex: INTEGER;
  BEGIN
    BlockArea(F, first, last, l, r);
    org := F.org; L := F.trailer.next; y := F.Y + F.H - F.top - L.asr; ln := LineNoAt(F.text, F.org);
    WHILE L # F.trailer DO
      IF (ln >= first) & (ln <= last) THEN
        IF l < r THEN
          b := PosAtX(F, org, l, bx); b := PosAtX(F, org, r, ex);
          IF ex > bx THEN ReplConst(FullColor, F, F.X + bx, y - L.dsr, ex - bx, L.asr + L.dsr, invert) END
        ELSIF EndX(F, org) >= l THEN
          b := PosAtX(F, org, l, bx);
          ReplConst(FullColor, F, F.X + bx, y - L.dsr, 2, L.asr + L.dsr, invert)
        END
      END;
      org := org + L.len; y := y - Step(L); L := L.next; INC(ln)
    END
  END FlipBlock;

  PROCEDURE ShowBlock (F: Frame);
  BEGIN
    IF (blockF = F) & ~bShown THEN Oberon.RemoveMarks(F.X, F.Y, F.W, F.H); FlipBlock(F); bShown := TRUE END
  END ShowBlock;

  PROCEDURE HideBlock (F: Frame);
  BEGIN
    IF (blockF = F) & bShown THEN Oberon.RemoveMarks(F.X, F.Y, F.W, F.H); FlipBlock(F); bShown := FALSE END
  END HideBlock;

  PROCEDURE EndBlock;
  BEGIN IF blockF # NIL THEN HideBlock(blockF); blockF := NIL END
  END EndBlock;

  (* the width of c in the font lib *)
  PROCEDURE CharW (lib: Objects.Library; c: CHAR): INTEGER;
    VAR obj: Objects.Object;
  BEGIN
    IF (lib = NIL) OR ~(lib IS Fonts.Font) THEN lib := Fonts.Default END;
    lib.GetObj(lib, ORD(c), obj);
    IF (obj # NIL) & (obj IS Fonts.Char) & (obj(Fonts.Char).dx > 0) THEN RETURN obj(Fonts.Char).dx END;
    RETURN 4
  END CharW;

  (* the width of a blank in the looks the caret writes with *)
  PROCEDURE BlankW (lib: Objects.Library): INTEGER;
  BEGIN RETURN CharW(lib, " ")
  END BlankW;

  (* the caret of the block to line ln, column x (beyond the line end too) *)
  PROCEDURE BlockCaret (F: Frame; ln: LONGINT; x: INTEGER);
    VAR ls: LONGINT; px: INTEGER;
  BEGIN
    IF x < F.left THEN x := F.left END;
    ls := LineStartNo(F.text, ln);
    IF ls >= 0 THEN bCarX := x; RemoveCaret(F); SetCaret(F, PosAtX(F, ls, x, px)) END
  END BlockCaret;

  (* delete the columns of the block on its lines; it keeps width 0 at its left column *)
  PROCEDURE DeleteBlock (F: Frame);
    VAR first, last, ln, ls, b, e, cl: LONGINT; l, r, bx, ex: INTEGER;
  BEGIN
    BlockArea(F, first, last, l, r); cl := LineNoAt(F.text, F.carloc.pos);
    ln := first;
    WHILE ln <= last DO
      ls := LineStartNo(F.text, ln);
      IF ls >= 0 THEN
        b := PosAtX(F, ls, l, bx); e := PosAtX(F, ls, r, ex);
        IF e > b THEN Texts.Delete(F.text, b, e) END
      END;
      INC(ln)
    END;
    bAnX := l; BlockCaret(F, cl, l)
  END DeleteBlock;

  (* type ch into every line of the block that reaches its column, after deleting its columns *)
  PROCEDURE BlockType (F: Frame; ch1: CHAR; lib: Objects.Library; col, voff: SHORTINT);
    VAR first, last, ln, ls, p, cl: LONGINT; l, r, px: INTEGER;
  BEGIN
    BlockArea(F, first, last, l, r);
    IF l < r THEN DeleteBlock(F); BlockArea(F, first, last, l, r) END;
    cl := LineNoAt(F.text, F.carloc.pos);
    ln := first;
    WHILE ln <= last DO
      ls := LineStartNo(F.text, ln);
      IF (ls >= 0) & (EndX(F, ls) >= l) THEN
        p := PosAtX(F, ls, l, px);
        KW.lib := lib; KW.col := col; KW.voff := voff; Texts.Write(KW, ch1); Texts.Insert(F.text, p, KW.buf)
      END;
      INC(ln)
    END;
    (* every line moved its column by the width of ch1: the nearest boundary to l + w is the one
       after the inserted character on each of them (proportional fonts) *)
    bAnX := l + CharW(lib, ch1); BlockCaret(F, cl, bAnX)
  END BlockType;

  (* Backspace (back) or Delete in a block of width 0: the character before or at its column *)
  PROCEDURE BlockErase (F: Frame; back: BOOLEAN);
    VAR first, last, ln, ls, p, cl: LONGINT; l, r, px, w: INTEGER;
  BEGIN
    BlockArea(F, first, last, l, r); cl := LineNoAt(F.text, F.carloc.pos);
    ls := LineStartNo(F.text, cl); p := PosAtX(F, ls, l, px); w := 0;  (* the width taken out on the caret's line *)
    IF back & (p > ls) THEN w := px - XAtPos(F, PrevPos(F.text, p)) END;
    ln := first;
    WHILE ln <= last DO
      ls := LineStartNo(F.text, ln);
      IF (ls >= 0) & (EndX(F, ls) >= l) THEN
        p := PosAtX(F, ls, l, px);
        IF back & (p > ls) THEN Texts.Delete(F.text, PrevPos(F.text, p), p)
        ELSIF ~back & (p < LineEnd(F.text, ls)) THEN Texts.Delete(F.text, p, NextPos(F.text, p))
        END
      END;
      INC(ln)
    END;
    bAnX := l - w; BlockCaret(F, cl, bAnX)
  END BlockErase;

  (* the block into blockClip and to the clipboard of X, rows joined by line ends *)
  PROCEDURE CopyBlock (F: Frame);
    VAR first, last, ln, ls, b, e, i: LONGINT; l, r, bx, ex: INTEGER; buf: Texts.Buffer;
      R: Texts.Reader; s: POINTER TO ARRAY OF CHAR;
  BEGIN
    BlockArea(F, first, last, l, r);
    NEW(blockClip); Texts.Open(blockClip, "");
    ln := first;
    WHILE ln <= last DO
      ls := LineStartNo(F.text, ln);
      IF ls >= 0 THEN
        b := PosAtX(F, ls, l, bx); e := PosAtX(F, ls, r, ex);
        IF e > b THEN NEW(buf); Texts.OpenBuf(buf); Texts.Save(F.text, b, e, buf); Texts.Append(blockClip, buf) END
      END;
      IF ln < last THEN Texts.Write(KW, CR); Texts.Append(blockClip, KW.buf) END;
      INC(ln)
    END;
    clipBuf := NIL;
    IF blockClip.len > 0 THEN
      NEW(s, blockClip.len); Texts.OpenReader(R, blockClip, 0); i := 0;
      WHILE i < blockClip.len DO Texts.Read(R, s[i]); IF s[i] = CR THEN s[i] := 0AX END; INC(i) END;
      Input.SetClipboard(s^, blockClip.len)
    END
  END CopyBlock;

  (* blockClip into the lines from the caret's on, at the caret's column; lines are lengthened
     with blanks and added at the end as needed *)
  PROCEDURE PasteBlock (F: Frame);
    VAR R: Texts.Reader; c: CHAR; x, w: INTEGER; ln, ls, p, rowEnd: LONGINT; buf: Texts.Buffer; px: INTEGER;
  BEGIN
    x := F.carloc.x; ln := LineNoAt(F.text, F.carloc.pos); p := 0;
    WHILE p <= blockClip.len DO
      rowEnd := p; Texts.OpenReader(R, blockClip, p); Texts.Read(R, c);
      WHILE ~R.eot & (c # CR) DO INC(rowEnd); Texts.Read(R, c) END;
      ls := LineStartNo(F.text, ln);
      IF ls < 0 THEN Texts.Write(KW, CR); Texts.Insert(F.text, F.text.len, KW.buf); ls := LineStartNo(F.text, ln) END;
      w := BlankW(KW.lib);
      WHILE EndX(F, ls) + w DIV 2 <= x DO Texts.Write(KW, " "); Texts.Insert(F.text, LineEnd(F.text, ls), KW.buf) END;
      IF rowEnd > p THEN
        NEW(buf); Texts.OpenBuf(buf); Texts.Save(blockClip, p, rowEnd, buf);
        Texts.Insert(F.text, PosAtX(F, ls, x, px), buf)
      END;
      p := rowEnd + 1; INC(ln)
    END
  END PasteBlock;

  (* the keys of a block: TRUE if ch was one *)
  PROCEDURE BlockKey (F: Frame; ch1: CHAR; lib: Objects.Library; col, voff: SHORTINT): BOOLEAN;
    VAR ln, ls, cl: LONGINT; n: INTEGER;
  BEGIN
    IF (ch1 = 7FX) OR (ch1 = 0A1X) OR (ch1 = 09X) OR (ch1 >= " ") & (ch1 < 7FX) OR (ch1 >= 80X) & (ch1 < 0A0X) OR
       (ch1 >= 0AAX) & (ch1 < 0C1X) OR (ch1 > 0C4X) & (ch1 < 0F0X) THEN
      bBusy := TRUE; HideBlock(F); bMarking := FALSE;
      IF ((ch1 = 7FX) OR (ch1 = 0A1X)) & (bAnX = bCarX) THEN BlockErase(F, ch1 = 7FX)
      ELSIF (ch1 = 7FX) OR (ch1 = 0A1X) THEN DeleteBlock(F)
      ELSE BlockType(F, ch1, lib, col, voff)
      END;
      bBusy := FALSE; ShowBlock(F); RETURN TRUE
    END;
    cl := LineNoAt(F.text, F.carloc.pos);
    IF bMarking & ((ch1 = 0C1X) OR (ch1 = 0C2X) OR (ch1 = 0C3X) OR (ch1 = 0C4X) OR (ch1 = 0A8X) OR (ch1 = 0A9X) OR
       (ch1 = 0A2X) OR (ch1 = 0A3X)) THEN
      bBusy := TRUE; HideBlock(F);
      IF ch1 = 0C1X THEN IF cl > 0 THEN BlockCaret(F, cl - 1, bCarX) END  (* up *)
      ELSIF ch1 = 0C2X THEN IF LineStartNo(F.text, cl + 1) >= 0 THEN BlockCaret(F, cl + 1, bCarX) END  (* down *)
      ELSIF ch1 = 0C3X THEN  (* right: the next character, past the end by blanks *)
        ls := LineStart(F.text, F.carloc.pos);
        IF (F.carloc.pos < LineEnd(F.text, ls)) & (bCarX <= F.carloc.x) THEN BlockCaret(F, cl, XAtPos(F, NextPos(F.text, F.carloc.pos)))
        ELSE BlockCaret(F, cl, bCarX + BlankW(lib))
        END
      ELSIF ch1 = 0C4X THEN  (* left *)
        IF bCarX > EndX(F, LineStart(F.text, F.carloc.pos)) THEN BlockCaret(F, cl, bCarX - BlankW(lib))
        ELSIF F.carloc.pos > LineStart(F.text, F.carloc.pos) THEN BlockCaret(F, cl, XAtPos(F, PrevPos(F.text, F.carloc.pos)))
        END
      ELSIF ch1 = 0A8X THEN BlockCaret(F, cl, F.left)  (* Home *)
      ELSIF ch1 = 0A9X THEN BlockCaret(F, cl, EndX(F, LineStart(F.text, F.carloc.pos)))  (* End *)
      ELSE  (* Page Up, Page Down *)
        n := Lines(F) - 1; IF n < 1 THEN n := 1 END; ln := cl;
        IF ch1 = 0A2X THEN ln := ln - n; IF ln < 0 THEN ln := 0 END
        ELSE WHILE (n > 0) & (LineStartNo(F.text, ln + 1) >= 0) DO INC(ln); DEC(n) END
        END;
        BlockCaret(F, ln, bCarX)
      END;
      bBusy := FALSE; ShowBlock(F); RETURN TRUE
    END;
    IF ch1 = 03X THEN CopyBlock(F); bMarking := FALSE; RETURN TRUE  (* Ctrl+C *)
    ELSIF ch1 = 18X THEN  (* Ctrl+X *)
      CopyBlock(F); bBusy := TRUE; HideBlock(F); DeleteBlock(F); bBusy := FALSE; EndBlock; RETURN TRUE
    END;
    EndBlock; RETURN FALSE  (* any other key ends the block and does its work *)
  END BlockKey;


  (* move the caret to pos; with shift the selection runs from the anchor to pos *)
  PROCEDURE MoveCaret (F: Frame; pos: LONGINT; shift: BOOLEAN);
    VAR old: LONGINT;
  BEGIN
    old := F.carloc.pos;
    IF pos < 0 THEN pos := 0 ELSIF pos > F.text.len THEN pos := F.text.len END;
    IF shift THEN
      IF (anchorF # F) OR (F.sel = 0) THEN anchorF := F; anchorPos := old END
    ELSIF anchorF = F THEN RemoveSelection(F); anchorF := NIL
    END;
    RemoveCaret(F); SetCaret(F, pos);
    IF shift THEN
      IF pos < anchorPos THEN SetSelection(F, pos, anchorPos)
      ELSIF pos > anchorPos THEN SetSelection(F, anchorPos, pos)
      ELSE RemoveSelection(F)
      END
    END
  END MoveCaret;

  (* baseline (relative to F.Y) of the line shown before L *)
  PROCEDURE PrevBase (F: Frame; L: Line): INTEGER;
    VAR P: Line; y, py: INTEGER;
  BEGIN
    P := F.trailer.next; y := F.H - F.top - P.asr; py := y;
    WHILE (P # L) & (P # F.trailer) DO py := y; y := y - Step(P); P := P.next END;
    RETURN py
  END PrevBase;

  (* the caret one line up (dir = 1) or down (dir = -1), in the same column; scrolls at the edges *)
  PROCEDURE MoveLine (F: Frame; dir: INTEGER; shift: BOOLEAN);
    VAR loc: Location; x, y, n: INTEGER; pos, org: LONGINT;
  BEGIN
    IF goalF # F THEN goalF := F; goalX := F.carloc.x END;
    x := goalX; pos := F.carloc.pos;
    IF dir > 0 THEN
      IF F.carloc.lin = F.trailer.next THEN  (* first line shown *)
        IF F.org = 0 THEN MoveCaret(F, 0, shift); RETURN END;
        org := LineStart(F.text, F.org - 1);
        RemoveCaret(F); Oberon.RemoveMarks(F.X, F.Y, F.W, F.H);
        Show(F, org); LocatePos(F, pos, F.carloc)
      END;
      y := PrevBase(F, F.carloc.lin)
    ELSE
      n := 0;
      WHILE (F.carloc.lin.next = F.trailer) & ~F.carloc.lin.eot & (n < 4) DO  (* last line shown *)
        RemoveCaret(F); Oberon.RemoveMarks(F.X, F.Y, F.W, F.H);
        Show(F, F.org + F.trailer.next.len); LocatePos(F, pos, F.carloc); INC(n)
      END;
      IF F.carloc.lin.next = F.trailer THEN MoveCaret(F, F.text.len, shift); RETURN END;
      y := F.carloc.y - Step(F.carloc.lin)
    END;
    LocateChar(F, x, y, loc);
    MoveCaret(F, loc.pos, shift)
  END MoveLine;

  (* one page up (dir = 1) or down (dir = -1), the caret stays on its row *)
  PROCEDURE MovePage (F: Frame; dir: INTEGER; shift: BOOLEAN);
    VAR loc: Location; n: INTEGER; org: LONGINT; x, y: INTEGER; L: Line;
  BEGIN
    x := F.carloc.x; y := F.carloc.y; n := Lines(F) - 1; IF n < 1 THEN n := 1 END;
    org := F.org;
    IF dir > 0 THEN
      IF org = 0 THEN MoveCaret(F, 0, shift); RETURN END;
      WHILE (n > 0) & (org > 0) DO org := LineStart(F.text, org - 1); DEC(n) END
    ELSE
      L := F.trailer.next;
      WHILE (n > 0) & (L.next # F.trailer) DO org := org + L.len; L := L.next; DEC(n) END;
      IF L.eot & (org = F.org) THEN MoveCaret(F, F.text.len, shift); RETURN END
    END;
    RemoveCaret(F); Oberon.RemoveMarks(F.X, F.Y, F.W, F.H);
    Show(F, org); LocateChar(F, x, y, loc);
    MoveCaret(F, loc.pos, shift)
  END MovePage;

  (* Ctrl+C: copy the selection to the clipboard, and offer it to other programs *)
  PROCEDURE CopySelection (): BOOLEAN;
    VAR text: Texts.Text; beg, end, time, i: LONGINT; R: Texts.Reader; s: POINTER TO ARRAY OF CHAR;
  BEGIN
    Oberon.GetSelection(text, beg, end, time);
    IF (time < 0) OR (end <= beg) THEN RETURN FALSE END;
    NEW(clipBuf); Texts.OpenBuf(clipBuf); Texts.Save(text, beg, end, clipBuf); blockClip := NIL;
    NEW(s, end - beg); Texts.OpenReader(R, text, beg); i := 0;
    WHILE i < end - beg DO
      Texts.Read(R, s[i]); IF s[i] = CR THEN s[i] := 0AX END; INC(i)
    END;
    Input.SetClipboard(s^, end - beg);
    RETURN TRUE
  END CopySelection;

  (* Ctrl+V: insert the clipboard at the caret; text copied in another program comes from X *)
  PROCEDURE PasteClipboard (F: Frame);
    VAR buf: Texts.Buffer; pos: LONGINT;
  BEGIN
    IF Input.RequestClipboard() THEN RETURN END;  (* arrives later as typed characters *)
    IF blockClip # NIL THEN PasteBlock(F)
    ELSIF clipBuf # NIL THEN
      NEW(buf); Texts.OpenBuf(buf); Texts.Copy(clipBuf, buf);
      pos := F.carloc.pos + buf.len;
      Texts.Insert(F.text, F.carloc.pos, buf); SetCaret(F, pos)
    END
  END PasteClipboard;

  (* polpo: Tab after a word completes it (TextComplete); FALSE: nothing to complete, a Tab is wanted *)
  PROCEDURE Completed (F: Frame; lib: Objects.Library; col, voff: SHORTINT): BOOLEAN;
    VAR n: LONGINT;
  BEGIN
    KW.lib := lib; KW.col := col; KW.voff := voff;
    n := TextComplete.Word(F.text, F.carloc.pos, KW);
    IF n > 0 THEN SetCaret(F, F.carloc.pos + n) END;
    RETURN n >= 0
  END Completed;

  PROCEDURE Write* (F: Frame; ch: CHAR; lib: Objects.Library; col, voff: SHORTINT);
  VAR pos, beg, end, time: LONGINT; keys: SET; shift, ctrl: BOOLEAN; text: Texts.Text;
  BEGIN (*F.car # 0*)
    Input.KeyState(keys); shift := Input.SHIFT IN keys; ctrl := Input.CTRL IN keys;
    IF ch = 02X THEN  (* polpo: Ctrl+B starts a block (a selection made with Shift becomes one), or ends it *)
      IF blockF = F THEN EndBlock
      ELSE
        EndBlock; bAnLn := LineNoAt(F.text, F.carloc.pos); bAnX := F.carloc.x;
        IF (anchorF = F) & (F.sel # 0) THEN bAnLn := LineNoAt(F.text, anchorPos); bAnX := XAtPos(F, anchorPos) END;
        RemoveSelection(F); anchorF := NIL;
        bCarX := F.carloc.x; blockF := F; bShown := FALSE; bMarking := TRUE; ShowBlock(F)
      END;
      RETURN
    END;
    IF (blockF = F) & BlockKey(F, ch, lib, col, voff) THEN RETURN END;
    IF (ch # 0C1X) & (ch # 0C2X) THEN goalF := NIL END;
    IF (ch = 7FX) OR (ch = 0A1X) THEN  (* a selection made with the keyboard is deleted as a whole *)
      IF (anchorF = F) & (F.sel # 0) THEN
        beg := F.selbeg.pos; end := F.selend.pos; RemoveSelection(F); anchorF := NIL;
        Texts.Delete(F.text, beg, end); SetCaret(F, beg); RETURN
      END
    END;
    IF ch = 0C1X THEN MoveLine(F, 1, shift)  (* up *)
    ELSIF ch = 0C2X THEN MoveLine(F, -1, shift)  (* down *)
    ELSIF (ch = 0C3X) & shift THEN MoveCaret(F, NextPos(F.text, F.carloc.pos), TRUE)
    ELSIF (ch = 0C4X) & shift THEN MoveCaret(F, PrevPos(F.text, F.carloc.pos), TRUE)
    ELSIF ch = 0A8X THEN  (* Home, Ctrl+Home *)
      IF ctrl THEN MoveCaret(F, 0, shift) ELSE MoveCaret(F, LineStart(F.text, F.carloc.pos), shift) END
    ELSIF ch = 0A9X THEN  (* End, Ctrl+End *)
      IF ctrl THEN MoveCaret(F, F.text.len, shift) ELSE MoveCaret(F, LineEnd(F.text, F.carloc.pos), shift) END
    ELSIF ch = 0A2X THEN MovePage(F, 1, shift)  (* Page Up *)
    ELSIF ch = 0A3X THEN MovePage(F, -1, shift)  (* Page Down *)
    ELSIF ch = 01X THEN  (* Ctrl+A: select all *)
      IF F.text.len > 0 THEN anchorF := NIL; SetSelection(F, 0, F.text.len) END
    ELSIF ch = 03X THEN  (* Ctrl+C *)
      IF CopySelection() THEN END
    ELSIF ch = 18X THEN  (* Ctrl+X *)
      IF CopySelection() THEN
        Oberon.GetSelection(text, beg, end, time);
        IF text = F.text THEN anchorF := NIL; RemoveSelection(F); Texts.Delete(text, beg, end); SetCaret(F, beg) END
      END
    ELSIF ch = 16X THEN PasteClipboard(F)  (* Ctrl+V *)
    ELSIF ch = 7FX THEN
      IF F.carloc.pos > F.org THEN
        pos := PrevPos(F.text, F.carloc.pos);
        Texts.Delete(F.text, pos, F.carloc.pos);
        SetCaret(F, pos)
      END
    ELSIF ch = 0C3X THEN (* right *)
      IF anchorF = F THEN RemoveSelection(F); anchorF := NIL END;
      IF F.carloc.pos < F.text.len THEN
        RemoveCaret(F); SetCaret(F, NextPos(F.text, F.carloc.pos))
      END
    ELSIF ch = 0C4X THEN (* left *)
      IF anchorF = F THEN RemoveSelection(F); anchorF := NIL END;
      IF F.carloc.pos > 0 THEN
        RemoveCaret(F); SetCaret(F, PrevPos(F.text, F.carloc.pos))
      END
    ELSIF (ch = 0A1X)  THEN  (* del-key *)
      IF F.carloc.pos < F.text.len THEN
        Texts.Delete(F.text, F.carloc.pos, NextPos(F.text, F.carloc.pos));
        SetCaret(F, F.carloc.pos + 0)
      END
    ELSIF (ch >= 0A0X) & (ch <= 0A9X) THEN
    ELSIF (ch >= 0F0X) & (ch <= 0FFX) THEN
    ELSIF (ch < " ") & (ch # CR) & (ch # 09X) & (ch # 0AX) THEN  (* other Ctrl keys *)
    ELSIF (ch = 09X) & ~shift & Completed(F, lib, col, voff) THEN
    ELSE
      KW.lib := lib; KW.col := col; KW.voff := voff; Texts.Write(KW, ch);
      Texts.Insert(F.text, F.carloc.pos, KW.buf);
      SetCaret(F, F.carloc.pos + 1)
    END
  END Write;

  PROCEDURE Defocus* (F: Frame);
  BEGIN RemoveCaret(F); IF hiddenF = F THEN hiddenF := NIL END
  END Defocus;

  PROCEDURE Neutralize* (F: Frame);
  BEGIN
    IF blockF = F THEN EndBlock  (* polpo: Esc ends a block, the caret stays to go on typing *)
    ELSE RemoveMarks(F)
    END
  END Neutralize;

  PROCEDURE Modify* (F: Frame; id, dY, Y, H: INTEGER);
  BEGIN
    Mark(F, 0); RemoveMarks(F);
    IF id = extend THEN
      IF dY > 0 THEN
        Display.CopyBlock(F.X, F.Y, F.W, F.H, F.X, F.Y + dY, replace); F.Y := F.Y + dY
      END;
      Extend(F, Y)
    ELSIF id = reduce THEN
      Reduce(F, Y + dY);
      IF dY > 0 THEN Display.CopyBlock(F.X, F.Y, F.W, F.H, F.X, Y, replace); F.Y := Y END;
    END;
    IF F.H > 0 THEN Mark(F, 1) END
  END Modify;

  PROCEDURE Open* (
        F: Frame; H: Objects.Handler; T: Texts.Text; org: LONGINT;
        col, left, right, top, bot, lsp: INTEGER);
    VAR L: Line;
  BEGIN NEW(L);
    L.len := 0; L.wid := 0; L.eot := FALSE; L.next := L;
    L.asr := asr; L.dsr := dsr; L.h := Fonts.Default.height;
    F.handle := H; F.text := T; F.org := org; F.trailer := L;
    F.left := left; F.right := right; F.top := top; F.bot := bot;
    F.lsp := lsp; F.col := col; F.mark := 0; F.car := 0; F.sel := 0
  END Open;

  PROCEDURE Copy* (F: Frame; VAR F1: Frame);
  BEGIN NEW(F1);
    Open(F1, F.handle, F.text, F.org, F.col, F.left, F.right, F.top, F.bot, F.lsp)
  END Copy;

  PROCEDURE CopyOver* (F: Frame; text: Texts.Text; beg, end: LONGINT);
    VAR  buf: Texts.Buffer;
  BEGIN
    IF F.car > 0 THEN
      NEW(buf); Texts.OpenBuf(buf);
      Texts.Save(text, beg, end, buf);
      Texts.Insert(F.text, F.carloc.pos, buf);
      SetCaret(F, F.carloc.pos + (end - beg))
    END
  END CopyOver;

  PROCEDURE GetSelection* (F: Frame; VAR M: Oberon.SelectMsg);
  BEGIN
    IF F.sel > 0 THEN
      IF (F.time - M.time > 0) OR (M.time = -1) THEN M.sel := F; M.time := F.time;
        M.text := F.text; M.beg := F.selbeg.pos; M.end := F.selend.pos;
        IF M.end > M.text.len THEN M.end := M.text.len END
(*
       ELSIF (F.text = M.text) & (F.selbeg.pos < M.beg) & (M.sel IS Frame) THEN
        IF (M.beg <= M.sel(Frame).org) & (F.selend.pos >= Pos(F, F.X+F.W, F.Y)) THEN
          M.beg := F.selbeg.pos
        END
*)
     ELSIF F.text = M.text THEN  (* extend selection over frame boundaries *)
        (* 7.4.98 - ps *)
        IF (F.selbeg.pos < M.beg) & (F.selend.pos >= Pos(F, F.X+F.W, F.Y)) THEN M.beg := F.selbeg.pos END;
        IF (F.selend.pos > M.end) & (F.selbeg.pos = F.org) THEN M.end := F.selend.pos END;
        IF M.end > F.text.len THEN M.end :=  F.text.len END
      END
    END
  END GetSelection;

  PROCEDURE GetCaret* (F: Frame; VAR M: Oberon.CaretMsg);
  BEGIN IF F.car > 0 THEN M.text := F.text; M.pos := F.carloc.pos; M.car := F; M.res := 0 END
  END GetCaret;

  PROCEDURE LineLen (VAR R: Texts.Reader): LONGINT;
    VAR len: LONGINT;
  BEGIN len := 0;
    WHILE (ch # CR) & (R.lib # NIL) DO INC(len); Texts.Read(R, ch) END;
    Texts.Read(R, ch);
    RETURN len + 1
  END LineLen;
  
  (** The text of F was changed: [beg, end) replaced by len characters.
    polpo: lines have their own heights; a change inside one line that keeps its height
    redraws that line, otherwise the lines from the changed one down are laid out again. *)
  PROCEDURE Update* (F: Frame; beg, end, len: LONGINT);
    VAR R: Texts.Reader; L, P, N: Line; loc: Location;
      org, orgB, llen, off, pos: LONGINT; y, pY, top, wid, n: INTEGER;
  BEGIN
    IF end < F.org THEN F.org := F.org - (end - beg) + len;
    ELSE
      IF beg < F.org THEN
        F.trailer.next.len := F.trailer.next.len + (F.org - beg);
        F.org := beg
      END;
      org := F.org; P := F.trailer; pY := 0; L := F.trailer.next; y := F.Y + F.H - F.top - L.asr;
      WHILE (L # F.trailer) & (org + L.len <= beg) DO
        org := org + L.len; P := L; pY := y; y := y - Step(L); L := L.next
      END;
      IF L # F.trailer THEN
        RemoveMarks(F); Oberon.RemoveMarks(F.X, F.Y, F.W, F.H);
        orgB := org;
        Texts.OpenReader(R, F.text, orgB); Texts.Read(R, ch); llen := LineLen(R);
        NEW(N); Texts.OpenReader(R, F.text, orgB); Texts.Read(R, ch); MeasureLine(R, N);
        IF (end < orgB + L.len) & (llen = L.len - (end - beg) + len)
            & (N.asr = L.asr) & (N.dsr = L.dsr) & (N.h = L.h) THEN
          (* inside the line, same height: redraw it from beg on *)
          off := beg - orgB; wid := Width(R, off);
          ReplConst(F.col, F, F.X + F.left + wid, y - L.dsr, L.wid - wid, L.asr + L.dsr, replace);
          DisplayLine(F, L, R, F.X + F.left + wid, y, off)
        ELSE
          (* lay out the lines from L down again *)
          IF P = F.trailer THEN top := F.Y + F.H - F.top ELSE top := pY - P.dsr END;
          IF top > F.Y THEN Display.ReplConst(F.col, F.X + F.left, F.Y, F.W - F.left, top - F.Y, replace) END;
          Texts.OpenReader(R, F.text, orgB); Texts.Read(R, ch);
          P.next := F.trailer; Fill(F, P, pY, R);
          (* autoscroll: keep the end of the change visible when it went below *)
          pos := beg + len; n := 0;
          LocatePos(F, pos, loc);
          WHILE (loc.pos # pos) & (pos > F.org) & (F.trailer.next # F.trailer) & (F.trailer.next.next # F.trailer) & (n < 50) DO
            ShowOrg(F, F.org + F.trailer.next.len); LocatePos(F, pos, loc); INC(n)
          END
        END
      END
    END;
    UpdateMark(F)
  END Update;

  PROCEDURE Recall (F: Frame);
    VAR buf: Texts.Buffer; pos: LONGINT;
  BEGIN
    IF F.car > 0 THEN
    NEW(buf); Texts.OpenBuf(buf);
      Texts.Recall(buf); pos := F.carloc.pos + buf.len;
    Texts.Insert(F.text, F.carloc.pos, buf);
      SetCaret(F, pos)
    END
  END Recall;

  PROCEDURE SaveCaret;
  BEGIN
    saved.car := NIL; saved.text := NIL;
    saved.id := Oberon.get; Display.Broadcast(saved)
  END SaveCaret;
  
  PROCEDURE RestoreCaret;
  BEGIN
    IF (saved.car # NIL) & (saved.text # NIL) THEN
      saved.id := Oberon.set; Display.Broadcast(saved)
    END
  END RestoreCaret;
  
  (* polpo: scroll with the scroll bar; the caret stays where it is in the text *)
  PROCEDURE Scroll (F: Frame; pos: LONGINT);
    VAR loc: Location; keep: BOOLEAN;
  BEGIN
    keep := F.car # 0;
    IF keep THEN hiddenF := F; hiddenPos := F.carloc.pos END;
    RemoveCaret(F); Oberon.RemoveMarks(F.X, F.Y, F.W, F.H);
    Show(F, pos);
    IF hiddenF = F THEN
      LocatePos(F, hiddenPos, loc);
      IF loc.pos = hiddenPos THEN F.carloc := loc; FlipCaret(F); F.car := 1; hiddenF := NIL END
    END
  END Scroll;

  PROCEDURE Edit* (F: Frame; X, Y: INTEGER; Keys: SET);
    VAR
      M: Oberon.ConsumeMsg;
      R: Texts.Reader;
      text: Texts.Text; buf: Texts.Buffer;
      time, pos, beg, end: LONGINT;
      keysum: SET;
      ch: CHAR;
  BEGIN
    IF (Keys # {}) & (blockF = F) THEN EndBlock END;  (* polpo: a click ends a block *)
    Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, X, Y);
    IF X < F.X + Min(F.left, barW) THEN
      IF (0 IN Keys) OR (1 IN Keys) THEN keysum := Keys;
        REPEAT
          Input.Mouse(Keys, X, Y);
          keysum := keysum + Keys;
          Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, X, Y)
        UNTIL Keys = {};
        IF ~(2 IN keysum) THEN
          IF (0 IN keysum) OR (F.Y + F.H < Y) THEN
            IF 1 IN keysum THEN pos := 0
            ELSE pos := Max(F.org - LONG(F.H) * 25 DIV lsp, 0)
            END
          ELSE
  (*          pos := (F.Y + F.H - Y) * (F.text.len) DIV F.H*)
      pos:=MulDiv(F.text.len, F.Y + F.H - Y, F.H);
          END;
          Scroll(F, pos)
        ELSIF ~(0 IN keysum) THEN
          Scroll(F, F.text.len)
        END
      ELSIF 2 IN Keys THEN
        TrackLine(F, X, Y, pos, keysum);
        IF (pos >= 0) & ~(0 IN keysum) THEN
          Scroll(F, pos)
        END
      END
    ELSE
      IF 0 IN Keys THEN
        TrackSelection(F, X, Y, keysum);
        IF F.sel # 0 THEN
          IF (2 IN keysum) & ~(1 IN keysum) THEN (*delete text*)
            Oberon.GetSelection(text, beg, end, time);
            Texts.Delete(text, beg, end);
            Oberon.Defocus; SetCaret(F, beg)
          ELSIF (1 IN keysum) & ~(2 IN keysum) THEN (*copy to focus*)
            Oberon.GetSelection(text, beg, end, time);
            M.F := NIL; M.text := text; M.beg := beg; M.end := end;
            Display.Broadcast(M)
        END;
      Input.Copy;
        END
      ELSIF 1 IN Keys THEN
        TrackWord(F, X, Y, pos, keysum);
        IF 0 IN keysum THEN
          IF (pos >= 0) & ~(2 IN keysum) THEN CallCmd(OpenCmd, F, pos, FALSE) END
        ELSE
          IF pos >= 0 THEN Call(F, pos, 2 IN keysum) END
        END
      ELSIF 2 IN Keys THEN
        IF Oberon.New & (F.car # 0) & (Pos(F, X, Y) = F.carloc.pos) THEN (*click on caret*)
          Oberon.Defocus; RestoreCaret; TrackWord(F, X, Y, pos, keysum);
          IF 0 IN keysum THEN
            IF (pos >= 0) & ~(1 IN keysum) THEN CallCmd(OpenCmd, F, pos, FALSE) END
          ELSE
            IF pos >= 0 THEN Call(F, pos, FALSE) END
          END
        ELSE
          IF Oberon.New THEN SaveCaret END;
          Oberon.Defocus; TrackCaret(F, X, Y, keysum);
          IF F.car # 0 THEN
            IF (1 IN keysum) & ~(0 IN keysum) THEN (*copy from selection*)
              Oberon.GetSelection(text, beg, end, time);
              IF time # -1 THEN
                 NEW(buf); Texts.OpenBuf(buf);
                 Texts.Save(text, beg, end, buf);
                 Texts.Insert(F.text, F.carloc.pos, buf);
                 SetCaret(F, F.carloc.pos + (end - beg))
               ELSE (*copy from delete buffer*)
                 NEW(buf); Texts.OpenBuf(buf);
                 Texts.Recall(buf);
                 end := F.carloc.pos + buf.len;
                 Texts.Insert(F.text, F.carloc.pos, buf);
                 SetCaret(F, end)
               END
            ELSIF (0 IN keysum) & ~(1 IN keysum) THEN (*copy font*)
              Oberon.GetSelection(text, beg, end, time);
              IF time # -1 THEN
                Texts.OpenReader(R, F.text, F.carloc.pos); Texts.Read(R, ch);
                IF (R.lib # NIL) & (R.lib IS Fonts.Font) THEN
                  Texts.ChangeLooks(text, beg, end, {0, 1, 2}, R.lib, R.col, R.voff)
                END
              END
            END
          END
        END
      END
    END
  END Edit;

  (* Insert a complete UTF-8 sequence without interpreting continuation bytes
     as Oberon control keys. *)
  PROCEDURE WriteBytes (F: Frame; VAR buf: ARRAY OF CHAR; n: INTEGER;
                        lib: Objects.Library; col, voff: SHORTINT);
  VAR i: INTEGER;
  BEGIN
    KW.lib := lib; KW.col := col; KW.voff := voff;
    i := 0; WHILE i < n DO Texts.Write(KW, buf[i]); INC(i) END;
    Texts.Insert(F.text, F.carloc.pos, KW.buf);
    SetCaret(F, F.carloc.pos + n)
  END WriteBytes;

  PROCEDURE FlushUTF(F: Frame);
  BEGIN
    IF utfLen > 0 THEN WriteBytes(F, utfBuf, utfLen, utfLib, utfCol, utfVoff) END;
    utfLen := 0; utfExp := 0
  END FlushUTF;

  PROCEDURE StartUTF(F: Frame; c: CHAR; lib: Objects.Library; col, voff: SHORTINT);
  BEGIN
    utfBuf[0] := c; utfLen := 1; utfLib := lib; utfCol := col; utfVoff := voff;
    IF (ORD(c) >= 0C2H) & (ORD(c) < 0E0H) THEN utfExp := 1
    ELSIF (ORD(c) >= 0E0H) & (ORD(c) < 0F0H) THEN utfExp := 2
    ELSIF (ORD(c) >= 0F0H) & (ORD(c) <= 0F4H) THEN utfExp := 3
    ELSE FlushUTF(F)
    END
  END StartUTF;

  (* polpo: line spacing in percent of the default font height: System.LineSpacing in
     Oberon.Text, default 150 *)
  PROCEDURE LineSpacing(): LONGINT;
    VAR S: Texts.Scanner; v: LONGINT;
  BEGIN
    v := 100;
    Oberon.OpenScanner(S, "System.LineSpacing");
    IF (S.class = Texts.Int) & (S.i >= 100) & (S.i <= 300) THEN v := S.i END;
    RETURN v
  END LineSpacing;

  (* standard sizes from the default font *)
  PROCEDURE SetMetrics;
  BEGIN
  IF Modern THEN menuH := Fonts.Default.height + 8
  ELSE menuH := Fonts.Default.height + 2
  END;
  barW := Fonts.Default.height + 2;
  left := barW + Fonts.Default.height DIV 2;
  right := Fonts.Default.height DIV 2;
  IF Modern THEN top := Fonts.Default.height DIV 2 * 2 DIV 3
  ELSE top := Fonts.Default.height DIV 2
  END;
  bot := Fonts.Default.height DIV 2;
  asr := Fonts.Default.maxY;
  dsr := -Fonts.Default.minY;
  spacing := LineSpacing();
  lsp := SHORT(Fonts.Default.height * spacing DIV 100);  (* polpo: leading between lines of the default font *)
  selH := Fonts.Default.height;
  markW := Fonts.Default.height DIV 3 * 2;
  eolW := Fonts.Default.height DIV 2;
  END SetMetrics;

  (** polpo: recompute the standard sizes after the fonts were scaled (Fonts.SetScale);
    frames adopt them on Fonts.ScaleMsg. *)
  PROCEDURE Rescale*;
  BEGIN
    oldLeft := left; oldRight := right; oldTop := top; oldBot := bot; oldLsp := lsp;
    SetMetrics
  END Rescale;

  PROCEDURE  Handle* (F: Objects.Object; VAR M: Objects.ObjMsg);
    VAR F1: Frame; u: Utf8.Char; n: INTEGER; beg, end: LONGINT;
  BEGIN
    WITH F: Frame DO
    IF M IS Texts.UpdateMsg THEN
      WITH M: Texts.UpdateMsg DO
          IF F.text = M.text THEN Update(F, M.beg, M.end, M.len) END
      END
      ELSIF M IS Fonts.ScaleMsg THEN  (* polpo: fonts were scaled, adopt the new standard sizes; a restore follows *)
        IF F.lsp = oldLsp THEN F.lsp := lsp END;
        IF F.left = oldLeft THEN F.left := left END;
        IF F.right = oldRight THEN F.right := right END;
        IF F.top = oldTop THEN F.top := top END;
        IF F.bot = oldBot THEN F.bot := bot END
      ELSIF M IS Oberon.InputMsg THEN
         WITH M: Oberon.InputMsg DO
          IF M.id = Oberon.track THEN Edit(F, M.X, M.Y, M.keys)
          ELSIF M.id = Oberon.consume THEN
            IF (F.car = 0) & (F.sel # 0) & ~M.utf & ((M.ch = 03X) OR (M.ch = 18X)) THEN
              (* polpo: Ctrl+C, Ctrl+X in a frame with a selection and no caret (scrolled away) *)
              IF CopySelection() THEN
                IF M.ch = 18X THEN
                  beg := F.selbeg.pos; end := F.selend.pos; RemoveSelection(F); anchorF := NIL;
                  Texts.Delete(F.text, beg, end)
                END;
                M.res := 0
              END
            ELSIF F.car # 0 THEN
              IF M.utf THEN
                IF utfExp > 0 THEN
                  IF (ORD(M.ch) >= 080H) & (ORD(M.ch) < 0C0H) THEN
                  utfBuf[utfLen] := M.ch; INC(utfLen); DEC(utfExp);
                  IF utfExp = 0 THEN
                      IF Utf8.Ord(utfBuf, 0, u, n) & (n = utfLen) THEN
                        WriteBytes(F, utfBuf, utfLen, utfLib, utfCol, utfVoff);
                        utfLen := 0
                      ELSE FlushUTF(F)
                      END
                    END
                  ELSE
                    FlushUTF(F); StartUTF(F, M.ch, M.fnt, M.col, M.voff)
                  END
                ELSE
                  StartUTF(F, M.ch, M.fnt, M.col, M.voff)
                END
              ELSE
                FlushUTF(F);
                Write(F, M.ch, M.fnt, M.col, M.voff)
              END
            END
          END
         END
      ELSIF M IS Oberon.ControlMsg THEN
        WITH M: Oberon.ControlMsg DO
        IF M.id = Oberon.defocus THEN Defocus(F)
        ELSIF M.id = Oberon.neutralize THEN Neutralize(F)
          END
        END
      ELSIF M IS Oberon.CaretMsg THEN
        WITH M: Oberon.CaretMsg DO
          IF M.id = Oberon.get THEN GetCaret(F, M)
          ELSIF (M.car = F) & (M.text = F.text) THEN
            IF M.id = Oberon.set THEN SetCaret(F, M.pos)
              ELSIF M.id = Oberon.reset THEN RemoveCaret(F)
            END
          END
        END
      ELSIF M IS Oberon.SelectMsg THEN
        WITH M: Oberon.SelectMsg DO
          IF M.id = Oberon.get THEN GetSelection(F, M)
          ELSIF (M.sel = F) & (M.text = F.text) THEN
            IF M.id = Oberon.set THEN SetSelection(F, M.beg, M.end); 
              ELSIF M.id = Oberon.reset THEN RemoveSelection(F)
            END
          END
        END
      ELSIF M IS Oberon.ConsumeMsg THEN
        WITH M: Oberon.ConsumeMsg DO
          CopyOver(F, M.text, M.beg, M.end)
        END
      ELSIF M IS Oberon.RecallMsg THEN
        WITH M: Oberon.RecallMsg DO Recall(F) END
      ELSIF M IS Display.ModifyMsg THEN
        WITH M: Display.ModifyMsg DO
          IF M.F = F THEN Modify(F, M.id, M.dY, M.Y, M.H) END
        END
      ELSIF M IS Display.LocateMsg THEN
        WITH M: Display.LocateMsg DO
          IF (F.X <= M.X) & (M.X < F.X + F.W) & (F.Y <= M.Y) & (M.Y < F.Y + F.H) THEN
            M.loc := F; M.res := 0
          END
        END
      ELSIF M IS Objects.AttrMsg THEN
        WITH M: Objects.AttrMsg DO GetAttr(F, M.s); M.class := Objects.String; M.res := 0 END
      ELSIF M IS Objects.CopyMsg THEN
        WITH M: Objects.CopyMsg DO Copy(F, F1); M.obj := F1 END
      ELSIF M IS Objects.LinkMsg THEN
        WITH M: Objects.LinkMsg DO M.obj := F.text; M.res := 0 END
    END
    END
  END Handle;

  (*creation*)

  PROCEDURE Menu (name, commands: ARRAY OF CHAR): Texts.Text;
    VAR T: Texts.Text; mb, me, m, s, d, i: INTEGER; ch: CHAR;
  BEGIN
    IF SmallDisplay & (Display.Width < 1024) THEN (*adjust commands*)
      mb := 0; me := 0; s := 0; d := 0;
      LOOP
        (*position to beginning of word*)
        LOOP
          IF s >= LEN(commands) THEN EXIT END;
          ch := commands[s]; INC(s);
          IF ch = 0X THEN EXIT END;
          commands[d] := ch; INC(d);
          IF ("A" <= CAP(ch)) & (CAP(ch) <= "Z") THEN EXIT END
        END;
        IF (s >= LEN(commands)) OR (ch = 0X) THEN EXIT END;
        (*scan first part of word, checking against last module name*)
        m := mb; i := 0;
        LOOP
          INC(i); IF (m < me) & (commands[m] = ch) THEN INC(m) END;
          IF s >= LEN(commands) THEN EXIT END;
          ch := commands[s]; INC(s);
          IF ch = 0X THEN EXIT END;
          commands[d] := ch; INC(d);
          IF (ch < "0") OR ("9" < ch) & (CAP(ch) < "A")
               OR (CAP(ch) > "Z") THEN EXIT
          END
        END;
        (*check for match*)
        IF (s < LEN(commands)) & (ch = ".") THEN
          IF m = mb + i THEN (*matches previous module name - compress*)
            DEC(d, i); commands[d-1] := "."
          ELSE (*set new module name*)
            mb := d - (i+1); me := d-1
          END;
          (*and do last part of word*)
          LOOP
            IF s >= LEN(commands) THEN EXIT END;
            ch := commands[s]; INC(s);
            IF ch = 0X THEN EXIT END;
            commands[d] := ch; INC(d);
            IF (ch < "0") OR ("9" < ch) & (CAP(ch) < "A")
                 OR (CAP(ch) > "Z") THEN EXIT
            END
          END
        END;
        IF (s >= LEN(commands)) OR (ch = 0X) THEN EXIT END
      END;
      IF d < LEN(commands) THEN commands[d] := 0X END
    END;
  
    NEW(T); Texts.Open(T, "");
    Texts.WriteString(W, name); Texts.WriteString(W, " | "); Texts.WriteString(W, commands);
    Texts.Append(T, W.buf);
    RETURN T
 END Menu;

  PROCEDURE Text* (name: ARRAY OF CHAR): Texts.Text;
    VAR T: Texts.Text;
  BEGIN NEW(T); Texts.Open(T, name); RETURN T
  END Text;

  PROCEDURE NewMenu* (name, commands: ARRAY OF CHAR): Frame;
    VAR F: Frame; l: INTEGER;
  BEGIN NEW(F);
    IF MoveArea THEN l := barW-1 ELSE l := left DIV 4 END;
    IF Modern THEN Open(F, Handle, Menu(name, commands), 0, MenuBG, l, 0, 3, 1, lsp)
    ELSE Open(F, Handle, Menu(name, commands), 0, MenuBG, l, 0, 1, 0, lsp)
    END;
    RETURN F
  END NewMenu;

  PROCEDURE NewText* (text: Texts.Text; pos: LONGINT): Frame;
    VAR F: Frame;
  BEGIN NEW(F);
    Open(F, Handle, text, pos, TextBG, left, right, top, bot, lsp);
    RETURN F
  END NewText;

PROCEDURE *ShowText(title: ARRAY OF CHAR; T: Texts.Text; W, H: INTEGER);
  VAR X, Y: INTEGER; V: Viewers.Viewer; menu: ARRAY 100 OF CHAR;
BEGIN
  X := 0; WHILE (title[X] # 0X) & (title[X] # "|") DO INC(X) END;
  IF title[X] = "|" THEN
    title[X] := 0X;  INC(X);  Y := 0;
    WHILE title[X] # 0X DO menu[Y] := title[X];  INC(X);  INC(Y) END;
    menu[Y] := 0X
  ELSE
    menu := ""
  END;
  IF T = Oberon.Log THEN
    Oberon.AllocateSystemViewer(0, X, Y);
    IF menu = "" THEN menu := LogMenu END;
    V := MenuViewers.New(NewMenu(title, menu), NewText(T, Max(T.len-200, 0)), menuH, X, Y);
  ELSE
    IF W > LONG(Display.Width * 3) DIV 8 THEN Oberon.AllocateUserViewer(0, X, Y)
    ELSE Oberon.AllocateSystemViewer(0, X, Y)
    END;
    IF menu = "" THEN menu := StandardMenu END;
    V := MenuViewers.New(NewMenu(title, menu), NewText(T, 0), menuH, X, Y)
  END;
END ShowText;

(** Replace the default system editor with a textframe. *)
PROCEDURE ReplaceSystemEditor*;
BEGIN
  Oberon.OpenText := ShowText
END ReplaceSystemEditor;

BEGIN
  IF Oberon.OpenText = NIL THEN
    Oberon.OpenText := ShowText
  END;
  IF Display.Depth(0) # 1 THEN
    MarkColor := 12; MenuBG := 13; TextBG := 14;
    IF Modern THEN BarColor := 12; FullColor := Display.FG - TextBG 
    ELSE BarColor := 13; FullColor := Display.FG 
    END;
    mode := paint
  ELSE
    MarkColor := Display.FG; BarColor := Display.FG; MenuBG := Display.FG; TextBG:= Display.BG;
    FullColor := Display.FG;  mode := invert
  END;
  SetMetrics;
  Texts.OpenWriter(W); Texts.OpenWriter(KW);
  blockF := NIL; bShown := FALSE; bBusy := FALSE; bMarking := FALSE; blockClip := NIL;
  BoxPat[0] := {0..11}; 
  BoxPat[1] := {0, 11}; BoxPat[2] := {0, 11}; BoxPat[3] := {0, 11}; BoxPat[4] := {0, 11};
  BoxPat[5] := {0, 11}; BoxPat[6] := {0, 11}; BoxPat[7] := {0, 11}; BoxPat[8] := {0, 11};
  BoxPat[9] := {0, 11}; BoxPat[10] := {0, 11}; BoxPat[11] := {0.. 11};
  NEW(box);
  box.dx := 12; box.x := 0; box.y := -3; box.w := 12; box.h := 12;
  box.pat := Display.NewPattern(12, 12, BoxPat)
END TextFrames.
