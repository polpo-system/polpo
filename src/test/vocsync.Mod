MODULE vocsync;  (** modules shared with voc: copies with the imports of voc or of polpo *)

(* vocsync.To polpo-file voc-file
     copies a module shared with voc to its voc repository; the file is the same on both systems.
     The shared modules (github.com/norayr: Internet on master, the others on main):
       src/lib/sockets/Sockets.Mod, src/lib/dns/DNS.Mod, src/lib/internet/Internet.Mod,
       src/lib/native/NetSystem.Mod -> Internet (src, src/native)
       src/lib/strutils/strUtils.Mod, strTypes.Mod -> strutils
       src/lib/base64/StringBase64.Mod -> base64
       src/lib/http/http.Mod, hexIntStr.Mod -> http
       src/lib/tls/*.Mod, src/lib/tls/test/TLSTest*.Mod -> tls
     The network modules import unixNet on both systems (polpo's module unixNet passes the calls to
     Linux0).
   vocsync.From voc-file ... polpo-dir
     copies modules of a voc repository into polpo-dir. A module of voc that imports Strings means
     the Oakwood module of voc, which is oocStrings in polpo (polpo's Strings is the one of ETH
     Oberon): the copy imports Strings := oocStrings. Everything else is the same file. *)

IMPORT Files, Texts, Out;

TYPE Buf = POINTER TO ARRAY OF CHAR;

PROCEDURE Len(VAR s: ARRAY OF CHAR): LONGINT;
VAR i: LONGINT;
BEGIN i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END; RETURN i
END Len;

PROCEDURE Read(VAR name: ARRAY OF CHAR; VAR buf: Buf): BOOLEAN;
VAR f: Files.File; R: Files.Rider; n, i: LONGINT;
BEGIN
  f := Files.Old(name);
  IF f = NIL THEN Out.String("vocsync: no "); Out.String(name); Out.Ln; RETURN FALSE END;
  n := Files.Length(f); NEW(buf, n + 1); Files.Set(R, f, 0);
  i := 0; WHILE i < n DO Files.Read(R, buf[i]); INC(i) END; buf[n] := 0X;
  RETURN TRUE
END Read;

PROCEDURE Write(VAR name: ARRAY OF CHAR; VAR buf: ARRAY OF CHAR);
VAR f: Files.File; R: Files.Rider; i: LONGINT;
BEGIN
  f := Files.New(name); Files.Set(R, f, 0);
  i := 0; WHILE buf[i] # 0X DO Files.Write(R, buf[i]); INC(i) END;
  Files.Register(f)
END Write;

(* the position of pat in s from pos, -1 if it is not there *)
PROCEDURE Pos(VAR s: ARRAY OF CHAR; VAR pat: ARRAY OF CHAR; pos: LONGINT): LONGINT;
VAR k: LONGINT;
BEGIN
  WHILE s[pos] # 0X DO
    k := 0; WHILE (pat[k] # 0X) & (s[pos+k] = pat[k]) DO INC(k) END;
    IF pat[k] = 0X THEN RETURN pos END;
    INC(pos)
  END;
  RETURN -1
END Pos;

(* buf with the text from beg to end (excluded) replaced by new *)
PROCEDURE Replace(VAR buf: Buf; beg, end: LONGINT; VAR new: ARRAY OF CHAR);
VAR b: Buf; n, i, j, k: LONGINT;
BEGIN
  n := Len(buf^) - (end - beg) + Len(new); NEW(b, n + 1);
  i := 0; WHILE i < beg DO b[i] := buf[i]; INC(i) END;
  k := 0; WHILE new[k] # 0X DO b[i] := new[k]; INC(i); INC(k) END;
  j := end; WHILE buf[j] # 0X DO b[i] := buf[j]; INC(i); INC(j) END;
  b[i] := 0X; buf := b
END Replace;

PROCEDURE Base(VAR path, name: ARRAY OF CHAR);  (* the file name of a path *)
VAR i, k, j: LONGINT;
BEGIN
  k := 0; i := 0; WHILE path[i] # 0X DO IF path[i] = "/" THEN k := i + 1 END; INC(i) END;
  j := 0; WHILE path[k] # 0X DO name[j] := path[k]; INC(k); INC(j) END; name[j] := 0X
END Base;

(* the IMPORT clause of buf with Strings := oocStrings for a plain Strings *)
PROCEDURE Convert(VAR buf: Buf): BOOLEAN;
VAR imp: ARRAY 8 OF CHAR; beg, end, i, j, k: LONGINT; clause, item, res: ARRAY 2048 OF CHAR; changed: BOOLEAN;

  PROCEDURE One;  (* item, with its blanks, to res *)
  VAR t: ARRAY 64 OF CHAR; a, b, m: LONGINT; alias: ARRAY 16 OF CHAR;
  BEGIN
    a := 0; WHILE (item[a] # 0X) & (item[a] <= " ") DO INC(a) END;
    b := Len(item); WHILE (b > a) & (item[b-1] <= " ") DO DEC(b) END;
    m := 0; WHILE (a + m < b) & (m < LEN(t) - 1) DO t[m] := item[a+m]; INC(m) END; t[m] := 0X;
    alias := "";
    IF t = "Strings" THEN alias := "oocStrings" END;
    IF alias # "" THEN  (* the blanks before, "Name := alias", the blanks after *)
      m := 0; WHILE m < a DO res[k] := item[m]; INC(k); INC(m) END;
      m := 0; WHILE t[m] # 0X DO res[k] := t[m]; INC(k); INC(m) END;
      res[k] := " "; res[k+1] := ":"; res[k+2] := "="; res[k+3] := " "; INC(k, 4);
      m := 0; WHILE alias[m] # 0X DO res[k] := alias[m]; INC(k); INC(m) END;
      m := b; WHILE item[m] # 0X DO res[k] := item[m]; INC(k); INC(m) END;
      changed := TRUE
    ELSE m := 0; WHILE item[m] # 0X DO res[k] := item[m]; INC(k); INC(m) END
    END
  END One;

BEGIN
  imp := "IMPORT"; beg := Pos(buf^, imp, 0);
  WHILE (beg > 0) & ((buf[beg-1] > " ") OR (buf[beg+6] > " ")) DO beg := Pos(buf^, imp, beg + 1) END;  (* the word *)
  IF beg < 0 THEN RETURN FALSE END;
  INC(beg, 6); end := beg; WHILE (buf[end] # 0X) & (buf[end] # ";") DO INC(end) END;
  i := beg; j := 0; WHILE (i < end) & (j < LEN(clause) - 1) DO clause[j] := buf[i]; INC(i); INC(j) END; clause[j] := 0X;
  changed := FALSE; k := 0; i := 0;
  WHILE clause[i] # 0X DO  (* the items between commas *)
    j := 0; WHILE (clause[i] # 0X) & (clause[i] # ",") DO item[j] := clause[i]; INC(i); INC(j) END; item[j] := 0X;
    One;
    IF clause[i] = "," THEN res[k] := ","; INC(k); INC(i) END
  END;
  res[k] := 0X;
  IF changed THEN Replace(buf, beg, end, res) END;
  RETURN changed
END Convert;

PROCEDURE To*;
VAR A: Texts.Reader; src, dst, name: ARRAY 256 OF CHAR; buf: Buf;
BEGIN
  Texts.OpenArgs(A);
  IF ~Texts.Arg(A, src) OR ~Texts.Arg(A, dst) THEN Out.String("usage: vocsync.To polpo-file voc-file"); Out.Ln; RETURN END;
  IF ~Read(src, buf) THEN RETURN END;
  Write(dst, buf^); Base(src, name);
  Out.String(name); Out.String(" copied"); Out.Ln
END To;

PROCEDURE From*;
VAR A: Texts.Reader; args: ARRAY 64 OF ARRAY 256 OF CHAR; n, i: INTEGER; dst, name: ARRAY 256 OF CHAR; buf: Buf; k, m: LONGINT;
BEGIN
  Texts.OpenArgs(A); n := 0;
  WHILE (n < LEN(args)) & Texts.Arg(A, args[n]) DO INC(n) END;
  IF n < 2 THEN Out.String("usage: vocsync.From voc-file ... polpo-dir"); Out.Ln; RETURN END;
  DEC(n); i := 0;  (* args[n]: the directory *)
  WHILE i < n DO
    IF Read(args[i], buf) THEN
      Base(args[i], name); Out.String(name);
      IF Convert(buf) THEN Out.String(" imports changed") ELSE Out.String(" same") END; Out.Ln;
      COPY(args[n], dst); k := Len(dst); IF (k > 0) & (dst[k-1] # "/") THEN dst[k] := "/"; INC(k) END;
      m := 0; WHILE name[m] # 0X DO dst[k] := name[m]; INC(k); INC(m) END; dst[k] := 0X;
      Write(dst, buf^)
    END;
    INC(i)
  END
END From;

END vocsync.
