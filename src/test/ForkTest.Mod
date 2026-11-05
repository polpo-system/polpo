MODULE ForkTest;  (* fork, execve and waitpid: the child exits 7, then runs /bin/true *)
IMPORT SYSTEM, Linux0, Out;

PROCEDURE Run*;
VAR pid, r, st: LONGINT; path: ARRAY 16 OF CHAR; argv: ARRAY 2 OF LONGINT;
BEGIN
  pid := Linux0.Fork0();
  IF pid = 0 THEN Linux0.Exit0( 7) END;
  st := 0; r := Linux0.Waitpid0( pid, SYSTEM.ADR( st), 0);
  Out.String( "pid "); Out.Int( pid, 0); Out.String( " r "); Out.Int( r, 0); Out.String( " exit status "); Out.Int( st DIV 256, 0); Out.Ln;
  pid := Linux0.Fork0();
  IF pid = 0 THEN
    path := "/bin/false"; argv[ 0] := SYSTEM.ADR( path); argv[ 1] := 0;
    r := Linux0.Execve0( SYSTEM.ADR( path), SYSTEM.ADR( argv), 0);
    Linux0.Exit0( 99)
  END;
  st := 0; r := Linux0.Waitpid0( pid, SYSTEM.ADR( st), 0);
  Out.String( "exec status "); Out.Int( st DIV 256, 0); Out.Ln
END Run;

END ForkTest.
