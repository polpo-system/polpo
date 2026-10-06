MODULE ClockTest;  (** loksh ClockTest.Run: Kernel.U2OTime, O2UTime and GetClock (UTC) on this port *)

IMPORT SYSTEM, Kernel, Linux0, out;

TYPE Timeval = RECORD sec, usec: LONGINT END;

VAR fails, checks: LONGINT;

PROCEDURE Check(what: ARRAY OF CHAR; ok: BOOLEAN);
BEGIN
  INC(checks);
  IF ~ok THEN INC(fails); out.String("ClockTest: failed: "); out.String(what); out.Ln END
END Check;

(* unix time t is the Oberon date d and time tm (the dates from Python's datetime, UTC) *)
PROCEDURE Pair(what: ARRAY OF CHAR; t, d, tm: LONGINT);
VAR c, date, time: LONGINT;
BEGIN
  c := t; Kernel.U2OTime(c, date, time);
  Check(what, (date = d) & (time = tm) & (Kernel.O2UTime(d, tm) = t))
END Pair;

PROCEDURE Run*;
VAR t, c, date, time, n, i, d2, t2: LONGINT; tv: Timeval; ok: BOOLEAN;
BEGIN
  fails := 0; checks := 0;
  Pair("1970-01-01 00:00:00", 0, 35873, 0);
  Pair("2000-02-29 00:00:00", 951782400, 51293, 0);
  Pair("2024-02-29 23:59:59", 1709251199, 63581, 98043);
  Pair("2026-10-07 00:00:00", 1791331200, 64839, 0);
  Pair("2038-01-19 03:14:07", 2147483647, 70707, 13191);
  Pair("1969-12-31 23:59:59", -1, 35743, 98043);
  ok := TRUE; t := 0; n := 0;
  WHILE (t >= 0) & (t < 2147000000) DO  (* about 7600 times from 1970 to 2038 *)
    c := t; Kernel.U2OTime(c, date, time);
    IF Kernel.O2UTime(date, time) # t THEN ok := FALSE END;
    INC(n); t := t + 282589 (* a prime number of seconds, about 3 days *)
  END;
  Check("round trip", ok & (n > 7000));
  i := Linux0.GetTimeOfDay(SYSTEM.ADR(tv), 0); Kernel.GetClock(t2, d2);
  c := tv.sec; Kernel.U2OTime(c, date, time);
  Check("GetClock is UTC", (d2 = date) & (ABS(Kernel.O2UTime(d2, t2) - tv.sec) <= 2));
  out.String("ClockTest: "); out.Int(checks, 0); out.String(" checks, "); out.Int(fails, 0); out.String(" failed"); out.Ln
END Run;

END ClockTest.
