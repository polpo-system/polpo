MODULE grep;

(** Line-oriented search for ASCII and Oberon text files. *)

IMPORT Files, FATFiles, Texts, Oberon := Oberon0, Out := out, regex;

CONST MaxLine = 8192;

TYPE
  ArgReader = RECORD
    R: Texts.Reader;
    ch: CHAR;
    eot: BOOLEAN
  END;

VAR
  pattern: regex.Pattern;
  ignoreCase, invert, namesOnly: BOOLEAN;
  currentDir, currentBase: ARRAY 256 OF CHAR;
  matchedFiles: LONGINT;

PROCEDURE OpenArgs(VAR A: ArgReader);
BEGIN
  Texts.OpenReader(A.R, Oberon.Par.text, Oberon.Par.pos);
  A.eot := A.R.eot;
  IF ~A.eot THEN Texts.Read(A.R, A.ch); A.eot := A.R.eot END
END OpenArgs;

PROCEDURE Advance(VAR A: ArgReader);
BEGIN
  IF ~A.eot THEN Texts.Read(A.R, A.ch); A.eot := A.R.eot END
END Advance;

PROCEDURE NextArg(VAR A: ArgReader; VAR arg: ARRAY OF CHAR): BOOLEAN;
VAR i: INTEGER; quote: CHAR;
BEGIN
  WHILE ~A.eot & (A.ch <= " ") DO Advance(A) END;
  IF A.eot THEN arg[0] := 0X; RETURN FALSE END;
  i := 0; quote := 0X;
  IF (A.ch = "'") OR (A.ch = '"') THEN quote := A.ch; Advance(A) END;
  WHILE ~A.eot & (((quote # 0X) & (A.ch # quote)) OR ((quote = 0X) & (A.ch > " "))) DO
    IF i < LEN(arg)-1 THEN arg[i] := A.ch; INC(i) END;
    Advance(A)
  END;
  IF (quote # 0X) & ~A.eot & (A.ch = quote) THEN Advance(A) END;
  arg[i] := 0X;
  RETURN TRUE
END NextArg;

PROCEDURE GlobMatchAt(VAR pat, name: ARRAY OF CHAR; pi, ni: INTEGER): BOOLEAN;
VAR i: INTEGER;
BEGIN
  LOOP
    IF pat[pi] = "*" THEN
      INC(pi);
      IF pat[pi] = 0X THEN RETURN TRUE END;
      i := ni;
      WHILE name[i] # 0X DO
        IF GlobMatchAt(pat, name, pi, i) THEN RETURN TRUE END;
        INC(i)
      END;
      RETURN GlobMatchAt(pat, name, pi, i)
    ELSIF pat[pi] = "?" THEN
      IF name[ni] = 0X THEN RETURN FALSE END;
      INC(pi); INC(ni)
    ELSIF pat[pi] = 0X THEN
      RETURN name[ni] = 0X
    ELSIF pat[pi] # name[ni] THEN
      RETURN FALSE
    ELSE
      INC(pi); INC(ni)
    END
  END
END GlobMatchAt;

PROCEDURE PrintMatch(name: ARRAY OF CHAR; lineNo: LONGINT; VAR line: ARRAY OF CHAR);
BEGIN
  Out.String(name); Out.Char(":"); Out.Int(lineNo, 1); Out.Char(":");
  Out.String(line); Out.Ln
END PrintMatch;

PROCEDURE MatchLine(name: ARRAY OF CHAR; lineNo: LONGINT; VAR line: ARRAY OF CHAR; VAR fileMatched: BOOLEAN);
VAR beg, end: INTEGER; found: BOOLEAN;
BEGIN
  regex.Search(pattern, line, beg, end); found := end >= 0;
  IF invert THEN found := ~found END;
  IF found THEN
    fileMatched := TRUE;
    IF ~namesOnly THEN PrintMatch(name, lineNo, line) END
  END
END MatchLine;

PROCEDURE SearchFile(name: ARRAY OF CHAR);
VAR f: Files.File; T: Texts.Text; R: Texts.Reader; line: ARRAY MaxLine OF CHAR;
  ch: CHAR; i: INTEGER; lineNo: LONGINT; fileMatched, overflow, overflowed: BOOLEAN;
BEGIN
  f := Files.Old(name);
  IF f = NIL THEN
    Out.String("grep: cannot open "); Out.String(name); Out.Ln; RETURN
  END;
  Files.ReleaseRead(f);
  NEW(T); Texts.Open(T, name); Texts.OpenReader(R, T, 0); Texts.Read(R, ch);
  i := 0; lineNo := 1; fileMatched := FALSE; overflow := FALSE; overflowed := FALSE;
  WHILE ~R.eot DO
    IF Texts.IsCharacterLibrary(R.lib) THEN
      IF ch = 0DX THEN
        line[i] := 0X; MatchLine(name, lineNo, line, fileMatched);
        overflowed := overflowed OR overflow;
        i := 0; overflow := FALSE; INC(lineNo)
      ELSIF (ch >= " ") OR (ch = 9X) THEN
        IF i < LEN(line)-1 THEN line[i] := ch; INC(i) ELSE overflow := TRUE END
      END
    END;
    Texts.Read(R, ch)
  END;
  IF (i > 0) OR overflow THEN line[i] := 0X; MatchLine(name, lineNo, line, fileMatched) END;
  IF overflowed OR overflow THEN Out.String("grep: line too long in "); Out.String(name); Out.Ln END;
  IF namesOnly & fileMatched THEN Out.String(name); Out.Ln END
END SearchFile;

PROCEDURE FileHandler(name: ARRAY OF CHAR; time, date, size: LONGINT;
                      attr: SET; VAR continue: BOOLEAN);
VAR full: ARRAY 512 OF CHAR; i, j: INTEGER;
BEGIN
  IF ~(FATFiles.SubDir IN attr) & GlobMatchAt(currentBase, name, 0, 0) THEN
    COPY(currentDir, full); i := 0; WHILE full[i] # 0X DO INC(i) END;
    j := 0; WHILE (name[j] # 0X) & (i < LEN(full)-1) DO full[i] := name[j]; INC(i); INC(j) END;
    full[i] := 0X; SearchFile(full); INC(matchedFiles)
  END
END FileHandler;

PROCEDURE SearchMask(mask: ARRAY OF CHAR);
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
  IF res # 0 THEN Out.String("grep: cannot enumerate "); Out.String(mask); Out.Ln END
END SearchMask;

PROCEDURE Run(literal: BOOLEAN);
VAR A: ArgReader; arg, expression: ARRAY 256 OF CHAR; error, pos, i: INTEGER;
  havePattern, haveMask, options: BOOLEAN;
BEGIN
  ignoreCase := FALSE; invert := FALSE; namesOnly := FALSE;
  havePattern := FALSE; haveMask := FALSE; options := TRUE;
  OpenArgs(A);
  WHILE ~havePattern & NextArg(A, arg) DO
    IF options & (arg[0] = "-") & (arg[1] = "-") & (arg[2] = 0X) THEN
      options := FALSE
    ELSIF options & (arg[0] = "-") & (arg[1] # 0X) THEN
      i := 1;
      WHILE arg[i] # 0X DO
        IF arg[i] = "i" THEN ignoreCase := TRUE
        ELSIF arg[i] = "v" THEN invert := TRUE
        ELSIF arg[i] = "l" THEN namesOnly := TRUE
        ELSE Out.String("grep: unknown option -"); Out.Char(arg[i]); Out.Ln; RETURN
        END;
        INC(i)
      END
    ELSE COPY(arg, expression); havePattern := TRUE
    END
  END;
  IF ~havePattern THEN Out.String("grep: pattern expected"); Out.Ln; RETURN END;
  IF literal THEN regex.CompileLiteral(expression, ignoreCase, pattern, error, pos)
  ELSE regex.Compile(expression, ignoreCase, pattern, error, pos)
  END;
  IF error # regex.noerror THEN
    Out.String("grep: invalid pattern at "); Out.Int(pos, 1); Out.Ln; RETURN
  END;
  matchedFiles := 0;
  WHILE NextArg(A, arg) DO haveMask := TRUE; SearchMask(arg) END;
  IF ~haveMask THEN Out.String("grep: file pattern expected"); Out.Ln
  ELSIF matchedFiles = 0 THEN Out.String("grep: no files matched"); Out.Ln
  END
END Run;

PROCEDURE Word*;
BEGIN Run(TRUE) END Word;

PROCEDURE Regex*;
BEGIN Run(FALSE) END Regex;

PROCEDURE Help*;
BEGIN
  Out.String("grep.Word [-ivl] pattern file..."); Out.Ln;
  Out.String("grep.Regex [-ivl] pattern file..."); Out.Ln;
  Out.String("options: -i ignore case, -v invert, -l list matching files"); Out.Ln;
  Out.String("regex: . ^ $ [] [^] ranges * + ? and backslash escapes"); Out.Ln
END Help;

END grep.
