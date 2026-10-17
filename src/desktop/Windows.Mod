MODULE Windows;  (** polpo: frames in X11 windows of their own *)

(** A window shows one frame, without a menu bar: the window manager gives it a title bar and a
  close button, and it looks like the windows of the other programs. Open puts a frame into a new
  window of W x H: the window shows an area below the screen (Display.OpenWindow), where the frame
  is a free viewer (Viewers.OpenFree) that gets the mouse, the keyboard and the broadcasts as the
  viewers of the desktop do. The close button closes the window when the desktop is idle.
  Windows exist with X11 only, at most 16, as wide as the screen and as high as it.
  Without the desktop (a command run from the shell, as loksh Windows.OpenText name), Run makes
  the windows a program of their own: the desktop's loop runs for them alone, its screen stays
  hidden, and loksh ends when the last window is closed. *)

IMPORT Kernel, Modules, Objects, Input, Display, Viewers, Texts, Oberon, TextFrames;

TYPE
  Window* = POINTER TO WindowDesc;
  WindowDesc* = RECORD (Viewers.ViewerDesc)
    n: INTEGER;  (* the window of Display *)
    link: Window  (* the open windows *)
  END;

VAR
  first: Window;  (* the open windows *)
  task: Oberon.Task;  (* looks for clicked close buttons *)
  alone: BOOLEAN;  (* Run: the windows without the desktop, loksh ends with the last *)
  W: Texts.Writer;

PROCEDURE Modify(F: Display.Frame; id, Y, H: INTEGER);
VAR M: Display.ModifyMsg;
BEGIN
  M.F := F; M.id := id; M.mode := Display.display; M.dlink := NIL;
  M.X := F.X; M.Y := Y; M.W := F.W; M.H := H;
  M.dX := 0; M.dY := 0; M.dW := 0; M.dH := H - F.H;
  M.res := MIN(INTEGER); M.x := 0; M.y := 0; Objects.Stamp(M);
  F.handle(F, M); F.Y := Y; F.H := H
END Modify;

PROCEDURE Restore(V: Window);  (* the frame fills the window *)
VAR F: Display.Frame; M: Display.ControlMsg;
BEGIN
  F := V.dsc;
  F.X := V.X; F.Y := V.Y + V.H; F.W := V.W; F.H := 0;
  M.F := NIL; M.id := Display.restore; M.res := -1; Objects.Stamp(M); M.dlink := NIL; M.x := 0; M.y := 0;
  F.handle(F, M);
  Modify(F, Display.extend, V.Y, V.H)
END Restore;

(** The handler of windows: the frame gets the messages; a window keeps its size and is not copied *)
PROCEDURE Handle*(V: Objects.Object; VAR M: Objects.ObjMsg);
VAR F: Display.Frame;
BEGIN
  WITH V: Window DO
    F := V.dsc;
    IF M IS Display.ModifyMsg THEN
      WITH M: Display.ModifyMsg DO IF M.F # V THEN F.handle(F, M) END END
    ELSIF M IS Display.ControlMsg THEN
      WITH M: Display.ControlMsg DO
        IF M.id = Display.restore THEN Restore(V)
        ELSIF M.id = Display.suspend THEN Modify(F, Display.reduce, V.Y + V.H, 0)
        ELSE F.handle(F, M)
        END
      END
    ELSIF M IS Oberon.ControlMsg THEN
      WITH M: Oberon.ControlMsg DO IF M.id # Oberon.mark THEN F.handle(F, M) END END
    ELSIF M IS Objects.CopyMsg THEN
    ELSE F.handle(F, M)
    END
  END
END Handle;

(** Close the window V *)
PROCEDURE Close*(V: Window);
VAR P: Window;
BEGIN
  IF V.state > 1 THEN Viewers.Close(V) END;
  Display.CloseWindow(V.n);
  IF first = V THEN first := V.link
  ELSE
    P := first; WHILE (P # NIL) & (P.link # V) DO P := P.link END;
    IF P # NIL THEN P.link := V.link END
  END;
  V.link := NIL;
  IF alone & (first = NIL) THEN Kernel.Shutdown(1) END
END Close;

PROCEDURE Check(me: Oberon.Task);  (* close the windows whose close button was clicked *)
VAR V, next: Window;
BEGIN
  V := first;
  WHILE V # NIL DO
    next := V.link;
    IF Display.CloseRequested(V.n) THEN Close(V) END;
    V := next
  END;
  me.time := Input.Time() + Input.TimeUnit DIV 10
END Check;

(** Open a window of W x H with the title title, showing the frame F; NIL: no window (no X11, too
  large, too many) *)
PROCEDURE Open*(F: Display.Frame; title: ARRAY OF CHAR; W, H: INTEGER): Window;
VAR V: Window; n, X, Y: INTEGER;
BEGIN
  n := Display.OpenWindow(title, W, H, X, Y);
  IF n < 0 THEN RETURN NIL END;
  NEW(V); V.handle := Handle; V.dsc := F; F.next := NIL; V.n := n; V.state := 0;
  Viewers.OpenFree(V, X, Y, W, H); Restore(V);
  V.link := first; first := V;
  IF task = NIL THEN
    NEW(task); task.safe := TRUE; task.time := 0; task.handle := Check; Oberon.Install(task)
  END;
  RETURN V
END Open;

(** Without the desktop, run the windows (V the first) as a program of their own until the last
  is closed, then end loksh; in the desktop, return at once: it runs them *)
PROCEDURE Run*(V: Window);
BEGIN
  IF (V # NIL) & (Modules.FindMod("System") = NIL) THEN alone := TRUE; Oberon.Loop END
END Run;

(** Windows.OpenText name [width height] ~  the text name in a window of its own (640 x 480 when
  no size is given); ^ takes the selected name *)
PROCEDURE OpenText*;
VAR S: Texts.Scanner; T: Texts.Text; beg, end, time: LONGINT; w, h: INTEGER; name: ARRAY 128 OF CHAR;
  V: Window;
BEGIN
  Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
  IF (S.class = Texts.Char) & (S.c = "^") THEN
    Oberon.GetSelection(T, beg, end, time);
    IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S) END
  END;
  IF S.class IN {Texts.Name, Texts.String} THEN
    COPY(S.s, name); w := 640; h := 480; Texts.Scan(S);
    IF S.class = Texts.Int THEN
      w := SHORT(S.i); Texts.Scan(S);
      IF S.class = Texts.Int THEN h := SHORT(S.i) END
    END;
    V := Open(TextFrames.NewText(TextFrames.Text(name), 0), name, w, h);
    IF V # NIL THEN Run(V)
    ELSE
      Texts.WriteString(W, "Windows.OpenText: no window (X11 only, at most 16, as large as the screen)");
      Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
    END
  ELSE
    Texts.WriteString(W, "usage: Windows.OpenText name [width height] ~  a text in a window of its own");
    Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
  END
END OpenText;

BEGIN
  first := NIL; task := NIL; alone := FALSE; Texts.OpenWriter(W)
END Windows.
