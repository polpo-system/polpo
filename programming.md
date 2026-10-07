# Writing commands for polpo

This is for programmers who write modules and commands for polpo: how commands are called,
how they get their arguments, what happens when they are stopped, and how to write code that
compiles on all five ports.

## Modules and commands

An Oberon module is one source file, `MODULE Name; ... END Name.`; what it exports is marked
with `*`. A **command** is an exported procedure without parameters:

```oberon
MODULE greet;
IMPORT texts, out;

PROCEDURE Hello*;
VAR A: texts.Reader; name: ARRAY 64 OF CHAR;
BEGIN
  texts.OpenArgs(A);
  IF ~texts.Arg(A, name) THEN out.String("usage: greet.Hello name"); out.Ln; RETURN END;
  out.String("hello, "); out.String(name); out.Ln
END Hello;

END greet.
```

Compile it and call it:

```sh
bin/x86/loksh compiler.Compile /s greet.Mod   # writes obj/x86/greet.Obj and greet.Sym
bin/x86/loksh greet.Hello world
```

`/s` lets the compiler write a new symbol file, the module's interface. It is
`Module.Sym`, next to `Module.Obj`, on every port (the x86 compiler puts it inside the `.Obj`
only with `/i`, as Native Oberon did). It is needed the first time, and whenever the exports
change. The modules that import a changed module must then be
compiled again. Choose module names that polpo does not have yet: `loksh name` says
"module not found" for a free name.

The other ports have their own compilers (`acompiler` for ARM, `a7compiler` for ARMv7,
`rvcompiler` for RISC-V, `mcompiler` for MIPS); all of them also run on x86 as cross
compilers. A module is loaded the first time one of its commands is called (or a module that
imports it is loaded); its body (`BEGIN ... END Name.`) runs then, once.

Where objects are written and read:

- A compiler writes `obj/<arch>/` of the current directory if there is one, otherwise the one
  in the polpo root.
- The loader looks for `obj/<arch>/Name.Obj` in the current directory first, then in the root,
  each time it loads a module. A project with its own `obj/<arch>/` uses its objects while you
  work in it.

## Looking at module interfaces: browser

To see what a module exports, without reading its source, ask the browser. It reads the
interface from the module's symbol file:

```
$ bin/x86/loksh browser.ShowDef fs
DEFINITION fs;

	IMPORT
		Linux0, Kernel, Files, Root, texts, objects, Objects0, Texts0, Reals, Oberon0, Modules, Modules0, out;

	PROCEDURE Cd*;
	PROCEDURE Cp*;
	...
END fs.
```

For a library you see its types, variables and procedures with their parameters:

```
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
```

- `browser.ShowDef module /e` writes out the fields a record inherits from its base types.
  Without `/e`, an extension shows only as `RECORD (Base)`.
- `browser.ShowDef module /d` adds record field offsets, the addresses of variables and the
  offsets of parameters.
- The module can be given as a path: `browser.ShowDef src/cli/net.Mod`.
- `browser.Help` lists the commands and options.
- In the desktop, the browser of the port shows the definition of the selected module name in
  a viewer: `XBrowser.ShowDef ^` on x86, `ABrowser.ShowDef ^` on ARM, `RBrowser.ShowDef ^` on
  ARMv7, RISC-V and MIPS (the same text as the console browser).

Every port has its own console browser, with the same commands and options. Each one reads the
symbol files of its port, in `obj/<arch>/` of the current directory or of the root:
`qemu-riscv32 bin/riscv/loksh browser.ShowDef fs` shows the RISC-V interface. The definitions
are the same, except for the `IMPORT` line: on x86 it lists every module in the symbol file's
module table, on ARM, ARMv7, RISC-V and MIPS only the modules the interface refers to. The
modules that differ between ports (such as Linux0 and Kernel) have different interfaces.

## Arguments and output

- `texts.OpenArgs(A)` and `texts.Arg(A, s)` give the arguments one by one. Blanks separate them,
  `"..."` keeps blanks inside one, and the end of the line or `~` ends them. `Arg` returns
  FALSE when there are no more.
- In the desktop, `Module.Command args ~` in a text calls the same command with the same
  arguments: console commands work in both.
- `out.String`, `out.Int(x, width)`, `out.Hex`, `out.Char` and `out.Ln` write to the terminal.
- When the arguments are missing or wrong, print a line `usage: module.Command ...` that says
  what the command does.
- Options are words that start with `/`, after the command or after its arguments:
  `compiler.Compile /s file`, `portia.Install /y name`, `browser.ShowDef Oberon0 /e`, `fs.Ls /l`.
  (A few older commands also take `-` options, as `grep -i`.) Paths can start with `/` too:
  accept only the option words the command knows.
- A console module should have a `Help` command that describes its commands, with examples.
  `loksh module` alone lists the commands of a module and points to `module.Help`.

Naming: console modules are lowercase (`net`, `fs`, `gzip`, `tar`); desktop modules are
capitalised (`System`, `Edit`, `ZipTool`). A tool for both is usually three modules: `Xxx0`
with the work (no console or desktop imports), `xxx` with the console commands, and `Xxx` with
the desktop commands. A plain text `tools/Xxx.Tool` describes it, with commands to click.

## How loksh runs commands

- `loksh Module.Command args` runs one command and exits.
- `loksh` alone is the interactive shell. `loksh < file` runs the commands of a file, one per
  line.
- All commands of a session run **in the same process**. Loaded modules and their global
  variables stay from one command to the next. So does the current directory: after `fs.Cd`,
  plain file names are looked up there first, then on the search path of the root.

## When a command is stopped

A command stops early in two ways:

- **Ctrl+C** while it runs, or
- **a trap**: a NIL pointer, an index out of range, a failed `ASSERT`, `HALT(n)`, a division
  by zero.

Then the kernel writes the details of the trap to `Kernel.Log`, abandons the command and goes
back to the interactive shell's prompt. The shell prints:

```
loksh: the command stopped (Ctrl+C, or a trap: Kernel.Log has the details)
```

Oberon has no exceptions and no unwinding. The stopped command does not go on. Its remaining
statements, including any closing it meant to do, never run. Its modules stay loaded and its
global variables keep their values. Memory is collected later as usual. Files it had open and
sockets it was using stay open.

Run as `loksh Module.Command` or `loksh < file`, loksh exits with **status 2** after a trap, so
scripts can tell that a command failed.

### Closing what a stopped command left open: `Oberon0.OnStop`

A command that holds something the system does not free by itself registers a procedure with
`Oberon0.OnStop`. Typical cases are a listening socket, a connection, or a temporary file to
delete. When the command is stopped, the shell calls the registered procedures, and so does
the desktop when it comes back from a trap. Keep what is to be closed in **global** variables:
the stopped command's local variables are gone.

```oberon
MODULE server;
IMPORT Sockets, Oberon := Oberon0, out;

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
```

The rules:

- `OnStop(p)` registers `p` once, however often it is called. Calling it at the start of every
  run is fine.
- `p` stays registered after the command ends normally, and runs after any later stop. It must
  therefore do nothing when there is nothing to close: check for NIL, and set to NIL after
  closing.
- `p` has no parameters and runs after the stack of the stopped command is gone. It may use
  only global variables.
- If `p` itself traps, it is not called again.
- At most 16 procedures can be registered at once.

`net.Echo` works this way: Ctrl+C closes its listening socket and connection at once, so the
port is free again.

## Files

- `Files.Old(name)` opens a file. A plain name (without `/`) is looked up in the current
  directory first, then on the search path of the root (the root, `share/`, `tools/`,
  `fonts/`). In tests use names that cannot be in the root, or full paths.
- `Files.New(name)` makes a file in memory. `Files.Register(f)` writes it, under its name.
  `Files.Close(f)` writes the changes of a file opened with `Old`.
- `fs` (`fs.Cd`, `fs.Ls`, `fs.Cp`, ...) works on directories and files with the names as Linux
  takes them. Files accepts letters, digits, `.`, `/`, `_` and `-`, and the first character
  must not be a digit.

## Code that compiles on all ports

polpo has five compilers. To be accepted by all of them:

- No `FOR` loops: use `WHILE`. The ARM compiler is Oberon-1.
- Declarations (CONST, TYPE, VAR) come before the procedures, in modules and in procedures.
- No read-only exports (`-`): use `*`.
- No type-bound procedures. Only the x86 compiler takes them, with the option `/2`.
- No `HUGEINT`: integers have at most 32 bits. `SET` has 32 elements. `ORD(ch)` is an
  INTEGER (16 bits) on x86: write `LONG(ORD(ch)) * 256`.
- `EXIT` only inside `LOOP`. Use `HALT(100)` (the ports accept different trap numbers).
- Module names shorter than 20 characters, identifiers shorter than 32. String constants
  shorter than 128 characters, and less than 4 KB of them per module.
- Real constants at the ends of the range (`1.17549435E-38`) are refused: write them as
  quotients of powers of two.

Test on the other ports with qemu: compile with the port's compiler, then run, for example,
`qemu-arm bin/arm/loksh Module.Command`, `qemu-riscv32 bin/riscv/loksh ...` or
`qemu-mipsel bin/mips/loksh ...`.

## Packages

To make a module installable with `portia`, it needs a recipe in the package tree arden. The
modules of polpo itself are described by `arden/tools/base.toml` and generated with
`loksh genarden.Run arden`. Other packages live in their own repositories in the polpo-system
organisation, with their sources pinned by commit and checked by sums. See "portia, the
package manager" in `readme.md`.
