MODULE StrUtilsTest;  (* strUtils at the bounds: empty strings, arrays without 0X, ranges outside the array
  (the checks of voc's TestStrBounds) *)
IMPORT strUtils, Out;
VAR source: ARRAY 16 OF CHAR;
    dest: ARRAY 3 OF CHAR;
    raw: ARRAY 3 OF CHAR;
    empty: ARRAY 1 OF CHAR;
    words: strUtils.pstrings;
    word: strUtils.pstring;
    found: BOOLEAN;
    pos: INTEGER;
    checks, fails: LONGINT;

PROCEDURE Check(ok: BOOLEAN);
BEGIN
  INC(checks);
  IF ~ok THEN INC(fails); Out.String("FAIL case "); Out.Int(checks, 0); Out.Ln END
END Check;

PROCEDURE Run*;
BEGIN
  checks := 0; fails := 0;
  empty := '';
  strUtils.zeroStr(empty); strUtils.copyAll('', empty);
  strUtils.Assign('abc', empty); strUtils.findChar('a', empty, found, pos);
  Check(~found); Check(pos = -1);
  Check(strUtils.Compare(empty, '') = strUtils.equal);
  raw[0] := 'a'; raw[1] := 'b'; raw[2] := 'c';
  Check(strUtils.Compare(raw, 'abc') = strUtils.equal);
  strUtils.Assign(raw, dest); Check(dest = 'ab');
  Check(strUtils.WordCount('', ' ') = 0);
  Check(strUtils.WordCount('   ', ' ') = 0);
  Check(strUtils.WordCount(' a  bc  d ', ' ') = 3);
  Check(strUtils.Lpos('', 'a') = 0); Check(strUtils.Rpos('', 'a') = 0);
  Check(strUtils.Pos('a', 'abc', -1) = 0);
  word := strUtils.ExtractWord(1, 'single', ' '); Check(word^ = 'single');
  word := strUtils.ExtractWord(2, ' a  bc  d ', ' '); Check(word^ = 'bc');
  word := strUtils.ExtractWord(4, ' a  bc  d ', ' '); Check(word^ = '');
  words := strUtils.tokenize('', ' '); Check(words = NIL);
  words := strUtils.tokenize(' a  bc  d ', ' ');
  Check(LEN(words^) = 3); Check(words[0]^ = 'a'); Check(words[2]^ = 'd');
  source := 'abc'; Check(~strUtils.contains(source, 'abcdef'));
  Check(strUtils.contains(source, '')); Check(strUtils.contains(source, 'bc'));
  Check(strUtils.contains(raw, 'abc')); Check(~strUtils.contains(raw, 'abcd'));
  dest := 'xx'; strUtils.copyBytes(raw, dest, 2, 1); Check(dest[2] = 'a');
  strUtils.copyBytes(raw, dest, -1, 1); Check(dest[0] = 'x');
  strUtils.copyBytes(raw, dest, 0, 0); Check(dest[0] = 'x');
  strUtils.getNextWord(source, 0, dest); Check(dest = 'ab');
  strUtils.getNextWord(source, 3, dest); Check(dest = '');
  strUtils.getNextAlphaNumWord(source, -1, dest); Check(dest = '');
  strUtils.getTillEOL(source, -1, dest); Check(dest = 'ab');
  strUtils.getTillEOL(source, 3, dest); Check(dest = '');
  dest := 'ab'; strUtils.appendLFCR(dest); Check(dest = 'ab');
  Out.String("StrUtilsTest: "); Out.Int(checks, 0); Out.String(" checks, "); Out.Int(fails, 0); Out.String(" failed"); Out.Ln
END Run;

END StrUtilsTest.
