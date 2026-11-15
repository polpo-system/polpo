MODULE Platform;  (** the part of voc's Platform that the modules shared with voc use *)

(* The procedures here have the names and parameters of the ones in voc's Platform
  (src/runtime/Platformunix.Mod), so that such modules compile unchanged; procedures are added
  when a shared module needs them. polpo's own modules use Kernel, Linux0 and Files.

  Differences from voc:
  - GetClock gives the time of polpo's clock, UTC; voc gives the local time. As in voc, the year
    in d is the year MOD 100.
  - The handler of SetInterruptHandler is called when Ctrl+C arrives (trap 13 of the kernel);
    when it returns, the program ends as after a trap, with exit status 2 (in voc it goes on where
    it was interrupted). The other traps are shown by traps.Handler.
  - getEnv takes the environment from Kernel.GetConfig, which reads it where the process starts;
    a variable set to "" counts as not set. In loksh, Kernel.Log records each variable looked up,
    with its value.
  - Exit(1) leaves without the termination handlers of the modules: Kernel.Shutdown(1) means a
    normal end, with exit status 0. *)

IMPORT SYSTEM, Kernel, Linux0, traps;

TYPE
  SignalHandler* = PROCEDURE (signal: LONGINT);

VAR
  interrupt: SignalHandler;

(** milliseconds since the program started, MOD 7FFFFFFFH *)
PROCEDURE Time*(): LONGINT;
BEGIN RETURN Kernel.GetTimer() MOD 7FFFFFFFH
END Time;

(** wait ms milliseconds *)
PROCEDURE Delay*(ms: LONGINT);
VAR tv: ARRAY 2 OF LONGINT; r: LONGINT;
BEGIN
  IF ms > 0 THEN
    tv[0] := ms DIV 1000; tv[1] := ms MOD 1000 * 1000;
    r := Linux0.Select0(0, 0, 0, 0, SYSTEM.ADR(tv[0]))
  END
END Delay;

(** seconds and microseconds since 1970 *)
PROCEDURE GetTimeOfDay*(VAR sec, usec: LONGINT);
VAR tv: ARRAY 2 OF LONGINT; r: LONGINT;
BEGIN
  r := Linux0.GetTimeOfDay(SYSTEM.ADR(tv[0]), 0); sec := tv[0]; usec := tv[1]
END GetTimeOfDay;

(** the time and the date in Oberon's form: t = hour*4096 + minute*64 + second,
  d = (year MOD 100)*512 + month*32 + day *)
PROCEDURE GetClock*(VAR t, d: LONGINT);
BEGIN
  Kernel.GetClock(t, d); d := d DIV 512 MOD 100 * 512 + d MOD 512
END GetClock;

(** the value of the environment variable var; FALSE when it is not set or empty *)
PROCEDURE getEnv*(var: ARRAY OF CHAR; VAR val: ARRAY OF CHAR): BOOLEAN;
BEGIN
  Kernel.GetConfig(var, val); RETURN val[0] # 0X
END getEnv;

(** the value of the environment variable var, "" when it is not set *)
PROCEDURE GetEnv*(var: ARRAY OF CHAR; VAR val: ARRAY OF CHAR);
BEGIN
  IF ~getEnv(var, val) THEN val[0] := 0X END
END GetEnv;

PROCEDURE Trap(trap, fp, pc, page: LONGINT);
BEGIN
  IF (trap = 13) & (interrupt # NIL) THEN interrupt(2) ELSE traps.Handler(trap, fp, pc, page) END
END Trap;

(** handler is called with 2 (SIGINT) when Ctrl+C arrives *)
PROCEDURE SetInterruptHandler*(handler: SignalHandler);
BEGIN
  interrupt := handler; Kernel.InstallTrap(Trap)
END SetInterruptHandler;

(** end the program with the exit status code *)
PROCEDURE Exit*(code: LONGINT);
BEGIN
  IF (code = 1) OR (code < 0) THEN Linux0.Exit0(code) ELSE Kernel.Shutdown(code) END
END Exit;

BEGIN
  interrupt := NIL
END Platform.
