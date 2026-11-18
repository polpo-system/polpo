MODULE TLSTestPinned;  (* pinned mutual Ed25519 TLS between this process (TLS13Live.BeginEd25519) and a
  child (TLS13Server.BeginEd25519, PollEd25519): two new identities (TLSEd25519Keys, TLSCertGen,
  TLSIdentity.FromEd25519), each side pinned to the key of the other, "hello" and "world" exchanged;
  a wrong pin is refused by the client and by the server *)

IMPORT TLS := TLS13Live, TLS13Server, TLSIdentity, TLSCertGen, TLSEd25519Keys, TLSBytes, Sockets, Internet,
  Linux0, SYSTEM, Out;

CONST
  Wait = 15000;  (* the most 1 ms pauses of a loop *)

TYPE
  Key = ARRAY 32 OF CHAR;

VAR
  checks, fails: LONGINT;
  serverSeed, serverKey, clientSeed, clientKey: Key;
  serverId, clientId: TLSIdentity.Identity;

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

(* the pin of key; wrong: with its first byte changed *)
PROCEDURE Pin(VAR key: Key; wrong: BOOLEAN; VAR pin: TLSBytes.Buffer);
VAR i: LONGINT;
BEGIN
  TLSBytes.Init(pin); i := 0;
  WHILE i < 32 DO TLSBytes.AppendByte(pin, ORD(key[i])); INC(i) END;
  IF wrong THEN pin.data[0] := CHR((ORD(pin.data[0]) + 1) MOD 256) END
END Pin;

(* a new seed, its public key and an identity with a self-signed certificate for it *)
PROCEDURE NewIdentity(cn: ARRAY OF CHAR; VAR seed, key: Key; VAR id: TLSIdentity.Identity): BOOLEAN;
VAR cert: TLSBytes.Buffer;
BEGIN
  RETURN TLSEd25519Keys.Generate(seed, key) & TLSCertGen.Ed25519SelfSigned(cn, seed, 1, cert)
    & TLSIdentity.FromEd25519(seed, cert, id)
END NewIdentity;

(* the child: one connection, the handshake pinned to the client's key (wrong: a wrong pin; exit 1 when
  it fails), then "hello" in and "world" out; it waits for the client to close *)
PROCEDURE Server(l: Sockets.Socket; wrong: BOOLEAN);
VAR c: Sockets.Socket; peer: Sockets.Address; p, n, waited: LONGINT; pin: TLSBytes.Buffer;
  pending: TLS13Server.Pending; state: TLS.State; result: INTEGER; data: ARRAY 32 OF CHAR;
BEGIN
  c := Sockets.Accept(l, peer, p); IF c = NIL THEN Linux0.Exit0(3) END;
  Pin(clientKey, wrong, pin); TLS.Init(state);
  IF ~TLS13Server.BeginEd25519(Sockets.Release(c), serverId, pin, pending) THEN Linux0.Exit0(4) END;
  waited := 0;
  REPEAT result := TLS13Server.PollEd25519(pending, state); Sleep(1); INC(waited) UNTIL (result # 0) OR (waited = Wait);
  IF result # 1 THEN TLS13Server.ClosePending(pending); Linux0.Exit0(1) END;
  IF ~state.peerAuthenticated THEN Linux0.Exit0(5) END;
  waited := 0;
  REPEAT n := TLS.ReadSome(state, data, 0, LEN(data) - 1); Sleep(1); INC(waited) UNTIL (n # -2) OR (waited = Wait);
  IF n # 5 THEN Linux0.Exit0(6) END;
  data := "world"; waited := 0;
  REPEAT n := TLS.WriteSome(state, data, 0, 5); Sleep(1); INC(waited) UNTIL (n # -2) OR (waited = Wait);
  IF n # 5 THEN Linux0.Exit0(7) END;
  waited := 0;
  REPEAT n := TLS.ReadSome(state, data, 0, LEN(data) - 1); Sleep(1); INC(waited) UNTIL (n # -2) OR (waited = Wait);
  TLS.CloseNow(state); Linux0.Exit0(0)
END Server;

(* one connection to a server child; wrongClient: the client has a wrong pin, wrongServer: the server *)
PROCEDURE Live(wrongClient, wrongServer: BOOLEAN);
VAR l: Sockets.Socket; a: Sockets.Address; port, pid, n, waited: LONGINT; fd: Internet.Socket;
  pin: TLSBytes.Buffer; state: TLS.State; result: INTEGER; ok: BOOLEAN; p: ARRAY 8 OF CHAR; data: ARRAY 32 OF CHAR;
BEGIN
  ok := Sockets.ParseAddress("127.0.0.1", a); l := Sockets.ListenAt(a, 0, 1);
  IF (l = NIL) OR ~Sockets.LocalAddress(l, a, port) THEN Check("listener", FALSE); RETURN END;
  pid := Linux0.Fork0();
  IF pid = 0 THEN Server(l, wrongServer) END;
  Sockets.Close(l); Port(port, p);
  IF ~Internet.Connect("127.0.0.1", p, fd) THEN Check("connect", FALSE); RETURN END;
  Pin(serverKey, wrongClient, pin); TLS.Init(state);
  Check("begin", TLS.BeginEd25519("localhost", fd, clientId, pin, state));
  waited := 0;
  REPEAT result := TLS.PollHandshake(state); Sleep(1); INC(waited) UNTIL (result # 0) OR (waited = Wait);
  IF wrongClient THEN
    Check("the client refuses a wrong server key", (result = -1) & ~state.peerAuthenticated);
    TLS.CloseNow(state);
    Check("the server sees the refusal", Status(pid) = 1)
  ELSIF wrongServer THEN
    IF result = 1 THEN  (* the client is done before the server checks the client's certificate *)
      waited := 0;
      REPEAT n := TLS.ReadSome(state, data, 0, LEN(data) - 1); Sleep(1); INC(waited) UNTIL (n # -2) OR (waited = Wait);
      Check("the client sees the refusal", n < 0)
    ELSE Check("the client sees the refusal", result = -1)
    END;
    TLS.CloseNow(state);
    Check("the server refuses a wrong client key", Status(pid) = 1)
  ELSE
    Check("handshake", (result = 1) & state.peerAuthenticated & state.identitySent);
    IF result # 1 THEN Out.String("  "); Out.String(TLS.lastError); Out.Ln END;
    data := "hello"; waited := 0;
    REPEAT n := TLS.WriteSome(state, data, 0, 5); Sleep(1); INC(waited) UNTIL (n # -2) OR (waited = Wait);
    Check("write", n = 5); waited := 0;
    REPEAT n := TLS.ReadSome(state, data, 0, LEN(data) - 1); Sleep(1); INC(waited) UNTIL (n # -2) OR (waited = Wait);
    Check("read", n = 5);
    IF n >= 0 THEN data[n] := 0X END; Check("answer", data = "world");
    TLS.CloseNow(state);
    Check("server done", Status(pid) = 0)
  END
END Live;

PROCEDURE Run*;
BEGIN
  checks := 0; fails := 0;
  IF NewIdentity("server", serverSeed, serverKey, serverId) & NewIdentity("client", clientSeed, clientKey, clientId) THEN
    Live(FALSE, FALSE); Live(TRUE, FALSE); Live(FALSE, TRUE)
  ELSE Check("identities", FALSE)
  END;
  Out.String("TLSTestPinned: "); Out.Int(checks, 0); Out.String(" checks, "); Out.Int(fails, 0); Out.String(" failed"); Out.Ln
END Run;

END TLSTestPinned.
