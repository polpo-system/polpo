MODULE PlatformTest;  (* Platform and Args, the interfaces of voc: time, delay, clock, environment, arguments *)

IMPORT Kernel, Platform, Args, Out;

VAR checks, fails: LONGINT;

PROCEDURE Check(what: ARRAY OF CHAR; ok: BOOLEAN);
BEGIN
  INC(checks);
  IF ~ok THEN INC(fails); Out.String("FAIL "); Out.String(what); Out.String(" (case "); Out.Int(checks, 0); Out.String(")"); Out.Ln END
END Check;

PROCEDURE Run*;
VAR t0, t1, t, d, kt, kd, sec, usec, n: LONGINT; s, a: ARRAY 256 OF CHAR; i: INTEGER;
BEGIN
  checks := 0; fails := 0;
  t0 := Platform.Time(); Platform.Delay(200); t1 := Platform.Time();
  Check("Delay(200) waits 200 ms", (t1 - t0 >= 195) & (t1 - t0 < 2000));
  Check("Time counts from the start", (t0 >= 0) & (t0 < 7FFFFFFFH));
  Platform.GetClock(t, d); Kernel.GetClock(kt, kd);
  Check("GetClock: the year MOD 100", (d DIV 512 < 100) & (d DIV 512 = kd DIV 512 MOD 100));
  Check("GetClock: month, day and time as the kernel's", (d MOD 512 = kd MOD 512) & (t DIV 4096 = kt DIV 4096));
  Platform.GetTimeOfDay(sec, usec);
  Check("GetTimeOfDay after 2025", (sec > 1735689600) & (usec >= 0) & (usec < 1000000));
  Check("a variable that is not set", ~Platform.getEnv("ZQ_PLATFORM_NOT_SET", s));
  s := "x"; Platform.GetEnv("ZQ_PLATFORM_NOT_SET", s);
  Check("GetEnv of it: empty", s = "");
  Kernel.GetConfig("PATH", a);
  Check("getEnv as the kernel's", (a = "") OR Platform.getEnv("PATH", s) & (s = a));
  Check("argc", Args.argc = Kernel.NoOfArgs);
  i := 0; n := 0;
  WHILE i < Args.argc DO Args.Get(i, s); Kernel.GetArg(i, a); IF s = a THEN INC(n) END; INC(i) END;
  Check("the arguments as the kernel's", n = Args.argc);
  s := "unchanged"; Args.Get(Args.argc, s);
  Check("an argument past the end leaves val", s = "unchanged");
  Check("Pos of a missing argument: argc", Args.Pos("zq-no-such-argument") = Args.argc);
  Out.String("PlatformTest: "); Out.Int(checks, 0); Out.String(" checks, "); Out.Int(fails, 0); Out.String(" failed"); Out.Ln
END Run;

END PlatformTest.
