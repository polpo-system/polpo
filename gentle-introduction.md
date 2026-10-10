# A Gentle Introduction to polpo

(Last updated: 10 October 2026.)

## Contents

    Background
    Introduction
    The console: loksh
    Modules and commands
    Compiling your first module
    Looking at an interface
    Texts
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
called Oberon System 3), and in particular the version that ran on top of Linux (Linux Oberon, or
OLR). polpo is a distribution of it: it runs on Linux on x86, ARM, ARMv7, RISC-V and MIPS, and on
each of them it is one program called `loksh`. Everything else (the compilers, the desktop, the
tools) is Oberon modules that loksh loads when they are needed.

There are a few ideas that make Oberon different from the systems you know, and it helps to have
them in mind from the start:

    there are no programs, only modules; a module offers commands, which you call by name,
    as Module.Command;

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
binaries are in the repository), go into its directory and type:

    bin/x86/loksh hello.world

On ARM, RISC-V or MIPS there is bin/arm/loksh, bin/riscv/loksh and so on; everything I show here
works the same on all of them. You will see

    hello not found

because the module hello has not been compiled yet. We shall do that in a moment. Try instead

    bin/x86/loksh fs.Pwd
    bin/x86/loksh net.Lookup localhost

The first prints the current directory, the second asks for the addresses of localhost and prints
something like

    localhost: 127.0.0.1 ::1

In each case loksh started, loaded the module (fs, or net), called the command (Pwd, or Lookup)
with the rest of the line as its parameters, and stopped. If you start loksh without a command,
it reads commands one per line, as a shell does:

    $ bin/x86/loksh
    > fs.Pwd
    /home/you/polpo
    > fs.Ls
    ...

Ctrl+D ends it. In this shell all commands run in the same loksh, so a module loaded by the first
command is still there for the second, with its variables as the first command left them. (Note:
that is the normal way of things in Oberon. The system is never restarted between commands; a
module is loaded on its first use, its body runs once, and it stays until someone unloads it.)

Question: what does bin/x86/loksh fs print? (Try it. A module name alone lists the commands of the
module.)

## Modules and commands

Here is the module hello. You find it as hello.Mod in the polpo directory; it is there for you to
play with.

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

How does a command get its parameters, if a procedure without parameters is a command? It reads
them itself, from the text after the command name. A console command does it like this:

    PROCEDURE Hello*;
      VAR A: texts.Reader; name: ARRAY 64 OF CHAR;
    BEGIN
      texts.OpenArgs(A);
      IF texts.Arg(A, name) THEN out.String("hello, "); out.String(name); out.Ln END
    END Hello;

texts.Arg gives the parameters one after the other and returns FALSE when there are no more. In
the desktop, where the "rest of the line" is the text after the command in a viewer, the same
command works unchanged. programming.md tells the details.

## Compiling your first module

The compiler is a module too. To compile hello:

    bin/x86/loksh compiler.Compile /s hello.Mod

and the compiler answers

    hello.Mod compiling obj/x86/hello new symbol file   33

It wrote two files: obj/x86/hello.Obj, the code, and obj/x86/hello.Sym, the symbol file with the
interface of the module. The /s allows the compiler to write a new symbol file; you need it the
first time and whenever the exports of the module change. Now

    bin/x86/loksh hello.world

prints hey hey!.

(Note: there is no linker step. loksh loads hello.Obj when the command is called, and with it the
modules hello imports, if they are not loaded yet. Only loksh itself, the small core of the system,
is linked.)

Where do the objects go? The compiler writes into obj/x86/ of the current directory if there is
one, and otherwise into the polpo directory. loksh looks for a module first in obj/x86/ of the
current directory and then in polpo's. So a project of your own can keep its objects to itself:
make a directory, make obj/x86 in it, compile there, and run loksh there.

Question: change the text in hello.Mod, compile it again without /s, and call hello.world. What
happens if you add a second exported procedure and compile without /s?

When the interface of a module changes, the modules that import it must be compiled again, because
each of them recorded the interface it was compiled against. loksh refuses to load a module that
imports an old version of another one; it tells you which.

## Looking at an interface

To see what a module offers without reading its source, ask the browser:

    bin/x86/loksh browser.ShowDef hello

    DEFINITION hello;

        IMPORT
            out, Linux0;

        PROCEDURE world*;

    END hello.

This is how you learn your way around the system: browser.ShowDef Texts, browser.ShowDef Files,
browser.ShowDef out. Since everything is a module, everything can be looked at this way.

## Texts

Many files in polpo are not plain text but Oberon texts: they keep fonts and colours, and they can
even contain pictures and other objects. Tool texts (tools/*.Tool), the configuration
Oberon.Text and many documents are written so. On the console you read them with

    bin/x86/loksh texts.ShowPlain tools/System.Tool

and edit them with xxs, a small editor in the style of nano that keeps their fonts:

    bin/x86/loksh xxs.Open tools/System.Tool

Sources (.Mod files) may be plain text or Oberon texts; the compiler reads both. (Note: texts.md
is about one text in particular, Oberon.Text, the configuration of the system.)

## The desktop

So far we stayed in the terminal. The Oberon system proper is its desktop:

    bin/x86/loksh System.Init

opens a window (under X11) with the Oberon desktop in it. It also runs inside an xterm with sixel
graphics, without X11; the readme tells how.

The screen is divided into two columns of viewers. On the left, the user track, texts are opened;
on the right, the system track holds the Log (the messages of the system) and System.Tool, a text
full of commands. The mouse has three buttons, and each has its own work:

    the left button sets the caret, where typed text goes;
    the middle button runs the command under the mouse;
    the right button selects text.

Now click with the left button at the end of the Log, type Edit.Open hello.Mod, point at
Edit.Open and click the middle button. A viewer opens in the user track with the source of hello.
This is all there is to running a command in Oberon: any word of the form Module.Command in any text
can be clicked, and what follows it on the line is its parameters. System.Tool is simply a text
with useful commands written in it, ready to be clicked. Try typing hello.world into the Log and
clicking it. Where did hey hey! go?

(Note: the answer is the terminal you started loksh in. out writes to the terminal. A desktop
module writes into a text instead, usually the Log, with the module Texts.)

The rest is learned by doing: storing a text is Edit.Store in its menu bar, selecting from here to
there is the right button held down while you move, a viewer is closed with System.Close. desktop.md
describes the mouse, the keys, the fonts and the useful commands in full.

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
