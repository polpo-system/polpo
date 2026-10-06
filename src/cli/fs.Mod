MODULE fs;  (** directories and files of Linux in the console: cd, pwd, ls, mkdir, rm, mv, cp *)

(* fs.Cd [path]              the current directory of loksh (and of Files) becomes path; $HOME
                              without one; ~ at the start is $HOME
   fs.Pwd                    the current directory
   fs.Ls [/l] [/a] [path ...]  the files of the directories (the current one without a path),
                              sorted, directories with "/"; /l with type, size and date (UTC),
                              /a with the names that start with "."
   fs.Mkdir path ...         new directories
   fs.Rm file ...            removes files
   fs.Rmdir path ...         removes empty directories
   fs.Mv old new             renames (moves) a file or directory
   fs.Cp from to             copies a file; into the directory to if it is one
   Commands of loksh run in its process: after fs.Cd, texts.Show name and the other commands
   find plain names in the new directory first (then on the search path of the root). The names
   are used as they are, as by Linux (Files accepts fewer). *)

IMPORT SYSTEM, Linux0, Kernel, Files, texts, out;

CONST
  NameLen = 256; Block = 8192;
  DirType = 4X; LinkType = 0AX;  (* d_type of getdents64 *)
  RemoveDir = 200H;  (* AT_REMOVEDIR *)

TYPE
  Name = ARRAY NameLen OF CHAR;
  Entry = POINTER TO EntryDesc;
  EntryDesc = RECORD name: Name; type: CHAR; next: Entry END;

PROCEDURE Len(VAR s: ARRAY OF CHAR): LONGINT;
VAR i: LONGINT;
BEGIN i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END; RETURN i
END Len;

PROCEDURE Append(VAR s: ARRAY OF CHAR; t: ARRAY OF CHAR);
VAR i, j: LONGINT;
BEGIN
  i := Len(s); j := 0;
  WHILE (t[j] # 0X) & (i < LEN(s) - 1) DO s[i] := t[j]; INC(i); INC(j) END;
  s[i] := 0X
END Append;

PROCEDURE Error(what: ARRAY OF CHAR; VAR name: ARRAY OF CHAR; res: LONGINT);
BEGIN
  out.String("fs: "); out.String(what); out.String(" "); out.String(name);
  IF res = -2 THEN out.String(": no such file or directory")
  ELSIF res = -13 THEN out.String(": permission denied")
  ELSIF res = -17 THEN out.String(": exists")
  ELSIF res = -20 THEN out.String(": not a directory")
  ELSIF res = -21 THEN out.String(": is a directory")
  ELSIF res = -39 THEN out.String(": not empty")
  ELSE out.String(": error "); out.Int(-res, 0)
  END;
  out.Ln
END Error;

(* ~ at the start of path is $HOME *)
PROCEDURE Expand(VAR path: ARRAY OF CHAR);
VAR home, rest: Name; i, j: LONGINT;
BEGIN
  IF (path[0] = "~") & ((path[1] = 0X) OR (path[1] = "/")) THEN
    Kernel.GetConfig("HOME", home); i := 1; j := 0;
    WHILE path[i] # 0X DO rest[j] := path[i]; INC(i); INC(j) END; rest[j] := 0X;
    COPY(home, path); Append(path, rest)
  END
END Expand;

PROCEDURE Cd*;
VAR A: texts.Reader; path: Name; r: LONGINT;
BEGIN
  texts.OpenArgs(A);
  IF ~texts.Arg(A, path) THEN Kernel.GetConfig("HOME", path) END;
  Expand(path);
  r := Linux0.ChDir0(SYSTEM.ADR(path[0]));
  IF r # 0 THEN Error("cd", path, r)
  ELSE Files.SetSYS("."); Files.SetWRK("")  (* plain names of Files in the new directory *)
  END
END Cd;

PROCEDURE Cwd(VAR s: ARRAY OF CHAR);
VAR n: LONGINT; proc: ARRAY 16 OF CHAR;
BEGIN
  proc := "/proc/self/cwd";
  n := Linux0.Readlinkat0(Linux0.ATFDCWD, SYSTEM.ADR(proc[0]), SYSTEM.ADR(s[0]), LEN(s) - 1);
  IF n < 0 THEN n := 0 END; s[n] := 0X
END Cwd;

PROCEDURE Pwd*;
VAR s: ARRAY 1024 OF CHAR;
BEGIN Cwd(s); out.String(s); out.Ln
END Pwd;

(* the entries of the directory path, sorted; FALSE if it is not one (res: the error) *)
PROCEDURE Read(VAR path: ARRAY OF CHAR; all: BOOLEAN; VAR list: Entry; VAR res: LONGINT): BOOLEAN;
VAR fd, n, i, k, rec, r: LONGINT; buf: ARRAY Block OF CHAR; e, p, q: Entry; dir: BOOLEAN;
BEGIN
  list := NIL; dir := FALSE; res := 0;
  fd := Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR(path[0]), Linux0.ORDonly, 0);
  IF fd <= 0 THEN res := fd; RETURN FALSE END;
  LOOP
    n := Linux0.GetDents0(fd, SYSTEM.ADR(buf[0]), LEN(buf));  (* getdents64: length at 16, type at 18, name at 19 *)
    IF n = -20 THEN res := 0 ELSIF n < 0 THEN res := n END;  (* ENOTDIR: a file *)
    IF n <= 0 THEN EXIT END;
    dir := TRUE; i := 0;
    WHILE i < n DO
      rec := ORD(buf[i + 16]) + 256 * LONG(ORD(buf[i + 17]));
      IF all & ~((buf[i + 19] = ".") & ((buf[i + 20] = 0X) OR (buf[i + 20] = ".") & (buf[i + 21] = 0X)))
        OR ~all & (buf[i + 19] # ".") THEN
        NEW(e); k := 0; WHILE (buf[i + 19 + k] # 0X) & (k < NameLen - 1) DO e.name[k] := buf[i + 19 + k]; INC(k) END;
        e.name[k] := 0X; e.type := buf[i + 18];
        IF (list = NIL) OR (e.name < list.name) THEN e.next := list; list := e  (* sorted insertion *)
        ELSE p := list; q := list.next; WHILE (q # NIL) & (q.name < e.name) DO p := q; q := q.next END; e.next := q; p.next := e
        END
      END;
      INC(i, rec)
    END
  END;
  r := Linux0.Close0(fd);
  RETURN dir
END Read;

PROCEDURE Two(n: LONGINT);
BEGIN out.Char(CHR(n DIV 10 MOD 10 + ORD("0"))); out.Char(CHR(n MOD 10 + ORD("0")))
END Two;

(* one line of ls -l for path, shown as name *)
PROCEDURE Long(VAR path, name: ARRAY OF CHAR; type: CHAR);
VAR st: Linux0.Status; t, date, time: LONGINT;
BEGIN
  IF type = DirType THEN out.Char("d") ELSIF type = LinkType THEN out.Char("l") ELSE out.Char("-") END;
  IF Linux0.FStatat0(Linux0.ATFDCWD, SYSTEM.ADR(path[0]), SYSTEM.ADR(st), 0) = 0 THEN
    out.Int(st.size, 12); out.String("  ");
    t := st.mtime; Kernel.U2OTime(t, date, time);
    out.Int(date DIV 512 + 1900, 4); out.Char("-"); Two(date DIV 32 MOD 16); out.Char("-"); Two(date MOD 32);
    out.Char(" "); Two(time DIV 4096); out.Char(":"); Two(time DIV 64 MOD 64)
  ELSE out.String("           ?                  ")
  END;
  out.String("  "); out.String(name); IF type = DirType THEN out.Char("/") END; out.Ln
END Long;

PROCEDURE List(VAR path: ARRAY OF CHAR; long, all, title: BOOLEAN);
VAR list, e: Entry; res, w, cols, col, n, k: LONGINT; full: ARRAY 2 * NameLen OF CHAR;
BEGIN
  IF ~Read(path, all, list, res) THEN
    IF res = 0 THEN  (* a file *)
      IF long THEN Long(path, path, 0X) ELSE out.String(path); out.Ln END
    ELSE Error("ls", path, res)
    END;
    RETURN
  END;
  IF title THEN out.String(path); out.String(":"); out.Ln END;
  IF long THEN
    e := list;
    WHILE e # NIL DO
      COPY(path, full); IF full[Len(full) - 1] # "/" THEN Append(full, "/") END; Append(full, e.name);
      Long(full, e.name, e.type); e := e.next
    END
  ELSE  (* in columns, 80 characters wide *)
    w := 1; e := list; WHILE e # NIL DO n := Len(e.name) + 1; IF n > w THEN w := n END; e := e.next END;
    cols := 80 DIV (w + 2); IF cols < 1 THEN cols := 1 END;
    col := 0; e := list;
    WHILE e # NIL DO
      out.String(e.name); n := Len(e.name); IF e.type = DirType THEN out.Char("/"); INC(n) END;
      INC(col);
      IF (col = cols) OR (e.next = NIL) THEN out.Ln; col := 0
      ELSE k := n; WHILE k < w + 2 DO out.Char(" "); INC(k) END
      END;
      e := e.next
    END
  END
END List;

PROCEDURE Ls*;
VAR A: texts.Reader; arg: Name; paths: ARRAY 64 OF Name; n, i: INTEGER; long, all: BOOLEAN;
BEGIN
  texts.OpenArgs(A); n := 0; long := FALSE; all := FALSE;
  WHILE texts.Arg(A, arg) DO
    (* /l /a /la as other commands (compiler.Compile /s), also -l -a -la; only these words:
       other words starting with "/" are paths *)
    IF (arg = "/l") OR (arg = "-l") THEN long := TRUE ELSIF (arg = "/a") OR (arg = "-a") THEN all := TRUE
    ELSIF (arg = "/la") OR (arg = "/al") OR (arg = "-la") OR (arg = "-al") THEN long := TRUE; all := TRUE
    ELSIF n < LEN(paths) THEN Expand(arg); COPY(arg, paths[n]); INC(n)
    END
  END;
  IF n = 0 THEN paths[0] := "."; n := 1 END;
  i := 0;
  WHILE i < n DO
    IF (i > 0) & (n > 1) THEN out.Ln END;
    List(paths[i], long, all, n > 1); INC(i)
  END
END Ls;

PROCEDURE Mkdir*;
VAR A: texts.Reader; path: Name; r: LONGINT;
BEGIN
  texts.OpenArgs(A);
  WHILE texts.Arg(A, path) DO
    Expand(path); r := Linux0.MkDir0(SYSTEM.ADR(path[0]), 1EDH);  (* 0755 *)
    IF r # 0 THEN Error("mkdir", path, r) END
  END
END Mkdir;

PROCEDURE Remove(flags: LONGINT; what: ARRAY OF CHAR);
VAR A: texts.Reader; path: Name; r: LONGINT;
BEGIN
  texts.OpenArgs(A);
  WHILE texts.Arg(A, path) DO
    Expand(path); r := Linux0.UnLinkat0(Linux0.ATFDCWD, SYSTEM.ADR(path[0]), flags);
    IF r # 0 THEN Error(what, path, r) END
  END
END Remove;

PROCEDURE Rm*;
BEGIN Remove(0, "rm")
END Rm;

PROCEDURE Rmdir*;
BEGIN Remove(RemoveDir, "rmdir")
END Rmdir;

(* to/the file name of from, if to is a directory *)
PROCEDURE Target(VAR from, to: ARRAY OF CHAR);
VAR list: Entry; res, i, k: LONGINT;
BEGIN
  IF Read(to, TRUE, list, res) THEN
    k := 0; i := 0; WHILE from[i] # 0X DO IF from[i] = "/" THEN k := i + 1 END; INC(i) END;
    IF to[Len(to) - 1] # "/" THEN Append(to, "/") END;
    i := Len(to); WHILE (from[k] # 0X) & (i < LEN(to) - 1) DO to[i] := from[k]; INC(i); INC(k) END; to[i] := 0X
  END
END Target;

PROCEDURE Mv*;
VAR A: texts.Reader; old, new: Name; r: LONGINT;
BEGIN
  texts.OpenArgs(A);
  IF ~texts.Arg(A, old) OR ~texts.Arg(A, new) THEN out.String("usage: fs.Mv old new"); out.Ln; RETURN END;
  Expand(old); Expand(new); Target(old, new);
  r := Linux0.Renameat0(Linux0.ATFDCWD, SYSTEM.ADR(old[0]), Linux0.ATFDCWD, SYSTEM.ADR(new[0]), 0);
  IF r # 0 THEN Error("mv", old, r) END
END Mv;

PROCEDURE Cp*;
VAR A: texts.Reader; from, to: Name; in, dst, n, w, r, total: LONGINT; buf: ARRAY Block OF CHAR;
BEGIN
  texts.OpenArgs(A);
  IF ~texts.Arg(A, from) OR ~texts.Arg(A, to) THEN out.String("usage: fs.Cp from to"); out.Ln; RETURN END;
  Expand(from); Expand(to); Target(from, to);
  in := Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR(from[0]), Linux0.ORDonly, 0);
  IF in <= 0 THEN Error("cp", from, in); RETURN END;
  dst := Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR(to[0]), Linux0.OWRonly + Linux0.OCREAT + Linux0.OTRUNC, 1A4H);  (* 0644 *)
  IF dst <= 0 THEN Error("cp", to, dst); r := Linux0.Close0(in); RETURN END;
  total := 0;
  LOOP
    n := Linux0.Read0(in, SYSTEM.ADR(buf[0]), LEN(buf));
    IF n < 0 THEN Error("cp: reading", from, n); EXIT END;
    IF n = 0 THEN EXIT END;
    w := Linux0.Write0(dst, SYSTEM.ADR(buf[0]), n);
    IF w # n THEN Error("cp: writing", to, w); EXIT END;
    INC(total, n)
  END;
  r := Linux0.Close0(in); r := Linux0.Close0(dst)
END Cp;

END fs.
