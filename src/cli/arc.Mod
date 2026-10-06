MODULE arc;  (** Oberon archives (.Arc of Compress) in the console *)

(* arc.Create archive              an empty archive
   arc.Directory archive           its entries: name, length, compression, date
   arc.Add archive file ...        adds (or replaces) the files; the archive is created if needed
   arc.Extract archive [file ...]  the named entries, or all
   arc.Delete archive file ...     removes entries
   Add, Extract: \C module.Install "key" before the archive encrypts or decrypts with the cipher
   of module (CompressCrypt for the one of System 3), as Compress.Add \C ... in System 3.
   The archives are those of Compress of ETH Oberon (LZSS, names of at most 31 characters); the
   work is done by Compress0. *)

IMPORT Files, Modules, texts, Compress0, out;

CONST MaxFiles = 128; MaxEntries = 1024;

TYPE Name = ARRAY 256 OF CHAR;

VAR count: LONGINT; noCipher: BOOLEAN;
  entries: ARRAY MaxEntries OF ARRAY 32 OF CHAR;  (* the \C cipher was not found: no usage message *)

PROCEDURE Error(VAR archive: ARRAY OF CHAR; entry: ARRAY OF CHAR; res: INTEGER);
BEGIN
  out.String("arc: "); out.String(archive);
  IF entry # "" THEN out.String(", "); out.String(entry) END; out.String(": ");
  CASE res OF
    Compress0.ArchiveNotFound: out.String("no such archive")
  | Compress0.ErrorInArchive: out.String("error in the archive")
  | Compress0.EntryNotFound: out.String("no such entry")
  | Compress0.ArchiveExists: out.String("the archive exists")
  | Compress0.FileError: out.String("file error")
  | Compress0.KeyNeeded: out.String("encrypted, a key is needed")
  ELSE out.String("error "); out.Int(res, 0)
  END;
  out.Ln
END Error;

PROCEDURE Usage(s: ARRAY OF CHAR);
BEGIN IF ~noCipher THEN out.String(s); out.Ln END
END Usage;

(* the command install (module.Command) exists; Compress0.InstallCrypt traps when it does not *)
PROCEDURE Cipher(VAR install: ARRAY OF CHAR): BOOLEAN;
VAR mod: Modules.Module; name, cmd: Name; i, j: LONGINT;
BEGIN
  i := 0; WHILE (install[i] # 0X) & (install[i] # ".") DO name[i] := install[i]; INC(i) END; name[i] := 0X;
  IF install[i] = "." THEN
    INC(i); j := 0; WHILE install[i] # 0X DO cmd[j] := install[i]; INC(i); INC(j) END; cmd[j] := 0X;
    mod := Modules.ThisMod(name);
    IF (mod # NIL) & (Modules.ThisCommand(mod, cmd) # NIL) THEN RETURN TRUE END
  END;
  out.String("arc: no cipher "); out.String(install); out.String(" (module.Install, as CompressCrypt.Install)"); out.Ln;
  RETURN FALSE
END Cipher;

(* the arguments: [\C install key] archive files; with \C the cipher is installed *)
PROCEDURE Args(VAR archive: ARRAY OF CHAR; VAR files: ARRAY OF Name; VAR n: INTEGER): BOOLEAN;
VAR A: texts.Reader; install, key: Name;
BEGIN
  texts.OpenArgs(A); n := 0; noCipher := FALSE; Compress0.ClearCrypt;
  IF ~texts.Arg(A, archive) THEN RETURN FALSE END;
  IF (archive = "\C") OR (archive = "\c") THEN
    IF ~texts.Arg(A, install) OR ~texts.Arg(A, key) OR ~texts.Arg(A, archive) THEN RETURN FALSE END;
    IF ~Cipher(install) THEN noCipher := TRUE; RETURN FALSE END;
    Compress0.InstallCrypt(install, key)
  END;
  WHILE (n < LEN(files)) & texts.Arg(A, files[n]) DO INC(n) END;
  RETURN TRUE
END Args;

PROCEDURE Create*;
VAR archive: Name; files: ARRAY 1 OF Name; n, res: INTEGER;
BEGIN
  IF ~Args(archive, files, n) THEN Usage("usage: arc.Create archive"); RETURN END;
  Compress0.CreateArchive(archive, res);
  IF res = Compress0.Done THEN out.String("arc: "); out.String(archive); out.String(" created"); out.Ln ELSE Error(archive, "", res) END
END Create;

PROCEDURE Two(n: LONGINT);  (* two digits *)
BEGIN out.Char(CHR(n DIV 10 MOD 10 + ORD("0"))); out.Char(CHR(n MOD 10 + ORD("0")))
END Two;

PROCEDURE ShowEntry(h: Compress0.Header; VAR stop: BOOLEAN);
BEGIN
  out.String(h.name); out.String("  "); out.Int(h.length, 0); out.String(" bytes compressed (");
  out.Int(ENTIER(h.ratio), 0); out.String("%)  ");
  out.Int(h.date DIV 512 + 1900, 0); out.Char("-"); Two(h.date DIV 32 MOD 16); out.Char("-"); Two(h.date MOD 32);
  out.Char(" "); Two(h.time DIV 4096); out.Char(":"); Two(h.time DIV 64 MOD 64);
  IF Compress0.encryption IN h.extensions THEN out.String("  encrypted") END;
  out.Ln; INC(count); stop := FALSE
END ShowEntry;

PROCEDURE Directory*;
VAR archive: Name; files: ARRAY 1 OF Name; n, res: INTEGER;
BEGIN
  IF ~Args(archive, files, n) THEN Usage("usage: arc.Directory archive"); RETURN END;
  count := 0; Compress0.Enumerate(archive, ShowEntry, TRUE, res);
  IF res = Compress0.Done THEN out.String("arc: "); out.Int(count, 0); out.String(" entries"); out.Ln ELSE Error(archive, "", res) END
END Directory;

PROCEDURE Add*;
VAR archive: Name; files: ARRAY MaxFiles OF Name; n, i, res: INTEGER; f: Files.File; R: Files.Rider; entry: Compress0.Name;
BEGIN
  IF ~Args(archive, files, n) OR (n = 0) THEN Usage("usage: arc.Add archive file ..."); RETURN END;
  IF Files.Old(archive) = NIL THEN Compress0.CreateArchive(archive, res) END;
  i := 0;
  WHILE i < n DO
    f := Files.Old(files[i]);
    IF f = NIL THEN out.String("arc: no "); out.String(files[i]); out.Ln
    ELSE
      COPY(files[i], entry); Compress0.DeleteFile(archive, entry, res);  (* replaced if there *)
      Files.Set(R, f, 0); Compress0.AddFile(archive, entry, R, Files.Length(f), res);
      IF res = Compress0.Done THEN out.String("arc: added "); out.String(entry); out.Ln ELSE Error(archive, files[i], res) END
    END;
    INC(i)
  END
END Add;

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

PROCEDURE Collect(h: Compress0.Header; VAR stop: BOOLEAN);  (* the names of the entries, for ExtractAll *)
BEGIN
  IF count < MaxEntries THEN COPY(h.name, entries[count]); INC(count) END; stop := FALSE
END Collect;

PROCEDURE ExtractOne(VAR archive, name: ARRAY OF CHAR): BOOLEAN;
VAR f: Files.File; R: Files.Rider; res: INTEGER;
BEGIN
  IF ~Safe(name) THEN out.String("arc: skipped "); out.String(name); out.String(", outside the directory"); out.Ln; RETURN TRUE END;
  f := Files.New(name); Files.Set(R, f, 0); Compress0.ExtractFile(archive, name, R, res);
  IF res = Compress0.Done THEN Files.Register(f); out.String("arc: extracted "); out.String(name); out.Ln
  ELSE Error(archive, name, res)
  END;
  RETURN res # Compress0.KeyNeeded
END ExtractOne;

PROCEDURE Extract*;
VAR archive: Name; files: ARRAY MaxFiles OF Name; n, i, res: INTEGER;
BEGIN
  IF ~Args(archive, files, n) THEN Usage("usage: arc.Extract archive [file ...]"); RETURN END;
  IF n = 0 THEN
    count := 0; Compress0.Enumerate(archive, Collect, FALSE, res);
    IF res # Compress0.Done THEN Error(archive, "", res); RETURN END;
    i := 0; WHILE (i < count) & ExtractOne(archive, entries[i]) DO INC(i) END;
    IF count = MaxEntries THEN out.String("arc: only the first "); out.Int(MaxEntries, 0); out.String(" entries"); out.Ln END
  ELSE
    i := 0; WHILE (i < n) & ExtractOne(archive, files[i]) DO INC(i) END
  END
END Extract;

PROCEDURE Delete*;
VAR archive: Name; files: ARRAY MaxFiles OF Name; n, i, res: INTEGER;
BEGIN
  IF ~Args(archive, files, n) OR (n = 0) THEN Usage("usage: arc.Delete archive file ..."); RETURN END;
  i := 0;
  WHILE i < n DO
    Compress0.DeleteFile(archive, files[i], res);
    IF res = Compress0.Done THEN out.String("arc: deleted "); out.String(files[i]); out.Ln ELSE Error(archive, files[i], res) END;
    INC(i)
  END
END Delete;

END arc.
