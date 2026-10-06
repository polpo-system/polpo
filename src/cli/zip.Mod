MODULE zip;  (** zip archives in the console, with Zip of ETH Oberon *)

(* zip.Directory archive.zip             the entries: name, size, compressed size
   zip.Add archive.zip file ...          adds the files (deflate); the archive is created if needed
   zip.Extract archive.zip [file ...]    the named entries, or all; directories are created
   zip.Delete archive.zip file ...       removes entries
   The archives are those of zip and unzip (deflate or stored, no encryption). ZipTool is the
   desktop tool. *)

IMPORT SYSTEM, Linux0, Files, Zip, texts, out;

CONST MaxFiles = 128;

TYPE Name = ARRAY 256 OF CHAR;

PROCEDURE Args(VAR archive: ARRAY OF CHAR; VAR files: ARRAY OF Name; VAR n: INTEGER): BOOLEAN;
VAR A: texts.Reader;
BEGIN
  texts.OpenArgs(A); n := 0;
  IF ~texts.Arg(A, archive) THEN RETURN FALSE END;
  WHILE (n < LEN(files)) & texts.Arg(A, files[n]) DO INC(n) END;
  RETURN TRUE
END Args;

PROCEDURE Error(VAR archive, entry: ARRAY OF CHAR; res: LONGINT);
BEGIN
  out.String("zip: "); out.String(archive); IF entry # "" THEN out.String(", "); out.String(entry) END; out.String(": ");
  IF res = Zip.FileError THEN out.String("no such file")
  ELSIF res = Zip.NotZipArchiveError THEN out.String("not a zip archive")
  ELSIF res = Zip.EntryNotFound THEN out.String("no such entry")
  ELSIF res = Zip.EntryAlreadyExists THEN out.String("the entry exists")
  ELSIF res = Zip.NotSupportedError THEN out.String("compression method not supported, or encrypted")
  ELSIF res = Zip.DataError THEN out.String("damaged")
  ELSIF res = Zip.BadName THEN out.String("bad name")
  ELSE out.String("error "); out.Int(res, 0)
  END;
  out.Ln
END Error;

PROCEDURE MakeDirs(VAR path: ARRAY OF CHAR);  (* the directories of the file path *)
VAR i, r: LONGINT; dir: Name;
BEGIN
  dir[0] := path[0]; i := 1;
  WHILE (path[i] # 0X) & (i < LEN(dir) - 1) DO
    IF path[i] = "/" THEN dir[i] := 0X; r := Linux0.MkDir0(SYSTEM.ADR(dir), 1EDH) END;
    dir[i] := path[i]; INC(i)
  END
END MakeDirs;

PROCEDURE Directory*;
VAR archive: Name; files: ARRAY 1 OF Name; n: INTEGER; arc: Zip.Archive; e: Zip.Entry; res: LONGINT; none: Name;
BEGIN
  IF ~Args(archive, files, n) THEN out.String("usage: zip.Directory archive.zip"); out.Ln; RETURN END;
  arc := Zip.OpenArchive(archive, res); none := "";
  IF arc = NIL THEN Error(archive, none, res); RETURN END;
  e := Zip.FirstEntry(arc);
  WHILE e # NIL DO
    out.String(e.name); out.String("  "); out.Int(e.uncompSize, 0); out.String(" bytes, "); out.Int(e.compSize, 0); out.String(" compressed"); out.Ln;
    e := Zip.NextEntry(e)
  END;
  out.String("zip: "); out.Int(arc.nofEntries, 0); out.String(" entries"); out.Ln
END Directory;

PROCEDURE Add*;
VAR archive: Name; files: ARRAY MaxFiles OF Name; n, i: INTEGER; arc: Zip.Archive; res: LONGINT; f: Files.File; R: Files.Rider; none: Name;
BEGIN
  IF ~Args(archive, files, n) OR (n = 0) THEN out.String("usage: zip.Add archive.zip file ..."); out.Ln; RETURN END;
  none := ""; arc := Zip.OpenArchive(archive, res);
  IF arc = NIL THEN arc := Zip.CreateArchive(archive, res) END;
  IF arc = NIL THEN Error(archive, none, res); RETURN END;
  i := 0;
  WHILE i < n DO
    f := Files.Old(files[i]);
    IF f = NIL THEN out.String("zip: no "); out.String(files[i]); out.Ln
    ELSE
      Files.Set(R, f, 0); Zip.AddEntry(arc, files[i], R, Files.Length(f), Zip.DefaultCompression, Zip.DefaultStrategy, res);
      IF res = Zip.Ok THEN out.String("zip: added "); out.String(files[i]); out.Ln ELSE Error(archive, files[i], res) END
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

PROCEDURE ExtractOne(arc: Zip.Archive; e: Zip.Entry; VAR archive: ARRAY OF CHAR);
VAR f: Files.File; R: Files.Rider; res: LONGINT; i: LONGINT;
BEGIN
  IF ~Safe(e.name) THEN out.String("zip: skipped "); out.String(e.name); out.String(", outside the directory"); out.Ln; RETURN END;
  i := 0; WHILE e.name[i] # 0X DO INC(i) END;
  IF (i > 0) & (e.name[i-1] = "/") THEN MakeDirs(e.name); RETURN END;  (* a directory *)
  MakeDirs(e.name); f := Files.New(e.name); Files.Set(R, f, 0); Zip.ExtractEntry(arc, e, R, res);
  IF res = Zip.Ok THEN Files.Register(f); out.String("zip: extracted "); out.String(e.name); out.Ln
  ELSE Error(archive, e.name, res)
  END
END ExtractOne;

PROCEDURE Extract*;
VAR archive: Name; files: ARRAY MaxFiles OF Name; n, i: INTEGER; arc: Zip.Archive; e: Zip.Entry; res: LONGINT; none: Name;
BEGIN
  IF ~Args(archive, files, n) THEN out.String("usage: zip.Extract archive.zip [file ...]"); out.Ln; RETURN END;
  none := ""; arc := Zip.OpenArchive(archive, res);
  IF arc = NIL THEN Error(archive, none, res); RETURN END;
  IF n = 0 THEN
    e := Zip.FirstEntry(arc); WHILE e # NIL DO ExtractOne(arc, e, archive); e := Zip.NextEntry(e) END
  ELSE
    i := 0;
    WHILE i < n DO
      e := Zip.GetEntry(arc, files[i], res);
      IF e = NIL THEN Error(archive, files[i], res) ELSE ExtractOne(arc, e, archive) END;
      INC(i)
    END
  END
END Extract;

PROCEDURE Delete*;
VAR archive: Name; files: ARRAY MaxFiles OF Name; n, i: INTEGER; arc: Zip.Archive; e: Zip.Entry; res: LONGINT; none: Name;
BEGIN
  IF ~Args(archive, files, n) OR (n = 0) THEN out.String("usage: zip.Delete archive.zip file ..."); out.Ln; RETURN END;
  none := ""; arc := Zip.OpenArchive(archive, res);
  IF arc = NIL THEN Error(archive, none, res); RETURN END;
  i := 0;
  WHILE i < n DO
    e := Zip.GetEntry(arc, files[i], res);
    IF e = NIL THEN Error(archive, files[i], res)
    ELSE Zip.DeleteEntry(arc, e, res); IF res = Zip.Ok THEN out.String("zip: deleted "); out.String(files[i]); out.Ln ELSE Error(archive, files[i], res) END
    END;
    INC(i)
  END
END Delete;

END zip.
