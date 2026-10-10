MODULE agena;  (** a Gemini server (gemini://, port 1965) over the TLS 1.3 of src/lib/tls *)

(* agena.Serve dir cert.pem key.pem [port] [/host name] [/n count]
   serves the files below dir. A request is a URL and CR LF; the answer a status line ("20
   text/gemini", "51 not found", ...) and, for 20, the file. A directory gives its index.gmi, or
   a list of its files when it has none; a directory named without a slash at the end is
   redirected (31) to the name with it. Names starting with a dot, and .. in a path, are not
   served. /host refuses (53) requests for other hosts; /n ends after count connections (tests).
   One connection at a time, each with a timeout of 10 seconds; Ctrl+C stops the server.
   The certificate must have an ECDSA P-256 key (TLS13Server); agena.Help shows how to make one. *)

IMPORT SYSTEM, Linux0, Sockets, TLSBytes, TLS13Live, TLS13Server, Texts := texts, out, Oberon := Oberon0;

CONST
  DefaultPort = 1965;
  MaxRequest = 1024;      (* the URL, without CR LF (the Gemini specification) *)
  Timeout = 10000;        (* ms *)
  Chunk = 16384;
  NameLen = 256;
  PathLen = 1024;

TYPE
  State = POINTER TO TLS13Live.State;  (* 300 KB: on the heap *)
  Entry = POINTER TO EntryDesc;
  EntryDesc = RECORD name: ARRAY NameLen OF CHAR; dir: BOOLEAN; next: Entry END;

VAR
  listener: Sockets.Socket;
  s: State;               (* the connection being served *)
  root: ARRAY PathLen OF CHAR;
  host: ARRAY 256 OF CHAR;  (* the host to serve, "" for any *)

(* ----- strings ----- *)

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

PROCEDURE Lower(c: CHAR): CHAR;
BEGIN
  IF (c >= "A") & (c <= "Z") THEN RETURN CHR(ORD(c) + 32) END;
  RETURN c
END Lower;

(* a = b, ignoring the case of letters *)
PROCEDURE SameName(VAR a: ARRAY OF CHAR; b: ARRAY OF CHAR): BOOLEAN;
VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (a[i] # 0X) & (Lower(a[i]) = Lower(b[i])) DO INC(i) END;
  RETURN Lower(a[i]) = Lower(b[i])
END SameName;

(* does a end with b (b in lower case), ignoring case? *)
PROCEDURE EndsWith(VAR a: ARRAY OF CHAR; b: ARRAY OF CHAR): BOOLEAN;
VAR i, j: LONGINT;
BEGIN
  i := Len(a); j := Len(b);
  IF j > i THEN RETURN FALSE END;
  WHILE (j > 0) & (Lower(a[i - 1]) = b[j - 1]) DO DEC(i); DEC(j) END;
  RETURN j = 0
END EndsWith;

PROCEDURE Hex(c: CHAR): LONGINT;
BEGIN
  IF (c >= "0") & (c <= "9") THEN RETURN ORD(c) - ORD("0")
  ELSIF (c >= "a") & (c <= "f") THEN RETURN ORD(c) - ORD("a") + 10
  ELSIF (c >= "A") & (c <= "F") THEN RETURN ORD(c) - ORD("A") + 10
  END;
  RETURN -1
END Hex;

(* name, %-encoded for a link: letters, digits and - . _ ~ / stay *)
PROCEDURE Encode(VAR name, enc: ARRAY OF CHAR);
VAR i, j: LONGINT; c: CHAR; hex: ARRAY 17 OF CHAR;
BEGIN
  hex := "0123456789ABCDEF"; i := 0; j := 0;
  WHILE (name[i] # 0X) & (j < LEN(enc) - 4) DO
    c := name[i];
    IF (c >= "a") & (c <= "z") OR (c >= "A") & (c <= "Z") OR (c >= "0") & (c <= "9") OR
       (c = "-") OR (c = ".") OR (c = "_") OR (c = "~") OR (c = "/") THEN
      enc[j] := c; INC(j)
    ELSE
      enc[j] := "%"; enc[j + 1] := hex[ORD(c) DIV 16]; enc[j + 2] := hex[ORD(c) MOD 16]; INC(j, 3)
    END;
    INC(i)
  END;
  enc[j] := 0X
END Encode;

(* ----- answers ----- *)

PROCEDURE Send(str: ARRAY OF CHAR): BOOLEAN;
BEGIN RETURN TLS13Live.WriteAppString(s^, str)
END Send;

(* the status line: status meta CR LF *)
PROCEDURE Status(status: LONGINT; meta: ARRAY OF CHAR): BOOLEAN;
VAR line: ARRAY 1100 OF CHAR; n: LONGINT;
BEGIN
  line[0] := CHR(status DIV 10 + ORD("0")); line[1] := CHR(status MOD 10 + ORD("0")); line[2] := " "; line[3] := 0X;
  Append(line, meta); n := Len(line);
  line[n] := 0DX; line[n + 1] := 0AX; line[n + 2] := 0X;
  RETURN Send(line)
END Status;

PROCEDURE MimeType(VAR name, mime: ARRAY OF CHAR);
BEGIN
  IF EndsWith(name, ".gmi") OR EndsWith(name, ".gemini") THEN COPY("text/gemini; charset=utf-8", mime)
  ELSIF EndsWith(name, ".txt") OR EndsWith(name, ".mod") THEN COPY("text/plain; charset=utf-8", mime)
  ELSIF EndsWith(name, ".md") THEN COPY("text/markdown; charset=utf-8", mime)
  ELSIF EndsWith(name, ".html") OR EndsWith(name, ".htm") THEN COPY("text/html; charset=utf-8", mime)
  ELSIF EndsWith(name, ".xml") OR EndsWith(name, ".atom") THEN COPY("application/xml", mime)
  ELSIF EndsWith(name, ".png") THEN COPY("image/png", mime)
  ELSIF EndsWith(name, ".jpg") OR EndsWith(name, ".jpeg") THEN COPY("image/jpeg", mime)
  ELSIF EndsWith(name, ".gif") THEN COPY("image/gif", mime)
  ELSIF EndsWith(name, ".svg") THEN COPY("image/svg+xml", mime)
  ELSIF EndsWith(name, ".pdf") THEN COPY("application/pdf", mime)
  ELSIF EndsWith(name, ".gz") THEN COPY("application/gzip", mime)
  ELSIF EndsWith(name, ".zip") THEN COPY("application/zip", mime)
  ELSE COPY("application/octet-stream", mime)
  END
END MimeType;

(* the file open as fd, after "20 mime" *)
PROCEDURE SendFile(fd: LONGINT; VAR name: ARRAY OF CHAR): BOOLEAN;
VAR b: TLSBytes.Buffer; n: LONGINT; mime: ARRAY 64 OF CHAR; ok: BOOLEAN;
BEGIN
  MimeType(name, mime); ok := Status(20, mime);
  LOOP
    IF ~ok THEN EXIT END;
    n := Linux0.Read0(fd, SYSTEM.ADR(b.data[0]), Chunk);
    IF n <= 0 THEN EXIT END;
    b.len := n; ok := TLS13Live.WriteAppBuffer(s^, b)
  END;
  RETURN ok
END SendFile;

(* the entries of the directory open as fd, sorted, without names starting with a dot;
   FALSE if fd is not a directory *)
PROCEDURE ReadDir(fd: LONGINT; VAR list: Entry): BOOLEAN;
VAR n, i, k, rec: LONGINT; buf: ARRAY 4096 OF CHAR; e, p, q: Entry;
BEGIN
  list := NIL;
  n := Linux0.GetDents0(fd, SYSTEM.ADR(buf[0]), LEN(buf));  (* getdents64: length at 16, type at 18, name at 19 *)
  IF n < 0 THEN RETURN FALSE END;
  WHILE n > 0 DO
    i := 0;
    WHILE i < n DO
      rec := ORD(buf[i + 16]) + 256 * LONG(ORD(buf[i + 17]));
      IF buf[i + 19] # "." THEN
        NEW(e); k := 0; WHILE (buf[i + 19 + k] # 0X) & (k < NameLen - 1) DO e.name[k] := buf[i + 19 + k]; INC(k) END;
        e.name[k] := 0X; e.dir := buf[i + 18] = 4X;  (* DT_DIR *)
        IF (list = NIL) OR (e.name < list.name) THEN e.next := list; list := e
        ELSE p := list; q := list.next; WHILE (q # NIL) & (q.name < e.name) DO p := q; q := q.next END; e.next := q; p.next := e
        END
      END;
      INC(i, rec)
    END;
    n := Linux0.GetDents0(fd, SYSTEM.ADR(buf[0]), LEN(buf))
  END;
  RETURN TRUE
END ReadDir;

(* a list of the files in the directory path (the URL path, ending with /) *)
PROCEDURE SendList(VAR path: ARRAY OF CHAR; list: Entry): BOOLEAN;
VAR ok: BOOLEAN; nl: ARRAY 2 OF CHAR; enc: ARRAY 3 * NameLen OF CHAR;
BEGIN
  nl[0] := 0AX; nl[1] := 0X;
  ok := Status(20, "text/gemini; charset=utf-8") & Send("# ") & Send(path) & Send(nl) & Send(nl);
  IF path[1] # 0X THEN ok := ok & Send("=> ../ ..") & Send(nl) END;
  WHILE ok & (list # NIL) DO
    Encode(list.name, enc);
    ok := Send("=> ") & Send(enc);
    IF list.dir THEN ok := ok & Send("/") END;
    ok := ok & Send(" ") & Send(list.name);
    IF list.dir THEN ok := ok & Send("/") END;
    ok := ok & Send(nl);
    list := list.next
  END;
  RETURN ok
END SendList;

(* ----- requests ----- *)

(* url := the request, up to CR LF; FALSE if it is longer than MaxRequest or the connection ends *)
PROCEDURE ReadRequest(VAR url: ARRAY OF CHAR): BOOLEAN;
VAR buf: ARRAY MaxRequest + 3 OF CHAR; n, got, i: LONGINT;
BEGIN
  n := 0;
  LOOP
    IF ~TLS13Live.ReadAppMax(s^, buf, MaxRequest + 2 - n, got) THEN RETURN FALSE END;
    i := 0; WHILE i < got DO url[n + i] := buf[i]; INC(i) END;
    INC(n, got); url[n] := 0X;
    IF (n >= 2) & (url[n - 2] = 0DX) & (url[n - 1] = 0AX) THEN url[n - 2] := 0X; RETURN TRUE END;
    IF n >= MaxRequest + 2 THEN url[MaxRequest] := 0X; RETURN FALSE END
  END
END ReadRequest;

(* the host and the %-decoded path of a gemini:// url (without query and fragment);
   status: 0 if fine, else the status for the error *)
PROCEDURE Parse(VAR url, h, path: ARRAY OF CHAR; VAR status: LONGINT);
VAR i, j, a, b: LONGINT;
BEGIN
  status := 0; h[0] := 0X; path[0] := 0X;
  i := 0; WHILE (url[i] # 0X) & (url[i] # ":") & (url[i] # "/") DO INC(i) END;
  IF (url[i] # ":") OR (url[i + 1] # "/") OR (url[i + 2] # "/") THEN status := 59; RETURN END;
  url[i] := 0X;
  IF ~SameName(url, "gemini") THEN url[i] := ":"; status := 53; RETURN END;  (* a proxy request *)
  url[i] := ":"; INC(i, 3); j := 0;
  WHILE (url[i] # 0X) & (url[i] # "/") & (url[i] # ":") & (url[i] # "?") & (url[i] # "#") DO
    IF j < LEN(h) - 1 THEN h[j] := url[i]; INC(j) END; INC(i)
  END;
  h[j] := 0X;
  IF j = 0 THEN status := 59; RETURN END;
  IF url[i] = ":" THEN WHILE (url[i] # 0X) & (url[i] # "/") & (url[i] # "?") & (url[i] # "#") DO INC(i) END END;
  j := 0;
  IF url[i] # "/" THEN path[0] := "/"; j := 1 END;
  WHILE (url[i] # 0X) & (url[i] # "?") & (url[i] # "#") & (j < LEN(path) - 1) DO
    IF url[i] = "%" THEN
      a := Hex(url[i + 1]); IF a >= 0 THEN b := Hex(url[i + 2]) ELSE b := -1 END;
      IF (b < 0) OR (a * 16 + b = 0) THEN status := 59; RETURN END;
      path[j] := CHR(a * 16 + b); INC(i, 3)
    ELSE path[j] := url[i]; INC(i)
    END;
    INC(j)
  END;
  path[j] := 0X;
  (* no hidden names, no .. : a segment may not start with a dot *)
  i := 0;
  WHILE path[i] # 0X DO
    IF (path[i] = "/") & (path[i + 1] = ".") THEN status := 51; RETURN END;
    INC(i)
  END
END Parse;

(* answers the request url; status: the status sent *)
PROCEDURE Answer(VAR url: ARRAY OF CHAR; VAR status: LONGINT);
VAR h: ARRAY 256 OF CHAR; path, file, index, target: ARRAY PathLen + 32 OF CHAR;
  fd, fd2, r: LONGINT; list: Entry; ok: BOOLEAN;
BEGIN
  Parse(url, h, path, status);
  IF status = 0 THEN
    IF (host[0] # 0X) & ~SameName(h, host) THEN status := 53
    ELSE
      COPY(root, file); Append(file, path);
      fd := Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR(file[0]), Linux0.ORDonly, 0);
      IF fd < 0 THEN status := 51
      ELSIF ReadDir(fd, list) THEN
        IF path[Len(path) - 1] # "/" THEN
          status := 31; COPY(url, target);
          r := 0; WHILE (target[r] # 0X) & (target[r] # "?") & (target[r] # "#") DO INC(r) END;
          target[r] := 0X; Append(target, "/"); ok := Status(31, target)
        ELSE
          COPY(file, index); Append(index, "index.gmi");
          fd2 := Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR(index[0]), Linux0.ORDonly, 0);
          status := 20;
          IF fd2 >= 0 THEN ok := SendFile(fd2, index); r := Linux0.Close0(fd2)
          ELSE ok := SendList(path, list)
          END
        END;
        r := Linux0.Close0(fd)
      ELSE status := 20; ok := SendFile(fd, file); r := Linux0.Close0(fd)
      END
    END
  END;
  IF status = 59 THEN ok := Status(59, "bad request")
  ELSIF status = 53 THEN ok := Status(53, "proxy request refused")
  ELSIF status = 51 THEN ok := Status(51, "not found")
  END
END Answer;

(* ----- the server ----- *)

PROCEDURE Close;
BEGIN
  IF (s # NIL) & s.connected THEN TLS13Live.Disconnect(s^) END;
  IF listener # NIL THEN Sockets.Close(listener); listener := NIL END
END Close;

PROCEDURE Int(VAR a: ARRAY OF CHAR; VAR v: LONGINT): BOOLEAN;
VAR i: LONGINT;
BEGIN
  i := 0; v := 0;
  WHILE (a[i] >= "0") & (a[i] <= "9") & (v < 1000000) DO v := v * 10 + ORD(a[i]) - ORD("0"); INC(i) END;
  RETURN (i > 0) & (a[i] = 0X)
END Int;

PROCEDURE Usage;
BEGIN
  out.String("usage: agena.Serve dir cert.pem key.pem [port] [/host name] [/n count]"); out.Ln;
  out.String("  serves the files below dir over Gemini (port 1965); agena.Help tells more"); out.Ln
END Usage;

PROCEDURE Serve*;
VAR
  A: Texts.Reader; arg, cert, key: ARRAY PathLen OF CHAR; url: ARRAY MaxRequest + 3 OF CHAR;
  port, count, served, peerPort, status: LONGINT; id: TLS13Server.Identity;
  c: Sockets.Socket; peer: Sockets.Address; addr: ARRAY 64 OF CHAR;
BEGIN
  Texts.OpenArgs(A);
  IF ~Texts.Arg(A, root) OR ~Texts.Arg(A, cert) OR ~Texts.Arg(A, key) THEN Usage; RETURN END;
  port := DefaultPort; count := -1; host := "";
  WHILE Texts.Arg(A, arg) DO
    IF arg = "/host" THEN IF ~Texts.Arg(A, host) THEN Usage; RETURN END
    ELSIF arg = "/n" THEN IF ~Texts.Arg(A, arg) OR ~Int(arg, count) THEN Usage; RETURN END
    ELSIF ~Int(arg, port) OR (port < 1) OR (port > 65535) THEN Usage; RETURN
    END
  END;
  WHILE (Len(root) > 1) & (root[Len(root) - 1] = "/") DO root[Len(root) - 1] := 0X END;
  IF ~TLS13Server.Load(cert, key, id) THEN out.String("agena: "); out.String(TLS13Server.lastError); out.Ln; RETURN END;
  Close; Oberon.OnStop(Close);
  IF s = NIL THEN NEW(s); TLS13Live.Init(s^) END;
  listener := Sockets.Listen(Sockets.Inet6, port, 16);
  IF listener = NIL THEN out.String("agena: cannot listen on port "); out.Int(port, 0); out.Ln; RETURN END;
  out.String("agena: serving "); out.String(root); out.String(" on port "); out.Int(port, 0); out.Ln;
  served := 0;
  WHILE served # count DO
    c := Sockets.Accept(listener, peer, peerPort);
    IF c # NIL THEN
      INC(served); url[0] := 0X;
      Sockets.AddressToString(peer, addr);
      Sockets.SetTimeout(c, Timeout);
      IF ~TLS13Server.Accept(c.fd, id, s^) THEN
        out.String(addr); out.String(" handshake failed: "); out.String(TLS13Server.lastError)
      ELSE
        IF ~ReadRequest(url) THEN
          status := 59; IF Status(59, "bad request") THEN END
        ELSE Answer(url, status)
        END;
        TLS13Live.Disconnect(s^);
        out.String(addr); out.Char(" "); out.Int(status, 0); out.Char(" ");
        IF url[0] = 0X THEN out.Char("-") ELSE out.String(url) END
      END;
      out.Ln
    END
  END;
  Close
END Serve;

PROCEDURE Help*;
BEGIN
  out.String("agena, a Gemini server"); out.Ln; out.Ln;
  out.String("  agena.Serve dir cert.pem key.pem [port] [/host name] [/n count]"); out.Ln;
  out.String("    serves the files below dir to gemini:// clients, on port 1965 by default."); out.Ln;
  out.String("    A directory gives its index.gmi, or a list of its files; names starting with"); out.Ln;
  out.String("    a dot are not served. /host name answers only requests for that host;"); out.Ln;
  out.String("    /n count ends after count connections. Ctrl+C stops the server."); out.Ln;
  out.String("    Each request is logged: the client, the status and the URL."); out.Ln; out.Ln;
  out.String("  The certificate needs an ECDSA P-256 key. A self-signed one, as Gemini clients"); out.Ln;
  out.String("  accept it (trust on first use), is made with openssl:"); out.Ln; out.Ln;
  out.String("    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes"); out.Ln;
  out.String("      -keyout key.pem -out cert.pem -days 3650 -subj /CN=example.org"); out.Ln; out.Ln;
  out.String("  Example:"); out.Ln;
  out.String("    loksh agena.Serve /home/me/capsule cert.pem key.pem"); out.Ln;
  out.String("    loksh gemini.Show gemini://localhost/"); out.Ln
END Help;

BEGIN
  listener := NIL; s := NIL
END agena.
