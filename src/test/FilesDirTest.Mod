MODULE FilesDirTest;  (** loksh FilesDirTest.Run: Files.CreateDirectory, RemoveDirectory, Exists; run it in a scratch directory *)

IMPORT Files, out;

VAR fails, checks: LONGINT;

PROCEDURE Check(what: ARRAY OF CHAR; ok: BOOLEAN);
BEGIN
  INC(checks);
  IF ~ok THEN INC(fails); out.String("FAIL "); out.String(what); out.Ln END
END Check;

PROCEDURE Write(name, text: ARRAY OF CHAR);
VAR f: Files.File; r: Files.Rider;
BEGIN f := Files.New(name); Files.Set(r, f, 0); Files.WriteString(r, text); Files.Register(f)
END Write;

PROCEDURE Run*;
VAR res: INTEGER; flags: SET; full: Files.FileName;
BEGIN
  fails := 0; checks := 0;
  Files.RemoveDirectory("zq_dir", TRUE, res);  (* left over from an earlier run *)
  Files.CreateDirectory("zq_dir", res); Check("CreateDirectory", res = 0);
  Files.CreateDirectory("zq_dir", res); Check("CreateDirectory of an existing directory fails", res # 0);
  Check("Exists of a directory", Files.Exists("zq_dir", full, flags) & (Files.Directory IN flags) & (full = "zq_dir"));
  Write("zq_dir/a.txt", "a");
  Check("Exists of a file", Files.Exists("zq_dir/a.txt", full, flags) & ~(Files.Directory IN flags) & ~(Files.ReadOnly IN flags));
  Check("Exists of nothing", ~Files.Exists("zq_dir/none.txt", full, flags) & (full = ""));
  Write("zq_dir/2024 notes սոնա.txt", "u");
  Check("a name with a digit first, a blank and UTF-8", Files.Exists("zq_dir/2024 notes սոնա.txt", full, flags));
  Files.CreateDirectory("zq_dir/sub", res); Check("CreateDirectory inside", res = 0);
  Write("zq_dir/sub/b.txt", "b");
  Files.CreateDirectory("zq_dir/sub/deeper", res); Write("zq_dir/sub/deeper/c.txt", "c");
  Files.RemoveDirectory("zq_dir", FALSE, res); Check("RemoveDirectory of a full directory fails", res # 0);
  Check("and leaves it", Files.Exists("zq_dir/sub/b.txt", full, flags));
  Files.CreateDirectory("zq_dir/empty", res); Files.RemoveDirectory("zq_dir/empty", FALSE, res);
  Check("RemoveDirectory of an empty one", (res = 0) & ~Files.Exists("zq_dir/empty", full, flags));
  Files.RemoveDirectory("zq_dir", TRUE, res); Check("RemoveDirectory force", (res = 0) & ~Files.Exists("zq_dir", full, flags));
  out.String("FilesDirTest: "); out.Int(checks, 0); out.String(" checks, "); out.Int(fails, 0); out.String(" failed"); out.Ln
END Run;

END FilesDirTest.
