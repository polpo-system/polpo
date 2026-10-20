MODULE Workspaces;  (** workspaces of the desktop: more screens of viewers, one shown at a time *)

(* Each workspace has its own tracks and viewers, laid out like the first one: a user track and a
   system track with System.Log and System.Tool. The viewers of a workspace not shown are suspended
   (Viewers.SetWorkspace); they get their messages again and are drawn anew when it is shown.
   Nothing is kept outside the screen, so this works the same with X11, KMS, the framebuffer and
   sixel.

   Workspaces.Add          a new workspace after the last one, shown
   Workspaces.Right        the next workspace (after the last, the first)
   Workspaces.Left         the one before (before the first, the last)
   Workspaces.Go n         workspace n, counted from 1
   Workspaces.Close [n]    workspace n (default: the one shown) and its viewers; one stays
   Workspaces.Show         which workspace is shown, of how many *)

IMPORT Display, Viewers, Texts, Oberon, TextFrames;

VAR W: Texts.Writer;

PROCEDURE Report;
BEGIN
  Texts.WriteString(W, "workspace "); Texts.WriteInt(W, Viewers.wsCur + 1, 0);
  Texts.WriteString(W, " of "); Texts.WriteInt(W, Viewers.wsCount, 0); Texts.WriteLn(W);
  Texts.Append(Oberon.Log, W.buf)
END Report;

(* the cursors faded and the focus taken back before the viewers of the screen change *)
PROCEDURE Leave;
BEGIN
  Oberon.Defocus; Oberon.RemoveMarks(0, 0, Display.Width, Display.Height)
END Leave;

PROCEDURE Set(n: INTEGER);
BEGIN
  IF (n >= 0) & (n < Viewers.wsCount) & (n # Viewers.wsCur) THEN Leave; Viewers.SetWorkspace(n) END
END Set;

(* the number after the command, or def *)
PROCEDURE Arg(def: INTEGER): INTEGER;
VAR S: Texts.Scanner;
BEGIN
  Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
  IF (S.class = Texts.Int) & (S.line = 0) THEN RETURN SHORT(S.i) ELSE RETURN def END
END Arg;

(** Workspaces.Add: a new workspace with System.Log and System.Tool, shown at once *)
PROCEDURE Add*;
VAR DW, DH, W0: INTEGER;
BEGIN
  Leave;
  IF Viewers.AddWorkspace() THEN
    DW := Oberon.DisplayWidth(0); DH := Oberon.DisplayHeight(0);
    W0 := DW DIV 8 * 5; IF W0 < 400 THEN W0 := 0 END;
    Oberon.OpenDisplay(W0, DW - W0, DH);
    IF Oberon.OpenText # NIL THEN
      Oberon.OpenText("System.Log", Oberon.Log, DW DIV 8 * 3, 240);
      Oberon.OpenText("System.Tool", TextFrames.Text("System.Tool"), DW DIV 8 * 3, 240)
    END;
    Report
  ELSE Texts.WriteString(W, "Workspaces.Add: there are 16 workspaces already"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
  END
END Add;

(** Workspaces.Right: the next workspace *)
PROCEDURE Right*;
BEGIN Set((Viewers.wsCur + 1) MOD Viewers.wsCount)
END Right;

(** Workspaces.Left: the workspace before *)
PROCEDURE Left*;
BEGIN Set((Viewers.wsCur + Viewers.wsCount - 1) MOD Viewers.wsCount)
END Left;

(** Workspaces.Go n: workspace n, counted from 1 *)
PROCEDURE Go*;
BEGIN Set(Arg(0) - 1)
END Go;

(** Workspaces.Close [n]: remove workspace n (the one shown when n is missing) with its viewers *)
PROCEDURE Close*;
VAR n: INTEGER;
BEGIN
  n := Arg(Viewers.wsCur + 1) - 1;
  IF Viewers.wsCount = 1 THEN
    Texts.WriteString(W, "Workspaces.Close: the last workspace stays"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
  ELSIF (n >= 0) & (n < Viewers.wsCount) THEN
    IF n = Viewers.wsCur THEN Leave END;
    Viewers.CloseWorkspace(n); Report
  END
END Close;

(** Workspaces.Show: which workspace is shown, of how many *)
PROCEDURE Show*;
BEGIN Report
END Show;

BEGIN Texts.OpenWriter(W)
END Workspaces.
