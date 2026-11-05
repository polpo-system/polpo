MODULE gemini;  (** Gemini downloads (gemini://, port 1965), on Gemini0 and the TLS 1.3 of src/lib/tls *)

(* gemini.Get url [file]   saves the body in file (default: the last part of the path, index.gmi)
   gemini.Show url         prints the body
   A server verified by a CA (TLSCABundle) is trusted; one with a self-signed certificate is
   trusted on first use, as the Gemini specification recommends: the SHA-256 of its key is kept in
   $HOME/.gemini_hosts (lines "host:port key"), and a later key that differs is refused.
   Redirects (3x) are followed, up to 5; a body is complete only when the server ended with TLS
   close_notify, an incomplete one is not saved. dcs is the client with identities and input. *)

IMPORT Texts, Gemini0, Out;

(* the file name for url: the last part of the path, index.gmi for a directory *)
PROCEDURE DefaultName(VAR url, name: ARRAY OF CHAR);
VAR host, port, path: ARRAY Gemini0.MaxURL OF CHAR; i, j: LONGINT;
BEGIN
  IF ~Gemini0.Split(url, host, port, path) THEN COPY("index.gmi", name); RETURN END;
  i := 0; WHILE (path[i] # 0X) & (path[i] # "?") DO INC(i) END; path[i] := 0X;
  i := 0; WHILE path[i] # 0X DO INC(i) END; WHILE (i > 0) & (path[i - 1] # "/") DO DEC(i) END;
  j := 0; WHILE (path[i] # 0X) & (j < LEN(name) - 1) DO name[j] := path[i]; INC(i); INC(j) END;
  name[j] := 0X; IF j = 0 THEN COPY("index.gmi", name) END
END DefaultName;

(* fetch url, following redirects; to the file name (made from the url if it is "?"), or to out if
   name = "" *)
PROCEDURE Fetch(VAR url: ARRAY OF CHAR; name: ARRAY OF CHAR);
VAR o: Gemini0.Options; r: Gemini0.Response; c: Gemini0.Chunk; i: LONGINT; seg: ARRAY 1025 OF CHAR; n: LONGINT;
BEGIN
  IF Gemini0.Protocol(url) # Gemini0.Gemini THEN Out.String("gemini: gemini:// expected: "); Out.String(url); Out.Ln; RETURN END;
  o := Gemini0.NewOptions();
  IF ~Gemini0.Fetch(url, "", o, r) THEN Out.String("gemini: "); Out.String(Gemini0.lastError); Out.Ln; RETURN END;
  IF r.firstUse THEN Out.String("gemini: trusting the key of the server on first use: "); Out.String(r.keyPin); Out.Ln END;
  IF r.url # url THEN Out.String("gemini: redirected to "); Out.String(r.url); Out.Ln END;
  IF Gemini0.Kind(r) = 2 THEN
    IF name = "" THEN
      c := r.body; n := 0;
      WHILE c # NIL DO
        i := 0;
        WHILE i < c.len DO
          IF c.data[i] # 0DX THEN seg[n] := c.data[i]; INC(n) END;
          IF n = 1024 THEN seg[n] := 0X; Out.String(seg); n := 0 END;
          INC(i)
        END;
        c := c.next
      END;
      seg[n] := 0X; Out.String(seg);
      IF ~r.complete THEN Out.Ln; Out.String("gemini: the body is incomplete (no close_notify)"); Out.Ln END
    ELSE
      IF name = "?" THEN DefaultName(r.url, name) END;
      Out.Int(r.status, 0); Out.Char(" "); Out.String(r.meta); Out.String(", "); Out.Int(r.length, 0); Out.String(" bytes");
      IF ~r.complete THEN Out.String(", incomplete (no close_notify): not saved")
      ELSIF Gemini0.Save(r, name) THEN Out.String(" in "); Out.String(name)
      ELSE Out.String(": "); Out.String(Gemini0.lastError)
      END;
      Out.Ln
    END
  ELSIF Gemini0.Kind(r) = 1 THEN Out.String("gemini: the server asks for input (dcs.Get url input): "); Out.String(r.meta); Out.Ln
  ELSIF Gemini0.Kind(r) = 6 THEN Out.String("gemini: a client certificate is required (dcs.Get url /ident who): "); Out.String(r.meta); Out.Ln
  ELSE Out.Int(r.status, 0); Out.Char(" "); Out.String(r.meta); Out.Ln
  END
END Fetch;

(** gemini.Get url [file] *)
PROCEDURE Get*;
VAR A: Texts.Reader; url, name: ARRAY Gemini0.MaxURL OF CHAR;
BEGIN
  Texts.OpenArgs(A);
  IF ~Texts.Arg(A, url) THEN Out.String("usage: gemini.Get gemini://host/path [file]"); Out.Ln; RETURN END;
  IF ~Texts.Arg(A, name) THEN name := "?" END;  (* a name is made from the url *)
  Fetch(url, name)
END Get;

(** gemini.Show url *)
PROCEDURE Show*;
VAR A: Texts.Reader; url: ARRAY Gemini0.MaxURL OF CHAR;
BEGIN
  Texts.OpenArgs(A);
  IF ~Texts.Arg(A, url) THEN Out.String("usage: gemini.Show gemini://host/path"); Out.Ln; RETURN END;
  Fetch(url, "")
END Show;

END gemini.
