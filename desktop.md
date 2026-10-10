# Using the desktop

The desktop of polpo is the ETH Oberon desktop: texts in viewers, where any `Module.Command` in
any text is a command you can run with the mouse. This page is for using it; `programming.md` is
for writing commands, `texts.md` for Oberon texts.

## Starting it

```
bin/x86/loksh System.Init        # in X11 (DISPLAY set); bin/arm/loksh ... on the other ports
```

It can also draw itself in an xterm with sixel graphics, without X11 (`make sixel`, then
`run.vt.sh`, see the readme). loksh loads modules from `obj/<arch>/` of the directory it is started
in before those of polpo, so a project with its own objects starts the desktop in its directory.
`Oberon.Text` is the configuration (fonts, the commands run at the start: `System.InitCommands`).

## The screen

The screen has two **tracks**, columns of **viewers**: the wide user track on the left, where texts
open, and the system track on the right (`System.Log` with the messages, `System.Tool` with useful
commands). Each viewer has a **menu bar** at the top: its name, then commands for it, as
`System.Close`, `System.Copy` (a second viewer of the same text), `System.Grow` (as large as the
track, or the screen; `System.Close` gives the place back), `Edit.Store`.

## The mouse

The three buttons are not the same; clicking a second button while the first is held (an
**interclick**) changes what happens:

| button | in a text | with an interclick |
| --- | --- | --- |
| **left** | sets the caret, where typing goes | + middle: copies the selection to the caret |
| **middle** | runs the command under the mouse (`Edit.Open Hello.Mod`) | + right: opens the word under the mouse as a file (`Edit.Open`); + left: unloads the command's module first and loads it new (after compiling it) |
| **right** | selects: press, drag from here to there, release | + left: deletes the selection; + middle: copies it to the caret |

- **Shift + right click** extends the selection to the mouse, or selects from the caret to the mouse,
  as in xterm. A selection is also copied to the clipboard of X11.
- In the **menu bar**, dragging with the left button moves the top of the viewer (making it larger
  or smaller); with the middle button added, the viewer moves to where the mouse is released, also
  into the other track.
- In the **scroll bar** at the left of a text: a left click makes the line at the mouse the first
  one shown, a right click goes back a page (+ middle: to the start), a middle click goes to the
  place at the mouse (in proportion to the text; + left: to the end).

## Commands and their parameters

A command is run where it stands: clicking `System.Directory fonts/*.Scn.Fnt` lists fonts, clicking
`Edit.Open System.Tool` opens that text. What follows the command are its parameters, up to the end
of the line or a `~`. Some parameter signs:

- `^` is the selection: `Edit.Open ^` opens the file whose name is selected;
- `*` is the viewer with the **star** marker: press **F1** to put the star where the mouse is,
  then for example `Edit.Store *` stores that viewer's text;
- **Esc** takes away the selections and the caret (and the star).

## Opening, storing and closing texts

| command | what it does |
| --- | --- |
| `Edit.Open name` | opens a text in the user track (middle + right on a name does the same) |
| `System.Open name` | opens it in the system track, for tool texts (`System.Open Edit.Tool`) |
| `Script.Open name` | opens it with styles (paragraphs, colours), as `System.Text` |
| `Edit.Store` | in the menu bar of a viewer: stores its text, as an Oberon text with fonts |
| `Edit.StorePlain` | the same as plain text, without fonts (for sources and other plain files) |
| `System.Close` | closes the viewer; `System.Recall` opens the last closed one again |
| `Edit.Recall` | puts back the text deleted last, at the caret |
| `Edit.Search` | in the menu bar: finds the selected text in this viewer, from the caret on |

Plain files stay plain when they are stored with `Edit.Store`; Oberon texts keep their fonts.

## Editing with the keyboard

Click with the left button where to type, then:

- **arrows**, **Home** / **End**, **Page Up** / **Page Down** move the caret; with **Shift** they
  select;
- **Backspace** and **Del** delete (a selection made with the keyboard as a whole);
- **Ctrl+A** selects all, **Ctrl+C** copies, **Ctrl+X** cuts, **Ctrl+V** pastes, with the clipboard of
  X11 (also from and to other programs);
- **Ctrl+B** starts a block selection (columns), and ends it; typing in a block types on every line.

## Fonts and colours

- `Edit.ChangeFont Oberon20.Scn.Fnt` gives the selection that font; `System.Directory fonts/*.Scn.Fnt`
  lists the fonts there are;
- `Edit.CopyFont` gives the selection the font of the character at the star marker (F1);
- `System.SetFont Oberon12.Scn.Fnt` is the font for what is typed from then on;
- `Edit.ChangeColor 3` colours the selection (the colours 0 .. 15 of the Oberon palette); a
  parameter that is not a number gives its own colour: `Edit.ChangeColor x` with the x in red;
- `System.SetFontScale 150` makes all fonts larger (in percent; `Oberon.Text` has the default),
  `Edit.ScaleFonts 200 *` only those of the viewer with the star.

`System.Tool` has more examples to click. After changing a text, store it (`Edit.Store`).

## Looking at a module's interface

Select a module name, then click the browser of the port: `XBrowser.ShowDef ^` on x86,
`ABrowser.ShowDef ^` on ARM, `RBrowser.ShowDef ^` on ARMv7, RISC-V and MIPS. It opens the
definition of the module (its exported types, variables and procedures) in a viewer;
`XBrowser.ShowDef Texts` names the module directly. In the console the same is
`browser.ShowDef Texts` (see `programming.md`).

## Stopping and pausing a command

A command runs until it ends; meanwhile the desktop waits (games, for example, take it over).

- **Ctrl+Pause/Break** or **Ctrl+Alt+C** stops the running command at once (in X11 and, for
  Ctrl+Alt+C, in the sixel desktop); **Ctrl+C** in the terminal where loksh runs does the same. A
  **Trap** viewer shows where it stood ("Keyboard interrupt"), and the desktop goes on.
- **Ctrl+Alt+P** pauses the running command: the desktop works again while the command waits; Ctrl+Alt+P
  again (while no other command runs) continues it where it was. The Log says "paused" and
  "continued".

A stopped command does not finish what it was doing: its module keeps its variables as they were,
files it had open stay open. That is safe for the system, but the module may be in a half state;
`System.Free Module` unloads it, so that it starts fresh next time.

Paused commands are all in the one thread, one on top of the other: pause a game, start another
command in the paused desktop, pause that too, and Ctrl+Alt+P continues the last one first, then the
one before (at most 8). While a command is paused, do not close its viewers or start it a second
time: it continues with what it had. A trap (or Ctrl+Alt+C) while commands are paused ends them
all; the Log says how many.

## When something goes wrong

A trap (an error in a command, or a stop) opens a **Trap** viewer with the procedures that were
running and their variables; `Kernel.Log` in the start directory has the details too. The desktop
goes on. `System.ShowModules` lists the loaded modules, `System.Free Module` unloads one (after
compiling it again, for example), `System.Quit` ends the desktop.
