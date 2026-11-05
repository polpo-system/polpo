MODULE dcs;  (** dcs, the digital command system: a command line Gemini and Spartan client *)

(* dcs, on Gemini0: it prints the answer rather than
   rendering gemtext: the URL, the status with its name, the meta, then the body as it arrived;
   only what a terminal cannot show is escaped (CR as \r, other control characters as \xHH).
   dcs.Get url [input] [options]   one request; input: the query (Gemini) or the data (Spartan)
     /ident who                    log in with an identity of the identities directory
     /cert file /key file          log in with a certificate and key
     /input file                   the input from a file, or from standard input as -
     /output file                  save the body to file instead of printing it
     /save                         save the body to a file named after the URL (never overwrites)
     /pin sha256                   require this server certificate (its SHA-256)
     /tofu                         trust a server on first use ($HOME/.gemini_hosts)
     /follow                       follow redirects
     /fingerprint                  print the SHA-256 of the server certificate and stop
   dcs.Idents                      list the identities
   dcs.NewIdent name [mail] [/years n]   make an identity (a P-256 key, self-signed)
   dcs.Help *)

IMPORT SYSTEM, Linux0, Files, Gemini0, Texts, Out;

CONST
  MaxInput = 3000;  (* a Gemini query is at most 1024 bytes in all *)
  PathLen = 1024;

VAR
  url, inputText: ARRAY MaxInput OF CHAR;

PROCEDURE Label(l: ARRAY OF CHAR);
BEGIN Out.String(l)
END Label;

(* the identity id in a line: name <mail> *)
PROCEDURE Person(id: Gemini0.Ident);
BEGIN
  IF id.cn[0] # 0X THEN Out.String(id.cn) END;
  IF id.mail[0] # 0X THEN IF id.cn[0] # 0X THEN Out.Char(" ") END; Out.Char("<"); Out.String(id.mail); Out.Char(">") END;
  IF (id.cn[0] = 0X) & (id.mail[0] = 0X) THEN Out.String("(no subject)") END
END Person;

PROCEDURE Describe(id: Gemini0.Ident);
VAR short: ARRAY 17 OF CHAR; i: LONGINT;
BEGIN
  i := 0; WHILE (i < 16) & (id.fingerprint[i] # 0X) DO short[i] := id.fingerprint[i]; INC(i) END; short[i] := 0X;
  Out.String("  "); Out.String(short); Out.String("  "); Person(id);
  IF id.notAfter[0] # 0X THEN Out.String("  until "); Out.String(id.notAfter) END;
  Out.Ln
END Describe;

PROCEDURE Error(a, b: ARRAY OF CHAR);
BEGIN Label("error:    "); Out.String(a); Out.String(b); Out.Ln
END Error;

(* the body as it arrived, with CR and other control characters escaped *)
PROCEDURE ShowBody(r: Gemini0.Response);
VAR c: Gemini0.Chunk; seg: ARRAY 1024 OF CHAR; i, n: LONGINT; ch: CHAR; last: CHAR; hex: ARRAY 17 OF CHAR;

  PROCEDURE Flush;
  BEGIN seg[n] := 0X; Out.String(seg); n := 0
  END Flush;

  PROCEDURE Put(x: CHAR);
  BEGIN IF n >= LEN(seg) - 1 THEN Flush END; seg[n] := x; INC(n)
  END Put;

BEGIN
  hex := "0123456789abcdef"; n := 0; last := 0X; c := r.body;
  WHILE c # NIL DO
    i := 0;
    WHILE i < c.len DO
      ch := c.data[i];
      IF (ch >= " ") & (ch # 7FX) OR (ch = 0AX) OR (ch = 09X) THEN Put(ch)
      ELSIF ch = 0DX THEN Put("\"); Put("r")
      ELSE Put("\"); Put("x"); Put(hex[ORD(ch) DIV 16]); Put(hex[ORD(ch) MOD 16])
      END;
      last := ch; INC(i)
    END;
    c := c.next
  END;
  Flush;
  IF last # 0AX THEN Out.Ln END
END ShowBody;

PROCEDURE Head(r: Gemini0.Response);
VAR name: ARRAY 64 OF CHAR;
BEGIN
  Label("url:      "); Out.String(r.url); Out.Ln;
  Gemini0.StatusName(r.protocol, r.status, name);
  Label("status:   "); Out.Int(r.status, 0); Out.String("  "); Out.String(name); Out.Ln;
  Label("meta:     "); Out.Char(22X); Out.String(r.meta); Out.Char(22X); Out.Ln
END Head;

(* the whole of standard input, or of the file name, into inputText *)
PROCEDURE ReadInput(VAR name: ARRAY OF CHAR): BOOLEAN;
VAR n, r: LONGINT; f: Files.File; rd: Files.Rider;
BEGIN
  IF name = "-" THEN  (* standard input, the console *)
    n := 0; r := 1;
    WHILE (r > 0) & (n < MaxInput - 1) DO r := Linux0.Read0(0, SYSTEM.ADR(inputText[n]), MaxInput - 1 - n); IF r > 0 THEN INC(n, r) END END;
    inputText[n] := 0X; RETURN r >= 0
  END;
  f := Files.Old(name);
  IF f = NIL THEN RETURN FALSE END;
  n := Files.Length(f); IF n > MaxInput - 1 THEN n := MaxInput - 1 END;
  Files.Set(rd, f, 0); Files.ReadBytes(rd, inputText, n); inputText[n] := 0X;
  RETURN TRUE
END ReadInput;

PROCEDURE Usage;
BEGIN
  Out.String("usage: dcs.Get url [input] [/ident who] [/cert file /key file] [/input file|-]"); Out.Ln;
  Out.String("         [/output file] [/save] [/pin sha256] [/tofu] [/follow] [/fingerprint]"); Out.Ln;
  Out.String("  dcs.Help tells more"); Out.Ln
END Usage;

(** dcs.Get url [input] [options]: one request (see dcs.Help) *)
PROCEDURE Get*;
VAR
  A: Texts.Reader; arg, who, cert, key, inputFile, output, dir: ARRAY PathLen OF CHAR; fp: ARRAY 100 OF CHAR;
  save, fingerprint, follow, ok, gotURL, gotInput: BOOLEAN; o: Gemini0.Options; r: Gemini0.Response;
  list, id: Gemini0.Ident; i: LONGINT;
BEGIN
  Texts.OpenArgs(A);
  who := ""; cert := ""; key := ""; inputFile := ""; output := ""; save := FALSE; fingerprint := FALSE; follow := FALSE;
  gotURL := FALSE; gotInput := FALSE; url := ""; inputText := "";
  o := Gemini0.NewOptions(); o.trust := Gemini0.None;
  WHILE Texts.Arg(A, arg) DO
    IF arg = "/ident" THEN IF ~Texts.Arg(A, who) THEN Usage; RETURN END
    ELSIF arg = "/cert" THEN IF ~Texts.Arg(A, cert) THEN Usage; RETURN END
    ELSIF arg = "/key" THEN IF ~Texts.Arg(A, key) THEN Usage; RETURN END
    ELSIF arg = "/input" THEN IF ~Texts.Arg(A, inputFile) THEN Usage; RETURN END
    ELSIF arg = "/output" THEN IF ~Texts.Arg(A, output) THEN Usage; RETURN END
    ELSIF arg = "/pin" THEN IF ~Texts.Arg(A, fp) THEN Usage; RETURN END; o.trust := Gemini0.Pin; COPY(fp, o.pin)
    ELSIF arg = "/save" THEN save := TRUE
    ELSIF arg = "/tofu" THEN o.trust := Gemini0.Tofu
    ELSIF arg = "/follow" THEN follow := TRUE
    ELSIF arg = "/fingerprint" THEN fingerprint := TRUE
    ELSIF ~gotURL THEN COPY(arg, url); gotURL := TRUE
    ELSIF ~gotInput THEN COPY(arg, inputText); gotInput := TRUE
    ELSE Usage; RETURN
    END
  END;
  IF ~gotURL THEN Usage; RETURN END;
  IF inputFile # "" THEN
    IF ~ReadInput(inputFile) THEN Error("cannot read ", inputFile); RETURN END
  END;
  IF fingerprint THEN
    IF Gemini0.Fingerprint(url, fp) THEN Out.String(fp); Out.Ln ELSE Error("", Gemini0.lastError) END;
    RETURN
  END;
  (* the identity *)
  IF who # "" THEN
    Gemini0.IdentsDir(dir); list := Gemini0.LoadIdents(dir);
    IF list = NIL THEN Error("no identities in ", dir); RETURN END;
    id := Gemini0.FindIdent(list, who);
    IF id = NIL THEN
      IF Gemini0.nCandidates > 1 THEN
        Label("error:    "); Out.Char(22X); Out.String(who); Out.Char(22X); Out.String(" matches "); Out.Int(Gemini0.nCandidates, 0);
        Out.String(" identities, so it is not clear which one to log in as:"); Out.Ln;
        i := 0; WHILE i < Gemini0.nCandidates DO Describe(Gemini0.candidates[i]); INC(i) END;
        Out.String("          name one of the above by its fingerprint"); Out.Ln
      ELSE Label("error:    "); Out.String("no identity matches "); Out.Char(22X); Out.String(who); Out.Char(22X); Out.Ln
      END;
      RETURN
    END;
    COPY(id.cert, cert); COPY(id.key, key);
    Label("identity: "); Person(id); Out.Ln
  END;
  IF (cert = "") # (key = "") THEN Error("an identity needs both a certificate and a key", ""); RETURN END;
  IF cert # "" THEN
    o.identity := Gemini0.LoadIdentity(cert, key);
    IF o.identity = NIL THEN Error(cert, ": "); Out.String("          "); Out.String(Gemini0.lastError); Out.Ln; RETURN END
  END;
  (* the name to save to *)
  IF save & (output = "") THEN
    Gemini0.NameForURL(url, output);
    IF Gemini0.Exists(output) THEN
      Label("url:      "); Out.String(url); Out.Ln;
      Label("error:    "); Out.String("would save to "); Out.Char(22X); Out.String(output); Out.Char(22X);
      Out.String(", which exists: name it with /output, or move it first"); Out.Ln;
      RETURN
    END
  END;
  IF follow THEN ok := Gemini0.Fetch(url, inputText, o, r) ELSE ok := Gemini0.Request(url, inputText, o, r) END;
  IF ~ok THEN Label("url:      "); Out.String(url); Out.Ln; Error("", Gemini0.lastError); RETURN END;
  Head(r);
  IF (output # "") & (output # "-") & (Gemini0.Kind(r) = 2) THEN
    IF ~r.complete THEN Error("the body is incomplete: not saved", ""); RETURN END;
    IF ~Gemini0.Save(r, output) THEN Error("cannot write ", output); RETURN END;
    Label("wrote:    "); Out.String(output); Out.String("  "); Out.Int(r.length, 0); Out.String(" bytes"); Out.Ln
  ELSIF r.body # NIL THEN
    Out.Ln; ShowBody(r);
    IF ~r.complete THEN Error("the body is incomplete (the connection was cut)", "") END
  END
END Get;

(** dcs.Idents: the identities of the identities directory *)
PROCEDURE Idents*;
VAR dir: ARRAY PathLen OF CHAR; id: Gemini0.Ident;
BEGIN
  Gemini0.IdentsDir(dir); id := Gemini0.LoadIdents(dir);
  IF id = NIL THEN Out.String("no identities in "); Out.String(dir); Out.Ln; RETURN END;
  Out.String("identities in "); Out.String(dir); Out.String(":"); Out.Ln;
  WHILE id # NIL DO Describe(id); id := id.next END
END Idents;

(** dcs.NewIdent name [mail] [/years n]: a new identity, a self-signed certificate for name *)
PROCEDURE NewIdent*;
VAR A: Texts.Reader; cn, mail, arg, dir: ARRAY PathLen OF CHAR; years, i: LONGINT; id: Gemini0.Ident;
BEGIN
  Texts.OpenArgs(A); cn := ""; mail := ""; years := 100;
  WHILE Texts.Arg(A, arg) DO
    IF arg = "/years" THEN
      IF ~Texts.Arg(A, arg) THEN cn := "" ELSE
        years := 0; i := 0; WHILE (arg[i] >= "0") & (arg[i] <= "9") DO years := years * 10 + ORD(arg[i]) - ORD("0"); INC(i) END
      END
    ELSIF cn = "" THEN COPY(arg, cn)
    ELSIF mail = "" THEN COPY(arg, mail)
    END
  END;
  IF (cn = "") OR (years < 1) THEN
    Out.String("usage: dcs.NewIdent name [mail] [/years n]   (100 years if not given)"); Out.Ln; RETURN
  END;
  Gemini0.IdentsDir(dir);
  IF Gemini0.NewIdent(dir, cn, mail, years, id) THEN
    Out.String("identity: "); Person(id); Out.Ln;
    Out.String("  "); Out.String(id.cert); Out.Ln; Out.String("  "); Out.String(id.key); Out.Ln
  ELSE Error("", Gemini0.lastError)
  END
END NewIdent;

PROCEDURE Help*;
VAR dir: ARRAY PathLen OF CHAR;
BEGIN
  Out.String("dcs, the digital command system: a Gemini and Spartan client"); Out.Ln; Out.Ln;
  Out.String("  dcs.Get url [input] [options]   one request; it prints the URL, the status, the meta"); Out.Ln;
  Out.String("      and the body as it arrived (CR and control characters escaped). input is sent as"); Out.Ln;
  Out.String("      the query (Gemini, percent-encoded) or as the data (Spartan)."); Out.Ln;
  Out.String("    /ident who               log in with an identity: a prefix of its fingerprint, its"); Out.Ln;
  Out.String("                             name, its mail, or part of them (it must be one)"); Out.Ln;
  Out.String("    /cert file /key file     log in with a certificate and key (ECDSA P-256 or RSA)"); Out.Ln;
  Out.String("    /input file              the input from a file, or from standard input as -"); Out.Ln;
  Out.String("    /output file             save the body to file (a success only)"); Out.Ln;
  Out.String("    /save                    save it to a file named after the URL; never overwrites"); Out.Ln;
  Out.String("    /pin sha256              require this server certificate"); Out.Ln;
  Out.String("    /tofu                    trust a server on first use ($HOME/.gemini_hosts); without"); Out.Ln;
  Out.String("                             /pin or /tofu a self-signed server is not checked"); Out.Ln;
  Out.String("    /follow                  follow redirects (at most 5)"); Out.Ln;
  Out.String("    /fingerprint             print the SHA-256 of the server certificate and stop"); Out.Ln;
  Out.String("  dcs.Idents                  list the identities"); Out.Ln;
  Out.String("  dcs.NewIdent name [mail] [/years n]   make an identity: a new P-256 key and a"); Out.Ln;
  Out.String("                             self-signed certificate (100 years)"); Out.Ln; Out.Ln;
  Gemini0.IdentsDir(dir);
  Out.String("  Identities are the pairs <fingerprint>.crt and .key in"); Out.Ln;
  Out.String("    "); Out.String(dir); Out.Ln; Out.Ln;
  Out.String("  Examples:"); Out.Ln;
  Out.String("    loksh dcs.Get gemini://geminiprotocol.net/"); Out.Ln;
  Out.String("    loksh dcs.Get gemini://geminiprotocol.net/ /save"); Out.Ln;
  Out.String("    loksh dcs.Get gemini://bbs.geminispace.org/ /ident ada"); Out.Ln;
  Out.String("    loksh dcs.Get gemini://example.org/search stones"); Out.Ln;
  Out.String("    loksh dcs.Get spartan://mozz.us/"); Out.Ln
END Help;

BEGIN
  url := ""; inputText := ""
END dcs.
