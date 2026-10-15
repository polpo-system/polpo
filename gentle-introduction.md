# A Gentle Introduction to polpo

(Last updated: 12 October 2026.)

## Contents

    Background
    Introduction
    The console: loksh
    Modules and commands
    Compiling your first module
    Changing a module
    Looking at an interface
    Texts
    Commands from the Unix shell, and their parameters
    The desktop
    Packages
    The other ports
    When a command does not stop
    Where to go from here

## Background

This note is for those who meet Oberon for the first time and have used a Unix shell and done
some programming in C, Pascal, Python or a similar language. It is not a manual of the Oberon
language, nor of the Oberon system; it shows how to find your way around polpo, so that you can
start to read and write Oberon programs. For the language and the system themselves, please read:

    N. Wirth and J. Gutknecht, "Project Oberon: The Design of an Operating System and Compiler",
    Addison-Wesley, 1992. (The Oberon system explained by the two who built it, with all of its
    source code. A revised edition, for the RISC computer of 2013, is free on the web.)

    M. Reiser, "The Oberon System: User Guide and Programmer's Manual", Addison-Wesley, 1991.
    (How to use the system, and how to program for it.)

    M. Reiser and N. Wirth, "Programming in Oberon: Steps Beyond Pascal and Modula",
    Addison-Wesley, 1992. (The language, with many small examples; the XY plane some of our games
    draw on comes from this book.)

    N. Wirth, "The Programming Language Oberon" (the report, a few pages long).

polpo itself comes with more pages, written for later: desktop.md (the desktop, in detail),
programming.md (writing commands), texts.md (the configuration text) and the readme.

## Introduction

Oberon is a programming language and an operating system, both designed by Niklaus Wirth and
Juerg Gutknecht at ETH Zurich in the late 1980s. The language is a successor to Pascal and
Modula-2, and smaller than both. The system was written in the language, and was meant to be
understood completely by one person: the compiler, the file system, the windows, the text editor,
all of it.

Over the years ETH made several versions of the system. The one polpo continues is ETH Oberon (also
called Oberon System 3), and in particular the version that ran on top of Linux (ETH Linux Oberon,
then it becameOLR by Peter Matthias).

polpo is a revival effort of it: it runs on Linux on x86, ARM, ARMv7, RISC-V and MIPS, and on
each of them it is one program called `loksh`: Linux Oberon Kommand Shell. 

Everything else (the compilers, the desktop, the
tools) is Oberon modules that loksh loads when they are needed.

There are a few ideas that make Oberon different from the systems you know, and it helps to have
them in mind from the start:

    there are no programs, only modules; a module offers commands, which you call by name,
    as Module.Command; there is no `main()`, that is one entry point, like in other programming
    languages.

    a module is loaded once and stays loaded; its variables keep their values between commands;

    any text can contain commands: in the desktop you click on Edit.Open some.Tool written in a
    text, and it runs;

    the system and your programs live in the same world: your module calls the modules of the
    system directly, as the system's own modules do.

(Note: compared with C, a module is like a .c file and its .h file together. What a module wants
others to use, it marks with an asterisk; everything else is private. There is no separate
header: the compiler writes the interface of the module into a symbol file.)

## The console: loksh

When you have a copy of polpo (a git clone of it is enough: the compiled objects and the loksh
binaries are in the repository), go into its directory and start loksh:

    $ bin/x86/loksh
    >

On ARM, RISC-V or MIPS there is bin/arm/loksh, bin/riscv/loksh and so on; everything I show here
works the same on all of them. The > is the prompt of loksh's shell: it reads commands one per
line and runs them. Try

    > fs.Pwd
    /home/you/polpo

fs is a module, Pwd one of its commands, and fs.Pwd prints the current directory. You do not have
to type all of it. Type fs. and press Tab, and loksh shows the commands of fs; type the first
letters of a name and press Tab, and loksh completes it, or shows the names that begin so. The
arrows up and down bring back the commands typed before, and Ctrl+D ends the shell.

All commands of this shell run in the same loksh, so a module loaded by the first command is still
there for the second, with its variables as the first command left them. (Note: that is the
normal way of things in Oberon. The system is never restarted between commands; a module is
loaded on its first use, its body runs once, and it stays until someone unloads it.)

Question: what does fs alone, typed at the prompt, print? (Try it. A module name alone lists the
commands of the module.)

## Modules and commands

In the polpo directory there is a small module for you to play with, hello.Mod. Let us look at it
without leaving the shell. Type tex and press Tab: loksh completes it to texts., and a second Tab
shows the commands of the module texts:

    > texts.
    DeleteLines Replace Show ShowPlain

The first two change files, as sed does on Unix; Show prints a file, as cat does. Type S and press
Tab: there are two commands beginning with S, Show and ShowPlain, so loksh shows both and waits.
Type how and a blank, then h and Tab, and loksh completes the file name:

    > texts.Show hello.Mod
    MODULE hello;
    IMPORT out;

    PROCEDURE world*;
    BEGIN
      out.String("hey hey!"); out.Ln;
    END world;

    END hello.

A module starts with MODULE and its name and ends with END, the name and a full stop. The IMPORT
line says which other modules it uses: here only out, which writes to the terminal. Then come its
declarations. world is a procedure, and the asterisk after its name exports it, so that it can be
used from outside the module. An exported procedure without parameters is a command: you can call
it as hello.world.

All keywords of Oberon are written in capital letters, and the language distinguishes upper and
lower case everywhere: hello, Hello and HELLO are three different names. Comments are written
between (* and *), and they may be nested.

(Remarks: console modules in polpo have lowercase names, as out, texts, fs and net; the modules of
the desktop have capitalised names, as Texts, Oberon and Display, the names ETH gave them. This is
only a convention, but it tells you at once which world a module belongs to.)

## Compiling your first module

First let us see what is in memory now:

    > system.ShowModules
    system  846     0
    shell   31880   0
    texts   7595    3
    ...
    Kernel  18382   14
    Linux0  1651    8
    TOTAL   139937  21

These are the modules loaded so far, each with its size in bytes and the number of loaded modules
that import it: the kernel, the files, the module loader, the shell and the few modules they need,
and texts, which we just used. The compiler is a module too. Compile hello:

    > compiler.Compile hello.Mod
    hello.Mod compiling obj/x86/hello new symbol file   33

It wrote two files: obj/x86/hello.Obj, the code, and obj/x86/hello.Sym, the symbol file with the
interface of the module, its exported names. Look into memory again:

    > system.ShowModules
    compiler  6159  0
    OPV     18942   1
    OPC     51892   2
    ...
    TOTAL   494734  32

The compiler is there now, with the modules it is made of, OPM, OPS, OPT and the others, and it
stays there: the next compilation starts at once. Now run the command:

    > hello.world
    hey hey!

and system.ShowModules lists hello too. It was loaded when we called hello.world, together with
the modules it imports, if they were not loaded yet.

(Note: there is no linker step. Only loksh itself, the small core of the system, is linked; every
other module is loaded from its .Obj file when it is first needed.)

Where do the objects go? The compiler writes into obj/x86/ of the current directory if there is
one, and otherwise into the polpo directory. loksh looks for a module first in obj/x86/ of the
current directory and then in polpo's. So a project of your own can keep its objects to itself:
make a directory, make obj/x86 in it, compile there, and run loksh there.

The same works the other way round: an object in obj/x86/ of the current directory wins over
polpo's own object of the same name. To try a changed version of one of polpo's modules,
compile your copy in such a directory and run loksh there; polpo itself stays as it was.
programming.md ("Trying a changed system module") tells what to keep in mind.

## Changing a module

Now let us give hello a second command. Open the file in xxs, the small editor of the console:

    > xxs.Open hello.Mod

Move with the arrows to the line PROCEDURE world*;, hold Shift and press the down arrow four times:
the four lines of the procedure are selected. Ctrl+C copies them. (Note: in xxs, Ctrl+C copies, as
in other editors; at the prompt of the shell it stops a command.) Press the down arrow once more,
without Shift, which ends the selection, and Ctrl+V pastes the copy. Now there are two procedures
world. Change the second one: call it there, in the PROCEDURE line and after END, and let it write
something else:

    PROCEDURE there*;
    BEGIN
      out.String("hello there!"); out.Ln;
    END there;

Ctrl+O writes the file (Enter confirms the name), Ctrl+X leaves xxs, and you are back at the prompt.
Compile it as before:

    > compiler.Compile hello.Mod
    hello.Mod compiling obj/x86/hello
            there is new
            pos      0  err 155      generation of new symbol file not allowed

The compiler refuses. there is a new exported name, so the interface of hello changed, and the
compiler does not write a new symbol file unless we allow it. Why so careful? Let us look at the
interface the symbol file holds now:

    > browser.ShowDef hello
    DEFINITION hello;

        IMPORT
            out, Linux0;

        PROCEDURE world*;

    END hello.

Other modules that import hello were compiled against this interface, and each of them recorded
it. A new interface means that they must be compiled again, so the compiler wants you to say that
you meant to change it. The option /s says so. Press the up arrow twice, and the compile command
comes back from the history; move left with the arrow to the file name and put /s before it (the
options come before the file name):

    > compiler.Compile /s hello.Mod
    hello.Mod compiling obj/x86/hello extended symbol file   59

The new symbol file extends the old one. Now type hello. and press Tab. Only world is offered!
The hello in memory is still the old one, loaded when we called hello.world; compiling writes new
files, but it does not replace a module that is loaded. hello.world would also still run the old
code. Unload it:

    > system.Free hello

system.ShowModules does not list hello any more. Type hello. and press Tab again: now it offers
there and world, because hello is loaded anew from the new file when it is needed, and

    > hello.there
    hello there!

(Remarks: this is the way of Oberon. A module is loaded once and stays, so after changing it you
free it, and the next command loads the new version. system.Free refuses to free a module that
other loaded modules import, saying that its reference count is not zero; free those first.)

Question: system.ShowModules lists xxs now. Why, and why does a second xxs.Open start faster than
the first?

## Looking at an interface

browser.ShowDef, which we used above, shows what any module offers, without its source:
browser.ShowDef Texts, browser.ShowDef Files, browser.ShowDef out. This is how you learn your way
around the system. Since everything is a module, everything can be looked at this way.

## Texts

Many files in polpo are not plain text but Oberon texts: they keep fonts and colours, and they can
even contain pictures and other objects. Tool texts (tools/*.Tool), the configuration
Oberon.Text and many documents are written so. texts.Show prints them with their fonts as styles
of the terminal, texts.ShowPlain as plain text, and xxs edits them and keeps their fonts:

    > texts.ShowPlain tools/System.Tool
    > xxs.Open tools/System.Tool

Sources (.Mod files) may be plain text or Oberon texts; the compiler reads both. (Note: texts.md
is about one text in particular, Oberon.Text, the configuration of the system.)

## Commands from the Unix shell, and their parameters

You do not have to start the shell of loksh to run one command. From the Unix shell,

    $ bin/x86/loksh hello.there
    $ bin/x86/loksh net.Lookup localhost
    localhost: 127.0.0.1 ::1

starts loksh, runs the command with the rest of the line as its parameters, and stops. And

    $ bin/x86/loksh < commands.txt

runs the commands of a file, one per line, in one loksh. That is how polpo is built: make runs
loksh with the file tools/build.Tool.

How does a command get its parameters, if a procedure without parameters is a command? It reads
them itself, from the text after the command name. A console command does it like this:

    PROCEDURE Hello*;
      VAR A: texts.Reader; name: ARRAY 64 OF CHAR;
    BEGIN
      texts.OpenArgs(A);
      IF texts.Arg(A, name) THEN out.String("hello, "); out.String(name); out.Ln END
    END Hello;

texts.Arg gives the parameters one after the other and returns FALSE when there are no more.
(hello would need IMPORT texts, out; for this.) In the desktop, where the "rest of the line" is
the text after the command in a viewer, the same command works unchanged. programming.md tells the
details.

When the interface of a module changes, as it did with there, the modules that import it must be
compiled again. loksh refuses to load a module that imports an old version of another one, and
tells you which.

## The desktop

Back at the prompt of loksh, start the desktop:

    > System.Init

A window opens (under X11) with the Oberon desktop, and now the whole Oberon system is loaded:
display, fonts, texts, viewers, the editor and the rest. The shell waits while the desktop runs.
If the window does not fit your screen, give its size when you start loksh:

    OWIDTH=1600 OHEIGHT=1000 bin/x86/loksh System.Init

(The desktop also runs inside an xterm with sixel graphics, without X11; the readme tells how.)

The screen is divided into two columns of viewers. On the left, the user track, texts are opened;
on the right, the system track holds the Log (the messages of the system) and System.Tool, a text
full of commands. The mouse has three buttons, and each has its own work:

    the left button sets the caret, where typed text goes;
    the middle button runs the command under the mouse;
    the right button selects text.

On Unix we read manuals with man. In Oberon the place of manuals is taken by tool texts: texts
with a short explanation and the commands ready to be clicked. They are the files ending in
.Tool, in the directory tools/. Let us open the one of Pishmish, the Gemini browser. Click with
the left button at the end of the Log, type

    Edit.Open Pishmish.Tool

press Enter, then point at Edit.Open and click the middle button. A viewer with Pishmish.Tool opens
on the left. (Note: why Enter? The Log keeps growing: the next message of the system is added at
its end, and would otherwise run into the line you typed.)

Each line of Pishmish.Tool that begins with Pishmish. is a command. Click the middle button on the
first one, Pishmish.Open gemini://geminiprotocol.net/. A Pishmish viewer opens with the page of
the Gemini project. If it is small, click System.Grow in its top line, the menu of the viewer, and
it takes the height of the track. The links of the page are blue; a middle click on one follows
it, in the same viewer. Click a link or two, then click Pishmish.Back in the menu of the viewer to
go back. (Note: in tool texts you will meet an upward arrow, as in Pishmish.Open followed by the
arrow. It is the character ^, which Oberon's fonts draw as an arrow, and it stands for the
selection: select a URL with the right button anywhere, then click that command.)

Now let us write a program in the desktop itself. Type in the Log

    Edit.Open Hello2.Mod

and click it as before. Since there is no such file yet, an empty viewer opens. Click into it with
the left button and type:

    MODULE Hello2;
    IMPORT Out;

    PROCEDURE World*;
    BEGIN
      Out.String("hello world"); Out.Ln
    END World;

    END Hello2.

This time we import Out, with a capital O. That is the module of the desktop, and it writes into
the Log; out, the console module we used before, writes to the terminal. Click Edit.Store in the
menu of the viewer, and the text is stored in the file Hello2.Mod. Now type in the Log, each
command followed by Enter,

    Compiler.Compile Hello2.Mod
    Hello2.World

and click them with the middle button, one after the other. The compiler reports in the Log, and
Hello2.World writes hello world below it. This is all there is to running a command in Oberon: any
word of the form Module.Command in any text can be clicked, and what follows it on the line is its
parameters.

(Note: Compiler.Compile * compiles the text of the viewer marked with the star, without storing
it first: press F1 with the mouse over the viewer to put the star there. Edit.Store saves the text
as an Oberon text, with its fonts; Edit.StorePlain saves it as plain text. The compiler reads
both.)

How do you select text? Press the right button where the selection is to begin, move the mouse
to its end with the button held, and let go. That is enough for what you see on the screen. For a
longer piece, begin the same way: press and release the right button at the start. Then scroll
with the scroll bar, the narrow strip at the left of the viewer (a left click there makes the line
at the mouse the first one shown; a right click goes back a page). The selection stays where it
is, even when it is out of view. When you see the end, hold Shift and click the right button
there: the selection now reaches from where it began to the mouse. The keyboard does it too: set
the caret with the left button, then Shift with the arrows, or with Page Down, selects as the
caret moves, and Ctrl+A selects the whole text.

What can you do with a selection? While you still hold the right button, a click of the left
button deletes it, and a click of the middle button copies it to the caret. Ctrl+C copies it to
the clipboard of X11, so that other programs can paste it, and Ctrl+V pastes at the caret.

(Note: this is so in the texts opened with Edit.Open, and in tool texts. System.Text, the text you
see at the start, is opened with Script.Open, which shows styles and pictures; its viewers select
with the right button only.)

The rest is learned by doing: a viewer is closed with System.Close in its menu, and System.Copy
gives a second viewer of the same text. desktop.md describes the mouse, the keys, the fonts and the
useful commands in full.

## Packages

The modules that come with polpo are its base system. More can be installed with portia, the
package manager. It reads a package tree, arden, which you get first:

    bin/x86/loksh portia.Sync

Then

    bin/x86/loksh portia.List
    bin/x86/loksh portia.Info ifs
    bin/x86/loksh portia.Install ifs

lists the packages, shows one (ifs draws fractals on the XY plane), and installs it: portia
downloads its sources, checks them, compiles them and records them. Later, after a git pull of
polpo,

    bin/x86/loksh portia.Sync
    bin/x86/loksh portia.Upgrade

brings the tree and your packages up to date. The readme has the rest.

## The other ports

Every port of polpo has its own compiler, and all of them also run on x86 as cross compilers. With
qemu installed you can try the ARM and RISC-V versions of hello without leaving your machine:

    bin/x86/loksh acompiler.Compile /s hello.Mod
    qemu-arm bin/arm/loksh hello.world
    bin/x86/loksh rvcompiler.Compile /s hello.Mod
    qemu-riscv32 bin/riscv/loksh hello.world

The ARMv7 compiler is a7compiler, the MIPS one mcompiler (run with qemu-mipsel). The objects go into
obj/arm, obj/riscv and so on. A module that compiles with all five compilers runs on all five
ports; programming.md lists the few things to avoid for that.

## When a command does not stop

A command runs until it ends, and while it runs nothing else happens: there is one thread in
Oberon, and the command has it. This is a feature, not a mistake (the system stays simple and
predictable), but it means that a command which loops forever holds everything.

On the console, Ctrl+C stops the command; loksh says so and goes on. In the desktop, Ctrl+Pause
(or Ctrl+Alt+C) does the same, and a Trap viewer shows where the command was. Ctrl+Alt+P pauses
a running command instead, gives you the desktop back, and continues the command when you press
Ctrl+Alt+P again.

Question: when a command is stopped in the middle, what happens to the variables of its module?
(They keep the values they had. Oberon does not undo anything; the module simply did not finish.
That is usually harmless, and System.Free unloads the module if you want it fresh.)

## Where to go from here

Read the sources. That is not a joke: Oberon was written to be read, and polpo has all of it, the
compilers included. Open src/cli/out.Mod or src/cli/fs.Mod and see how small a useful module can be.
Then read programming.md before you write commands of your own, and desktop.md for the desktop.

The books listed at the beginning explain the ideas behind what you have seen here far better than I
can in a short note. Reiser's User Guide is still the best way into the desktop, and Project Oberon
the best way into the system.
