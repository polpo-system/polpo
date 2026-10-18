MODULE POPL;  (* RC 14.3.90 / 8.9.93 *)  (* object model 9.2.94 *)
(* low level code generator for PowerPC (32-bit, big-endian) *)
(*
  polpo: made from the RISC-V back end VOPL (Peter Matthias 2015-2017).

  Registers: r1 stack pointer, r31 frame pointer, r3..r6 arguments (r3 also the result), f1..f3
  floating point arguments (f1 the result); r10, r11, r12 and f0 temporaries of the code
  patterns, r12 also of the loader; r0 holds the return address (from LR) in procedures that
  call others, and is no general register; r2 is not used.

  In the code a register number 0 is register r0, except in the conditions (Cond items),
  where 0 stands for the constant zero, as on MIPS and RISC-V.

  Conditions are compared when they are used: a compare into CR0 (cmpw, cmplw, cmpwi, cmplwi,
  fcmpu), then the conditional branch or the value.

  Links: a chain of instructions that wait for an address keeps in each the distance to the
  previous one, minus 1 (-1 ends the chain): in the 14-bit displacement of a conditional branch,
  the 24-bit one of b and bl, and the 16-bit D field of a load, a store or an addi. A global
  variable, a constant or the address of a procedure is reached by two words: the instruction
  with the link in its D field, and the offset; the loader (Linux0.Fixup) makes them
  lis r12, ha(adr); op rt, lo(adr)(r12). A call into another module is bl with the link,
  then three words: lis r12, ha(adr); addi r12, r12, lo(adr); mtctr r12; bctrl.
*)

  IMPORT OPM:=ROPM, OPS:=ROPS, OPT:=ROPT, S := SYSTEM;

  TYPE
    Item* = RECORD
      mode*, mnolev*, descmode*: SHORTINT;  (* mnolev < 0 -> mno = -mnolev *)
      typ*: OPT.Struct;
      reg*, reg2*: LONGINT;  (* LONGINT instead of SHORTINT to avoid truncation during multiplication with constants *)
      offset*: LONGINT;
      Tjmp*, Fjmp*: LONGINT;
      obj*: OPT.Object
    END ;

  CONST
    NEWDATA=TRUE;  (* consts at negative offsets to sb, vars directly before code *)

    pcahead*=0;
    RegSize*=32;  (* integer register size *)
    FPRegDist*=1;
    ZeroTrap=10;

    (* item base modes (=object modes) *)
    Var* = 1; VarPar* = 2; Con* = 3; LProc* = 6; XProc* = 7; CProc* = 9; IProc* = 10; TProc* = 13;
    (* item modes (must not overlap item basemodes,  > 13) *)
    Based* = 14; Cond* = 15; Reg* = 16;

    (* register usage *)
    T0*= 10; T1*= 11; T2*=12;  (* temporary registers; T0 is never a base *)
    FT0* = 32;  (* f0, temporary *)
    ARI*=3; RRI*=3; ARF*=1+32; RRF*=1+32; (* argument reg, Return reg *)
    SP* = 1; FP* = 31; RA* = 0; VirtualFP* = OPM.MaxRegNr + 1;
    ReservedIRegs={0, SP, 2, ARI..ARI+3, T0, T1, T2, FP};

    CallerSavedR = {3..9, 13..18};
    CalleeSavedR = {19..30};
    CallerSavedF = {1..13};
    CalleeSavedF = {14..31};

  TYPE
    RegSet* = RECORD
      r*, f*: SET
    END ;

(* Items:

  the fields mnolev and typ are set for all modes in OPV.
  mnolev is not set for non-allocated constants.

   mode  | reg   reg2  offset  Tjmp  Fjmp
------------------------------------------
 1 Var   |             adr
 2 VarPar|             adr
 3 Con   |             val
         |             adr     len         (for string)
 6 LProc |
 7 XProc |  (* exported or assigned *)
 9 CProc |
10 IProc |
13 TProc | tag         mthno   0/1         (0 = normal / 1 = super call)
14 Based | r           offset              (r may be VirtualFP)
15 Cond  | rs    rt    cond    Tjmp  Fjmp  (rs, rt >= 32: floating point registers)
16 Reg   | r                               ( if r < 32 then general register r else FPA register r - 32 )
                                           (r cannot be VirtualFP)

field descmode is the mode of an open array descriptor, reg2 -> reg, Tjmp -> offset
*)

  TYPE
    Label* = LONGINT;

  VAR
    level*: SHORTINT;
    pc*, resCallArea*: INTEGER;
    InterProcInf*: BOOLEAN;  (* inter-procedural information about register allocation *)
    sb*: LONGINT;
    defaultCalleeUsed*: RegSet;
    dynArrCopied*, LeafProc*: BOOLEAN;
    KNewRec*, KNewSys*, KNewArr*, GlobData*: OPT.Object;

  CONST
    (* structure forms *)
    Undef = 0; Byte* = 1; Bool* = 2; Char* = 3; SInt* = 4; Int* = 5; LInt* = 6;
    Real* = 7; LReal* = 8; Set* = 9; String* = 10; NilTyp* = 11; NoTyp* = 12;
    Pointer* = 13; ProcTyp* = 14; Comp* = 15;
    intSet* = {SInt..LInt}; realSet* = {Real, LReal};

    (* composite structure forms *)
    Basic* = 1; Array* = 2; DynArr* = 3; Record* = 4;

    (* object modes *)
    Fld = 4; Typ = 5; Head = 12;

    (* module visibility of objects *)
    internal = 0; external = 1; externalR = 2;

    (* history of imported objects *)
    inserted = 0; same = 1; pbmodified = 2; pvmodified = 3; removed = 4; inconsistent = 5;

    (* procedure flags (conval^.setval) *)
    hasBody = 1; isRedef = 2; slNeeded* = 3; alreadyCalled (*back-end only *) = 16;

    IMM16 = 10000H;

    (* register usage *)
    TempReg* = 0; VarReg* = 1; FrozenReg* = 2; (* register classes *)

    (* conditions of Cond items and PutBC: EQ, NE, LT, GE, GT, LE, + 8 unsigned; ODD = negated *)
    BEQ*=0; BNE*=1; BLT*=2; BGE*=3; BGT*=4; BLE*=5; BLTU*=10; BGEU*=11; BGTU*=12; BLEU*=13;

    (* PowerPC instructions *)
    ADDI*=38000000H; ADDIS*=3C000000H; MULLI*=1C000000H;
    ORI*=60000000H; ORIS*=64000000H; XORI*=68000000H; XORIS*=6C000000H; ANDI*=70000000H;  (* andi. *)
    CMPWI*=2C000000H; CMPLWI*=28000000H; TWI*=0C000000H;
    LWZ*=80000000H; LBZ*=88000000H; LHZ*=0A0000000H; LHA*=0A8000000H;
    STW*=90000000H; STB*=98000000H; STH*=0B0000000H;
    LFS*=0C0000000H; LFD*=0C8000000H; STFS*=0D0000000H; STFD*=0D8000000H;
    B*=48000000H; BL*=48000001H; BC*=40000000H; BCL4*=429F0005H;  (* bcl 20,31,.+4 *)
    BLR*=4E800020H; BCTR*=4E800420H; BCTRL*=4E800421H;
    MFLR*=7C0802A6H; MTLR*=7C0803A6H; MTCTR*=7C0903A6H; MFCR*=7C000026H;
    SC*=44000002H;
    ADD*=7C000214H; SUBF*=7C000050H; NEG*=7C0000D0H; MULLW*=7C0001D6H; DIVW*=7C0003D6H; DIVWU*=7C000396H;
    AND*=7C000038H; ANDC*=7C000078H; ORR*=7C000378H; XOR*=7C000278H; NOR*=7C0000F8H;
    SLW*=7C000030H; SRW*=7C000430H; SRAW*=7C000630H; SRAWI*=7C000670H;
    EXTSB*=7C000774H; EXTSH*=7C000734H;
    CMPW*=7C000000H; CMPLW*=7C000040H;
    RLWINM*=54000000H; RLWNM*=5C000000H;
    NOP* = 60000000H; (* ori 0, 0, 0 *)
    (* single precision; + 10000000H double *)
    FADD*=0EC00002AH; FSUB*=0EC000028H; FMUL*=0EC000032H; FDIV*=0EC000024H;
    FCMPU*=0FC000000H; FNEG*=0FC000050H; FABS*=0FC000210H; FMR*=0FC000090H; FRSP*=0FC000018H;
    FCTIW*=0FC00001CH; MTFSFI*=0FC00010CH;
    (* pseudo instructions of PutI and PutR *)
    SUB*=1; SLLI*=2; SRLI*=3; SRAI*=4;

    (* restrictions *)
    CodeLength =  32000; (* words *)
    CodeLim = CodeLength - 500;
    MaxEntryCode = 64;
    ConstLength = 16384;  (* strings, reals, type descriptors; conx is an INTEGER *)
    MaxComs = 128;
    MaxExts = 15;
    MaxLittleFrame = 512;

    NoShift = MAX(INTEGER);

  VAR
    locUsedR, calleesUsedR, mayBeUsedR, tempLiveR, permLiveR, frozenR: SET;  (* r IN frozenR => r IN tempLiveR *)
    locUsedF, calleesUsedF, mayBeUsedF, tempLiveF, permLiveF: SET;
    saved: RegSet;
    thisProc: INTEGER;
    NoFP, RegsSaved: BOOLEAN;
    frameSize, callArea, stackExt: LONGINT;
    loadOp, storeOp: ARRAY 16 OF LONGINT;
    conx, adjlx, lacx, shiftx, curshiftx: INTEGER;
    CodeOvF: BOOLEAN;
    code:  ARRAY CodeLength OF LONGINT;
    constant: ARRAY ConstLength OF CHAR;
    adjustLink: ARRAY 1024 OF INTEGER;
    localAccess: ARRAY 4096 OF INTEGER;
    shiftTab: ARRAY 512 OF INTEGER;  (* one for each procedure *)
    nofdesc: INTEGER;
    hostBig: BOOLEAN;  (* the compiler runs on a big-endian machine *)

  PROCEDURE Put*(instr: LONGINT);
  BEGIN code[pc] := instr; INC(pc)
  END Put;

  PROCEDURE Opcode(c: LONGINT): LONGINT;  (* the primary opcode *)
  BEGIN RETURN c DIV 4000000H MOD 64
  END Opcode;

  PROCEDURE GetD(c: LONGINT): LONGINT;  (* the 16-bit D field, sign extended *)
    VAR d: LONGINT;
  BEGIN d := c MOD IMM16;
    IF d >= 8000H THEN DEC(d, IMM16) END;
    RETURN d
  END GetD;

  PROCEDURE SetD(c, d: LONGINT): LONGINT;
  BEGIN
    IF (d < -8000H) OR (d >= 8000H) THEN OPM.err(909) END;
    RETURN c - c MOD IMM16 + d MOD IMM16
  END SetD;

  PROCEDURE GetBD(c: LONGINT): LONGINT;  (* the displacement of bc in words *)
  BEGIN RETURN GetD(c - c MOD 4) DIV 4
  END GetBD;

  PROCEDURE SetBD(c, d: LONGINT): LONGINT;
  BEGIN
    IF (d < -2000H) OR (d >= 2000H) THEN OPM.err(917) END;  (* conditional branch too far *)
    RETURN c - c MOD IMM16 + (d*4) MOD IMM16 + c MOD 4
  END SetBD;

  PROCEDURE GetLI(c: LONGINT): LONGINT;  (* the displacement of b and bl in words *)
    VAR d: LONGINT;
  BEGIN d := c MOD 4000000H DIV 4;
    IF d >= 800000H THEN DEC(d, 1000000H) END;
    RETURN d
  END GetLI;

  PROCEDURE SetLI(c, d: LONGINT): LONGINT;
  BEGIN RETURN c - c MOD 4000000H + (d*4) MOD 4000000H + c MOD 4
  END SetLI;

  PROCEDURE PutD*(op, rt, ra, d: LONGINT);  (* D form: rt, d(ra) or rt := ra op d *)
  BEGIN
    IF (d < -8000H) OR (d >= 8000H) THEN OPM.err(909) END;
    Put(op + ASH(rt, 21) + ASH(ra, 16) + d MOD IMM16)
  END PutD;

  PROCEDURE PutX*(op, a, b, c: LONGINT);  (* the three register fields in their order *)
  BEGIN Put(op + ASH(a, 21) + ASH(b, 16) + ASH(c, 11))
  END PutX;

  PROCEDURE Logical(op: LONGINT): BOOLEAN;  (* X form with the destination second (rA) *)
    VAR xo: LONGINT;
  BEGIN xo := op DIV 2 MOD 400H;
    RETURN (Opcode(op) = 31) & ((xo = 28) OR (xo = 60) OR (xo = 124) OR (xo = 316) OR (xo = 444) OR
      (xo = 24) OR (xo = 536) OR (xo = 792))
  END Logical;

  PROCEDURE PutR*(op, d, a, b: LONGINT);  (* d := a op b; SUB: a - b *)
  BEGIN
    IF op = SUB THEN PutX(SUBF, d, b, a)
    ELSIF Logical(op) THEN PutX(op, a, d, b)
    ELSE PutX(op, d, a, b)
    END
  END PutR;

  PROCEDURE PutI*(op, d, a, imm: LONGINT);  (* d := a op imm *)
  BEGIN
    IF op = SLLI THEN Put(RLWINM + ASH(a, 21) + ASH(d, 16) + ASH(imm MOD 32, 11) + ASH(31 - imm MOD 32, 1))
    ELSIF op = SRLI THEN Put(RLWINM + ASH(a, 21) + ASH(d, 16) + ASH((32 - imm) MOD 32, 11) + ASH(imm MOD 32, 6) + ASH(31, 1))
    ELSIF op = SRAI THEN Put(SRAWI + ASH(a, 21) + ASH(d, 16) + ASH(imm MOD 32, 11))
    ELSIF (op = ORI) OR (op = XORI) OR (op = ANDI) OR (op = ORIS) OR (op = XORIS) THEN
      IF (imm < 0) OR (imm >= IMM16) THEN OPM.err(909) END;
      Put(op + ASH(a, 21) + ASH(d, 16) + imm MOD IMM16)
    ELSE PutD(op, d, a, imm)
    END
  END PutI;

  PROCEDURE PutF*(op, ft, fa, fb: LONGINT);  (* floating point, A or X form; register numbers MOD 32 *)
  BEGIN
    IF op MOD 40H = 32H THEN Put(op + ASH(ft, 21) + ASH(fa, 16) + ASH(fb, 6))  (* fmul: frc *)
    ELSE Put(op + ASH(ft, 21) + ASH(fa, 16) + ASH(fb, 11))
    END
  END PutF;

  PROCEDURE PutTrap*( nr: LONGINT);  (* twi 31, r0, nr: always *)
  BEGIN Put(TWI + ASH(31, 21) + nr MOD IMM16)
  END PutTrap;

  PROCEDURE CondBits(c: LONGINT; VAR bo, bi: LONGINT);
  BEGIN
    CASE c DIV 2 MOD 4 OF 0: bi := 2 | 1: bi := 0 | 2: bi := 1 END;
    IF ODD(c) THEN bo := 4 ELSE bo := 12 END
  END CondBits;

  PROCEDURE PutBC*(c, disp: LONGINT);  (* branch on condition c of CR0, disp in words *)
    VAR bo, bi: LONGINT;
  BEGIN CondBits(c, bo, bi);
    Put(SetBD(BC + ASH(bo, 21) + ASH(bi, 16), disp))
  END PutBC;

  PROCEDURE PutCmp*(unsigned: BOOLEAN; rs, rt: LONGINT);
  BEGIN
    IF unsigned THEN PutX(CMPLW, 0, rs, rt) ELSE PutX(CMPW, 0, rs, rt) END
  END PutCmp;

  PROCEDURE PutCmpI*(unsigned: BOOLEAN; rs, imm: LONGINT);
  BEGIN
    IF unsigned THEN
      IF (imm < 0) OR (imm >= IMM16) THEN OPM.err(909) END;
      Put(CMPLWI + ASH(rs, 16) + imm MOD IMM16)
    ELSE PutD(CMPWI, 0, rs, imm)
    END
  END PutCmpI;

  PROCEDURE PutTrapUnless*(c, nr: LONGINT);  (* trap nr unless the condition c holds *)
  BEGIN PutBC(c, 2); PutTrap(nr)
  END PutTrapUnless;

  PROCEDURE AllocConst(cadr, len: LONGINT; VAR adr: LONGINT; align: SHORTINT);
  BEGIN
    WHILE ((conx-len) MOD align) #0 DO DEC(conx); constant[conx] := 0X; END ;
    IF conx < 255 THEN OPM.err(230); conx := LEN(constant)-1 END ;
    DEC(conx, SHORT(len));
    adr := conx-LEN(constant)+sb;  (* sb is negative *)
    S.MOVE(cadr, S.ADR(constant[conx]), len);
  END AllocConst;

  PROCEDURE AllocString*(VAR s: ARRAY OF CHAR; len: LONGINT; VAR adr: LONGINT);
  BEGIN AllocConst(S.ADR(s[0]), SHORT(len), adr, 4)
  END AllocString;

  (* n bytes at adr in the byte order of the target, big-endian: reversed on a little-endian host *)
  PROCEDURE AllocNumber(adr, n: LONGINT; VAR cadr: LONGINT);
  VAR b: ARRAY 8 OF CHAR; i: LONGINT;
  BEGIN
    IF ~hostBig THEN
      i := 0; WHILE i < n DO S.GET(adr + n - 1 - i, b[i]); INC(i) END;
      AllocConst(S.ADR(b[0]), n, cadr, SHORT(SHORT(n)))
    ELSE AllocConst(adr, n, cadr, SHORT(SHORT(n)))
    END
  END AllocNumber;

  PROCEDURE AllocReal*(r: REAL; VAR adr: LONGINT);
  BEGIN AllocNumber(S.ADR(r), 4, adr)
  END AllocReal;

  PROCEDURE AllocLReal*(r: LONGREAL; VAR adr: LONGINT);
  BEGIN AllocNumber(S.ADR(r), 8, adr)
  END AllocLReal;

  PROCEDURE AllocTypDesc*(typ: OPT.Struct);   (* typ^.comp = Record *)
    VAR obj: OPT.Object; name: OPS.Name;
  BEGIN
    IF (typ^.strobj = NIL) OR (typ^.strobj^.mnolev > 0) THEN OPT.IdFPrint(typ);  (* before deleting name *)
      (* insert a global object of that type, in order to find it when in OutCode *)
      name := "@"; OPT.Insert(name, obj); obj^.name := "";  (* avoid err 1 *)
      obj^.mode := Typ; obj^.typ := typ; typ^.strobj := obj  (* obj.linkadr needed, obj^.typ^.strobj = obj else alias ! *)
    END ;
    IF typ^.extlev > MaxExts THEN OPM.err(233) END
  END AllocTypDesc;

  PROCEDURE BegStat*;  (* general-purpose procedure which is called before each statement *)
  BEGIN
    IF pc > CodeLim THEN
      IF ~CodeOvF THEN OPM.err(210); CodeOvF := TRUE END ;
      pc := 0
    END
  END BegStat;

  PROCEDURE EndStat*;  (* general-purpose procedure which is called after each statement *)
  BEGIN
    tempLiveR := {}; tempLiveF := {}; frozenR := {}
    (* frozenR used for open array bases, see OPC.DeRef, and for common design bases, see OPC.CommonDesign *)
  END EndStat;

  PROCEDURE Invert*(VAR cond: LONGINT);
  BEGIN
    IF ODD(cond) THEN DEC(cond) ELSE INC(cond) END
  END Invert;

  PROCEDURE Swapped(c: LONGINT): LONGINT;  (* the condition with the operands exchanged *)
  BEGIN
    IF c MOD 8 DIV 2 = 1 THEN RETURN c + 2  (* LT, GE -> GT, LE *)
    ELSIF c MOD 8 DIV 2 = 2 THEN RETURN c - 2
    ELSE RETURN c
    END
  END Swapped;

  PROCEDURE Fixup*(L: Label);  (* enter pc at L, pc > L *)
    VAR c: LONGINT;
  BEGIN
    c:=code[L];
    IF Opcode(c) = 18 THEN code[L] := SetLI(c, pc - L)
    ELSE OPM.err(901)
    END
  END Fixup;

  PROCEDURE FixLink*(L: Label);
    VAR L1: Label; c: LONGINT;
  BEGIN
    IF ~CodeOvF & (L # 0) THEN
      REPEAT
        L1 := L; c := code[L1];
        IF Opcode(c) = 16 THEN L := L1 + GetBD(c) + 1; code[L1] := SetBD(c, pc - L1)
        ELSIF Opcode(c) = 18 THEN L := L1 + GetLI(c) + 1; code[L1] := SetLI(c, pc - L1)
        ELSE OPM.err(918); OPM.LogWHex(c); L := L1
        END;
      UNTIL L = L1
    END
  END FixLink;

  PROCEDURE FixLinkWith*(L, val: Label);
    VAR L1: Label; c: LONGINT;
  BEGIN
    IF ~CodeOvF & (L # 0) THEN
      REPEAT
        L1 := L; c := code[L1];
        IF Opcode(c) = 16 THEN L := L1 + GetBD(c) + 1; code[L1] := SetBD(c, val - L1 - 1)
        ELSIF Opcode(c) = 18 THEN L := L1 + GetLI(c) + 1; code[L1] := SetLI(c, val - L1 - 1)
        ELSE OPM.err(903); L := L1
        END
      UNTIL L = L1
    END
  END FixLinkWith;

  PROCEDURE MergedLinks*(L0, L1: Label): Label;
    VAR L2, L3: Label; c: LONGINT;
  BEGIN
    IF ~CodeOvF & (L0 # 0) THEN L2 := L0;
      LOOP
        c := code[L2];
        IF Opcode(c) = 16 THEN L3 := L2 + GetBD(c) + 1
        ELSIF Opcode(c) = 18 THEN L3 := L2 + GetLI(c) + 1
        ELSE OPM.err(904); OPM.LogWHex(c); EXIT
        END;
        IF L3 = L2 THEN EXIT END ;
        L2 := L3
      END;
      IF Opcode(c) = 16 THEN code[L2] := SetBD(c, L1 - 1 - L2) ELSE code[L2] := SetLI(c, L1 - 1 - L2) END;
      RETURN L0
    ELSE RETURN L1
    END
  END MergedLinks;

  PROCEDURE FixBranches(proc: OPT.Object);  (* forward calls; addresses of proc are left to the loader *)
    VAR L, L1, keep: Label; c: LONGINT;
  BEGIN
    L := proc.linkadr; keep := 0;
    IF ~CodeOvF & (L # 0) THEN
      IF proc.x < shiftx THEN DEC(L, LONG(shiftTab[proc.x])); proc.x := NoShift END ;
      REPEAT
        L1 := L; c := code[L1];
        IF Opcode(c) = 18 THEN  (* forward declared procedure *)
          L := L1 + GetLI(c) + 1; code[L1] := SetLI(c, pc - L1)
        ELSIF Opcode(c) = 14 THEN  (* addi, the address of proc: a chain for the loader *)
          L := L1 + GetD(c) + 1;
          IF keep = 0 THEN code[L1] := SetD(c, -1) ELSE code[L1] := SetD(c, keep - L1 - 1) END;
          keep := L1
        ELSE OPM.err(905); OPM.LogWHex( c); L := L1
        END;
      UNTIL L = L1;
    END ;
    proc^.linkadr := keep; proc.x := NoShift
  END FixBranches;

  PROCEDURE PickR(pool: SET; VAR r: LONGINT): BOOLEAN;  (* TRUE if found *)
    VAR i: LONGINT;
  BEGIN
    pool := pool - ReservedIRegs - tempLiveR - permLiveR;
    IF pool = {} THEN RETURN FALSE END ;
    i := 3;
    WHILE ~(i IN pool) DO INC(i) END ;
    r := i; RETURN TRUE
  END PickR;

  PROCEDURE GetR*(class: SHORTINT; VAR rt: LONGINT);  (* class IN {TempReg, FrozenReg, VarReg} *)
  BEGIN
    ASSERT((rt # VirtualFP) & ((rt # SP) OR (class = TempReg)));
    IF (rt < 0) OR (rt > 31) THEN
      IF class IN {TempReg, FrozenReg} THEN
        IF PickR(locUsedR*CalleeSavedR, rt) OR
          InterProcInf & (~LeafProc & (
            PickR(mayBeUsedR*CallerSavedR, rt) OR PickR(CallerSavedR, rt) OR PickR(mayBeUsedR, rt))) OR
          PickR(CallerSavedR, rt) OR PickR(CalleeSavedR, rt)
        THEN
          INCL(locUsedR, rt); INCL(tempLiveR, rt);
          IF class = FrozenReg THEN INCL(frozenR, rt) END
        ELSE OPM.err(215); rt := 3
        END
      ELSE (* class = VarReg *)
        IF LeafProc & (PickR(CallerSavedR, rt) OR PickR(CalleeSavedR, rt)
          ) OR ~LeafProc & (
            InterProcInf & (
              PickR(mayBeUsedR*CalleeSavedR, rt) OR PickR(CalleeSavedR, rt) OR PickR(mayBeUsedR, rt)) OR
            PickR(CalleeSavedR, rt) OR PickR(CallerSavedR, rt)
          )
        THEN INCL(locUsedR, rt); INCL(permLiveR, rt)
        ELSE OPM.err(215); rt := 3
        END
      END
    ELSE
      IF class = TempReg THEN INCL(tempLiveR, rt)  (* param regs *)
      ELSIF class = FrozenReg THEN INCL(tempLiveR, rt); INCL(frozenR, rt)  (* freeze function *)
      ELSE INCL(permLiveR, rt)  (* param var regs *)
      END
    END
  END GetR;

  PROCEDURE ReleaseR*(r: LONGINT);
  BEGIN
    IF (r >= 0) & (r < 32) & ~(r IN frozenR) THEN EXCL(tempLiveR, r) END
  END ReleaseR;

  PROCEDURE ThawR*(class: SHORTINT; r: LONGINT);  (* class IN {FrozenReg, VarReg} *)
  BEGIN
    IF class = FrozenReg THEN EXCL(frozenR, r); EXCL(tempLiveR, r)
    ELSE EXCL(permLiveR, r)
    END
  END ThawR;

  PROCEDURE PickF(pool: SET; VAR f: LONGINT): BOOLEAN;  (* TRUE if found *)
    VAR i: LONGINT;
  BEGIN
    pool := pool - tempLiveF - permLiveF;
    IF pool = {} THEN RETURN FALSE END ;
    i := 0;
    WHILE (i # 32) & ~(i IN pool) DO INC(i, FPRegDist) END ;
    f := i; RETURN i # 32
  END PickF;

  PROCEDURE GetF*(class: SHORTINT; VAR ft: LONGINT);  (* class IN {TempReg, VarReg} *)
  BEGIN
    ASSERT(ft # VirtualFP);
    IF ft < 32 THEN
      IF class = TempReg THEN
        IF PickF(locUsedF*CalleeSavedF, ft) OR
          InterProcInf & (~LeafProc & (
            PickF(mayBeUsedF*CallerSavedF, ft) OR PickF(CallerSavedF, ft) OR PickF(mayBeUsedF, ft))) OR
          PickF(CallerSavedF, ft) OR PickF(CalleeSavedF, ft)
        THEN
          INCL(locUsedF, ft); INCL(tempLiveF, ft); INC(ft, 32)
        ELSE OPM.err(216); ft := 33
        END
      ELSE (* class = VarReg *)
        IF LeafProc & (PickF(CallerSavedF, ft) OR PickF(CalleeSavedF, ft)
          ) OR ~LeafProc & (
            InterProcInf & (
              PickF(mayBeUsedF*CalleeSavedF, ft) OR PickF(CalleeSavedF, ft) OR PickF(mayBeUsedF, ft)) OR
            PickF(CalleeSavedF, ft) OR PickF(CallerSavedF, ft)
          )
        THEN INCL(locUsedF, ft); INCL(permLiveF, ft); INC(ft, 32)
        ELSE OPM.err(216); ft := 33
        END
      END
    ELSE
      IF class = TempReg THEN INCL(tempLiveF, ft - 32)  (* param regs *)
      ELSE INCL(permLiveF, ft - 32)  (* param var regs *)
      END
    END
  END GetF;

  PROCEDURE ReleaseF*(f: LONGINT);
  BEGIN EXCL(tempLiveF, f - 32)
  END ReleaseF;

  PROCEDURE Release(r: LONGINT);  (* a general or floating point register *)
  BEGIN
    IF r >= 32 THEN ReleaseF(r) ELSE ReleaseR(r) END
  END Release;

  (* Compare the operands of the Cond item x into CR0 and return its condition. *)
  PROCEDURE Compare(VAR x: Item): LONGINT;
    VAR rs, rt, c: LONGINT;
  BEGIN
    rs := x.reg; rt := x.reg2; c := x.offset;
    IF rs >= 32 THEN PutX(FCMPU, 0, rs MOD 32, rt MOD 32)
    ELSE
      IF (rs = 0) & (rt = 0) THEN rs := SP; rt := SP  (* a constant condition: 0 = 0 *)
      ELSIF rs = 0 THEN rs := rt; rt := 0; c := Swapped(c)
      END;
      IF rt = 0 THEN PutCmpI(c >= 8, rs, 0) ELSE PutCmp(c >= 8, rs, rt) END
    END;
    RETURN c
  END Compare;

  PROCEDURE PutCond*(VAR x: Item; loc: Label; locok: BOOLEAN);
    VAR c, disp: LONGINT;
  BEGIN
    c := Compare(x);
    IF loc = 0 THEN (* end of chain *) disp := -1
    ELSIF ~locok THEN disp := loc - pc - 1
    ELSE disp := loc
    END;
    IF disp < -2000H THEN  (* far backwards *)
      Invert(c); PutBC(c, 2); Put(SetLI(B, disp - 1))
    ELSE PutBC(c, disp)
    END;
    Release(x.reg); Release(x.reg2)
  END PutCond;

  PROCEDURE SetLink*(VAR link: LONGINT);
  BEGIN
    IF link = 0 THEN link := -1;
    ELSE
      IF link < thisProc + MaxEntryCode THEN adjustLink[adjlx] := pc; INC(adjlx) END;
      link := (link - pc -1);
    END
  END SetLink;

  PROCEDURE Link*(obj: OPT.Object): LONGINT;
    VAR link: LONGINT;
  BEGIN
    IF (obj.linkadr # 0) & (obj.x < shiftx) THEN DEC(obj.linkadr, LONG(shiftTab[obj.x])) END ;
    obj.x := curshiftx; link := obj.linkadr; obj.linkadr := pc; SetLink(link);
    RETURN link
  END Link;

  (* the two words of an access to obj (global variable, constant, procedure): see the top *)
  PROCEDURE PutLinked(op, rt: LONGINT; obj: OPT.Object; offset: LONGINT);
  BEGIN Put(op + ASH(rt, 21) + Link(obj) MOD IMM16); Put(offset)
  END PutLinked;

  PROCEDURE CallExt*(obj: OPT.Object);  (* call into another module (or the Kernel runtime), fixed by the loader *)
  BEGIN Put(SetLI(BL, Link(obj))); Put(NOP); Put(NOP); Put(NOP)
  END CallExt;

  PROCEDURE ^Load*(VAR x: Item; rt: LONGINT);  (* returned x.mode = Reg, x.typ must be defined *)

  PROCEDURE LoadFP*(lev: SHORTINT; rt: LONGINT): LONGINT;
    VAR sl: Item;
  BEGIN
    lev := level-lev;
    IF lev = 0 THEN (* local *)
      IF NoFP THEN RETURN VirtualFP ELSE RETURN FP END
    ELSE (* intermediate *)
      sl.mode := Var; sl.mnolev := level; sl.typ := OPT.linttyp;
      sl.offset := 64; Load(sl, rt);
      WHILE lev > 1 DO DEC(lev);
        sl.mode := Based; sl.offset := 0; Load(sl, rt)
      END ;
      RETURN sl.reg
    END
  END LoadFP;

  PROCEDURE Base*(VAR x: Item; rt: LONGINT);    (* x.mode IN {Var, VarPar, Based}, returned x.mode = Based *)
    VAR lev: SHORTINT; typ: OPT.Struct; offset: LONGINT;
  BEGIN
    IF rt >= 32 THEN rt := -1 END ;
    lev := x.mnolev;
    CASE x.mode OF
      Var:
        IF (x.offset > 0) & (x.offset < 64) THEN OPM.err(127) END ;
        IF x.offset >= 64 THEN DEC(x.offset, 64) END ;
        IF lev <= 0 THEN (* global or extern, Var only and string const*)
          GetR(TempReg, rt);
          PutLinked(ADDI, rt, x.obj, x.offset);
          x.offset := 0; x.reg := rt
        ELSE x.reg := LoadFP(lev, rt)
        END
    | VarPar:
        offset := x.offset;
        IF (offset >= 0) & (offset < 64) THEN x.reg := offset; x.offset := 0
        ELSE
          IF offset >= 64 THEN DEC(x.offset, 64) END ;
          typ := x.typ; x.typ := OPT.linttyp;
          x.reg := LoadFP(lev, rt); x.mode := Based; Load(x, rt); x.offset := 0; x.typ := typ
        END
    | Based:
        (* ok *)
    ELSE OPM.err(127); x.reg := 0; x.offset := 0
    END ;
    x.mode := Based
  END Base;

  PROCEDURE AddUpperToBase(VAR x: Item);  (* x.mode = Based, returned x.offset is sign extended 16 bit *)
    (* the next instruction MUST use returned x.reg as base *)
    VAR offset, base, rt: LONGINT;
  BEGIN
    ASSERT(x.mode = Based, 32);
    base := x.reg;
    IF base = VirtualFP THEN INC(x.offset, stackExt) END ;
    offset := x.offset;
    IF (offset >= -8000H) & (offset < 8000H) & ((base # VirtualFP) OR (offset >= -7000H) & (offset < 7000H)) THEN
      (* VirtualFP: room for the frame size added later *)
      IF base = VirtualFP THEN base := SP; localAccess[lacx] := pc; INC(lacx) END;
    ELSE ASSERT(base # VirtualFP, 33);
      rt := -1; GetR(TempReg, rt); ReleaseR(base);
      PutD(ADDIS, rt, base, ASH(offset + 8000H, -16));
      base := rt; x.offset := GetD(offset)
    END ;
    x.reg := base
  END AddUpperToBase;

  PROCEDURE LoadAddr*(VAR x: Item; rt: LONGINT);  (* returned x.mode = Reg, x.reg # VirtualFP *)
    VAR b: LONGINT;
  BEGIN
    Base(x, rt);
    IF (x.offset # 0) OR (x.reg = VirtualFP) THEN
      AddUpperToBase(x); b := x.reg; ReleaseR(b);
      GetR(TempReg, rt);
      PutD(ADDI, rt, b, x.offset);  (* b = 0: absolute *)
      x.reg := rt
    END ;
    x.mode := Reg; x.typ := OPT.linttyp
  END LoadAddr;

  (* rt := the value of the condition in CR0 (c), 0 or 1 *)
  PROCEDURE CondValue(c, rt: LONGINT);
    VAR bo, bi: LONGINT;
  BEGIN CondBits(c, bo, bi);
    Put(MFCR + ASH(rt, 21));
    Put(RLWINM + ASH(rt, 21) + ASH(rt, 16) + ASH(bi + 1, 11) + ASH(31, 6) + ASH(31, 1));
    IF ODD(c) THEN PutI(XORI, rt, rt, 1) END
  END CondValue;

  PROCEDURE Load*(VAR x: Item; rt: LONGINT);  (* returned x.mode = Reg, x.typ must be defined if not Reg*)
    VAR val, lower, c: LONGINT; f: SHORTINT;
  BEGIN
    CASE x.mode OF
      Var:
        f := x.typ^.form; lower := x.offset;
        IF (lower >= 0) & (lower < 64) THEN x.mode := Reg; x.reg := lower
        ELSIF x.mnolev <= 0 THEN (* global or extern *)
          IF lower >= 64 THEN DEC(x.offset, 64) END ;
          IF f IN realSet THEN GetF(TempReg, rt) ELSE GetR(TempReg, rt) END;
          PutLinked(loadOp[f], rt MOD 32, x.obj, x.offset);
          IF f = SInt THEN PutX(EXTSB, rt, rt, 0) END;
          x.mode := Reg; x.reg := rt;
        ELSE (* local or intermediate *)
          Base(x, rt); Load(x, rt);
        END
    | VarPar:
        Base(x, rt); Load(x, rt)
    | Con:
        val := x.offset;
        GetR(TempReg, rt);
        IF (val >= -8000H) & (val < 8000H) THEN PutD(ADDI, rt, 0, val)
        ELSE PutD(ADDIS, rt, 0, GetD(ASH(val, -16)));
          IF val MOD IMM16 # 0 THEN PutI(ORI, rt, rt, val MOD IMM16) END
        END;
        x.mode := Reg; x.reg := rt
    | XProc, IProc:
        GetR(TempReg, rt);
        PutLinked(ADDI, rt, x.obj, 0);
        x.mode := Reg; x.reg := rt
    | Based:
        AddUpperToBase(x);
        f := x.typ^.form;
        ReleaseR(x.reg);
        IF f IN realSet THEN GetF(TempReg, rt) ELSE GetR(TempReg, rt) END;
        PutD(loadOp[f], rt MOD 32, x.reg, x.offset);
        IF f = SInt THEN PutX(EXTSB, rt, rt, 0) END;
        x.mode := Reg; x.reg := rt;
    | Cond:
        IF (x.Tjmp = 0) & (x.Fjmp = 0) THEN
          c := Compare(x); Release(x.reg); Release(x.reg2);
          GetR(TempReg, rt); CondValue(c, rt)
        ELSE
          GetR(TempReg, rt);
          PutCond(x, 3, TRUE); FixLink(x.Fjmp); PutD(ADDI, rt, 0, 0); Put(SetLI(B, 2));
          FixLink(x.Tjmp); PutD(ADDI, rt, 0, 1)
        END;
        x.mode := Reg; x.reg := rt
    | Reg:
    ELSE OPM.err(127); x.mode := Reg; x.reg := 3
    END
  END Load;

  PROCEDURE Move*(VAR x, y: Item; xform: SHORTINT);  (* x := y *)
    VAR rx, ry, lower: LONGINT;
  BEGIN
    IF x.mode = Var THEN lower := x.offset;
      IF (lower >= 0) & (lower < 64) THEN x.mode := Reg; x.reg := lower END
    END ;
    IF y.mode # Reg THEN
      IF x.mode = Reg THEN ry := x.reg ELSE ry := -1 END ;
      Load(y, ry)
    END ;
    ry := y.reg;
    CASE x.mode OF
      Var:
        IF x.mnolev <= 0 THEN (* global or extern *)
          IF lower >= 64 THEN DEC(lower, 64) END;
          PutLinked(storeOp[xform], ry MOD 32, x.obj, lower);
          Release(ry)
        ELSE (* local or intermediate *)
          Base(x, -1); Move(x, y, xform)
        END
    | VarPar:
        Base(x, -1); Move(x, y, xform)
    | Based:
        AddUpperToBase(x); lower := x.offset;
        ReleaseR(x.reg);
        PutD(storeOp[xform], ry MOD 32, x.reg, lower);
        Release(ry)
    | Reg:
        rx := x.reg;
        IF ry # rx THEN
          IF rx < 32 THEN
            IF ry < 32 THEN PutX(ORR, ry, rx, ry); ReleaseR(ry)
            ELSE OPM.err(713);
            END
          ELSIF rx < 64 THEN
            IF ry < 32 THEN OPM.err(712);
            ELSE PutF(FMR, rx MOD 32, 0, ry MOD 32)
            END
          ELSE OPM.err(708);
          END
        END
    ELSE OPM.err(127)
    END
  END Move;

  PROCEDURE PutSPC*(funct, rt: LONGINT; VAR x, y: Item): LONGINT;  (* rt := x funct y *)
    VAR rx, ry: LONGINT;
  BEGIN
    Load(x, -1); Load(y, -1); rx := x.reg; ry := y.reg;
    ReleaseR(rx); ReleaseR(ry); GetR(TempReg, rt);
    PutR(funct, rt, rx, ry);
    RETURN rt
  END PutSPC;

  PROCEDURE PutIMM*(op, rt: LONGINT; VAR x: Item; imm: LONGINT): LONGINT;  (* rt := x op imm *)
    VAR rx: LONGINT;
  BEGIN
    Load(x, -1); rx := x.reg; ReleaseR(rx); GetR(TempReg, rt);
    PutI(op, rt, rx, imm);
    RETURN rt
  END PutIMM;

  PROCEDURE Unary(op: LONGINT): BOOLEAN;
  BEGIN RETURN (op = FNEG) OR (op = FABS) OR (op = FMR) OR (op = FRSP) OR (op = FCTIW)
  END Unary;

  PROCEDURE PutFPA*(func, ft: LONGINT; VAR x, y: Item): LONGINT;  (* ft := x func y; unary: func y *)
    VAR fx, fy: LONGINT;
  BEGIN
    Load(x, -1); Load(y, -1); fx := x.reg; fy := y.reg;
    ReleaseF(fx); ReleaseF(fy);
    GetF( TempReg, ft); ASSERT( (ft>=32) & (ft<64));
    IF Unary(func) THEN PutF(func, ft MOD 32, 0, fy MOD 32)
    ELSE PutF(func, ft MOD 32, fx MOD 32, fy MOD 32)
    END;
    RETURN ft
  END PutFPA;

  (* Scratch memory below the stack: a signal taken meanwhile writes below the new stack pointer. *)
  PROCEDURE Scratch(n: LONGINT);
  BEGIN PutD(ADDI, SP, SP, n)
  END Scratch;

  PROCEDURE IntToReal*(VAR x: Item; ft: LONGINT; single: BOOLEAN);  (* x := FLOAT(x) *)
    VAR rx: LONGINT;
  BEGIN
    Load(x, -1); rx := x.reg; ReleaseR(rx); GetF(TempReg, ft);
    (* (2^52 + 2^31 + x) - (2^52 + 2^31) from the bits 43300000 80000000 xor x *)
    Scratch(-16);
    PutD(ADDIS, T0, 0, 4330H); PutD(STW, T0, SP, 0); PutD(STW, T0, SP, 8);
    PutI(XORIS, T1, rx, 8000H); PutD(STW, T1, SP, 4);
    PutD(ADDIS, T1, 0, -8000H); PutD(STW, T1, SP, 12);
    PutD(LFD, ft MOD 32, SP, 0); PutD(LFD, FT0 MOD 32, SP, 8);
    PutF(FSUB + 10000000H, ft MOD 32, ft MOD 32, FT0 MOD 32);
    Scratch(16);
    IF single THEN PutF(FRSP, ft MOD 32, 0, ft MOD 32) END;
    x.mode := Reg; x.reg := ft
  END IntToReal;

  PROCEDURE RealToInt*(VAR x: Item; rt: LONGINT);  (* x := ENTIER(x), rounding toward minus infinity *)
    VAR fx: LONGINT;
  BEGIN
    Load(x, -1); fx := x.reg; ReleaseF(fx); GetR(TempReg, rt);
    Put(MTFSFI + ASH(7, 23) + ASH(3, 12));
    PutF(FCTIW, FT0 MOD 32, 0, fx MOD 32);
    Put(MTFSFI + ASH(7, 23));
    Scratch(-16); PutD(STFD, FT0 MOD 32, SP, 0); PutD(LWZ, rt, SP, 4); Scratch(16);
    x.mode := Reg; x.reg := rt
  END RealToInt;

  PROCEDURE MoveBits*(VAR x: Item; rt: LONGINT; toReal: BOOLEAN);  (* SYSTEM.VAL between REAL and LONGINT *)
    VAR r: LONGINT;
  BEGIN
    Load(x, -1); r := x.reg; Scratch(-16);
    IF toReal THEN ReleaseR(r); GetF(TempReg, rt); PutD(STW, r, SP, 0); PutD(LFS, rt MOD 32, SP, 0)
    ELSE ReleaseF(r); GetR(TempReg, rt); PutD(STFS, r MOD 32, SP, 0); PutD(LWZ, rt, SP, 0)
    END;
    Scratch(16); x.mode := Reg; x.reg := rt
  END MoveBits;

  PROCEDURE Add*(VAR x, y: Item; rt: LONGINT; sub: BOOLEAN);  (* x := x+-y *)
    VAR z: Item; c: LONGINT; xc, yc: BOOLEAN;
  BEGIN
    xc := x.mode = Con; yc := y.mode = Con;
    IF xc & yc THEN
      IF sub THEN DEC(x.offset, y.offset) ELSE INC(x.offset, y.offset) END ;
      RETURN
    END ;
    IF xc & ~sub THEN z := x; x := y; y := z; yc := TRUE END ;
    IF yc THEN
      IF sub & (y.offset # MIN(LONGINT)) THEN y.offset := -y.offset; sub := FALSE END ;
      c := y.offset;
      IF c # 0 THEN
        IF (c < 8000H) & (c >= -8000H) THEN x.reg := PutIMM(ADDI, rt, x, c);
        ELSIF sub THEN x.reg := PutSPC(SUB, rt, x, y)
        ELSE x.reg := PutSPC(ADD, rt, x, y)
        END
      END
    ELSIF sub THEN x.reg := PutSPC(SUB, rt, x, y)
    ELSE x.reg := PutSPC(ADD, rt, x, y)
    END
  END Add;

  PROCEDURE Mul*(VAR x, y: Item; rt: LONGINT);  (* x := x*y *)
    VAR c, n: LONGINT; xc, yc: BOOLEAN;
  BEGIN
    xc := x.mode = Con; yc := y.mode = Con;
    IF xc & yc THEN x.offset := x.offset*y.offset
    ELSE
      IF xc THEN c := x.offset; x := y; y.mode := Con; y.offset := c; yc := TRUE END;
      IF yc THEN c := y.offset;
        n := 0; WHILE (n < 31) & (ASH(1, n) < c) DO INC(n) END;
        IF (c > 0) & (ASH(1, n) = c) THEN
          IF n # 0 THEN x.reg := PutIMM(SLLI, rt, x, n) ELSE Load(x, rt) END
        ELSIF (c >= -8000H) & (c < 8000H) THEN x.reg := PutIMM(MULLI, rt, x, c)
        ELSE x.reg := PutSPC(MULLW, rt, x, y)
        END
      ELSE x.reg := PutSPC(MULLW, rt, x, y)
      END;
      x.mode := Reg
    END
  END Mul;

  PROCEDURE Div*(VAR x, y: Item; rt: LONGINT; mod: BOOLEAN);  (* floored; y > 0, else trap 10 *)
    VAR zeroTrap: BOOLEAN;
  BEGIN
    zeroTrap := (y.mode # Con) OR (y.offset <= 0);
    Load(x, -1); Load(y, -1);
    ReleaseR(x.reg); GetR(TempReg, rt); ReleaseR(y.reg);
    IF rt = y.reg THEN rt := -1; GetR(TempReg, rt) END;
    IF zeroTrap THEN PutCmpI(FALSE, y.reg, 0); PutTrapUnless(BGT, ZeroTrap) END;
    IF mod THEN  (* r := x - (x quot y) * y; IF r < 0 THEN INC(r, y) END *)
      PutR(DIVW, T0, x.reg, y.reg);
      PutR(MULLW, T0, T0, y.reg);
      PutR(SUB, rt, x.reg, T0);
      PutI(SRAI, T1, rt, 31);
      PutR(AND, T1, T1, y.reg);
      PutR(ADD, rt, rt, T1)
    ELSE  (* q := (x - s) quot y + s, s = -1 for x < 0, else 0 *)
      PutI(SRAI, T1, x.reg, 31);
      PutR(SUB, T0, x.reg, T1);
      PutR(DIVW, rt, T0, y.reg);
      PutR(ADD, rt, rt, T1)
    END;
    x.reg := rt
  END Div;

  PROCEDURE LenDesc*(VAR x, len: Item; typ: OPT.Struct);  (* set len to LEN(x, typ^.n), x.typ^.comp = DynArr *)
  BEGIN
    len.mode := x.descmode; len.mnolev := x.mnolev; len.reg := x.reg2; len.offset := x.Tjmp; len.typ := OPT.linttyp;
    IF len.mode = Reg THEN INC(len.reg, typ^.n + 1)
    ELSIF (len.mode IN {Var, VarPar}) & (len.offset >= 0) & (len.offset < 64) THEN (* Reg *) INC(len.offset, typ^.n + 1)
    ELSE INC(len.offset, typ^.n*4 + 4)
    END
  END LenDesc;

  PROCEDURE Size*(VAR x, size: Item; rt: LONGINT; typ: OPT.Struct);  (* size := SIZE(x), x of type typ *)
    VAR len: Item;
  BEGIN
    IF typ^.comp # DynArr THEN size.mode := Con; size.offset := typ^.size
    ELSE Size(x, size, rt, typ^.BaseTyp); LenDesc(x, len, typ); Mul(size, len, rt)
    END
  END Size;

  PROCEDURE SaveRegs(r, f: SET; offset: LONGINT; VAR size: LONGINT);
    VAR i, s: LONGINT; rg, sp: Item;
  BEGIN i := 0; s := 0;
    WHILE i <32 DO
      IF i IN f THEN
        rg.mode := Reg; rg.reg := i + 32; sp.mode := Based; sp.reg := SP; sp.offset := offset;
        Move(sp, rg, LReal); INC(offset, 8); INC(s, 8)
      END ;
      INC(i, FPRegDist)
    END ;
    i := 0;
    WHILE i <32 DO
      IF i IN r THEN
        rg.mode := Reg; rg.reg := i; sp.mode := Based; sp.reg := SP; sp.offset := offset;
        Move(sp, rg, LInt); INC(offset, 4); INC(s, 4)
      END ;
      INC(i)
    END ;
    size := s + s MOD 8
  END SaveRegs;

  PROCEDURE RestoreRegs(r, f: SET; offset, base: LONGINT; VAR size: LONGINT);
    VAR i, s: LONGINT; rg, sp: Item;
  BEGIN i := 0; s := 0;
    WHILE i <32 DO
      IF i IN f THEN
        rg.mode := Reg; rg.reg := i + 32; sp.mode := Based; sp.reg := base; sp.offset := offset;
        AddUpperToBase(sp); base := sp.reg; offset := sp.offset; sp.typ := OPT.lrltyp;
        Move(rg, sp, LReal); INC(offset, 8); INC(s, 8)
      END ;
      INC(i, FPRegDist)
    END ;
    i := 0;
    WHILE i <32 DO
      IF (i IN r) THEN
        rg.mode := Reg; rg.reg := i; sp.mode := Based; sp.reg := base; sp.offset := offset;
        AddUpperToBase(sp); base := sp.reg; offset := sp.offset; sp.typ := OPT.linttyp;
        Move(rg, sp, LInt); INC(offset, 4); INC(s, 4)
      END ;
      INC(i)
    END ;
    size := s + s MOD 8
  END RestoreRegs;

  PROCEDURE Enter*(proc: OPT.Object; calleeUsed: RegSet);
    VAR par: OPT.Object;
  BEGIN (* IProc ? *)
    callArea := 0; dynArrCopied := FALSE;
    adjlx := 0; lacx := 0; thisProc := -MaxEntryCode;
    calleesUsedR := calleeUsed.r; calleesUsedF := calleeUsed.f;
    IF InterProcInf THEN
      mayBeUsedR := CallerSavedR + CalleeSavedR - calleeUsed.r;
      mayBeUsedF := CallerSavedF + CalleeSavedF - calleeUsed.f
    END ;
    locUsedR := {}; locUsedF := {}; tempLiveR := {}; tempLiveF := {};
    permLiveR := {}; permLiveF := {}; frozenR := {};
    curshiftx := NoShift;
    IF proc = NIL THEN (* module *)
      NoFP := TRUE; LeafProc := FALSE
    ELSE
      par := proc^.link;
      WHILE par # NIL DO
        IF (par^.mode = Var) & (par^.typ^.comp = DynArr) THEN dynArrCopied := TRUE END ;
        par := par^.link
      END ;
      LeafProc := proc^.leaf;
      NoFP := ~dynArrCopied & (proc^.conval^.intval - proc^.conval^.intval2 <= MaxLittleFrame);
      INC(proc^.adr, LONG(pc));  (* do not destroy mthd no *)
      FixBranches(proc)
    END ;
    thisProc := pc; INC(pc, MaxEntryCode); curshiftx := shiftx
  END Enter;

  PROCEDURE Exit*(proc: OPT.Object; VAR calleeUsed: RegSet; VAR pcOffset: INTEGER);
    VAR i, j, savedPC, shift: INTEGER; sp, fp, y: Item;
        instr, spdisp, offset, varSize, calleeSize, dummy: LONGINT;
        saveR, saveF: SET; openProc: BOOLEAN;
  BEGIN
    calleeUsed.r := locUsedR + calleesUsedR; calleeUsed.f := locUsedF + calleesUsedF;
    IF proc = NIL THEN (* module *)
      openProc := TRUE; varSize := 0
    ELSE
      openProc := (proc^.mode = XProc) (* exported or assigned *) OR (alreadyCalled IN proc^.conval^.setval);
      varSize := proc^.conval^.intval2
    END ;
    IF ~InterProcInf OR openProc THEN
      saveR := calleeUsed.r*CalleeSavedR; saveF := calleeUsed.f*CalleeSavedF;
      calleeUsed.r := calleeUsed.r*CallerSavedR; calleeUsed.f := calleeUsed.f*CallerSavedF
    ELSE
      saveR := {}; saveF := {}
    END ;
    IF dynArrCopied THEN
      IF code[resCallArea] = ADDI + ASH(SP, 21) + ASH(SP, 16) THEN  (* addi sp, sp, 0 from OPC.Enter *)
        code[resCallArea] := SetD(code[resCallArea], -callArea)
      ELSE OPM.err(920); OPM.LogWHex( code[resCallArea]);
      END;
    END ;
    (* entry code: *)
    savedPC := pc; pc := thisProc; curshiftx := NoShift;
    IF ~LeafProc THEN INCL(saveR, RA); Put(MFLR + ASH(RA, 21)) END ;
    IF ~NoFP THEN INCL(saveR, FP) END ;
    calleeSize := 0; i := 0;
    WHILE i < 32 DO
      IF i IN saveF THEN INC(calleeSize, 8) END ;
      INC(i, FPRegDist)
    END ;
    i := 0;
    WHILE i < 32 DO
      IF i IN saveR THEN INC(calleeSize, 4) END ;
      INC(i)
    END ;
    INC(calleeSize, calleeSize MOD 8);  (* +0 or +4 *)
    frameSize := calleeSize - varSize + callArea;
    IF dynArrCopied THEN spdisp := calleeSize - varSize ELSE spdisp := frameSize END ;
    sp.mode := Reg; sp.reg := SP;
    IF ~NoFP & (spdisp >= 8000H) THEN y.mode := Reg; y.reg := T1; Move(y, sp, LInt)
    END ;
    y.mode := Con; y.offset := spdisp; Add(sp, y, SP, TRUE);
    IF dynArrCopied THEN offset := 0 ELSE offset := callArea END ;
    SaveRegs(saveR, saveF, offset, dummy);
    IF ~NoFP THEN
      IF spdisp >= 8000H THEN fp.mode := Reg; fp.reg := FP; y.mode := Reg; y.reg := T1; Move(fp, y, LInt);
      ELSE sp.mode := Reg; sp.reg := SP; y.mode := Con; y.offset := spdisp; Add(sp, y, FP, FALSE);
      END
    ELSE i := 0;
      WHILE i < lacx DO
        j := localAccess[i]; INC(i); instr := code[j];
        code[j] := SetD(instr, GetD(instr) + frameSize)
      END
    END ;
    shift := thisProc + MaxEntryCode - pc; pcOffset := shift;
    i := 0;
    WHILE i < adjlx DO
      j := adjustLink[i]; INC(i); instr := code[j];
      IF Opcode(instr) = 18 THEN code[j] := SetLI(instr, GetLI(instr) + shift)
      ELSE code[j] := SetD(instr, GetD(instr) + shift)  (* two words to the loader *)
      END
    END ;
    shiftTab[shiftx] := shift; INC(shiftx);
    i := thisProc + MaxEntryCode;
    WHILE i < savedPC DO code[i - shift] := code[i]; INC(i) END ;
    pc := savedPC - shift;
    (* exit code: *)
    IF NoFP THEN RestoreRegs(saveR, saveF, callArea, SP, dummy)
    ELSE
      fp.mode := Reg; fp.reg := FP; y.mode := Reg; y.reg := T0; Move(y, fp, LInt);
      RestoreRegs(saveR, saveF, varSize - calleeSize, T0, dummy)
    END ;
    sp.mode := Reg; sp.reg := SP;
    IF NoFP THEN
      IF (frameSize > 0) THEN y.mode := Con; y.offset := frameSize; Add(sp, y, SP, FALSE) END;
    ELSE y.mode := Reg; y.reg := T0; Move(sp, y, LInt)
    END;
    IF ~LeafProc THEN Put(MTLR + ASH(RA, 21)) END;
    Put(BLR);
    saved.r := saveR; saved.f := saveF;
  END Exit;

  PROCEDURE SaveRegisters*(calleeUsed: RegSet; argSize: LONGINT; VAR saved, live: RegSet);  (* argSize aligned to 8 *)
    VAR sp, ext: Item; saveSize, patch: LONGINT;
  BEGIN
    saved.r := (tempLiveR + permLiveR)*calleeUsed.r; live.r := tempLiveR;
    saved.f := (tempLiveF + permLiveF)*calleeUsed.f; live.f := tempLiveF;
    saveSize := 0; patch := 0;
    IF (saved.r # {}) OR (saved.f # {}) THEN (* something to save *)
      IF RegsSaved THEN  (* extend stack *)
        sp.mode := Reg; sp.reg := SP;
        ext.mode := Con; ext.offset := 1;  (* 1 to be patched *)
        Add(sp, ext, SP, TRUE);
        patch := pc-1
      ELSE RegsSaved := TRUE
      END ;
      SaveRegs(saved.r, saved.f, argSize, saveSize);
      tempLiveR := tempLiveR - saved.r; tempLiveF := tempLiveF - saved.f
    END ;
    INC(saveSize, argSize);
    IF saveSize > callArea THEN callArea := saveSize END ;
    IF patch # 0 THEN
      IF code[patch] = ADDI + ASH(SP, 21) + ASH(SP, 16) + 0FFFFH THEN  (* addi sp, sp, -1 *)
        code[patch] := SetD(code[patch], -saveSize);
        OPM.err(-715);
      ELSE OPM.err(-916); OPM.LogWHex( code[patch]);
      END;
      INC(stackExt, saveSize)
    END
  END SaveRegisters;

  PROCEDURE RestoreRegisters*(VAR x: Item; argSize: LONGINT; saved, live: RegSet);
    VAR y, sp, ext: Item; rt, rx, saveSize: LONGINT; f: SHORTINT;
  BEGIN
    tempLiveR := live.r; tempLiveF := live.f;
    IF x.typ # OPT.notyp THEN
      x.mode := Reg; f := x.typ^.form; rt := -1;
      IF f IN {Real, LReal} THEN rx := RRF; INCL(tempLiveF, RRF-32);
        IF RRF-32 IN saved.f THEN GetF(TempReg, rt) END
      ELSE rx := RRI; INCL(tempLiveR, RRI);
        IF RRI IN saved.r THEN GetR(TempReg, rt) END
      END ;
      IF rt # -1 THEN y.mode := Reg; y.reg := rx; x.reg := rt; Move(x, y, f)
      ELSE x.reg := rx
      END ;
    END ;
    IF (saved.r # {}) OR (saved.f # {}) THEN (* something to restore *)
      RestoreRegs(saved.r, saved.f, argSize, SP, saveSize);
      IF stackExt = 0 THEN
        RegsSaved := FALSE
      ELSE
        INC(saveSize, argSize);
        sp.mode := Reg; sp.reg := SP;
        ext.mode := Con; ext.offset := saveSize;
        Add(sp, ext, SP, FALSE);
        DEC(stackExt, saveSize)
      END
    END
  END RestoreRegisters;

  PROCEDURE OutRefPoint*;
  BEGIN
    OPM.RefW(0F8X); OPM.RefWNum(pc);
    OPM.RefWNum(S.VAL(LONGINT, saved.r));
    OPM.RefWNum(S.VAL(LONGINT, saved.f));
    OPM.RefWNum(frameSize); OPM.RefWNum(callArea)
  END OutRefPoint;

  PROCEDURE OutRefName*(VAR name: ARRAY OF CHAR);
    VAR ch: CHAR; i: INTEGER;
  BEGIN i := 0;
    REPEAT ch := name[i]; OPM.RefW(ch); INC(i) UNTIL ch = 0X
  END OutRefName;

  PROCEDURE OutRefs*(obj: OPT.Object);
    VAR f: SHORTINT;
  BEGIN
    IF obj # NIL THEN
      OutRefs(obj^.left);
      IF (obj^.mode = Var) OR (obj^.mode = VarPar) THEN
        f := obj^.typ^.form;
        IF (f IN {Byte .. Set, Pointer, ProcTyp})
          OR (obj^.typ^.comp = Array) & (obj^.typ^.BaseTyp^.form = Char) THEN
          IF obj^.mode = Var THEN OPM.RefW(1X) ELSE OPM.RefW(3X) END ;
          IF obj^.typ^.comp = Array THEN OPM.RefW(0FX)
          ELSE OPM.RefW(CHR(f))
          END ;
          OPM.RefWNum(obj^.linkadr);
          OutRefName(obj^.name)
        END
      END ;
      OutRefs(obj^.right)
    END
  END OutRefs;

  PROCEDURE FindPtrs*(typ: OPT.Struct; adr: LONGINT; VAR tab: ARRAY OF LONGINT; VAR last: INTEGER);
    VAR fld: OPT.Object; btyp: OPT.Struct; i, n: LONGINT; last1: INTEGER;

    PROCEDURE Add(adr: LONGINT);
    BEGIN IF last < LEN(tab) THEN tab[last] := adr; INC(last) END
    END Add;

  BEGIN
    IF typ^.form = Pointer THEN Add(adr)
    ELSIF typ^.comp = Record THEN
      btyp := typ^.BaseTyp;
      IF btyp # NIL THEN FindPtrs(btyp, adr, tab, last) END ;
      fld := typ^.link;
      WHILE (fld # NIL) & (fld^.mode = Fld) DO
        IF fld^.name = OPM.HdPtrName THEN Add(fld^.adr + adr)
        ELSE FindPtrs(fld^.typ, fld^.adr + adr, tab, last)
        END ;
        fld := fld^.link
      END
    ELSIF typ^.comp = Array THEN
      btyp := typ^.BaseTyp; n := typ^.n;
      WHILE btyp^.comp = Array DO n := btyp^.n * n; btyp := btyp^.BaseTyp END ;
      IF (btyp^.form = Pointer) OR (btyp^.comp = Record) THEN
        last1 := last; FindPtrs(btyp, adr, tab, last);
        IF last # last1 THEN i := 1;
          WHILE (i < n) & (last < LEN(tab)) DO
            INC(adr, btyp^.size); FindPtrs(btyp, adr, tab, last); INC(i)
          END
        END
      END
    END
  END FindPtrs;

  PROCEDURE WLink(obj: OPT.Object);
    VAR link: INTEGER;
  BEGIN
    link := SHORT(obj.linkadr);
    IF (link # 0) & (obj.x < shiftx) THEN DEC(link, shiftTab[obj.x]); obj.linkadr := link; obj.x := NoShift END ;
    OPM.ObjWNum(link)
  END WLink;

  PROCEDURE WName(VAR name: OPS.Name);
    VAR ch: CHAR; i: INTEGER;
  BEGIN i := 0;
    REPEAT ch := name[i]; OPM.ObjW(ch); INC(i) UNTIL ch = 0X
  END WName;

  PROCEDURE WTDesc(typ: OPT.Struct);
    VAR btyp: OPT.Struct; nofinhmth, nofnewmeth, nofptr, i: INTEGER;
      ptrTab: ARRAY OPM.MaxPtr + 1 OF LONGINT;
      NewMthTab: ARRAY 256 OF OPT.Object;

    PROCEDURE FindNewMths(obj: OPT.Object);
    BEGIN
      IF obj # NIL THEN
        FindNewMths(obj^.left);
        IF obj^.mode = TProc THEN NewMthTab[nofnewmeth] := obj; INC(nofnewmeth) END ;
        FindNewMths(obj^.right)
      END
    END FindNewMths;

  BEGIN
    IF typ^.ref >= 0 THEN
      btyp := typ^.BaseTyp;
      typ^.ref := -nofdesc-1; INC(nofdesc);
      OPM.ObjW(8X); WName(typ^.strobj^.name);
      IF typ^.strobj^.name = "" THEN OPT.FPrintStr(typ); OPM.ObjWNum(typ^.pvfp) END ;
      WLink(typ^.strobj); OPM.ObjWNum(typ^.size);
      IF btyp = NIL THEN nofinhmth := 0; OPM.ObjWNum(-1)
      ELSE nofinhmth := SHORT(btyp^.n);
        OPM.ObjWNum(btyp^.mno); WName(btyp^.strobj^.name);
        IF btyp^.strobj^.name = "" THEN OPT.FPrintStr(btyp); OPM.ObjWNum(btyp^.pvfp) END
        (* extension table of base td copied by loader *)
      END ;
      OPM.ObjWNum(typ^.n); (* total nof method *)
      OPM.ObjWNum(nofinhmth); (* nof of inherited method *)
      nofnewmeth := 0; FindNewMths(typ^.link);
      OPM.ObjWNum(nofnewmeth);
      nofptr := 0; FindPtrs(typ, 0, ptrTab, nofptr);
      IF nofptr > OPM.MaxPtr THEN OPM.err(221) END ;
      OPM.ObjWNum(nofptr);
      WHILE nofnewmeth > 0 DO DEC(nofnewmeth);
        OPM.ObjWNum(NewMthTab[nofnewmeth]^.adr DIV 10000H);  (*mthno*)
        OPM.ObjWNum(NewMthTab[nofnewmeth]^.adr MOD 10000H)  (*pc*)
      END ;
      i := 0;
      WHILE i < nofptr DO OPM.ObjWNum(ptrTab[i]); INC(i) END ;
    END
  END WTDesc;

  PROCEDURE OutCode*;
    VAR i, nofexp, nofcom, nofptr: INTEGER;
      obj: OPT.Object;
      ptrTab: ARRAY OPM.MaxGPtr + 1 OF LONGINT;
      ComTab: ARRAY MaxComs OF OPT.Object;

    PROCEDURE WriteName(VAR name: OPS.Name);
      VAR i: INTEGER; ch: CHAR;
    BEGIN i := 0;
      REPEAT ch := name[i]; OPM.ObjW(ch); INC(i)
      UNTIL ch = 0X
    END WriteName;

    PROCEDURE Export(obj: OPT.Object);

      PROCEDURE WStruct(obj: OPT.Object);
        VAR strobj: OPT.Object; typ: OPT.Struct;
      BEGIN
        typ := obj^.typ; strobj := typ^.strobj;
        IF (strobj = obj) & (typ^.form = Comp) THEN  (* not an alias *)  ASSERT(obj^.typ^.mno = 0);
          IF (strobj^.name # "") & (typ^.ref # OPM.MaxStruct) THEN  (* named and exported type *)
            INC(nofexp, 2);  (* 2 entries in module desc, pbfp and pvfp *)
            OPM.ObjW(6X); WName(strobj^.name); OPT.FPrintStr(typ);
            OPM.ObjWNum(typ^.pbfp); OPM.ObjWNum(typ^.pvfp)
          END ;
          IF typ^.comp = Record THEN WTDesc(obj^.typ) END
        END
      END WStruct;

    BEGIN
      IF obj # NIL THEN
        Export(obj^.left);
        IF obj^.history # removed THEN
          IF obj^.vis # internal THEN OPT.FPrintObj(obj);
            IF obj^.mode = Con THEN INC(nofexp);
              OPM.ObjW(1X); WName(obj^.name); OPM.ObjWNum(obj^.fprint)
            ELSIF obj^.mode = Typ THEN INC(nofexp);
              OPM.ObjW(2X); WName(obj^.name); OPM.ObjWNum(obj^.fprint); WStruct(obj)
            ELSIF obj^.mode = Var THEN INC(nofexp);
              OPM.ObjW(3X); WName(obj^.name); OPM.ObjWNum(obj^.fprint); OPM.ObjWNum(obj^.adr);
              FindPtrs(obj^.typ, obj^.adr, ptrTab, nofptr)
            ELSIF obj^.mode IN {XProc, IProc} THEN INC(nofexp);
              OPM.ObjW(4X); WName(obj^.name); OPM.ObjWNum(obj^.fprint); OPM.ObjWNum(obj^.adr);
              IF obj^.linkadr # 0 (*assigned*) THEN OPM.ObjW(9X); OPM.ObjWNum(obj^.adr); WLink(obj) END ;
              IF (obj^.link = NIL) & (obj^.typ = OPT.notyp) THEN  (*command*)
                IF nofcom < MaxComs THEN ComTab[nofcom] := obj; INC(nofcom)
                ELSE OPM.err(232); nofcom := 0
                END
              END
            ELSIF obj^.mode = CProc THEN INC(nofexp);
              OPM.ObjW(5X); WName(obj^.name); OPM.ObjWNum(obj^.fprint)
            END
          ELSIF obj^.mode = Typ THEN WStruct(obj)
          ELSIF obj^.mode = Var THEN FindPtrs(obj^.typ, obj^.adr, ptrTab, nofptr)
          ELSIF (obj^.mode IN {XProc, IProc}) & (obj^.linkadr # 0) THEN  (* assigned *)
            OPM.ObjW(9X); OPM.ObjWNum(obj^.adr); WLink(obj)
          END
        END ;
        Export(obj^.right)
      END
    END Export;

    PROCEDURE Use(obj: OPT.Object);
      VAR typ: OPT.Struct; strobj: OPT.Object;
    BEGIN
      IF obj # NIL THEN
        Use(obj^.left);
        IF obj^.used THEN OPT.FPrintObj(obj);
          IF obj^.mode = Con THEN
            OPM.ObjW(1X); WName(obj^.name); OPM.ObjWNum(obj^.fprint)
          ELSIF obj^.mode = Typ THEN
            OPM.ObjW(2X); WName(obj^.name); OPM.ObjWNum(obj^.fprint)
          ELSIF obj^.mode = Var THEN
            OPM.ObjW(3X); WName(obj^.name); OPM.ObjWNum(obj^.fprint); WLink(obj)
          ELSIF obj^.mode IN {XProc, IProc} THEN
            OPM.ObjW(4X); WName(obj^.name); OPM.ObjWNum(obj^.fprint); WLink(obj)
          ELSIF obj^.mode = CProc THEN
            OPM.ObjW(5X); WName(obj^.name); OPM.ObjWNum(obj^.fprint)
          END
        END ;
        IF obj^.mode = Typ THEN typ := obj^.typ; strobj := typ^.strobj;
          IF (typ^.form = Comp) & (strobj = obj) THEN OPT.FPrintStr(typ);
            IF strobj^.name # "" THEN  (* not only Record, e.g. non-exported dereferenced external array *)
              IF typ^.pvused THEN OPM.ObjW(7X); WName(strobj^.name); OPM.ObjWNum(typ^.pvfp);
                IF obj^.history = inconsistent THEN OPT.FPrintErr(obj, 249) END
              ELSIF typ^.pbused THEN OPM.ObjW(6X); WName(strobj^.name); OPM.ObjWNum(typ^.pbfp)
              END
            (* ELSE fp already checked *)
            END ;
            IF (typ^.comp = Record) & (strobj^.linkadr # 0) THEN
              OPM.ObjW(8X); WName(strobj^.name);
              IF strobj^.name = "" THEN OPM.ObjWNum(typ^.pvfp) END ;
              WLink(strobj)
            END
          END
        END ;
        Use(obj^.right)
      END
    END Use;

  BEGIN
    INC(pc, pc MOD 2);
    WHILE (conx MOD 8) # 0 DO DEC(conx); constant[conx] := 0X END;
  (*HeaderBlk*)
    nofexp := 0; nofdesc := 0; nofcom := 0; nofptr := 0;
    OPM.ObjWNum(OPT.nofGmod-1); WLink(KNewRec); WLink(KNewSys); WLink(KNewArr);
    WLink(GlobData); OPM.ObjWNum(-sb);
    OPM.ObjWNum( LEN(constant)-conx);
    OPM.ObjWNum(pc); WriteName(OPT.SelfName);
  (*ImpBlk*)
    OPM.ObjW(81X); i := 1;
    WHILE i < OPT.nofGmod DO WriteName(OPT.GlbMod[i].name); INC(i) END ;
  (*ExpBlk*)
    OPM.ObjW(82X);
    Export(OPT.topScope^.right);  (* export objects and collect commands and pointers*)
    IF nofptr > OPM.MaxGPtr THEN OPM.err(222) END ;
    OPM.ObjW(0X);
  (*CmdBlk*)
    OPM.ObjW(83X); i := 0;
    WHILE i < nofcom DO
      obj := ComTab[i]; WriteName(obj^.name); OPM.ObjWNum(obj^.adr); INC(i)
    END ;
  (*PtrBlk*)
    OPM.ObjW(84X); i := 0;
    WHILE i < nofptr DO OPM.ObjWNum(ptrTab[i]); INC(i) END ;
  (*ConstBlk*)
    OPM.ObjW(87X);
    i:=0;
    WHILE i<LEN(constant)-conx DO
      constant[ i]:= constant[ conx+i];
      INC(i);
    END;
    OPM.ObjWBytes(constant, LEN(constant)-conx);
  (*CodeBlk*)
    OPM.ObjW(88X); i := 0;
    WHILE i < pc DO OPM.ObjWLInt(code[i]); INC(i) END ;
  (*UseBlk*)
    OPM.ObjW(89X); i := 1;
    WHILE i < OPT.nofGmod DO Use(OPT.GlbMod[i].right); OPM.ObjW(0X); INC(i) END;
  (*RefBlk written in OPM.RegisterRefObj*)
    IF OPM.noerr THEN OPM.RegisterRefObj(nofexp, nofdesc, nofcom, nofptr) END;
    OPM.pc:=pc; OPM.sb:=sb;
  END OutCode;

  PROCEDURE Init*(opt: SET);
    CONST intprinf = 6;
    VAR w: LONGINT; c: CHAR;
  BEGIN
    InterProcInf := intprinf IN opt;
    w := 1; S.GET(S.ADR(w), c); hostBig := c = 0X;
    pc := 0; level := 0; sb := 0; conx := 0; shiftx := 0; curshiftx := NoShift;
    conx:=LEN(constant);
    CodeOvF := FALSE; RegsSaved := FALSE; stackExt := 0;
    KNewRec.linkadr := 0; KNewSys.linkadr := 0; KNewArr.linkadr := 0; GlobData.linkadr := 0
  END Init;

  PROCEDURE Close*;
  END Close;

BEGIN
  NEW(KNewRec); NEW(KNewSys); NEW(KNewArr); NEW(GlobData);
  defaultCalleeUsed.r := CallerSavedR;
  defaultCalleeUsed.f := CallerSavedF;
  loadOp[Byte] := LBZ;
  loadOp[Bool] := LBZ;
  loadOp[Char] := LBZ;
  loadOp[SInt] := LBZ;  (* and extsb *)
  loadOp[Int] := LHA;
  loadOp[LInt] := LWZ;
  loadOp[Real] := LFS;
  loadOp[LReal] := LFD;
  loadOp[Set] := LWZ;
  loadOp[String] := NOP;
  loadOp[NilTyp] := NOP;
  loadOp[NoTyp] := LWZ;
  loadOp[ProcTyp] := LWZ;
  loadOp[Pointer] := LWZ;
  loadOp[Comp] := LWZ;
  storeOp[Byte] := STB;
  storeOp[Bool] := STB;
  storeOp[Char] := STB;
  storeOp[SInt] := STB;
  storeOp[Int] := STH;
  storeOp[LInt] := STW;
  storeOp[Real] := STFS;
  storeOp[LReal] := STFD;
  storeOp[Set] := STW;
  storeOp[String] := NOP;
  storeOp[NilTyp] := NOP;
  storeOp[NoTyp] := STW;
  storeOp[ProcTyp] := STW;
  storeOp[Pointer] := STW;
  storeOp[Comp] := STW;

END POPL.
