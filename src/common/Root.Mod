MODULE Root;  (** polpo installation root: where bin/, obj/, share/, tools/, fonts/ are *)

(* The root is found once, at startup:
     1. the environment variable POLPO, if set;
     2. otherwise the executable /proc/self/exe = <root>/bin/<arch>/loksh;
     3. otherwise argv[0], if it contains a "/".
   path is the root with a trailing "/", or "" when it is unknown (the current directory).
   Obj gives the object directory of an architecture: obj/<arch>/ in the current directory
   if it exists there, else in the root; so running from the polpo directory is unchanged.
   RootObj always gives the one in the root: the module loaders look there for modules
   that are not in a local obj/<arch>/, so a directory of your own objects is possible. *)

  IMPORT Linux0, Kernel, SYSTEM;

  CONST PathLen = 256;

  VAR path*: ARRAY PathLen OF CHAR;  (** root directory with trailing "/", or "" *)

  PROCEDURE Length(VAR s: ARRAY OF CHAR): LONGINT;
    VAR i: LONGINT;
  BEGIN
    i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END;
    RETURN i
  END Length;

  PROCEDURE Append(VAR s: ARRAY OF CHAR; t: ARRAY OF CHAR);
    VAR i, j: LONGINT;
  BEGIN
    i := Length(s); j := 0;
    WHILE (t[j] # 0X) & (i < LEN(s)-1) DO s[i] := t[j]; INC(i); INC(j) END;
    s[i] := 0X
  END Append;

  (* Remove the last n components of the file name s and keep a trailing "/".
     s becomes "" if it has no directory part left. *)
  PROCEDURE Strip(VAR s: ARRAY OF CHAR; n: INTEGER);
    VAR i: LONGINT;
  BEGIN
    WHILE n > 0 DO
      i := Length(s) - 1;
      WHILE (i >= 0) & (s[i] # "/") DO DEC(i) END;
      IF i < 0 THEN s[0] := 0X; n := 0
      ELSIF i = 0 THEN s[1] := 0X; n := 0  (* root directory "/" *)
      ELSE s[i] := 0X; DEC(n)
      END
    END;
    i := Length(s);
    IF (i > 0) & (s[i-1] # "/") & (i < LEN(s)-1) THEN s[i] := "/"; s[i+1] := 0X END
  END Strip;

  (** Does the file or directory name exist, relative to the current directory? *)
  PROCEDURE Exists*(name: ARRAY OF CHAR): BOOLEAN;
    VAR fd, res: LONGINT;
  BEGIN
    fd := Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR(name[0]), Linux0.ORDonly, 0);
    IF fd > 0 THEN res := Linux0.Close0(fd); RETURN TRUE END;
    RETURN FALSE
  END Exists;

  (** name in the root directory: path + name *)
  PROCEDURE Join*(name: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);
  BEGIN
    COPY(path, s); Append(s, name)
  END Join;

  (** Object directory of arch: "obj/<arch>/" if it exists in the current directory,
    else in the root. *)
  PROCEDURE Obj*(arch: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);
    VAR local: ARRAY 64 OF CHAR;
  BEGIN
    local := "obj/"; Append(local, arch);
    IF Exists(local) OR (path[0] = 0X) THEN COPY(local, s) ELSE Join(local, s) END;
    Append(s, "/")
  END Obj;

  (** Object directory of arch in the root: "<root>obj/<arch>/", or "obj/<arch>/" when the
    root is unknown. *)
  PROCEDURE RootObj*(arch: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);
    VAR local: ARRAY 64 OF CHAR;
  BEGIN
    local := "obj/"; Append(local, arch); Append(local, "/");
    Join(local, s)
  END RootObj;

  PROCEDURE Init;
    VAR s: ARRAY PathLen OF CHAR; n, i: LONGINT;
  BEGIN
    Kernel.GetConfig("POLPO", s);
    IF s[0] # 0X THEN
      COPY(s, path); n := Length(path);
      IF (path[n-1] # "/") & (n < LEN(path)-1) THEN path[n] := "/"; path[n+1] := 0X END
    ELSE
      n := Linux0.Readlinkat0(Linux0.ATFDCWD, SYSTEM.ADR("/proc/self/exe"), SYSTEM.ADR(s[0]), LEN(s)-1);
      IF n > 0 THEN
        s[n] := 0X
      ELSE
        Kernel.GetArg(0, s);
        i := 0; WHILE (s[i] # 0X) & (s[i] # "/") DO INC(i) END;
        IF s[i] # "/" THEN s[0] := 0X END
      END;
      IF s[0] # 0X THEN Strip(s, 3) END;  (* <root>/bin/<arch>/loksh *)
      COPY(s, path)
    END;
    IF (path[0] # 0X) & (path[0] # "/") THEN  (* relative (qemu-user gives the exe as typed): absolute, so a chdir keeps it *)
      n := Linux0.Readlinkat0(Linux0.ATFDCWD, SYSTEM.ADR("/proc/self/cwd"), SYSTEM.ADR(s[0]), LEN(s)-2);
      IF n > 0 THEN
        s[n] := "/"; s[n+1] := 0X;
        IF (path[0] = ".") & (path[1] = "/") THEN i := 2 ELSE i := 0 END;
        n := Length(s); WHILE (path[i] # 0X) & (n < LEN(s)-1) DO s[n] := path[i]; INC(n); INC(i) END; s[n] := 0X;
        COPY(s, path)
      END
    END
  END Init;

BEGIN
  Init
END Root.
