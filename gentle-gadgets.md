# A Gentle Introduction to Gadgets

(Last updated: 18 October 2026.)

## Contents

    Background
    Introduction
    Getting the gadgets
    A panel made by hand
    A panel made by a program
    Commands and their context
    Models and views
    A gadget of your own
    Storing and loading
    Programs of their own
    The other ports
    Where to go from here

## Background

This note is for those who know a little Oberon and polpo (gentle-introduction.md shows the way
around) and have built graphical programs with a toolkit such as GTK, Qt, Swing or Tk. It is not a
manual of the Gadgets system; it shows how to put gadgets together into a program, how gadgets
talk to each other, and how to write a gadget of your own, with three small programs that you can
type in and run. For the Gadgets system itself, please read:

    A. Fischer and H. Marais, "The Oberon Companion: A Guide to Using and Programming Oberon
    System 3", vdf, 1998. (How to use Oberon System 3 and its gadgets, and how to program them.)

    J. Marais, "Design and Implementation of a Component Architecture for Oberon", ETH Zurich,
    1996. (The design of the Gadgets system, by its author.)

    The sources: src/pkg/gadgets/ after the gadgets are installed. Gadgets.Mod, BasicGadgets.Mod
    and Panels.Mod are well commented; their comments starting with (** are the interface.

## Introduction

Gadgets are the component system of ETH Oberon System 3. A gadget is an object: a button, a text
field, a slider, a panel holding other gadgets, a picture, a whole document. What makes gadgets
different from the widgets of most toolkits is how little is fixed in advance:

    - Every gadget has one handler, a procedure that gets every message sent to it: "draw
      yourself", "the mouse is here", "copy yourself", "store yourself", "what is your attribute
      Caption?". The handler looks at the type of the message (with IS and WITH) and does what it
      knows; everything else it passes on to a default handler, as a subclass would call its
      superclass. There are no methods to override, only messages to answer.

    - Gadgets have attributes, named values that anyone can get and set: a button's Caption and
      Cmd, a slider's Min and Max, every gadget's Name. The inspector (Columbus) shows and changes
      them for any gadget, also one written yesterday.

    - Gadgets have links, named references to other objects. A slider's link Model names the
      object that holds its value. Several views can share one model: change the model, and every
      view of it follows.

    - A gadget runs a command, an exported procedure of some module (Hello.Greet), as a click in a
      text does: the command line is an attribute (Cmd), not code compiled into the program.

    - Gadgets are stored and loaded with their attributes and links, as panels and documents. A
      program can be a panel made by hand in the desktop and a module of commands, or a module
      that builds its panel itself; usually it is some of both.

This note uses polpo's windows of their own (the module Windows and DocWindows of the gadgets): a
panel opens in an X11 window beside the desktop, or, started from a shell, as a program of its
own, a Linux program like any other.

## Getting the gadgets

The gadgets are a package of their own:

    loksh portia.Install gadgets

compiles them and what they need. In the desktop (loksh System.Init), Desktops.OpenDoc
Gadgets.Panel shows the toolkit: the classes to insert, with the commands to make documents.
Many more gadgets and programs are packages of their own: portia.List gadgets lists them, and
portia.Install gadgets-hpcalc, for instance, installs a calculator, which then runs as

    loksh DocWindows.OpenDoc HPCalc.Panel

## A panel made by hand

The ETH way to make a user interface is to draw it. In the desktop:

    Desktops.OpenDoc (PanelDocs.NewDoc)     a new, empty panel document
    Gadgets.Insert Button ~                 a button at the caret (click into the panel first)
    Gadgets.Insert TextField ~              a text field
    Columbus.Inspect                        the attributes of the selected gadget

A gadget is selected with a right click; the inspector changes its Caption, its Cmd (the command
it runs) and its Name. The panel is stored with Desktops.StoreDoc (Store in its menu bar), under
a name ending in .Panel, and opened again with Desktops.OpenDoc My.Panel, or in a window of its
own with DocWindows.OpenDoc My.Panel. The names after Gadgets.Insert are aliases, listed in the
section Gadgets of Oberon.Text: Button stands for BasicGadgets.NewButton, the generator, the
procedure that makes a new button.

Drawing is quick, but a panel made by hand is a binary file; for this note we make our panels by
program, which is also how a program makes a panel that depends on its data.

## A panel made by a program

Our first program shows a text field with a name, a button Greet, and a second text field for
the answer:

    MODULE Hello;  (* a panel with a text field, a button and an answer, made by the program *)

    IMPORT Strings, Objects, Display, Gadgets, Attributes, Panels, Documents, PanelDocs, DocWindows, Windows;

    (* a new gadget made by its generator, w x h, at x, y of the panel (from its top left corner;
       y counts down, so it is negative) *)
    PROCEDURE Add(P: Panels.Panel; gen: ARRAY OF CHAR; x, y, w, h: INTEGER): Display.Frame;
    VAR obj: Objects.Object; F: Display.Frame;
    BEGIN
      obj := Gadgets.CreateObject(gen); F := obj(Display.Frame);
      F.W := w; F.H := h;
      Panels.InsertChild(P, F, x, y - h);
      RETURN F
    END Add;

    (** Hello.Open  the panel in a window of its own *)
    PROCEDURE Open*;
    VAR D: Documents.Document; P: Panels.Panel; F: Display.Frame; V: Windows.Window;
    BEGIN
      PanelDocs.NewDoc; D := Objects.NewObj(Documents.Document);
      D.name := "Hello"; D.W := 270; D.H := 90;
      P := D.dsc(Panels.Panel);
      F := Add(P, "TextFields.NewTextField", 10, -10, 160, 25);
      Gadgets.NameObj(F, "Name"); Attributes.SetString(F, "Value", "world");
      F := Add(P, "BasicGadgets.NewButton", 180, -10, 80, 25);
      Attributes.SetString(F, "Caption", "Greet"); Attributes.SetString(F, "Cmd", "Hello.Greet");
      F := Add(P, "TextFields.NewTextField", 10, -50, 250, 25);
      Gadgets.NameObj(F, "Answer");
      V := DocWindows.Open(D);
      Windows.Run(V)
    END Open;

    (** Hello.Greet  the command of the button: the answer for the name *)
    PROCEDURE Greet*;
    VAR name, answer: ARRAY 64 OF CHAR; obj: Objects.Object;
    BEGIN
      Attributes.GetString(Gadgets.FindObj(Gadgets.context, "Name"), "Value", name);
      answer := "Hello, "; Strings.Append(answer, name);
      obj := Gadgets.FindObj(Gadgets.context, "Answer");
      Attributes.SetString(obj, "Value", answer); Gadgets.Update(obj)
    END Greet;

    END Hello.

Save it as Hello.Mod in a directory of your own, compile it, and run it from the shell:

    mkdir -p obj/x86
    loksh compiler.Compile Hello.Mod
    loksh Hello.Open

(The compiler writes Hello.Obj into obj/x86/ of the current directory when there is one, and
into polpo's own obj/x86/ otherwise; loksh looks in both, the current directory first.)

A window titled Hello opens; a middle click on Greet writes "Hello, world" into the lower field.
(The mouse buttons of Oberon: the middle one uses a gadget, clicks buttons and drags sliders; the
left one sets the caret, and dragged on a gadget moves or resizes it; the right one selects.)
Change the name and click again. Closing the window ends loksh. In the desktop, a middle click
on Hello.Open in a text does the same, but the window opens beside the desktop, and closing it
closes only the window.

What happened in Open:

    - PanelDocs.NewDoc made a panel document. Its contents, D.dsc, is an empty panel. A document
      is the outermost gadget of something that can be stored and opened: it has a name and
      knows how to load and store what it holds.

    - Add makes a gadget by its generator, Gadgets.CreateObject("BasicGadgets.NewButton"),
      gives it a size, and puts it into the panel with Panels.InsertChild. Positions in a panel
      count from its top left corner, and y counts down, so a gadget 10 pixels below the top has
      y = -10; InsertChild takes the lower left corner, hence y - h.

    - Gadgets.NameObj names a gadget, so that commands can find it. Attributes.SetString sets an
      attribute, here the Value of a text field and the Caption and Cmd of the button.

    - DocWindows.Open puts the document into a window as large as the document, and Windows.Run
      makes that window a program of its own when there is no desktop (when there is one, Run
      returns at once: the desktop runs the window).

(Question: what happens if you remove the call of Windows.Run and run loksh Hello.Open from the
shell? The window opens, and loksh, its command done, ends at once and takes the window along.)

## Commands and their context

The button runs its Cmd, "Hello.Greet", as if the text were clicked; Hello.Greet is an ordinary
command. While a gadget runs a command, the module Gadgets tells it where the command came from:

    Gadgets.executorObj    the gadget that runs the command (the button)
    Gadgets.context        the gadget around it (the panel)
    Oberon.Par             the parameters: the text of the command line, after the command name

Gadgets.FindObj(Gadgets.context, "Name") finds the gadget named Name in the panel, so Greet works
for any panel that has a Name and an Answer, also for a second Hello window or a panel made by
hand. After changing an attribute, Gadgets.Update(obj) tells the gadget, and whoever shows it,
to show the change.

## Models and views

A text field shows its own text; but it can also show the value of a model, a gadget without a
picture of its own that holds a value. Our second program has one model, an integer, and two
views of it, a slider and a text field; the buttons change only the model:

    MODULE Counter;  (* one model, an integer, shown by a slider and a text field; buttons change it *)

    IMPORT Texts, Oberon, Objects, Display, Gadgets, Attributes, Links, Panels, Documents, PanelDocs, DocWindows, Windows;

    PROCEDURE Add(P: Panels.Panel; gen: ARRAY OF CHAR; x, y, w, h: INTEGER): Display.Frame;
    VAR obj: Objects.Object; F: Display.Frame;
    BEGIN
      obj := Gadgets.CreateObject(gen); F := obj(Display.Frame);
      F.W := w; F.H := h;
      Panels.InsertChild(P, F, x, y - h);
      RETURN F
    END Add;

    PROCEDURE Button(P: Panels.Panel; x, y: INTEGER; caption, cmd: ARRAY OF CHAR);
    VAR F: Display.Frame;
    BEGIN
      F := Add(P, "BasicGadgets.NewButton", x, y, 80, 25);
      Attributes.SetString(F, "Caption", caption); Attributes.SetString(F, "Cmd", cmd)
    END Button;

    (** Counter.Open  the counter in a window of its own *)
    PROCEDURE Open*;
    VAR D: Documents.Document; P: Panels.Panel; F: Display.Frame; model: Objects.Object; V: Windows.Window;
    BEGIN
      model := Gadgets.CreateObject("BasicGadgets.NewInteger");  (* the model: no frame, not shown *)
      PanelDocs.NewDoc; D := Objects.NewObj(Documents.Document);
      D.name := "Counter"; D.W := 280; D.H := 115;
      P := D.dsc(Panels.Panel);
      F := Add(P, "BasicGadgets.NewSlider", 10, -10, 260, 20);
      Attributes.SetInt(F, "Min", 0); Attributes.SetInt(F, "Max", 100);
      Links.SetLink(F, "Model", model);
      F := Add(P, "TextFields.NewTextField", 10, -45, 80, 25);
      Gadgets.NameObj(F, "Number"); Links.SetLink(F, "Model", model);
      Button(P, 100, -45, "+ 1", "Counter.Step 1");
      Button(P, 190, -45, "- 1", "Counter.Step -1");
      Button(P, 100, -80, "Reset", "Counter.Reset");
      V := DocWindows.Open(D);
      Windows.Run(V)
    END Open;

    PROCEDURE Model(): Objects.Object;  (* the model of the text field "Number" of the panel the command came from *)
    VAR m: Objects.Object;
    BEGIN
      Links.GetLink(Gadgets.FindObj(Gadgets.context, "Number"), "Model", m); RETURN m
    END Model;

    PROCEDURE Set(m: Objects.Object; v: LONGINT);  (* change the model; Update tells its views *)
    BEGIN
      IF v < 0 THEN v := 0 ELSIF v > 100 THEN v := 100 END;
      Attributes.SetInt(m, "Value", v); Gadgets.Update(m)
    END Set;

    (** Counter.Step n  add n (the parameters of a button's command come in Oberon.Par, as in a text) *)
    PROCEDURE Step*;
    VAR S: Texts.Scanner; m: Objects.Object; v, n: LONGINT;
    BEGIN
      Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
      n := 1;
      IF (S.class = Texts.Char) & (S.c = "-") THEN Texts.Scan(S); n := -1 END;
      IF S.class = Texts.Int THEN n := n * S.i END;
      m := Model(); Attributes.GetInt(m, "Value", v);
      Set(m, v + n)
    END Step;

    (** Counter.Reset  back to 0 *)
    PROCEDURE Reset*;
    BEGIN Set(Model(), 0)
    END Reset;

    END Counter.

    loksh compiler.Compile Counter.Mod
    loksh Counter.Open

Click + 1 a few times: the number and the slider move together. Drag the slider's knob (with the
middle button): the number follows, although the program has no code for that. Type a number into the field and press
Enter: the slider follows. Each view has a link Model to the same integer (Links.SetLink); when
the model changes, Gadgets.Update(model) sends a message to everybody, and each view that shows
that model draws itself again.

Counter.Step shows the parameters of a command: the button's Cmd is "Counter.Step 1" or "Counter.Step
-1", and Step reads the number after its name from Oberon.Par, with a Texts scanner, exactly as a
command clicked in a text would. Model finds the model through the link of the text field named
Number.

(Question: models make sense beyond sliders. A BasicGadgets.NewString model shown by two text
fields in two windows: what happens when you type into one of them?)

## A gadget of your own

Our third program is a gadget we write ourselves: a lamp, on or off. A middle click switches it
and runs its command, which counts the lamps that are on; a button switches them all off. The
module follows Skeleton.Mod, the template ETH gave for new gadgets:

    MODULE Lamps;  (* a gadget of our own: a lamp, on or off; a middle click switches it and runs its command *)

    IMPORT Files, Display, Display3, Effects, Objects, Oberon, Gadgets, Attributes,
      Panels, Documents, PanelDocs, DocWindows, Windows;

    CONST middle = 1;  (* the middle mouse button in M.keys *)

    TYPE
      Lamp* = POINTER TO LampDesc;
      LampDesc* = RECORD (Gadgets.FrameDesc)
        on*: BOOLEAN
      END;

    (* the attributes: On, and Cmd, run after a click; the others are those of every gadget *)
    PROCEDURE Attrs(F: Lamp; VAR M: Objects.AttrMsg);
    BEGIN
      IF M.id = Objects.get THEN
        IF M.name = "Gen" THEN M.class := Objects.String; M.s := "Lamps.New"; M.res := 0
        ELSIF M.name = "On" THEN M.class := Objects.Bool; M.b := F.on; M.res := 0
        ELSIF M.name = "Cmd" THEN
          Gadgets.framehandle(F, M);
          IF M.res < 0 THEN M.class := Objects.String; M.s := ""; M.res := 0 END
        ELSE Gadgets.framehandle(F, M)
        END
      ELSIF M.id = Objects.set THEN
        IF (M.name = "On") & (M.class = Objects.Bool) THEN F.on := M.b; M.res := 0
        ELSE Gadgets.framehandle(F, M)
        END
      ELSIF M.id = Objects.enum THEN
        M.Enum("On"); M.Enum("Cmd"); Gadgets.framehandle(F, M)
      END
    END Attrs;

    (* draw the lamp at x, y (w x h), only where the mask Q lets it *)
    PROCEDURE Restore(F: Lamp; Q: Display3.Mask; x, y, w, h: INTEGER);
    VAR r: INTEGER; col: Display.Color;
    BEGIN
      Display3.ReplConst(Q, Display3.groupC, x, y, w, h, Display.replace);
      IF F.on THEN col := Display.RGB(255, 210, 0) ELSE col := Display.RGB(70, 70, 70) END;
      r := w; IF h < r THEN r := h END; r := r DIV 2 - 4;
      Display3.Circle(Q, col, Display.solid, x + w DIV 2, y + h DIV 2, r, 1, {Display3.filled}, Display.replace);
      IF Gadgets.selected IN F.state THEN
        Display3.FillPattern(Q, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
      END
    END Restore;

    PROCEDURE Copy*(VAR M: Objects.CopyMsg; from, to: Lamp);
    BEGIN to.on := from.on; Gadgets.CopyFrame(M, from, to)
    END Copy;

    (** The handler: every message to a lamp comes here *)
    PROCEDURE Handle*(F: Objects.Object; VAR M: Objects.ObjMsg);
    VAR x, y, w, h: INTEGER; F1: Lamp; Q: Display3.Mask; keysum: SET;
    BEGIN
      WITH F: Lamp DO
        IF M IS Display.FrameMsg THEN
          WITH M: Display.FrameMsg DO
            IF (M.F = NIL) OR (M.F = F) THEN  (* to this frame, or to all *)
              x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;  (* where it is on the screen *)
              IF M IS Display.DisplayMsg THEN
                WITH M: Display.DisplayMsg DO
                  IF (M.device = Display.screen) & ((M.id = Display.full) OR (M.F = NIL)) THEN
                    Gadgets.MakeMask(F, x, y, M.dlink, Q); Restore(F, Q, x, y, w, h)
                  ELSIF (M.device = Display.screen) & (M.id = Display.area) THEN
                    Gadgets.MakeMask(F, x, y, M.dlink, Q);
                    Display3.AdjustMask(Q, x + M.u, y + h - 1 + M.v, M.w, M.h);
                    Restore(F, Q, x, y, w, h)
                  END
                END
              ELSIF M IS Oberon.InputMsg THEN
                WITH M: Oberon.InputMsg DO
                  IF (M.id = Oberon.track) & Gadgets.InActiveArea(F, M) & (M.keys = {middle}) THEN
                    keysum := M.keys;  (* follow the mouse until all buttons are up *)
                    REPEAT Effects.TrackMouse(M.keys, M.X, M.Y, Effects.PointHand); keysum := keysum + M.keys
                    UNTIL M.keys = {};
                    IF keysum = {middle} THEN  (* only the middle button: a click *)
                      F.on := ~F.on; Gadgets.Update(F);
                      Gadgets.ExecuteAttr(F, "Cmd", M.dlink, NIL, NIL)
                    END;
                    M.res := 0
                  ELSE Gadgets.framehandle(F, M)  (* moving, resizing, selecting: as every gadget *)
                  END
                END
              ELSE Gadgets.framehandle(F, M)
              END
            END
          END
        ELSIF M IS Objects.AttrMsg THEN Attrs(F, M(Objects.AttrMsg))
        ELSIF M IS Objects.CopyMsg THEN
          WITH M: Objects.CopyMsg DO
            IF M.stamp = F.stamp THEN M.obj := F.dlink  (* copied already in this copy *)
            ELSE NEW(F1); F.stamp := M.stamp; F.dlink := F1; Copy(M, F, F1); M.obj := F1
            END
          END
        ELSIF M IS Objects.FileMsg THEN  (* storing and loading, with the panel or document *)
          WITH M: Objects.FileMsg DO
            IF M.id = Objects.store THEN Files.WriteBool(M.R, F.on)
            ELSIF M.id = Objects.load THEN Files.ReadBool(M.R, F.on)
            END;
            Gadgets.framehandle(F, M)
          END
        ELSE Gadgets.framehandle(F, M)
        END
      END
    END Handle;

    PROCEDURE Init*(F: Lamp);
    BEGIN F.W := 40; F.H := 40; F.on := FALSE; F.handle := Handle
    END Init;

    (** Lamps.New  the generator: Gadgets.Insert Lamps.New ~ puts a lamp at the caret *)
    PROCEDURE New*;
    VAR F: Lamp;
    BEGIN NEW(F); Init(F); Objects.NewObj := F
    END New;

    PROCEDURE Add(P: Panels.Panel; gen: ARRAY OF CHAR; x, y, w, h: INTEGER): Display.Frame;
    VAR obj: Objects.Object; F: Display.Frame;
    BEGIN
      obj := Gadgets.CreateObject(gen); F := obj(Display.Frame);
      F.W := w; F.H := h;
      Panels.InsertChild(P, F, x, y - h);
      RETURN F
    END Add;

    (** Lamps.Open  three lamps and a count in a window of their own *)
    PROCEDURE Open*;
    VAR D: Documents.Document; P: Panels.Panel; F: Display.Frame; i: INTEGER; name: ARRAY 4 OF CHAR;
      V: Windows.Window;
    BEGIN
      PanelDocs.NewDoc; D := Objects.NewObj(Documents.Document);
      D.name := "Lamps"; D.W := 200; D.H := 110;
      P := D.dsc(Panels.Panel);
      i := 0;
      WHILE i < 3 DO
        F := Add(P, "Lamps.New", 15 + 60*i, -10, 50, 50);
        name := "L0"; name[1] := CHR(ORD("1") + i); Gadgets.NameObj(F, name);
        Attributes.SetString(F, "Cmd", "Lamps.Count");
        INC(i)
      END;
      F := Add(P, "TextFields.NewTextField", 15, -70, 110, 25); Gadgets.NameObj(F, "Count");
      F := Add(P, "BasicGadgets.NewButton", 135, -70, 50, 25);
      Attributes.SetString(F, "Caption", "Off"); Attributes.SetString(F, "Cmd", "Lamps.AllOff");
      V := DocWindows.Open(D);
      Windows.Run(V)
    END Open;

    PROCEDURE ThisLamp(n: INTEGER): Objects.Object;  (* lamp n (1..3) of the panel of the command *)
    VAR name: ARRAY 4 OF CHAR;
    BEGIN name := "L0"; name[1] := CHR(ORD("0") + n); RETURN Gadgets.FindObj(Gadgets.context, name)
    END ThisLamp;

    (** Lamps.Count  how many lamps are on, into the text field Count *)
    PROCEDURE Count*;
    VAR i, n: INTEGER; on: BOOLEAN; s: ARRAY 32 OF CHAR; obj: Objects.Object;
    BEGIN
      n := 0; i := 1;
      WHILE i <= 3 DO Attributes.GetBool(ThisLamp(i), "On", on); IF on THEN INC(n) END; INC(i) END;
      s := "0 of 3 on"; s[0] := CHR(ORD("0") + n);
      obj := Gadgets.FindObj(Gadgets.context, "Count");
      Attributes.SetString(obj, "Value", s); Gadgets.Update(obj)
    END Count;

    (** Lamps.AllOff  every lamp off *)
    PROCEDURE AllOff*;
    VAR i: INTEGER; obj: Objects.Object;
    BEGIN
      i := 1;
      WHILE i <= 3 DO obj := ThisLamp(i); Attributes.SetBool(obj, "On", FALSE); Gadgets.Update(obj); INC(i) END;
      Count
    END AllOff;

    END Lamps.

    loksh compiler.Compile Lamps.Mod
    loksh Lamps.Open

A lamp is a record extending Gadgets.FrameDesc, the frame every visual gadget is, with one field
of its own, on. Everything else is in Handle, which answers the messages:

    - Display.DisplayMsg: draw yourself. Gadgets.MakeMask gives the mask of the lamp, the parts of
      it that are visible (another gadget can lie on top of it); the Display3 procedures draw only
      inside the mask. A whole frame is drawn for id full; for id area only the rectangle u, v, w,
      h of it, so AdjustMask cuts the mask down to it.

    - Oberon.InputMsg: the mouse. Gadgets.InActiveArea tells whether the mouse is on the lamp and
      not on its border, where the default handler resizes and moves the gadget. On a middle
      click (the middle button, and no other one pressed before all were released) the lamp
      switches, shows it, and runs its Cmd. Every other mouse event goes to the default handler:
      moving, resizing and selecting work as with every gadget, without a line of our code.

    - Objects.AttrMsg: the attributes. get, set and enum (list them) for On and Cmd; Gen, the
      name of the generator, is how a stored lamp is made again when loaded. The other
      attributes (Name, ...) are the default handler's.

    - Objects.CopyMsg: copy yourself. The stamp makes sure that a lamp reached twice in one copy
      (a group of gadgets can share parts) is copied once.

    - Objects.FileMsg: store yourself, load yourself: our field, then the default handler's.

    - Anything else, to Gadgets.framehandle, the default handler of frames.

New is the generator; in the desktop, Gadgets.Insert Lamps.New ~ puts a lamp into any panel, and
the inspector shows its On and Cmd. Count and AllOff are commands like those of Hello; Count
reads the attribute On of each lamp, AllOff sets it, and Gadgets.Update makes the lamps draw
themselves again (the default handler answers the update with a DisplayMsg to the lamp).

(Question: the lamp draws a circle in two colours. What would it take to give it an attribute
Color, so that the inspector can make a red lamp? Look at how Skeleton.Mod does it.)

## Storing and loading

A document stores itself with D.Store(D) under its name, and Documents.Open(name) loads it:

    PanelDocs.NewDoc; D := Objects.NewObj(Documents.Document); D.name := "My.Panel";
    ... insert gadgets into D.dsc ...
    D.Store(D);
    D := Documents.Open("My.Panel")

The panel stores each gadget with its generator name (the attribute Gen), its attributes and its
links; loading calls the generators again, which loads their modules. A stored panel with lamps
therefore needs no program at all to be opened: DocWindows.OpenDoc My.Panel loads Lamps by
itself, and the lamps come back on or off as they were stored. This is the usual shape of an
Oberon program: a panel, stored, and a module of commands that its buttons run.

## Programs of their own

Run from the shell, loksh Hello.Open is a program of its own: only its window is shown (the
desktop's screen stays hidden), and loksh ends when the last window is closed. A script starts it
like any other program:

    #!/bin/sh
    cd /home/me/hello && exec /home/me/polpo/bin/x86/loksh Hello.Open

loksh loads modules from obj/x86/ of the current directory before those of polpo, so the cd
matters: that is where compiler.Compile put Hello.Obj. (A program installed as a package of
portia has its objects in polpo's obj/, and needs no cd.)

Without the desktop, a few things of the desktop are missing: System.Log, where commands write
their messages (output with out still goes to the terminal), the Trap viewer (a trap ends the
program and prints where it happened), and documents that the program opens with
Desktops.OpenDoc land in the desktop that nobody sees: open them with DocWindows.OpenDoc instead.
The fonts stay at their size; the desktop scales them (System.SetFontScale), so panels made for
the desktop can look a little smaller.

Windows of their own exist with X11. On the Linux console (the framebuffer or KMS) and in a
terminal with sixel graphics, the gadgets run in the desktop as they always did.

## The other ports

The three programs compile unchanged with all five of polpo's compilers:

    loksh acompiler.Compile Hello.Mod      ARM, objects in obj/arm/
    loksh a7compiler.Compile Hello.Mod     ARMv7
    loksh rvcompiler.Compile Hello.Mod     RISC-V
    loksh mcompiler.Compile Hello.Mod      MIPS

and run there, on such a machine or on x86 under qemu (qemu-arm bin/arm/loksh Lamps.Open), with
the gadgets installed for that port (portia.Install /arm gadgets). The compilers of the other
ports are a little stricter than the x86 one: declare everything before the procedures, and
declare a procedure before its first call; programming.md lists the rest. (No compiler accepts a
type guard on the result of a call, Gadgets.CreateObject(gen)(Display.Frame): assign it to a
variable first, as Add does.)

## Where to go from here

    Desktops.OpenDoc Gadgets.Panel     the gadgets there are, to insert and try
    Columbus.Inspect                   the attributes of any gadget
    src/pkg/gadgets/src/               the sources: BasicGadgets for buttons, check boxes and
                                       sliders with models, TextFields, Panels, Documents
    portia.List gadgets                programs and games made of gadgets, to read

A program that is more than a panel becomes a document type of its own (a picture editor, a
game board): Documents.Document has Load and Store procedures, and TextDocs.Mod and PanelDocs.Mod
show how they are written. programming.md tells how to make a package of your program, so that
portia installs it for others, with a test that portia runs on every port.
