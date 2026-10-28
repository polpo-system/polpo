MODULE AsyncNetSystemTest;  (** loksh AsyncNetSystemTest.Run: AsyncOpenConnection of NetSystem on 127.0.0.1 *)

(* The cases of TestAsyncNetSystem of norayr/Internet, with the peers its Python runner makes made here:
  basic (an asynchronous connection completed, read and written; a busy local port; broadcast; a
  passive open), refused (a port nobody listens on), pending (a listener with a full queue: the
  connection stays in waitCon, reading and writing are refused, closing frees the local port), resume
  (a child process takes the queued connections, the pending one completes) and blocking (a child
  sends in pieces with pauses and reads 8 MB: the exact reads and writes after an asynchronous open
  wait as before). *)

IMPORT N := NetSystem, S := Sockets, Linux0, SYSTEM, Out;

VAR checks, failed: LONGINT; ip: N.IPAdr; address: S.Address;

PROCEDURE Check(name: ARRAY OF CHAR; value: BOOLEAN);
BEGIN
  INC(checks);
  IF ~value THEN INC(failed); Out.String("FAIL "); Out.String(name); Out.Ln END
END Check;

PROCEDURE Sleep(ms: LONGINT);
VAR tv: ARRAY 2 OF LONGINT; r: LONGINT;
BEGIN
  tv[0] := ms DIV 1000; tv[1] := ms MOD 1000 * 1000; r := Linux0.Select0(0, 0, 0, 0, SYSTEM.ADR(tv[0]))
END Sleep;

PROCEDURE Port(p: LONGINT): INTEGER;
BEGIN
  IF p >= 32768 THEN DEC(p, 65536) END;
  RETURN SHORT(p)
END Port;

(* a port nobody listens on (a listener closed again) *)
PROCEDURE FreePort(): LONGINT;
VAR l: S.Socket; e: S.Endpoint;
BEGIN
  l := S.ListenNonblocking(address, 0, 1); Check("free port", (l # NIL) & S.LocalEndpoint(l, e)); S.Close(l);
  RETURN e.port
END FreePort;

PROCEDURE Connected(c: N.Connection): BOOLEAN;
VAR i: LONGINT; state: INTEGER;
BEGIN
  state := N.State(c); i := 0;
  WHILE (state = N.waitCon) & (i < 5000) DO Sleep(1); state := N.State(c); INC(i) END;
  RETURN state = N.inout
END Connected;

PROCEDURE Basic;
VAR listener, reserve, peer, client: S.Socket; endpoint, local: S.Endpoint;
  c, passive, accepted: N.Connection; result, remotePort: INTEGER; remoteIP: N.IPAdr; i: LONGINT; byte: CHAR;
BEGIN
  listener := S.ListenNonblocking(address, 0, 4); Check("listener", listener # NIL);
  Check("listener endpoint", S.LocalEndpoint(listener, endpoint));
  reserve := S.ListenNonblocking(address, 0, 4); Check("reserve local port", reserve # NIL);
  Check("reserved endpoint", S.LocalEndpoint(reserve, local));
  N.AsyncOpenConnection(c, Port(local.port), ip, Port(endpoint.port), result);
  Check("busy local port rejected", (result = N.error) & (N.State(c) = N.errorCon));
  N.CloseConnection(c); S.Close(reserve);
  N.AsyncOpenConnection(c, Port(local.port), ip, Port(endpoint.port), result);
  Check("async started", (result = N.done) & (c.res = N.done));
  Check("async completed", Connected(c));
  peer := S.AcceptNonblocking(listener, endpoint); Check("accepted async peer", peer # NIL);
  Check("local port honored", endpoint.port = local.port);
  N.GetPartner(c, remoteIP, remotePort);
  Check("partner address", remoteIP = ip);
  Check("partner port", S.LocalEndpoint(listener, endpoint) & (remotePort = Port(endpoint.port)));
  Check("no data available", (N.Available(c) = 0) & (c.res = N.done));
  Check("peer write", S.SendString(peer, "A") = 1);
  N.Read(c, byte); Check("read after async", (byte = "A") & (c.res = N.done));
  N.Write(c, "B"); Check("write after async", c.res = N.done);
  N.CloseConnection(c); Check("closed", N.State(c) = N.closed);
  N.CloseConnection(c); S.Close(peer); S.Close(listener);
  N.AsyncOpenConnection(c, 0, N.allIP, 1, result);
  Check("broadcast rejected", (result = N.error) & (N.State(c) = N.errorCon));
  N.CloseConnection(c);
  reserve := S.ListenNonblocking(address, 0, 4); Check("passive port reservation", reserve # NIL);
  Check("passive endpoint", S.LocalEndpoint(reserve, local)); S.Close(reserve);
  N.AsyncOpenConnection(passive, Port(local.port), N.anyIP, N.anyport, result);
  Check("passive opened", (result = N.done) & (N.State(passive) = N.listening));
  Check("passive not requested", ~N.Requested(passive));
  client := S.ConnectFrom(address, address, local.port); Check("passive client", client # NIL);
  i := 0;
  WHILE ~N.Requested(passive) & (i < 5000) DO Sleep(1); INC(i) END;
  Check("passive requested", N.Requested(passive));
  N.Accept(passive, accepted, result);
  Check("passive accepted", (result = N.done) & (N.State(accepted) = N.inout));
  N.CloseConnection(accepted); N.CloseConnection(passive); S.Close(client)
END Basic;

PROCEDURE Refused(port: LONGINT);
VAR c: N.Connection; result, state: INTEGER; i: LONGINT; byte: CHAR;
BEGIN
  N.AsyncOpenConnection(c, 0, ip, Port(port), result);
  Check("refusal start result", (result = N.done) OR (result = N.error));
  state := N.State(c); i := 0;
  WHILE (state = N.waitCon) & (i < 5000) DO Sleep(1); state := N.State(c); INC(i) END;
  Check("refused connection", (state = N.errorCon) & (c.res = N.error));
  i := 1;
  WHILE i <= 32 DO
    Check("stable error state", N.State(c) = N.errorCon);
    Check("failed available", (N.Available(c) = 0) & (c.res = N.error));
    INC(i)
  END;
  N.Read(c, byte); Check("failed read", c.res = N.error);
  N.Write(c, "x"); Check("failed write", c.res = N.error);
  N.CloseConnection(c); Check("failed connection closed", N.State(c) = N.closed)
END Refused;

(* a listener of a queue of 1 filled with connections nobody takes, so that the next one stays pending;
  fillers: those connections *)
PROCEDURE FullListener(VAR fillers: ARRAY OF S.Socket; VAR n: LONGINT): S.Socket;
VAR l: S.Socket; e: S.Endpoint; full: BOOLEAN;
BEGIN
  l := S.ListenNonblocking(address, 0, 1); Check("listener of a full queue", (l # NIL) & S.LocalEndpoint(l, e));
  n := 0; full := FALSE;
  WHILE ~full & (n < LEN(fillers)) DO
    fillers[n] := S.ConnectFrom(address, address, e.port);
    IF fillers[n] # NIL THEN
      full := Linux0.Poll0(fillers[n].fd, TRUE, 100) = 0;  (* not writable: the handshake cannot finish *)
      INC(n)
    END
  END;
  Check("queue filled", full);
  RETURN l
END FullListener;

PROCEDURE Pending(port, localPort: LONGINT);
VAR c: N.Connection; result: INTEGER; i, attempt: LONGINT; byte: CHAR; probe: S.Socket;
BEGIN
  attempt := 1;
  WHILE attempt <= 4 DO
    N.AsyncOpenConnection(c, Port(localPort), ip, Port(port), result);
    Check("pending started", (result = N.done) & (c.res = N.done));
    i := 1;
    WHILE i <= 32 DO
      Check("genuinely pending", N.State(c) = N.waitCon);
      Check("pending available", (N.Available(c) = 0) & (c.res = N.done));
      Sleep(1); INC(i)
    END;
    N.Read(c, byte); Check("pending read guarded", (c.res = N.error) & (N.State(c) = N.waitCon));
    N.Write(c, "x"); Check("pending write guarded", (c.res = N.error) & (N.State(c) = N.waitCon));
    N.CloseConnection(c); Check("pending canceled", N.State(c) = N.closed);
    N.CloseConnection(c);
    probe := S.ListenNonblocking(address, localPort, 1);
    Check("cancellation released descriptor and port", probe # NIL); S.Close(probe);
    INC(attempt)
  END
END Pending;

(* the child of Resume: after a pause, take the queued connections; answer "R" to the one that sends "Q" *)
PROCEDURE Drain(l: S.Socket);
VAR s: S.Socket; e: S.Endpoint; buf: ARRAY 4 OF CHAR; n, i: LONGINT; done: BOOLEAN;
BEGIN
  Sleep(500); done := FALSE; i := 0;
  WHILE ~done & (i < 1000) DO
    s := S.AcceptNonblocking(l, e);
    IF s = NIL THEN Sleep(10); INC(i)
    ELSIF S.SetBlocking(s, TRUE) THEN
      S.SetTimeout(s, 5000); n := S.Receive(s, buf, 1);
      IF (n = 1) & (buf[0] = "Q") THEN n := S.SendString(s, "R"); done := TRUE END;
      S.Close(s)
    END
  END
END Drain;

PROCEDURE Resume(l: S.Socket; port: LONGINT);
VAR c: N.Connection; result: INTEGER; byte: CHAR; pid, r, status: LONGINT;
BEGIN
  pid := Linux0.Fork0();
  IF pid = 0 THEN Drain(l); Linux0.Exit0(0) END;
  N.AsyncOpenConnection(c, 0, ip, Port(port), result);
  Check("resume started pending", (result = N.done) & (N.State(c) = N.waitCon));
  Check("resume initially empty", (N.Available(c) = 0) & (c.res = N.done));
  Check("pending became connected", Connected(c));
  N.Write(c, "Q"); Check("resumed write", c.res = N.done);
  N.Read(c, byte); Check("resumed read", (c.res = N.done) & (byte = "R"));
  N.CloseConnection(c);
  r := Linux0.Waitpid0(pid, SYSTEM.ADR(status), 0)
END Resume;

(* the child of Blocking: send "abcdefg" in pieces with pauses, read 128 times 64 KB of "x", answer "Y" *)
PROCEDURE Peer(l: S.Socket);
VAR s: S.Socket; a: S.Address; port, n, total: LONGINT; buf: ARRAY 65536 OF CHAR; ok: BOOLEAN;
BEGIN
  s := S.Accept(l, a, port);
  IF s # NIL THEN
    S.SetTimeout(s, 10000);
    Sleep(100); n := S.SendString(s, "ab"); Sleep(100); n := S.SendString(s, "cd"); Sleep(100);
    buf[0] := "e"; buf[1] := "f"; buf[2] := "g"; buf[3] := 0X; n := S.Send(s, buf, 4);
    Sleep(300); total := 0; ok := TRUE;
    WHILE ok & (total < 128 * 65536) DO
      n := S.Receive(s, buf, LEN(buf));
      IF n <= 0 THEN ok := FALSE ELSE INC(total, n) END
    END;
    IF ok THEN n := S.SendString(s, "Y") END;
    S.Close(s)
  END
END Peer;

PROCEDURE Blocking;
VAR c: N.Connection; result: INTEGER; data: ARRAY 65536 OF CHAR; reply: ARRAY 8 OF CHAR;
  i, pid, r, status, port: LONGINT; byte: CHAR; l: S.Socket;
BEGIN
  l := S.ListenAt(address, 0, 1); Check("blocking listener", (l # NIL) & S.LocalAddress(l, address, port));
  pid := Linux0.Fork0();
  IF pid = 0 THEN Peer(l); Linux0.Exit0(0) END;
  S.Close(l);
  N.AsyncOpenConnection(c, 0, ip, Port(port), result);
  Check("blocking test started", result = N.done); Check("blocking test connected", Connected(c));
  N.ReadBytes(c, 0, LEN(reply), reply);
  Check("delayed fragmented exact read", (c.res = N.done) & (reply = "abcdefg"));
  i := 0; WHILE i < LEN(data) DO data[i] := "x"; INC(i) END;
  i := 1;
  WHILE i <= 128 DO N.WriteBytes(c, 0, LEN(data), data); Check("backpressured exact write", c.res = N.done); INC(i) END;
  N.Read(c, byte); Check("peer verified complete write", (c.res = N.done) & (byte = "Y"));
  N.CloseConnection(c);
  r := Linux0.Waitpid0(pid, SYSTEM.ADR(status), 0)
END Blocking;

(** AsyncNetSystemTest.Run *)
PROCEDURE Run*;
VAR ok: BOOLEAN; fillers: ARRAY 16 OF S.Socket; n, i, port, localPort: LONGINT; l: S.Socket; e: S.Endpoint;
BEGIN
  checks := 0; failed := 0;
  N.ToHost("127.0.0.1", ip, ok); Check("IPv4 loopback", ok);
  Check("socket loopback", S.ParseAddress("127.0.0.1", address));
  Basic;
  Refused(FreePort());
  l := FullListener(fillers, n);
  IF (l # NIL) & S.LocalEndpoint(l, e) THEN
    port := e.port; localPort := FreePort();
    Pending(port, localPort);
    i := 0; WHILE i < n DO S.Close(fillers[i]); INC(i) END;  (* their connections stay queued until taken *)
    Resume(l, port);
    S.Close(l)
  END;
  Check("socket loopback", S.ParseAddress("127.0.0.1", address));
  Blocking;
  Out.String("AsyncNetSystemTest: "); Out.Int(checks, 0); Out.String(" checks, "); Out.Int(failed, 0);
  Out.String(" failed"); Out.Ln
END Run;

END AsyncNetSystemTest.
