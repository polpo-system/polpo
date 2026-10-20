# Using the Desktop

The desktop of polpo is the desktop of ETH Oberon: texts in viewers, in which any Module.Command
can be run with the mouse. This note describes how to use it. gentle-introduction.md is a slower
first walk through it, programming.md is for writing commands, and texts.md is about the
configuration text Oberon.Text.

## Starting it

    bin/x86/loksh System.Init

opens the desktop in an X11 window (DISPLAY must be set). On the other ports it is bin/arm/loksh
System.Init and so on. The desktop can also draw itself inside an xterm with sixel graphics,
without X11: make sixel switches to that, and run.vt.sh opens a suitable xterm (the readme has the
details).

Without X11 and without a terminal, on the Linux console: started there (TERM is linux), the
desktop draws on the whole screen itself, through /dev/fb0 when the kernel has it, else through
KMS (/dev/dri/card0, the kernel's graphics driver, in the preferred mode of the first connected
screen). It reads the keyboard from the console and the mouse from /dev/input/mice. No other
program may be showing the screen then (an X server or Wayland on that console); switch to a free
console with Ctrl+Alt+F2 first. booting.md starts a machine with polpo as its only program, the desktop
on the whole screen from the start.

loksh loads modules from obj/<arch>/ of the directory it is started in before those of polpo, so
a project with objects of its own starts the desktop in its directory. Oberon.Text is the
configuration (fonts, and System.InitCommands, the commands run at the start).

## The screen

The screen is divided into two tracks, columns of viewers. The wide one on the left is the user
track, where texts are opened; the right one is the system track, with System.Log (the messages of
the system) and System.Tool (a text of useful commands). Each viewer has a menu bar at its top,
with the viewer's name and commands for it: System.Close, System.Copy (a second viewer of the same
text), System.Grow (as high as the track, or as large as the screen; System.Close gives the place
back) and Edit.Store.

## Workspaces

When the screen fills up, open another one. Workspaces.Add makes a new workspace, with its own
user track and system track, System.Log and System.Tool, and shows it. Workspaces.Right and
Workspaces.Left go to the next workspace and back (after the last comes the first again),
Workspaces.Go 3 goes to the third, and Workspaces.Close closes the one shown, with all its
viewers (Workspaces.Close 2 closes the second). Workspaces.Show writes in System.Log which one is
shown, and how many there are. System.Tool has the first four commands near its top.

The viewers of the workspaces that are not shown keep their texts and their places; they are drawn
again when their workspace comes back, and what was written into System.Log meanwhile is there. There
can be 16 workspaces. They work the same with X11, in the text console (KMS or framebuffer) and in a
terminal with sixel graphics.

## The mouse

The three buttons each have their own work, and clicking a second button while the first is still
held, an interclick, changes what happens:

| button | in a text | with an interclick |
| --- | --- | --- |
| left | sets the caret, where typed text goes | with the middle: copies the selection to the caret |
| middle | runs the command under the mouse | with the right: opens the word under the mouse as a file (Edit.Open); with the left: unloads the command's module first, so that it is loaded anew (after compiling it) |
| right | selects: press, move from here to there, release | with the left: deletes the selection; with the middle: copies it to the caret |

Shift and a right click extend the selection to the mouse, or select from the caret to the mouse,
as in xterm. The selection stays when the text is scrolled, so a long piece is selected by a right
click at its start, scrolling with the scroll bar, and Shift with a right click at its end. A selection is also given to the clipboard of X11.

In the menu bar, dragging with the left button moves the top edge of the viewer, so that it gets
larger or smaller; with the middle button added, the viewer moves to wherever the mouse is
released, also into the other track. In the scroll bar at the left of a text, a left click makes
the line at the mouse the first one shown, a right click goes back a page (with the middle button,
to the start), and a middle click goes to the place at the mouse, in proportion to the length of
the text (with the left button, to the end).

## Commands and their parameters

A command runs where it stands. Clicking System.Directory fonts/*.Scn.Fnt lists the fonts, clicking
Edit.Open System.Tool opens that text. What follows the command on its line, up to a ~, are its
parameters, and a few signs have a meaning there. ^ stands for the selection: Edit.Open ^ opens
the file whose name is selected. * stands for the viewer with the star marker: F1 puts the star
where the mouse is, and then, for example, Edit.Store * stores that viewer's text. Esc takes away
the selections, the caret and the star.

Commands written for the console, with out, print into System.Log in the desktop, so portia.Install
or fs.Ls clicked in a text show their output there.

Tab after a word completes it, as in the shell of loksh: the first word of a line as a command
(Desk becomes Desktops., Desktops.Op becomes Desktops.Open), the words after it as file names, with
directories (Edit.Open src/desk becomes src/desktop/; ~ is not known there). When several
names fit, what they have in common is added and System.Log lists them. Tab inside a word, after a
blank or after a word that is already complete inserts a tab, as before.

Enter right after Tab completed a command (Desktops.Op, Tab, Enter) runs it, as a middle click
on it would. After a completion that leaves several choices, or a file name, Enter starts a new
line.

## Opening, storing and closing texts

Edit.Open name opens a text in the user track; a middle click with the right button on a name does
the same. System.Open name opens it in the system track, which is the place for tool texts
(System.Open Edit.Tool), and Script.Open name opens it with its styles (paragraphs, colours), as
System.Text is shown. Edit.Store in the menu bar of a viewer stores its text, as an Oberon text with
its fonts; Edit.StorePlain stores it as plain text, for sources and other plain files. (Note: a
plain file stays plain when it is stored with Edit.Store; only Oberon texts keep fonts.)

Tools.Open (in System.Tool) lists the tool texts of the system and of the installed packages, each on
a line with what it is for; a middle click on Edit.Open in a line opens that tool text.

System.Close closes a viewer, and System.Recall opens the last closed one again. Edit.Recall puts
the text deleted last back at the caret. Edit.Search, clicked in the menu bar of a viewer, finds the
selected text in that viewer, from the caret on.

## Editing with the keyboard

Click with the left button where you want to type. The arrows, Home and End, Page Up and Page Down
move the caret, and with Shift they select. Backspace and Del delete; a selection made with the
keyboard is deleted as a whole. Ctrl+A selects everything, and Ctrl+C, Ctrl+X and Ctrl+V copy, cut
and paste with the clipboard of X11, so also to and from other programs. Ctrl+B starts a block
selection (a rectangle of columns) and ends it again; typing in a block types on every one of its
lines.

## Fonts and colours

Edit.ChangeFont Oberon20.Scn.Fnt gives the selection that font, and System.Directory fonts/*.Scn.Fnt
shows which fonts there are. Edit.CopyFont gives the selection the font of the character at the
star marker. System.SetFont Oberon12.Scn.Fnt chooses the font for what is typed from then on.
Edit.ChangeColor 3 colours the selection with colour 3 of the Oberon palette (there are 16); a
parameter that is not a number gives its own colour, so Edit.ChangeColor x with the x written in
red makes the selection red.

System.SetFontScale 150 makes all fonts larger, in percent (Oberon.Text has the default), and
Edit.ScaleFonts 200 * only those of the viewer with the star. System.Tool has more examples to
click. After changing a text, remember to store it.

## Looking at a module's interface

Select a module name and click the browser of the port: XBrowser.ShowDef ^ on x86,
ABrowser.ShowDef ^ on ARM, RBrowser.ShowDef ^ on ARMv7, RISC-V and MIPS. It opens the definition of
the module, its exported types, variables and procedures, in a viewer. XBrowser.ShowDef Texts names
the module directly. On the console the same is browser.ShowDef Texts (see programming.md).

## Browsing Gemini and Spartan

Pishmish.Open gemini://geminiprotocol.net/ ~ opens a viewer with the page, rendered: headings,
links, lists, quotes and preformatted text, in a Unicode font. A middle click on a link follows it in
the same viewer, and the menu of the viewer has Pishmish.Back and Pishmish.Reload. When a page asks
for input, it shows a line Pishmish.Send ~: write the answer after the command and click it. When a
server wants a certificate, it lists your identities as Pishmish.Ident lines; DCS.NewIdent makes a
new one. tools/Pishmish.Tool has more commands, and DCS.Get shows an answer as it arrived.

## Windows of their own

Windows.OpenText name opens a text in an X11 window of its own, beside the desktop, 640 x 480 or
the size given after the name (Windows.OpenText System.Tool 500 300). The window looks like the
windows of the other programs: the window manager gives it a title bar, moves it, and its close
button closes it. Inside it works as a viewer does: click to type, middle-click commands, select.
With the package gadgets, DocWindows.OpenDoc name opens a document the same way, as large
as the document: DocWindows.OpenDoc HPCalc.Panel. There are at most 16 windows, each at most as
large as the screen, and only with X11 (not in a terminal with sixel graphics).

Such a window also works without the desktop, as a program of its own: run from a shell,
loksh Windows.OpenText System.Tool or loksh DocWindows.OpenDoc HPCalc.Panel shows only that window
(the desktop's screen stays hidden), and loksh ends when it is closed.

## Stopping and pausing a command

A command runs until it ends, and meanwhile the desktop waits; the games, for example, take it over
while they run. Ctrl+Pause (Break) or Ctrl+Alt+C stops the running command at once, in X11, and in
the sixel desktop Ctrl+Alt+C; Ctrl+C in the terminal where loksh runs does the same. A Trap viewer
then shows where the command stood ("Keyboard interrupt"), and the desktop goes on.

Ctrl+Alt+P pauses the running command instead. The desktop works again while the command waits,
and Ctrl+Alt+P once more, while no other command runs, continues it where it was; the Log says
"paused" and "continued". This all happens in the one thread of Oberon: the paused command simply
stays where it was, and the desktop runs again on top of it. So paused commands pile up. If you
pause a game, start another command in the paused desktop and pause that too, Ctrl+Alt+P continues
the last one first, then the one before; at most 8 can be paused. While a command is paused, do not
close its viewers or start it a second time, because it continues with what it had. A trap, or
Ctrl+Alt+C, while commands are paused ends them all, and the Log says how many.

Question: what is left of a command that was stopped? (Its module keeps its variables as they were,
and files it had open stay open. That is safe for the system, but the module may be half way
through something; System.Free Module unloads it, so that it starts fresh the next time.)

## When something goes wrong

A trap, an error in a command or a stop, opens a Trap viewer with the procedures that were running
and their variables, and Kernel.Log in the start directory has the details too. The desktop goes
on. System.ShowModules lists the loaded modules, System.Free Module unloads one (after compiling it
again, for example), and System.Quit ends the desktop.
