MODULE Texts;

  IMPORT Objects, Display, Fonts, Files, Reals, Texts0;

  CONST
    Inval* = Texts0.Inval; Name* = Texts0.Name; String* = Texts0.String;
    Int* = Texts0.Int; Real* = Texts0.Real; LongReal* = Texts0.LongReal;
    Char* = Texts0.Char; Object* = Texts0.Object; ElemChar* = Texts0.ElemChar;

  TYPE
    Text* = Texts0.Text;
    TextDesc* = Texts0.TextDesc;
    Finder* = Texts0.Finder;
    Reader* = Texts0.Reader;
    Scanner* = Texts0.Scanner;
    Buffer* = Texts0.Buffer;
    BufDesc* = Texts0.BufDesc;
    Writer* = Texts0.Writer;
    UpdateMsg* = RECORD (Display.FrameMsg)
      text*: Text;
      beg*, end*, len*: LONGINT
    END;

  VAR TextBlockId*: CHAR;

  PROCEDURE LoadAscii* (T: Text; f: Files.File);
  BEGIN Texts0.LoadAscii(T, f) END LoadAscii;

  PROCEDURE Load* (T: Text; f: Files.File; pos: LONGINT; VAR len: LONGINT);
  BEGIN Texts0.Load(T, f, pos, len) END Load;

  PROCEDURE Store* (T: Text; f: Files.File; pos: LONGINT; VAR len: LONGINT);
  BEGIN Texts0.Store(T, f, pos, len) END Store;

  PROCEDURE Open* (T: Text; name: ARRAY OF CHAR);
  BEGIN Texts0.Open(T, name) END Open;

  PROCEDURE New*;
    VAR T: Text;
  BEGIN
    NEW(T); Texts0.Open(T, ""); Objects.NewObj := T
  END New;

  PROCEDURE Insert* (T: Text; pos: LONGINT; B: Buffer);
  BEGIN Texts0.Insert(T, pos, B) END Insert;

  PROCEDURE Append* (T: Text; B: Buffer);
  BEGIN Texts0.Append(T, B) END Append;

  PROCEDURE Delete* (T: Text; beg, end: LONGINT);
  BEGIN Texts0.Delete(T, beg, end) END Delete;

  PROCEDURE Replace* (T: Text; beg, end: LONGINT; B: Buffer);
  BEGIN Texts0.Replace(T, beg, end, B) END Replace;

  PROCEDURE ChangeLooks* (T: Text; beg, end: LONGINT; sel: SET; lib: Objects.Library; col, voff: SHORTINT);
  BEGIN Texts0.ChangeLooks(T, beg, end, sel, lib, col, voff) END ChangeLooks;

  PROCEDURE OpenBuf* (B: Buffer);
  BEGIN Texts0.OpenBuf(B) END OpenBuf;

  PROCEDURE Save* (T: Text; beg, end: LONGINT; B: Buffer);
  BEGIN Texts0.Save(T, beg, end, B) END Save;

  PROCEDURE Copy* (SB, DB: Buffer);
  BEGIN Texts0.Copy(SB, DB) END Copy;

  PROCEDURE Recall* (VAR B: Buffer);
  BEGIN Texts0.Recall(B) END Recall;

  PROCEDURE Handle* (obj: Objects.Object; VAR M: Objects.ObjMsg);
  BEGIN Texts0.Handle(obj, M) END Handle;

  PROCEDURE OpenFinder* (VAR F: Finder; T: Text; pos: LONGINT);
  BEGIN Texts0.OpenFinder(F, T, pos) END OpenFinder;

  PROCEDURE FindObj* (VAR F: Finder; VAR obj: Objects.Object);
  BEGIN Texts0.FindObj(F, obj) END FindObj;

  PROCEDURE OpenReader* (VAR R: Reader; T: Text; pos: LONGINT);
  BEGIN Texts0.OpenReader(R, T, pos) END OpenReader;

  PROCEDURE Read* (VAR R: Reader; VAR ch: CHAR);
  BEGIN Texts0.Read(R, ch) END Read;

  PROCEDURE Pos* (VAR R: Reader): LONGINT;
  BEGIN RETURN Texts0.Pos(R) END Pos;

  PROCEDURE OpenScanner* (VAR S: Scanner; T: Text; pos: LONGINT);
  BEGIN Texts0.OpenScanner(S, T, pos) END OpenScanner;

  PROCEDURE Scan* (VAR S: Scanner);
  BEGIN Texts0.Scan(S) END Scan;

  PROCEDURE OpenWriter* (VAR W: Writer);
  BEGIN Texts0.OpenWriter(W) END OpenWriter;

  PROCEDURE SetFont* (VAR W: Writer; fnt: Objects.Library);
  BEGIN Texts0.SetFont(W, fnt) END SetFont;

  PROCEDURE SetColor* (VAR W: Writer; col: SHORTINT);
  BEGIN Texts0.SetColor(W, col) END SetColor;

  PROCEDURE SetOffset* (VAR W: Writer; voff: SHORTINT);
  BEGIN Texts0.SetOffset(W, voff) END SetOffset;

  PROCEDURE Write* (VAR W: Writer; ch: CHAR);
  BEGIN Texts0.Write(W, ch) END Write;

  PROCEDURE WriteLn* (VAR W: Writer);
  BEGIN Texts0.WriteLn(W) END WriteLn;

  PROCEDURE WriteString* (VAR W: Writer; s: ARRAY OF CHAR);
  BEGIN Texts0.WriteString(W, s) END WriteString;

  PROCEDURE WriteInt* (VAR W: Writer; x, n: LONGINT);
  BEGIN Texts0.WriteInt(W, x, n) END WriteInt;

  PROCEDURE WriteHex* (VAR W: Writer; x: LONGINT);
  BEGIN Texts0.WriteHex(W, x) END WriteHex;

  PROCEDURE WriteReal* (VAR W: Writer; x: REAL; n: LONGINT);
  BEGIN Texts0.WriteReal(W, x, n) END WriteReal;

  PROCEDURE WriteRealFix* (VAR W: Writer; x: REAL; n, f, E: LONGINT);
  BEGIN Texts0.WriteRealFix(W, x, n, f, E) END WriteRealFix;

  PROCEDURE WriteRealHex* (VAR W: Writer; x: REAL);
  BEGIN Texts0.WriteRealHex(W, x) END WriteRealHex;

  PROCEDURE WriteLongReal* (VAR W: Writer; x: LONGREAL; n: LONGINT);
  BEGIN Texts0.WriteLongReal(W, x, n) END WriteLongReal;

  PROCEDURE WriteLongRealFix* (VAR W: Writer; x: LONGREAL; n, f, D: LONGINT);
  BEGIN Texts0.WriteLongRealFix(W, x, n, f, D) END WriteLongRealFix;

  PROCEDURE WriteLongRealHex* (VAR W: Writer; x: LONGREAL);
  BEGIN Texts0.WriteLongRealHex(W, x) END WriteLongRealHex;

  PROCEDURE WriteDate* (VAR W: Writer; t, d: LONGINT);
  BEGIN Texts0.WriteDate(W, t, d) END WriteDate;

  PROCEDURE WriteSet* (VAR W: Writer; s: SET);
  BEGIN Texts0.WriteSet(W, s) END WriteSet;

  PROCEDURE WriteObj* (VAR W: Writer; obj: Objects.Object);
  BEGIN Texts0.WriteObj(W, obj) END WriteObj;

  PROCEDURE DefaultLibrary(): Objects.Library;
  BEGIN RETURN Fonts.Default END DefaultLibrary;

  PROCEDURE Update(T: Text; beg, end, len: LONGINT; VAR stamp: LONGINT);
    VAR M: UpdateMsg;
  BEGIN
    M.text := T; M.F := NIL; M.beg := beg; M.end := end; M.len := len;
    (* polpo: Viewers installs Display.Broadcast; without the desktop (a console program) nobody
       shows the text *)
    IF Display.Broadcast # NIL THEN Display.Broadcast(M); stamp := M.stamp END
  END Update;

BEGIN
  TextBlockId := Texts0.TextBlockId;
  Texts0.DefaultLibrary := DefaultLibrary;
  Texts0.Update := Update;
END Texts.
