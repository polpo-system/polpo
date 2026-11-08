MODULE TLSTestAsync;  (* the resumable client of TLS13Live: Begin, PollHandshake, ReadSome, WriteSome,
  FlushOutput, UseNonblocking, CloseNow (after test/TestAsyncRecords.Mod and test/async.py of the tls
  repository, with TLS13Server in a child process as the peer)

  Run in a scratch directory with SSL_CERT_FILE naming the certificate the test writes there:
    SSL_CERT_FILE=zq_tls_async.crt loksh TLSTestAsync.Run
  Records: partial record headers and bodies, a KeyUpdate request and the answer queued in order, the
  new keys, close_notify. Live: a TLS13Server child behind a relay child that passes the server's
  bytes on in pieces of 7, the client resumable (X25519) or blocking; refused for an IP address the
  certificate does not name and for a certificate not in the bundle.
  TLSTestAsync.Client host port [blocking] connects to a server (openssl s_server -tls1_3 -www, with
  -groups P-256 for a HelloRetryRequest), sends a GET and shows the start of the answer. *)

IMPORT TLS := TLS13Live, B := TLSBytes, Keys := TLS13Keys, Records := TLS13Records, HKDF := TLSHKDF,
  TLS13Server, TLSCertGen, Sockets, Internet, Files, Texts, Kernel, Linux0, SYSTEM, Out;

CONST
  Wait = 30000;  (* the most 1 ms pauses of a loop *)
  CA = "zq_tls_async.crt"; Key = "zq_tls_async.key"; Other = "zq_tls_other.crt"; OtherKey = "zq_tls_other.key";

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

(* --- records: the server side written by hand on a socket pair --- *)

PROCEDURE Send(peer: Sockets.Socket; VAR record: B.Buffer; at, count: LONGINT);
VAR n, done, waited: LONGINT;
BEGIN
  done := 0; waited := 0;
  WHILE (done < count) & (waited < Wait) DO
    n := Sockets.SendSome(peer, record.data, at + done, count - done);
    IF n > 0 THEN INC(done, n) ELSE Sleep(1); INC(waited) END
  END
END Send;

PROCEDURE Pending(VAR state: TLS.State): BOOLEAN;  (* ten reads of an incomplete record are all pending *)
VAR i, n: LONGINT; bytes: ARRAY 128 OF CHAR; ok: BOOLEAN;
BEGIN
  ok := TRUE; i := 0;
  WHILE i < 10 DO n := TLS.ReadSome(state, bytes, 0, LEN(bytes)); IF n # -2 THEN ok := FALSE END; INC(i) END;
  RETURN ok
END Pending;

PROCEDURE GetRecord(peer: Sockets.Socket; VAR received: B.Buffer): BOOLEAN;  (* one record the client wrote *)
VAR count, need, n, waited: LONGINT;
BEGIN
  B.SetLen(received, 16384 + 256); count := 0; need := 5; waited := 0;
  WHILE (count < need) & (waited < Wait) DO
    n := Sockets.ReceiveSome(peer, received.data, count, need - count);
    IF n > 0 THEN INC(count, n)
    ELSIF Sockets.WouldBlock(n) THEN Sleep(1); INC(waited)
    ELSE waited := Wait
    END;
    IF count = 5 THEN need := 5 + LONG(ORD(received.data[3])) * 256 + ORD(received.data[4]) END
  END;
  received.len := count;
  RETURN count = need
END GetRecord;

PROCEDURE RecordTests;
VAR listener, peer, accepted: Sockets.Socket; local: Sockets.Address; endpoint, remote: Sockets.Endpoint;
  state: TLS.State; a, b, keyA, ivA, keyB, ivB, plain, record, empty, next, received: B.Buffer;
  bytes: ARRAY 128 OF CHAR; n, i, kind, waited: LONGINT;
BEGIN
  Sockets.AnyAddress(Sockets.Inet4, local); listener := Sockets.ListenNonblocking(local, 0, 2);
  Check("listener", (listener # NIL) & Sockets.LocalEndpoint(listener, endpoint));
  IF listener = NIL THEN RETURN END;
  Check("loopback", Sockets.ParseAddress("127.0.0.1", endpoint.address));
  peer := Sockets.ConnectFrom(local, endpoint.address, endpoint.port); Check("connect", peer # NIL);
  IF peer = NIL THEN Sockets.Close(listener); RETURN END;
  waited := 0;
  REPEAT n := Sockets.PollConnect(peer); Sleep(1); INC(waited) UNTIL (n # 1) OR (waited = Wait);
  Check("connected", n = 0);
  accepted := Sockets.AcceptNonblocking(listener, remote); Check("accepted", accepted # NIL); Sockets.Close(listener);
  IF accepted = NIL THEN Sockets.Close(peer); RETURN END;
  B.SetLen(a, 32); B.SetLen(b, 32);
  i := 0; WHILE i < 32 DO a.data[i] := CHR(i); b.data[i] := CHR(i + 32); INC(i) END;
  TLS.Init(state); TLS.Accepted(state, Sockets.Release(accepted), a, b);
  Check("UseNonblocking", TLS.UseNonblocking(state));
  Keys.TrafficKey(a, keyA); Keys.TrafficIV(a, ivA); Keys.TrafficKey(b, keyB); Keys.TrafficIV(b, ivB);

  (* a record in pieces: 2 bytes of its header, the rest of it, one byte of the body, the rest *)
  B.Init(plain); B.AppendString(plain, "abc");
  Records.ProtectRecord(keyB, ivB, 0, Records.ApplicationData, plain, record);
  Send(peer, record, 0, 2); Check("pending after 2 header bytes", Pending(state));
  Send(peer, record, 2, 3); Check("pending after the header", Pending(state));
  Send(peer, record, 5, 1); Check("pending after 1 body byte", Pending(state));
  Send(peer, record, 6, record.len - 6);
  waited := 0;
  REPEAT n := TLS.ReadSome(state, bytes, 0, LEN(bytes)); Sleep(1); INC(waited) UNTIL (n # -2) OR (waited = Wait);
  Check("record read whole", (n = 3) & (bytes[0] = "a") & (bytes[2] = "c"));

  (* a KeyUpdate that asks for ours: new server keys, our KeyUpdate queued, then the new client keys *)
  B.Init(plain); B.AppendByte(plain, 24); B.PutBE24(plain, 1); B.AppendByte(plain, 1);
  Records.ProtectRecord(keyB, ivB, 1, Records.Handshake, plain, record); Send(peer, record, 0, record.len);
  waited := 0;
  REPEAT n := TLS.ReadSome(state, bytes, 0, LEN(bytes)); Sleep(1); INC(waited)
  UNTIL (n # -2) OR (state.serverAppSeq = 0) OR (waited = Wait);
  Check("KeyUpdate taken, nothing to read", (n = -2) & (state.serverAppSeq = 0));
  waited := 0;
  REPEAT n := TLS.FlushOutput(state); Sleep(1); INC(waited) UNTIL (n # 0) OR (waited = Wait);
  Check("answer flushed", n = 1);
  B.Init(empty); HKDF.ExpandLabel(b, "traffic upd", empty, 32, next); B.Copy(next, b);
  Keys.TrafficKey(b, keyB); Keys.TrafficIV(b, ivB);
  Check("new server key", B.EqualConstTime(keyB, state.serverAppKey) & (state.serverAppSeq = 0));
  Check("answer received", GetRecord(peer, received));
  Check("answer is a KeyUpdate", Records.OpenRecord(keyA, ivA, 0, received, kind, plain) & (kind = Records.Handshake)
    & (plain.len = 5) & (ORD(plain.data[0]) = 24) & (ORD(plain.data[4]) = 0));
  HKDF.ExpandLabel(a, "traffic upd", empty, 32, next); B.Copy(next, a);
  Keys.TrafficKey(a, keyA); Keys.TrafficIV(a, ivA);
  Check("new client key", B.EqualConstTime(keyA, state.clientAppKey));
  bytes := "after update"; waited := 0;
  REPEAT n := TLS.WriteSome(state, bytes, 0, 12); Sleep(1); INC(waited) UNTIL (n # -2) OR (waited = Wait);
  Check("written after the update", n = 12);
  Check("data received", GetRecord(peer, received));
  Check("data with the new key", Records.OpenRecord(keyA, ivA, 0, received, kind, plain)
    & (kind = Records.ApplicationData) & (plain.len = 12) & (plain.data[0] = "a"));

  (* close_notify: a read gives 0 *)
  B.Init(plain); B.AppendByte(plain, 1); B.AppendByte(plain, 0);
  Records.ProtectRecord(keyB, ivB, 0, Records.Alert, plain, record); Send(peer, record, 0, record.len);
  waited := 0;
  REPEAT n := TLS.ReadSome(state, bytes, 0, LEN(bytes)); Sleep(1); INC(waited) UNTIL (n # -2) OR (waited = Wait);
  Check("close_notify read as 0", (n = 0) & state.closeNotify);
  TLS.CloseNow(state); Sockets.Close(peer)
END RecordTests;

(* --- live: a TLS13Server child behind a relay child --- *)

PROCEDURE WriteFile(name: ARRAY OF CHAR; VAR text: ARRAY OF CHAR);
VAR f: Files.File; r: Files.Rider; n: LONGINT;
BEGIN
  n := 0; WHILE text[n] # 0X DO INC(n) END;
  f := Files.New(name); Files.Set(r, f, 0); Files.WriteBytes(r, text, n); Files.Register(f)
END WriteFile;

PROCEDURE Certificates(): BOOLEAN;  (* two certificates for localhost and their keys *)
VAR cert, key: ARRAY 4096 OF CHAR;
BEGIN
  IF ~TLSCertGen.SelfSigned("localhost", "", "localhost", 2, cert, key) THEN RETURN FALSE END;
  WriteFile(CA, cert); WriteFile(Key, key);
  IF ~TLSCertGen.SelfSigned("localhost", "", "localhost", 2, cert, key) THEN RETURN FALSE END;
  WriteFile(Other, cert); WriteFile(OtherKey, key);
  RETURN TRUE
END Certificates;

(* the server child: the handshake, "hello" in, "world" out; exit status 0 if all went so *)
PROCEDURE Server(l: Sockets.Socket; cert, key: ARRAY OF CHAR);
VAR s: Sockets.Socket; peer: Sockets.Address; port, n: LONGINT; id: TLS13Server.Identity;
  state: TLS.State; data: ARRAY 64 OF CHAR;
BEGIN
  IF ~TLS13Server.Load(cert, key, id) THEN Linux0.Exit0(2) END;
  s := Sockets.Accept(l, peer, port); IF s = NIL THEN Linux0.Exit0(3) END;
  Sockets.SetTimeout(s, Wait);
  TLS.Init(state);
  IF ~TLS13Server.Accept(Sockets.Release(s), id, state) THEN Linux0.Exit0(1) END;
  IF ~TLS.ReadApp(state, data, n) OR (n # 5) THEN Linux0.Exit0(4) END;
  data[5] := 0X; IF data # "hello" THEN Linux0.Exit0(5) END;
  IF ~TLS.WriteAppString(state, "world") THEN Linux0.Exit0(6) END;
  TLS.Disconnect(state); Linux0.Exit0(0)
END Server;

PROCEDURE Pass(from, to: Sockets.Socket; piece: LONGINT; VAR open: BOOLEAN): BOOLEAN;
  (* what from has, on to in pieces; TRUE if something came *)
VAR buf: ARRAY 4096 OF CHAR; n, at, m, k, waited: LONGINT;
BEGIN
  n := Sockets.ReceiveSome(from, buf, 0, LEN(buf));
  IF n = 0 THEN open := FALSE; RETURN FALSE
  ELSIF n < 0 THEN IF ~Sockets.WouldBlock(n) THEN open := FALSE END; RETURN FALSE
  END;
  at := 0; waited := 0;
  WHILE (at < n) & (waited < Wait) DO
    k := n - at; IF k > piece THEN k := piece END;
    m := Sockets.SendSome(to, buf, at, k);
    IF m > 0 THEN INC(at, m); IF piece < LEN(buf) THEN Sleep(1) END
    ELSIF Sockets.WouldBlock(m) THEN Sleep(1); INC(waited)
    ELSE at := n; open := FALSE
    END
  END;
  RETURN TRUE
END Pass;

(* the relay child: the client's bytes to the server as they come, the server's to the client in pieces of 7 *)
PROCEDURE Relay(l: Sockets.Socket; port: LONGINT);
VAR c, s: Sockets.Socket; peer, a: Sockets.Address; p, idle: LONGINT; open, moved: BOOLEAN;
BEGIN
  c := Sockets.Accept(l, peer, p); IF c = NIL THEN Linux0.Exit0(3) END;
  IF ~Sockets.ParseAddress("127.0.0.1", a) THEN Linux0.Exit0(3) END;
  s := Sockets.Connect(a, port); IF s = NIL THEN Linux0.Exit0(4) END;
  IF ~Sockets.SetBlocking(c, FALSE) OR ~Sockets.SetBlocking(s, FALSE) THEN Linux0.Exit0(5) END;
  open := TRUE; idle := 0;
  WHILE open & (idle < Wait) DO
    moved := Pass(c, s, 4096, open);
    IF open & Pass(s, c, 7, open) THEN moved := TRUE END;
    IF moved THEN idle := 0 ELSE Sleep(1); INC(idle) END
  END;
  Sockets.Close(c); Sockets.Close(s); Linux0.Exit0(0)
END Relay;

PROCEDURE Port(n: LONGINT; VAR s: ARRAY OF CHAR);
VAR d: ARRAY 8 OF CHAR; i, k: LONGINT;
BEGIN
  i := 0; REPEAT d[i] := CHR(n MOD 10 + ORD("0")); n := n DIV 10; INC(i) UNTIL n = 0;
  k := 0; WHILE i > 0 DO DEC(i); s[k] := d[i]; INC(k) END; s[k] := 0X
END Port;

(* one connection: mode "async", "blocking" or "reject"; host the name checked against the certificate *)
PROCEDURE Live(mode, host, cert, key: ARRAY OF CHAR);
VAR sl, rl: Sockets.Socket; a: Sockets.Address; sport, rport, server, relay, n, waited: LONGINT;
  fd: Internet.Socket; state: TLS.State; result: INTEGER; ok: BOOLEAN; port: ARRAY 8 OF CHAR;
  data: ARRAY 64 OF CHAR;
BEGIN
  ok := Sockets.ParseAddress("127.0.0.1", a);
  sl := Sockets.ListenAt(a, 0, 1); rl := Sockets.ListenAt(a, 0, 1);
  IF (sl = NIL) OR (rl = NIL) OR ~Sockets.LocalAddress(sl, a, sport) OR ~Sockets.LocalAddress(rl, a, rport) THEN
    Check("listeners", FALSE); RETURN
  END;
  server := Linux0.Fork0();
  IF server = 0 THEN Sockets.Close(rl); Server(sl, cert, key) END;
  relay := Linux0.Fork0();
  IF relay = 0 THEN Sockets.Close(sl); Relay(rl, sport) END;
  Sockets.Close(sl); Sockets.Close(rl);
  Port(rport, port); TLS.Init(state);
  IF ~Internet.Connect("127.0.0.1", port, fd) THEN Check("connect to the relay", FALSE)
  ELSIF mode = "blocking" THEN
    ok := TLS.Start(host, fd, state); Check("blocking handshake", ok);
    IF ok THEN
      Check("blocking write", TLS.WriteAppString(state, "hello"));
      ok := TLS.ReadApp(state, data, n); Check("blocking read", ok & (n = 5));
      data[5] := 0X; Check("blocking answer", data = "world")
    END;
    TLS.CloseNow(state)
  ELSE
    Check("Begin", TLS.Begin(host, fd, state)); waited := 0;
    REPEAT result := TLS.PollHandshake(state); Sleep(1); INC(waited) UNTIL (result # 0) OR (waited = Wait);
    IF mode = "reject" THEN
      Check("refused", result < 0);
      IF result > 0 THEN Out.String("  accepted: "); Out.String(host); Out.Ln END
    ELSIF result > 0 THEN
      data := "hello"; waited := 0;
      REPEAT n := TLS.WriteSome(state, data, 0, 5); Sleep(1); INC(waited) UNTIL (n # -2) OR (waited = Wait);
      Check("resumable write", n = 5); waited := 0;
      REPEAT n := TLS.ReadSome(state, data, 0, LEN(data) - 1); Sleep(1); INC(waited) UNTIL (n # -2) OR (waited = Wait);
      Check("resumable read", n = 5);
      IF n >= 0 THEN data[n] := 0X END; Check("resumable answer", data = "world")
    ELSE
      Check("resumable handshake", FALSE); Out.String("  "); Out.String(TLS.lastError); Out.Ln
    END;
    TLS.CloseNow(state)
  END;
  n := Status(server);
  IF mode = "reject" THEN Check("server saw no exchange", n # 0) ELSE Check("server done", n = 0) END;
  Check("relay done", Status(relay) = 0)
END Live;

PROCEDURE LiveTests;
VAR bundle: ARRAY 256 OF CHAR;
BEGIN
  Kernel.GetConfig("SSL_CERT_FILE", bundle);
  IF bundle # CA THEN
    Out.String("live tests skipped: run as SSL_CERT_FILE="); Out.String(CA); Out.String(" loksh TLSTestAsync.Run"); Out.Ln
  ELSIF ~Certificates() THEN Check("certificates", FALSE)
  ELSE
    Live("async", "localhost", CA, Key);
    Live("blocking", "localhost", CA, Key);
    Live("reject", "127.0.0.1", CA, Key);  (* the certificate names localhost only *)
    Live("reject", "localhost", Other, OtherKey)  (* a certificate not in the bundle *)
  END
END LiveTests;

PROCEDURE Run*;
BEGIN
  checks := 0; fails := 0;
  RecordTests; LiveTests;
  Out.String("TLSTestAsync: "); Out.Int(checks, 0); Out.String(" checks, "); Out.Int(fails, 0); Out.String(" failed"); Out.Ln
END Run;

(** TLSTestAsync.Client host port [blocking]: the resumable (or blocking) handshake with a server, a GET,
  the first bytes of the answer *)
PROCEDURE Client*;
VAR A: Texts.Reader; host, port, mode: ARRAY 256 OF CHAR; fd: Internet.Socket; state: TLS.State;
  result: INTEGER; n, waited, i: LONGINT; data: ARRAY 512 OF CHAR; ok: BOOLEAN;
BEGIN
  Texts.OpenArgs(A);
  IF ~Texts.Arg(A, host) OR ~Texts.Arg(A, port) THEN
    Out.String("usage: TLSTestAsync.Client host port [blocking]   a TLS 1.3 handshake, GET / and the answer's start"); Out.Ln;
    RETURN
  END;
  IF ~Texts.Arg(A, mode) THEN mode := "" END;
  IF ~Internet.Connect(host, port, fd) THEN Out.String("no connection"); Out.Ln; RETURN END;
  TLS.Init(state);
  IF mode = "blocking" THEN ok := TLS.Start(host, fd, state)
  ELSE
    ok := TLS.Begin(host, fd, state); waited := 0;
    REPEAT result := TLS.PollHandshake(state); Sleep(1); INC(waited) UNTIL (result # 0) OR (waited = Wait);
    ok := ok & (result > 0)
  END;
  IF ~ok THEN Out.String("handshake failed: "); Out.String(TLS.lastError); Out.Ln; TLS.CloseNow(state); RETURN END;
  Out.String("verified, key "); Out.String(TLS.keyPin); Out.Ln;
  data := "GET / HTTP/1.0"; n := 14; data[n] := 0DX; data[n + 1] := 0AX; data[n + 2] := 0DX; data[n + 3] := 0AX;
  IF mode = "blocking" THEN
    data[n + 4] := 0X; ok := TLS.WriteAppString(state, data) & TLS.ReadAppMax(state, data, LEN(data) - 1, n)
  ELSE
    waited := 0; i := n + 4;
    REPEAT n := TLS.WriteSome(state, data, 0, i); Sleep(1); INC(waited) UNTIL (n # -2) OR (waited = Wait);
    waited := 0;
    REPEAT n := TLS.ReadSome(state, data, 0, LEN(data) - 1); Sleep(1); INC(waited) UNTIL (n # -2) OR (waited = Wait);
    ok := n > 0
  END;
  IF ok THEN
    i := 0; WHILE i < n DO IF data[i] = 0DX THEN data[i] := " " END; INC(i) END;
    data[n] := 0X; Out.String(data); Out.Ln
  ELSE Out.String("no answer: "); Out.String(TLS.lastError); Out.Ln
  END;
  TLS.CloseNow(state)
END Client;

END TLSTestAsync.
