MODULE tar;  (** tar archives, plain or gzip compressed, in the console *)

(* tar.List archive               the entries of the archive
   tar.Unpack archive dir [n]     its files and directories into dir, without the first n
                                  components of their paths (n = 1 for the archives of GitHub,
                                  which have everything in name-branch/)
   tar.Pack archive path ...      the files, and the directories with everything in them, into a
                                  new archive; gzip compressed when its name ends with .gz or .tgz
   An archive starting with 1FX 8BX is read through gzip (GZReaders). Ustar, the pax headers of
   GitHub (path=) and GNU long names (L) are understood; links and devices are skipped, and so
   are entries that would land outside dir. Pack writes ustar, with GNU long names for paths of
   more than 100 characters that no prefix splits; the archives are those of tar and tar -z. *)

IMPORT SYSTEM, Linux0, Files, GZReaders, GZWriters, texts, out;

CONST Block = 512; NameLen = 256;

TYPE
  Name = ARRAY NameLen OF CHAR;
  Entry = POINTER TO EntryDesc;  (* a name in a directory, for Pack *)
  EntryDesc = RECORD name: Name; next: Entry END;

VAR
  gz: BOOLEAN; zr: GZReaders.Reader; fr: Files.Rider;  (* the archive *)
  eof: BOOLEAN;
  zw: GZWriters.Writer; aw: Files.Rider;  (* the archive written by Pack *)
  packed, dirsPacked: LONGINT; ok: BOOLEAN;

PROCEDURE Open(VAR name: ARRAY OF CHAR): BOOLEAN;
VAR f: Files.File; c0, c1: CHAR;
BEGIN
  f := Files.Old(name);
  IF f = NIL THEN out.String("tar: no "); out.String(name); out.Ln; RETURN FALSE END;
  Files.Set(fr, f, 0); Files.Read(fr, c0); Files.Read(fr, c1);
  gz := (c0 = 1FX) & (c1 = 8BX); eof := FALSE;
  IF gz THEN GZReaders.Open(zr, f) ELSE Files.Set(fr, f, 0) END;
  RETURN TRUE
END Open;

(* the next n bytes (at most LEN(buf)); FALSE at the end *)
PROCEDURE Read(VAR buf: ARRAY OF CHAR; n: LONGINT): BOOLEAN;
VAR got: LONGINT;
BEGIN
  IF gz THEN GZReaders.ReadBytes(zr, buf, 0, n, got)
  ELSE Files.ReadBytes(fr, buf, n); got := n - fr.res
  END;
  IF got < n THEN eof := TRUE END;
  RETURN got = n
END Read;

PROCEDURE Skip(n: LONGINT);  (* n bytes and the padding to the next block *)
VAR buf: ARRAY Block OF CHAR; k: LONGINT;
BEGIN
  n := (n + Block - 1) DIV Block * Block;
  WHILE (n > 0) & ~eof DO k := n; IF k > Block THEN k := Block END; IF Read(buf, k) THEN END; DEC(n, k) END
END Skip;

PROCEDURE Octal(VAR h: ARRAY OF CHAR; pos, len: INTEGER): LONGINT;
VAR n: LONGINT; i: INTEGER;
BEGIN
  n := 0; i := pos; WHILE (i < pos + len) & (h[i] = " ") DO INC(i) END;
  WHILE (i < pos + len) & (h[i] >= "0") & (h[i] <= "7") DO n := n * 8 + ORD(h[i]) - ORD("0"); INC(i) END;
  RETURN n
END Octal;

PROCEDURE Str(VAR h: ARRAY OF CHAR; pos, len: INTEGER; VAR s: ARRAY OF CHAR);
VAR i: INTEGER;
BEGIN i := 0; WHILE (i < len) & (h[pos + i] # 0X) DO s[i] := h[pos + i]; INC(i) END; s[i] := 0X
END Str;

PROCEDURE Append(VAR s: ARRAY OF CHAR; t: ARRAY OF CHAR);
VAR i, j: LONGINT;
BEGIN
  i := 0; WHILE s[i] # 0X DO INC(i) END;
  j := 0; WHILE (t[j] # 0X) & (i < LEN(s) - 1) DO s[i] := t[j]; INC(i); INC(j) END;
  s[i] := 0X
END Append;

PROCEDURE MakeDirs(VAR full: ARRAY OF CHAR);  (* the directories of the path full; full itself too if it ends with "/" *)
VAR i, r: LONGINT; dir: Name;
BEGIN
  dir[0] := full[0]; i := 1;
  WHILE (full[i] # 0X) & (i < NameLen - 1) DO
    IF full[i] = "/" THEN dir[i] := 0X; r := Linux0.MkDir0(SYSTEM.ADR(dir), 1EDH) END;
    dir[i] := full[i]; INC(i)
  END
END MakeDirs;

(* name without its first n components; FALSE if nothing is left *)
PROCEDURE Strip(VAR name: ARRAY OF CHAR; n: INTEGER): BOOLEAN;
VAR i, j: INTEGER;
BEGIN
  i := 0;
  WHILE n > 0 DO
    WHILE (name[i] # 0X) & (name[i] # "/") DO INC(i) END;
    IF name[i] = "/" THEN INC(i) END;
    DEC(n)
  END;
  j := 0; WHILE name[i] # 0X DO name[j] := name[i]; INC(i); INC(j) END; name[j] := 0X;
  RETURN name[0] # 0X
END Strip;

(* the value of key=... in the pax records of buf[0..n) into val *)
PROCEDURE Pax(VAR buf: ARRAY OF CHAR; n: LONGINT; key: ARRAY OF CHAR; VAR val: ARRAY OF CHAR);
VAR i, j, k, len, rec: LONGINT;
BEGIN
  i := 0;
  WHILE i < n DO  (* "len key=value\n" *)
    rec := i; len := 0; WHILE (i < n) & (buf[i] >= "0") & (buf[i] <= "9") DO len := len * 10 + ORD(buf[i]) - ORD("0"); INC(i) END;
    IF len <= 0 THEN RETURN END;
    INC(i); k := 0; WHILE (key[k] # 0X) & (i + k < n) & (buf[i + k] = key[k]) DO INC(k) END;
    IF (key[k] = 0X) & (buf[i + k] = "=") THEN
      i := i + k + 1; j := 0; WHILE (i < rec + len - 1) & (j < LEN(val) - 1) DO val[j] := buf[i]; INC(i); INC(j) END; val[j] := 0X
    END;
    i := rec + len
  END
END Pax;

(* a path that stays below the current directory: not absolute, no ".." component *)
PROCEDURE Safe(VAR path: ARRAY OF CHAR): BOOLEAN;
VAR i: LONGINT;
BEGIN
  IF path[0] = "/" THEN RETURN FALSE END;
  i := 0;
  WHILE path[i] # 0X DO
    IF (path[i] = ".") & (path[i+1] = ".") & ((i = 0) OR (path[i-1] = "/")) & ((path[i+2] = "/") OR (path[i+2] = 0X)) THEN RETURN FALSE END;
    INC(i)
  END;
  RETURN TRUE
END Safe;

(* through the archive: list the entries, or extract them into dir *)
PROCEDURE Walk(VAR archive, dir: ARRAY OF CHAR; strip: INTEGER; extract: BOOLEAN);
VAR h: ARRAY Block OF CHAR; buf: ARRAY 8192 OF CHAR; name, long, prefix, full: Name; size, k, n, files, dirs: LONGINT;
  type: CHAR; f: Files.File; w: Files.Rider; zero: INTEGER; i: INTEGER;
BEGIN
  IF ~Open(archive) THEN RETURN END;
  long := ""; files := 0; dirs := 0; zero := 0;
  LOOP
    IF ~Read(h, Block) THEN EXIT END;
    IF h[0] = 0X THEN INC(zero); IF zero = 2 THEN EXIT END
    ELSE
      zero := 0; type := h[156]; size := Octal(h, 124, 12);
      Str(h, 0, 100, name);
      IF (h[257] = "u") & (h[258] = "s") & (h[259] = "t") & (h[260] = "a") & (h[261] = "r") THEN
        Str(h, 345, 155, prefix); IF prefix # "" THEN Append(prefix, "/"); Append(prefix, name); COPY(prefix, name) END
      END;
      IF long # "" THEN COPY(long, name); long := "" END;
      IF (type = "x") OR (type = "L") THEN  (* the name of the next entry *)
        IF size <= LEN(buf) THEN
          IF Read(buf, size) THEN END;
          n := (size + Block - 1) DIV Block * Block - size; IF n > 0 THEN IF Read(h, n) THEN END END;  (* the padding *)
          IF type = "x" THEN Pax(buf, size, "path", long)
          ELSE i := 0; WHILE (i < size) & (buf[i] # 0X) & (i < NameLen - 1) DO long[i] := buf[i]; INC(i) END; long[i] := 0X
          END
        ELSE Skip(size)
        END
      ELSIF (type = "g") OR ~extract & (type # "0") & (type # 0X) & (type # "5") THEN Skip(size)
      ELSIF (type = "0") OR (type = 0X) OR (type = "7") THEN  (* a file *)
        IF ~extract THEN out.String(name); out.String("  "); out.Int(size, 0); out.Ln; Skip(size)
        ELSIF Strip(name, strip) & ~Safe(name) THEN out.String("tar: skipped "); out.String(name); out.String(", outside the directory"); out.Ln; Skip(size)
        ELSIF Strip(name, 0) THEN
          COPY(dir, full); Append(full, name); MakeDirs(full);
          f := Files.New(full); Files.Set(w, f, 0); k := size;
          WHILE (k > 0) & ~eof DO
            n := k; IF n > LEN(buf) THEN n := LEN(buf) END;
            IF Read(buf, n) THEN END; Files.WriteBytes(w, buf, n); DEC(k, n)
          END;
          Files.Register(f); INC(files);
          n := (size + Block - 1) DIV Block * Block - size; IF n > 0 THEN IF Read(h, n) THEN END END
        ELSE Skip(size)
        END
      ELSIF type = "5" THEN  (* a directory *)
        IF ~extract THEN out.String(name); out.Ln
        ELSIF Strip(name, strip) & Safe(name) THEN COPY(dir, full); Append(full, name); MakeDirs(full); INC(dirs)
        END;
        Skip(size)
      ELSE Skip(size)  (* links, devices, fifos *)
      END
    END
  END;
  IF gz THEN GZReaders.Close(zr) END;
  IF extract THEN
    out.String("tar: "); out.Int(files, 0); out.String(" files, "); out.Int(dirs, 0); out.String(" directories in "); out.String(dir); out.Ln
  END
END Walk;

PROCEDURE List*;
VAR A: texts.Reader; archive, dir: Name;
BEGIN
  texts.OpenArgs(A);
  IF ~texts.Arg(A, archive) THEN out.String("usage: tar.List archive"); out.Ln; RETURN END;
  dir := ""; Walk(archive, dir, 0, FALSE)
END List;

PROCEDURE Unpack*;
VAR A: texts.Reader; archive, dir, n: Name; strip, i: INTEGER;
BEGIN
  texts.OpenArgs(A);
  IF ~texts.Arg(A, archive) OR ~texts.Arg(A, dir) THEN out.String("usage: tar.Unpack archive dir [n]"); out.Ln; RETURN END;
  strip := 0;
  IF texts.Arg(A, n) THEN i := 0; WHILE (n[i] >= "0") & (n[i] <= "9") DO strip := strip * 10 + ORD(n[i]) - ORD("0"); INC(i) END END;
  i := 0; WHILE dir[i] # 0X DO INC(i) END; IF (i > 0) & (dir[i-1] # "/") THEN Append(dir, "/") END;
  Walk(archive, dir, strip, TRUE)
END Unpack;

(* Pack *)

PROCEDURE Emit(VAR buf: ARRAY OF CHAR; n: LONGINT);
VAR written: LONGINT;
BEGIN
  IF gz THEN GZWriters.WriteBytes(zw, buf, 0, n, written) ELSE Files.WriteBytes(aw, buf, n) END
END Emit;

PROCEDURE Len(VAR s: ARRAY OF CHAR): LONGINT;
VAR i: LONGINT;
BEGIN i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END; RETURN i
END Len;

PROCEDURE PutOctal(VAR h: ARRAY OF CHAR; pos, len: INTEGER; n: LONGINT);  (* len - 1 digits and 0X *)
VAR i: INTEGER;
BEGIN
  h[pos + len - 1] := 0X; i := pos + len - 2;
  WHILE i >= pos DO h[i] := CHR(n MOD 8 + ORD("0")); n := n DIV 8; DEC(i) END
END PutOctal;

PROCEDURE PutStr(VAR h: ARRAY OF CHAR; pos, len: INTEGER; VAR s: ARRAY OF CHAR; from: LONGINT);
VAR i: INTEGER;
BEGIN i := 0; WHILE (i < len) & (s[from + i] # 0X) DO h[pos + i] := s[from + i]; INC(i) END
END PutStr;

(* a header block for name (type "0", "5" or "L") *)
PROCEDURE Header(VAR name: ARRAY OF CHAR; type: CHAR; size, mtime: LONGINT);
VAR h, lb: ARRAY Block OF CHAR; i, n, split, sum: LONGINT; long, magic: Name;
BEGIN
  n := Len(name);
  IF (n > 100) & (type # "L") THEN  (* a prefix of at most 155 characters ending before a "/", or a long name first *)
    split := n - 101; WHILE (split < n) & ((split < 0) OR (name[split] # "/")) DO INC(split) END;
    IF (split >= n) OR (split > 155) THEN
      long := "././@LongLink"; Header(long, "L", n + 1, 0);  (* the name, in a block (it has less than 256 characters) *)
      i := 0; WHILE i < Block DO lb[i] := 0X; INC(i) END; i := 0; WHILE i < n DO lb[i] := name[i]; INC(i) END;
      Emit(lb, Block);
      split := -1
    END
  ELSE split := -1
  END;
  i := 0; WHILE i < Block DO h[i] := 0X; INC(i) END;
  IF split > 0 THEN
    i := 0; WHILE i < split DO h[345 + i] := name[i]; INC(i) END;
    PutStr(h, 0, 100, name, split + 1)
  ELSE PutStr(h, 0, 100, name, 0)
  END;
  IF type = "5" THEN PutOctal(h, 100, 8, 1EDH) ELSE PutOctal(h, 100, 8, 1A4H) END;  (* 0755, 0644 *)
  PutOctal(h, 108, 8, 0); PutOctal(h, 116, 8, 0); PutOctal(h, 124, 12, size); PutOctal(h, 136, 12, mtime);
  h[156] := type; magic := "ustar"; PutStr(h, 257, 6, magic, 0); h[263] := "0"; h[264] := "0";
  i := 148; WHILE i < 156 DO h[i] := " "; INC(i) END;
  sum := 0; i := 0; WHILE i < Block DO sum := sum + ORD(h[i]); INC(i) END;
  PutOctal(h, 148, 7, sum); h[155] := " ";
  Emit(h, Block)
END Header;

PROCEDURE MTime(VAR path: ARRAY OF CHAR): LONGINT;
VAR st: Linux0.Status;
BEGIN
  IF Linux0.FStatat0(Linux0.ATFDCWD, SYSTEM.ADR(path[0]), SYSTEM.ADR(st), 0) = 0 THEN RETURN st.mtime ELSE RETURN 0 END
END MTime;

(* the entries of the directory path, NIL if it is not one (or empty); dir: it is a directory *)
PROCEDURE Entries(VAR path: ARRAY OF CHAR; VAR dir: BOOLEAN): Entry;
VAR fd, n, i, r, rec: LONGINT; buf: ARRAY 8192 OF CHAR; list, e: Entry; k: LONGINT;
BEGIN
  list := NIL; dir := FALSE;
  fd := Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR(path[0]), Linux0.ORDonly, 0);
  IF fd <= 0 THEN RETURN NIL END;
  LOOP
    n := Linux0.GetDents0(fd, SYSTEM.ADR(buf[0]), LEN(buf));  (* getdents64: the length at 16, the name at 19 *)
    IF n <= 0 THEN EXIT END;
    dir := TRUE; i := 0;
    WHILE i < n DO
      rec := ORD(buf[i + 16]) + 256 * LONG(ORD(buf[i + 17]));
      IF ~((buf[i + 19] = ".") & ((buf[i + 20] = 0X) OR (buf[i + 20] = ".") & (buf[i + 21] = 0X))) THEN
        NEW(e); k := 0; WHILE (buf[i + 19 + k] # 0X) & (k < NameLen - 1) DO e.name[k] := buf[i + 19 + k]; INC(k) END; e.name[k] := 0X;
        e.next := list; list := e
      END;
      INC(i, rec)
    END
  END;
  r := Linux0.Close0(fd);
  RETURN list
END Entries;

(* the entries of a directory in the order of their names, the list reversed by Entries *)
PROCEDURE Sort(e: Entry): Entry;
VAR s, p, q, next: Entry;
BEGIN
  s := NIL;
  WHILE e # NIL DO
    next := e.next;
    IF (s = NIL) OR (e.name < s.name) THEN e.next := s; s := e
    ELSE p := s; q := s.next; WHILE (q # NIL) & (q.name < e.name) DO p := q; q := q.next END; e.next := q; p.next := e
    END;
    e := next
  END;
  RETURN s
END Sort;

(* path into the archive: a file, or a directory and everything in it *)
PROCEDURE Pack1(VAR path: ARRAY OF CHAR);
VAR e: Entry; dir: BOOLEAN; f: Files.File; r: Files.Rider; buf: ARRAY 8192 OF CHAR; sub: Name; size, k, n: LONGINT; st: Linux0.Status;
BEGIN
  IF ~ok THEN RETURN END;
  IF Linux0.FStatat0(Linux0.ATFDCWD, SYSTEM.ADR(path[0]), SYSTEM.ADR(st), 0) # 0 THEN
    out.String("tar: no "); out.String(path); out.Ln; RETURN
  END;
  e := Sort(Entries(path, dir));
  IF dir THEN
    COPY(path, sub); IF sub[Len(sub) - 1] # "/" THEN Append(sub, "/") END;
    Header(sub, "5", 0, MTime(path)); INC(dirsPacked);
    WHILE e # NIL DO  (* in the order of the names *)
      COPY(path, sub); IF sub[Len(sub) - 1] # "/" THEN Append(sub, "/") END; Append(sub, e.name);
      IF Len(sub) >= NameLen - 1 THEN out.String("tar: skipped, too long: "); out.String(sub); out.Ln ELSE Pack1(sub) END;
      e := e.next
    END
  ELSE
    f := Files.Old(path);
    IF f = NIL THEN out.String("tar: cannot read "); out.String(path); out.Ln; RETURN END;
    size := Files.Length(f); Header(path, "0", size, MTime(path)); Files.Set(r, f, 0); k := size;
    WHILE k > 0 DO
      n := k; IF n > LEN(buf) THEN n := LEN(buf) END;
      Files.ReadBytes(r, buf, n); Emit(buf, n); DEC(k, n)
    END;
    n := (size + Block - 1) DIV Block * Block - size;
    IF n > 0 THEN k := 0; WHILE k < n DO buf[k] := 0X; INC(k) END; Emit(buf, n) END;
    INC(packed)
  END
END Pack1;


PROCEDURE Pack*;
VAR A: texts.Reader; archive, path: Name; g: Files.File; n, k: LONGINT; zero: ARRAY Block OF CHAR;
BEGIN
  texts.OpenArgs(A);
  IF ~texts.Arg(A, archive) THEN out.String("usage: tar.Pack archive[.gz|.tgz] path ..."); out.Ln; RETURN END;
  n := Len(archive);
  gz := (n > 3) & (archive[n-3] = ".") & (archive[n-2] = "g") & (archive[n-1] = "z")
    OR (n > 4) & (archive[n-4] = ".") & (archive[n-3] = "t") & (archive[n-2] = "g") & (archive[n-1] = "z");
  g := Files.New(archive);
  IF gz THEN GZWriters.Open(zw, GZWriters.DefaultCompression, GZWriters.DefaultStrategy, g) ELSE Files.Set(aw, g, 0) END;
  packed := 0; dirsPacked := 0; ok := TRUE;
  WHILE texts.Arg(A, path) DO Pack1(path) END;
  k := 0; WHILE k < Block DO zero[k] := 0X; INC(k) END;
  Emit(zero, Block); Emit(zero, Block);
  IF gz THEN GZWriters.Close(zw); ok := zw.res = GZWriters.Ok END;
  IF ok THEN
    Files.Register(g); out.String("tar: "); out.String(archive); out.String(", "); out.Int(packed, 0); out.String(" files, ");
    out.Int(dirsPacked, 0); out.String(" directories"); out.Ln
  ELSE out.String("tar: writing "); out.String(archive); out.String(" failed"); out.Ln
  END
END Pack;

END tar.
