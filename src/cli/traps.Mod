MODULE traps;  (** the traps of console commands, shown on the terminal *)

(** The shell installs Handler as the trap handler of the kernel (the desktop installs its own,
  System.Trap). After a trap in a command it writes to the standard error what the trap was
  and the procedures that were running, the last one first, each with its pc in the code of
  its module, and the command that finds the statement of the first pc in the source:

    TRAP 7: index out of range
      ZqTrap.Index  pc 32
      ZqTrap.Run  pc 90
      ...
    compiler.Compile /f 32 <the source of ZqTrap> shows the statement (compile it with the
    options of its object)

  The kernel writes the registers and the rest into Kernel.Log as before. *)

IMPORT SYSTEM, Kernel, Linux0;

CONST Max = 16;  (* procedures shown *)

VAR
  first: BOOLEAN;  (* the first procedure of the trace not shown yet *)
  firstMod: ARRAY 32 OF CHAR; firstPC: LONGINT;
  shown: LONGINT;
  busy: BOOLEAN;  (* a trap while showing one *)

PROCEDURE Str(s: ARRAY OF CHAR);
VAR n, r: LONGINT;
BEGIN
  n := 0; WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END;
  IF n > 0 THEN r := Linux0.Write0(2, SYSTEM.ADR(s[0]), n) END
END Str;

PROCEDURE Ln;
VAR s: ARRAY 2 OF CHAR;
BEGIN s[0] := 0AX; s[1] := 0X; Str(s)
END Ln;

PROCEDURE Int(x: LONGINT);
VAR d: ARRAY 12 OF CHAR; s: ARRAY 13 OF CHAR; i, k: LONGINT; neg: BOOLEAN;
BEGIN
  IF x = MIN(LONGINT) THEN Str("-2147483648"); RETURN END;
  neg := x < 0; IF neg THEN x := -x END;
  i := 0; REPEAT d[i] := CHR(x MOD 10 + ORD("0")); x := x DIV 10; INC(i) UNTIL x = 0;
  k := 0; IF neg THEN s[0] := "-"; k := 1 END;
  WHILE i > 0 DO DEC(i); s[k] := d[i]; INC(k) END;
  s[k] := 0X; Str(s)
END Int;

PROCEDURE Hex(x: LONGINT);
VAR s: ARRAY 10 OF CHAR; i, d: LONGINT;
BEGIN
  i := 7;
  WHILE i >= 0 DO
    d := x MOD 16; x := SYSTEM.LSH(x, -4);
    IF d < 10 THEN s[i] := CHR(d + ORD("0")) ELSE s[i] := CHR(d - 10 + ORD("A")) END;
    DEC(i)
  END;
  s[8] := "H"; s[9] := 0X; Str(s)
END Hex;

(* what the trap was. The ROP2 back ends (ARMv7, RISC-V, MIPS, PowerPC) have numbers of their
  own for the checks; signals come as x86 negative codes (-14 a page fault), the ARM signal
  (11 a segmentation fault) or 29 in the ROP2 kernels *)
PROCEDURE Meaning(trap, page: LONGINT);
VAR rop2, done: BOOLEAN;
BEGIN
  rop2 := (Linux0.ARCH # "X86") & (Linux0.ARCH # "ARM"); done := TRUE;
  IF rop2 THEN
    CASE trap OF
      8: Str("value out of range")
    | 14: Str("WITH guard failed")
    | 15: Str("index out of range")
    | 16: Str("CASE without a matching label")
    | 17: Str("function without RETURN")
    | 18: Str("type guard failed")
    | 19: Str("implicit type guard failed")
    ELSE done := FALSE
    END
  ELSE
    CASE trap OF
      1: Str("WITH guard failed")
    | 2: Str("CASE without a matching label")
    | 3: Str("function without RETURN")
    | 4: Str("overflow")
    | 5: Str("implicit type guard failed")
    | 6: Str("type guard failed")
    | 7: Str("index out of range")
    | 8: Str("ASSERT failed")
    | 9: Str("array dimension error")
    | 12: Str("stack overflow")
    | 14: Str("out of memory")
    ELSE done := FALSE
    END
  END;
  IF ~done THEN
    CASE trap OF
      10: Str("division by zero or by a negative number")
    | 13: Str("keyboard interrupt")
    | 113: Str("keyboard interrupt, or HALT or ASSERT (113)")
    | 28, -6: Str("invalid instruction")
    | 11, 29, -14:
        IF (page >= 0) & (page < 4096) THEN Str("NIL reference")
        ELSE Str("memory access fault at "); Hex(page)
        END
    | -13: Str("general protection fault")
    | -4: Str("overflow")
    ELSE
      IF trap = MAX(INTEGER) THEN Str("trace")
      ELSIF trap >= 20 THEN Str("HALT or ASSERT ("); Int(trap); Str(")")
      ELSIF trap < 0 THEN Str("signal "); Int(-trap)
      ELSE Str("trap "); Int(trap)
      END
    END
  END
END Meaning;

PROCEDURE Frame(m: Kernel.Module; pc: LONGINT; VAR name: ARRAY OF CHAR);
VAR i: LONGINT;
BEGIN
  IF (m = NIL) & (pc = 0) THEN  (* the end of the stack *)
  ELSIF shown < Max THEN
    Str("  ");
    IF m = NIL THEN Str("unknown module, pc "); Hex(pc)
    ELSE
      Str(m.name);
      IF name = "$$" THEN Str(" (module body)")
      ELSIF name # "" THEN Str("."); Str(name)
      END;
      Str("  pc "); Int(pc);
      IF first THEN
        i := 0; WHILE (i < LEN(firstMod) - 1) & (m.name[i] # 0X) DO firstMod[i] := m.name[i]; INC(i) END;
        firstMod[i] := 0X; firstPC := pc; first := FALSE
      END
    END;
    Ln
  ELSIF shown = Max THEN Str("  ..."); Ln
  END;
  IF (m # NIL) OR (pc # 0) THEN INC(shown) END
END Frame;

(** The trap handler: trap, the frame (the stack pointer for the ROP2 kernels) and pc of the
  trap, page the address of a memory fault *)
PROCEDURE Handler*(trap, fp, pc, page: LONGINT);
BEGIN
  IF busy THEN Str("TRAP "); Int(trap); Str(" while showing a trap"); Ln; RETURN END;
  busy := TRUE;
  Ln; Str("TRAP "); Int(trap); Str(": "); Meaning(trap, page); Ln;
  IF (trap # 13) & (trap # 113) THEN
    first := TRUE; shown := 0; firstMod := "";
    Kernel.Trace(fp, pc, Frame);
    IF firstMod # "" THEN
      Str("compiler.Compile /f "); Int(firstPC); Str(" <the source of "); Str(firstMod);
      Str("> shows the statement (compile it with the options of its object)"); Ln
    END
  END;
  busy := FALSE
END Handler;

(** Install Handler as the trap handler of the kernel *)
PROCEDURE Install*;
BEGIN Kernel.InstallTrap(Handler)
END Install;

BEGIN
  busy := FALSE
END traps.
