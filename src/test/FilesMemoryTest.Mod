MODULE FilesMemoryTest;  (** loksh FilesMemoryTest.Run: files in memory (Files.NewMemory, FromBytes) and Purge *)

(* After the PictureMemoryTest of voc 4.0.6: a file in memory has a fixed capacity; a write beyond it writes
  nothing, sets the rider's res and makes MemoryFailed TRUE until Purge; Set keeps the rider inside the file;
  Close, Register and GetDate do nothing; FromBytes copies. Then the same rider operations on a file on
  disk, and Purge of it. *)

IMPORT Files, Out;

VAR checks, failed: LONGINT; phase: ARRAY 64 OF CHAR;

PROCEDURE Check(ok: BOOLEAN);
BEGIN
  INC(checks);
  IF ~ok THEN INC(failed); Out.String("FAIL "); Out.String(phase); Out.String(", check "); Out.Int(checks, 0); Out.Ln END
END Check;

PROCEDURE Equal(VAR a, b: ARRAY OF CHAR; length: LONGINT): BOOLEAN;
VAR i: LONGINT;
BEGIN
  IF (length < 0) OR (length > LEN(a)) OR (length > LEN(b)) THEN RETURN FALSE END;
  i := 0; WHILE i < length DO IF a[i] # b[i] THEN RETURN FALSE END; INC(i) END;
  RETURN TRUE
END Equal;

PROCEDURE Fill(VAR bytes: ARRAY OF CHAR);
VAR i, seed: LONGINT;
BEGIN
  seed := 1; i := 0;
  WHILE i < LEN(bytes) DO seed := (seed * 75 + 74) MOD 65537; bytes[i] := CHR(seed MOD 256); INC(i) END
END Fill;

PROCEDURE Memory;
VAR f, other: Files.File; r, s: Files.Rider; src, dst, bytes: Files.Bytes;
  i, n, t, d: LONGINT; c: CHAR; name: ARRAY 256 OF CHAR; chunk: ARRAY 4 OF CHAR; abc: ARRAY 4 OF CHAR;
  flag: BOOLEAN; short: INTEGER; number: LONGINT; real: REAL; lreal: LONGREAL; set: SET;
BEGIN
  phase := "boundaries"; abc := "abc";
  Check(Files.NewMemory(-1) = NIL); Check(Files.FromBytes(abc, -1) = NIL); Check(Files.FromBytes(abc, 5) = NIL);
  f := Files.NewMemory(0); Check(Files.IsMemory(f) & ~Files.MemoryFailed(f));
  bytes := Files.MemoryData(f, n); Check((bytes # NIL) & (n = 0));
  Files.Set(r, f, 0); Files.Read(r, c); Check(r.eof & (c = 0X));
  Files.Write(r, "x"); Check((r.res = 1) & Files.MemoryFailed(f) & (Files.Length(f) = 0));
  Check(Files.MemoryData(f, n) = NIL); Check(n = 0);

  phase := "capacity and Purge";
  f := Files.NewMemory(4); Files.Set(r, f, 0); Files.Write(r, "a"); Files.Write(r, "b");
  chunk := "cde"; Files.WriteBytes(r, chunk, 3); Check((r.res = 3) & Files.MemoryFailed(f) & (Files.Length(f) = 2));
  Files.Set(r, f, 0); Files.Write(r, "X"); Check((r.res = 1) & Files.MemoryFailed(f));
  Files.Set(r, f, 0); Files.Read(r, c); Check(c = "a");
  Files.Purge(f); Check(~Files.MemoryFailed(f) & (Files.Length(f) = 0));
  Files.Write(r, "z"); Check((r.res = 0) & (Files.Length(f) = 1));
  bytes := Files.MemoryData(f, n); Check((n = 1) & (bytes[0] = "z"));

  phase := "64 KB byte by byte";
  NEW(src, 65537); NEW(dst, 65540); Fill(src^);
  f := Files.NewMemory(LEN(src^)); Files.Set(r, f, 0);
  i := 0; WHILE i < LEN(src^) DO Files.Write(r, src[i]); INC(i) END;
  Check((Files.Pos(r) = LEN(src^)) & (Files.Length(f) = LEN(src^)) & ~Files.MemoryFailed(f));
  Files.Set(s, f, 0); Files.ReadBytes(s, dst^, LEN(src^));
  Check((s.res = 0) & ~s.eof & Equal(src^, dst^, LEN(src^)));
  Files.Set(s, f, 4095); Files.Write(s, 0FFX); Files.Set(r, f, 4095); Files.Read(r, c); Check(c = 0FFX);
  Files.Set(s, f, 65535); Files.ReadBytes(s, dst^, 5);
  Check(s.eof & (s.res = 3) & (dst[0] = src[65535]) & (dst[1] = src[65536]));
  Files.Set(s, f, MAX(LONGINT)); Check(Files.Pos(s) = 65537);
  Files.Set(s, f, -1); Check(Files.Pos(s) = 0);
  Files.Close(f); Files.Register(f); Files.GetDate(f, t, d); Check((t = 0) & (d = 0));
  Files.GetName(f, name); Check(name = "");

  phase := "FromBytes copies";
  other := Files.FromBytes(src^, LEN(src^)); Check(Files.IsMemory(other));
  c := src[0]; src[0] := CHR((ORD(c) + 1) MOD 256);
  Files.Set(s, other, 0); Files.Read(s, src[0]); Check(src[0] = c);
  f := Files.NewMemory(LEN(src^)); Files.Set(r, f, 0); Files.WriteBytes(r, src^, LEN(src^));
  Files.Set(s, f, 0); Files.ReadBytes(s, dst^, LEN(src^)); Check(Equal(src^, dst^, LEN(src^)));

  phase := "numbers and strings";
  f := Files.NewMemory(1024); Files.Set(r, f, 0);
  Files.WriteBool(r, TRUE); Files.WriteInt(r, -12345); Files.WriteLInt(r, -123456789);
  Files.WriteReal(r, 1.5); Files.WriteLReal(r, -2.25D0); Files.WriteSet(r, {0, 7, 31}); Files.WriteString(r, "memory");
  Check(~Files.MemoryFailed(f)); Files.Set(s, f, 0);
  Files.ReadBool(s, flag); Check(flag); Files.ReadInt(s, short); Check(short = -12345);
  Files.ReadLInt(s, number); Check(number = -123456789); Files.ReadReal(s, real); Check(real = 1.5);
  Files.ReadLReal(s, lreal); Check(lreal = -2.25D0);
  Files.ReadSet(s, set); Check(set = {0, 7, 31}); Files.ReadString(s, name); Check(name = "memory");
  f := Files.NewMemory(2); Files.Set(r, f, 0); Files.WriteLInt(r, 1234);
  Check(Files.MemoryFailed(f) & (Files.Length(f) = 0));
  f := Files.NewMemory(6); Files.Set(r, f, 0); Files.WriteLReal(r, 1.0D0);
  Check(Files.MemoryFailed(f) & (Files.Length(f) = 0))
END Memory;

PROCEDURE Disk;
VAR f, old: Files.File; r: Files.Rider; data, copy: Files.Bytes; res: INTEGER; i: LONGINT;
BEGIN
  phase := "a file on disk"; NEW(data, 65537); NEW(copy, 65537); Fill(data^);
  f := Files.New("zq_filesmemory.bin"); Check(~Files.IsMemory(f) & ~Files.MemoryFailed(f)); Files.Set(r, f, 0);
  Files.WriteBytes(r, data^, LEN(data^)); Files.Register(f); Files.Close(f);
  Check(Files.Length(f) = LEN(data^)); Check(Files.MemoryData(f, i) = NIL);
  old := Files.Old("zq_filesmemory.bin"); Check(old # NIL); Files.Set(r, old, 0);
  Files.ReadBytes(r, copy^, LEN(copy^)); Check((r.res = 0) & Equal(data^, copy^, LEN(data^)));
  Files.Set(r, old, 4095); Files.Write(r, 0FFX); Files.Close(old); Files.Set(r, old, 4095);
  Files.Read(r, copy[0]); Check(copy[0] = 0FFX);
  Files.Purge(old); Check(Files.Length(old) = 0); Files.Set(r, old, 0);
  i := 0; WHILE i < 256 DO Files.Write(r, CHR(i)); INC(i) END; Files.Close(old);
  old := Files.Old("zq_filesmemory.bin"); Check((old # NIL) & (Files.Length(old) = 256)); Files.Set(r, old, 0);
  i := 0; WHILE i < 256 DO Files.Read(r, copy[i]); Check(copy[i] = CHR(i)); INC(i) END;
  Files.Delete("zq_filesmemory.bin", res); Check(Files.Old("zq_filesmemory.bin") = NIL)
END Disk;

PROCEDURE Run*;
BEGIN
  checks := 0; failed := 0;
  Memory; Disk;
  Out.String("FilesMemoryTest: "); Out.Int(checks, 0); Out.String(" checks, "); Out.Int(failed, 0); Out.String(" failed"); Out.Ln
END Run;

END FilesMemoryTest.
