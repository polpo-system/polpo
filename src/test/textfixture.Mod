MODULE textfixture;

IMPORT Files, Objects := objects, Texts := texts;

PROCEDURE Font(name: ARRAY OF CHAR): Objects.Library;
VAR lib: Objects.Library;
BEGIN
  NEW(lib); Objects.OpenLibrary(lib); COPY(name, lib.name);
  RETURN lib
END Font;

PROCEDURE Generate*;
VAR
  T: Texts.Text;
  W: Texts.Writer;
  R: Files.Rider;
  f: Files.File;
  normal, bold, italic: Objects.Library;
BEGIN
  normal := Font("Oberon10.Scn.Fnt");
  bold := Font("Oberon10b.Scn.Fnt");
  italic := Font("Oberon10i.Scn.Fnt");

  NEW(T); Texts.Open(T, ""); Texts.OpenWriter(W);
  Texts.SetFont(W, normal); Texts.WriteString(W, "plain ");
  Texts.SetFont(W, bold); Texts.WriteString(W, "bold");
  Texts.SetFont(W, normal); Texts.WriteString(W, " ");
  Texts.SetFont(W, italic); Texts.WriteString(W, "italic");
  Texts.SetFont(W, normal); Texts.WriteLn(W);

  Texts.SetColor(W, 1); Texts.WriteString(W, "red ");
  Texts.SetColor(W, 2); Texts.WriteString(W, "green ");
  Texts.SetColor(W, 4); Texts.WriteString(W, "blue");
  Texts.SetColor(W, 15); Texts.WriteLn(W);

  Texts.Append(T, W.buf);
  f := Files.New("Styled.Text"); Files.Set(R, f, 0);
  Texts.Store(R, T); Files.Register(f)
END Generate;

END textfixture.
