MODULE StringBase64Test;  (* StringBase64: the vectors of RFC 4648, the bytes 0FFX, and the line end
  that fixToIncludeEOL adds (the checks of voc's TestStringBase64) *)
IMPORT Base64 := StringBase64, Out;
VAR encoded, decoded: ARRAY 64 OF CHAR;
    source: ARRAY 8 OF CHAR;
    checks, fails: LONGINT;

PROCEDURE Check(ok: BOOLEAN);
BEGIN
  INC(checks);
  IF ~ok THEN INC(fails); Out.String("FAIL case "); Out.Int(checks, 0); Out.Ln END
END Check;

(* plain encoded is expected, and expected decoded is plain *)
PROCEDURE Pair(plain, expected: ARRAY OF CHAR);
BEGIN
  Base64.EncodeString(plain, encoded); Check(encoded = expected);
  Base64.DecodeString(encoded, decoded); Check(decoded = plain)
END Pair;

PROCEDURE Run*;
BEGIN
  checks := 0; fails := 0;
  Base64.fixToIncludeEOL := FALSE;
  Pair('', ''); Pair('f', 'Zg=='); Pair('fo', 'Zm8=');
  Pair('foo', 'Zm9v'); Pair('foob', 'Zm9vYg==');
  Pair('fooba', 'Zm9vYmE='); Pair('foobar', 'Zm9vYmFy');
  Pair('Aladdin:open sesame', 'QWxhZGRpbjpvcGVuIHNlc2FtZQ==');
  source[0] := 0FFX; source[1] := 0FFX; source[2] := 0FFX; source[3] := 0X;
  Pair(source, '////');
  Base64.fixToIncludeEOL := TRUE;
  source := 'f'; Base64.EncodeString(source, encoded);
  Check(encoded = 'Zgo='); Check(source = 'f');
  Out.String("StringBase64Test: "); Out.Int(checks, 0); Out.String(" checks, "); Out.Int(fails, 0); Out.String(" failed"); Out.Ln
END Run;

END StringBase64Test.
