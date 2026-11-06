# Writing Commands for polpo

This note is for those who want to write modules and commands of their own for polpo. It explains
how a command is called and how it gets its parameters, where the compiled objects go, what
happens when a command is stopped, and how to write code that the compilers of all five ports
accept. If Oberon is new to you, read gentle-introduction.md first; it shows the same things more
slowly.

## Modules and commands

An Oberon module is one source file, from MODULE Name; to END Name.; what it exports is marked
with an asterisk. A command is an exported procedure without parameters. Here is a small one:

    MODULE greet;
    IMPORT Texts, Out;

    PROCEDURE Hello*;
      VAR A: Texts.Reader; name: ARRAY 64 OF CHAR;
    BEGIN
      Texts.OpenArgs(A);
      IF ~Texts.Arg(A, name) THEN Out.String("usage: greet.Hello name"); Out.Ln; RETURN END;
      Out.String("hello, "); Out.String(name); Out.Ln
    END Hello;

    END greet.

We compile it and call it:

    bin/x86/loksh compiler.Compile /s greet.Mod
    bin/x86/loksh greet.Hello world

The compiler writes two files, obj/x86/greet.Obj (the code) and obj/x86/greet.Sym (the
interface). The /s lets it write a new symbol file. You need it the first time, and whenever the
exports of the module change; the modules that import a changed module must then be compiled
again, because each of them recorded the interface it was compiled against. (Note: the x86
compiler can also put the interface inside the .Obj, as Native Oberon did, if you give it /i.
Nowadays every port writes a separate .Sym.) Choose names that polpo does not use yet: loksh name
says "module not found" for a free one.

The other ports have their own compilers: acompiler for ARM, a7compiler for ARMv7, rvcompiler for
RISC-V and mcompiler for MIPS. All of them also run on x86 as cross compilers. A module is loaded
the first time one of its commands is called, or when a module that imports it is loaded; its body
(the statements between BEGIN and END Name.) runs then, once.

Where do the objects go? A compiler writes into obj/<arch>/ of the current directory if there is
one, and otherwise into the polpo directory. The loader looks for obj/<arch>/Name.Obj in the
current directory first and then in polpo's, each time it loads a module. So a project with its
own obj/<arch>/ uses its own objects while you work in it, and polpo's directory stays clean.

### Trying a changed system module in a directory of its own

The same rule lets you replace a module of polpo itself for a while, without touching polpo:
make a directory with an obj/<arch>/ in it, compile your changed copy of the module there (or
copy an object you already have into it), and run loksh in that directory. There, your object
is loaded instead of polpo's; everywhere else polpo's is. When you are done, leave the directory
behind; nothing in polpo has changed, so there is nothing to undo.

    mkdir -p /tmp/try/obj/x86 /tmp/try/obj/arm && cd /tmp/try
    cp ~/polpo/src/cli/arm/OBC.Mod .       # a copy of a module of the ARM compiler, changed
    loksh compiler.Compile OBC.Mod         # its object goes to /tmp/try/obj/x86/OBC.Obj
    loksh acompiler.Compile Test.Mod       # the ARM compiler, with your OBC: /tmp/try/obj/arm/Test.Obj

This works for any module that is loaded from an object file, and for every port (obj/arm,
obj/riscv and so on, with that port's loksh). Three things to keep in mind:

- The modules linked into loksh itself are not loaded from objects: Linux0, Kernel, Root,
  Modules0 and loksh (on x86 also Files). To try a change of one of them you build a new loksh.
- Keep the interface. If your copy exports something different, every module that imports it
  must be compiled into the same directory too; otherwise loading stops with "imports
  incompatible version". A changed body with the same exports needs nothing else.
- A module is loaded once per loksh process and then stays. After compiling, start a new loksh
  (an interactive one keeps the old module), and start it in the directory with your objects.

The compilers write their output there as well, into obj/<arch>/ of the current directory when it
exists, so make one for every port you compile for; a test module compiled there then does not
end up in polpo either.

## Looking at module interfaces

To see what a module exports without reading its source, ask the browser. It reads the interface
from the module's symbol file:

    $ bin/x86/loksh browser.ShowDef fs
    DEFINITION fs;

        IMPORT
            Linux0, Kernel, Files, Root, Texts, Objects, Modules, Modules0, Objects0, Display, Fonts, Reals, Texts0,
            Oberon0, Out;

        PROCEDURE Cd*;
        PROCEDURE Cp*;
        ...
    END fs.

For a library you see its types, variables and procedures with their parameters:

    $ bin/x86/loksh browser.ShowDef Oberon0
    DEFINITION Oberon0;
        ...
        TYPE
            Cleanup* = PROCEDURE;
            ParList* = POINTER TO ParRec;
            ParRec* = RECORD
                text*: Texts0.Text;
                pos*: LONGINT;
            END;
        ...
        PROCEDURE OnStop*(p: Cleanup);
        PROCEDURE Stopped*;
        ...

browser.ShowDef module /e also writes out the fields a record inherits from its base types (without
/e an extension shows only as RECORD (Base)), and /d adds the offsets of record fields, the
addresses of variables and the offsets of parameters. The module can be given as a path too,
browser.ShowDef src/cli/net.Mod, and browser.Help lists the commands and options. In the desktop,
the browser of the port shows the definition of a selected module name in a viewer:
XBrowser.ShowDef ^ on x86, ABrowser.ShowDef ^ on ARM, RBrowser.ShowDef ^ on ARMv7, RISC-V and MIPS.
They write the same text as the console browser.

Every port has its own console browser, with the same commands, reading the symbol files of its
port: qemu-riscv32 bin/riscv/loksh browser.ShowDef fs shows the RISC-V interface. The definitions
are the same on all ports except for the IMPORT line (on x86 it lists every module in the symbol
file's module table, elsewhere only the modules the interface refers to), and except for the few
modules that differ between ports, as Linux0 and Kernel.

## Parameters and output

A command reads its parameters itself. Texts.OpenArgs(A) opens them, and Texts.Arg(A, s) gives one
after the other: blanks separate them, quotes ("...") keep blanks inside one, and the end of the
line or a ~ ends them. Arg returns FALSE when there are no more. In the desktop, Module.Command
args ~ written in a text calls the same command with the same parameters, so a console command
works in both worlds.

Write output with Out: Out.String, Out.Int(x, width), Out.Char, Out.Ln, Out.Hex(x) (a blank and 8
hexadecimal digits), Out.Real, Out.LongReal and their fixed-point forms Out.RealFix and
Out.LongRealFix, as in ETH Oberon. Out.HexDigits(x, n) writes x as an unsigned hexadecimal number of
at least n digits, with leading zeros and without a blank, 8 digits for n <= 0, as Out.Hex(x, n)
does in OO2C; the modules polpo shares with voc use it. It writes to the terminal, and in
the desktop into System.Log a line at a time (the rest of a line comes when the command has ended);
in the desktop Out.Open sends it to a viewer of its own instead, until Out.Close. Out.writer, a
procedure variable, is where the output goes: NIL, the default, is the terminal, and the desktop
points it at System.Log; a command that must know whether it runs in the desktop can test it, as
portia does. The same Out serves the modules polpo shares with voc. The older console module out
writes through Out and is deprecated; it remains for packages that still import it.

In reads the parameters of the command (In.Open, then In.Int, In.Name, In.String, In.Real, and
In.Done to see whether they were there), in the console from the command line and in the desktop
from the text after the command; ^ instead of the parameters takes the latest selection, * the
marked viewer, both only in the desktop. Strings (conversions between numbers, dates and strings)
works in both too. A program that uses Out, Texts.Arg or In, and asks no questions runs unchanged
in the console and in the desktop. Reading the terminal itself (stdin, as the shell does) and
writing to it directly work only in the console.

Texts, imported above for OpenArgs and Arg, is also Show, ShowPlain, ReplaceIn, DeleteLines and the
rest of the ETH text interface, and it needs Display and Fonts, although nothing opens a window
before the desktop starts. The older module texts has the same OpenArgs, Arg, Show, ShowPlain,
Replace (its name for ReplaceIn: in Texts, Replace is the ETH procedure on a live text) and
DeleteLines, and the same types, since both take them from Texts0; it lacks the parts tied to the
viewers of the desktop, and needs neither Display nor Fonts.

Every console session loads Texts, Display and Fonts, because the shell imports Texts, and so do
most console commands. With the shell, oberon and system importing texts instead, a console
session holds these bytes of modules after it has started (system.ShowModules, the line TOTAL;
measured with polpo 1.5):

    port            with Texts   with texts    less
    x86                 227725       184138   43587
    ARM                 287888       225124   62764
    ARMv7               273528       219152   54376
    RISC-V              251104       202464   48640
    MIPS, MIPS BE       260624       209888   50736
    PowerPC             270336       218280   52056

That is a fifth less. The resident memory of the process changes little, because loksh takes its
heap when it starts and loads the modules into it: 16692 kB against 16632 kB on x86. The saving
lasts until a module that imports Texts is loaded, and fs, tar, net, the compilers and most other
console commands import it; each of them uses only what texts has. building.md tells how to build
a console that keeps to texts. A package meant for such a console imports texts and depends on
console-base; for a package that depends on console, which is almost every package, Texts costs
nothing further.

When the parameters are missing or wrong, print a line usage: module.Command ... that says what the
command does. Options are words that start with a slash, after the command or after its
parameters, as in compiler.Compile /s file, portia.Install /y name, browser.ShowDef Oberon0 /e or
fs.Ls /l. (A few older commands also take options starting with -, as grep -i.) Since paths can
start with a slash too, accept only the option words your command knows. A console module should
also have a Help command that describes its commands, with examples; loksh module alone lists the
commands of a module and points to module.Help.

(Remarks: console modules have lowercase names, as net, fs, gzip and tar; desktop modules are
capitalised, as System, Edit and ZipTool. A tool meant for both worlds is usually three modules:
Xxx0 with the work and no console or desktop imports, xxx with the console commands, and Xxx with
the desktop commands. A plain text tools/Xxx.Tool describes it, with commands to click.)

## How loksh runs commands

loksh Module.Command args runs one command and exits. loksh alone is an interactive shell, and
loksh < file runs the commands of a file, one per line. All commands of such a session run in the
same process. Loaded modules and their global variables stay from one command to the next, and so
does the current directory: after fs.Cd, plain file names are looked up there first and then on
the search path of polpo.

## When a command is stopped

A command can stop early in two ways. Someone stops it: Ctrl+C in the terminal where loksh runs,
or in the desktop Ctrl+Pause (Break) or Ctrl+Alt+C. Or it traps: a NIL pointer, an index out of
range, a failed ASSERT, HALT(n), a division by zero.

(Note: the desktop notices Ctrl+Pause and Ctrl+Alt+C when the command reads the keyboard or the
clock, through Input.Available, Input.Read or Oberon.Time. A loop that does neither can only be
stopped by Ctrl+C in the terminal, which interrupts it at once. Ctrl+Alt+P pauses a command
instead of stopping it; desktop.md describes that.)

Then the kernel abandons the command and goes back to the shell's prompt (or to the desktop,
which shows a Trap viewer with the procedures and their variables). In the console the trap is
shown on the standard error: what it was, the procedures that were running, the last one first,
each with its pc in the code of its module, and the command that finds the statement:

    TRAP 7: index out of range
      Test.Index  pc 32
      Test.Run  pc 90
      Oberon0.Call  pc 2062
      shell.Run  pc 6714
    compiler.Compile /f 32 <the source of Test> shows the statement (compile it with the options of its object)

and the shell prints

    loksh: the command stopped (Ctrl+C or a trap; Kernel.Log has the registers)

Compiling with /f and a pc writes no object; the compiler names the line and column of the
statement whose code holds the pc:

    loksh compiler.Compile /f 32 Test.Mod
    Test.Mod:9:11: pc 32

The pc of a procedure that called another is that of its call (one byte before the return
address), so /f finds the call statement for it too. The source and the options (/2, /x) must be
those the object was compiled from, since the search compiles the module again. compiler.Compile
is the native compiler of each port; the cross compilers (acompiler, a7compiler, rvcompiler,
mcompiler, mbcompiler, pcompiler) take /f the same way. Kernel.Log keeps the registers and the
other details the kernel writes.

Oberon has no exceptions and no unwinding. The stopped command does not go on, and its remaining
statements, including any closing it meant to do, never run. Its modules stay loaded, and its
global variables keep their values; memory is collected later as usual. But files it had open and
sockets it was using stay open. Run as loksh Module.Command or loksh < file, loksh exits with
status 2 after a trap, so that scripts can tell a command failed.

### Closing what a stopped command left open

A command that holds something the system does not free by itself registers a procedure with
Oberon0.OnStop: typically a listening socket, a connection, or a temporary file to delete. When
the command is stopped, the shell calls the registered procedures, and so does the desktop when it
comes back from a trap. Keep what is to be closed in global variables, because the stopped
command's local variables are gone by then.

    MODULE server;
    IMPORT Sockets, Oberon := Oberon0, Out;

    VAR listener: Sockets.Socket;  (* global: still there when the command is stopped *)

    PROCEDURE Close;  (* closes what Serve holds; nothing when there is nothing *)
    BEGIN
      IF listener # NIL THEN Sockets.Close(listener); listener := NIL END
    END Close;

    PROCEDURE Serve*;
    BEGIN
      Close;                  (* a leftover of an earlier run, if Close was not called *)
      Oberon.OnStop(Close);   (* called if Serve is stopped *)
      listener := Sockets.Listen(Sockets.Inet6, 8080, 8);
      ...                     (* serve; Ctrl+C may stop it anywhere *)
      Close                   (* the normal end *)
    END Serve;

    END server.

OnStop(p) registers p only once, however often it is called, so calling it at the start of every
run is fine. p stays registered after the command ends normally and runs after any later stop;
it must therefore do nothing when there is nothing to close (check for NIL, and set to NIL after
closing). It has no parameters and runs after the stack of the stopped command is gone, so it may
use only global variables. If p itself traps, it is not called again, and at most 16 procedures
can be registered at once. net.Echo works this way: Ctrl+C closes its listening socket and its
connection at once, so the port is free again.

## Windows of their own

A desktop program can put any frame into an X11 window of its own: Windows.Open(F, title, W, H)
opens a window of W x H with the title and makes F fill it; it returns the window, a viewer, or
NIL (no X11, more than 16 windows, larger than the screen). Windows.Close(V) closes it, and so does
the close button of the window manager, when the desktop is idle. The frame works there as in a
viewer of the desktop: it gets the mouse, the keyboard and the broadcasts. The window shows an
area below the screen (y < 0), so the frame's coordinates are negative there; frames that draw
only inside their own rectangle need not know. Underneath, Display.OpenWindow makes the X11 window
and Viewers.OpenFree a viewer outside the tracks. Windows.Run(V) after Open makes a command a program of
its own when it runs without the desktop (from a shell): the desktop's loop runs for the windows
alone, its screen is not shown (System.Init shows it with Display.ShowMain), and loksh ends when
the last window closes; in the desktop Run returns at once. Windows.OpenText shows the use with a
text frame; DocWindows (in the package gadgets) does it for gadget documents.

## Files

Files.Old(name) opens a file. A plain name (without a slash) is looked up in the current directory
first and then on the search path of polpo: its directory, share/, tools/ and fonts/. (Note: so in
tests use names that cannot be in polpo's directory, or full paths; otherwise a test may find a
file of polpo by accident.) Files.New(name) makes a file in memory, and Files.Register(f) writes
it under its name; Files.Close(f) writes the changes of a file opened with Old. The module fs
(fs.Cd, fs.Ls, fs.Cp and so on) works on directories and files with their names as Linux takes
them, while Files accepts letters, digits, ., /, _ and -, and a name must not begin with a digit.

## Code that compiles on all ports

polpo has five compilers, and they do not all accept the same language. The ARM compiler is an
Oberon-1 compiler, the x86 one knows some Oberon-2, the ROP2 compilers (ARMv7, RISC-V, MIPS)
something in between. A module that keeps to the following compiles with all of them:

    declarations (CONST, TYPE, VAR) come before the procedures, in modules and in procedures;

    no read-only exports (-): export with *;

    no type-bound procedures (only the x86 compiler takes them, with the option /2);

    SET has 32 elements;

    EXIT only inside LOOP, and HALT(100) (the ports accept different ranges of trap numbers);

    module names shorter than 20 characters, identifiers shorter than 32, string constants
    shorter than 128 characters, and less than 16 KB of them in a module;

    DIV and MOD only with a divisor > 0, as in Oberon-07: a constant divisor <= 0 does not
    compile (err 237), a variable one stops the program (trap 10). For a negative dividend
    they round down: -7 DIV 2 = -4, -7 MOD 2 = 1, the remainder is never negative.

Real literals are converted exactly and rounded to the nearest REAL or LONGREAL, the ends of the
range and the denormal numbers included; a literal that is not 0 but rounds to 0 is an error.

HUGEINT is a 64-bit integer on every port. The compilers keep it in two words and compile its
operations into calls of the module HugeInt (src/common/HugeInt.Mod), which a module using HUGEINT
imports without naming it; arithmetic on LONGINT stays faster. A literal that does not fit a LONGINT
is a HUGEINT: decimal above 2147483647, or hexadecimal with 9 to 16 digits (0FFFFFFFFH is still the
LONGINT -1, and 0FFFFFFFFFFFFFFFFH is -1). LONG of a LONGINT gives a HUGEINT and SHORT of a HUGEINT
its low 32 bits; the smaller integer types and constants mix with HUGEINT in expressions,
assignments and parameters, and HUGEINT mixes with REAL and LONGREAL. ABS, ODD, ASH, INC, DEC, MIN,
MAX and SIZE take it, and functions may return it. It cannot index an array, select a CASE, count a
FOR loop or be an element of a SET, and SYSTEM.VAL takes it only as a variable.

(Note: ORD(ch) is an INTEGER, 16 bits, on x86, so ORD(ch) * 256 can overflow there without a trap;
write LONG(ORD(ch)) * 256. FOR loops are fine on all five compilers.)

Test on the other ports with qemu: compile with the port's compiler, then run, for example,
qemu-arm bin/arm/loksh Module.Command, qemu-riscv32 bin/riscv/loksh ... or
qemu-mipsel bin/mips/loksh ....

## Packages

To make a module installable with portia, it needs a recipe in the package tree arden
(github.com/polpo-system/arden). portia reads the copy in arden/ that portia.Sync downloads. To
change the tree, work in a git clone of it (for example ../arden), and try your change before you
push it with PORTIA_TREE=../arden. The modules of polpo itself are described by tools/base.toml of
the tree and generated with loksh genarden.Run ../arden, which also writes the lists of the base
system, portia.base.<arch>, into polpo. Other packages live in their own repositories in the
polpo-system organisation, with their sources pinned by commit and checked by sums. The readme
tells more under "portia, the package manager".
