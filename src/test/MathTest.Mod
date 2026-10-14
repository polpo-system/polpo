MODULE MathTest;  (** MathTest.Run: Math and MathL against known values *)

IMPORT Math, MathL, out;

VAR fails: LONGINT;

PROCEDURE Near(what: ARRAY OF CHAR; x, want, tol: LONGREAL);
VAR d: LONGREAL;
BEGIN
  d := x - want; IF d < 0 THEN d := -d END;
  IF want < 0 THEN want := -want END;
  IF want > 1 THEN d := d / want END;  (* relative above 1 *)
  IF d > tol THEN INC(fails); out.String("FAIL "); out.String(what); out.Ln END
END Near;

PROCEDURE Run*;
CONST t = 1.0D-5; tl = 1.0D-10;
BEGIN
  fails := 0;
  Near("sin(0.5)", Math.sin(0.5), 0.479425538604203D0, t);
  Near("sin(-2)", Math.sin(-2.0), -0.909297426825682D0, t);
  Near("cos(1)", Math.cos(1.0), 0.540302305868140D0, t);
  Near("cos(3)", Math.cos(3.0), -0.989992496600445D0, t);
  Near("arctan(1)", Math.arctan(1.0), 0.785398163397448D0, t);
  Near("arctan(-10)", Math.arctan(-10.0), -1.471127674303735D0, t);
  Near("sqrt(2)", Math.sqrt(2.0), 1.414213562373095D0, t);
  Near("sqrt(1E6)", Math.sqrt(1.0E6), 1000.0D0, t);
  Near("ln(10)", Math.ln(10.0), 2.302585092994046D0, t);
  Near("ln(0.25)", Math.ln(0.25), -1.386294361119891D0, t);
  Near("exp(1)", Math.exp(1.0), 2.718281828459045D0, t);
  Near("exp(-3)", Math.exp(-3.0), 0.049787068367864D0, t);
  Near("sinL(0.5)", MathL.sin(0.5D0), 0.479425538604203D0, tl);
  Near("sinL(-2)", MathL.sin(-2.0D0), -0.909297426825682D0, tl);
  Near("cosL(1)", MathL.cos(1.0D0), 0.540302305868140D0, tl);
  Near("cosL(3)", MathL.cos(3.0D0), -0.989992496600445D0, tl);
  Near("arctanL(1)", MathL.arctan(1.0D0), 0.785398163397448D0, tl);
  Near("arctanL(-10)", MathL.arctan(-10.0D0), -1.471127674303735D0, tl);
  Near("sqrtL(2)", MathL.sqrt(2.0D0), 1.414213562373095D0, tl);
  Near("sqrtL(1E6)", MathL.sqrt(1.0D6), 1000.0D0, tl);
  Near("lnL(10)", MathL.ln(10.0D0), 2.302585092994046D0, tl);
  Near("lnL(0.25)", MathL.ln(0.25D0), -1.386294361119891D0, tl);
  Near("expL(1)", MathL.exp(1.0D0), 2.718281828459045D0, tl);
  Near("expL(-3)", MathL.exp(-3.0D0), 0.049787068367864D0, tl);
  out.String("MathTest: "); out.Int(fails, 0); out.String(" failed"); out.Ln
END Run;

END MathTest.
