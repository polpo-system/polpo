MODULE FATFiles;  (* polpo Linux implementation of Native Oberon FATFiles interface *)
(*
  Provides the same exported interface as Native Oberon FATFiles so that
  modules written for NO can be compiled against this on Linux without change.
  Uses Linux0 syscalls (getdents64, fstatat64) instead of FAT disk structures.

  Attribute bit assignments match Native Oberon FATFiles exactly (bits 0-5).
  Linux-only file types use higher bits (6-10) that FAT leaves undefined.
*)

IMPORT SYSTEM, Linux0;

CONST
  (* FAT file attributes - identical to Native Oberon FATFiles *)
  ReadOnly* = 0;
  Hidden*   = 1;
  System*   = 2;
  VolLabel* = 3;
  SubDir*   = 4;
  Archive*  = 5;
  (* Linux-only extensions, no FAT equivalent *)
  SymLink*  = 6;
  CharDev*  = 7;
  BlockDev* = 8;
  FIFO*     = 9;
  Socket*   = 10;

  BufSize = 4096;

  (* linux_dirent64 field offsets - same on 32-bit and 64-bit Linux *)
  ReclenOfs = 16;  (* uint16: total size of this dirent entry *)
  TypeOfs   = 18;  (* uint8:  d_type (DT_* values below) *)
  NameOfs   = 19;  (* char[]: null-terminated filename *)

  (* d_type values from <dirent.h> *)
  DTUnk = 0; DTFifo = 1; DTChr = 2; DTDir = 4;
  DTBlk = 6; DTReg = 8; DTLnk = 10; DTSock = 12;

TYPE
  (* Same signature as Native Oberon FATFiles.EntryHandler *)
  EntryHandler* = PROCEDURE (name: ARRAY OF CHAR; time, date, size: LONGINT;
                              attr: SET; VAR continue: BOOLEAN);

PROCEDURE StrLen(VAR s: ARRAY OF CHAR): INTEGER;
VAR i: INTEGER;
BEGIN i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END; RETURN i
END StrLen;

PROCEDURE CopyFromAddr(addr: LONGINT; VAR dst: ARRAY OF CHAR);
VAR i: INTEGER; c: CHAR;
BEGIN
  i := 0;
  REPEAT
    SYSTEM.GET(addr + LONG(i), c);
    dst[i] := c; INC(i)
  UNTIL (c = 0X) OR (i >= LEN(dst) - 1);
  dst[i] := 0X
END CopyFromAddr;

(* Glob matching: * matches any sequence, ? matches one character, case-insensitive *)
PROCEDURE MatchAt(VAR pat, name: ARRAY OF CHAR; pi, ni: INTEGER): BOOLEAN;
VAR res: BOOLEAN;
BEGIN
  res := FALSE;
  LOOP
    IF pat[pi] = '*' THEN
      INC(pi);
      IF pat[pi] = 0X THEN res := TRUE; EXIT END;
      WHILE ~res & (name[ni] # 0X) DO
        res := MatchAt(pat, name, pi, ni); INC(ni)
      END;
      EXIT
    ELSIF pat[pi] = '?' THEN
      IF name[ni] = 0X THEN EXIT END;
      INC(pi); INC(ni)
    ELSIF pat[pi] = 0X THEN
      res := name[ni] = 0X; EXIT
    ELSE
      IF CAP(pat[pi]) # CAP(name[ni]) THEN EXIT END;
      INC(pi); INC(ni)
    END
  END;
  RETURN res
END MatchAt;

PROCEDURE Match(VAR pat, name: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF pat[0] = 0X THEN RETURN TRUE END;
  RETURN MatchAt(pat, name, 0, 0)
END Match;

PROCEDURE IsLeap(y: LONGINT): BOOLEAN;
BEGIN RETURN (y MOD 4 = 0) & ((y MOD 100 # 0) OR (y MOD 400 = 0))
END IsLeap;

PROCEDURE DaysInMonth(m, y: LONGINT): LONGINT;
BEGIN
  IF m = 2 THEN
    IF IsLeap(y) THEN RETURN 29 ELSE RETURN 28 END
  ELSIF (m = 4) OR (m = 6) OR (m = 9) OR (m = 11) THEN RETURN 30
  ELSE RETURN 31
  END
END DaysInMonth;

(* Convert Unix timestamp (seconds since 1970-01-01) to Oberon time/date format.
   Oberon time: hours*4096 + minutes*64 + seconds
   Oberon date: (year-1900)*512 + month*32 + day, as Kernel and Files have it
   Valid for dates before 2038 (32-bit mtime from stat64). *)
PROCEDURE UnixToOberon(unix: LONGINT; VAR oTime, oDate: LONGINT);
VAR days, year, month, day, hour, min, sec, rem, yd: LONGINT;
BEGIN
  IF unix <= 0 THEN oTime := 0; oDate := 0; RETURN END;
  days := unix DIV 86400;  rem := unix MOD 86400;
  hour := rem DIV 3600;    rem := rem MOD 3600;
  min  := rem DIV 60;      sec := rem MOD 60;
  year := 1970;
  LOOP
    IF IsLeap(year) THEN yd := 366 ELSE yd := 365 END;
    IF days < yd THEN EXIT END;
    DEC(days, yd); INC(year)
  END;
  month := 1;
  LOOP
    yd := DaysInMonth(month, year);
    IF days < yd THEN EXIT END;
    DEC(days, yd); INC(month)
  END;
  oTime := hour * 4096 + min * 64 + sec;
  oDate := (year - 1900) * 512 + month * 32 + (days + 1)  (* polpo: was year * 512, not an Oberon date *)
END UnixToOberon;

(* Map stat64 st_mode to FATFiles-compatible attr SET.
   st_mode layout: bits 12-15 are the file type nibble.
   In Linux0.Status, x1 at offset 16 is st_mode. *)
PROCEDURE ModeToAttr(mode: LONGINT): SET;
VAR t: LONGINT; a: SET;
BEGIN
  a := {};
  t := (mode DIV 1000H) MOD 10H;
  IF    t = 4  THEN INCL(a, SubDir)
  ELSIF t = 8  THEN INCL(a, Archive)
  ELSIF t = 10 THEN INCL(a, SymLink)
  ELSIF t = 2  THEN INCL(a, CharDev)
  ELSIF t = 6  THEN INCL(a, BlockDev)
  ELSIF t = 1  THEN INCL(a, FIFO)
  ELSIF t = 12 THEN INCL(a, Socket)
  END;
  IF mode MOD 200H = 0 THEN INCL(a, ReadOnly) END;  (* no owner-write bit *)
  RETURN a
END ModeToAttr;

(** Enumerate directory entries matching a path/pattern.
    path may be "dir/pattern" or just "pattern" (searches current directory).
    pattern supports * and ? wildcards; empty pattern matches all entries.
    Calls handler for each match; handler may set continue := FALSE to stop.
    Skips . and .. entries automatically.
    res = 0 on success, positive errno on failure. *)
PROCEDURE Enumerate*(path: ARRAY OF CHAR; handler: EntryHandler; VAR res: LONGINT);
VAR
  fd, n, sres, mode: LONGINT;
  pos, reclen: LONGINT;
  reclenI: INTEGER;
  dtype: CHAR;
  buf: ARRAY BufSize DIV 4 OF LONGINT;  (* word aligned: d_reclen is read as 16 bits (MIPS traps otherwise) *)
  name: ARRAY 256 OF CHAR;
  fullPath: ARRAY 512 OF CHAR;
  dir: ARRAY 256 OF CHAR;
  pat: ARRAY 128 OF CHAR;
  i, j, slash: INTEGER;
  time, date, size: LONGINT;
  attr: SET;
  st: Linux0.Status;
  continue: BOOLEAN;
BEGIN
  res := 0;

  (* split "dir/pattern" at the last '/' *)
  i := StrLen(path); slash := -1;
  WHILE i > 0 DO
    DEC(i);
    IF path[i] = '/' THEN slash := i; i := 0 END
  END;
  IF slash < 0 THEN
    COPY(".", dir); COPY(path, pat)
  ELSE
    j := 0; WHILE j < slash DO dir[j] := path[j]; INC(j) END; dir[j] := 0X;
    j := 0; i := slash + 1;
    WHILE path[i] # 0X DO pat[j] := path[i]; INC(j); INC(i) END; pat[j] := 0X
  END;

  fd := Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR(dir),
                        Linux0.ORDonly + Linux0.ODirectory, 0);
  IF fd < 0 THEN res := -fd; RETURN END;

  continue := TRUE;
  LOOP
    n := Linux0.GetDents0(fd, SYSTEM.ADR(buf), BufSize);
    IF n <= 0 THEN EXIT END;
    pos := 0;
    WHILE continue & (pos < n) DO
      SYSTEM.GET(SYSTEM.ADR(buf) + pos + ReclenOfs, reclenI);
      reclen := LONG(reclenI);
      SYSTEM.GET(SYSTEM.ADR(buf) + pos + TypeOfs, dtype);
      CopyFromAddr(SYSTEM.ADR(buf) + pos + NameOfs, name);

      (* skip . and .. *)
      IF ~((name[0] = '.') &
           ((name[1] = 0X) OR ((name[1] = '.') & (name[2] = 0X)))) THEN
        IF Match(pat, name) THEN
          (* build full path for fstatat64 *)
          COPY(dir, fullPath);
          i := StrLen(fullPath); fullPath[i] := '/'; INC(i);
          j := 0;
          WHILE name[j] # 0X DO fullPath[i] := name[j]; INC(i); INC(j) END;
          fullPath[i] := 0X;

          sres := Linux0.FStatat0(Linux0.ATFDCWD, SYSTEM.ADR(fullPath),
                                   SYSTEM.ADR(st), 0);
          IF sres = 0 THEN
            size := st.size;
            UnixToOberon(st.mtime, time, date);
            SYSTEM.GET(SYSTEM.ADR(st) + Linux0.StatModeOfs, mode);
            attr := ModeToAttr(mode)
          ELSE
            (* stat failed: fall back to d_type for attr, zero size/time *)
            size := 0; time := 0; date := 0; attr := {};
            IF    ORD(dtype) = DTDir  THEN INCL(attr, SubDir)
            ELSIF ORD(dtype) = DTReg  THEN INCL(attr, Archive)
            ELSIF ORD(dtype) = DTLnk  THEN INCL(attr, SymLink)
            ELSIF ORD(dtype) = DTChr  THEN INCL(attr, CharDev)
            ELSIF ORD(dtype) = DTBlk  THEN INCL(attr, BlockDev)
            ELSIF ORD(dtype) = DTFifo THEN INCL(attr, FIFO)
            ELSIF ORD(dtype) = DTSock THEN INCL(attr, Socket)
            END
          END;
          handler(name, time, date, size, attr, continue)
        END
      END;
      pos := pos + reclen
    END
  END;
  sres := Linux0.Close0(fd)
END Enumerate;

END FATFiles.
