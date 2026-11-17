MODULE InternetTimeoutTest;  (* Internet.timeout: reads from a server that sends nothing end after the
  timeout, in plain connections and in a TLS handshake; an answer within the timeout is read. The server is
  a child process. TLSCABundle.LoadDefault takes no descriptor after the first load. *)

IMPORT Internet, Sockets, TLS := TLS13Live, TLSCABundle, Kernel, Linux0, SYSTEM, Out;

CONST
  Limit = 1000;  (* the timeout of the tests, ms *)
  Silent = 0; Answer = 1;  (* what the server does *)

TYPE
  Bundle = POINTER TO TLSCABundle.Bundle;

VAR
  checks, fails: LONGINT;

PROCEDURE Check(what: ARRAY OF CHAR; ok: BOOLEAN);
BEGIN
  INC(checks);
  IF ~ok THEN INC(fails); Out.String("FAIL "); Out.String(what); Out.String(" (case "); Out.Int(checks, 0); Out.String(")"); Out.Ln END
END Check;

PROCEDURE Sleep(ms: LONGINT);
VAR tv: ARRAY 2 OF LONGINT; r: LONGINT;
BEGIN
  tv[0] := ms DIV 1000; tv[1] := ms MOD 1000 * 1000; r := Linux0.Select0(0, 0, 0, 0, SYSTEM.ADR(tv[0]))
END Sleep;

PROCEDURE Status(pid: LONGINT): LONGINT;  (* the exit status of child pid, -1 if it did not exit *)
VAR status, r: LONGINT;
BEGIN
  status := 0; r := Linux0.Waitpid0(pid, SYSTEM.ADR(status), 0);
  IF (r # pid) OR (status MOD 128 # 0) THEN RETURN -1 END;
  RETURN status DIV 256 MOD 256
END Status;

PROCEDURE Port(n: LONGINT; VAR s: ARRAY OF CHAR);
VAR d: ARRAY 8 OF CHAR; i, k: LONGINT;
BEGIN
  i := 0; REPEAT d[i] := CHR(n MOD 10 + ORD("0")); n := n DIV 10; INC(i) UNTIL n = 0;
  k := 0; WHILE i > 0 DO DEC(i); s[k] := d[i]; INC(k) END; s[k] := 0X
END Port;

(* the child: accepts one connection, sends nothing or "hello" after Limit DIV 4, then reads until the
  client has gone *)
PROCEDURE Server(l: Sockets.Socket; mode: LONGINT);
VAR c: Sockets.Socket; peer: Sockets.Address; p, n: LONGINT; buf: ARRAY 512 OF CHAR;
BEGIN
  c := Sockets.Accept(l, peer, p); IF c = NIL THEN Linux0.Exit0(3) END;
  IF mode = Answer THEN
    Sleep(Limit DIV 4); buf := "hello";
    IF Sockets.Send(c, buf, 5) # 5 THEN Linux0.Exit0(4) END
  END;
  REPEAT n := Sockets.Receive(c, buf, LEN(buf)) UNTIL n <= 0;
  Linux0.Exit0(0)
END Server;

(* one connection to a server child: plain or TLS (tls), the server Silent or Answer *)
PROCEDURE Connection(tls: BOOLEAN; mode: LONGINT);
VAR l: Sockets.Socket; a: Sockets.Address; port, pid, t: LONGINT; fd: Internet.Socket; ok: BOOLEAN;
  p: ARRAY 8 OF CHAR; buf: ARRAY 64 OF CHAR; state: TLS.State;
BEGIN
  ok := Sockets.ParseAddress("127.0.0.1", a);
  l := Sockets.ListenAt(a, 0, 1);
  IF (l = NIL) OR ~Sockets.LocalAddress(l, a, port) THEN Check("listener", FALSE); RETURN END;
  pid := Linux0.Fork0();
  IF pid = 0 THEN Server(l, mode) END;
  Sockets.Close(l); Port(port, p);
  Internet.timeout := Limit; t := Kernel.GetTimer();
  IF tls THEN
    TLS.Init(state); Check("no handshake", ~TLS.Connect("127.0.0.1", p, state))
  ELSIF ~Internet.Connect("127.0.0.1", p, fd) THEN Check("connect", FALSE)
  ELSIF mode = Silent THEN
    Check("read ends", ~Internet.Read(fd, buf)); Internet.Disconnect(fd)
  ELSE
    ok := Internet.Read(fd, buf); Check("answer read", ok & (buf = "hello")); Internet.Disconnect(fd)
  END;
  t := Kernel.GetTimer() - t; Internet.timeout := 0;
  IF mode = Silent THEN Check("after the timeout", (t >= Limit - 100) & (t < 10 * Limit))
  ELSE Check("before the timeout", t < Limit)
  END;
  Check("server done", Status(pid) = 0)
END Connection;

(* the number the next descriptor gets *)
PROCEDURE NextFd(): LONGINT;
VAR s: Sockets.Socket; fd: LONGINT;
BEGIN
  s := Sockets.OpenUDP(Sockets.Inet4, 0);
  IF s = NIL THEN RETURN -1 END;
  fd := s.fd; Sockets.Close(s);
  RETURN fd
END NextFd;

PROCEDURE Bundles;
VAR b: Bundle; fd, i: LONGINT; ok: BOOLEAN;
BEGIN
  NEW(b);
  IF ~TLSCABundle.LoadDefault(b^) THEN Out.String("no CA bundle: its checks skipped"); Out.Ln; RETURN END;
  fd := NextFd(); ok := TRUE; i := 0;
  WHILE i < 20 DO ok := ok & TLSCABundle.LoadDefault(b^); INC(i) END;
  Check("bundle loaded again", ok & (b.len > 0));
  Check("no descriptor per load", NextFd() = fd)
END Bundles;

PROCEDURE Run*;
BEGIN
  checks := 0; fails := 0;
  Connection(FALSE, Silent);
  Connection(FALSE, Answer);
  Connection(TRUE, Silent);
  Bundles;
  Out.String("InternetTimeoutTest: "); Out.Int(checks, 0); Out.String(" checks, "); Out.Int(fails, 0); Out.String(" failed"); Out.Ln
END Run;

END InternetTimeoutTest.
