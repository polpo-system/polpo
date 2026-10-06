(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

MODULE Files;  (* pjm *)

(* 
  Linux-compatible Files module not based on OFS
  Peter Matthias

  2014-05-27  first version
  2014-06-04  made FileDesc.new LONGINT, fixed some filename lengths; merged CleanupOld and CleanupNew
  2014-06-16  added f.len (File length for faster writing)
  2014-06-22  mmapped files working
  2015-02-10  OLR version
  2015-04-01  open old files read only if no write permission
  2015-04-17  Close makes files anonymous
  2015-05-15  Close updates file now, changed Set
  2015-05-20  changed Set to allow pos >f.len
  2015-05-26  added check for LEN(x)< n in WriteBytes
  2015-07-31  made MAPSHARED MAPPRIVATE; SHARED might not work on NOKIA N810; ToDo Test!
  2015-12-09  imported Linux0
  2016-05-14  allowed "_" and "-"in filename
  2016-07-31  changed ReadNum to work with 64bit registers
  2016-08-29  added Files.dirfd
  2016-09-13  Close* don't write to file ToDo: don't use MAPPRIVATE

ToDo:  Register  GC on Too many open files Trap (Trap 109)

Volume:
PROCEDURE New*(name: ARRAY OF CHAR): File;
PROCEDURE Old*( name: ARRAY OF CHAR): File;
PROCEDURE Rename*(old, new: ARRAY OF CHAR; VAR res: INTEGER);
PROCEDURE Register*(f: File);
PROCEDURE Close*(f: File);

Filesystem:
PROCEDURE GetDate*(f: File; VAR t, d: LONGINT);
PROCEDURE SetDate*(f: File; t, d: LONGINT);
PROCEDURE Set*(VAR r: Rider; f: File; pos: LONGINT);  ??
PROCEDURE ReadBytes*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);
PROCEDURE WriteBytes*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);
PROCEDURE Enumerate*(mask: ARRAY OF CHAR; flags: SET; proc: EntryHandler);

Volume to be added:
PROCEDURE Mount(prefix: ARRAY OF CHAR; volume: Volume): LONGINT;
PROCEDURE Unmount( volume: Volume): LONGINT;

*)

IMPORT Linux0, Kernel, Root, SYSTEM;

CONST

  FnLength = 256;  (* includes 0X *)
  MremapMaymove = 1;

TYPE
  File* = POINTER TO FileDesc;

  FileName*= ARRAY FnLength OF CHAR;

  FileDesc = RECORD
      (** private fields for implementors *)
      Name: FileName;
      fd, addr, len, dirfd: LONGINT;
      disk: LONGINT;  (* polpo: the length on disk of a file mapped shared, -1 for a private mapping *)
      changed: BOOLEAN;
  END;

  Rider* = RECORD
    file: File;
    apos: LONGINT;
    res*: LONGINT;  (** leftover byte count for ReadBytes/WriteBytes *)
    eof*: BOOLEAN;  (** has end of file been passed *)
  END;

  Bytes1 = ARRAY 1 OF SYSTEM.BYTE;
  Bytes2 = ARRAY 2 OF SYSTEM.BYTE;
  Bytes4 = ARRAY 4 OF SYSTEM.BYTE;
  Bytes8 = ARRAY 8 OF SYSTEM.BYTE;

  TimeSpec= RECORD  tvsec, tvnsec: LONGINT END;

VAR
  trace: BOOLEAN;
(* Check a file name. *)
  sysfd, wrkfd: LONGINT;
  searchPath: ARRAY 5 OF FileName;  (* polpo: directories tried by Old for plain names *)
  nofSearch: LONGINT;

PROCEDURE SetSYS*( s: ARRAY OF CHAR);
BEGIN
  sysfd:=Linux0.Openat0( Linux0.ATFDCWD, SYSTEM.ADR(s[0]), Linux0.ORDonly+Linux0.ODirectory , 0);
  IF sysfd<=0 THEN Kernel.WriteString("Files.SetSYS: "); Kernel.WriteHex( -sysfd, 9); Kernel.WriteLn END;
END SetSYS;

PROCEDURE SetWRK*( s: ARRAY OF CHAR);
BEGIN
  IF s="" THEN wrkfd:=-1;
  ELSE
    wrkfd:=Linux0.Openat0( Linux0.ATFDCWD, SYSTEM.ADR(s[0]), Linux0.ORDonly+Linux0.ODirectory , 0);
    IF wrkfd<=0 THEN Kernel.WriteString("Files.SetWRK: "); Kernel.WriteHex( -wrkfd, 9); Kernel.WriteLn END;
  END;
END SetWRK;

PROCEDURE GetDirfd(VAR s: ARRAY OF CHAR): LONGINT;
VAR i, fd: LONGINT;
BEGIN
  IF (LEN(s)>4) & (s[3]=":") THEN
    s[3]:=0X;
    IF s="SYS" THEN fd:= sysfd;
    ELSIF s="WRK" THEN fd:= wrkfd;
    ELSE fd:=-1;
    END;
    i:=3;
    REPEAT
      INC(i);
      s[i-4]:=s[i];
    UNTIL s[i] =0X;
    RETURN fd;  
  END;
  IF wrkfd>0 THEN  RETURN wrkfd;
  ELSE RETURN sysfd;
  END;
END GetDirfd;    

PROCEDURE Check(VAR s, name: ARRAY OF CHAR; VAR dirfd: LONGINT; VAR res: INTEGER);
  VAR i: LONGINT; ch: CHAR;
BEGIN
  dirfd:=GetDirfd(s);
  ch := s[0]; i := 0;
  IF ("A" <= CAP(ch)) & (CAP(ch) <= "Z")OR (ch = ".") OR (ch="/") OR (ch="_") OR (ch="-") THEN
    LOOP name[i] := ch; INC(i); ch := s[i];
      IF ch = 0X THEN
        WHILE i < LEN(name) DO name[i] := 0X; INC(i) END ;
        res := 0; EXIT
      END ;
      IF ~(("A" <= CAP(ch)) & (CAP(ch) <= "Z")
        OR ("0" <= ch) & (ch <= "9") OR (ch = ".") OR (ch="/") OR (ch="_") OR (ch="-")) THEN res := 3; EXIT
      END ;
      IF i = LEN(name)-1 THEN res := 4; EXIT END
    END
  ELSIF ch = 0X THEN name[0] := 0X; res := -1
  ELSE res := 3
  END
END Check;

PROCEDURE Cleanup( f: SYSTEM.PTR);
VAR res: LONGINT; newName: FileName; f2: File;
BEGIN
  IF trace THEN Kernel.WriteString("Files.Cleanup: ") END; 
  IF f # NIL THEN
    f2:=SYSTEM.VAL(File, f);
    IF trace THEN Kernel.WriteString(f2.Name) END;
    IF f2.fd#-1 THEN res:= Linux0.Close0( f2.fd); f2.fd:=-1 END;
  END;
  IF trace THEN Kernel.WriteLn END;
END Cleanup;


(** Open an existing file. The same file descriptor is returned if a file is opened multiple times. *)
(* Open name relative to directory dirfd, read-write or else read-only. *)
PROCEDURE OpenRW(dirfd: LONGINT; VAR name: ARRAY OF CHAR): LONGINT;
VAR fd: LONGINT;
BEGIN
  fd:=Linux0.Openat0( dirfd, SYSTEM.ADR(name[0]), Linux0.ORDWR , 0);
  IF -fd=0DH THEN  (* permission denied, try read only *)
    fd:=Linux0.Openat0( dirfd, SYSTEM.ADR(name[0]), Linux0.ORDonly , 0);
  END;
  RETURN fd
END OpenRW;

(* polpo: try a plain file name in the directories of searchPath (root, share/, tools/, fonts/),
   a relative name with a directory part (obj/x86/Texts.Sym) in the root only;
   on success name becomes the path that was found. *)
PROCEDURE OpenSearch(VAR name: ARRAY OF CHAR): LONGINT;
VAR fd, i, j, k, n: LONGINT; path: FileName;
BEGIN
  IF name[0]="/" THEN RETURN -2 END;
  i:=0; WHILE (name[i]#0X) & (name[i]#"/") DO INC(i) END;
  IF name[i]#"/" THEN n:=nofSearch
  ELSIF Root.path#"" THEN n:=1  (* searchPath[0] is the root *)
  ELSE RETURN -2
  END;
  fd:=-2; k:=0;
  WHILE (fd<=0) & (k<n) DO
    i:=0; WHILE searchPath[k][i]#0X DO path[i]:=searchPath[k][i]; INC(i) END;
    j:=0; WHILE (name[j]#0X) & (i<LEN(path)-1) DO path[i]:=name[j]; INC(i); INC(j) END;
    path[i]:=0X;
    fd:=OpenRW( Linux0.ATFDCWD, path);
    IF fd>0 THEN COPY(path, name) END;
    INC(k)
  END;
  RETURN fd
END OpenSearch;

(* polpo: a plain name that does not exist in the directory dirfd (or SYS) but is found in the
   search path becomes the path found, so a file is written back where it was read from. *)
PROCEDURE Locate(VAR name: ARRAY OF CHAR; VAR dirfd: LONGINT);
VAR fd, r, i: LONGINT; path: FileName;
BEGIN
  i:=0; WHILE (name[i]#0X) & (name[i]#"/") DO INC(i) END;
  IF (name[0]#0X) & (name[i]#"/") THEN
    fd:=Linux0.Openat0( dirfd, SYSTEM.ADR(name[0]), Linux0.ORDonly, 0);
    IF fd<=0 THEN fd:=Linux0.Openat0( sysfd, SYSTEM.ADR(name[0]), Linux0.ORDonly, 0) END;
    IF fd>0 THEN r:=Linux0.Close0(fd)
    ELSE
      COPY(name, path); fd:=OpenSearch(path);
      IF fd>0 THEN r:=Linux0.Close0(fd); COPY(path, name); dirfd:=Linux0.ATFDCWD END
    END
  END
END Locate;

(** Creates a new file with the specified name. *)
PROCEDURE New*(name: ARRAY OF CHAR): File;
VAR f: File; res: INTEGER; newName: FileName;
BEGIN
  IF trace THEN Kernel.WriteString("Files.New "); Kernel.WriteString(name); Kernel.WriteLn END;
  NEW(f);
  Check( name, f.Name, f.dirfd, res);
  IF res=0 THEN Locate(f.Name, f.dirfd) END;
  IF res <=0 THEN
    f.fd:=-1;
(* MAP_SHARED=1, MAP_PRIVATE=2, MAP_ANONYMOUS=20H, 800@MIPS, RW=3 Anonymous files have to be private for mmap to work! *)
    f.addr:=Linux0.Mmap20( 0, Linux0.PageSize, 3, Linux0.MAPPRIVATE+Linux0.MAPANONYMOUS, 0, 0);
    IF (f.addr MOD 1000H) #0 THEN Kernel.WriteString("Files.New mmap failed"); Kernel.WriteHex(f.addr, 9); Kernel.WriteLn;END;
    f.len:=0; f.disk:=-1;
    f.changed:=FALSE;
    Kernel.RegisterObject( f, Cleanup, FALSE);
    RETURN f;
  END;
  Kernel.WriteString("Files.New failed"); Kernel.WriteLn;
  RETURN NIL;
END New;

PROCEDURE Old*( name: ARRAY OF CHAR): File;
VAR f: File; fd, r: LONGINT; status: Linux0.Status; res: INTEGER;
BEGIN
  NEW( f);
  IF trace THEN Kernel.WriteString("Files.Old "); Kernel.WriteString(name); Kernel.WriteLn END;
  Check( name, f.Name, f.dirfd, res);
  IF res=0 THEN
    fd:=Linux0.Openat0( f.dirfd, SYSTEM.ADR(f.Name[0]), Linux0.ORDWR , 0);  (* 0x400*O_EXCL *)
    IF -fd=0DH THEN  (* permission denied, try read only *)
      fd:=Linux0.Openat0( f.dirfd, SYSTEM.ADR(f.Name[0]), Linux0.ORDonly , 0);
    END;
    IF fd<=0 THEN
      fd:=Linux0.Openat0( sysfd, SYSTEM.ADR(f.Name[0]), Linux0.ORDWR , 0);  (* 0x400*O_EXCL *)
      IF -fd=0DH THEN  (* permission denied, try read only *)
        fd:=Linux0.Openat0( sysfd, SYSTEM.ADR(f.Name[0]), Linux0.ORDonly , 0);
      END;
    END;
    IF fd<=0 THEN
      r:=OpenSearch(f.Name);
      IF r>0 THEN fd:=r; f.dirfd:=Linux0.ATFDCWD END
    END;
    IF fd<=0 THEN
      IF fd=-2 THEN Kernel.WriteString( f.Name); Kernel.WriteString(" not present");
      ELSE Kernel.WriteString("Error: "); Kernel.WriteString(f.Name); Kernel.WriteHex(-fd, 9);
      END;
      Kernel.WriteLn;
      RETURN NIL;
    END;
    f.fd:= fd;
    r:=Linux0.FStat0( f.fd, SYSTEM.ADR(status));
    f.len:=status.size;
    IF trace THEN Kernel.WriteString(" size: "); Kernel.WriteInt(f.len, 9); Kernel.WriteLn END;

    IF f.len = 0 THEN  (* polpo: a mapping of length 0 fails, an empty file got NIL; a page as in New *)
      f.addr:=Linux0.Mmap20( 0, Linux0.PageSize, 3, Linux0.MAPPRIVATE+Linux0.MAPANONYMOUS, 0, 0); f.disk:=-1
    ELSE
      f.addr:=Linux0.Mmap20( 0, f.len (*((f.len+bsize-1) DIV bsize)*bsize*), 3, Linux0.MAPSHARED, f.fd, 0); f.disk:=f.len
    END;
    IF (f.addr MOD 1000H)#0 THEN
      Kernel.WriteString("Files.Old mmap failed"); Kernel.WriteHex(-f.addr, 9); Kernel.WriteLn;
      r:= Linux0.Close0( fd);
      RETURN NIL;
    END;
    f.changed:=FALSE;
    Kernel.RegisterObject( f, Cleanup, FALSE);
    RETURN f;
  END;
  RETURN NIL;
END Old;

(* Release an opened read file descriptor while retaining its memory map. *)
PROCEDURE ReleaseRead*(f: File);
VAR res: LONGINT;
BEGIN
  IF (f # NIL) & (f.fd > 0) THEN
    res := Linux0.Close0(f.fd); f.fd := -1
  END
END ReleaseRead;

(** Register a file created with New in the directory, replacing the previous file in the 
directory with the same name. The file is automatically closed. *)
PROCEDURE Register*(f: File);
VAR res: LONGINT;
BEGIN
  IF f# NIL THEN
    IF trace THEN Kernel.WriteString("Files.Register "); Kernel.WriteString(f.Name); Kernel.WriteLn END;
    IF f.Name#"" THEN
      IF f.fd=-1 THEN                                  (* flags were 242H for X86 *)
        (* polpo: remove the old file first, so that processes that have it open or mapped
           (object files of a running Oberon) keep the old contents *)
        res:=Linux0.UnLinkat0( f.dirfd, SYSTEM.ADR(f.Name[0]), 0);
        f.fd:=Linux0.Openat0( f.dirfd, SYSTEM.ADR(f.Name[0]), Linux0.ORDWR+Linux0.OTRUNC+Linux0.OCREAT, SYSTEM.VAL( LONGINT, { 8, 7, 5, 2}));
        (*   ARM: was 240H; 200H: O_DSYNC, 40H: O_CREAT MIPS: 110H*)
        IF f.fd<=0 THEN
          Kernel.WriteString("Files.Register bug"); Kernel.WriteHex(-f.fd, 9); Kernel.WriteLn;
          IF f.fd=-24 THEN    (* too many open files; must not return NIL; Bug?? *)
            (* close open files *)
            HALT( 109);
          END;
          HALT( 108);
        END;
        IF f.len#Linux0.Write0( f.fd, f.addr, f.len) THEN Kernel.WriteString("Files.Register 2"); HALT( 107) END;
        f.changed:=FALSE
      ELSE
        IF f.changed THEN  (* polpo: from the start; at the descriptor's position a second Register appended *)
          res:=Linux0.LSeek0( f.fd, 0, Linux0.SEEKSET);
          IF f.len#Linux0.Write0( f.fd, f.addr, f.len) THEN Kernel.WriteString("Files.Register 3"); HALT( 110) END;
          f.changed:=FALSE
        END;
        IF 0#Linux0.Ftruncate0( f.fd, f.len) THEN Kernel.WriteString("Files.Register 4"); HALT(102) END;
        IF f.disk >= 0 THEN f.disk:=f.len END
      END;
    END;
    f:=NIL;
  END;
END Register;

(** Flushes the changes made to a file to disk. Register will automatically Close a file. *)
(* polpo: a file with a descriptor (registered, or opened with Old) is written if it changed; it
   stays usable and keeps its name (Close cleared the name: a later Register wrote nothing, so the
   zlib, Zip and Compress code of ETH Oberon lost its files). A new file is written by Register. *)
PROCEDURE Close*(f: File);
VAR res: LONGINT; 
BEGIN
  IF f# NIL THEN
    IF trace THEN Kernel.WriteString("Files.Close "); Kernel.WriteString(f.Name); Kernel.WriteLn END;
    IF (f.fd>0) & f.changed THEN
      res:=Linux0.LSeek0( f.fd, 0, Linux0.SEEKSET);
      res:=Linux0.Write0( f.fd, f.addr, f.len);
      IF res#f.len THEN Kernel.WriteString("Files.Close: write failed "); Kernel.WriteString(f.Name); Kernel.WriteHex(-res, 9); Kernel.WriteLn
      ELSE res:=Linux0.Ftruncate0( f.fd, f.len); f.changed:=FALSE; IF f.disk >= 0 THEN f.disk:=f.len END
      END
    END
  END
END Close;

(** Returns the current length of a file. *)
PROCEDURE Length*(f: File): LONGINT;
BEGIN
  IF f# NIL THEN RETURN f.len END;
  RETURN 0;
END Length;

(** Returns the time (t) and date (d) when a file was last modified. *)
PROCEDURE GetDate*(f: File; VAR t, d: LONGINT);
VAR status: Linux0.Status; res: LONGINT;
BEGIN
  res:=Linux0.FStat0( f.fd, SYSTEM.ADR(status));
  Kernel.U2OTime( status.mtime, d, t);
END GetDate;

(** Sets the modification time (t) and date (d) of a file. *)
PROCEDURE SetDate*(f: File; t, d: LONGINT);
VAR tm: LONGINT; buf: ARRAY 2 OF TimeSpec;
BEGIN
  tm:= Kernel.O2UTime( d, t);
  buf[0].tvsec:=tm; buf[0].tvnsec:=0;
  buf[1].tvsec:=tm; buf[1].tvnsec:=0;
  tm:=Linux0.UTimensat0( f.dirfd, SYSTEM.ADR( f.Name[0]), SYSTEM.ADR( buf), 0);
END SetDate;

(** Positions a Rider at a certain position in a file. Multiple Riders can be positioned 
at different locations in a file. A Rider cannot be positioned beyond the end of a file. *)
PROCEDURE Set*(VAR r: Rider; f: File; pos: LONGINT);
BEGIN
  r.file:= f;
  r.apos:= pos;
  r.res:= 0;
  r.eof:= FALSE;
  IF (f#NIL) & (pos>f.len) THEN Kernel.WriteString("Warning: Files.Set pos/f.len"); Kernel.WriteHex( pos, 9); Kernel.WriteHex( f.len, 9);Kernel.WriteLn END;
END Set;

(** Returns the offset of a Rider positioned on a file. *)
PROCEDURE Pos*(VAR r: Rider): LONGINT;
BEGIN  RETURN r.apos;
END Pos;

(** Returns the File a Rider is based on. *)
PROCEDURE Base*(VAR r: Rider): File;
BEGIN
  RETURN r.file
END Base;

(** Reads a sequence of length n bytes into the buffer x, advancing the Rider. Less bytes 
will be read when reading over the length of the file. r.res indicates the number of unread bytes. 
x must be big enough to hold n bytes. *)
PROCEDURE ReadBytes*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);
VAR f: File; res: LONGINT;
BEGIN
  f:=r.file;
  res:=r.apos+n-f.len;
  IF  res>0 THEN
    r.eof:= TRUE;
    r.res:= res;
    (* OLR 2017-02-25: bytes beyond the end of the file read as 0X *)
    REPEAT DEC(n); x[n]:=0X; DEC(res) UNTIL res=0;
  ELSE
    r.eof:= FALSE;
    r.res:= 0;
  END;
  IF n>0 THEN SYSTEM.MOVE( f.addr+r.apos, SYSTEM.ADR( x[0]), n) END;
  INC( r.apos, n);
END ReadBytes;

(** Read a byte from a file, advancing the Rider one byte further.  R.eof indicates if the end of the file has been passed. *)
PROCEDURE Read*(VAR r: Rider; VAR x: SYSTEM.BYTE);
BEGIN  ReadBytes( r, x, 1);
END Read;

(**
Portable routines to read the standard Oberon types.
*)

PROCEDURE ReadInt*(VAR r: Rider; VAR x: INTEGER);
BEGIN
  ReadBytes(r, SYSTEM.VAL(Bytes2, x), 2)
END ReadInt;

PROCEDURE ReadLInt*(VAR r: Rider; VAR x: LONGINT);
BEGIN
  ReadBytes(r, SYSTEM.VAL(Bytes4, x), 4)
END ReadLInt;

PROCEDURE ReadSet*(VAR r: Rider; VAR x: SET);
BEGIN
  ReadBytes(r, SYSTEM.VAL(Bytes4, x), 4)
END ReadSet;

PROCEDURE ReadBool*(VAR r: Rider; VAR x: BOOLEAN);
VAR s: SHORTINT;
BEGIN
  Read(r, s); x := s # 0
END ReadBool;

PROCEDURE ReadReal*(VAR r: Rider; VAR x: REAL);
BEGIN
  ReadBytes(r, SYSTEM.VAL(Bytes4, x), 4)
END ReadReal;

PROCEDURE ReadLReal*(VAR r: Rider; VAR x: LONGREAL);
BEGIN
  ReadBytes(r, SYSTEM.VAL(Bytes8, x), 8)
END ReadLReal;

PROCEDURE ReadString*(VAR r: Rider; VAR x: ARRAY OF CHAR);
VAR i: INTEGER; ch: CHAR;
BEGIN i := 0;
  LOOP
    Read(r, ch); x[i] := ch; INC(i);
    IF ch = 0X THEN EXIT END;
    IF i = LEN(x) THEN x[i-1] := 0X;
      REPEAT Read(r, ch) UNTIL ch = 0X;
      EXIT
    END
  END
END ReadString;

(** Reads a number in compressed variable length notation using the minimum amount of bytes. *)
PROCEDURE ReadNum*(VAR r: Rider; VAR x: LONGINT);
VAR ch: CHAR; n, y: LONGINT;
BEGIN
  n := 0; y := 0; Read(r, ch);
  WHILE ch >= 80X DO INC(y, SYSTEM.LSH(LONG(ORD(ch)) - 128, n)); INC(n, 7); Read(r, ch) END;
  x := ASH(SYSTEM.LSH(LONG(ORD(ch)), Linux0.RegSize-7), n-Linux0.RegSize + 7) + y
END ReadNum;

(** Writes the buffer x containing n bytes into a file at the Rider position. *)
PROCEDURE WriteBytes*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);
VAR f: File;  lo, ln: LONGINT;
BEGIN
  f:=r.file;
  lo:=(f.len+Linux0.PageSize-1)DIV Linux0.PageSize*Linux0.PageSize;  (* the length of the mapping *)
  IF lo=0 THEN lo:= Linux0.PageSize END;
  ln:=(r.apos+n+Linux0.PageSize-1) DIV Linux0.PageSize*Linux0.PageSize;
  IF (f.disk >= 0) & (r.apos+n > f.disk) THEN
    (* polpo: a file mapped shared is made longer on disk (whole pages) before the write: what is
       written after its end on disk, in its last page, is zeroed by the kernel whenever the page is
       written back, at any time (an .Arc archive lost a part of its entries now and then, on slow
       qemu-arm). Close and Register cut it to its length. *)
    IF ln < lo THEN ln:=lo END;
    IF 0#Linux0.Ftruncate0( f.fd, ln) THEN Kernel.WriteString("Files.WriteBytes: ftruncate "); Kernel.WriteString(f.Name); Kernel.WriteLn; HALT(102) END;
    f.disk:=ln;
    IF ln > lo THEN
      f.addr:=Linux0.Mremap0( f.addr, lo, ln, MremapMaymove, 0);
      IF f.addr MOD 1000H # 0 THEN Kernel.WriteString("mremap: "); Kernel.WriteHex(-f.addr, 9); Kernel.WriteLn END  (* an address, not an error; above 2 GB it is negative *)
    END
  ELSIF ln > lo THEN  (* a private mapping: new files, empty old ones *)
    IF trace THEN Kernel.WriteString("mremap: "); Kernel.WriteHex(f.addr, 9); Kernel.WriteHex(ln, 9); Kernel.WriteHex(lo, 9) END;
    f.addr:=Linux0.Mremap0( f.addr, lo, ln, MremapMaymove, 0);
    IF trace OR ( f.addr MOD 1000H # 0) THEN Kernel.WriteString("mremap: "); Kernel.WriteHex(r.apos, 9); Kernel.WriteHex(n, 9); Kernel.WriteHex(-f.addr, 9); Kernel.WriteLn END;
  END;
  IF LEN(x)<n THEN
    Kernel.WriteString("Files.WriteBytes: Array too small "); Kernel.WriteHex( LEN(x), 8); Kernel.WriteHex(n, 9); Kernel.WriteLn;
    HALT(103);
  END;
  SYSTEM.MOVE(SYSTEM.ADR(x[0]), f.addr+r.apos, n);
  f.changed:=TRUE;
  INC( r.apos, n);
  IF r.apos> f.len THEN f.len:=r.apos END;
  r.eof:= r.apos>= f.len;
END WriteBytes;

(* Writes a byte into the file at the Rider position, advancing the Rider by one. *)
PROCEDURE Write*(VAR r: Rider; x: SYSTEM.BYTE);
BEGIN  WriteBytes( r,  x, 1);
END Write;

(**
Portable routines to write the standard Oberon types.
*)

PROCEDURE WriteInt*(VAR r: Rider; x: INTEGER);
BEGIN
  WriteBytes(r, SYSTEM.VAL(Bytes2, x), 2)
END WriteInt;

PROCEDURE WriteLInt*(VAR r: Rider; x: LONGINT);
BEGIN
  WriteBytes(r, SYSTEM.VAL(Bytes4, x), 4)
END WriteLInt;

PROCEDURE WriteSet*(VAR r: Rider; x: SET);
BEGIN
  WriteBytes(r, SYSTEM.VAL(Bytes4, x), 4)
END WriteSet;

PROCEDURE WriteBool*(VAR r: Rider; x: BOOLEAN);
BEGIN
  IF x THEN Write(r, 1) ELSE Write(r, 0) END
END WriteBool;

PROCEDURE WriteReal*(VAR r: Rider; x: REAL);
BEGIN
  WriteBytes(r, SYSTEM.VAL(Bytes4, x), 4)
END WriteReal;

PROCEDURE WriteLReal*(VAR r: Rider; x: LONGREAL);
BEGIN
  WriteBytes(r, SYSTEM.VAL(Bytes8, x), 8)
END WriteLReal;

PROCEDURE WriteString*(VAR r: Rider; x: ARRAY OF CHAR);
VAR i: INTEGER; ch: CHAR;
BEGIN
  i := 0;
  LOOP ch := x[i]; Write(r, ch); INC(i);
    IF ch = 0X THEN EXIT END;
    IF i = LEN(x) THEN Write(r, 0X); EXIT END
  END
END WriteString;

(** Writes a number in a compressed format. *)
PROCEDURE WriteNum*(VAR r: Rider; x: LONGINT);
BEGIN
  WHILE (x < - 64) OR (x > 63) DO Write(r, CHR(x MOD 128 + 128)); x := x DIV 128 END;
  Write(r, CHR(x MOD 128))
END WriteNum;

(** Deletes a file. res = 0 indicates success. *)
PROCEDURE Delete*(name: ARRAY OF CHAR; VAR res: INTEGER);
VAR namebuf: FileName; r, dirfd: LONGINT;
BEGIN
  Check(name, namebuf, dirfd, res); 
  IF res=0 THEN
    r:= SHORT( Linux0.UnLinkat0( dirfd, SYSTEM.ADR( name[0]), 0));
    IF r#0 THEN res:=2 END;
  END;
END Delete;

(** Renames a file. res = 0 indicates success. *)
PROCEDURE Rename*(old, new: ARRAY OF CHAR; VAR res: INTEGER);
VAR olddirfd, newdirfd, i, j, k: LONGINT; oldname, newname, path: FileName;
BEGIN
  Check( old, oldname, olddirfd, res);
  Check( new, newname, newdirfd, res);
  (* polpo: a file found in the search path is renamed there, System.Tool -> System.Tool.Bak *)
  COPY(oldname, path); Locate(oldname, olddirfd);
  IF oldname#path THEN
    i:=0; WHILE (newname[i]#0X) & (newname[i]#"/") DO INC(i) END;
    IF newname[i]#"/" THEN
      k:=-1; i:=0; WHILE oldname[i]#0X DO IF oldname[i]="/" THEN k:=i END; INC(i) END;
      i:=0; WHILE i<=k DO path[i]:=oldname[i]; INC(i) END;
      j:=0; WHILE (newname[j]#0X) & (i<LEN(path)-1) DO path[i]:=newname[j]; INC(i); INC(j) END;
      path[i]:=0X; COPY(path, newname); newdirfd:=Linux0.ATFDCWD
    END
  END;
  res:= SHORT( Linux0.Renameat0( olddirfd, SYSTEM.ADR( oldname[0]), newdirfd, SYSTEM.ADR( newname[0]), 0));
END Rename;

(** Returns the full name of a file. *)
PROCEDURE GetName*(f: File; VAR name: ARRAY OF CHAR);
BEGIN
  COPY( f.Name, name);
END GetName;

BEGIN
  trace:= Kernel.trace="Files";
  SetSYS(".");
  SetWRK("");
  (* polpo: plain names are also looked up in the polpo root and its share/, tools/, fonts/ *)
  nofSearch:=0;
  IF Root.path#"" THEN COPY(Root.path, searchPath[0]); nofSearch:=1 END;
  Root.Join("share/", searchPath[nofSearch]); INC(nofSearch);
  Root.Join("tools/", searchPath[nofSearch]); INC(nofSearch);
  Root.Join("fonts/", searchPath[nofSearch]); INC(nofSearch);
END Files.

(** Remarks:

1. Oberon uses the little-endian byte ordering for exchanging files between different Oberon platforms.

2. Files are separate entities from directory entries. Files may be anonymous by having no name and not being registered in a
  directory. Files only become visible to other clients of the Files module by explicitly passing a File descriptor or by registering
  a file and then opening it from the other client. Deleting a file of which a file descriptor is still available, results in the file
  becoming anonymous. The deleted file may be re-registered at any time.

3. Files and their access mechanism (Riders) are separated. A file might have more than one rider operating on it at different
  offsets in the file.

4. The garbage collector will automatically close files when they are not required any more. File buffers will be discarded
  without flushing them to disk.  Use the Close procedure to update modified files on disk.

5. Relative and absolute filenames written in the directory syntax of the host operating system are used. By convention, Oberon
  filenames consists of the letters A..Z, a..z, 0..9, and ".". The directory separator is typically / or :. Oberon filenames are
  case sensitive. *)
