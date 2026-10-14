MODULE DCS;  (** dcs in the desktop: Gemini and Spartan requests, the answers in viewers *)

(* The commands and options of the console dcs (dcs.Help), on Gemini0; the answer of DCS.Get opens
   a viewer named after the URL: the URL, the status, the meta, then the body as it arrived (CR and
   other control characters escaped). Messages go to the Log. tools/DCS.Tool has commands to click.
   DCS.Get url [input] [/ident who] [/cert file /key file] [/input file] [/output file] [/save]
                       [/pin sha256] [/tofu] [/follow] [/fingerprint] ~
   DCS.Idents ~
   DCS.NewIdent name [mail] [/years n] ~ *)

IMPORT Files, Gemini0, Args := texts, Texts, Oberon, MenuViewers, TextFrames;

CONST
  Menu = "System.Close System.Copy System.Grow Edit.Search Edit.Store";
  MaxInput = 3000;
  PathLen = 1024;

VAR
  W: Texts.Writer;
  url, inputText: ARRAY MaxInput OF CHAR;

PROCEDURE Log(a, b: ARRAY OF CHAR);
BEGIN
  Texts.WriteString(W, "DCS: "); Texts.WriteString(W, a); Texts.WriteString(W, b); Texts.WriteLn(W);
  Texts.Append(Oberon.Log, W.buf)
END Log;

(* a viewer named name with the text T, in the user track *)
PROCEDURE Show(name: ARRAY OF CHAR; T: Texts.Text);
VAR V: MenuViewers.Viewer; X, Y: INTEGER;
BEGIN
  IF Oberon.Par.vwr # NIL THEN Oberon.AllocateUserViewer(Oberon.Par.vwr.X, X, Y)
  ELSE Oberon.AllocateUserViewer(0, X, Y)  (* run without a viewer: the user track *)
  END;
  V := MenuViewers.New(TextFrames.NewMenu(name, Menu), TextFrames.NewText(T, 0), TextFrames.menuH, X, Y)
END Show;

PROCEDURE Person(id: Gemini0.Ident);
BEGIN
  IF id.cn[0] # 0X THEN Texts.WriteString(W, id.cn) END;
  IF id.mail[0] # 0X THEN
    IF id.cn[0] # 0X THEN Texts.Write(W, " ") END;
    Texts.Write(W, "<"); Texts.WriteString(W, id.mail); Texts.Write(W, ">")
  END;
  IF (id.cn[0] = 0X) & (id.mail[0] = 0X) THEN Texts.WriteString(W, "(no subject)") END
END Person;

PROCEDURE Describe(id: Gemini0.Ident);
VAR short: ARRAY 17 OF CHAR; i: LONGINT;
BEGIN
  i := 0; WHILE (i < 16) & (id.fingerprint[i] # 0X) DO short[i] := id.fingerprint[i]; INC(i) END; short[i] := 0X;
  Texts.WriteString(W, "  "); Texts.WriteString(W, short); Texts.WriteString(W, "  "); Person(id);
  IF id.notAfter[0] # 0X THEN Texts.WriteString(W, "  until "); Texts.WriteString(W, id.notAfter) END;
  Texts.WriteLn(W)
END Describe;

(* the body of r into W, as it arrived, CR and control characters escaped *)
PROCEDURE Body(r: Gemini0.Response);
VAR c: Gemini0.Chunk; i: LONGINT; ch: CHAR; hex: ARRAY 17 OF CHAR;
BEGIN
  hex := "0123456789abcdef"; c := r.body;
  WHILE c # NIL DO
    i := 0;
    WHILE i < c.len DO
      ch := c.data[i];
      IF ch = 0AX THEN Texts.WriteLn(W)
      ELSIF (ch >= " ") & (ch # 7FX) OR (ch = 09X) THEN Texts.Write(W, ch)
      ELSIF ch = 0DX THEN Texts.WriteString(W, "\r")
      ELSE Texts.WriteString(W, "\x"); Texts.Write(W, hex[ORD(ch) DIV 16]); Texts.Write(W, hex[ORD(ch) MOD 16])
      END;
      INC(i)
    END;
    c := c.next
  END
END Body;

PROCEDURE ReadInput(VAR name: ARRAY OF CHAR): BOOLEAN;
VAR n: LONGINT; f: Files.File; rd: Files.Rider;
BEGIN
  f := Files.Old(name);
  IF f = NIL THEN RETURN FALSE END;
  n := Files.Length(f); IF n > MaxInput - 1 THEN n := MaxInput - 1 END;
  Files.Set(rd, f, 0); Files.ReadBytes(rd, inputText, n); inputText[n] := 0X;
  RETURN TRUE
END ReadInput;

(** DCS.Get url [input] [options] ~ (see dcs.Help): the answer in a new viewer *)
PROCEDURE Get*;
VAR
  A: Args.Reader; arg, who, cert, key, inputFile, output, dir: ARRAY PathLen OF CHAR; fp: ARRAY 100 OF CHAR;
  name: ARRAY 64 OF CHAR; save, fingerprint, follow, ok, gotURL, gotInput: BOOLEAN; o: Gemini0.Options; r: Gemini0.Response;
  list, id: Gemini0.Ident; i: LONGINT; T: Texts.Text;
BEGIN
  Args.OpenArgs(A);
  who := ""; cert := ""; key := ""; inputFile := ""; output := ""; save := FALSE; fingerprint := FALSE; follow := FALSE;
  gotURL := FALSE; gotInput := FALSE; url := ""; inputText := "";
  o := Gemini0.NewOptions(); o.trust := Gemini0.None;
  WHILE Args.Arg(A, arg) DO
    IF arg = "/ident" THEN IF ~Args.Arg(A, who) THEN gotURL := FALSE END
    ELSIF arg = "/cert" THEN IF ~Args.Arg(A, cert) THEN gotURL := FALSE END
    ELSIF arg = "/key" THEN IF ~Args.Arg(A, key) THEN gotURL := FALSE END
    ELSIF arg = "/input" THEN IF ~Args.Arg(A, inputFile) THEN gotURL := FALSE END
    ELSIF arg = "/output" THEN IF ~Args.Arg(A, output) THEN gotURL := FALSE END
    ELSIF arg = "/pin" THEN IF Args.Arg(A, fp) THEN o.trust := Gemini0.Pin; COPY(fp, o.pin) END
    ELSIF arg = "/save" THEN save := TRUE
    ELSIF arg = "/tofu" THEN o.trust := Gemini0.Tofu
    ELSIF arg = "/follow" THEN follow := TRUE
    ELSIF arg = "/fingerprint" THEN fingerprint := TRUE
    ELSIF ~gotURL THEN COPY(arg, url); gotURL := TRUE
    ELSIF ~gotInput THEN COPY(arg, inputText); gotInput := TRUE
    END
  END;
  IF ~gotURL THEN Log("usage: DCS.Get url [input] [options] ~", ""); RETURN END;
  IF (inputFile # "") & ~ReadInput(inputFile) THEN Log("cannot read ", inputFile); RETURN END;
  IF fingerprint THEN
    IF Gemini0.Fingerprint(url, fp) THEN Log("fingerprint ", fp) ELSE Log("", Gemini0.lastError) END;
    RETURN
  END;
  NEW(T); Texts.Open(T, "");
  IF who # "" THEN
    Gemini0.IdentsDir(dir); list := Gemini0.LoadIdents(dir);
    id := Gemini0.FindIdent(list, who);
    IF id = NIL THEN
      IF Gemini0.nCandidates > 1 THEN
        Texts.WriteString(W, "DCS: "); Texts.WriteString(W, who); Texts.WriteString(W, " matches ");
        Texts.WriteInt(W, Gemini0.nCandidates, 0); Texts.WriteString(W, " identities; name one by its fingerprint:"); Texts.WriteLn(W);
        i := 0; WHILE i < Gemini0.nCandidates DO Describe(Gemini0.candidates[i]); INC(i) END;
        Texts.Append(Oberon.Log, W.buf)
      ELSE Log("no identity matches ", who)
      END;
      RETURN
    END;
    COPY(id.cert, cert); COPY(id.key, key);
    Texts.WriteString(W, "identity: "); Person(id); Texts.WriteLn(W)
  END;
  IF (cert = "") # (key = "") THEN Log("an identity needs both a certificate and a key", ""); RETURN END;
  IF cert # "" THEN
    o.identity := Gemini0.LoadIdentity(cert, key);
    IF o.identity = NIL THEN Log(cert, ": "); Log("", Gemini0.lastError); RETURN END
  END;
  IF save & (output = "") THEN
    Gemini0.NameForURL(url, output);
    IF Gemini0.Exists(output) THEN Log(output, " exists: name it with /output, or move it first"); RETURN END
  END;
  IF follow THEN ok := Gemini0.Fetch(url, inputText, o, r) ELSE ok := Gemini0.Request(url, inputText, o, r) END;
  IF ~ok THEN Log(url, ": "); Log("", Gemini0.lastError); RETURN END;
  Texts.WriteString(W, "url:      "); Texts.WriteString(W, r.url); Texts.WriteLn(W);
  Gemini0.StatusName(r.protocol, r.status, name);
  Texts.WriteString(W, "status:   "); Texts.WriteInt(W, r.status, 0); Texts.WriteString(W, "  "); Texts.WriteString(W, name); Texts.WriteLn(W);
  Texts.WriteString(W, "meta:     "); Texts.Write(W, 22X); Texts.WriteString(W, r.meta); Texts.Write(W, 22X); Texts.WriteLn(W);
  IF (output # "") & (Gemini0.Kind(r) = 2) THEN
    IF ~r.complete THEN Texts.WriteString(W, "error:    the body is incomplete: not saved")
    ELSIF Gemini0.Save(r, output) THEN Texts.WriteString(W, "wrote:    "); Texts.WriteString(W, output); Texts.WriteString(W, "  "); Texts.WriteInt(W, r.length, 0); Texts.WriteString(W, " bytes")
    ELSE Texts.WriteString(W, "error:    cannot write "); Texts.WriteString(W, output)
    END;
    Texts.WriteLn(W)
  ELSIF r.body # NIL THEN
    Texts.WriteLn(W); Body(r);
    IF ~r.complete THEN Texts.WriteLn(W); Texts.WriteString(W, "error:    the body is incomplete (the connection was cut)"); Texts.WriteLn(W) END
  END;
  Texts.Append(T, W.buf);
  Show(r.url, T)
END Get;

(** DCS.Idents: the identities, in a viewer *)
PROCEDURE Idents*;
VAR dir: ARRAY PathLen OF CHAR; id: Gemini0.Ident; T: Texts.Text;
BEGIN
  Gemini0.IdentsDir(dir); id := Gemini0.LoadIdents(dir);
  NEW(T); Texts.Open(T, "");
  IF id = NIL THEN Texts.WriteString(W, "no identities in ") ELSE Texts.WriteString(W, "identities in ") END;
  Texts.WriteString(W, dir); Texts.WriteLn(W); Texts.WriteLn(W);
  WHILE id # NIL DO Describe(id); id := id.next END;
  Texts.WriteLn(W); Texts.WriteString(W, "DCS.NewIdent name mail ~   makes another one"); Texts.WriteLn(W);
  Texts.Append(T, W.buf);
  Show("DCS.Idents", T)
END Idents;

(** DCS.NewIdent name [mail] [/years n] ~: a new identity (a P-256 key, self-signed), in the Log *)
PROCEDURE NewIdent*;
VAR A: Args.Reader; cn, mail, arg, dir: ARRAY PathLen OF CHAR; years, i: LONGINT; id: Gemini0.Ident;
BEGIN
  Args.OpenArgs(A); cn := ""; mail := ""; years := 100;
  WHILE Args.Arg(A, arg) DO
    IF arg = "/years" THEN
      years := 0;
      IF Args.Arg(A, arg) THEN i := 0; WHILE (arg[i] >= "0") & (arg[i] <= "9") DO years := years * 10 + ORD(arg[i]) - ORD("0"); INC(i) END END
    ELSIF cn = "" THEN COPY(arg, cn)
    ELSIF mail = "" THEN COPY(arg, mail)
    END
  END;
  IF (cn = "") OR (years < 1) THEN Log("usage: DCS.NewIdent name [mail] [/years n] ~", ""); RETURN END;
  Gemini0.IdentsDir(dir);
  IF Gemini0.NewIdent(dir, cn, mail, years, id) THEN
    Texts.WriteString(W, "DCS: new identity "); Person(id); Texts.WriteString(W, ", "); Texts.WriteString(W, id.fingerprint);
    Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
  ELSE Log("", Gemini0.lastError)
  END
END NewIdent;

BEGIN
  Texts.OpenWriter(W)
END DCS.
