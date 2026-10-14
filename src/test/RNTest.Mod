MODULE RNTest;  (** RNTest.Run: uniform numbers in [0, 1) with mean 1/2, exponential ones with mean 1/mu *)
IMPORT RandomNumbers, out;
PROCEDURE Run*;
CONST n = 20000;
VAR i, fails: LONGINT; x, sum, esum: REAL;
BEGIN
  fails := 0; RandomNumbers.InitSeed(12345); sum := 0; esum := 0; i := 0;
  WHILE i < n DO
    x := RandomNumbers.Uniform();
    IF (x < 0) OR (x >= 1) THEN INC(fails) END;
    sum := sum + x; esum := esum + RandomNumbers.Exp(2.0); INC(i)
  END;
  IF (sum / n < 0.48) OR (sum / n > 0.52) THEN INC(fails); out.String("FAIL mean of Uniform"); out.Ln END;
  IF (esum / n < 0.47) OR (esum / n > 0.53) THEN INC(fails); out.String("FAIL mean of Exp(2)"); out.Ln END;
  out.String("RNTest: "); out.Int(fails, 0); out.String(" failed"); out.Ln
END Run;
END RNTest.
