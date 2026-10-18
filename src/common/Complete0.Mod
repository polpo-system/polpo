MODULE Complete0;  (** completion of command and file names, shared by the shell and the desktop *)

(** Command completes a command: "Mod" gives the module names of the object directories (the one of
  the current directory and the root's), "Mod.Pr" the commands of Mod (from memory when it is loaded,
  else from its object file). Path completes a file name, as FATFiles.Enumerate finds it.
  Both set n, the number of matches, name[0..n-1] (at most MaxNames; directories end in "/")
  and add, what all matches have after the typed word (with "." after a single module name). *)

IMPORT Kernel, Files, FATFiles, Modules0, Root;

CONST
  MaxNames* = 256;

VAR
  n*: INTEGER;  (** the number of matches *)
  name*: ARRAY MaxNames OF ARRAY 128 OF CHAR;  (** the matches kept *)
  common: ARRAY 128 OF CHAR;  (* the common part of all matches *)
  pfx: ARRAY 128 OF CHAR;  (* what is typed of the name *)
  pfxLen: INTEGER;
  cmdAdrSize: INTEGER;  (* bytes per command address in the CmdBlk being read *)

PROCEDURE Length(VAR s: ARRAY OF CHAR): INTEGER;
VAR i: INTEGER;
BEGIN i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END; RETURN i
END Length;

PROCEDURE Append(VAR s: ARRAY OF CHAR; t: ARRAY OF CHAR);
VAR i, j: INTEGER;
BEGIN
  i := Length(s); j := 0;
  WHILE (t[j] # 0X) & (i < LEN(s) - 1) DO s[i] := t[j]; INC(i); INC(j) END;
  s[i] := 0X
END Append;

PROCEDURE Prefix(VAR s: ARRAY OF CHAR): BOOLEAN;  (* does s begin with pfx? *)
VAR i: INTEGER;
BEGIN
  i := 0; WHILE (i < pfxLen) & (s[i] = pfx[i]) DO INC(i) END;
  RETURN i = pfxLen
END Prefix;

PROCEDURE Add(s: ARRAY OF CHAR);  (* a match, once *)
VAR i: INTEGER;
BEGIN
  i := 0; WHILE (i < n) & (i < MaxNames) & (name[i] # s) DO INC(i) END;
  IF (i = n) OR (i = MaxNames) THEN
    IF n = 0 THEN COPY(s, common)
    ELSE i := 0; WHILE (common[i] # 0X) & (common[i] = s[i]) DO INC(i) END; common[i] := 0X
    END;
    IF n < MaxNames THEN COPY(s, name[n]) END;
    INC(n)
  END
END Add;

PROCEDURE Start(VAR word: ARRAY OF CHAR; from: INTEGER);  (* the name to complete is word[from..] *)
VAR i: INTEGER;
BEGIN
  i := 0; WHILE (word[from + i] # 0X) & (i < LEN(pfx) - 1) DO pfx[i] := word[from + i]; INC(i) END;
  pfx[i] := 0X; pfxLen := i; n := 0; common[0] := 0X
END Start;

PROCEDURE Rest(VAR add: ARRAY OF CHAR);  (* add := common[pfxLen..] *)
VAR i, j: INTEGER;
BEGIN
  i := pfxLen; j := 0;
  IF n > 0 THEN WHILE (common[i] # 0X) & (j < LEN(add) - 2) DO add[j] := common[i]; INC(i); INC(j) END END;
  add[j] := 0X
END Rest;

(* the object directories: of the current directory, then the root's *)
PROCEDURE ObjDir(k: INTEGER; VAR dir: ARRAY OF CHAR);
VAR arch: ARRAY 32 OF CHAR; i, j: INTEGER;
BEGIN
  IF k = 0 THEN COPY(Modules0.objPath, dir)
  ELSE
    dir[0] := 0X;
    IF (Modules0.objPath[0] = "o") & (Modules0.objPath[1] = "b") & (Modules0.objPath[2] = "j")
      & (Modules0.objPath[3] = "/") THEN
      i := 4; j := 0;
      WHILE (Modules0.objPath[i] # 0X) & (Modules0.objPath[i] # "/") & (j < LEN(arch) - 1) DO
        arch[j] := Modules0.objPath[i]; INC(i); INC(j)
      END;
      arch[j] := 0X; Root.RootObj(arch, dir);
      IF dir = Modules0.objPath THEN dir[0] := 0X END
    END
  END
END ObjDir;

(* ---- .Obj parsing helpers ----------------------------------------- *)

PROCEDURE ObjReadStr(VAR R: Files.Rider; VAR s: ARRAY OF CHAR);
VAR i: INTEGER; ch: CHAR;
BEGIN
  i := 0;
  LOOP
    Files.Read(R, ch);
    IF ch = 0X THEN s[i] := 0X; RETURN
    ELSIF ch > 7FX THEN s[i] := CHR(ORD(ch) - 80H); s[i+1] := 0X; RETURN
    ELSE s[i] := ch; INC(i)
    END
  END
END ObjReadStr;

PROCEDURE ObjReadU16(VAR R: Files.Rider; VAR u: LONGINT);
VAR lo, hi: CHAR;
BEGIN
  Files.Read(R, lo); Files.Read(R, hi);
  u := 256 * LONG(ORD(hi)) + ORD(lo)
END ObjReadU16;

(* Position rider at start of CmdBlk of an ARM object file (after the F5X tag);
   returns nofCmds, or -1 on error. *)
PROCEDURE ArmSeekCmds(VAR R: Files.Rider): INTEGER;
VAR
  tag: CHAR;
  n: LONGINT;
  nofImps, nofEntries, nofPtrs, nofCmds: INTEGER;
  dummy: ARRAY 64 OF CHAR;
  i: INTEGER;
BEGIN
  Files.Read(R, tag); IF tag # "0" THEN RETURN -1 END;
  Files.ReadLInt(R, n); Files.ReadLInt(R, n);  (* refpos, body entry *)
  Files.ReadInt(R, nofImps); Files.ReadInt(R, nofEntries);
  Files.ReadInt(R, nofPtrs); Files.ReadInt(R, nofCmds);
  Files.ReadLInt(R, n); Files.ReadLInt(R, n); Files.ReadLInt(R, n);  (* const, data, code size *)
  Files.ReadInt(R, i); Files.ReadLInt(R, n);  (* nofRecs, key *)
  Files.ReadString(R, dummy);  (* module name *)
  Files.Read(R, tag); IF tag # 085X THEN RETURN -1 END;  (* imports *)
  i := 0; WHILE i < nofImps DO Files.ReadLInt(R, n); Files.ReadString(R, dummy); INC(i) END;
  Files.Read(R, tag); IF tag # 082X THEN RETURN -1 END;  (* entries *)
  i := 0; WHILE i < nofEntries DO Files.ReadLInt(R, n); INC(i) END;
  Files.Read(R, tag); IF tag # 084X THEN RETURN -1 END;  (* pointers *)
  i := 0; WHILE i < nofPtrs DO Files.ReadLInt(R, n); INC(i) END;
  Files.Read(R, tag); IF tag # 083X THEN RETURN -1 END;  (* commands *)
  cmdAdrSize := 4;
  RETURN nofCmds
END ArmSeekCmds;

(* Position rider at start of CmdBlk of a ROP2 object file (ARMv7 FBX, RISC-V FDX, MIPS F9X and F8X, PowerPC F7X,
   after the tag), as Modules0.LoadModule of src/cli/rop2 reads it; returns nofCmds, or -1. *)
PROCEDURE Rop2SeekCmds(VAR R: Files.Rider): INTEGER;
VAR
  tag, ch: CHAR;
  n, nofImps, nofMeth, nofPtr, bmno: LONGINT;
  nofExp, nofDesc, nofCmds, nofPtrs: INTEGER;
  s: ARRAY 64 OF CHAR;
  i: LONGINT;
BEGIN
  Files.Read(R, tag); IF tag # "6" THEN RETURN -1 END;
  Files.ReadLInt(R, n);  (* refsize *)
  Files.ReadInt(R, nofExp); Files.ReadInt(R, nofDesc); Files.ReadInt(R, nofCmds); Files.ReadInt(R, nofPtrs);
  Files.ReadNum(R, nofImps);
  i := 0; WHILE i < 7 DO Files.ReadNum(R, n); INC(i) END;  (* links, data, const and code size *)
  Files.ReadString(R, s);  (* module name *)
  Files.Read(R, tag); IF tag # 081X THEN RETURN -1 END;  (* imports *)
  i := 0; WHILE i < nofImps DO Files.ReadString(R, s); INC(i) END;
  Files.Read(R, tag); IF tag # 082X THEN RETURN -1 END;  (* exports *)
  Files.Read(R, ch);
  WHILE (ch # 0X) & ~R.eof DO
    IF ch = 8X THEN  (* a type descriptor *)
      Files.ReadString(R, s); IF s = "" THEN Files.ReadNum(R, n) END;
      Files.ReadNum(R, n); Files.ReadNum(R, n); Files.ReadNum(R, bmno);  (* link, size, base *)
      IF bmno >= 0 THEN Files.ReadString(R, s); IF s = "" THEN Files.ReadNum(R, n) END END;
      Files.ReadNum(R, n); Files.ReadNum(R, n);  (* methods, inherited *)
      Files.ReadNum(R, nofMeth); Files.ReadNum(R, nofPtr);
      i := 0; WHILE i < 2 * nofMeth DO Files.ReadNum(R, n); INC(i) END;
      i := 0; WHILE i < nofPtr DO Files.ReadNum(R, n); INC(i) END
    ELSIF ch = 9X THEN Files.ReadNum(R, n); Files.ReadNum(R, n)  (* a link *)
    ELSE
      Files.ReadString(R, s); Files.ReadNum(R, n);  (* name, fingerprint *)
      IF (ch = 3X) OR (ch = 4X) OR (ch = 6X) THEN Files.ReadNum(R, n) END
    END;
    Files.Read(R, ch)
  END;
  Files.Read(R, tag); IF tag # 083X THEN RETURN -1 END;  (* commands *)
  cmdAdrSize := 0;  (* a compact number *)
  RETURN nofCmds
END Rop2SeekCmds;

(* Position rider at start of CmdBlk; returns nofCmds, or -1 on error.
   Understands x86 (BBX AFX), ARM (F5X "0") and ROP2 (F7X PowerPC, F8X MIPS big-endian, F9X, FBX,
   FDX "6") object files. *)
PROCEDURE ObjSeekCmds(VAR R: Files.Rider): INTEGER;
VAR
  tag: CHAR;
  symSize, refSize, dataSize, conSize, codeSize, n: LONGINT;
  nofEntries, nofCmds, nofPtrs, nofTds, nofImps, nofDL, nofLinks: INTEGER;
  dummy: ARRAY 64 OF CHAR;
  i: INTEGER;
BEGIN
  Files.Read(R, tag);
  IF tag = 0F5X THEN RETURN ArmSeekCmds(R) END;
  IF (tag = 0F7X) OR (tag = 0F8X) OR (tag = 0F9X) OR (tag = 0FAX) OR (tag = 0FBX) OR (tag = 0FDX) THEN RETURN Rop2SeekCmds(R) END;
  IF tag # 0BBX THEN RETURN -1 END;
  Files.Read(R, tag); IF tag # 0AFX THEN RETURN -1 END;
  cmdAdrSize := 2;
  Files.ReadNum(R, symSize);
  Files.Set(R, Files.Base(R), Files.Pos(R) + symSize);
  Files.ReadLInt(R, refSize);
  Files.ReadInt(R, nofEntries); Files.ReadInt(R, nofCmds);
  Files.ReadInt(R, nofPtrs);   Files.ReadInt(R, nofTds);
  Files.ReadInt(R, nofImps);   Files.ReadInt(R, nofDL);
  Files.ReadInt(R, nofLinks);
  Files.ReadLInt(R, dataSize);
  ObjReadU16(R, conSize); ObjReadU16(R, codeSize);
  ObjReadStr(R, dummy);            (* module name *)
  Files.Read(R, tag); IF tag # 082X THEN RETURN -1 END;  (* EntryBlk *)
  i := 0; WHILE i < nofEntries DO ObjReadU16(R, n); INC(i) END;
  Files.Read(R, tag); IF tag # 083X THEN RETURN -1 END;  (* CmdBlk *)
  RETURN nofCmds
END ObjSeekCmds;

(* Read one CmdBlk entry, skipping its address. *)
PROCEDURE ObjReadCmd(VAR R: Files.Rider; VAR name: ARRAY OF CHAR);
VAR n: LONGINT;
BEGIN
  ObjReadStr(R, name);
  IF cmdAdrSize = 4 THEN Files.ReadLInt(R, n)
  ELSIF cmdAdrSize = 0 THEN Files.ReadNum(R, n)
  ELSE ObjReadU16(R, n)
  END
END ObjReadCmd;

PROCEDURE ObjHandler(name: ARRAY OF CHAR; time, date, size: LONGINT; attr: SET; VAR continue: BOOLEAN);
VAR mod: ARRAY 64 OF CHAR; i: INTEGER;
BEGIN
  i := 0; WHILE (name[i] # 0X) & (name[i] # ".") & (i < LEN(mod) - 1) DO mod[i] := name[i]; INC(i) END;
  mod[i] := 0X;
  IF (name[i] = ".") & (name[i+1] = "O") & (name[i+2] = "b") & (name[i+3] = "j") & (name[i+4] = 0X)
    & Prefix(mod) THEN Add(mod)
  END
END ObjHandler;

PROCEDURE PathHandler(name: ARRAY OF CHAR; time, date, size: LONGINT; attr: SET; VAR continue: BOOLEAN);
VAR s: ARRAY 128 OF CHAR;
BEGIN
  IF Prefix(name) THEN
    COPY(name, s); IF FATFiles.SubDir IN attr THEN Append(s, "/") END;
    Add(s)
  END
END PathHandler;

PROCEDURE Commands(VAR mod: ARRAY OF CHAR);  (* the commands of mod beginning with pfx *)
VAR m: Kernel.Module; i, k, nofCmds: INTEGER; fname: ARRAY 320 OF CHAR; f: Files.File; R: Files.Rider;
  cname: ARRAY 64 OF CHAR;
BEGIN
  m := Kernel.modules; WHILE (m # NIL) & (m.name # mod) DO m := m.next END;
  IF m # NIL THEN
    i := 0;
    WHILE i < LEN(m.cmds^) DO
      IF Prefix(m.cmds[i].name) THEN Add(m.cmds[i].name) END;
      INC(i)
    END
  ELSE
    k := 0; f := NIL;
    WHILE (k < 2) & (f = NIL) DO
      ObjDir(k, fname);
      IF fname # "" THEN Append(fname, mod); Append(fname, ".Obj"); f := Files.Old(fname) END;
      INC(k)
    END;
    IF f # NIL THEN
      Files.Set(R, f, 0); nofCmds := ObjSeekCmds(R);
      i := 0;
      WHILE i < nofCmds DO
        ObjReadCmd(R, cname); IF Prefix(cname) THEN Add(cname) END;
        INC(i)
      END;
      Files.ReleaseRead(f)
    END
  END
END Commands;

(** Complete the command word: a module name, or a command after the "." *)
PROCEDURE Command*(word: ARRAY OF CHAR; VAR add: ARRAY OF CHAR);
VAR i, dot, k: INTEGER; mod: Kernel.Name; pat: ARRAY 320 OF CHAR; res: LONGINT;
BEGIN
  dot := -1; i := 0;
  WHILE word[i] # 0X DO IF word[i] = "." THEN dot := i END; INC(i) END;
  IF dot >= 0 THEN
    i := 0; WHILE (i < dot) & (i < LEN(mod) - 1) DO mod[i] := word[i]; INC(i) END; mod[i] := 0X;
    Start(word, dot + 1); Commands(mod); Rest(add)
  ELSE
    Start(word, 0);
    k := 0;
    WHILE k < 2 DO
      ObjDir(k, pat); IF pat # "" THEN Append(pat, "*.Obj"); FATFiles.Enumerate(pat, ObjHandler, res) END;
      INC(k)
    END;
    Rest(add); IF n = 1 THEN Append(add, ".") END
  END
END Command;

(** Complete the file name word, with a directory part or without *)
PROCEDURE Path*(word: ARRAY OF CHAR; VAR add: ARRAY OF CHAR);
VAR i, last: INTEGER; pat: ARRAY 320 OF CHAR; res: LONGINT;
BEGIN
  last := 0; i := 0;
  WHILE word[i] # 0X DO IF word[i] = "/" THEN last := i + 1 END; INC(i) END;
  Start(word, last);
  COPY(word, pat); Append(pat, "*"); FATFiles.Enumerate(pat, PathHandler, res);
  Rest(add)
END Path;

END Complete0.
