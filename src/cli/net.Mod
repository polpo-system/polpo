MODULE net;  (** minimal network tools over Sockets and DNS *)

(* net.Help                       what the commands do, with examples
   net.Get host port [path]       HTTP/1.0 GET, prints the answer
   net.Send host port text        sends text, prints what comes back
   net.Echo port [count]          a server: echoes count connections (default 1), IPv6 and IPv4
   net.UDP host port text         sends a datagram, prints the answer
   net.Lookup name ...            the addresses of the names, IPv6 and IPv4
   net.Resolve name ...           only the IPv4 addresses (A records)
   net.Resolve6 name ...          only the IPv6 addresses (AAAA records)
   net.Address text ...           IP addresses in normal form (no lookup)
   A host is a name or an IPv4 or IPv6 address; its addresses are tried in turn. *)

IMPORT Texts := texts, Sockets, DNS, out;

CONST MaxAddrs = 8;

PROCEDURE Number(VAR s: ARRAY OF CHAR; VAR n: LONGINT): BOOLEAN;
VAR i: LONGINT;
BEGIN
  n := 0; i := 0;
  IF (s[0] < "0") OR (s[0] > "9") THEN RETURN FALSE END;
  WHILE (s[i] >= "0") & (s[i] <= "9") DO n := n * 10 + ORD(s[i]) - ORD("0"); INC(i) END;
  RETURN s[i] = 0X
END Number;

PROCEDURE Ln(s: ARRAY OF CHAR);
BEGIN out.String(s); out.Ln
END Ln;

(** net.Help -- what the commands do *)
PROCEDURE Help*;
BEGIN
  Ln("net: small network tools (TCP, UDP, DNS), IPv6 and IPv4");
  Ln("  net.Lookup name ...         the addresses of host names");
  Ln("  net.Resolve name ...        only IPv4 (A);  net.Resolve6 name ...  only IPv6 (AAAA)");
  Ln("  net.Address addr ...        an IPv4/IPv6 address in normal form (does not look up names)");
  Ln("  net.Get host port [path]    an HTTP/1.0 GET; prints the whole answer");
  Ln("  net.Send host port text     connects, sends text, prints what comes back");
  Ln("  net.UDP host port text      sends one datagram, prints the answer and who sent it");
  Ln("  net.Echo port [count]       a server: waits on port, sends back what each of count");
  Ln("                              connections sends (default 1)");
  Ln("  A host is a name or an address. Text with blanks goes in quotes.");
  Ln("examples:");
  Ln("  net.Lookup norayr.am");
  Ln("  net.Get norayr.am 80 /");
  Ln("  net.Echo 7007 2      (and in another loksh)  net.Send localhost 7007 hello");
  Ln("  net.Address ::ffff:127.0.0.1  127.0.0.1")
END Help;

PROCEDURE Error(what: ARRAY OF CHAR; res: LONGINT);
BEGIN out.String("net: "); out.String(what); out.String(" failed, error "); out.Int(-res, 0); out.Ln
END Error;

(* print everything s receives until the other side closes *)
PROCEDURE Print(s: Sockets.Socket);
VAR buf: ARRAY 4096 OF CHAR; n, i: LONGINT;
BEGIN
  n := Sockets.Receive(s, buf, LEN(buf));
  WHILE n > 0 DO
    i := 0; WHILE i < n DO IF buf[i] # 0DX THEN out.Char(buf[i]) END; INC(i) END;  (* CR LF: out.Char(0DX) is a line end *)
    n := Sockets.Receive(s, buf, LEN(buf))
  END;
  IF n < 0 THEN Error("receive", n) END
END Print;

PROCEDURE LookupError(VAR name: ARRAY OF CHAR);
BEGIN
  out.String("net: "); out.String(name);
  IF DNS.res = DNS.NotFound THEN out.String(" not found")
  ELSIF DNS.res = DNS.BadName THEN out.String(" is not a host name")
  ELSE out.String(": no answer from the name servers")
  END;
  out.Ln
END LookupError;

(* the host and port arguments: the host's addresses in a[0..n), the host in host *)
PROCEDURE Target(VAR A: Texts.Reader; usage: ARRAY OF CHAR; VAR host: ARRAY OF CHAR; VAR a: ARRAY OF Sockets.Address; VAR n, port: LONGINT): BOOLEAN;
VAR s: ARRAY 256 OF CHAR;
BEGIN
  IF ~Texts.Arg(A, host) OR ~Texts.Arg(A, s) THEN out.String("usage: "); Ln(usage); RETURN FALSE END;
  IF ~Number(s, port) THEN out.String("net: "); out.String(s); Ln(" is not a port number"); RETURN FALSE END;
  DNS.Lookup(host, DNS.Any, a, n);
  IF n = 0 THEN LookupError(host); RETURN FALSE END;
  RETURN TRUE
END Target;

(* a connection to one of a[0..n) *)
PROCEDURE Open(VAR a: ARRAY OF Sockets.Address; n, port: LONGINT): Sockets.Socket;
VAR i: LONGINT; s: Sockets.Socket;
BEGIN
  i := 0; s := NIL;
  WHILE (s = NIL) & (i < n) DO s := Sockets.Connect(a[i], port); INC(i) END;
  IF s = NIL THEN Error("connect", Sockets.res) END;
  RETURN s
END Open;

(** net.Get host port [path] -- HTTP/1.0 GET *)
PROCEDURE Get*;
VAR A: Texts.Reader; a: ARRAY MaxAddrs OF Sockets.Address; n, port, r: LONGINT; path, host, req: ARRAY 512 OF CHAR; s: Sockets.Socket; i, j: LONGINT;
BEGIN
  Texts.OpenArgs(A);
  IF ~Target(A, "net.Get host port [path]  (an HTTP/1.0 GET)", host, a, n, port) THEN RETURN END;
  IF ~Texts.Arg(A, path) THEN path := "/" END;
  s := Open(a, n, port);
  IF s = NIL THEN RETURN END;
  IF Sockets.ParseAddress(host, a[0]) THEN Sockets.AddressToString(a[0], host) END;
  req := "GET "; i := 4; j := 0; WHILE path[j] # 0X DO req[i] := path[j]; INC(i); INC(j) END;

  req[i] := 0X;
  r := Sockets.SendString(s, req); r := Sockets.SendString(s, " HTTP/1.0");
  req[0] := 0DX; req[1] := 0AX; req[2] := 0X;
  r := Sockets.SendString(s, req); r := Sockets.SendString(s, "Host: "); r := Sockets.SendString(s, host);
  r := Sockets.SendString(s, req); r := Sockets.SendString(s, req);
  IF r < 0 THEN Error("send", r) ELSE Print(s) END;
  Sockets.Close(s)
END Get;

(** net.Send host port text -- send text and print what comes back *)
PROCEDURE Send*;
VAR A: Texts.Reader; a: ARRAY MaxAddrs OF Sockets.Address; n, port, r: LONGINT; host: ARRAY 256 OF CHAR; text: ARRAY 1024 OF CHAR; s: Sockets.Socket;
BEGIN
  Texts.OpenArgs(A);
  IF ~Target(A, "net.Send host port text  (connects, sends text, prints the answer)", host, a, n, port) THEN RETURN END;
  IF ~Texts.Arg(A, text) THEN text := "" END;
  s := Open(a, n, port);
  IF s = NIL THEN RETURN END;
  r := Sockets.SendString(s, text);
  IF r < 0 THEN Error("send", r) ELSE Sockets.Shutdown(s, 1); Print(s) END;
  Sockets.Close(s)
END Send;

(** net.Echo port [count] -- echo count connections, then stop *)
PROCEDURE Echo*;
VAR A: Texts.Reader; arg, peer: ARRAY 256 OF CHAR; port, count, pport, n, r: LONGINT;
  l, c: Sockets.Socket; a: Sockets.Address; buf: ARRAY 4096 OF CHAR;
BEGIN
  Texts.OpenArgs(A);
  IF ~Texts.Arg(A, arg) OR ~Number(arg, port) THEN
    Ln("usage: net.Echo port [count]  (a server: waits for count connections on port, default 1,");
    Ln("       and sends back what they send; try net.Send localhost port text from another loksh)"); RETURN
  END;
  IF ~Texts.Arg(A, arg) OR ~Number(arg, count) THEN count := 1 END;
  l := Sockets.Listen(Sockets.Inet6, port, 8);
  IF l = NIL THEN Error("listen", Sockets.res); RETURN END;
  out.String("net: echoing on port "); out.Int(port, 0); out.Ln;
  WHILE count > 0 DO
    c := Sockets.Accept(l, a, pport);
    IF c = NIL THEN Error("accept", l.res); count := 0
    ELSE
      Sockets.AddressToString(a, peer);
      out.String("net: connection from "); out.String(peer); out.String(" port "); out.Int(pport, 0); out.Ln;
      n := Sockets.Receive(c, buf, LEN(buf));
      WHILE n > 0 DO r := Sockets.Send(c, buf, n); n := Sockets.Receive(c, buf, LEN(buf)) END;
      Sockets.Close(c); DEC(count)
    END
  END;
  Sockets.Close(l)
END Echo;

(** net.UDP host port text -- send a datagram (to the host's first address), print the answer and who sent it *)
PROCEDURE UDP*;
VAR A: Texts.Reader; a: ARRAY MaxAddrs OF Sockets.Address; from: Sockets.Address; port, fport, n, i: LONGINT;
  host: ARRAY 256 OF CHAR; text, t: ARRAY 1024 OF CHAR; s: Sockets.Socket;
BEGIN
  Texts.OpenArgs(A);
  IF ~Target(A, "net.UDP host port text  (one datagram, prints the answer)", host, a, n, port) THEN RETURN END;
  IF ~Texts.Arg(A, text) THEN text := "" END;
  s := Sockets.OpenUDP(a[0].family, 0);
  IF s = NIL THEN Error("socket", Sockets.res); RETURN END;
  n := 0; WHILE text[n] # 0X DO INC(n) END;
  n := Sockets.SendTo(s, a[0], port, text, n);
  IF n < 0 THEN Error("send", n)
  ELSE
    n := Sockets.ReceiveFrom(s, text, LEN(text), from, fport);
    IF n < 0 THEN Error("receive", n)
    ELSE
      Sockets.AddressToString(from, t); out.String(t); out.String(" port "); out.Int(fport, 0); out.String(": ");
      i := 0; WHILE i < n DO out.Char(text[i]); INC(i) END; out.Ln
    END
  END;
  Sockets.Close(s)
END UDP;

(* the addresses of family of each name argument *)
PROCEDURE Names(family: INTEGER; usage: ARRAY OF CHAR);
VAR A: Texts.Reader; name, t: ARRAY 256 OF CHAR; a: ARRAY MaxAddrs OF Sockets.Address; n, i, k: LONGINT;
BEGIN
  Texts.OpenArgs(A); k := 0;
  WHILE Texts.Arg(A, name) DO
    INC(k);
    DNS.Lookup(name, family, a, n);
    IF n = 0 THEN LookupError(name)
    ELSE
      out.String(name); out.String(":");
      i := 0; WHILE i < n DO Sockets.AddressToString(a[i], t); out.Char(" "); out.String(t); INC(i) END;
      out.Ln
    END
  END;
  IF k = 0 THEN out.String("usage: "); Ln(usage) END
END Names;

(** net.Lookup name ... -- the IPv6 and IPv4 addresses of each name *)
PROCEDURE Lookup*;
BEGIN Names(DNS.Any, "net.Lookup name ...  (the IPv6 and IPv4 addresses of host names)")
END Lookup;

(** net.Resolve name ... -- the IPv4 addresses of each name *)
PROCEDURE Resolve*;
BEGIN Names(Sockets.Inet4, "net.Resolve name ...  (the IPv4 addresses of host names)")
END Resolve;

(** net.Resolve6 name ... -- the IPv6 addresses of each name *)
PROCEDURE Resolve6*;
BEGIN Names(Sockets.Inet6, "net.Resolve6 name ...  (the IPv6 addresses of host names)")
END Resolve6;

(** net.Address text -- an IPv4 or IPv6 address in normal form (names are not looked up) *)
PROCEDURE Address*;
VAR A: Texts.Reader; arg, t: ARRAY 256 OF CHAR; a: Sockets.Address; k: LONGINT;
BEGIN
  Texts.OpenArgs(A); k := 0;
  WHILE Texts.Arg(A, arg) DO
    INC(k); out.String(arg);
    IF Sockets.ParseAddress(arg, a) THEN Sockets.AddressToString(a, t); out.String(" -> "); out.String(t)
    ELSE out.String(": not an IP address (net.Lookup "); out.String(arg); out.String(" finds the addresses of a name)")
    END;
    out.Ln
  END;
  IF k = 0 THEN Ln("usage: net.Address addr ...  (e.g. 2001:db8:0:0::1 -> 2001:db8::1; no name lookup)") END
END Address;

END net.
