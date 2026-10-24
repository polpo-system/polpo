MODULE fetch;  (** HTTP downloads with the http module *)

(* fetch.Get url [file]   saves the body in file (default: the last part of the path)
   fetch.Show url         prints the body
   fetch.Verbose                   the TLS handshake in detail from now on (fetch.Quiet: not)
   url: http[s]://host[:port][/path]; host is a name, an IPv4 address or [an IPv6 address].
   https is TLS 1.3 in Oberon (TLS_AES_128_GCM_SHA256, X25519): the certificate chain up to a
   root of the CA bundle (SSL_CERT_FILE, else /etc/ssl/certs/ca-certificates.crt), the host
   name, CertificateVerify and Finished are checked; the connection is refused otherwise.
   An incomplete body (shorter than its length, no last chunk, or a TLS connection that ended
   without close_notify) is not saved. *)

IMPORT Texts, Files, http, httpsPure, TLS13Live, strTypes, out;

VAR secure: BOOLEAN;  (* the last Split saw https *)

(* scheme, host, port and path of url *)
PROCEDURE Split(VAR url, host, port, path: ARRAY OF CHAR): BOOLEAN;
VAR i, j: LONGINT;
BEGIN
  i := 0; secure := FALSE;
  WHILE (url[i] # 0X) & (url[i] # ":") DO INC(i) END;
  IF (url[i] = ":") & (url[i + 1] = "/") & (url[i + 2] = "/") THEN
    IF (i >= 4) & (CAP(url[0]) = "H") & (CAP(url[1]) = "T") & (CAP(url[2]) = "T") & (CAP(url[3]) = "P")
      & ((i = 4) OR (i = 5) & (CAP(url[4]) = "S")) THEN secure := i = 5
    ELSE out.String("fetch: http:// or https:// expected"); out.Ln; RETURN FALSE
    END;
    INC(i, 3)
  ELSE i := 0
  END;
  j := 0;
  IF url[i] = "[" THEN  (* [IPv6] *)
    INC(i);
    WHILE (url[i] # 0X) & (url[i] # "]") DO host[j] := url[i]; INC(i); INC(j) END;
    IF url[i] = "]" THEN INC(i) END
  ELSE
    WHILE (url[i] # 0X) & (url[i] # ":") & (url[i] # "/") DO host[j] := url[i]; INC(i); INC(j) END
  END;
  host[j] := 0X; j := 0;
  IF url[i] = ":" THEN
    INC(i); WHILE (url[i] >= "0") & (url[i] <= "9") DO port[j] := url[i]; INC(i); INC(j) END
  END;
  IF j # 0 THEN port[j] := 0X ELSIF secure THEN COPY("443", port) ELSE COPY("80", port) END;
  j := 0;
  IF url[i] # "/" THEN path[0] := "/"; j := 1 END;
  WHILE url[i] # 0X DO path[j] := url[i]; INC(i); INC(j) END;
  path[j] := 0X;
  RETURN host[0] # 0X
END Split;

PROCEDURE Fetch(VAR url: ARRAY OF CHAR; VAR h: http.Client): BOOLEAN;
VAR host, port, path: ARRAY 1024 OF CHAR; body: strTypes.pstring;
BEGIN
  IF ~Split(url, host, port, path) THEN out.String("fetch: bad url "); out.String(url); out.Ln; RETURN FALSE END;
  IF secure THEN h := httpsPure.Create(host, port, path) ELSE h := http.Create(host, port, path) END;
  body := h.Get(h);
  RETURN body # NIL
END Fetch;

(** fetch.Get url [file] *)
PROCEDURE Get*;
VAR A: Texts.Reader; url, name: ARRAY 1024 OF CHAR; h: http.Client; f: Files.File; R: Files.Rider; i: LONGINT;
BEGIN
  Texts.OpenArgs(A);
  IF ~Texts.Arg(A, url) THEN out.String("usage: fetch.Get url [file]"); out.Ln; RETURN END;
  IF ~Fetch(url, h) THEN RETURN END;
  IF h.rspnFirstLine = NIL THEN out.String("fetch: no answer from the server"); out.Ln; RETURN END;
  out.String(h.rspnFirstLine^); out.String(", "); out.Int(h.rspnContentLength, 0); out.String(" bytes");
  IF ~h.rspnComplete THEN out.String(", incomplete: not saved"); out.Ln; RETURN END;
  IF Texts.Arg(A, name) THEN
    f := Files.New(name);
    IF f = NIL THEN out.String(", cannot create "); out.String(name)
    ELSE
      Files.Set(R, f, 0); i := 0;
      WHILE i < h.rspnContentLength DO Files.Write(R, h.rspnBody[i]); INC(i) END;
      Files.Register(f); out.String(" in "); out.String(name)
    END
  ELSE h.Save(h)
  END;
  out.Ln
END Get;

(** fetch.Verbose -- print the TLS handshake in detail *)
PROCEDURE Verbose*;
BEGIN TLS13Live.verbose := TRUE
END Verbose;

(** fetch.Quiet *)
PROCEDURE Quiet*;
BEGIN TLS13Live.verbose := FALSE
END Quiet;

(** fetch.Show url *)
PROCEDURE Show*;
VAR A: Texts.Reader; url: ARRAY 1024 OF CHAR; h: http.Client; i: LONGINT;
BEGIN
  Texts.OpenArgs(A);
  IF ~Texts.Arg(A, url) THEN out.String("usage: fetch.Show url"); out.Ln; RETURN END;
  IF ~Fetch(url, h) THEN RETURN END;
  IF h.rspnFirstLine = NIL THEN out.String("fetch: no answer from the server"); out.Ln; RETURN END;
  i := 0;
  WHILE i < h.rspnContentLength DO
    IF h.rspnBody[i] # 0DX THEN out.Char(h.rspnBody[i]) END;  (* out.Char(0DX) is a line end *)
    INC(i)
  END;
  IF ~h.rspnComplete THEN out.Ln; out.String("fetch: the body is incomplete"); out.Ln END
END Show;

END fetch.
