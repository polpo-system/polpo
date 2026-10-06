MODULE genarden;  (** the recipes of the base system of polpo for the package tree arden *)

(* genarden.Run [dir]   reads the build recipes tools/*.Tool of polpo and dir/tools/base.toml (the
                        packages of the base system: categories, descriptions, dependencies, the
                        rules saying which package a module belongs to, files), writes a recipe
                        for each of these packages into dir and the INDEX of all the recipes of
                        dir (the remote packages too, found in its directories).
   dir defaults to the tree of portia (PORTIA_TREE, Portia.Tree in Oberon.Text, <root>arden/).
   Run it after changing the build recipes, then portia.Check. *)

IMPORT SYSTEM, Kernel, Linux0, Files, FATFiles, Root, Texts := Texts0, Oberon := Oberon0, texts, TOML, out;

CONST
  NameLen = 256; MaxArchs = 5; MaxLine = 1024;
  Version = "0.1.0";

TYPE
  Name = ARRAY NameLen OF CHAR;
  Buf = POINTER TO ARRAY OF CHAR;
  Item = POINTER TO ItemDesc;
  ItemDesc = RECORD s: Name; archs, xflag: SET; next: Item END;  (* a source: on which architectures, with /x *)
  Package = POINTER TO PackageDesc;
  PackageDesc = RECORD
    name: Name;
    sec: TOML.Section;
    match, sources: Item;
    next: Package
  END;

VAR
  archs: ARRAY MaxArchs OF ARRAY 8 OF CHAR;
  links: ARRAY MaxArchs OF ARRAY MaxLine OF CHAR;  (* the link command of each architecture *)
  packages: Package;
  claimed, entries: Item;  (* files installed by remote packages; of a directory listing *)
  tree: Name;
  W: Files.Rider; problems: INTEGER;

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

PROCEDURE Add(VAR list: Item; s: ARRAY OF CHAR): Item;  (* at the end *)
VAR it, p: Item;
BEGIN
  NEW(it); COPY(s, it.s); it.archs := {}; it.xflag := {}; it.next := NIL;
  IF list = NIL THEN list := it ELSE p := list; WHILE p.next # NIL DO p := p.next END; p.next := it END;
  RETURN it
END Add;

PROCEDURE Find(list: Item; VAR s: ARRAY OF CHAR): Item;
BEGIN WHILE (list # NIL) & (list.s # s) DO list := list.next END; RETURN list
END Find;

PROCEDURE Prefix(VAR s: ARRAY OF CHAR; pre: ARRAY OF CHAR): BOOLEAN;
VAR i: LONGINT;
BEGIN i := 0; WHILE (pre[i] # 0X) & (s[i] = pre[i]) DO INC(i) END; RETURN pre[i] = 0X
END Prefix;

(* the position of pat in s, -1 if it is not there *)
PROCEDURE Pos(VAR s: ARRAY OF CHAR; pat: ARRAY OF CHAR): LONGINT;
VAR i, k: LONGINT;
BEGIN
  i := 0;
  WHILE s[i] # 0X DO
    k := 0; WHILE (pat[k] # 0X) & (s[i+k] = pat[k]) DO INC(k) END;
    IF pat[k] = 0X THEN RETURN i END;
    INC(i)
  END;
  RETURN -1
END Pos;

PROCEDURE ReadFile(VAR path: ARRAY OF CHAR; VAR buf: Buf): BOOLEAN;
VAR f: Files.File; R: Files.Rider; n, i: LONGINT;
BEGIN
  f := Files.Old(path); IF f = NIL THEN RETURN FALSE END;
  n := Files.Length(f); NEW(buf, n + 1); Files.Set(R, f, 0);
  i := 0; WHILE i < n DO Files.Read(R, buf[i]); INC(i) END; buf[n] := 0X;
  RETURN TRUE
END ReadFile;

PROCEDURE MakeDirs(VAR full: ARRAY OF CHAR);  (* the directories of the file path full *)
VAR i, r: LONGINT; dir: Name;
BEGIN
  dir[0] := full[0]; i := 1;
  WHILE (full[i] # 0X) & (i < NameLen - 1) DO
    IF full[i] = "/" THEN dir[i] := 0X; r := Linux0.MkDir0(SYSTEM.ADR(dir), 1EDH) END;
    dir[i] := full[i]; INC(i)
  END
END MakeDirs;

PROCEDURE CollectEntry(name: ARRAY OF CHAR; time, date, size: LONGINT; attr: SET; VAR continue: BOOLEAN);
VAR it: Item;
BEGIN
  it := Add(entries, name); IF FATFiles.SubDir IN attr THEN it.archs := {0} END;  (* {0}: a directory *)
  continue := TRUE
END CollectEntry;

(* the entries of the directory dir (with "/" at the end), sorted *)
PROCEDURE List(VAR dir: ARRAY OF CHAR): Item;
VAR list, a, b: Item; res: LONGINT; t: Name; s: SET;
BEGIN
  entries := NIL; FATFiles.Enumerate(dir, CollectEntry, res); list := entries; entries := NIL;
  a := list;  (* sort by name, bytewise *)
  WHILE a # NIL DO
    b := a.next;
    WHILE b # NIL DO
      IF b.s < a.s THEN t := a.s; a.s := b.s; b.s := t; s := a.archs; a.archs := b.archs; b.archs := s END;
      b := b.next
    END;
    a := a.next
  END;
  RETURN list
END List;

(* the files under dir (relative to the polpo root, "/" at the end), recursively, sorted as git does *)
PROCEDURE Expand(VAR dir: ARRAY OF CHAR; VAR files: Item);
VAR full, path: Name; it, x: Item; i: LONGINT;
BEGIN
  Root.Join(dir, full); it := List(full);
  WHILE it # NIL DO
    COPY(dir, path); Append(path, it.s);
    IF it.archs = {0} THEN Append(path, "/"); Expand(path, files)
    ELSE
      i := Len(path);
      IF ~((i > 4) & (path[i-4] = ".") & (path[i-3] = "B") & (path[i-2] = "a") & (path[i-1] = "k")) & (Find(claimed, path) = NIL) THEN
        x := Add(files, path)
      END
    END;
    it := it.next
  END
END Expand;

(* ----- writing TOML ----- *)

PROCEDURE Ws(s: ARRAY OF CHAR);
VAR i: LONGINT;
BEGIN i := 0; WHILE s[i] # 0X DO IF s[i] = 0AX THEN Files.Write(W, 0AX) ELSE Files.Write(W, s[i]) END; INC(i) END
END Ws;

PROCEDURE Ln;
BEGIN Files.Write(W, 0AX)
END Ln;

PROCEDURE Quoted(VAR s, buf: ARRAY OF CHAR);  (* s as a TOML basic string, appended to buf *)
VAR i, j: LONGINT;
BEGIN
  j := Len(buf); buf[j] := 22X; INC(j); i := 0;
  WHILE (s[i] # 0X) & (j < LEN(buf) - 3) DO
    IF (s[i] = 22X) OR (s[i] = "\") THEN buf[j] := "\"; INC(j) END;
    buf[j] := s[i]; INC(i); INC(j)
  END;
  buf[j] := 22X; buf[j+1] := 0X
END Quoted;

PROCEDURE Q(s: ARRAY OF CHAR);
VAR buf: ARRAY MaxLine OF CHAR;
BEGIN buf := ""; Quoted(s, buf); Ws(buf)
END Q;

(* a TOML array: on one line when it is at most 80 characters long, else one element a line *)
PROCEDURE Arr(list: Item);
VAR buf: ARRAY 8192 OF CHAR; it: Item;
BEGIN
  buf := "["; it := list;
  WHILE it # NIL DO Quoted(it.s, buf); IF it.next # NIL THEN Append(buf, ", ") END; it := it.next END;
  Append(buf, "]");
  IF Len(buf) <= 80 THEN Ws(buf)
  ELSE
    Ws("["); Ln; it := list;
    WHILE it # NIL DO buf := "  "; Quoted(it.s, buf); Append(buf, ","); Ws(buf); Ln; it := it.next END;
    Ws("]")
  END
END Arr;

(* ----- reading the build recipes ----- *)

PROCEDURE Field(sec: TOML.Section; key: ARRAY OF CHAR; VAR val: ARRAY OF CHAR): BOOLEAN;
BEGIN RETURN TOML.GetField(sec, key, val)
END Field;

PROCEDURE Items(sec: TOML.Section; key: ARRAY OF CHAR): Item;  (* the elements of an array *)
VAR f: TOML.Field; it: TOML.Item; list, x: Item;
BEGIN
  list := NIL; f := TOML.Find(sec, key);
  IF f # NIL THEN it := f.items; WHILE it # NIL DO x := Add(list, it.value); it := it.next END END;
  RETURN list
END Items;

(* the package of the source path: the first whose match has its directory, its path or its name *)
PROCEDURE PackageOf(VAR path: ARRAY OF CHAR): Package;
VAR p: Package; m: Item; dir, base: Name; i, k, j: LONGINT;
BEGIN
  k := -1; i := 0; WHILE path[i] # 0X DO IF path[i] = "/" THEN k := i END; INC(i) END;
  i := 0; WHILE i <= k DO dir[i] := path[i]; INC(i) END; dir[i] := 0X;
  j := 0; i := k + 1; WHILE path[i] # 0X DO base[j] := path[i]; INC(i); INC(j) END; base[j] := 0X;
  IF (j > 4) & (base[j-4] = ".") THEN base[j-4] := 0X END;
  p := packages;
  WHILE p # NIL DO
    m := p.match;
    WHILE m # NIL DO
      IF (m.s = dir) OR (m.s = path) OR (m.s = base) THEN RETURN p END;
      m := m.next
    END;
    p := p.next
  END;
  RETURN NIL
END PackageOf;

PROCEDURE AddSource(p: Package; VAR path: ARRAY OF CHAR; a: INTEGER; x: BOOLEAN);
VAR it: Item;
BEGIN
  it := Find(p.sources, path); IF it = NIL THEN it := Add(p.sources, path) END;
  INCL(it.archs, a); IF x THEN INCL(it.xflag, a) END
END AddSource;

(* the lines of the recipe tools/<name>.Tool for the architecture a *)
PROCEDURE Recipe(name: ARRAY OF CHAR; a: INTEGER; link: BOOLEAN);
VAR path: Name; T: Texts.Text; R: Texts.Reader; ch: CHAR; line: ARRAY MaxLine OF CHAR; n: LONGINT;

  PROCEDURE Line;  (* a compilation of a source, or the link command *)
  VAR i, j: LONGINT; src, word: Name; p: Package;
  BEGIN
    i := Pos(line, "src/");
    IF (i >= 0) & (Pos(line, "Compile") >= 0) THEN
      j := 0; WHILE line[i] > " " DO src[j] := line[i]; INC(i); INC(j) END; src[j] := 0X;
      IF (j > 4) & (src[j-4] = ".") & (src[j-3] = "M") THEN
        p := PackageOf(src);
        IF p = NIL THEN out.String("genarden: no package for "); out.String(src); out.Ln; INC(problems)
        ELSE AddSource(p, src, a, Pos(line, " /x ") >= 0)
        END
      END
    END;
    i := 0; WHILE (line[i] = " ") OR (line[i] = 09X) DO INC(i) END;
    j := 0; WHILE line[i+j] > " " DO word[j] := line[i+j]; INC(j) END; word[j] := 0X;
    IF link & (j >= 11) & (Pos(word, "linker.Link") = j - 11) & (line[i+j] = " ") THEN
      j := Len(line); WHILE (j > 0) & (line[j-1] <= " ") DO DEC(j) END; line[j] := 0X;
      j := 0; WHILE line[i] # 0X DO links[a][j] := line[i]; INC(i); INC(j) END; links[a][j] := 0X
    END
  END Line;

BEGIN
  path := "tools/"; Append(path, name); Append(path, ".Tool"); Root.Join(path, path);
  IF Files.Old(path) = NIL THEN out.String("genarden: no "); out.String(path); out.Ln; INC(problems); RETURN END;
  NEW(T); Texts.Open(T, path); Texts.OpenReader(R, T, 0); n := 0; Texts.Read(R, ch);
  WHILE ~R.eot DO
    IF (ch = 0DX) OR (ch = 0AX) THEN line[n] := 0X; Line; n := 0
    ELSIF n < MaxLine - 1 THEN line[n] := ch; INC(n)
    END;
    Texts.Read(R, ch)
  END;
  line[n] := 0X; Line
END Recipe;

(* the recipes of the tree other than the base ones: category/name/name-version.arden *)
PROCEDURE Recipes(VAR found: Item);
VAR cats, pkgs, rs, x: Item; cdir, pdir, path: Name; p: Package; base: BOOLEAN;
BEGIN
  found := NIL; cats := List(tree);
  WHILE cats # NIL DO
    IF (cats.archs = {0}) & (cats.s # "tools") & (cats.s[0] # ".") THEN
      COPY(tree, cdir); Append(cdir, cats.s); Append(cdir, "/"); pkgs := List(cdir);
      WHILE pkgs # NIL DO
        p := packages; base := FALSE; WHILE p # NIL DO IF p.name = pkgs.s THEN base := TRUE END; p := p.next END;
        IF (pkgs.archs = {0}) & ~base THEN
          COPY(cdir, pdir); Append(pdir, pkgs.s); Append(pdir, "/"); rs := List(pdir);
          WHILE rs # NIL DO
            IF (rs.archs # {0}) & (Pos(rs.s, ".arden") > 0) THEN
              COPY(cats.s, path); Append(path, "/"); Append(path, pkgs.s); Append(path, "/"); Append(path, rs.s); x := Add(found, path)
            END;
            rs := rs.next
          END
        END;
        pkgs := pkgs.next
      END
    END;
    cats := cats.next
  END
END Recipes;

(* the files that remote packages install: their [FILES] path=dest *)
PROCEDURE Claimed(recipes: Item);
VAR path, dest: Name; buf: Buf; doc: TOML.Doc; f: TOML.Field; it: TOML.Item; s: TOML.Section;
  i, k: LONGINT; key: ARRAY 16 OF CHAR; x: Item;
BEGIN
  claimed := NIL;
  WHILE recipes # NIL DO
    COPY(tree, path); Append(path, recipes.s);
    IF ReadFile(path, buf) THEN
      doc := TOML.Parse(buf^); key := "FILES"; s := TOML.GetSection(doc, key);
      IF s # NIL THEN f := s.first ELSE f := NIL END;
      WHILE f # NIL DO
        it := f.items;
        WHILE it # NIL DO
          i := Pos(it.value, "=");
          IF i > 0 THEN k := 0; INC(i); WHILE it.value[i] # 0X DO dest[k] := it.value[i]; INC(i); INC(k) END; dest[k] := 0X; x := Add(claimed, dest) END;
          it := it.next
        END;
        f := f.next
      END
    END;
    recipes := recipes.next
  END
END Claimed;

(* ----- writing the recipes ----- *)

PROCEDURE Tok(it: Item; on: SET; VAR s: ARRAY OF CHAR);  (* "/x path" when every one of on has /x *)
BEGIN
  IF on * it.xflag = on THEN COPY("/x ", s); Append(s, it.s) ELSE COPY(it.s, s) END
END Tok;

PROCEDURE Write(p: Package; VAR index: Item);
VAR cat, desc, author, lic, path, tok: Name; all, l, it, files, deps, x: Item; a: INTEGER; i, j: LONGINT; f: Files.File; key: ARRAY 32 OF CHAR;
  none: BOOLEAN; tf: TOML.Field;
BEGIN
  IF ~Field(p.sec, "category", cat) OR ~Field(p.sec, "description", desc) THEN
    out.String("genarden: "); out.String(p.name); out.String(" needs a category and a description"); out.Ln; INC(problems); RETURN
  END;
  IF ~Field(p.sec, "author", author) THEN author := "polpo" END;
  IF ~Field(p.sec, "license", lic) THEN lic := "GPL-3" END;
  COPY(tree, path); Append(path, cat); Append(path, "/"); Append(path, p.name); Append(path, "/"); Append(path, p.name);
  Append(path, "-"); Append(path, Version); Append(path, ".arden"); MakeDirs(path);
  f := Files.New(path); Files.Set(W, f, 0);
  Ws("[PACKAGE]"); Ln; Ws("name        = "); Q(p.name); Ln; Ws("category    = "); Q(cat); Ln;
  Ws('version     = "'); Ws(Version); Ws('"'); Ln; Ws("author      = "); Q(author); Ln; Ws("license     = "); Q(lic); Ln;
  Ws("description = "); Q(desc); Ln; Ln;
  Ws("[REMOTE]"); Ln; Ws('type = "git"'); Ln; Ws('uri  = "https://raw.githubusercontent.com/polpo-system/polpo/main"'); Ln; Ws('tag  = "main"'); Ln; Ln;
  Ws("[DEPS]"); Ln; deps := Items(p.sec, "deps");
  WHILE deps # NIL DO Ws(deps.s); Ws(' = "'); Ws(Version); Ws('"'); Ln; deps := deps.next END;
  l := Items(p.sec, "provides");
  IF l # NIL THEN Ln; Ws("[PROVIDES]"); Ln; Ws(l.s); Ws(' = "'); Ws(Version); Ws('"'); Ln END;
  l := Items(p.sec, "conflicts");
  IF l # NIL THEN Ln; Ws("[CONFLICTS]"); Ln; Ws(l.s); Ws(' = "'); Ws(Version); Ws('"'); Ln END;
  (* the modules, in build order: the common ones under all, the rest per architecture *)
  Ln; Ws("[MODULES]"); Ln;
  all := NIL; it := p.sources;
  WHILE it # NIL DO IF it.archs = {0..MaxArchs-1} THEN Tok(it, {0..MaxArchs-1}, tok); x := Add(all, tok) END; it := it.next END;
  IF all # NIL THEN Ws("all = "); Arr(all); Ln END;
  a := 0;
  WHILE a < MaxArchs DO
    l := NIL; it := p.sources;
    WHILE it # NIL DO IF (a IN it.archs) & (it.archs # {0..MaxArchs-1}) THEN Tok(it, {a}, tok); x := Add(l, tok) END; it := it.next END;
    IF l # NIL THEN Ws(archs[a]); Ws(" = "); Arr(l); Ln END;
    INC(a)
  END;
  IF p.name = "core" THEN  (* link the boot image, then move it in place *)
    Ln; Ws("[BUILD]"); Ln; a := 0;
    WHILE a < MaxArchs DO
      l := NIL; x := Add(l, links[a]);
      i := 0; WHILE (links[a][i] # 0X) & ~((links[a][i] = "b") & (links[a][i+1] = "i") & (links[a][i+2] = "n") & (links[a][i+3] = "/")) DO INC(i) END;
      tok := "mv "; j := 3; WHILE links[a][i] > " " DO tok[j] := links[a][i]; INC(i); INC(j) END; tok[j] := 0X;
      Append(tok, " bin/"); Append(tok, archs[a]); Append(tok, "/loksh"); x := Add(l, tok);
      Ws(archs[a]); Ws(" = "); Arr(l); Ln; INC(a)
    END
  END;
  (* the files: files.all and files.<arch>, a directory/* expanded *)
  none := TRUE; tf := p.sec.first;
  WHILE tf # NIL DO
    IF Prefix(tf.key, "files.") THEN
      IF none THEN Ln; Ws("[FILES]"); Ln; none := FALSE END;
      i := 6; j := 0; WHILE tf.key[i] # 0X DO key[j] := tf.key[i]; INC(i); INC(j) END; key[j] := 0X;
      files := NIL; l := Items(p.sec, tf.key);
      WHILE l # NIL DO
        i := Len(l.s);
        IF (i > 2) & (l.s[i-1] = "*") & (l.s[i-2] = "/") THEN l.s[i-1] := 0X; Expand(l.s, files)
        ELSE x := Add(files, l.s)
        END;
        l := l.next
      END;
      Ws(key); Ws(" = "); Arr(files); Ln
    END;
    tf := tf.next
  END;
  Files.Register(f);
  COPY(cat, tok); Append(tok, "/"); Append(tok, p.name); Append(tok, " "); Append(tok, Version); x := Add(index, tok)
END Write;

(* the other recipes, for the INDEX: category/name/name-version.arden as category/name version *)
PROCEDURE Others(recipes: Item; VAR index: Item);
VAR line: Name; i, k, n: LONGINT; x: Item;
BEGIN
  WHILE recipes # NIL DO
    k := 0; i := 0; WHILE recipes.s[i] # 0X DO IF recipes.s[i] = "/" THEN k := i END; INC(i) END;
    i := 0; WHILE i < k DO line[i] := recipes.s[i]; INC(i) END; line[i] := 0X;  (* category/name *)
    n := Len(line) - Pos(line, "/") - 1;  (* the length of the name *)
    Append(line, " "); i := k + 1 + n + 1; k := Len(line);
    WHILE (recipes.s[i] # 0X) & (Pos(recipes.s, ".arden") # i) DO line[k] := recipes.s[i]; INC(i); INC(k) END; line[k] := 0X;
    x := Add(index, line);
    recipes := recipes.next
  END
END Others;

PROCEDURE Run*;
VAR A: texts.Reader; arg, path: Name; buf: Buf; doc: TOML.Doc; s: TOML.Section; p, last: Package;
  index, it, others: Item; f: Files.File; S: Texts.Scanner; i: LONGINT;
BEGIN
  problems := 0; texts.OpenArgs(A);
  IF texts.Arg(A, arg) THEN COPY(arg, tree)
  ELSE
    Kernel.GetConfig("PORTIA_TREE", tree);
    IF tree = "" THEN
      Oberon.OpenScanner(S, "Portia.Tree");
      IF S.class IN {Texts.Name, Texts.String} THEN COPY(S.s, tree) ELSE Root.Join("arden/", tree) END
    END
  END;
  i := Len(tree); IF (i > 0) & (tree[i-1] # "/") THEN Append(tree, "/") END;
  COPY(tree, path); Append(path, "tools/base.toml");
  IF ~ReadFile(path, buf) THEN out.String("genarden: no "); out.String(path); out.Ln; RETURN END;
  doc := TOML.Parse(buf^);
  IF doc.errors > 0 THEN out.String("genarden: "); out.String(path); out.Char(":"); out.Int(doc.errorLine, 0); out.String(": "); out.String(doc.error); out.Ln; RETURN END;
  packages := NIL; last := NIL; s := doc.first;
  WHILE s # NIL DO
    IF s.name # "" THEN
      NEW(p); COPY(s.name, p.name); p.sec := s; p.match := Items(s, "match"); p.sources := NIL; p.next := NIL;
      IF last = NIL THEN packages := p ELSE last.next := p END; last := p
    END;
    s := s.next
  END;
  i := 0; WHILE i < MaxArchs DO links[i] := ""; INC(i) END;
  Recipe("build", 0, TRUE); Recipe("arm-cross", 0, FALSE); Recipe("rop2-cross", 0, FALSE);
  Recipe("arm", 1, TRUE); Recipe("riscv", 2, TRUE); Recipe("mips", 3, TRUE); Recipe("armv7", 4, TRUE);
  p := packages;  (* sources not in the recipes, on every architecture *)
  WHILE p # NIL DO
    it := Items(p.sec, "extra");
    WHILE it # NIL DO
      IF Prefix(it.s, "/x ") THEN
        i := 0; WHILE it.s[i+3] # 0X DO path[i] := it.s[i+3]; INC(i) END; path[i] := 0X;
        i := 0; WHILE i < MaxArchs DO AddSource(p, path, SHORT(i), TRUE); INC(i) END
      ELSE i := 0; WHILE i < MaxArchs DO AddSource(p, it.s, SHORT(i), FALSE); INC(i) END
      END;
      it := it.next
    END;
    p := p.next
  END;
  Recipes(others); Claimed(others);
  index := NIL; p := packages; WHILE p # NIL DO Write(p, index); p := p.next END;
  Others(others, index);
  COPY(tree, path); Append(path, "INDEX"); f := Files.New(path); Files.Set(W, f, 0);
  it := index; WHILE it # NIL DO Ws(it.s); Ln; it := it.next END;
  Files.Register(f);
  i := 0; it := index; WHILE it # NIL DO INC(i); it := it.next END;
  out.String("genarden: "); out.Int(i, 0); out.String(" recipes in the INDEX of "); out.String(tree);
  IF problems > 0 THEN out.String(", "); out.Int(problems, 0); out.String(" problems") END;
  out.Ln
END Run;

BEGIN
  archs[0] := "x86"; archs[1] := "arm"; archs[2] := "riscv"; archs[3] := "mips"; archs[4] := "armv7"
END genarden.
