MODULE portia;  (** polpo's package manager; reads the package tree arden *)

(* portia.List [category]   the packages, of a category: linux, system, devel, apps, games, lib
   portia.Info name         a package: description, dependencies, provides, conflicts
   portia.Files name        the files of a package on this architecture
   portia.Owner file        the package a file belongs to (sources, objects, data)
   portia.Check             every file present, every import satisfied by the package
                            itself or its dependencies
   portia.Build [/arch] [name ...]  compile the packages and their dependencies in order
                            (modules ordered by their imports), then link; without names
                            every installed package; /arm, /riscv ... for another one
   Install, Upgrade, Build and Remove show what they will do and ask; /y does not ask.
   portia.Install [/arch] name ...  build, link and record packages; dependencies only when
                            missing or older than needed
   portia.Upgrade [/arch] [name ...]  the installed packages with newer versions in the tree,
                            and the remote ones compiled before an interface they import
                            changed (after a git pull of polpo)
   When the interface of a module changes (its symbol file), the installed packages with a
   module importing it are recompiled, and so on.
   portia.Remove [/arch] [/src | /all] [/deps] name ...   delete their objects and unrecord
                            them, if nothing needs them (/deps: what needs them goes too);
                            /src: the downloaded sources only, /all: both
   portia.Test name ...     run the tests of installed packages ([TESTS]); Install /t and
                            Build /t test after building
   portia.Fetch name ...    download the sources of remote packages, checked by their sums
   portia.Sums name [dir]   the [SUMS] section of a remote package, from its files in dir
                            (default: where portia keeps them)
   portia.Graph [name]      the dependencies as a Graphviz (.dot) graph
   portia.Record, portia.Mark name, portia.Unmark name   the record of installed packages:
                            portia.base.<arch> (the base system, comes with polpo) and
                            portia.world.<arch> (local: packages added, "-name" for base
                            packages removed)

   portia.Sync              the package tree: the newest commit of github.com/polpo-system/arden,
                            downloaded as files into <polpo root>/arden/ (not into a git checkout)

   The tree: the environment variable PORTIA_TREE, Portia.Tree in Oberon.Text, or
   <polpo root>/arden/. Package descriptions
   are TOML: <tree>/<category>/<name>/<name>-<version>.arden; INDEX lists category/name
   and version. Packages are found by name or by category/name.

   Remote packages ([REMOTE] type = files) have their sources in another repository: uri is the
   base of the links of their files (https://, http://, gemini:// or spartan://, downloaded with
   fetch.Get, gemini.Get or spartan.Get). Every file needs its sum in [SUMS] (path = "sha256:..."
   or "md5:...", paths as in the repository); a file whose sum differs is refused. The files are
   kept in src/pkg/<name>/ with their repository paths. A [FILES] entry "path=dest" is copied to
   dest in the polpo root (share/, tools/: where Files.Old finds plain names) and removed with
   the objects; the copies in src/pkg/<name>/ go with /src. *)

IMPORT Kernel, Linux0, SYSTEM, F := Files, FATFiles, Root, Texts := texts, Oberon := Oberon0, TOML, Versions, Checksums, termios, out;

CONST
  NameLen = 256;
  SYS = "SYSTEM";
  EndMark = "portia: end of the tests";  (* the tests ran to their end *)
  PkgDir = "src/pkg/"; PkgDirLen = 8;  (* the sources of remote packages, src/pkg/<name>/ *)
  ATREMOVEDIR = 200H;
  TreeRepo = "polpo-system/arden"; TreeBranch = "master";  (* where portia.Sync gets the tree *)

TYPE
  Name = ARRAY NameLen OF CHAR;
  Buf = POINTER TO ARRAY OF CHAR;
  Item = POINTER TO ItemDesc;
  ItemDesc = RECORD
    s: Name;
    v: ARRAY 32 OF CHAR;  (* a version: of a dependency the least needed, of an installed package its own *)
    flags: ARRAY 16 OF CHAR;  (* compiler options of a source *)
    r: Name;  (* of a remote package: the path in its repository; in sums: the sum *)
    next: Item
  END;

  Package = POINTER TO PackageDesc;
  PackageDesc = RECORD
    name, category, version, desc: Name;  (* category: linux, system, devel, apps, games, lib *)
    deps, provides, conflicts, sources, files, modules, build: Item;  (* modules: names of sources *)
    remote: Name;  (* the base of the links of a remote package, else "" *)
    sums: Item;  (* of a remote package: repository path, sum in r *)
    tcopy, tcmds, tok, tbad: Item;  (* [TESTS]: files to copy, commands, lines expected, texts refused *)
    tdisplay: BOOLEAN;  (* the tests need the desktop (X11) *)
    next: Package
  END;

VAR
  tree: Name;  (* with trailing / *)
  arch, hostArch: ARRAY 16 OF CHAR;  (* the architecture packages are read for, the one running *)
  packages: Package;
  imports: Item;  (* of the last source parsed *)
  installed: Item; haveDb: BOOLEAN;  (* the installed packages of this architecture *)
  base: Item;  (* the base system of this architecture, portia.base.<arch> *)
  converted: BOOLEAN;  (* LoadDb made portia.world.<arch> from portia.<arch> *)
  assumeYes: BOOLEAN;  (* /y: do not ask *)
  delObj, delSrc: BOOLEAN;
  doTest: BOOLEAN;  (* /t: Install and Build test the packages *)
  withDeps: BOOLEAN;  (* /deps: Remove also removes the installed packages that need the named ones *)
  entries: Item;  (* of Collect: the entries of a directory, s with "/" at the end for directories *)  (* Remove: the objects (default), the downloaded sources (/src), both (/all) *)
  changedMods: Item;  (* modules whose interface changed in this run *)

(* ----- strings and lists ----- *)

PROCEDURE Pre;  (* the start of a message; one string for the ARM compiler's 4 KB of strings *)
BEGIN out.String("portia: ")
END Pre;

PROCEDURE Usage(s: ARRAY OF CHAR);  (* "usage: portia." s *)
BEGIN out.String("usage: portia."); out.String(s); out.Ln
END Usage;

PROCEDURE NoPackage(VAR name: ARRAY OF CHAR);
BEGIN Pre; out.String("no package "); out.String(name); out.Ln
END NoPackage;

PROCEDURE Append(VAR s: ARRAY OF CHAR; t: ARRAY OF CHAR);
VAR i, j: LONGINT;
BEGIN
  i := 0; WHILE s[i] # 0X DO INC(i) END;
  j := 0; WHILE (t[j] # 0X) & (i < LEN(s) - 1) DO s[i] := t[j]; INC(i); INC(j) END;
  s[i] := 0X
END Append;

PROCEDURE Len(VAR s: ARRAY OF CHAR): LONGINT;
VAR i: LONGINT;
BEGIN i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END; RETURN i
END Len;

PROCEDURE Add(VAR list: Item; s: ARRAY OF CHAR);  (* at the end *)
VAR it, p: Item;
BEGIN
  NEW(it); COPY(s, it.s); it.next := NIL;
  IF list = NIL THEN list := it ELSE p := list; WHILE p.next # NIL DO p := p.next END; p.next := it END
END Add;

PROCEDURE Has(list: Item; s: ARRAY OF CHAR): BOOLEAN;
BEGIN
  WHILE (list # NIL) & (list.s # s) DO list := list.next END;
  RETURN list # NIL
END Has;

PROCEDURE Prefix(VAR s: ARRAY OF CHAR; pre: ARRAY OF CHAR): BOOLEAN;
VAR i: LONGINT;
BEGIN
  i := 0; WHILE (pre[i] # 0X) & (s[i] = pre[i]) DO INC(i) END;
  RETURN pre[i] = 0X
END Prefix;

(* add the blank separated words of s to list *)
PROCEDURE AddWords(VAR list: Item; VAR s: ARRAY OF CHAR);
VAR i, j: LONGINT; w: Name;
BEGIN
  i := 0;
  WHILE s[i] # 0X DO
    WHILE (s[i] = " ") OR (s[i] = 09X) OR (s[i] = 0AX) OR (s[i] = 0DX) DO INC(i) END;
    j := 0;
    WHILE (s[i] # 0X) & (s[i] # " ") & (s[i] # 09X) & (s[i] # 0AX) & (s[i] # 0DX) DO
      IF j < NameLen - 1 THEN w[j] := s[i]; INC(j) END; INC(i)
    END;
    w[j] := 0X;
    IF w # "" THEN Add(list, w) END
  END
END AddWords;

(* the sources of a MODULES value: paths, each after its compiler options ("/x path") *)
PROCEDURE AddSources(VAR list: Item; VAR s: ARRAY OF CHAR);
VAR words, w, it: Item; flags: ARRAY 16 OF CHAR;
BEGIN
  words := NIL; AddWords(words, s); flags := ""; w := words;
  WHILE w # NIL DO
    IF w.s[0] = "/" THEN Append(flags, " "); Append(flags, w.s)
    ELSE Add(list, w.s); it := list; WHILE it.next # NIL DO it := it.next END; COPY(flags, it.flags); flags := ""
    END;
    w := w.next
  END
END AddSources;

(* the commands of a BUILD value, separated by ";" *)
PROCEDURE AddCommands(VAR list: Item; VAR s: ARRAY OF CHAR);
VAR i, j: LONGINT; c: Name;
BEGIN
  i := 0;
  WHILE s[i] # 0X DO
    WHILE s[i] = " " DO INC(i) END;
    j := 0; WHILE (s[i] # 0X) & (s[i] # ";") DO IF j < NameLen - 1 THEN c[j] := s[i]; INC(j) END; INC(i) END;
    WHILE (j > 0) & (c[j-1] = " ") DO DEC(j) END;
    c[j] := 0X; IF c # "" THEN Add(list, c) END;
    IF s[i] = ";" THEN INC(i) END
  END
END AddCommands;

(* ----- reading Oberon sources: the module name and its imports ----- *)

(* the MODULE name of the source path and its imports (in imports); FALSE if unreadable *)
PROCEDURE Header(VAR path: ARRAY OF CHAR; VAR mod: ARRAY OF CHAR): BOOLEAN;
VAR T: Texts.Text; R: Texts.Reader; ch, pend: CHAR; havePend: BOOLEAN; tok, last: Name;

  PROCEDURE Get;
  BEGIN
    IF havePend THEN ch := pend; havePend := FALSE ELSE Texts.Read(R, ch) END
  END Get;

  PROCEDURE Comment;  (* after the start of a comment; comments nest *)
  VAR depth: INTEGER;
  BEGIN
    depth := 1; Get;
    WHILE ~R.eot & (depth > 0) DO
      IF ch = "(" THEN Get; IF ch = "*" THEN INC(depth); Get END
      ELSIF ch = "*" THEN Get; IF ch = ")" THEN DEC(depth); Get END
      ELSE Get
      END
    END
  END Comment;

  (* the next token: a name, or a symbol of one or two characters *)
  PROCEDURE Token;
  VAR i: INTEGER;
  BEGIN
    LOOP
      WHILE ~R.eot & (ch <= " ") DO Get END;
      IF (ch = "(") & ~R.eot THEN
        Get;
        IF ch = "*" THEN Comment ELSE pend := ch; havePend := TRUE; ch := "("; EXIT END
      ELSE EXIT
      END
    END;
    i := 0;
    IF R.eot THEN tok := ""
    ELSIF (CAP(ch) >= "A") & (CAP(ch) <= "Z") OR (ch = "_") THEN
      WHILE (CAP(ch) >= "A") & (CAP(ch) <= "Z") OR (ch >= "0") & (ch <= "9") OR (ch = "_") DO
        IF i < NameLen - 1 THEN tok[i] := ch; INC(i) END; Get
      END;
      tok[i] := 0X
    ELSIF ch = ":" THEN Get; IF ch = "=" THEN tok := ":="; Get ELSE tok := ":" END
    ELSE tok[0] := ch; tok[1] := 0X; Get
    END
  END Token;

BEGIN
  imports := NIL; mod[0] := 0X;
  IF F.Old(path) = NIL THEN RETURN FALSE END;
  NEW(T); Texts.Open(T, path); Texts.OpenReader(R, T, 0); havePend := FALSE; Get;
  Token; WHILE (tok # "") & (tok # "MODULE") DO Token END;
  IF tok = "" THEN RETURN FALSE END;
  Token; COPY(tok, mod);
  Token; IF tok = "*" THEN Token END;  (* MODULE *Name in some sources *)
  Token;  (* after ";" *)
  IF tok = "IMPORT" THEN
    last := "";
    LOOP
      Token;
      IF (tok = ";") OR (tok = "") THEN EXIT
      ELSIF tok = "," THEN IF last # "" THEN Add(imports, last); last := "" END
      ELSIF tok = ":=" THEN  (* alias := module: the module follows *)
      ELSIF (CAP(tok[0]) >= "A") & (CAP(tok[0]) <= "Z") OR (tok[0] = "_") THEN COPY(tok, last)  (* after := the real name *)
      END
    END;
    IF last # "" THEN Add(imports, last) END
  END;
  RETURN TRUE
END Header;

(* ----- the tree ----- *)

PROCEDURE ReadFile(VAR path: ARRAY OF CHAR; VAR buf: Buf): BOOLEAN;
VAR f: F.File; R: F.Rider; n, i: LONGINT; c: CHAR;
BEGIN
  f := F.Old(path);
  IF f = NIL THEN RETURN FALSE END;
  n := F.Length(f); NEW(buf, n + 1);
  F.Set(R, f, 0); i := 0;
  WHILE i < n DO F.Read(R, c); buf[i] := c; INC(i) END;
  buf[n] := 0X; F.ReleaseRead(f);
  RETURN TRUE
END ReadFile;

PROCEDURE Field(doc: TOML.Doc; sec, key: ARRAY OF CHAR; VAR val: ARRAY OF CHAR): BOOLEAN;
VAR s: TOML.Section;
BEGIN
  s := TOML.GetSection(doc, sec);
  IF s = NIL THEN val[0] := 0X; RETURN FALSE END;
  RETURN TOML.GetField(s, key, val)
END Field;

(* the commands of a field: the elements of an array, or a text separated by ";" *)
PROCEDURE Commands(doc: TOML.Doc; sec, key: ARRAY OF CHAR; VAR list: Item);
VAR f: TOML.Field; it: TOML.Item;
BEGIN
  f := TOML.Find(TOML.GetSection(doc, sec), key);
  IF f = NIL THEN
  ELSIF f.kind = TOML.Array THEN it := f.items; WHILE it # NIL DO Add(list, it.value); it := it.next END
  ELSE AddCommands(list, f.value)
  END
END Commands;

(* the keys of section sec as a list (deps, provides, conflicts) *)
PROCEDURE Keys(doc: TOML.Doc; sec: ARRAY OF CHAR; VAR list: Item);
VAR s: TOML.Section; f: TOML.Field; it: Item;
BEGIN
  s := TOML.GetSection(doc, sec);
  IF s # NIL THEN
    f := s.first;
    WHILE f # NIL DO
      Add(list, f.key); it := list; WHILE it.next # NIL DO it := it.next END; COPY(f.value, it.v);
      f := f.next
    END
  END
END Keys;

(* the [SUMS] of a remote package: keys are repository paths (quoted or not) *)
PROCEDURE ReadSums(doc: TOML.Doc; VAR list: Item);
VAR s: TOML.Section; f: TOML.Field; it: Item; key: Name; i, j: LONGINT;
BEGIN
  key := "SUMS"; s := TOML.GetSection(doc, key);
  IF s # NIL THEN
    f := s.first;
    WHILE f # NIL DO
      i := 0; j := 0;
      WHILE f.key[i] # 0X DO IF f.key[i] # 22X THEN key[j] := f.key[i]; INC(j) END; INC(i) END;
      key[j] := 0X;
      Add(list, key); it := list; WHILE it.next # NIL DO it := it.next END; COPY(f.value, it.r);
      f := f.next
    END
  END
END ReadSums;

(* the directory of the downloaded files of p, relative to the root: src/pkg/<name>/ *)
PROCEDURE PackageDir(p: Package; VAR dir: ARRAY OF CHAR);
BEGIN COPY(PkgDir, dir); Append(dir, p.name); Append(dir, "/")
END PackageDir;

(* of a remote package the sources are in its directory, the files go to their destination:
   r is the repository path, s the path in the root *)
PROCEDURE Localize(p: Package);
VAR it: Item; dir: Name; i, j: LONGINT;
BEGIN
  PackageDir(p, dir);
  it := p.sources;
  WHILE it # NIL DO COPY(it.s, it.r); COPY(dir, it.s); Append(it.s, it.r); it := it.next END;
  it := p.files;
  WHILE it # NIL DO
    i := 0; WHILE (it.s[i] # 0X) & (it.s[i] # "=") DO it.r[i] := it.s[i]; INC(i) END; it.r[i] := 0X;
    IF it.s[i] = "=" THEN  (* path=dest *)
      INC(i); j := 0; WHILE it.s[i] # 0X DO it.s[j] := it.s[i]; INC(i); INC(j) END; it.s[j] := 0X
    ELSE COPY(dir, it.s); Append(it.s, it.r)
    END;
    it := it.next
  END
END Localize;

(* load the package at entry, "category/name" (or "name") of the INDEX, in version *)
PROCEDURE Load(VAR entry, version: ARRAY OF CHAR): Package;
VAR path, name, cat: Name; buf: Buf; doc: TOML.Doc; p: Package; v: ARRAY 4096 OF CHAR; it: Item; mod: Name; i, j, k: LONGINT;
BEGIN
  i := 0; k := -1; WHILE entry[i] # 0X DO IF entry[i] = "/" THEN k := i END; INC(i) END;
  i := 0; WHILE i < k DO cat[i] := entry[i]; INC(i) END; cat[i] := 0X;
  j := 0; i := k + 1; WHILE entry[i] # 0X DO name[j] := entry[i]; INC(i); INC(j) END; name[j] := 0X;
  COPY(tree, path); IF cat # "" THEN Append(path, cat); Append(path, "/") END;
  Append(path, name); Append(path, "/"); Append(path, name); Append(path, "-");
  Append(path, version); Append(path, ".arden");
  IF ~ReadFile(path, buf) THEN Pre; out.String("cannot read "); out.String(path); out.Ln; RETURN NIL END;
  doc := TOML.Parse(buf^);
  IF doc.errors > 0 THEN
    Pre; out.String(path); out.Char(":"); out.Int(doc.errorLine, 0); out.String(": "); out.String(doc.error);
    IF doc.errors > 1 THEN out.String(" (and "); out.Int(doc.errors - 1, 0); out.String(" more)") END; out.Ln
  END;
  NEW(p); COPY(name, p.name); COPY(cat, p.category); COPY(version, p.version);
  IF ~Field(doc, "PACKAGE", "description", p.desc) THEN p.desc := "" END;
  p.remote := "";
  IF Field(doc, "REMOTE", "type", v) & (v = "files") & Field(doc, "REMOTE", "uri", v) THEN
    COPY(v, p.remote); i := Len(p.remote); IF (i > 0) & (p.remote[i-1] = "/") THEN p.remote[i-1] := 0X END;
    ReadSums(doc, p.sums)
  END;
  Keys(doc, "DEPS", p.deps); Keys(doc, "PROVIDES", p.provides); Keys(doc, "CONFLICTS", p.conflicts);
  IF Field(doc, "MODULES", "all", v) THEN AddSources(p.sources, v) END;
  IF Field(doc, "MODULES", arch, v) THEN AddSources(p.sources, v) END;
  Commands(doc, "BUILD", arch, p.build);
  IF Field(doc, "FILES", "all", v) THEN AddWords(p.files, v) END;
  IF Field(doc, "FILES", arch, v) THEN AddWords(p.files, v) END;
  IF p.remote # "" THEN Localize(p) END;
  IF Field(doc, "TESTS", "copy", v) THEN AddWords(p.tcopy, v) END;
  Commands(doc, "TESTS", "cmds", p.tcmds);
  COPY("TESTS.", mod); Append(mod, arch); Commands(doc, mod, "cmds", p.tcmds);  (* [TESTS.x86] cmds after *)
  Commands(doc, "TESTS", "ok", p.tok); Commands(doc, "TESTS", "bad", p.tbad);
  p.tdisplay := Field(doc, "TESTS", "display", v) & (v = "true");
  it := p.sources;
  WHILE it # NIL DO
    IF Header(it.s, mod) THEN Add(p.modules, mod)
    ELSE  (* not here (yet): the module named as the file *)
      i := 0; k := 0; WHILE it.s[i] # 0X DO IF it.s[i] = "/" THEN k := i + 1 END; INC(i) END;
      j := 0; WHILE (it.s[k] # 0X) & (it.s[k] # ".") DO mod[j] := it.s[k]; INC(j); INC(k) END; mod[j] := 0X;
      Add(p.modules, mod)
    END;
    it := it.next
  END;
  RETURN p
END Load;

PROCEDURE ^LoadDb;
PROCEDURE ^SaveDb;
PROCEDURE ^Drop(VAR list: Item; s: ARRAY OF CHAR);

PROCEDURE LoadTree(): BOOLEAN;
VAR path: Name; buf: Buf; i, j: LONGINT; name, version: Name; p, last: Package;
BEGIN
  converted := FALSE; LoadDb;
  IF packages # NIL THEN RETURN TRUE END;
  COPY(tree, path); Append(path, "INDEX");
  IF ~ReadFile(path, buf) THEN
    Pre; out.String("no package tree at "); out.String(tree);
    out.String(": portia.Sync downloads it (or PORTIA_TREE, Portia.Tree in Oberon.Text)"); out.Ln; RETURN FALSE
  END;
  i := 0; last := NIL;
  WHILE buf[i] # 0X DO
    j := 0; WHILE (buf[i] > " ") DO name[j] := buf[i]; INC(i); INC(j) END; name[j] := 0X;
    WHILE (buf[i] = " ") OR (buf[i] = 09X) DO INC(i) END;
    j := 0; WHILE (buf[i] > " ") DO version[j] := buf[i]; INC(i); INC(j) END; version[j] := 0X;
    WHILE (buf[i] # 0X) & (buf[i] # 0AX) DO INC(i) END;
    IF buf[i] = 0AX THEN INC(i) END;
    IF name # "" THEN
      p := Load(name, version);
      IF p # NIL THEN IF last = NIL THEN packages := p ELSE last.next := p END; last := p END
    END
  END;
  IF converted THEN  (* the old record had base packages of other architectures, empty here *)
    p := packages;
    WHILE p # NIL DO IF (p.remote = "") & ~Has(base, p.name) THEN Drop(installed, p.name) END; p := p.next END;
    SaveDb; converted := FALSE
  END;
  RETURN TRUE
END LoadTree;

(* the package name, or category/name *)
PROCEDURE Find(VAR name: ARRAY OF CHAR): Package;
VAR p: Package; i, k: LONGINT; cat, n: Name;
BEGIN
  i := 0; k := -1; WHILE name[i] # 0X DO IF name[i] = "/" THEN k := i END; INC(i) END;
  IF k < 0 THEN
    p := packages; WHILE (p # NIL) & (p.name # name) DO p := p.next END
  ELSE
    i := 0; WHILE i < k DO cat[i] := name[i]; INC(i) END; cat[i] := 0X;
    i := 0; WHILE name[k+1+i] # 0X DO n[i] := name[k+1+i]; INC(i) END; n[i] := 0X;
    p := packages; WHILE (p # NIL) & ((p.name # n) OR (p.category # cat)) DO p := p.next END
  END;
  RETURN p
END Find;

(* the object files of module mod on this architecture *)
PROCEDURE ObjFile(VAR mod: ARRAY OF CHAR; sym: BOOLEAN; VAR path: ARRAY OF CHAR);
BEGIN
  COPY("obj/", path); Append(path, arch); Append(path, "/"); Append(path, mod);
  IF sym THEN Append(path, ".Sym") ELSE Append(path, ".Obj") END
END ObjFile;

(* opened read-only: a running binary cannot be opened for writing *)
PROCEDURE Exists(VAR path: ARRAY OF CHAR): BOOLEAN;
VAR full: Name;
BEGIN
  IF Root.Exists(path) THEN RETURN TRUE END;
  Root.Join(path, full); RETURN Root.Exists(full)
END Exists;

PROCEDURE Installed(p: Package): BOOLEAN;  (* all sources, objects and files here *)
VAR it: Item; path: Name;
BEGIN
  it := p.sources; WHILE it # NIL DO IF ~Exists(it.s) THEN RETURN FALSE END; it := it.next END;
  it := p.modules; WHILE it # NIL DO ObjFile(it.s, FALSE, path); IF ~Exists(path) THEN RETURN FALSE END; it := it.next END;
  it := p.files; WHILE it # NIL DO IF ~Exists(it.s) THEN RETURN FALSE END; it := it.next END;
  RETURN TRUE
END Installed;

(* the downloaded sources of p are here *)
PROCEDURE HasSources(p: Package): BOOLEAN;
VAR it: Item;
BEGIN
  it := p.sources; WHILE it # NIL DO IF ~Exists(it.s) THEN RETURN FALSE END; it := it.next END;
  RETURN p.sources # NIL
END HasSources;

(* ----- the installed packages ----- *)

(* <root>portia.base.<arch>: the base system, installed with polpo (written by genarden, in git);
   <root>portia.world.<arch>: this installation (not in git): the packages added, lines
   "name version", and "-name" for a base package removed or replaced. installed: both together *)

PROCEDURE RecName(kind: ARRAY OF CHAR; VAR path: ARRAY OF CHAR);
VAR n: Name;
BEGIN n := "portia."; Append(n, kind); IF kind # "" THEN Append(n, ".") END; Append(n, arch); Root.Join(n, path)
END RecName;

(* the lines of the record file path into list (with versions), the "-name" ones into removed *)
PROCEDURE ReadRec(VAR path: ARRAY OF CHAR; VAR list, removed: Item): BOOLEAN;
VAR buf: Buf; i, j: LONGINT; name, ver: Name; it: Item;
BEGIN
  list := NIL; removed := NIL;
  IF ~ReadFile(path, buf) THEN RETURN FALSE END;
  i := 0;
  WHILE buf[i] # 0X DO
    j := 0; WHILE buf[i] > " " DO name[j] := buf[i]; INC(i); INC(j) END; name[j] := 0X;
    WHILE (buf[i] = " ") OR (buf[i] = 09X) DO INC(i) END;
    j := 0; WHILE buf[i] > " " DO ver[j] := buf[i]; INC(i); INC(j) END; ver[j] := 0X;
    WHILE (buf[i] # 0X) & (buf[i] # 0AX) DO INC(i) END;
    IF buf[i] = 0AX THEN INC(i) END;
    IF name[0] = "-" THEN
      j := 0; WHILE name[j+1] # 0X DO name[j] := name[j+1]; INC(j) END; name[j] := 0X; Add(removed, name)
    ELSIF name # "" THEN
      Add(list, name); it := list; WHILE it.next # NIL DO it := it.next END; COPY(ver, it.v)
    END
  END;
  RETURN TRUE
END ReadRec;

PROCEDURE Ver(list: Item; VAR name, v: ARRAY OF CHAR): BOOLEAN;  (* the version of name in list *)
BEGIN
  WHILE (list # NIL) & (list.s # name) DO list := list.next END;
  IF list = NIL THEN RETURN FALSE END;
  COPY(list.v, v); RETURN TRUE
END Ver;

PROCEDURE LoadDb;
VAR path, old: Name; world, removed, it, x: Item; haveBase, haveWorld: BOOLEAN; v: ARRAY 32 OF CHAR; r: INTEGER;
BEGIN
  installed := NIL;
  RecName("base", path); haveBase := ReadRec(path, base, x);
  RecName("world", path); haveWorld := ReadRec(path, world, removed);
  IF ~haveWorld THEN  (* the record of before: everything in portia.<arch>; what differs from base goes to world *)
    RecName("", old);
    IF ReadRec(old, installed, x) THEN
      haveDb := TRUE; converted := TRUE; SaveDb; COPY(old, path); Append(path, ".old"); F.Rename(old, path, r);
      Pre; out.String("the record is now portia.world."); out.String(arch); out.String(" (the packages besides the base system); the old one is "); out.String(path); out.Ln;
      RETURN
    END
  END;
  it := base;
  WHILE it # NIL DO
    IF ~Has(removed, it.s) THEN Add(installed, it.s); x := installed; WHILE x.next # NIL DO x := x.next END; COPY(it.v, x.v) END;
    it := it.next
  END;
  it := world;
  WHILE it # NIL DO
    x := installed; WHILE (x # NIL) & (x.s # it.s) DO x := x.next END;
    IF x = NIL THEN Add(installed, it.s); x := installed; WHILE x.next # NIL DO x := x.next END END;
    COPY(it.v, x.v); it := it.next
  END;
  haveDb := haveBase OR haveWorld
END LoadDb;

(* portia.world.<arch>: installed against base *)
PROCEDURE SaveDb;
VAR path: Name; f: F.File; R: F.Rider; it: Item; i: LONGINT; v: ARRAY 32 OF CHAR;

  PROCEDURE W(s: ARRAY OF CHAR);
  BEGIN i := 0; WHILE s[i] # 0X DO F.Write(R, s[i]); INC(i) END
  END W;

BEGIN
  RecName("world", path); f := F.New(path);
  IF f = NIL THEN Pre; out.String("cannot write "); out.String(path); out.Ln; RETURN END;
  F.Set(R, f, 0); it := installed;
  WHILE it # NIL DO
    IF ~Ver(base, it.s, v) OR (v # it.v) THEN W(it.s); W(" "); W(it.v); F.Write(R, 0AX) END;
    it := it.next
  END;
  it := base;
  WHILE it # NIL DO
    IF ~Has(installed, it.s) THEN W("-"); W(it.s); F.Write(R, 0AX) END;
    it := it.next
  END;
  F.Register(f); haveDb := TRUE
END SaveDb;

PROCEDURE Drop(VAR list: Item; s: ARRAY OF CHAR);
VAR p: Item;
BEGIN
  IF list # NIL THEN
    IF list.s = s THEN list := list.next
    ELSE p := list; WHILE (p.next # NIL) & (p.next.s # s) DO p := p.next END; IF p.next # NIL THEN p.next := p.next.next END
    END
  END
END Drop;

(* record name as installed in version v *)
PROCEDURE SetInstalled(name, v: ARRAY OF CHAR);
VAR it: Item;
BEGIN
  it := installed; WHILE (it # NIL) & (it.s # name) DO it := it.next END;
  IF it = NIL THEN Add(installed, name); it := installed; WHILE it.next # NIL DO it := it.next END END;
  COPY(v, it.v)
END SetInstalled;

(* the installed version of p; FALSE if it is not recorded *)
PROCEDURE InstVer(p: Package; VAR v: ARRAY OF CHAR): BOOLEAN;
VAR it: Item;
BEGIN
  it := installed; WHILE (it # NIL) & (it.s # p.name) DO it := it.next END;
  IF it = NIL THEN v[0] := 0X; RETURN FALSE END;
  COPY(it.v, v); RETURN TRUE
END InstVer;

(* installed: in the record, or without a record, all its files here *)
PROCEDURE IsInstalled(p: Package): BOOLEAN;
BEGIN
  IF haveDb THEN RETURN Has(installed, p.name) END;
  RETURN Installed(p)
END IsInstalled;

(* ----- commands ----- *)

PROCEDURE Arg(VAR s: ARRAY OF CHAR): BOOLEAN;
VAR A: Texts.Reader;
BEGIN Texts.OpenArgs(A); RETURN Texts.Arg(A, s)
END Arg;

PROCEDURE ListItems(label: ARRAY OF CHAR; it: Item);
BEGIN
  IF it # NIL THEN
    out.String(label); WHILE it # NIL DO out.Char(" "); out.String(it.s); it := it.next END; out.Ln
  END
END ListItems;

(** portia.List [category] -- the packages of the tree (of one category: linux, system,
  devel, apps, games, lib); i: installed here, u: a newer version in the tree, s: the sources of a
  remote package downloaded, not installed; r: a remote package *)
PROCEDURE List*;
VAR p: Package; n: LONGINT; v: ARRAY 32 OF CHAR; cat: Name; all: BOOLEAN;
BEGIN
  IF ~LoadTree() THEN RETURN END;
  all := ~Arg(cat);
  p := packages;
  WHILE p # NIL DO
   IF all OR (p.category = cat) THEN
    IF ~IsInstalled(p) THEN
      IF (p.remote # "") & HasSources(p) THEN out.String("s ") ELSE out.String("  ") END  (* downloaded, not built *)
    ELSIF haveDb & InstVer(p, v) & ~Versions.AtLeast(v, p.version) THEN out.String("u ")  (* upgradable *)
    ELSE out.String("i ")
    END;
    IF p.remote # "" THEN out.String("r ") ELSE out.String("  ") END;
    out.String(p.category); out.Char("/"); out.String(p.name);
    n := 1 + Len(p.category) + Len(p.name); WHILE n < 30 DO out.Char(" "); INC(n) END;
    IF haveDb & InstVer(p, v) & (Versions.Compare(v, p.version) # 0) THEN
      out.String(v); out.String(" -> "); out.String(p.version)
    ELSE out.String(p.version)
    END;
    out.String("  "); out.String(p.desc); out.Ln
   END;
    p := p.next
  END
END List;

(** portia.Info name -- a package *)
PROCEDURE Info*;
VAR name: Name; p: Package; n: LONGINT; it: Item;
BEGIN
  IF ~Arg(name) THEN Usage("Info name"); RETURN END;
  IF ~LoadTree() THEN RETURN END;
  p := Find(name);
  IF p = NIL THEN NoPackage(name); RETURN END;
  out.String(p.category); out.Char("/"); out.String(p.name); out.Char(" "); out.String(p.version); out.String(": "); out.String(p.desc); out.Ln;
  ListItems("depends on:", p.deps); ListItems("provides:", p.provides); ListItems("conflicts with:", p.conflicts);
  ListItems("modules:", p.modules);
  IF p.remote # "" THEN
    out.String("remote: "); out.String(p.remote); out.String(", sources ");
    IF HasSources(p) THEN out.String("downloaded") ELSE out.String("not downloaded") END; out.Ln
  END;
  n := 0; it := p.files; WHILE it # NIL DO INC(n); it := it.next END;
  out.String("files: "); out.Int(n, 0); out.String(", installed: ");
  IF IsInstalled(p) THEN out.String("yes") ELSE out.String("no") END; out.Ln
END Info;

(** portia.Files name -- the files of a package on this architecture; "- " before the ones that
  are not here *)
PROCEDURE FilesCmd(p: Package);
VAR it: Item; path, dir: Name;

  PROCEDURE F(VAR s: ARRAY OF CHAR);  (* "- " before a file that is not here *)
  BEGIN IF Exists(s) THEN out.String("  ") ELSE out.String("- ") END; out.String(s); out.Ln
  END F;

BEGIN
  it := p.sources; WHILE it # NIL DO F(it.s); it := it.next END;
  it := p.modules;
  WHILE it # NIL DO
    ObjFile(it.s, FALSE, path); F(path);
    ObjFile(it.s, TRUE, path); IF Exists(path) THEN F(path) END;
    it := it.next
  END;
  it := p.files; WHILE it # NIL DO F(it.s); it := it.next END;
  IF p.remote # "" THEN  (* the downloaded copies of files installed elsewhere *)
    PackageDir(p, dir); it := p.files;
    WHILE it # NIL DO IF ~Prefix(it.s, dir) THEN COPY(dir, path); Append(path, it.r); F(path) END; it := it.next END
  END
END FilesCmd;

PROCEDURE Files*;
VAR name: Name; p: Package;
BEGIN
  IF ~Arg(name) THEN Usage("Files name"); RETURN END;
  IF ~LoadTree() THEN RETURN END;
  p := Find(name);
  IF p = NIL THEN NoPackage(name) ELSE FilesCmd(p) END
END Files;

(** portia.Owner file -- the package the file belongs to *)
PROCEDURE Owner*;
VAR file, path: Name; p: Package; it: Item; i, j: LONGINT; found: BOOLEAN;
BEGIN
  IF ~Arg(file) THEN Usage("Owner file"); RETURN END;
  IF ~LoadTree() THEN RETURN END;
  (* relative to the polpo root *)
  i := 0; WHILE (Root.path[i] # 0X) & (file[i] = Root.path[i]) DO INC(i) END;
  IF Root.path[i] # 0X THEN i := 0 END;
  IF (file[i] = ".") & (file[i+1] = "/") THEN INC(i, 2) END;
  j := 0; WHILE file[i] # 0X DO file[j] := file[i]; INC(i); INC(j) END; file[j] := 0X;
  found := FALSE; p := packages;
  WHILE p # NIL DO
    IF ~IsInstalled(p) THEN  (* installed packages first *)
    ELSIF Has(p.sources, file) OR Has(p.files, file) THEN found := TRUE
    ELSIF (p.remote # "") & Prefix(file, PkgDir) THEN
      it := p.files;  (* the downloaded copy of a file installed elsewhere *)
      WHILE it # NIL DO PackageDir(p, path); Append(path, it.r); IF path = file THEN found := TRUE END; it := it.next END
    ELSE
      it := p.modules;
      WHILE it # NIL DO
        ObjFile(it.s, FALSE, path); IF path = file THEN found := TRUE END;
        ObjFile(it.s, TRUE, path); IF path = file THEN found := TRUE END;
        it := it.next
      END
    END;
    IF found THEN out.String(file); out.String(": "); out.String(p.name); out.Ln; RETURN END;
    p := p.next
  END;
  out.String(file); out.String(": no package"); out.Ln
END Owner;

(* the packages p needs: its dependencies, transitively; virtual ones through PROVIDES *)
PROCEDURE Closure(p: Package; VAR set: Item);
VAR it: Item; q: Package;
BEGIN
  IF Has(set, p.name) THEN RETURN END;
  Add(set, p.name);
  it := p.deps;
  WHILE it # NIL DO
    q := Find(it.s);
    IF q # NIL THEN Closure(q, set)
    ELSE  (* virtual: every package providing it counts *)
      q := packages;
      WHILE q # NIL DO IF Has(q.provides, it.s) THEN Closure(q, set) END; q := q.next END
    END;
    it := it.next
  END
END Closure;

(* is module mod in one of the packages of set *)
PROCEDURE Provided(set: Item; VAR mod: ARRAY OF CHAR): BOOLEAN;
VAR q: Package;
BEGIN
  WHILE set # NIL DO
    q := Find(set.s);
    IF (q # NIL) & Has(q.modules, mod) THEN RETURN TRUE END;
    set := set.next
  END;
  RETURN FALSE
END Provided;

(** portia.Check -- every file present and every import satisfied, on this architecture *)
PROCEDURE ^Resolve(VAR name: ARRAY OF CHAR): Package;

PROCEDURE Check*;
VAR p, q: Package; it, im, set: Item; path, mod: Name; problems: LONGINT; v: ARRAY 32 OF CHAR;
BEGIN
  IF ~LoadTree() THEN RETURN END;
  problems := 0; p := packages;
  WHILE p # NIL DO
   IF IsInstalled(p) THEN
    it := p.files;
    WHILE it # NIL DO
      IF ~Exists(it.s) & ~((p.remote # "") & Prefix(it.s, PkgDir)) THEN  (* downloaded sources may be removed *)
        out.String(p.name); out.String(": missing "); out.String(it.s); out.Ln; INC(problems)
      END;
      it := it.next
    END;
    it := p.deps;
    WHILE it # NIL DO
      q := Resolve(it.s);
      IF q = NIL THEN out.String(p.name); out.String(": needs "); out.String(it.s); out.String(", not in the tree"); out.Ln; INC(problems)
      ELSIF ~IsInstalled(q) THEN out.String(p.name); out.String(": needs "); out.String(it.s); out.String(", not installed"); out.Ln; INC(problems)
      ELSIF haveDb & InstVer(q, v) & (it.v # "") & ~Versions.AtLeast(v, it.v) THEN
        out.String(p.name); out.String(": needs "); out.String(q.name); out.String(" "); out.String(it.v);
        out.String(", installed is "); out.String(v); out.Ln; INC(problems)
      END;
      it := it.next
    END;
    set := NIL; Closure(p, set);
    it := p.sources;
    WHILE it # NIL DO
      IF ~Header(it.s, mod) THEN
        IF p.remote = "" THEN out.String(p.name); out.String(": missing "); out.String(it.s); out.Ln; INC(problems) END
      ELSE
        im := imports;
        WHILE im # NIL DO
          IF (im.s # SYS) & ~Provided(set, im.s) THEN
            out.String(p.name); out.String(": "); out.String(mod); out.String(" imports ");
            out.String(im.s); out.String(", not in the package or its dependencies"); out.Ln; INC(problems)
          END;
          im := im.next
        END;
        ObjFile(mod, FALSE, path);
        IF ~Exists(path) THEN out.String(p.name); out.String(": not compiled "); out.String(path); out.Ln; INC(problems) END
      END;
      it := it.next
    END
   END;
    p := p.next
  END;
  out.Int(problems, 0); out.String(" problems ("); out.String(arch); out.String(")"); out.Ln
END Check;

(* ----- building ----- *)

(* path as it is found: in the current directory, else in the polpo root *)
PROCEDURE Local(VAR path: ARRAY OF CHAR);
VAR full: Name;
BEGIN
  IF ~Root.Exists(path) THEN Root.Join(path, full); IF Root.Exists(full) THEN COPY(full, path) END END
END Local;

PROCEDURE Compiler(VAR cmd: ARRAY OF CHAR);  (* for arch *)
BEGIN
  IF arch = "x86" THEN COPY("compiler.Compile", cmd) ELSIF arch = "arm" THEN COPY("acompiler.Compile", cmd)
  ELSIF arch = "riscv" THEN COPY("rvcompiler.Compile", cmd) ELSIF arch = "mips" THEN COPY("mcompiler.Compile", cmd)
  ELSE COPY("a7compiler.Compile", cmd)
  END
END Compiler;

(* run "Module.Command parameters", or "mv from to" *)
PROCEDURE Run(VAR line: ARRAY OF CHAR): BOOLEAN;
VAR cmd, a, b: Name; i, j: LONGINT; par: Oberon.ParList; W: Texts.Writer; res: INTEGER;
BEGIN
  i := 0; WHILE (line[i] # 0X) & (line[i] # " ") DO cmd[i] := line[i]; INC(i) END; cmd[i] := 0X;
  WHILE line[i] = " " DO INC(i) END;
  IF cmd = "mv" THEN
    j := 0; WHILE (line[i] # 0X) & (line[i] # " ") DO a[j] := line[i]; INC(i); INC(j) END; a[j] := 0X;
    WHILE line[i] = " " DO INC(i) END;
    j := 0; WHILE (line[i] # 0X) & (line[i] # " ") DO b[j] := line[i]; INC(i); INC(j) END; b[j] := 0X;
    F.Rename(a, b, res);
    IF res # 0 THEN Pre; out.String("cannot move "); out.String(a); out.String(" to "); out.String(b); out.Ln; RETURN FALSE END;
    RETURN TRUE
  END;
  NEW(par); NEW(par.text); Texts.Open(par.text, ""); par.pos := 0;
  Texts.OpenWriter(W); j := i; WHILE line[j] # 0X DO Texts.Write(W, line[j]); INC(j) END;
  Texts.Append(par.text, W.buf);
  Oberon.Call(cmd, par, FALSE, res);
  IF res # 0 THEN Pre; out.String("cannot run "); out.String(cmd); out.Ln; RETURN FALSE END;
  RETURN TRUE
END Run;

(* ----- remote packages: downloading, checking, removing ----- *)

(* make the directories of the file path full *)
PROCEDURE MakeDirs(VAR full: ARRAY OF CHAR);
VAR i, r: LONGINT; dir: Name;
BEGIN
  dir[0] := full[0]; i := 1;
  WHILE (full[i] # 0X) & (i < NameLen - 1) DO
    IF full[i] = "/" THEN dir[i] := 0X; r := Linux0.MkDir0(SYSTEM.ADR(dir), 1EDH) END;  (* 755 *)
    dir[i] := full[i]; INC(i)
  END
END MakeDirs;

(* the sum of the repository path r of p *)
PROCEDURE SumOf(p: Package; VAR r, sum: ARRAY OF CHAR): BOOLEAN;
VAR it: Item;
BEGIN
  it := p.sums; WHILE (it # NIL) & (it.s # r) DO it := it.next END;
  IF it = NIL THEN sum[0] := 0X; RETURN FALSE END;
  COPY(it.r, sum); RETURN TRUE
END SumOf;

(* the downloader of url: fetch.Get, gemini.Get or spartan.Get *)
PROCEDURE Downloader(VAR url, cmd: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF Prefix(url, "https://") OR Prefix(url, "http://") THEN COPY("fetch.Get", cmd)
  ELSIF Prefix(url, "gemini://") THEN COPY("gemini.Get", cmd)
  ELSIF Prefix(url, "spartan://") THEN COPY("spartan.Get", cmd)
  ELSE Pre; out.String("cannot download "); out.String(url); out.String(" (https, http, gemini or spartan)"); out.Ln; RETURN FALSE
  END;
  RETURN TRUE
END Downloader;

(* download the repository path r of p to src/pkg/<name>/r, unless it is there with its sum *)
PROCEDURE Download(p: Package; VAR r: ARRAY OF CHAR): BOOLEAN;
VAR rel, full, part, sum, cmd: Name; url, line: ARRAY 1024 OF CHAR; res: INTEGER;
BEGIN
  IF ~SumOf(p, r, sum) THEN
    Pre; out.String(p.name); out.String(": no sum for "); out.String(r); out.String(" in [SUMS]"); out.Ln; RETURN FALSE
  END;
  PackageDir(p, rel); Append(rel, r); Root.Join(rel, full);
  IF Root.Exists(full) & Checksums.Matches(sum, full) THEN RETURN TRUE END;  (* downloaded before *)
  COPY(p.remote, url); Append(url, "/"); Append(url, r);
  IF ~Downloader(url, cmd) THEN RETURN FALSE END;
  COPY(full, part); Append(part, ".part"); MakeDirs(full);
  COPY(cmd, line); Append(line, " "); Append(line, url); Append(line, " "); Append(line, part);
  Pre; out.String("downloading "); out.String(url); out.Ln;
  IF ~Run(line) THEN Pre; out.String("is the package "); out.String(cmd); out.String(" installed?"); out.Ln; RETURN FALSE END;
  IF ~Root.Exists(part) THEN Pre; out.String(url); out.String(" was not downloaded"); out.Ln; RETURN FALSE END;
  IF ~Checksums.Matches(sum, part) THEN
    Pre; out.String(r); out.String(" does not have the sum of [SUMS], refused"); out.Ln;
    F.Delete(part, res); RETURN FALSE
  END;
  F.Rename(part, full, res);
  IF res # 0 THEN Pre; out.String("cannot move "); out.String(part); out.Ln; RETURN FALSE END;
  RETURN TRUE
END Download;

(* copy the file from to the file to (paths as they are opened) *)
PROCEDURE CopyFile(VAR from, to: ARRAY OF CHAR): BOOLEAN;
VAR f, g: F.File; R, W: F.Rider; c: CHAR;
BEGIN
  f := F.Old(from); IF f = NIL THEN RETURN FALSE END;
  MakeDirs(to); g := F.New(to); IF g = NIL THEN F.ReleaseRead(f); RETURN FALSE END;
  F.Set(R, f, 0); F.Set(W, g, 0);
  F.Read(R, c); WHILE ~R.eof DO F.Write(W, c); F.Read(R, c) END;
  F.ReleaseRead(f); F.Register(g);
  RETURN TRUE
END CopyFile;

(* download the files of the remote package p; install: copy the files with a destination there *)
PROCEDURE FetchPackage(p: Package; install: BOOLEAN): BOOLEAN;
VAR it: Item; dir, from, to: Name;
BEGIN
  PackageDir(p, dir);
  it := p.sources; WHILE it # NIL DO IF ~Download(p, it.r) THEN RETURN FALSE END; it := it.next END;
  it := p.files;
  WHILE it # NIL DO
    IF ~Download(p, it.r) THEN RETURN FALSE END;
    IF install & ~Prefix(it.s, dir) THEN
      COPY(dir, from); Append(from, it.r); Root.Join(from, from); Root.Join(it.s, to);
      IF ~CopyFile(from, to) THEN Pre; out.String("cannot install "); out.String(it.s); out.Ln; RETURN FALSE END
    END;
    it := it.next
  END;
  RETURN TRUE
END FetchPackage;

(* delete the file rel (relative to the root); then its directories that became empty, up to
   src/pkg/ when rel is in there *)
PROCEDURE DeleteFile(VAR rel: ARRAY OF CHAR);
VAR full: Name; res: INTEGER; i, r: LONGINT;
BEGIN
  Root.Join(rel, full);
  IF Root.Exists(full) THEN F.Delete(full, res) END;
  IF Prefix(rel, PkgDir) THEN
    i := Len(full);
    LOOP
      WHILE (i > 0) & (full[i] # "/") DO DEC(i) END;
      IF i <= 0 THEN EXIT END;
      full[i] := 0X;
      IF Len(full) < Len(Root.path) + PkgDirLen THEN EXIT END;  (* src/pkg/ itself stays *)
      r := Linux0.UnLinkat0(Linux0.ATFDCWD, SYSTEM.ADR(full), ATREMOVEDIR);
      IF r # 0 THEN EXIT END  (* not empty *)
    END
  END
END DeleteFile;

(* delete the downloaded files of p, in src/pkg/<name>/ *)
PROCEDURE DeleteSources(p: Package);
VAR it: Item; dir, rel: Name;
BEGIN
  PackageDir(p, dir);
  it := p.sources; WHILE it # NIL DO DeleteFile(it.s); it := it.next END;
  it := p.files; WHILE it # NIL DO COPY(dir, rel); Append(rel, it.r); DeleteFile(rel); it := it.next END
END DeleteSources;

(* delete the files of the remote package p copied out of src/pkg/<name>/, but those that
   the package keep (not NIL) installs too *)
PROCEDURE DeleteData(p, keep: Package);
VAR it: Item; dir: Name;
BEGIN
  PackageDir(p, dir); it := p.files;
  WHILE it # NIL DO
    IF ~Prefix(it.s, dir) & ((keep = NIL) OR ~Has(keep.files, it.s)) THEN DeleteFile(it.s) END;
    it := it.next
  END
END DeleteData;

(* ----- tests ----- *)

PROCEDURE CollectEntry(name: ARRAY OF CHAR; time, date, size: LONGINT; attr: SET; VAR continue: BOOLEAN);
BEGIN
  Add(entries, name);
  IF FATFiles.SubDir IN attr THEN Add(entries, "/") END;  (* a directory: "/" follows its name *)
  continue := TRUE
END CollectEntry;

(* delete the directory dir (a full path, without "/" at the end) and everything in it *)
PROCEDURE DeleteTree(VAR dir: ARRAY OF CHAR);
VAR list, it: Item; path: Name; res: LONGINT; r: INTEGER;
BEGIN
  entries := NIL; COPY(dir, path); Append(path, "/"); FATFiles.Enumerate(path, CollectEntry, res);
  list := entries; entries := NIL; it := list;
  WHILE it # NIL DO
    COPY(dir, path); Append(path, "/"); Append(path, it.s);
    IF (it.next # NIL) & (it.next.s = "/") THEN DeleteTree(path); it := it.next
    ELSE F.Delete(path, r)
    END;
    it := it.next
  END;
  res := Linux0.UnLinkat0(Linux0.ATFDCWD, SYSTEM.ADR(dir), ATREMOVEDIR)
END DeleteTree;

(* the line with $compile replaced by the compiler of the architecture ("compiler.Compile /s") *)
PROCEDURE Expand(VAR line, res: ARRAY OF CHAR);
VAR i, j, k: LONGINT; cmd: Name; pat: ARRAY 9 OF CHAR;
BEGIN
  pat := "$compile"; i := 0; j := 0;
  WHILE (line[i] # 0X) & (j < LEN(res) - 1) DO
    k := 0; WHILE (k < 8) & (line[i+k] = pat[k]) DO INC(k) END;
    IF k = 8 THEN
      Compiler(cmd); Append(cmd, " /s"); res[j] := 0X; Append(res, cmd); j := Len(res); INC(i, 8)
    ELSE res[j] := line[i]; INC(i); INC(j)
    END
  END;
  res[j] := 0X
END Expand;

(* run the commands of the tests of p in dir, in a copy of this process, its output to log *)
PROCEDURE RunTests(p: Package; VAR dir, log: ARRAY OF CHAR): BOOLEAN;
VAR pid, r, st: LONGINT; it: Item; line: ARRAY 1024 OF CHAR; null: ARRAY 12 OF CHAR; ok: BOOLEAN;
BEGIN
  pid := Linux0.Fork0();
  IF pid < 0 THEN Pre; out.String("cannot fork"); out.Ln; RETURN FALSE END;
  IF pid = 0 THEN  (* the child: in dir, no input, the output to log *)
    (* the files of the parent go (the X11 display of a test needs a descriptor below 32), but
       3, Kernel.Log, opened first by Kernel; Files opens names relative to its directory *)
    r := 4; WHILE r < 1024 DO pid := Linux0.Close0(r); INC(r) END;
    r := Linux0.ChDir0(SYSTEM.ADR(dir)); F.SetSYS(dir); F.SetWRK(dir);
    null := "/dev/null"; r := Linux0.Close0(0); r := Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR(null), Linux0.ORDonly, 0);
    r := Linux0.Close0(1);
    r := Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR(log), Linux0.OWRonly + Linux0.OCREAT + Linux0.OTRUNC + Linux0.OAPPEND, 1A4H);
    r := Linux0.Close0(2);
    r := Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR(log), Linux0.OWRonly + Linux0.OAPPEND, 0);
    ok := TRUE; it := p.tcmds;
    WHILE ok & (it # NIL) DO
      Expand(it.s, line); out.String("> "); out.String(line); out.Ln;
      ok := Run(line); it := it.next
    END;
    IF ok THEN out.String(EndMark); out.Ln; Linux0.Exit0(0) ELSE Linux0.Exit0(1) END
  END;
  st := 0; r := Linux0.Waitpid0(pid, SYSTEM.ADR(st), 0);
  RETURN (r = pid) & (st = 0)
END RunTests;

(* is t a line of buf (blanks around ignored), or (part) in buf *)
PROCEDURE Contains(VAR buf: ARRAY OF CHAR; VAR t: ARRAY OF CHAR; line: BOOLEAN): BOOLEAN;
VAR i, j, k, n: LONGINT;
BEGIN
  n := Len(t); i := 0;
  WHILE buf[i] # 0X DO
    IF line THEN
      WHILE (buf[i] = " ") OR (buf[i] = 09X) DO INC(i) END;
      k := 0; WHILE (k < n) & (buf[i+k] = t[k]) DO INC(k) END;
      IF k = n THEN
        j := i + n; WHILE (buf[j] = " ") OR (buf[j] = 09X) OR (buf[j] = 0DX) DO INC(j) END;
        IF (buf[j] = 0AX) OR (buf[j] = 0X) THEN RETURN TRUE END
      END;
      WHILE (buf[i] # 0X) & (buf[i] # 0AX) DO INC(i) END;
      IF buf[i] = 0AX THEN INC(i) END
    ELSE
      k := 0; WHILE (k < n) & (buf[i+k] = t[k]) DO INC(k) END;
      IF k = n THEN RETURN TRUE END;
      INC(i)
    END
  END;
  RETURN FALSE
END Contains;

(* test the installed package p: copy the files of [TESTS] copy ("path" or "path=name"; of a
   remote package from src/pkg/<name>/) to a new directory, run the commands there ($compile:
   the compiler of this architecture; objects stay in the directory's obj/<arch>/); every line
   of ok must be a line of the output, no text of bad in it. The directory is deleted when the
   test passes *)
PROCEDURE TestPackage(p: Package): BOOLEAN;
VAR dir, path, from, to, name, log: Name; it: Item; buf: Buf; i, k, r: LONGINT; ok: BOOLEAN;
BEGIN
  IF p.tcmds = NIL THEN Pre; out.String(p.name); out.String(" has no tests"); out.Ln; RETURN TRUE END;
  Kernel.GetConfig("DISPLAY", dir);
  IF p.tdisplay & (dir = "") THEN
    Pre; out.String(p.name); out.String(": tests skipped, they need the desktop (set DISPLAY)"); out.Ln; RETURN TRUE
  END;
  Kernel.GetConfig("TMPDIR", dir); IF dir = "" THEN dir := "/tmp" END;
  Append(dir, "/portia-test-"); Append(dir, p.name); Append(dir, "-"); Append(dir, arch);
  DeleteTree(dir);
  COPY(dir, path); Append(path, "/obj/"); Append(path, arch); Append(path, "/x"); MakeDirs(path);
  it := p.tcopy;
  WHILE it # NIL DO
    i := 0; k := -1; WHILE it.s[i] # 0X DO IF it.s[i] = "=" THEN k := i END; INC(i) END;
    COPY(it.s, from); IF k >= 0 THEN from[k] := 0X END;
    IF k >= 0 THEN i := 0; INC(k); WHILE it.s[k] # 0X DO name[i] := it.s[k]; INC(i); INC(k) END; name[i] := 0X
    ELSE i := Len(from); WHILE (i > 0) & (from[i-1] # "/") DO DEC(i) END; k := 0;
      WHILE from[i] # 0X DO name[k] := from[i]; INC(i); INC(k) END; name[k] := 0X
    END;
    IF p.remote # "" THEN PackageDir(p, path); Append(path, from); COPY(path, from) END;
    Root.Join(from, path); COPY(dir, to); Append(to, "/"); Append(to, name);
    IF ~CopyFile(path, to) THEN Pre; out.String("no "); out.String(from); out.String(" for the tests of "); out.String(p.name); out.Ln; RETURN FALSE END;
    it := it.next
  END;
  COPY(dir, log); Append(log, "/test.log");
  Pre; out.String("testing "); out.String(p.name); out.String(" in "); out.String(dir); out.Ln;
  ok := RunTests(p, dir, log);
  IF ReadFile(log, buf) THEN
    i := 0;  (* the output, indented *)
    WHILE buf[i] # 0X DO
      out.String("  | "); WHILE (buf[i] # 0X) & (buf[i] # 0AX) DO out.Char(buf[i]); INC(i) END; out.Ln;
      IF buf[i] = 0AX THEN INC(i) END
    END;
    COPY(EndMark, name);
    IF ~Contains(buf^, name, TRUE) THEN Pre; out.String("the tests stopped before their end"); out.Ln; ok := FALSE END;
    it := p.tok;
    WHILE it # NIL DO
      IF ~Contains(buf^, it.s, TRUE) THEN Pre; out.String("expected "); out.String(it.s); out.Ln; ok := FALSE END;
      it := it.next
    END;
    it := p.tbad;
    WHILE it # NIL DO
      IF Contains(buf^, it.s, FALSE) THEN Pre; out.String("refused "); out.String(it.s); out.Ln; ok := FALSE END;
      it := it.next
    END
  ELSE Pre; out.String("no output of the tests"); out.Ln; ok := FALSE
  END;
  IF ok THEN DeleteTree(dir); Pre; out.String(p.name); out.String(" passed its tests"); out.Ln
  ELSE Pre; out.String(p.name); out.String(" failed its tests, see "); out.String(dir); out.Ln
  END;
  RETURN ok
END TestPackage;

(* the date and time of the file path (found as Local finds it); FALSE if there is none *)
PROCEDURE FileDate(VAR path: ARRAY OF CHAR; VAR d, t: LONGINT): BOOLEAN;
VAR f: F.File;
BEGIN
  Local(path); f := F.Old(path); IF f = NIL THEN RETURN FALSE END;
  F.GetDate(f, t, d); F.ReleaseRead(f); RETURN TRUE
END FileDate;


(* a checksum of the interface of module mod: its symbol file (on x86 the symbol part of the
   object file when there is no .Sym: tag, format, size, then the symbols); len 0 if there is none *)
PROCEDURE SymKey(VAR mod: ARRAY OF CHAR; VAR len, s1, s2: LONGINT);
VAR path: Name; f: F.File; R: F.Rider; c, tag: CHAR; n: LONGINT; inObj: BOOLEAN;
BEGIN
  len := 0; s1 := 0; s2 := 0;
  ObjFile(mod, TRUE, path); Local(path);  (* the .Sym; on x86 the .Obj when it has none (compiled with /i) *)
  f := F.Old(path); inObj := FALSE;
  IF (f = NIL) & (arch = "x86") THEN ObjFile(mod, FALSE, path); Local(path); f := F.Old(path); inObj := TRUE END;
  IF f = NIL THEN RETURN END;
  F.Set(R, f, 0);
  IF inObj THEN
    F.Read(R, tag); F.Read(R, c);
    IF tag # 0BBX THEN F.ReleaseRead(f); len := -1; RETURN END;
    F.ReadNum(R, n)
  ELSE n := F.Length(f)
  END;
  WHILE (len < n) & ~R.eof DO
    F.Read(R, c); s1 := (s1 * 31 + ORD(c)) MOD 999983; s2 := (s2 + ORD(c) * (len MOD 97 + 1)) MOD 1000003; INC(len)
  END;
  F.ReleaseRead(f)
END SymKey;

(* the interfaces the modules of a remote package p were compiled against, for Upgrade:
   src/pkg/<name>/portia-<arch>.keys, a line "Module len s1 s2" (SymKey) for each import *)
PROCEDURE KeysFile(p: Package; VAR full: ARRAY OF CHAR);
VAR rel: Name;
BEGIN
  PackageDir(p, rel); Append(rel, "portia-"); Append(rel, arch); Append(rel, ".keys"); Root.Join(rel, full)
END KeysFile;

PROCEDURE SaveKeys(p: Package);
VAR it, im, mods: Item; mod, full: Name; f: F.File; R: F.Rider; l, a, b: LONGINT;

  PROCEDURE W(s: ARRAY OF CHAR);
  VAR i: LONGINT;
  BEGIN i := 0; WHILE s[i] # 0X DO F.Write(R, s[i]); INC(i) END
  END W;

  PROCEDURE N(x: LONGINT);
  VAR d: ARRAY 12 OF CHAR; i: LONGINT;
  BEGIN
    F.Write(R, " "); IF x < 0 THEN F.Write(R, "-"); x := -x END;
    i := 0; REPEAT d[i] := CHR(ORD("0") + x MOD 10); x := x DIV 10; INC(i) UNTIL x = 0;
    WHILE i > 0 DO DEC(i); F.Write(R, d[i]) END
  END N;

BEGIN
  mods := NIL; it := p.sources;
  WHILE it # NIL DO
    IF Header(it.s, mod) THEN
      im := imports;
      WHILE im # NIL DO IF (im.s # SYS) & ~Has(mods, im.s) THEN Add(mods, im.s) END; im := im.next END
    END;
    it := it.next
  END;
  KeysFile(p, full); f := F.New(full); IF f = NIL THEN RETURN END;
  F.Set(R, f, 0); it := mods;
  WHILE it # NIL DO SymKey(it.s, l, a, b); W(it.s); N(l); N(a); N(b); F.Write(R, 0AX); it := it.next END;
  F.Register(f)
END SaveKeys;

(* a module of p was compiled before the interface of a module it imports changed, as after a
   git pull of polpo that changed a base interface; why: that import. The keys recorded when p
   was compiled (SaveKeys) are compared with the interfaces now; for a package compiled before
   portia recorded them, an import whose symbol file (on x86 its object, when it has no .Sym)
   is newer than the object of the module counts *)
PROCEDURE Stale(p: Package; VAR why: ARRAY OF CHAR): BOOLEAN;
VAR it, im: Item; mod, obj, sym, full: Name; od, ot, sd, st, i, j, k, l, a, b, v: LONGINT;
  key: ARRAY 3 OF LONGINT; found, neg: BOOLEAN; buf: Buf;
BEGIN
  KeysFile(p, full);
  IF ReadFile(full, buf) THEN
    i := 0;
    WHILE buf[i] # 0X DO
      j := 0; WHILE buf[i] > " " DO IF j < NameLen - 1 THEN mod[j] := buf[i]; INC(j) END; INC(i) END; mod[j] := 0X;
      k := 0;
      WHILE k < 3 DO
        WHILE buf[i] = " " DO INC(i) END;
        neg := buf[i] = "-"; IF neg THEN INC(i) END;
        v := 0; WHILE (buf[i] >= "0") & (buf[i] <= "9") DO v := v * 10 + ORD(buf[i]) - ORD("0"); INC(i) END;
        IF neg THEN v := -v END; key[k] := v; INC(k)
      END;
      WHILE (buf[i] # 0X) & (buf[i] # 0AX) DO INC(i) END;
      IF buf[i] = 0AX THEN INC(i) END;
      IF mod[0] # 0X THEN
        SymKey(mod, l, a, b);
        IF (l # key[0]) OR (a # key[1]) OR (b # key[2]) THEN COPY(mod, why); RETURN TRUE END
      END
    END;
    RETURN FALSE
  END;
  it := p.sources;
  WHILE it # NIL DO
    IF Header(it.s, mod) THEN
      ObjFile(mod, FALSE, obj);
      IF FileDate(obj, od, ot) THEN
        im := imports;
        WHILE im # NIL DO
          IF im.s # SYS THEN
            ObjFile(im.s, TRUE, sym); found := FileDate(sym, sd, st);
            IF ~found & (arch = "x86") THEN ObjFile(im.s, FALSE, sym); found := FileDate(sym, sd, st) END;
            IF found & ((sd > od) OR (sd = od) & (st > ot)) THEN COPY(im.s, why); RETURN TRUE END
          END;
          im := im.next
        END
      END
    END;
    it := it.next
  END;
  RETURN FALSE
END Stale;

(* compile the sources of p, each after the modules of p it imports; changed: the interface
   of a module that existed before changed, its importers must be recompiled *)
PROCEDURE BuildPackage(p: Package; VAR changed: BOOLEAN): BOOLEAN;
CONST Max = 256;
VAR src, modn: ARRAY Max OF Item; imp: ARRAY Max OF Item; done: ARRAY Max OF BOOLEAN;
  n, i, k, left: LONGINT; it: Item; ready, progress, had: BOOLEAN; mod, cmd, line, obj, old: Name; res: INTEGER;
  l0, a0, b0, l1, a1, b1: LONGINT;
BEGIN
  changed := FALSE; n := 0; it := p.sources;
  WHILE (it # NIL) & (n < Max) DO
    src[n] := it; IF Header(it.s, mod) THEN END;
    NEW(modn[n]); COPY(mod, modn[n].s); imp[n] := imports; done[n] := FALSE; INC(n); it := it.next
  END;
  Compiler(cmd); left := n;
  WHILE left > 0 DO
    progress := FALSE; i := 0;
    WHILE i < n DO
      IF ~done[i] THEN
        ready := TRUE; it := imp[i];
        WHILE it # NIL DO  (* an import from this package not compiled yet *)
          k := 0; WHILE k < n DO IF ~done[k] & (k # i) & (modn[k].s = it.s) THEN ready := FALSE END; INC(k) END;
          it := it.next
        END;
        IF ready THEN
          (* the old object aside: a new one must appear; back if the compilation fails *)
          SymKey(modn[i].s, l0, a0, b0);
          Root.Obj(arch, obj); Append(obj, modn[i].s); Append(obj, ".Obj");  (* where the compiler writes it *)
          COPY(obj, old); Append(old, ".old");
          had := Root.Exists(obj); IF had THEN F.Rename(obj, old, res) END;
          COPY(cmd, line); Append(line, " /s"); Append(line, src[i].flags); Append(line, " "); Append(line, src[i].s);
          IF ~Run(line) OR ~Root.Exists(obj) THEN
            IF had THEN F.Rename(old, obj, res) END;
            Pre; out.String(src[i].s); out.String(" did not compile"); out.Ln; RETURN FALSE
          END;
          IF had THEN F.Delete(old, res) END;
          SymKey(modn[i].s, l1, a1, b1);
          IF (l0 > 0) & ((l1 # l0) OR (a1 # a0) OR (b1 # b0)) THEN
            Pre; out.String("the interface of "); out.String(modn[i].s); out.String(" changed"); out.Ln; changed := TRUE;
            IF ~Has(changedMods, modn[i].s) THEN Add(changedMods, modn[i].s) END
          END;
          done[i] := TRUE; DEC(left); progress := TRUE
        END
      END;
      INC(i)
    END;
    IF ~progress THEN Pre; out.String("modules of "); out.String(p.name); out.String(" import each other in a cycle"); out.Ln; RETURN FALSE END
  END;
  IF p.remote # "" THEN SaveKeys(p) END;
  RETURN TRUE
END BuildPackage;

(* the packages to build in order, dependencies first; virtual ones: the installed provider *)
PROCEDURE Order(p: Package; VAR list: Item);
VAR it: Item; q, r: Package;
BEGIN
  IF Has(list, p.name) THEN RETURN END;
  Add(list, "?");  (* placeholder against cycles, replaced below *)
  it := p.deps;
  WHILE it # NIL DO
    q := Find(it.s);
    IF q = NIL THEN  (* virtual *)
      r := packages; q := NIL;
      WHILE r # NIL DO IF Has(r.provides, it.s) & ((q = NIL) OR IsInstalled(r)) THEN q := r END; r := r.next END
    END;
    IF q # NIL THEN Order(q, list) END;
    it := it.next
  END;
  Drop(list, "?"); IF ~Has(list, p.name) THEN Add(list, p.name) END
END Order;

PROCEDURE SetArch(a: ARRAY OF CHAR);
BEGIN
  IF a # arch THEN COPY(a, arch); packages := NIL END
END SetArch;

(** portia.Record -- record the packages whose files are here as installed; of alternatives
  sharing files (display-x11, display-sixel) the first; see portia.Mark *)
(* the record from the files present; of alternatives the first *)
PROCEDURE RecordAll(verbose: BOOLEAN);
VAR p: Package; it: Item; skip: BOOLEAN;
BEGIN
  installed := NIL; p := packages;
  WHILE p # NIL DO
    IF Installed(p) THEN
      skip := FALSE; it := p.conflicts;
      WHILE it # NIL DO IF Has(installed, it.s) THEN skip := TRUE END; it := it.next END;
      IF skip THEN
        IF verbose THEN
          out.String("not recorded "); out.String(p.name); out.String(", it conflicts with a recorded package (portia.Mark "); out.String(p.name); out.String(" switches)"); out.Ln
        END
      ELSE SetInstalled(p.name, p.version)
      END
    END;
    p := p.next
  END;
  SaveDb
END RecordAll;

PROCEDURE Record*;
BEGIN
  IF ~LoadTree() THEN RETURN END;
  RecordAll(TRUE); List
END Record;

(** portia.Mark name -- record the package as installed; its conflicts are unmarked *)
PROCEDURE Mark*;
VAR name: Name; p: Package; it: Item;
BEGIN
  IF ~Arg(name) THEN Usage("Mark name"); RETURN END;
  IF ~LoadTree() THEN RETURN END;
  p := Find(name);
  IF p = NIL THEN NoPackage(name); RETURN END;
  it := p.conflicts; WHILE it # NIL DO Drop(installed, it.s); it := it.next END;
  SetInstalled(name, p.version);
  SaveDb; out.String(name); out.String(" marked installed"); out.Ln
END Mark;

(** portia.Unmark name -- record the package as not installed (the files stay) *)
PROCEDURE Unmark*;
VAR name: Name;
BEGIN
  IF ~Arg(name) THEN Usage("Unmark name"); RETURN END;
  IF ~LoadTree() THEN RETURN END;
  Drop(installed, name); SaveDb; out.String(name); out.String(" unmarked"); out.Ln
END Unmark;

(* ----- installing and removing ----- *)

(* delete the objects of the modules of p that no other installed package has *)
(* (keep, if not NIL: the package replacing p; the objects of its modules stay, so that its build
   sees whether their interfaces change and recompiles the importers) *)
PROCEDURE DeleteObjects(p, keep: Package);
VAR it: Item; q: Package; shared: BOOLEAN; path, full: Name; res: INTEGER; i: INTEGER;
BEGIN
  it := p.modules;
  WHILE it # NIL DO
    shared := (keep # NIL) & Has(keep.modules, it.s); q := packages;
    WHILE q # NIL DO IF (q # p) & IsInstalled(q) & Has(q.modules, it.s) THEN shared := TRUE END; q := q.next END;
    IF ~shared THEN
      i := 0;
      WHILE i < 2 DO
        ObjFile(it.s, i = 1, path);
        IF Root.Exists(path) THEN F.Delete(path, res)
        ELSE Root.Join(path, full); IF Root.Exists(full) THEN F.Delete(full, res) END
        END;
        INC(i)
      END
    END;
    it := it.next
  END
END DeleteObjects;

(* the installed packages that need p: depend on it, or on something only p provides *)
PROCEDURE Needers(p: Package; VAR list: Item);
VAR q, r: Package; it: Item; other: BOOLEAN;
BEGIN
  q := packages;
  WHILE q # NIL DO
    IF (q # p) & IsInstalled(q) THEN
      it := q.deps;
      WHILE it # NIL DO
        IF it.s = p.name THEN Add(list, q.name)
        ELSIF Has(p.provides, it.s) THEN
          other := FALSE; r := packages;
          WHILE r # NIL DO IF (r # p) & IsInstalled(r) & Has(r.provides, it.s) THEN other := TRUE END; r := r.next END;
          IF ~other THEN Add(list, q.name) END
        END;
        it := it.next
      END
    END;
    q := q.next
  END
END Needers;

(* the installed packages that need p, directly or through others, added to list *)
PROCEDURE AllNeeders(p: Package; VAR list: Item);
VAR direct, it: Item; q: Package;
BEGIN
  direct := NIL; Needers(p, direct); it := direct;
  WHILE it # NIL DO
    IF ~Has(list, it.s) THEN Add(list, it.s); q := Find(it.s); IF q # NIL THEN AllNeeders(q, list) END END;
    it := it.next
  END
END AllNeeders;

(* the arguments: /arch and package names *)
PROCEDURE Args(VAR names: Item);
VAR A: Texts.Reader; name: Name; n: LONGINT;
BEGIN
  Texts.OpenArgs(A); names := NIL; SetArch(hostArch); assumeYes := FALSE; delObj := TRUE; delSrc := FALSE; doTest := FALSE; withDeps := FALSE;
  WHILE Texts.Arg(A, name) DO
    IF (name = "/y") OR (name = "/Y") THEN assumeYes := TRUE
    ELSIF name = "/t" THEN doTest := TRUE
    ELSIF name = "/deps" THEN withDeps := TRUE
    ELSIF name = "/src" THEN delObj := FALSE; delSrc := TRUE
    ELSIF name = "/all" THEN delObj := TRUE; delSrc := TRUE
    ELSIF name[0] = "/" THEN
      n := 0; WHILE name[n+1] # 0X DO name[n] := name[n+1]; INC(n) END; name[n] := 0X; SetArch(name)
    ELSE Add(names, name)
    END
  END
END Args;

(* ask to proceed with n packages; /y does not ask, without a terminal /y is needed *)
PROCEDURE Confirm(n: LONGINT; what: ARRAY OF CHAR): BOOLEAN;
VAR t: termios.Termios; c, answer: CHAR; r: LONGINT; echo: BOOLEAN;
BEGIN
  IF assumeYes THEN RETURN TRUE END;
  IF termios.Get(0, t) # 0 THEN
    Pre; out.String("not asking without a terminal; add /y to proceed"); out.Ln; RETURN FALSE
  END;
  echo := ~(termios.ECHO IN t.lflag);  (* the shell may have turned echo off *)
  out.String("Proceed "); out.String(what); out.String(" "); out.Int(n, 0);
  IF n = 1 THEN out.String(" package? [Y/n] ") ELSE out.String(" packages? [Y/n] ") END;
  answer := 0X;
  LOOP
    r := Linux0.Read0(0, SYSTEM.ADR(c), 1);
    IF r <= 0 THEN answer := "n"; EXIT END;
    IF (c = 0DX) OR (c = 0AX) THEN EXIT END;
    IF c = 3X THEN answer := "n"; EXIT END;  (* ^C *)
    IF c > " " THEN IF answer = 0X THEN answer := c END; IF echo THEN out.Char(c) END END
  END;
  IF echo THEN out.Ln END;
  RETURN (answer = 0X) OR (answer = "y") OR (answer = "Y")
END Confirm;

(* ----- versions: what to build ----- *)

(* the package for a dependency: itself, or for a virtual one the installed provider (else
   the first one in the tree) *)
PROCEDURE Resolve(VAR name: ARRAY OF CHAR): Package;
VAR q, r: Package;
BEGIN
  q := Find(name);
  IF q = NIL THEN
    r := packages;
    WHILE r # NIL DO IF Has(r.provides, name) & ((q = NIL) OR IsInstalled(r)) THEN q := r END; r := r.next END
  END;
  RETURN q
END Resolve;

(* add to set the dependencies of p that are missing or older than p needs, recursively *)
PROCEDURE AddNeeded(p: Package; VAR set: Item): BOOLEAN;
VAR it: Item; q: Package; v: ARRAY 32 OF CHAR;
BEGIN
  it := p.deps;
  WHILE it # NIL DO
    q := Resolve(it.s);
    IF q = NIL THEN Pre; out.String(p.name); out.String(" needs "); out.String(it.s); out.String(", not in the tree"); out.Ln; RETURN FALSE END;
    IF (it.v # "") & ~Versions.AtLeast(q.version, it.v) THEN
      Pre; out.String(p.name); out.String(" needs "); out.String(q.name); out.String(" "); out.String(it.v);
      out.String(", the tree has "); out.String(q.version); out.Ln; RETURN FALSE
    END;
    IF ~Has(set, q.name) & (~IsInstalled(q) OR haveDb & InstVer(q, v) & (it.v # "") & ~Versions.AtLeast(v, it.v)) THEN
      Add(set, q.name);
      IF ~AddNeeded(q, set) THEN RETURN FALSE END
    END;
    it := it.next
  END;
  RETURN TRUE
END AddNeeded;

(* p and q cannot be installed together: one of them says so *)
PROCEDURE Conflict(p, q: Package): BOOLEAN;
BEGIN RETURN (p # q) & (Has(p.conflicts, q.name) OR Has(q.conflicts, p.name))
END Conflict;

(* build the packages of set in dependency order, link, record them; replace conflicts *)
PROCEDURE Execute(set: Item; verb: ARRAY OF CHAR);
VAR order, it, c, cf, d, im: Item; p, q: Package; ok, changed: BOOLEAN; line, mod: Name; n: LONGINT; v: ARRAY 32 OF CHAR;
BEGIN
  order := NIL; it := set; WHILE it # NIL DO p := Find(it.s); Order(p, order); it := it.next END;
  q := packages; WHILE q # NIL DO IF IsInstalled(q) THEN Order(q, order) END; q := q.next END;  (* for importers *)
  Pre; out.String(verb); out.String(" for "); out.String(arch); out.String(":"); out.Ln;
  it := order; n := 0;
  WHILE it # NIL DO
    IF Has(set, it.s) THEN
      p := Find(it.s); out.String("  "); out.String(p.name); out.Char(" "); out.String(p.version); out.String("  ");
      c := set; WHILE c.s # p.name DO c := c.next END;
      IF c.v # "" THEN out.String("recompiled for the new "); out.String(c.v)
      ELSIF ~IsInstalled(p) THEN out.String("new")
      ELSIF InstVer(p, v) & (Versions.Compare(v, p.version) # 0) THEN out.String("upgrade from "); out.String(v)
      ELSE out.String("rebuilt")
      END;
      q := packages;
      WHILE q # NIL DO
        IF Conflict(p, q) & IsInstalled(q) THEN out.String(", replaces "); out.String(q.name) END;
        q := q.next
      END;
      out.Ln; INC(n)
    END;
    it := it.next
  END;
  out.String("  (installed packages importing an interface that changes are recompiled too)"); out.Ln;
  IF ~Confirm(n, verb) THEN Pre; out.String("nothing done"); out.Ln; RETURN END;
  n := 0; changedMods := NIL;
  ok := TRUE; it := order;
  WHILE ok & (it # NIL) DO
    p := Find(it.s);
    IF Has(set, p.name) THEN
      (* the installed packages p conflicts with go first: they may have modules of the same
         names, and must not be recompiled as importers of the new interfaces *)
      q := packages;
      WHILE q # NIL DO
        IF Conflict(p, q) & IsInstalled(q) THEN
          Drop(installed, q.name); DeleteObjects(q, p); IF q.remote # "" THEN DeleteData(q, p) END;
          Pre; out.String("replacing "); out.String(q.name); out.Ln; SaveDb
        END;
        q := q.next
      END;
      IF p.remote # "" THEN ok := FetchPackage(p, TRUE) END;
      IF ok THEN ok := BuildPackage(p, changed) END; INC(n);
      IF ok & changed THEN  (* packages importing a changed module are recompiled when their turn comes *)
        q := packages;
        WHILE q # NIL DO
          IF IsInstalled(q) & ~Has(set, q.name) THEN
            d := q.sources;
            WHILE (d # NIL) & ~Has(set, q.name) DO
              IF Header(d.s, mod) THEN
                im := imports;
                WHILE (im # NIL) & ~Has(changedMods, im.s) DO im := im.next END;
                IF im # NIL THEN
                  Add(set, q.name); Pre; out.String("recompiling "); out.String(q.name);
                  out.String(", "); out.String(mod); out.String(" imports "); out.String(im.s); out.Ln
                END
              END;
              d := d.next
            END
          END;
          q := q.next
        END
      END;
      c := p.build; WHILE ok & (c # NIL) DO COPY(c.s, line); ok := Run(line); c := c.next END;
      IF ok THEN
        SetInstalled(p.name, p.version); SaveDb;
        IF doTest & (arch = hostArch) THEN ok := TestPackage(p) END
      END
    END;
    it := it.next
  END;
  IF ok THEN Pre; out.String("done, "); out.Int(n, 0); out.String(" packages") ELSE Pre; out.String("stopped") END; out.Ln
END Execute;

PROCEDURE Start(VAR names: Item): BOOLEAN;  (* arguments, the tree and the record *)
BEGIN
  Args(names);
  IF ~LoadTree() THEN SetArch(hostArch); RETURN FALSE END;
  IF ~haveDb THEN RecordAll(FALSE) END;
  RETURN TRUE
END Start;

(** portia.Install [/arch] name ... -- install the packages: build them, and the dependencies
  that are missing or older than needed; packages already installed in the tree's version
  are left alone. Installed packages they conflict with are replaced *)
PROCEDURE Install*;
VAR names, set, it: Item; p: Package; v: ARRAY 32 OF CHAR; ok: BOOLEAN;
BEGIN
  IF ~Start(names) THEN RETURN END;
  IF names = NIL THEN Usage("Install [/arch] name ..."); SetArch(hostArch); RETURN END;
  set := NIL; ok := TRUE; it := names;
  WHILE ok & (it # NIL) DO
    p := Find(it.s);
    IF p = NIL THEN NoPackage(it.s); ok := FALSE
    ELSIF IsInstalled(p) & haveDb & InstVer(p, v) & Versions.AtLeast(v, p.version) THEN
      Pre; out.String(p.name); out.Char(" "); out.String(v); out.String(" is installed"); out.Ln
    ELSE Add(set, p.name); ok := AddNeeded(p, set)
    END;
    it := it.next
  END;
  IF ok & (set # NIL) THEN Execute(set, "installing") END;
  SetArch(hostArch)
END Install;

(** portia.Upgrade [/arch] [name ...] -- build the installed packages with a newer version in
  the tree (all, or the named ones), what they need, and the packages depending on them; and
  recompile the installed remote packages compiled before an interface they import changed
  (after a git pull of polpo) *)
PROCEDURE Upgrade*;
VAR names, set, it: Item; p: Package; v: ARRAY 32 OF CHAR; why: Name; ok: BOOLEAN;
BEGIN
  IF ~Start(names) THEN RETURN END;
  set := NIL; ok := TRUE; p := packages;
  WHILE ok & (p # NIL) DO
    IF IsInstalled(p) & ((names = NIL) OR Has(names, p.name)) & InstVer(p, v) & ~Versions.AtLeast(v, p.version) THEN
      Add(set, p.name); ok := AddNeeded(p, set)
    END;
    p := p.next
  END;
  p := packages;
  WHILE ok & (p # NIL) DO
    IF IsInstalled(p) & (p.remote # "") & ((names = NIL) OR Has(names, p.name)) & ~Has(set, p.name) & Stale(p, why) THEN
      Add(set, p.name); it := set; WHILE it.s # p.name DO it := it.next END;
      COPY(why, it.v);  (* shown as "recompiled for the new <why>" *)
      ok := AddNeeded(p, set)
    END;
    p := p.next
  END;
  IF ~ok THEN
  ELSIF set = NIL THEN Pre; out.String("everything is up to date"); out.Ln
  ELSE Execute(set, "upgrading")
  END;
  SetArch(hostArch)
END Upgrade;

(** portia.Build [/arch] [name ...] -- rebuild the packages (and dependencies missing or too
  old); without names every installed package *)
PROCEDURE Build*;
VAR names, set, it: Item; p: Package; ok: BOOLEAN;
BEGIN
  IF ~Start(names) THEN RETURN END;
  set := NIL; ok := TRUE;
  IF names = NIL THEN
    p := packages; WHILE p # NIL DO IF IsInstalled(p) THEN Add(set, p.name) END; p := p.next END
  ELSE
    it := names;
    WHILE ok & (it # NIL) DO
      p := Find(it.s);
      IF p = NIL THEN NoPackage(it.s); ok := FALSE
      ELSE Add(set, p.name); ok := AddNeeded(p, set)
      END;
      it := it.next
    END
  END;
  IF ok THEN Execute(set, "building") END;
  SetArch(hostArch)
END Build;

(* ----- the dependency graph ----- *)

(** portia.Graph [name] -- the dependencies as a Graphviz graph on the standard output, of
  one package and what it needs, or of the whole tree; installed packages filled, virtual
  ones (display) dashed with their providers:  loksh portia.Graph > deps.dot; dot -Tsvg ... *)
PROCEDURE Graph*;
VAR name: Name; set, it, d, virt: Item; p, q: Package;

  PROCEDURE Q(s: ARRAY OF CHAR);
  BEGIN out.Char(22X); out.String(s); out.Char(22X)
  END Q;

BEGIN
  IF ~LoadTree() THEN RETURN END;
  set := NIL;
  IF Arg(name) THEN
    p := Find(name);
    IF p = NIL THEN NoPackage(name); RETURN END;
    Closure(p, set)
  ELSE p := packages; WHILE p # NIL DO Add(set, p.name); p := p.next END
  END;
  out.String("digraph arden {"); out.Ln;
  out.String("  rankdir=LR; node [shape=box, fontname=sans];"); out.Ln;
  virt := NIL; it := set;
  WHILE it # NIL DO
    p := Find(it.s);
    IF p # NIL THEN
      out.String("  "); Q(p.name); out.String(" [label="); out.Char(22X); out.String(p.name); out.String("\n"); out.String(p.version); out.Char(22X);
      IF IsInstalled(p) THEN out.String(", style=filled, fillcolor=lightgrey") END;
      out.String("];"); out.Ln;
      d := p.deps;
      WHILE d # NIL DO
        out.String("  "); Q(p.name); out.String(" -> "); Q(d.s);
        IF d.v # "" THEN out.String(" [label="); Q(d.v); out.String("]") END;
        out.String(";"); out.Ln;
        IF (Find(d.s) = NIL) & ~Has(virt, d.s) THEN Add(virt, d.s) END;
        d := d.next
      END
    END;
    it := it.next
  END;
  it := virt;
  WHILE it # NIL DO  (* a virtual package and its providers *)
    out.String("  "); Q(it.s); out.String(" [style=dashed, shape=ellipse];"); out.Ln;
    q := packages;
    WHILE q # NIL DO
      IF Has(q.provides, it.s) THEN out.String("  "); Q(q.name); out.String(" -> "); Q(it.s); out.String(" [style=dashed, dir=back];"); out.Ln END;
      q := q.next
    END;
    it := it.next
  END;
  out.String("}"); out.Ln
END Graph;

(** portia.Remove [/arch] [/src | /all] [/deps] name ... -- delete the objects of the packages
  and unrecord them, not while installed packages need them (/deps: those go too, directly or
  indirectly needing ones); the files a remote package copied out
  of src/pkg/<name>/ go too. /src: only the downloaded sources of remote packages (they stay
  installed), /all: both. Sources and data of the base system stay *)
PROCEDURE Remove*;
VAR names, it, needers, n2: Item; p: Package; ok: BOOLEAN; n: LONGINT;
BEGIN
  Args(names);
  IF names = NIL THEN Usage("Remove [/arch] [/src | /all] [/deps] [/y] name ..."); SetArch(hostArch); RETURN END;
  IF ~LoadTree() THEN SetArch(hostArch); RETURN END;
  IF ~haveDb THEN RecordAll(FALSE) END;
  ok := TRUE; it := names;
  WHILE it # NIL DO
    p := Find(it.s);
    IF p = NIL THEN NoPackage(it.s); ok := FALSE
    ELSIF delSrc & ~delObj & (p.remote = "") THEN
      Pre; out.String(it.s); out.String(" is part of the base system, its sources stay"); out.Ln; ok := FALSE
    ELSIF delSrc & ~delObj & ~HasSources(p) THEN
      Pre; out.String("the sources of "); out.String(it.s); out.String(" are not here"); out.Ln; ok := FALSE
    ELSIF delObj & ~IsInstalled(p) & ~(delSrc & HasSources(p)) THEN
      Pre; out.String(it.s); out.String(" is not installed"); out.Ln; ok := FALSE
    ELSIF delObj & IsInstalled(p) THEN
      needers := NIL; AllNeeders(p, needers);
      n2 := needers; WHILE n2 # NIL DO IF Has(names, n2.s) THEN Drop(needers, n2.s); n2 := needers ELSE n2 := n2.next END END;
      IF needers = NIL THEN
      ELSIF withDeps THEN  (* they go too *)
        n2 := needers; WHILE n2 # NIL DO IF ~Has(names, n2.s) THEN Add(names, n2.s) END; n2 := n2.next END
      ELSE  (* needed by packages that stay *)
        Pre; out.String(p.name); out.String(" is needed by");
        n2 := needers; WHILE n2 # NIL DO out.Char(" "); out.String(n2.s); n2 := n2.next END; out.Ln;
        Pre; out.String("portia.Remove /deps "); out.String(p.name); out.String(" removes them too"); out.Ln; ok := FALSE
      END
    END;
    it := it.next
  END;
  IF ok THEN
    Pre; out.String("removing for "); out.String(arch);
    IF ~delSrc THEN out.String(" (objects; sources stay):")
    ELSIF ~delObj THEN out.String(" (the downloaded sources; the packages stay installed):")
    ELSE out.String(" (objects and downloaded sources):")
    END;
    out.Ln;
    n := 0; it := names; WHILE it # NIL DO p := Find(it.s); out.String("  "); out.String(p.name); out.Char(" "); out.String(p.version); out.Ln; INC(n); it := it.next END;
    IF Confirm(n, "removing") THEN
      it := names;
      WHILE it # NIL DO
        p := Find(it.s);
        IF delObj & IsInstalled(p) THEN
          DeleteObjects(p, NIL); IF p.remote # "" THEN DeleteData(p, NIL) END; Drop(installed, p.name)
        END;
        IF delSrc & (p.remote # "") THEN DeleteSources(p) END;
        it := it.next
      END;
      IF delObj THEN SaveDb END;
      Pre; out.String("removed "); out.Int(n, 0); IF n = 1 THEN out.String(" package") ELSE out.String(" packages") END; out.Ln
    ELSE Pre; out.String("nothing done"); out.Ln
    END
  END;
  SetArch(hostArch)
END Remove;

(** portia.Sync -- the package tree from GitHub: the newest commit of polpo-system/arden, as files,
  into the tree (default <root>arden/; its commit in COMMIT); a tree that is a git checkout is left
  to git *)
PROCEDURE Sync*;
VAR dir, path, line, tmp, new, sha, have: Name; buf: Buf; i, j: LONGINT; r: INTEGER; f: F.File; R: F.Rider;

  PROCEDURE At(VAR b: ARRAY OF CHAR; i: LONGINT; pat: ARRAY OF CHAR): BOOLEAN;  (* pat at b[i] *)
  VAR k: LONGINT;
  BEGIN k := 0; WHILE (pat[k] # 0X) & (b[i+k] = pat[k]) DO INC(k) END; RETURN pat[k] = 0X
  END At;

  PROCEDURE Tree(s: ARRAY OF CHAR);
  BEGIN Pre; out.String("tree at "); out.String(sha); out.String(s); out.Ln
  END Tree;

  PROCEDURE Get(url: ARRAY OF CHAR): BOOLEAN;  (* https://<url> into tmp *)
  BEGIN
    line := "fetch.Get https://"; Append(line, url); Append(line, " "); Append(line, tmp);
    RETURN Run(line) & Root.Exists(tmp)
  END Get;

  PROCEDURE Hex(c: CHAR): BOOLEAN;
  BEGIN RETURN (c >= "0") & (c <= "9") OR (c >= "a") & (c <= "f")
  END Hex;

BEGIN
  COPY(tree, dir); i := Len(dir); IF (i > 1) & (dir[i-1] = "/") THEN dir[i-1] := 0X END;
  COPY(tree, path); Append(path, ".git");
  IF Root.Exists(path) THEN Pre; out.String(dir); out.String(" is a git checkout: git pull there"); out.Ln; RETURN END;
  Root.Join("portia.tmp", tmp); sha := "";
  path := "api.github.com/repos/"; Append(path, TreeRepo); Append(path, "/commits/"); Append(path, TreeBranch);
  IF Get(path) & ReadFile(tmp, buf) THEN  (* the newest commit: the first "sha": "..." *)
    i := 0; WHILE (buf[i] # 0X) & ~At(buf^, i, '"sha"') DO INC(i) END;
    IF buf[i] # 0X THEN
      INC(i, 5); WHILE (buf[i] # 0X) & (buf[i] # 22X) DO INC(i) END;
      IF buf[i] # 0X THEN INC(i) END;
      j := 0; WHILE (j < 40) & Hex(buf[i]) DO sha[j] := buf[i]; INC(i); INC(j) END;
      IF j = 40 THEN sha[j] := 0X ELSE sha := "" END
    END
  END;
  F.Delete(tmp, r);
  IF sha = "" THEN Pre; out.String("no commit found"); out.Ln; RETURN END;
  COPY(tree, path); Append(path, "COMMIT");
  IF ReadFile(path, buf) THEN
    i := 0; WHILE (i < NameLen - 1) & (buf[i] > " ") DO have[i] := buf[i]; INC(i) END; have[i] := 0X;
    IF have = sha THEN Tree(", up to date"); RETURN END
  END;
  (* the files of the commit into dir.new, then in place of dir *)
  COPY(dir, new); Append(new, ".new");
  COPY(new, path); Append(path, "/"); IF Root.Exists(path) THEN DeleteTree(new) END;
  path := "codeload.github.com/"; Append(path, TreeRepo); Append(path, "/tar.gz/"); Append(path, sha);
  IF Get(path) THEN line := "tar.Unpack "; Append(line, tmp); Append(line, " "); Append(line, new); Append(line, " 1") END;
  COPY(new, path); Append(path, "/INDEX");
  IF ~Root.Exists(tmp) OR ~Run(line) OR ~Root.Exists(path) THEN
    F.Delete(tmp, r); Pre; out.String("no tree downloaded, the old tree stays as it was"); out.Ln; RETURN
  END;
  F.Delete(tmp, r);
  COPY(new, path); Append(path, "/COMMIT"); f := F.New(path); F.Set(R, f, 0);
  i := 0; WHILE sha[i] # 0X DO F.Write(R, sha[i]); INC(i) END; F.Write(R, 0AX); F.Register(f);
  COPY(dir, path); Append(path, "/"); IF Root.Exists(path) THEN DeleteTree(dir) END;
  F.Rename(new, dir, r);
  IF r # 0 THEN Pre; out.String("cannot move "); out.String(new); out.Ln; RETURN END;
  packages := NIL; Tree("")
END Sync;

(** portia.Fetch name ... -- download the sources of remote packages (src/pkg/<name>/), checked
  by their sums; installing does this too *)
PROCEDURE Fetch*;
VAR names, it: Item; p: Package;
BEGIN
  Args(names);
  IF names = NIL THEN Usage("Fetch name ..."); SetArch(hostArch); RETURN END;
  IF ~LoadTree() THEN SetArch(hostArch); RETURN END;
  it := names;
  WHILE it # NIL DO
    p := Find(it.s);
    IF p = NIL THEN NoPackage(it.s)
    ELSIF p.remote = "" THEN Pre; out.String(p.name); out.String(" is part of the base system, nothing to download"); out.Ln
    ELSIF FetchPackage(p, FALSE) THEN Pre; out.String(p.name); out.String(": the sources are here and correct"); out.Ln
    END;
    it := it.next
  END;
  SetArch(hostArch)
END Fetch;

(** portia.Sums name [dir] -- the [SUMS] section of a remote package for its recipe: the SHA-256
  of its files in dir (a checkout of its repository; default src/pkg/<name>/) *)
PROCEDURE Sums*;
VAR A: Texts.Reader; name, dir, path: Name; p: Package; it: Item; hex: ARRAY 72 OF CHAR; i: LONGINT;

  PROCEDURE One(VAR r: ARRAY OF CHAR);
  BEGIN
    COPY(dir, path); Append(path, r);
    IF Checksums.File(Checksums.SHA256, path, hex) THEN
      out.String(r); out.String(" = "); out.Char(22X); out.String("sha256:"); out.String(hex); out.Char(22X); out.Ln
    ELSE out.String("# missing "); out.String(path); out.Ln
    END
  END One;

BEGIN
  Texts.OpenArgs(A);
  IF ~Texts.Arg(A, name) THEN Usage("Sums name [dir]"); RETURN END;
  IF ~LoadTree() THEN RETURN END;
  p := Find(name);
  IF p = NIL THEN NoPackage(name); RETURN END;
  IF p.remote = "" THEN Pre; out.String(p.name); out.String(" is not a remote package"); out.Ln; RETURN END;
  IF Texts.Arg(A, dir) THEN
    i := Len(dir); IF (i > 0) & (dir[i-1] # "/") THEN Append(dir, "/") END
  ELSE PackageDir(p, path); Root.Join(path, dir)
  END;
  out.String("[SUMS]"); out.Ln;
  it := p.sources; WHILE it # NIL DO One(it.r); it := it.next END;
  it := p.files; WHILE it # NIL DO One(it.r); it := it.next END
END Sums;

(** portia.Test name ... -- run the tests of installed packages ([TESTS]); Install /t and
  Build /t test what they build *)
PROCEDURE Test*;
VAR names, it: Item; p: Package; failed: LONGINT;
BEGIN
  Args(names);
  IF names = NIL THEN Usage("Test name ..."); SetArch(hostArch); RETURN END;
  SetArch(hostArch);
  IF ~LoadTree() THEN RETURN END;
  failed := 0; it := names;
  WHILE it # NIL DO
    p := Find(it.s);
    IF p = NIL THEN NoPackage(it.s); INC(failed)
    ELSIF ~IsInstalled(p) THEN Pre; out.String(p.name); out.String(" is not installed"); out.Ln; INC(failed)
    ELSIF ~TestPackage(p) THEN INC(failed)
    END;
    it := it.next
  END;
  IF failed > 0 THEN out.Int(failed, 0); out.String(" failed"); out.Ln END
END Test;

PROCEDURE Init;
VAR S: Texts.Scanner; i: LONGINT;
BEGIN
  IF Linux0.ARCH = "X86" THEN hostArch := "x86" ELSIF Linux0.ARCH = "ARM" THEN hostArch := "arm"
  ELSIF Linux0.ARCH = "RISC-V" THEN hostArch := "riscv" ELSIF Linux0.ARCH = "MIPS" THEN hostArch := "mips"
  ELSE hostArch := "armv7"
  END;
  COPY(hostArch, arch);
  Kernel.GetConfig("PORTIA_TREE", tree);  (* first: Oberon.Text strings have at most 63 characters *)
  IF tree = "" THEN
    Oberon.OpenScanner(S, "Portia.Tree");
    IF S.class IN {Texts.Name, Texts.String} THEN COPY(S.s, tree)
    ELSE Root.Join("arden/", tree)
    END
  END;
  i := 0; WHILE tree[i] # 0X DO INC(i) END;
  IF (i > 0) & (tree[i-1] # "/") THEN Append(tree, "/") END;
  packages := NIL
END Init;

BEGIN
  Init
END portia.
