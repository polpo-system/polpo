MODULE SysClock;  (* the clock for Time, with gettimeofday of Linux0 (polpo; voc uses Platform) *)

IMPORT SYSTEM, Linux0;

TYPE Timeval = RECORD sec, usec: LONGINT END;

PROCEDURE CanGetClock*(): BOOLEAN;
BEGIN RETURN TRUE
END CanGetClock;

PROCEDURE GetTimeOfDay* (VAR sec, usec: LONGINT): LONGINT;
(* PRIVAT.  Don't use this.  Take Time.GetTime instead.
   Equivalent to the C function `gettimeofday'.  The return value is `0' on
   success and `-1' on failure; in the latter case `sec' and `usec' are set to
   zero.  *)
VAR tv: Timeval;
BEGIN
  IF Linux0.GetTimeOfDay(SYSTEM.ADR(tv), 0) = 0 THEN sec := tv.sec; usec := tv.usec; RETURN 0
  ELSE sec := 0; usec := 0; RETURN -1
  END
END GetTimeOfDay;

END SysClock.
