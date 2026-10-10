MODULE TLSServeTest;  (* TLSServeTest.Run cert.pem key.pem port [n]: a TLS 1.3 server for tests (TLS13Server);
  it answers n connections (default 1) with an HTTP/1.0 response: the host name the client asked
  for and what it sent first; "big" in the request adds 100 000 bytes *)
IMPORT TLS13Server, TLS13Live, Sockets, texts, out, Oberon := Oberon0;

VAR listener: Sockets.Socket;

PROCEDURE Close;
BEGIN
  IF listener # NIL THEN Sockets.Close(listener); listener := NIL END
END Close;

PROCEDURE Int(s: ARRAY OF CHAR): LONGINT;
VAR i, v: LONGINT;
BEGIN
  i := 0; v := 0; WHILE (s[i] >= "0") & (s[i] <= "9") DO v := v * 10 + ORD(s[i]) - ORD("0"); INC(i) END;
  RETURN v
END Int;

PROCEDURE Has(VAR s: ARRAY OF CHAR; w: ARRAY OF CHAR): BOOLEAN;
VAR i, j: LONGINT;
BEGIN
  i := 0;
  WHILE s[i] # 0X DO
    j := 0; WHILE (w[j] # 0X) & (s[i + j] = w[j]) DO INC(j) END;
    IF w[j] = 0X THEN RETURN TRUE END;
    INC(i)
  END;
  RETURN FALSE
END Has;

PROCEDURE Reply(VAR s: TLS13Live.State; VAR req: ARRAY OF CHAR);
VAR ok: BOOLEAN; nl: ARRAY 3 OF CHAR; line: ARRAY 101 OF CHAR; i: LONGINT;
BEGIN
  nl[0] := 0DX; nl[1] := 0AX; nl[2] := 0X;
  ok := TLS13Live.WriteAppString(s, "HTTP/1.0 200 OK") & TLS13Live.WriteAppString(s, nl) &
    TLS13Live.WriteAppString(s, "Content-Type: text/plain") & TLS13Live.WriteAppString(s, nl) & TLS13Live.WriteAppString(s, nl) &
    TLS13Live.WriteAppString(s, "host: ") & TLS13Live.WriteAppString(s, TLS13Server.serverName) &
    TLS13Live.WriteAppString(s, nl) & TLS13Live.WriteAppString(s, "request: ") & TLS13Live.WriteAppString(s, req);
  IF Has(req, "big") THEN
    i := 0; WHILE i < 99 DO line[i] := CHR(ORD("a") + i MOD 26); INC(i) END;
    line[99] := 0AX; line[100] := 0X;
    i := 0; WHILE ok & (i < 1000) DO ok := TLS13Live.WriteAppString(s, line); INC(i) END
  END
END Reply;

PROCEDURE Run*;
VAR
  A: texts.Reader; cert, key, arg: ARRAY 256 OF CHAR; port, n, k, got, peerPort: LONGINT;
  id: TLS13Server.Identity; s: TLS13Live.State; c: Sockets.Socket; peer: Sockets.Address;
  req: ARRAY 1025 OF CHAR;
BEGIN
  texts.OpenArgs(A);
  IF ~texts.Arg(A, cert) OR ~texts.Arg(A, key) OR ~texts.Arg(A, arg) THEN
    out.String("usage: TLSServeTest.Run cert.pem key.pem port [n]"); out.Ln; RETURN
  END;
  port := Int(arg); n := 1;
  IF texts.Arg(A, arg) THEN n := Int(arg) END;
  IF ~TLS13Server.Load(cert, key, id) THEN out.String(TLS13Server.lastError); out.Ln; RETURN END;
  Close; Oberon.OnStop(Close);
  listener := Sockets.Listen(Sockets.Inet6, port, 8);
  IF listener = NIL THEN out.String("cannot listen"); out.Ln; RETURN END;
  k := 0;
  WHILE k < n DO
    c := Sockets.Accept(listener, peer, peerPort);
    IF c # NIL THEN
      Sockets.SetTimeout(c, 10000);
      IF TLS13Server.Accept(c.fd, id, s) THEN
        IF TLS13Live.ReadAppMax(s, req, 1024, got) THEN Reply(s, req) END;
        TLS13Live.Disconnect(s);
        out.String("served "); out.String(TLS13Server.serverName); out.Ln
      ELSE out.String("handshake failed: "); out.String(TLS13Server.lastError); out.Ln
      END
    END;
    INC(k)
  END;
  Close
END Run;

BEGIN
  listener := NIL
END TLSServeTest.
