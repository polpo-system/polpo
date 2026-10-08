# POLPO
## platform orbiting linux: project oberon

This is an attempt to contunie development of ETH Linux Oberon in some way.

### Goals

* Create minimal set of CLI modules, working compiler, and loader of Obj files - done.
* Create a minimal Oberon OS that runs over Linux - only minimal set of modules. - done.
* Add package manager to add packages over the network.
* Create a ports tree of package recipies.
* Also integrate ARM and other existing compilers.
* Add support for aarch64 and x86_64.
* Build also bootable on X86 machine version of Oberon on Linux
* Build also bootable on some ARM devices version of Oberon on Linux

## How to play

`bin/x86/loksh` is the statically linked x86 console. It loads the object files from
`obj/x86/`; `make` rebuilds the whole system with it (`tools/build.Tool`) and links
`bin/x86/loksh2`.

To write your own modules and commands, read [programming.md](programming.md): arguments,
how loksh runs commands, Ctrl+C and traps, closing resources with `Oberon0.OnStop`, and code
that compiles on all ports.

Look at [compiler options](compiler_options.md) or do

```
bin/x86/loksh compiler.Help
```

Compile the hello world example:

```
bin/x86/loksh compiler.Compile hello.Mod
```

Run:

```
bin/x86/loksh hello.world
```

Show an Oberon text on the terminal, with its styles and colours, or only its characters.
Bold and italic fonts are shown bold and italic, larger sizes (headings) bold, with the
terminal's own font:

```
bin/x86/loksh texts.Show texts/UserGuide.Text
bin/x86/loksh texts.ShowPlain texts/UserGuide.Text | less
```

Programs can call `texts.ShowFile(name, rich)`. `cat.Cat [-p]` still works but is
deprecated.

Edit texts from the console, Oberon texts and plain files alike:

```
bin/x86/loksh texts.Replace tools/System.Tool Oberon20.Scn.Fnt Syntax20.Scn.Fnt
bin/x86/loksh texts.Replace notes.Text '"old words"' '"new words"'
bin/x86/loksh texts.DeleteLines tools/System.Tool wishup.Tool
```

`texts.Replace file old new` replaces every occurrence; the new text keeps the font and
colour of the old, and `""` as new deletes. `texts.DeleteLines file text` deletes every
line containing the text. Arguments are words separated by blanks, any file name works;
texts with blanks are quoted (in the Unix shell as `'"..."'`). The file is stored where it was found, the old version as `.Bak`; an Oberon
text keeps its fonts and colours, a plain file stays plain. Texts with objects (gadgets)
are left alone.

### portia, the package manager

polpo is described as packages in the tree arden (github.com/polpo-system/arden), kept in
`arden/` in the polpo directory. It does not come with the git clone: the first thing to do
with a new polpo is to get it, and again later to see new packages and versions:

```
bin/x86/loksh portia.Sync    # the newest commit of arden from GitHub, as files, into arden/
```

Sync downloads one archive of the newest commit and remembers the commit in `arden/COMMIT`;
when nothing changed it downloads nothing more. A tree that is a git checkout is left to
`git pull`. Another tree can be named with `PORTIA_TREE` or `Portia.Tree` in `Oberon.Text`.
The tree describes core, console, xxs, the compilers, the desktop, the
display variants and more, each with its modules per architecture, data files and
dependencies, sorted into categories: `linux` (packages producing Linux executables, like
core with `loksh`), `system`, `devel`, `apps`, `lib`. portia reads it:

```
bin/x86/loksh portia.List                    # the packages; i: installed
bin/x86/loksh portia.List apps               # one category
bin/x86/loksh portia.Info display-sixel      # dependencies, provides, conflicts, modules
bin/x86/loksh portia.Files xxs               # the files of a package on this architecture
bin/x86/loksh portia.Owner obj/x86/Display.Obj
bin/x86/loksh portia.Check                   # all files here, every import satisfied
bin/x86/loksh portia.Build xxs               # build xxs and its dependencies
bin/x86/loksh portia.Build                   # build every installed package (all of polpo)
bin/x86/loksh portia.Build /arm              # the same for ARM, cross compiled on x86
qemu-arm bin/arm/loksh portia.Build          # or natively
```

`portia.Build` compiles the packages in dependency order, the modules of a package in the
order of their imports, then links and installs `bin/<arch>/loksh`. It gives the same
objects as the recipes in `tools/`.

```
bin/x86/loksh portia.Install display-sixel   # build it, replacing display-x11 (make sixel)
bin/x86/loksh portia.Install display-x11     # and back
bin/x86/loksh portia.Remove console-tools    # delete its objects, if nothing needs it
```

`portia.Install` builds a package and the dependencies not installed yet, links, and
records it; installed packages it conflicts with are replaced. `portia.Remove` refuses
while an installed package needs the package (directly, or as the only provider of
something like `display`); the sources and data of the base system stay.

Install, Upgrade, Build and Remove first list what they will do (new, upgrade from, rebuilt,
recompiled for a changed dependency) and ask; answering n changes nothing. `/y` does not
ask, for scripts; without a terminal portia needs `/y`.

Packages have versions (`1.2.10`, `0.3.0-rc1`); a version in `[DEPS]` is the least one
needed. `portia.Install` builds dependencies only when they are missing or older than
needed, and leaves a package installed in the tree's version alone. `portia.List` marks
packages with a newer version in the tree with `u`; `portia.Upgrade [name ...]` builds
them and what they need. When the interface of a module changes (portia compares its symbol
file before and after compiling; on x86 the symbol part of the object file when it was
compiled with `/i`), the installed
packages depending on its package are recompiled, and so on: in Oberon a changed interface
must be recompiled into its importers. `portia.Graph [name] >
deps.dot` writes the dependencies as a Graphviz graph. The tree can also be set with the
environment variable `PORTIA_TREE`.

Updating: polpo itself (the base system, with its objects and binaries) is updated with git,
the package tree with portia.Sync; then portia upgrades the other packages:

```
git pull                                   # polpo
bin/x86/loksh portia.Sync                  # the package tree
bin/x86/loksh portia.Upgrade               # every installed package with a newer version
bin/x86/loksh portia.Upgrade /arm          # the same for the ARM port (/armv7, /riscv, /mips)
```

`portia.Upgrade` also recompiles the packages you built (the remote ones) when the pull
changed an interface they import: when portia compiles a package it records the interfaces
(the keys of the symbol files) its modules import, in `src/pkg/<name>/portia-<arch>.keys`, and
compares them with the new ones. A rebuild of polpo that leaves the interfaces as they were
recompiles nothing.

The record of the installed packages has two parts for each architecture. `portia.base.<arch>`
lists the base system, the packages that come built with polpo; it is in git, written by
genarden from the build recipes, and changes with `git pull`. `portia.world.<arch>` is this
installation's own and not in git: the packages installed besides the base system, and a line
`-name` for a base package removed or replaced. portia writes only the world file. (A record
`portia.<arch>` of earlier versions of portia is turned into a world file the first time, and
kept as `portia.<arch>.old`.) `portia.Record` makes the world file from the files present;
display-x11 and display-sixel are alternatives providing `display`, and `portia.Mark
display-sixel` records the switch after `make sixel` (in the world file: `display-sixel` and
`-display-x11`). Installing, removing and fetching packages come next. The
package descriptions are TOML. Libraries the base system needs live in `src/lib/<name>/`
(`toml`, `versions`), each a package of the `lib` category.

### Network

`Sockets` (`src/lib/sockets`) is TCP and UDP over IPv4 and IPv6, on every port, with the
socket system calls of `Linux0`. `DNS` (`src/lib/dns`) turns host names into addresses:
`/etc/hosts` first, then A and AAAA queries over UDP to the `nameserver`s of
`/etc/resolv.conf` (or 1.1.1.1), waiting 2 seconds for each; the environment variable
`DNS_SERVER` (an address, optionally `#port`) is asked first. `net` is a set of minimal tools
on top of them; a host is a name or an address, and its addresses are tried in turn:

```
bin/x86/loksh net.Get example.com 80 /           # HTTP/1.0 GET
bin/x86/loksh net.Get ::1 8080 /index.html
bin/x86/loksh net.Lookup example.com localhost   # the addresses of names
bin/x86/loksh net.Resolve example.com           # only IPv4 (A); net.Resolve6: only IPv6 (AAAA)
bin/x86/loksh net.Reverse 1.1.1.1 ::1           # the names of addresses (/etc/hosts, PTR)
bin/x86/loksh net.Send 192.0.2.1 7 hello        # send a text, print the answer
bin/x86/loksh net.Echo 7000 3                   # echo 3 connections, IPv6 and IPv4
bin/x86/loksh net.UDP ::1 5353 hello            # a datagram, the answer and its sender
bin/x86/loksh net.Address 2001:0db8:0:0:0:0:0:1 # addresses in normal form: 2001:db8::1
```

`NetSystem` (`src/lib/native`) is the network interface of ETH Native Oberon (OpenConnection,
ReadString, SendDG, GetIP, ...) over Sockets and DNS, for programs written for it; it is shared
with voc (github.com/norayr/Internet, where its README lists how it differs from Native Oberon).

`http` (`src/lib/http`) is an HTTP/1.1 client (Content-Length, chunked, or to the end of the
connection), and `fetch` uses it:

```
bin/x86/loksh fetch.Show http://example.com/          # the body on the screen
bin/x86/loksh fetch.Get http://[::1]:8080/a.tar a.tar  # saved; without a file name: the last part of the path
bin/x86/loksh fetch.Get https://example.com/ page.html # TLS 1.3
bin/x86/loksh gemini.Get gemini://norayr.am/gd.gif     # Gemini; gemini.Show prints the page
```

HTTPS is TLS 1.3 written in Oberon (`src/lib/tls`, the modules of github.com/norayr/tls; only
32 bit integers, so it runs on every port): X25519 (or P-256 when the server asks for it with a
HelloRetryRequest), AES-128-GCM, SHA-256/384/512, randomness from `/dev/urandom`, roots from
`$SSL_CERT_FILE` or `/etc/ssl/certs/ca-certificates.crt`. A server is accepted only if its
certificate chain leads to one of those roots (RSA PKCS#1 and RSASSA-PSS, ECDSA P-256/P-384/P-521
signatures; validity, CA, key usage and name constraints), the certificate is for the host name or
IP address, CertificateVerify verifies and its Finished is right; otherwise the connection is
refused and the server is sent the alert that says why. The ServerHello is checked strictly (no
downgrade), KeyUpdate is followed, and a body that ends without its length, its last chunk or TLS
close_notify is reported incomplete (fetch does not save it). `fetch.Verbose` shows the handshake.
`gemini` trusts a server without a CA on first use, as the Gemini specification recommends: the
SHA-256 of its key is kept in `$HOME/.gemini_hosts`, and a different key later is refused.
`tools/fromvoc.py` copies a module of the tls repository with polpo's imports; the tests are in
`src/lib/tls/test` (`TLS_TEST_CERTS=src/lib/tls/test/certs loksh TLSTestChain.Run` and so on).

`http`, `Internet`, `Sockets`, `DNS`, `strUtils` and `Base64` are the same files in voc
(github.com/norayr: http, Internet, strutils, base64: main, master for Internet), apart from their
import lines; `tools/tovoc.py` writes the voc version of a file.

### xxs, a console editor

`xxs` is a small nano-like editor for the console, the size that fits every terminal:

```
bin/x86/loksh xxs.Open Oberon.Text     # edit the configuration...
bin/x86/loksh System.Init              # ...then start the desktop
bin/x86/loksh xxs.Fit notes.txt        # the same as xxs.Open; new files are created
```

It edits plain files and Oberon texts: plain files stay plain, Oberon texts keep their
fonts and colours (shown in the terminal) and new text gets the looks of the character
before it. The keys are nano's, shown at the bottom: ^O Write Out, ^X Exit, ^K Cut (a
line; ^K again adds the next), ^U Paste, ^W Where Is, ^C Location, ^G Help, ^A/^E line
start/end, ^Y/^V page up/down, and the arrows, Home, End, PgUp, PgDn. In the Write Out
prompt ^T switches between storing as Oberon text and as plain text, so an Oberon text can
be saved as a plain file. It runs on every port.

### X11 Oberon

The same `bin/x86/loksh` starts the whole Oberon desktop:

```
bin/x86/loksh System.Init
```

It loads the desktop modules from `obj/x86/` and forms the whole Oberon operating system.
`OWIDTH` and `OHEIGHT` set the size of the window.

Now it can draw itself in an X11 window.
But wait, it can also draw itself in other ways! Just replace the Display module.

### xterm Oberon

![](polpo.png)

Oberon can draw itself not only in X11, but in a bitmap graphics capable Unix terminal, such as xterm.
For that you need to compile other version of Display and Input modules.

```
make sixel
```

This will replace compiled Display.Obj and Input.Obj with the versions that work in xterm.

After that we suggest to use supplied `run.vt.sh` script that will open a conveniently big xterm and load oberon that would draw itself in it.

Oberon uses up to 256 sixel colour registers, assigned as colours appear on the screen,
so only colours actually shown cost traffic. `SXL_COLORS=16` (2..256) limits them for
terminals with fewer registers; colours beyond get the nearest one. xterm emulating a
VT340 has 16 registers unless `XTerm*numColorRegisters: 256` is set, as `run.vt.sh` does.

The same `bin/x86/loksh` (no need for relinking) will load modules, including Display and Input(but those are different Display and Input now), and the OS will now work in the terminal.

Since Oberon now draws itself in the VT320 capable Unix terminal, you can also run it via ssh.

To use X11 mode again, type:

```
make x11
```

#### Other terminals

In theory, mlterm should also work, at least they claim they support sixel mode.

And we don't know how xterm of your OS is compiled. We tested with xterm on Gentoo that is compiled with 'sixel' USE flag. Our friend confirmed that it worked on their Arch. Our other friend confirmed it didn't work on their Debian.

### HiDPI screens: font scaling

In short, there are two different things:

* `System.SetFontScale 150` makes **all fonts on the screen** larger: every viewer,
  menu and the log, at once (a broadcast). Documents are not changed. This is the
  command for a HiDPI screen.
* `Edit.ScaleFonts 50 *` changes the fonts **stored in one document**: the one in the
  marked viewer, or files named after the number. See the next section.

Screen fonts can be scaled, so that every text, including existing documents, is
shown larger with the real Syntax and Oberon bitmap fonts. The scale is in percent:

* `FontScale = 150` in the `System` section of `Oberon.Text` sets it at startup
  (next to `TimeDiff`); the environment variable `OFONTSCALE=150` overrides it;
* `System.SetFontScale 150` changes it while Oberon runs (middle-click it in a tool
  text): the fonts are reloaded, a message is broadcast, and all viewers, menus and
  the log lay out their texts again. `System.SetFontScale ^` takes a selected number,
  `System.SetFontScale` alone shows the current scale in the log;
* without a setting the scale follows the screen resolution reported by X11 or the
  framebuffer (96 dpi = 100%). Many X servers report 96 dpi, so set it explicitly.

A text asking for `Syntax10.Scn.Fnt` gets the existing font nearest to 10 * scale / 100,
of the same family if possible (at 200% the real Syntax20), else of the Oberon family.
Texts keep their font names, so documents are stored unchanged. In text viewers each
line is as high as the largest font on it, so headings get their full size;
`LineSpacing = 100` in the `System` section (percent of each line's height, default 100)
sets the spacing of lines; 120 or 150 give more room.

How `Oberon.Text` is read, and how your own programs can keep settings there, is
described in [texts.md](texts.md).

### Editing with the keyboard

Text viewers (tools like System.Tool, the log, texts opened with `Edit.Open`) can be
used like a common editor. The left pane, `System.Text`, is a Script viewer and keeps
the classic keys.

* arrows move the caret, Up and Down keep the column and scroll at the edges;
  Home/End go to the start/end of the line, Ctrl+Home/Ctrl+End of the text;
  Page Up/Page Down move by a viewer height
* Shift with any of these selects; Backspace or Delete removes a selection made so
* Ctrl+A selects the whole text
* Ctrl+C copies the selection, Ctrl+X cuts it, Ctrl+V pastes at the caret. Inside
  Oberon fonts and colours are kept. The copied text is also on the X clipboard, so
  Ctrl+V in other programs pastes it, and Ctrl+V in Oberon pastes what other programs
  copied. In xterm (sixel) Oberon, Ctrl+C sends the text to xterm's clipboard (OSC 52,
  when xterm allows it) and Shift+Insert pastes from other programs.
* Shift+right click extends the selection to the mouse, or selects from the caret to
  the mouse: left click at the start, scroll with the scroll bar, Shift+right click at
  the end, like in xterm. Scrolling keeps the selection and the caret.
* `Edit.Store` keeps a plain file (a `.Mod` source, `Oberon.Text`) plain as long as its
  text has one font and colour; the log then says `(plain)`. `Edit.StorePlain` (in the
  menu, or `Edit.StorePlain name` with the marked viewer) always stores plain ASCII,
  dropping fonts and colours

### Changing the fonts of a document

* `Edit.ChangeFont Syntax10.Scn.Fnt` sets the font of the selected text: select the text
  with the right mouse button first, then middle-click the command. It gives the whole
  selection one font.
* `Edit.ScaleFonts 50 *` scales all fonts of the text in the marked viewer (mark it with
  the star, F1), keeping family and style: Syntax20 becomes Syntax10, Syntax20b becomes
  Syntax10b; a size that does not exist becomes the nearest one that does. Store the text
  afterwards (Store in its menu).
* `Edit.ScaleFonts 50 System.Tool Oberon.Text ~` does the same for files, and stores them
  (the old versions are kept as `.Bak`). Plain ASCII files are left alone.
* `Edit.RenameFont Syntax20.Scn.Fnt Syntax10.Scn.Fnt *` (or with file names) replaces one
  font by another in the whole text.

With font scaling, documents can keep normal sizes (Syntax10, Syntax12) and be shown larger
on HiDPI screens; `Edit.ScaleFonts 50` brings documents that were enlarged by hand back.

### ARM

polpo also runs on 32-bit ARM Linux. The ARM compiler is the ETH/OLR ARM
compiler (Oberon-1). Object files are in `obj/arm/`, the static executable is
`bin/arm/loksh`.

```
make arm            # on x86: cross compile the ARM system
make arm-native     # on ARM: rebuild it with the ARM compiler (on x86: under qemu-arm)
make arm-run        # start the ARM desktop (System.Init); on x86 through qemu-arm
make arm-shell      # ARM console
```

`make arm` runs `tools/arm-cross.Tool` (the x86-hosted cross tools `acompiler`
and `alinker`) and then `tools/arm.Tool` (the ARM system). `make arm-native`
runs only `tools/arm.Tool`, with the ARM compiler. Both link
`bin/arm/loksh.new` and move it to `bin/arm/loksh`.

Directly, from the polpo directory (prefix `qemu-arm` on x86):

```
bin/arm/loksh texts.Show texts/UserGuide.Text
bin/arm/loksh compiler.Compile hello.Mod     # native ARM compiler
bin/arm/loksh hello.world
bin/arm/loksh System.Init                    # the Oberon desktop
```

On ARM, `compiler.Compile` and `linker.Link` are the ARM compiler and boot
linker. `make arm-sixel` and `make arm-x11` switch the ARM Display and Input
modules, like `make sixel` and `make x11` for x86.

### RISC-V

polpo runs on 32-bit RISC-V (RV32) Linux too. The compiler is OLR's OP2-based
ROP2 compiler (shared front end `ROPM`..`ROPP`, RISC-V back end `VOPL`..`VOPV`).
Object files are in `obj/riscv/`, the static executable is `bin/riscv/loksh`.

```
make riscv          # on x86: cross compile the RISC-V system
make riscv-native   # rebuild it with the RISC-V compiler (on x86: under qemu-riscv32)
make riscv-run      # start the RISC-V desktop (System.Init); on x86 through qemu-riscv32
make riscv-shell    # RISC-V console
```

`make riscv` runs `tools/rop2-cross.Tool` (the x86-hosted `rcompiler`, `rvcompiler`
and `rlinker`) and then `tools/riscv.Tool`. On RISC-V, `compiler.Compile` and
`linker.Link` are the RISC-V compiler and boot linker. The runtime uses the
Linux RV32 system calls (64-bit time, statx).

### MIPS

polpo runs on 32-bit little-endian MIPS (mipsel) Linux, with the same ROP2
compiler family and runtime as RISC-V and the MIPS back end `MOPL`..`MOPV`.
Object files are in `obj/mips/`, the static executable is `bin/mips/loksh`.

```
make mips           # on x86: cross compile the MIPS system
make mips-native    # rebuild it with the MIPS compiler (on x86: under qemu-mipsel)
make mips-run       # start the MIPS desktop (System.Init); on x86 through qemu-mipsel
make mips-shell     # MIPS console
```

On MIPS, `compiler.Compile` and `linker.Link` are the MIPS compiler and boot
linker. The compiler avoids misaligned word accesses (it uses LWL/LWR and
SWL/SWR where alignment is unknown), so no kernel fixups are needed.

### ARMv7

Besides the Oberon-1 ARM compiler for older ARM processors (`make arm`, `obj/arm/`),
polpo has an ARMv7 system built with OLR's OP2 ARM back end `AOPL`..`AOPV` from the
same ROP2 family as MIPS and RISC-V. Object files are in `obj/armv7/`, the static
executable is `bin/armv7/loksh`.

```
make armv7          # on x86: cross compile the ARMv7 system
make armv7-native   # rebuild it with the ARMv7 compiler (on x86: under qemu-arm)
make armv7-run      # start the ARMv7 desktop (System.Init); on x86 through qemu-arm
make armv7-shell    # ARMv7 console
```

The ARMv7 compiler uses software division by default, so the code also runs on
Cortex-A8 and A9, which have no divide instruction; `/d` selects the hardware `sdiv`.

Note: the ROP2 compilers (MIPS, RISC-V, ARMv7) trap on `DIV` and `MOD` by a divisor
that is not positive, while the x86 compiler computes the floored result.

### Layout

* `bin/<arch>/loksh` - static executables; run them from the polpo directory
* `obj/<arch>/` - object files loaded by `bin/<arch>/loksh`
* `src/cli` - console modules shared by all architectures; `src/cli/<arch>` - runtime
  (Linux0, Kernel, Modules0), compiler and linker of that architecture; `src/cli/rop2` -
  the ROP2 compiler front end, runtime (Kernel, Modules0) and boot linker shared by MIPS,
  RISC-V and ARMv7
* `src/common` - modules shared by console and desktop (Files, Texts0, Oberon0, ...)
* `src/desktop` - desktop modules shared by all architectures; `src/desktop/<arch>` -
  architecture dependent desktop modules (XCompiler, ACompiler, RCompiler, decoders, browsers, System on RISC-V)
* `tools/` - `.Tool` texts, including the build recipes `build.Tool`, `arm-cross.Tool`, `arm.Tool`, `rop2-cross.Tool`, `riscv.Tool`, `mips.Tool` and `armv7.Tool`
* `share/` - data files (`Default.Pal`, `OPA.Data`, `System.Text`, ...)
* `fonts/`, `texts/` - fonts and documentation texts; `Oberon.Text` is the configuration

`bin/<arch>/loksh` finds the polpo root from its own location (`/proc/self/exe`,
also through symlinks and `PATH`), or from the environment variable `POLPO`. So it
can be started from any directory. A project directory can have its own `obj/<arch>/`:
the compiler then writes its objects there, and modules and symbol files that are not
there are taken from the root's `obj/<arch>/`. `Files.Old` looks for a plain file name in
the current directory, then in the root and its `share/`, `tools/` and `fonts/`, and for
a relative path such as `obj/x86/Texts.Sym` in the current directory, then in the root. So
`Oberon.Text`, `Edit.Open System.Tool` and fonts are found from anywhere.

Files are saved where they were found: `Store` in the menu of `System.Tool` writes
`tools/System.Tool` (and `tools/System.Tool.Bak`), unless there is a `System.Tool` in the
current directory. A new name is created in the current directory; to make a local copy
of a file from the root, store it as `./System.Tool`. A saved file replaces the old one
instead of overwriting it, so a running Oberon keeps working while its object files are
recompiled.

---



Wait for us for updates, or join #oberon on irc.libera.chat and help with development!
At least, we want to add ARM and other compilers, integrate vipak package manager, and run the os also natively. We also want to have 64-bit compiler backends.

Till.
