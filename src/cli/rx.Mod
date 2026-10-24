MODULE rx;

(** Console commands for the System 3 RXA regular-expression engine. *)

IMPORT Files, FATFiles, Texts, Oberon := Oberon0, Out := out, RXA;

CONST MaxLine = 10001;

VAR
  dfa: RXA.DFA;
  replacement: ARRAY MaxLine OF CHAR;
  line: ARRAY MaxLine OF CHAR;
  casesens, replacementSet, lineSet, matchSet: BOOLEAN;
  matchBeg, matchEnd: INTEGER;
  grepInvert: BOOLEAN;
  currentDir, currentBase: ARRAY 256 OF CHAR;
  matchedFiles: LONGINT;

PROCEDURE Upper(ch: CHAR): CHAR;
BEGIN
  IF ("a" <= ch) & (ch <= "z") THEN RETURN CAP(ch) ELSE RETURN ch END
END Upper;

PROCEDURE Params(VAR s: ARRAY OF CHAR);
VAR R: Texts.Reader; ch: CHAR; i: INTEGER;
BEGIN
  Texts.OpenReader(R, Oberon.Par.text, Oberon.Par.pos); i := 0;
  Texts.Read(R, ch);
  WHILE ~R.eot DO
    IF i < LEN(s)-1 THEN s[i] := ch; INC(i) END;
    Texts.Read(R, ch)
  END;
  s[i] := 0X
END Params;

PROCEDURE SkipSpaces(VAR s: ARRAY OF CHAR; VAR pos: INTEGER);
BEGIN WHILE (s[pos] # 0X) & (s[pos] <= " ") DO INC(pos) END
END SkipSpaces;

PROCEDURE Token(VAR s: ARRAY OF CHAR; VAR pos: INTEGER; VAR token: ARRAY OF CHAR): BOOLEAN;
VAR i: INTEGER; quote: CHAR;
BEGIN
  SkipSpaces(s, pos);
  IF s[pos] = 0X THEN token[0] := 0X; RETURN FALSE END;
  i := 0; quote := 0X;
  IF (s[pos] = "'") OR (s[pos] = '"') THEN quote := s[pos]; INC(pos) END;
  WHILE (s[pos] # 0X) & (((quote # 0X) & (s[pos] # quote)) OR
        ((quote = 0X) & (s[pos] > " "))) DO
    IF i < LEN(token)-1 THEN token[i] := s[pos]; INC(i) END;
    INC(pos)
  END;
  IF (quote # 0X) & (s[pos] = quote) THEN INC(pos) END;
  token[i] := 0X; RETURN TRUE
END Token;

PROCEDURE Options(VAR s: ARRAY OF CHAR; VAR pos: INTEGER; allowInvert: BOOLEAN): BOOLEAN;
VAR save, i: INTEGER; opt: ARRAY 32 OF CHAR;
BEGIN
  LOOP
    save := pos;
    IF ~Token(s, pos, opt) THEN RETURN TRUE END;
    IF ((opt[0] = "-") OR (opt[0] = 5CX)) & (opt[1] # 0X) THEN
      i := 1;
      WHILE opt[i] # 0X DO
        IF opt[i] = "c" THEN casesens := FALSE
        ELSIF allowInvert & (opt[i] = "i") THEN grepInvert := TRUE
        ELSE
          Out.String("rx: unknown option "); Out.Char(opt[0]); Out.Char(opt[i]); Out.Ln;
          RETURN FALSE
        END;
        INC(i)
      END
    ELSE pos := save; RETURN TRUE
    END
  END
END Options;

PROCEDURE Expression(VAR raw: ARRAY OF CHAR; pos: INTEGER; VAR expr: ARRAY OF CHAR);
VAR i: INTEGER; quoted, first: BOOLEAN; ch: CHAR;
BEGIN
  SkipSpaces(raw, pos); i := 0; quoted := FALSE; first := FALSE;
  WHILE (raw[pos] # 0X) & (i < LEN(expr)-1) DO
    ch := raw[pos];
    IF ~first & (ch = '"') THEN quoted := ~quoted; first := quoted; expr[i] := ch
    ELSE
      IF quoted & ~casesens THEN expr[i] := Upper(ch) ELSE expr[i] := ch END;
      first := FALSE
    END;
    INC(i); INC(pos)
  END;
  expr[i] := 0X
END Expression;

PROCEDURE PatternError(error, pos: INTEGER);
BEGIN
  Out.String("rx: pattern error "); Out.Int(error, 1);
  Out.String(" at "); Out.Int(pos, 1); Out.Ln
END PatternError;

PROCEDURE Compile(VAR raw: ARRAY OF CHAR; pos: INTEGER): BOOLEAN;
VAR expr: ARRAY MaxLine OF CHAR; error, errorPos: INTEGER;
BEGIN
  Expression(raw, pos, expr);
  IF expr[0] = 0X THEN Out.String("rx: expression expected"); Out.Ln; RETURN FALSE END;
  RXA.New(expr, dfa, error, errorPos);
  IF error # RXA.noerror THEN PatternError(error, errorPos); RETURN FALSE END;
  RETURN TRUE
END Compile;

PROCEDURE SetSearch*;
(** Compile and store an RXA search expression. Option -c ignores letter case. *)
VAR raw: ARRAY MaxLine OF CHAR; pos: INTEGER;
BEGIN
  Params(raw); pos := 0; casesens := TRUE; grepInvert := FALSE;
  IF Options(raw, pos, FALSE) & Compile(raw, pos) THEN matchSet := FALSE END
END SetSearch;

PROCEDURE SetReplace*;
(** Store an RXA replacement expression. X0 through X9 insert captured subexpressions. *)
VAR raw: ARRAY MaxLine OF CHAR; pos, i: INTEGER;
BEGIN
  Params(raw); pos := 0; SkipSpaces(raw, pos); i := 0;
  WHILE (raw[pos] # 0X) & (i < LEN(replacement)-1) DO
    replacement[i] := raw[pos]; INC(i); INC(pos)
  END;
  replacement[i] := 0X; replacementSet := replacement[0] # 0X;
  IF ~replacementSet THEN Out.String("rx: replacement expected"); Out.Ln END
END SetReplace;

PROCEDURE TextArgument(VAR raw, text: ARRAY OF CHAR): BOOLEAN;
VAR pos, i, end: INTEGER; quote: CHAR;
BEGIN
  pos := 0; SkipSpaces(raw, pos);
  IF raw[pos] = 0X THEN RETURN FALSE END;
  quote := 0X;
  IF (raw[pos] = "'") OR (raw[pos] = '"') THEN quote := raw[pos]; INC(pos) END;
  end := pos; WHILE raw[end] # 0X DO INC(end) END;
  WHILE (end > pos) & (raw[end-1] <= " ") DO DEC(end) END;
  IF (quote # 0X) & (end > pos) & (raw[end-1] = quote) THEN DEC(end) END;
  i := 0;
  WHILE (pos < end) & (i < LEN(text)-1) DO text[i] := raw[pos]; INC(i); INC(pos) END;
  text[i] := 0X; RETURN TRUE
END TextArgument;

PROCEDURE Fold(VAR source, folded: ARRAY OF CHAR);
VAR i: INTEGER;
BEGIN
  COPY(source, folded);
  IF ~casesens THEN
    i := 0; WHILE folded[i] # 0X DO folded[i] := Upper(folded[i]); INC(i) END
  END
END Fold;

PROCEDURE Find(start: INTEGER): BOOLEAN;
VAR folded: ARRAY MaxLine OF CHAR;
BEGIN
  matchSet := FALSE;
  IF dfa = NIL THEN Out.String("rx: search expression is not set"); Out.Ln; RETURN FALSE END;
  IF ~lineSet THEN Out.String("rx: text argument expected"); Out.Ln; RETURN FALSE END;
  Fold(line, folded); matchBeg := start; RXA.Search(dfa, folded, matchBeg, matchEnd);
  matchSet := matchEnd >= 0; RETURN matchSet
END Find;

PROCEDURE PrintMatch;
VAR i: INTEGER;
BEGIN
  Out.Int(matchBeg, 1); Out.Char(":"); Out.Int(matchEnd, 1); Out.Char(":");
  i := matchBeg; WHILE i < matchEnd DO Out.Char(line[i]); INC(i) END; Out.Ln
END PrintMatch;

PROCEDURE Search*;
(** Search optional text and print beg:end:match. Without text, continue after the current match. *)
VAR raw: ARRAY MaxLine OF CHAR; start: INTEGER;
BEGIN
  Params(raw);
  IF TextArgument(raw, line) THEN lineSet := TRUE; start := 0
  ELSIF matchSet THEN start := matchEnd
  ELSE start := 0
  END;
  IF Find(start) THEN PrintMatch END
END Search;

PROCEDURE ReplaceCurrent(VAR next: INTEGER): BOOLEAN;
VAR error, pos: INTEGER;
BEGIN
  IF ~replacementSet THEN Out.String("rx: replacement is not set"); Out.Ln; RETURN FALSE END;
  RXA.Replace(dfa, line, replacement, matchBeg, matchEnd, error, pos);
  IF error # RXA.noerror THEN
    Out.String("rx: replacement error "); Out.Int(error, 1);
    Out.String(" at "); Out.Int(pos, 1); Out.Ln; RETURN FALSE
  END;
  next := pos; matchSet := FALSE; RETURN TRUE
END ReplaceCurrent;

PROCEDURE Replace*;
(** Replace the current or first match in optional text, print the result, and find the next match. *)
VAR raw: ARRAY MaxLine OF CHAR; next: INTEGER;
BEGIN
  Params(raw);
  IF TextArgument(raw, line) THEN lineSet := TRUE; matchSet := FALSE END;
  IF ~matchSet THEN matchSet := Find(0) END;
  IF matchSet & ReplaceCurrent(next) THEN
    Out.String(line); Out.Ln; matchSet := Find(next)
  END
END Replace;

PROCEDURE ReplaceAll*;
(** Replace every match in optional text and print the resulting text. *)
VAR raw: ARRAY MaxLine OF CHAR; next, previous: INTEGER;
BEGIN
  Params(raw);
  IF TextArgument(raw, line) THEN lineSet := TRUE END;
  IF ~lineSet THEN Out.String("rx: text argument expected"); Out.Ln; RETURN END;
  previous := -1;
  WHILE Find(previous + 1) DO
    IF ~ReplaceCurrent(next) THEN RETURN END;
    IF next > previous THEN previous := next - 1 ELSE INC(previous) END
  END;
  Out.String(line); Out.Ln
END ReplaceAll;

PROCEDURE GlobMatchAt(VAR pat, name: ARRAY OF CHAR; pi, ni: INTEGER): BOOLEAN;
VAR i: INTEGER;
BEGIN
  LOOP
    IF pat[pi] = "*" THEN
      INC(pi); IF pat[pi] = 0X THEN RETURN TRUE END;
      i := ni;
      WHILE name[i] # 0X DO
        IF GlobMatchAt(pat, name, pi, i) THEN RETURN TRUE END;
        INC(i)
      END;
      RETURN GlobMatchAt(pat, name, pi, i)
    ELSIF pat[pi] = "?" THEN
      IF name[ni] = 0X THEN RETURN FALSE END;
      INC(pi); INC(ni)
    ELSIF pat[pi] = 0X THEN RETURN name[ni] = 0X
    ELSIF pat[pi] # name[ni] THEN RETURN FALSE
    ELSE INC(pi); INC(ni)
    END
  END
END GlobMatchAt;

PROCEDURE PrintLine(name: ARRAY OF CHAR; lineNo: LONGINT; VAR text: ARRAY OF CHAR; len: INTEGER);
VAR i: INTEGER;
BEGIN
  Out.String(name); Out.Char(":"); Out.Int(lineNo, 1); Out.Char(":");
  i := 0; WHILE i < len DO Out.Char(text[i]); INC(i) END; Out.Ln
END PrintLine;

PROCEDURE GrepLine(name: ARRAY OF CHAR; lineNo: LONGINT; VAR text: ARRAY OF CHAR; len: INTEGER);
VAR folded: ARRAY MaxLine OF CHAR; beg, end: INTEGER; found: BOOLEAN;
BEGIN
  Fold(text, folded); beg := 0; RXA.Search(dfa, folded, beg, end); found := end >= 0;
  IF grepInvert THEN found := ~found END;
  IF found THEN PrintLine(name, lineNo, text, len) END
END GrepLine;

PROCEDURE GrepFile(name: ARRAY OF CHAR);
VAR f: Files.File; T: Texts.Text; R: Texts.Reader; text: ARRAY MaxLine OF CHAR;
  ch: CHAR; i: INTEGER; lineNo: LONGINT; overflow, overflowed: BOOLEAN;
BEGIN
  f := Files.Old(name);
  IF f = NIL THEN Out.String("rx: cannot open "); Out.String(name); Out.Ln; RETURN END;
  Files.ReleaseRead(f);
  NEW(T); Texts.Open(T, name); Texts.OpenReader(R, T, 0); Texts.Read(R, ch);
  i := 0; lineNo := 1; overflow := FALSE; overflowed := FALSE;
  WHILE ~R.eot DO
    IF Texts.IsCharacterLibrary(R.lib) THEN
      IF ch = 0DX THEN
        IF i < LEN(text)-1 THEN text[i] := ch; text[i+1] := 0X ELSE text[i] := 0X END;
        GrepLine(name, lineNo, text, i);
        overflowed := overflowed OR overflow; overflow := FALSE; i := 0; INC(lineNo)
      ELSIF (ch >= " ") OR (ch = 9X) THEN
        IF i < LEN(text)-2 THEN text[i] := ch; INC(i) ELSE overflow := TRUE END
      END
    END;
    Texts.Read(R, ch)
  END;
  IF (i > 0) OR overflow THEN text[i] := 0X; GrepLine(name, lineNo, text, i) END;
  IF overflowed OR overflow THEN Out.String("rx: line too long in "); Out.String(name); Out.Ln END
END GrepFile;

PROCEDURE FileHandler(name: ARRAY OF CHAR; time, date, size: LONGINT;
                      attr: SET; VAR continue: BOOLEAN);
VAR full: ARRAY 512 OF CHAR; i, j: INTEGER;
BEGIN
  IF ~(FATFiles.SubDir IN attr) & GlobMatchAt(currentBase, name, 0, 0) THEN
    COPY(currentDir, full); i := 0; WHILE full[i] # 0X DO INC(i) END;
    j := 0; WHILE (name[j] # 0X) & (i < LEN(full)-1) DO full[i] := name[j]; INC(i); INC(j) END;
    full[i] := 0X; GrepFile(full); INC(matchedFiles)
  END
END FileHandler;

PROCEDURE GrepMask(mask: ARRAY OF CHAR);
VAR i, slash: INTEGER; res: LONGINT;
BEGIN
  i := 0; slash := -1;
  WHILE mask[i] # 0X DO IF mask[i] = "/" THEN slash := i END; INC(i) END;
  IF slash < 0 THEN currentDir := ""; COPY(mask, currentBase)
  ELSE
    i := 0; WHILE i <= slash DO currentDir[i] := mask[i]; INC(i) END; currentDir[i] := 0X;
    INC(slash); i := 0;
    WHILE mask[slash] # 0X DO currentBase[i] := mask[slash]; INC(i); INC(slash) END;
    currentBase[i] := 0X
  END;
  FATFiles.Enumerate(mask, FileHandler, res);
  IF res # 0 THEN Out.String("rx: cannot enumerate "); Out.String(mask); Out.Ln END
END GrepMask;

PROCEDURE Grep*;
(** Search matching files line by line. Options -c and -i ignore case and invert matches. *)
VAR raw: ARRAY MaxLine OF CHAR; mask: ARRAY 256 OF CHAR; pos: INTEGER;
BEGIN
  Params(raw); pos := 0;
  IF ~Token(raw, pos, mask) THEN Out.String("rx: file pattern expected"); Out.Ln; RETURN END;
  casesens := TRUE; grepInvert := FALSE;
  IF Options(raw, pos, TRUE) & Compile(raw, pos) THEN
    matchedFiles := 0; GrepMask(mask);
    IF matchedFiles = 0 THEN Out.String("rx: no files matched"); Out.Ln END
  END
END Grep;

PROCEDURE Help*;
(** Print command usage. *)
BEGIN
  Out.String("rx.SetSearch [-c] expression"); Out.Ln;
  Out.String("rx.SetReplace replacement"); Out.Ln;
  Out.String("rx.Search [text]"); Out.Ln;
  Out.String("rx.Replace [text]"); Out.Ln;
  Out.String("rx.ReplaceAll [text]"); Out.Ln;
  Out.String("rx.Grep file [-ci] expression"); Out.Ln
END Help;

BEGIN
  dfa := NIL; casesens := TRUE; replacementSet := FALSE;
  lineSet := FALSE; matchSet := FALSE
END rx.
