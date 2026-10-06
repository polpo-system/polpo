MODULE OocIOTest;  (** loksh OocIOTest.Run alpha "b c": the channels of the OOC library (x86) *)

(* Writes and reads zq_oocio1.txt (TextRider) and zq_oocio2.bin (a Tmp file, BinaryRider) in the
   current directory, then deletes them; ProgramArgs gives the command name and the arguments. *)

IMPORT oocFiles, TextRider, BinaryRider, ProgramArgs, Files, out;

VAR fails, checks: LONGINT;

PROCEDURE Check(what: ARRAY OF CHAR; ok: BOOLEAN);
BEGIN
  INC(checks);
  IF ~ok THEN INC(fails); out.String("OocIOTest: failed: "); out.String(what); out.Ln END
END Check;

PROCEDURE Text;
VAR f: oocFiles.File; res: oocFiles.Result; w: TextRider.Writer; r: TextRider.Reader;
  s: ARRAY 64 OF CHAR; i: LONGINT; x: LONGREAL;
BEGIN
  f := oocFiles.New("zq_oocio1.txt", {oocFiles.read, oocFiles.write}, res);
  Check("oocFiles.New", (f # NIL) & (res = oocFiles.done));
  IF f = NIL THEN RETURN END;
  w := TextRider.ConnectWriter(f);
  w.WriteString("hello"); w.WriteLn; w.WriteLInt(-42, 0); w.WriteLn; w.WriteLReal(2.5D0, 12, 4); w.WriteLn;
  f.Register; f.Close;
  Check("oocFiles.Exists", oocFiles.Exists("zq_oocio1.txt"));
  f := oocFiles.Old("zq_oocio1.txt", {oocFiles.read}, res);
  Check("oocFiles.Old", (f # NIL) & (res = oocFiles.done));
  IF f = NIL THEN RETURN END;
  Check("File.Length", f.Length() > 10);
  r := TextRider.ConnectReader(f);
  r.ReadLine(s); Check("TextRider.ReadLine", s = "hello");
  r.ReadLInt(i); Check("TextRider.ReadLInt", i = -42);
  r.ReadLReal(x); Check("TextRider.ReadLReal", x = 2.5D0);
  f.Close
END Text;

PROCEDURE Binary;
VAR f: oocFiles.File; res: oocFiles.Result; w: BinaryRider.Writer; r: BinaryRider.Reader; i, n: LONGINT;
BEGIN
  f := oocFiles.Tmp("zq_oocio2.bin", {oocFiles.write}, res);
  Check("oocFiles.Tmp", (f # NIL) & (res = oocFiles.done));
  IF f = NIL THEN RETURN END;
  w := BinaryRider.ConnectWriter(f); w.WriteLInt(123456789); w.WriteNum(-300);
  Check("not there before Register", ~oocFiles.Exists("zq_oocio2.bin"));
  f.Register; Check("File.Register", f.res = oocFiles.done); f.Close;
  Check("there after Register", oocFiles.Exists("zq_oocio2.bin"));
  f := oocFiles.Old("zq_oocio2.bin", {oocFiles.read}, res);
  IF f = NIL THEN Check("oocFiles.Old binary", FALSE); RETURN END;
  r := BinaryRider.ConnectReader(f); r.ReadLInt(i); r.ReadNum(n);
  Check("BinaryRider", (i = 123456789) & (n = -300));
  f.Close
END Binary;

PROCEDURE Args;
VAR r: TextRider.Reader; s: ARRAY 64 OF CHAR;
BEGIN
  r := TextRider.ConnectReader(ProgramArgs.args);
  r.ReadLine(s); Check("ProgramArgs: the command", s = "OocIOTest.Run");
  r.ReadLine(s); Check("ProgramArgs: alpha", s = "alpha");
  r.ReadLine(s); Check("ProgramArgs: b c", s = "b c")
END Args;

PROCEDURE Run*;
VAR res: INTEGER;
BEGIN
  fails := 0; checks := 0;
  Text; Binary; Args;
  Files.Delete("./zq_oocio1.txt", res); Files.Delete("./zq_oocio2.bin", res);
  out.String("OocIOTest: "); out.Int(checks, 0); out.String(" checks, "); out.Int(fails, 0); out.String(" failed"); out.Ln
END Run;

END OocIOTest.
