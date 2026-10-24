MODULE oberon;

IMPORT Kernel, Texts, Oberon0;

PROCEDURE PopulateParams;
VAR W: Texts.Writer; i: INTEGER; arg: ARRAY 256 OF CHAR;
BEGIN
  Texts.OpenWriter(W);
  i := 2;
  WHILE i < Kernel.NoOfArgs DO
    Kernel.GetArg(i, arg);
    Texts.WriteString(W, arg);
    IF i < Kernel.NoOfArgs - 1 THEN Texts.Write(W, " ") END;
    INC(i)
  END;
  Texts.Append(Oberon0.Par.text, W.buf)
END PopulateParams;

BEGIN
  Oberon0.SetOptionChar('-');
  PopulateParams
END oberon.
