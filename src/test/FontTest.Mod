MODULE FontTest;  (** DISPLAY=... loksh FontTest.Run: damaged and missing fonts are substituted, not trapped *)

(* The fonts are loaded before the desktop sets Fonts.Default (Oberon is not imported), so a
   substitute has to come from Oberon10.Scn.Fnt or the empty font. The damaged files are copies of
   Oberon10.Scn.Fnt with one field changed, written to zq_*.Scn.Fnt in the current directory. *)

IMPORT Files, Fonts, Objects, out;

CONST Good = "Oberon10.Scn.Fnt";
  RunsAt = 14;  (* byte offset of the number of runs: id, type, family, variant, 5 integers *)

VAR fails, checks: LONGINT;
  good: ARRAY 16384 OF CHAR; len: LONGINT;

PROCEDURE Check(what: ARRAY OF CHAR; ok: BOOLEAN);
BEGIN
  INC(checks);
  IF ~ok THEN INC(fails); out.String("FontTest: failed: "); out.String(what); out.Ln END
END Check;

PROCEDURE Int(a: LONGINT): INTEGER;  (* the little endian integer of the good font at a *)
BEGIN RETURN SHORT(ORD(good[a]) + LONG(ORD(good[a+1])) * 256)
END Int;

(* write the good font with its integer at a set to x, cut at n bytes (n < 0: whole) *)
PROCEDURE Write(name: ARRAY OF CHAR; a: LONGINT; x: INTEGER; n: LONGINT);
VAR F: Files.File; R: Files.Rider; i: LONGINT;
BEGIN
  IF n < 0 THEN n := len END;
  F := Files.New(name); Files.Set(R, F, 0); i := 0;
  WHILE i < n DO
    IF (a >= 0) & (i = a) THEN Files.Write(R, CHR(x MOD 256))
    ELSIF (a >= 0) & (i = a + 1) THEN Files.Write(R, CHR(x DIV 256 MOD 256))
    ELSE Files.Write(R, good[i])
    END;
    INC(i)
  END;
  Files.Register(F)
END Write;

PROCEDURE Substituted(name: ARRAY OF CHAR);
VAR F: Fonts.Font; obj: Objects.Object;
BEGIN
  F := Fonts.This(name);
  Check(name, (F # NIL) & (F.type = Fonts.substitute) & (F.height > 0) & (F.ind # NIL));
  IF F # NIL THEN  (* drawing it reads the index: a character and one outside the index *)
    F.GetObj(F, ORD("A"), obj); Check("A of a substitute", (obj # NIL) & (obj IS Fonts.Char));
    F.GetObj(F, F.maxRef + 10, obj); Check("outside the index", (obj # NIL) & (obj(Fonts.Char).w <= 255))
  END
END Substituted;

PROCEDURE Delete(name: ARRAY OF CHAR);
VAR res: INTEGER;
BEGIN Files.Delete(name, res)
END Delete;

PROCEDURE Run*;
VAR F: Fonts.Font; G: Files.File; R: Files.Rider; nr: INTEGER;
BEGIN
  fails := 0; checks := 0;
  G := Files.Old(Good); Check("Oberon10.Scn.Fnt found", G # NIL);
  IF G # NIL THEN
    len := Files.Length(G); IF len > LEN(good) THEN len := LEN(good) END;
    Files.Set(R, G, 0); Files.ReadBytes(R, good, len);
    F := Fonts.This(Good); Check("good font", (F # NIL) & (F.type = Fonts.font));
    nr := Int(RunsAt);
    Substituted("zq_Missing10.Scn.Fnt");
    Write("zq_Cut10.Scn.Fnt", -1, 0, 40); Substituted("zq_Cut10.Scn.Fnt");
    Write("zq_NegRuns10.Scn.Fnt", RunsAt, -5, -1); Substituted("zq_NegRuns10.Scn.Fnt");
    Write("zq_HugeRuns10.Scn.Fnt", RunsAt, 30000, -1); Substituted("zq_HugeRuns10.Scn.Fnt");
    Write("zq_DescRun10.Scn.Fnt", RunsAt + 2, Int(RunsAt + 4) + 1, -1); Substituted("zq_DescRun10.Scn.Fnt");
    Write("zq_BadBox10.Scn.Fnt", RunsAt + 2 + 4 * LONG(nr) + 6, -7, -1); Substituted("zq_BadBox10.Scn.Fnt");
    Write("zq_BigBox10.Scn.Fnt", RunsAt + 2 + 4 * LONG(nr) + 8, 300, -1); Substituted("zq_BigBox10.Scn.Fnt");
    Delete("zq_Cut10.Scn.Fnt"); Delete("zq_NegRuns10.Scn.Fnt"); Delete("zq_HugeRuns10.Scn.Fnt");
    Delete("zq_DescRun10.Scn.Fnt"); Delete("zq_BadBox10.Scn.Fnt"); Delete("zq_BigBox10.Scn.Fnt")
  END;
  out.String("FontTest: "); out.Int(checks, 0); out.String(" checks, "); out.Int(fails, 0); out.String(" failed"); out.Ln
END Run;

END FontTest.
