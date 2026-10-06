MODULE FilesHost;  (* the host files of oocFiles, on Files of polpo (voc: Platform) *)

(* A handle is a file of Files with a position. Files maps files into memory: what is written
   reaches the disk with Sync and Close (Files.Close). Plain names are taken in the current
   directory ("./name"): Files.Old looks for plain names on the search path of the root too. *)

IMPORT SYSTEM, Linux0, Files;

CONST
  ok = 0; absent = 2; inaccessible = 13; tooMany = 24; failed = 5;  (* errno values *)
  maxPath = 1024;

TYPE
  Byte* = SYSTEM.BYTE;
  Handle* = POINTER TO HandleDesc;
  HandleDesc = RECORD
    f: Files.File;
    pos: LONGINT;
    name: ARRAY maxPath OF CHAR
  END;
  Error* = INTEGER;

PROCEDURE Absent* (error: Error): BOOLEAN;
BEGIN RETURN error = absent
END Absent;

PROCEDURE TooManyFiles* (error: Error): BOOLEAN;
BEGIN RETURN error = tooMany
END TooManyFiles;

PROCEDURE Inaccessible* (error: Error): BOOLEAN;
BEGIN RETURN error = inaccessible
END Inaccessible;

(* name with "./" before a plain name *)
PROCEDURE Local(VAR name, local: ARRAY OF CHAR);
VAR i, j: LONGINT; slash: BOOLEAN;
BEGIN
  i := 0; slash := FALSE; WHILE name[i] # 0X DO IF name[i] = "/" THEN slash := TRUE END; INC(i) END;
  IF slash THEN COPY(name, local)
  ELSE
    local[0] := "."; local[1] := "/"; j := 0;
    WHILE (name[j] # 0X) & (j + 2 < LEN(local) - 1) DO local[j + 2] := name[j]; INC(j) END;
    local[j + 2] := 0X
  END
END Local;

PROCEDURE Exists* (VAR name: ARRAY OF CHAR): BOOLEAN;
VAR st: Linux0.Status; local: ARRAY maxPath OF CHAR;
BEGIN
  Local(name, local);
  RETURN Linux0.FStatat0(Linux0.ATFDCWD, SYSTEM.ADR(local[0]), SYSTEM.ADR(st), 0) = 0
END Exists;

PROCEDURE New* (VAR name: ARRAY OF CHAR; VAR handle: Handle): Error;
VAR f: Files.File; local: ARRAY maxPath OF CHAR;
BEGIN
  Local(name, local); f := Files.New(local);
  IF f = NIL THEN handle := NIL; RETURN inaccessible END;
  Files.Register(f);  (* on the disk now, as open(O_CREAT|O_TRUNC) *)
  NEW(handle); handle.f := f; handle.pos := 0; COPY(local, handle.name);
  RETURN ok
END New;

PROCEDURE Open(VAR name: ARRAY OF CHAR; VAR handle: Handle): Error;
VAR f: Files.File; local: ARRAY maxPath OF CHAR;
BEGIN
  Local(name, local);
  IF ~Exists(name) THEN handle := NIL; RETURN absent END;
  f := Files.Old(local);
  IF f = NIL THEN handle := NIL; RETURN inaccessible END;
  NEW(handle); handle.f := f; handle.pos := 0; COPY(local, handle.name);
  RETURN ok
END Open;

PROCEDURE OpenReadOnly* (VAR name: ARRAY OF CHAR; VAR handle: Handle): Error;
BEGIN RETURN Open(name, handle)
END OpenReadOnly;

PROCEDURE OpenReadWrite* (VAR name: ARRAY OF CHAR; VAR handle: Handle): Error;
BEGIN RETURN Open(name, handle)
END OpenReadWrite;

PROCEDURE Close* (handle: Handle): Error;
BEGIN
  IF handle.f # NIL THEN Files.Close(handle.f); handle.f := NIL END;
  RETURN ok
END Close;

PROCEDURE Size* (handle: Handle; VAR length: LONGINT): Error;
BEGIN length := Files.Length(handle.f); RETURN ok
END Size;

PROCEDURE Seek* (handle: Handle; position: LONGINT): Error;
BEGIN handle.pos := position; RETURN ok
END Seek;

PROCEDURE ReadByte* (handle: Handle; VAR x: Byte; VAR count: LONGINT): Error;
VAR r: Files.Rider;
BEGIN
  IF handle.pos >= Files.Length(handle.f) THEN count := 0
  ELSE Files.Set(r, handle.f, handle.pos); Files.Read(r, x); INC(handle.pos); count := 1
  END;
  RETURN ok
END ReadByte;

PROCEDURE ReadBytes* (handle: Handle; VAR x: ARRAY OF Byte;
                      start, n: LONGINT; VAR count: LONGINT): Error;
VAR r: Files.Rider; i, len: LONGINT;
BEGIN
  len := Files.Length(handle.f) - handle.pos; IF n > len THEN n := len END;
  IF n < 0 THEN n := 0 END;
  Files.Set(r, handle.f, handle.pos); i := 0;
  WHILE i < n DO Files.Read(r, x[start + i]); INC(i) END;
  INC(handle.pos, n); count := n;
  RETURN ok
END ReadBytes;

PROCEDURE WriteByte* (handle: Handle; x: Byte): Error;
VAR r: Files.Rider;
BEGIN
  Files.Set(r, handle.f, handle.pos); Files.Write(r, x); INC(handle.pos);
  RETURN ok
END WriteByte;

PROCEDURE WriteBytes* (handle: Handle; VAR x: ARRAY OF Byte;
                       start, n: LONGINT): Error;
VAR r: Files.Rider; i: LONGINT;
BEGIN
  Files.Set(r, handle.f, handle.pos); i := 0;
  WHILE i < n DO Files.Write(r, x[start + i]); INC(i) END;
  INC(handle.pos, n);
  RETURN ok
END WriteBytes;

PROCEDURE Sync* (handle: Handle): Error;
BEGIN Files.Close(handle.f); RETURN ok  (* Files.Close writes the changes and keeps the file *)
END Sync;

(* Files cannot shorten a file: a new one with its first length bytes (zeros after the end)
   replaces it under the same name *)
PROCEDURE Truncate* (handle: Handle; length: LONGINT): Error;
VAR g: Files.File; r, w: Files.Rider; i, old: LONGINT; ch: CHAR;
BEGIN
  old := Files.Length(handle.f);
  IF length = old THEN RETURN ok END;
  g := Files.New(handle.name);
  IF g = NIL THEN RETURN failed END;
  Files.Set(r, handle.f, 0); Files.Set(w, g, 0); i := 0;
  WHILE i < length DO
    IF i < old THEN Files.Read(r, ch) ELSE ch := 0X END;
    Files.Write(w, ch); INC(i)
  END;
  Files.Register(g); handle.f := g;
  RETURN ok
END Truncate;

PROCEDURE Remove* (VAR name: ARRAY OF CHAR): Error;
VAR res: INTEGER; local: ARRAY maxPath OF CHAR;
BEGIN
  Local(name, local); Files.Delete(local, res);
  IF res = 0 THEN RETURN ok ELSIF ~Exists(name) THEN RETURN absent ELSE RETURN inaccessible END
END Remove;

PROCEDURE Rename* (VAR oldName, newName: ARRAY OF CHAR): Error;
VAR res: INTEGER; old, new: ARRAY maxPath OF CHAR;
BEGIN
  Local(oldName, old); Local(newName, new); Files.Rename(old, new, res);
  IF res = 0 THEN RETURN ok ELSIF ~Exists(oldName) THEN RETURN absent ELSE RETURN inaccessible END
END Rename;

(* the time and date of Oberon: hour*4096 + minute*64 + second, (year-1900)*512 + month*32 + day *)
PROCEDURE GetModTime* (handle: Handle; VAR packedTime, packedDate: LONGINT): Error;
BEGIN Files.GetDate(handle.f, packedTime, packedDate); RETURN ok
END GetModTime;

PROCEDURE SetModTime* (VAR name: ARRAY OF CHAR; year, month, day,
                       hour, minute, second: LONGINT): Error;
VAR f: Files.File; local: ARRAY maxPath OF CHAR;
BEGIN
  Local(name, local);
  IF ~Exists(name) THEN RETURN absent END;
  f := Files.Old(local);
  IF f = NIL THEN RETURN inaccessible END;
  Files.SetDate(f, hour * 4096 + minute * 64 + second, (year - 1900) * 512 + month * 32 + day);
  RETURN ok
END SetModTime;

PROCEDURE ReadLink(path: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);
VAR n: LONGINT;
BEGIN
  n := Linux0.Readlinkat0(Linux0.ATFDCWD, SYSTEM.ADR(path[0]), SYSTEM.ADR(s[0]), LEN(s) - 1);
  IF n < 0 THEN n := 0 END;
  s[n] := 0X
END ReadLink;

PROCEDURE CurrentDirectory* (VAR path: ARRAY OF CHAR);
BEGIN ReadLink("/proc/self/cwd", path)
END CurrentDirectory;

PROCEDURE ProcessId* (): INTEGER;
VAR s: ARRAY 32 OF CHAR; i, n: LONGINT;
BEGIN
  ReadLink("/proc/self", s); n := 0; i := 0;  (* /proc/self is a link to /proc/<pid> *)
  WHILE (s[i] >= "0") & (s[i] <= "9") DO n := n * 10 + ORD(s[i]) - ORD("0"); INC(i) END;
  RETURN SHORT(n MOD 32768)
END ProcessId;

END FilesHost.
