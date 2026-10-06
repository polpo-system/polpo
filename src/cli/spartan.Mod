MODULE spartan;  (** Spartan downloads (spartan://, port 300): plain TCP, no TLS *)

(* spartan.Get url [file]   saves the body in file (default: the last part of the path, index.gmi)
   spartan.Show url         prints the body
   The request is "host path 0" (no data), the answer a line "<status> <meta>": 2 success (meta:
   the MIME type), 3 redirect (meta: a path on the same host, followed up to 5 times), 4 client
   error, 5 server error. The body ends with the connection. *)

IMPORT Texts := texts, Files, Internet, out;

CONST
  DefaultPort = "300";
  MaxRedirects = 5;

PROCEDURE Len(VAR a: ARRAY OF CHAR): LONGINT;
VAR i: LONGINT;
BEGIN i := 0; WHILE (i < LEN(a)) & (a[i] # 0X) DO INC(i) END; RETURN i
END Len;

PROCEDURE Append(VAR a: ARRAY OF CHAR; b: ARRAY OF CHAR);
VAR i, j: LONGINT;
BEGIN
  i := Len(a); j := 0;
  WHILE (j < LEN(b)) & (b[j] # 0X) & (i < LEN(a) - 1) DO a[i] := b[j]; INC(i); INC(j) END;
  a[i] := 0X
END Append;

PROCEDURE StartsWith(VAR a: ARRAY OF CHAR; b: ARRAY OF CHAR): BOOLEAN;
VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < LEN(b)) & (b[i] # 0X) DO
    IF (i >= LEN(a)) OR (CAP(a[i]) # CAP(b[i])) THEN RETURN FALSE END;
    INC(i)
  END;
  RETURN TRUE
END StartsWith;

(* host, port and path of a spartan:// url *)
PROCEDURE Split(VAR url, host, port, path: ARRAY OF CHAR): BOOLEAN;
VAR i, j: LONGINT;
BEGIN
  IF ~StartsWith(url, "spartan://") THEN out.String("spartan: spartan:// expected: "); out.String(url); out.Ln; RETURN FALSE END;
  i := 10; j := 0;
  IF url[i] = "[" THEN  (* [IPv6] *)
    INC(i);
    WHILE (url[i] # 0X) & (url[i] # "]") & (j < LEN(host) - 1) DO host[j] := url[i]; INC(i); INC(j) END;
    IF url[i] = "]" THEN INC(i) END
  ELSE
    WHILE (url[i] # 0X) & (url[i] # ":") & (url[i] # "/") & (j < LEN(host) - 1) DO host[j] := url[i]; INC(i); INC(j) END
  END;
  host[j] := 0X; j := 0;
  IF url[i] = ":" THEN
    INC(i); WHILE (url[i] >= "0") & (url[i] <= "9") & (j < LEN(port) - 1) DO port[j] := url[i]; INC(i); INC(j) END
  END;
  port[j] := 0X; IF j = 0 THEN COPY(DefaultPort, port) END;
  j := 0;
  WHILE (url[i] # 0X) & (j < LEN(path) - 1) DO path[j] := url[i]; INC(i); INC(j) END;
  path[j] := 0X;
  IF path[0] = 0X THEN COPY("/", path) END;
  RETURN host[0] # 0X
END Split;

(* the file name for path: its last part, index.gmi for a directory *)
PROCEDURE DefaultName(VAR path, name: ARRAY OF CHAR);
VAR i, j: LONGINT;
BEGIN
  i := Len(path); WHILE (i > 0) & (path[i - 1] # "/") DO DEC(i) END;
  j := 0; WHILE (path[i] # 0X) & (path[i] # "?") & (j < LEN(name) - 1) DO name[j] := path[i]; INC(i); INC(j) END;
  name[j] := 0X; IF j = 0 THEN COPY("index.gmi", name) END
END DefaultName;

(* one request for path; status and meta of the answer; the body to the file name, or to out
   if name = "" *)
PROCEDURE Request(VAR host, port, path: ARRAY OF CHAR; VAR status: LONGINT; VAR meta: ARRAY OF CHAR;
  VAR name: ARRAY OF CHAR; VAR n: LONGINT): BOOLEAN;
VAR conn: Internet.Socket; req, header: ARRAY 1100 OF CHAR; buf: ARRAY 4096 OF CHAR;
  got, i, j, hlen: LONGINT; inHeader: BOOLEAN; f: Files.File; R: Files.Rider;
BEGIN
  status := 0; meta[0] := 0X; n := 0; f := NIL;
  IF ~Internet.Connect(host, port, conn) THEN
    out.String("spartan: no connection to "); out.String(host); out.Char(":"); out.String(port); out.Ln; RETURN FALSE
  END;
  COPY(host, req); Append(req, " "); Append(req, path); Append(req, " 0");
  i := Len(req); req[i] := 0DX; req[i+1] := 0AX; req[i+2] := 0X;
  IF ~Internet.WriteBytes(conn, req, i + 2) THEN
    out.String("spartan: the request could not be sent"); out.Ln; Internet.Disconnect(conn); RETURN FALSE
  END;
  inHeader := TRUE; hlen := 0;
  LOOP
    got := 0;
    IF ~Internet.ReadBuf(conn, buf, got) OR (got <= 0) THEN EXIT END;
    i := 0;
    IF inHeader THEN  (* <status> <meta><CR><LF> *)
      WHILE (i < got) & inHeader DO
        IF buf[i] = 0AX THEN inHeader := FALSE
        ELSIF hlen < LEN(header) - 1 THEN header[hlen] := buf[i]; INC(hlen)
        END;
        INC(i)
      END;
      IF ~inHeader THEN
        IF (hlen > 0) & (header[hlen - 1] = 0DX) THEN DEC(hlen) END;
        header[hlen] := 0X;
        IF (hlen < 1) OR (header[0] < "2") OR (header[0] > "5") THEN
          out.String("spartan: a malformed answer: "); out.String(header); out.Ln; Internet.Disconnect(conn); RETURN FALSE
        END;
        status := ORD(header[0]) - ORD("0");
        j := 1; IF header[j] = " " THEN INC(j) END;
        hlen := 0; WHILE (header[j] # 0X) & (hlen < LEN(meta) - 1) DO meta[hlen] := header[j]; INC(hlen); INC(j) END;
        meta[hlen] := 0X;
        IF status # 2 THEN Internet.Disconnect(conn); RETURN TRUE END;
        IF name[0] # 0X THEN f := Files.New(name); Files.Set(R, f, 0) END
      END
    END;
    IF ~inHeader & (i < got) THEN  (* the body *)
      IF f # NIL THEN WHILE i < got DO Files.Write(R, buf[i]); INC(i); INC(n) END
      ELSE WHILE i < got DO IF buf[i] # 0DX THEN out.Char(buf[i]) END; INC(i); INC(n) END
      END
    END
  END;
  Internet.Disconnect(conn);
  IF inHeader THEN out.String("spartan: no answer"); out.Ln; RETURN FALSE END;
  IF f # NIL THEN Files.Register(f) END;
  RETURN TRUE
END Request;

(* fetch url, following redirects; to the file name (made from the url unless given), or to
   out if name = "" *)
PROCEDURE Fetch(VAR url: ARRAY OF CHAR; name: ARRAY OF CHAR; given: BOOLEAN);
VAR host, port, path, meta: ARRAY 1100 OF CHAR; status, n, redirects: LONGINT;
BEGIN
  IF ~Split(url, host, port, path) THEN RETURN END;
  redirects := 0;
  LOOP
    IF ~given & (name[0] # 0X) THEN DefaultName(path, name) END;
    IF ~Request(host, port, path, status, meta, name, n) THEN EXIT END;
    IF status = 3 THEN
      INC(redirects);
      IF redirects > MaxRedirects THEN out.String("spartan: too many redirects"); out.Ln; EXIT END;
      IF meta[0] # "/" THEN out.String("spartan: a redirect to "); out.String(meta); out.String(", not a path"); out.Ln; EXIT END;
      COPY(meta, path); out.String("spartan: redirected to "); out.String(path); out.Ln
    ELSE
      IF status = 2 THEN
        IF name[0] # 0X THEN
          out.String("2 "); out.String(meta); out.String(", "); out.Int(n, 0); out.String(" bytes in "); out.String(name); out.Ln
        END
      ELSE out.Int(status, 0); out.Char(" "); out.String(meta); out.Ln
      END;
      EXIT
    END
  END
END Fetch;

(** spartan.Get url [file] *)
PROCEDURE Get*;
VAR A: Texts.Reader; url, name: ARRAY 1100 OF CHAR; given: BOOLEAN;
BEGIN
  Texts.OpenArgs(A);
  IF ~Texts.Arg(A, url) THEN out.String("usage: spartan.Get spartan://host/path [file]"); out.Ln; RETURN END;
  given := Texts.Arg(A, name);
  IF ~given THEN name := "?" END;  (* a name is made from the url *)
  Fetch(url, name, given)
END Get;

(** spartan.Show url *)
PROCEDURE Show*;
VAR A: Texts.Reader; url: ARRAY 1100 OF CHAR;
BEGIN
  Texts.OpenArgs(A);
  IF ~Texts.Arg(A, url) THEN out.String("usage: spartan.Show spartan://host/path"); out.Ln; RETURN END;
  Fetch(url, "", TRUE)
END Show;

END spartan.
