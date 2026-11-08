MODULE KOPC;  (* Copyright (c) Michael Franz, 1989-95 / mf 13.7.94 se 16 Aug 97 *)
(* code generator for the Motorola 68020 and later, with a floating point unit
  polpo: made from aOPC of ST-Oberon V4 (see KOPL), on the ROP2 front end. Heap blocks, type descriptors
  and open arrays as the ROP2 Kernel and loader have them:
  - a record has its tag (the type descriptor) at -4; a type descriptor has the tag of its base type of
    extension level n at -8 - 4*n;
  - an open array (a parameter, or on the heap at p+8) has a descriptor: its address, then the length
    of each dimension, the innermost first;
  - an array on the heap has its elements at p+16 (one open dimension or none), p+24 (two, three) ...
  DIV and MOD: the divisor must be positive (trap 10), the quotient is rounded down. *)

  IMPORT OPM := ROPM, OPT := ROPT, OPL := KOPL, SYSTEM;

  CONST
    (* symbol values *)
    times = 1; slash = 2; div = 3; mod = 4; and = 5; plus = 6; minus = 7; or = 8; eql = 9; neq = 10; lss = 11; leq = 12;
    gtr = 13; geq = 14; in = 15; ash = 17; msk = 18; len = 19; conv = 20; abs = 21; cap = 22; odd = 23; not = 33;
    adr = 24; cc = 25; bit = 26; lsh = 27; rot = 28; val = 29;
    (* node classes *)
    Nvarpar = 1; Nderef = 3;
    (* function numbers *)
    incfn = 13; decfn = 14; inclfn = 15; exclfn = 16; copyfn = 18; getfn = 24; putfn = 25; getrfn = 26; putrfn = 27;
    (* object modes *)
    Var = 1; VarPar = 2; CProc = 9; IProc = 10;
    (* structure forms *)
    Byte = 1; Bool = 2; Char = 3; SInt = 4; Int = 5; LInt = 6; Real = 7; LReal = 8; Set = 9; String = 10; NilTyp = 11;
    Pointer = 13; ProcTyp = 14; Comp = 15; Array = 2; DynArr = 3; Record = 4;
    (* data sizes *)
    Half = 0; Word = 1; Long = 2; Double = 3; Other = 4;
    (* item modes *)
    Dn = 14; An = 15; Fn = 16; RegInd = 17; MemInd = 18; Indexed = 19;
    GlobVar = 20; GlobDes = 21; Pop = 25; Abs = 26; Imm = 27; CCR = 28;
    (* modifiers of Op1, Op2 *)
    opSZ = 4000H; opKS = 2000H; opRD = 1000H; opLS = 800H; opXLS = 400H; opLD = 100H; opXLD = 80H;
    (* formats *)
    opRx = 6; opRxLong = 7; opRy = 8; opEa = 10; opEaLong = 11; opRwLong = 12; opRzRz = 13;
    opRyRx = 17; opRxRy = 18; opEaRn = 19; opRnEa = 20; opImmEa = 21; opEaRwLong = 22;
    (* conditions *)
    ccT = 0; ccF = 1; ccHI = 2; ccLS = 3; ccCC = 4; ccCS = 5; ccNE = 6; ccEQ = 7; ccVC = 8; ccVS = 9; ccPL = 10;
    ccMI = 11; ccGE = 12; ccLT = 13; ccGT = 14; ccLE = 15;
    ccfEQ = -1; ccfNE = -14; ccfGT = -18; ccfGE = -19; ccfLT = -20; ccfLE = -21;
    (* traps, as in the other ROP2 back ends *)
    RangeTrap = 8; ZeroTrap = 10; IndexTrap = 15; TGTrap = 18; ITGTrap = 19;
    Tag0Offset = -8;

    intSet = {SInt, Int, LInt}; realSet = {Real, LReal};

  VAR
    inxchk, ranchk, typchk, ptrinit: BOOLEAN;
    cmpCC, cmpCCX, cmpCCF, swapRel, invRel: ARRAY 15 OF INTEGER;

  PROCEDURE err(n: INTEGER);
  BEGIN OPM.err(n)
  END err;

  PROCEDURE Trap*(n: LONGINT);
  BEGIN OPL.Trap(n)
  END Trap;

  PROCEDURE TrapCC*(cond: INTEGER; n: LONGINT);
    VAR x: OPL.Item;
  BEGIN x.alpha := 0; x.beta := 0; x.code := cond; OPL.TrapCC(x, n)
  END TrapCC;

  PROCEDURE SetImm(VAR x: OPL.Item; v: LONGINT);
  BEGIN x.mode := Imm; x.adr := v; x.typ := OPT.linttyp
  END SetImm;

(* Boolean expressions *)

  PROCEDURE LoadCC(VAR x: OPL.Item);
  BEGIN
    IF x.mode # CCR THEN
      IF x.mode = Imm THEN
        IF x.adr = OPL.false THEN OPL.SetCC(x, ccF) ELSE OPL.SetCC(x, ccT) END
      ELSE OPL.LoadCC(x)
      END
    END
  END LoadCC;

  PROCEDURE And(VAR x, y: OPL.Item);
  BEGIN LoadCC(y);
    IF y.beta # 0 THEN x.beta := OPL.MergedLinks(x.beta, y.beta) END;
    x.code := y.code; x.alpha := y.alpha
  END And;

  PROCEDURE Or(VAR x, y: OPL.Item);
  BEGIN LoadCC(y);
    IF y.alpha # 0 THEN x.alpha := OPL.MergedLinks(x.alpha, y.alpha) END;
    x.code := y.code; x.beta := y.beta
  END Or;

  PROCEDURE CondAnd*(VAR x: OPL.Item);
  BEGIN
    IF x.mode = CCR THEN
      IF x.code # ccT THEN OPL.BccLink(OPL.InvertCC(x.code), x.beta) END;
      OPL.FixLink(x.alpha); x.alpha := 0
    ELSIF x.mode = Imm THEN LoadCC(x); CondAnd(x)
    ELSE OPL.LoadCC(x); OPL.BccLink(ccEQ, x.beta)
    END
  END CondAnd;

  PROCEDURE CondOr*(VAR x: OPL.Item);
  BEGIN
    IF x.mode = CCR THEN
      IF x.code # ccF THEN OPL.BccLink(x.code, x.alpha) END;
      OPL.FixLink(x.beta); x.beta := 0
    ELSIF x.mode = Imm THEN LoadCC(x); CondOr(x)
    ELSE OPL.LoadCC(x); OPL.BccLink(ccNE, x.alpha)
    END
  END CondOr;

  PROCEDURE Relation*(VAR x: OPL.Item);  (* a condition as a value in a register *)
    VAR y: OPL.Item;
  BEGIN
    IF x.mode = CCR THEN y := x; OPL.GetD(x); x.typ := OPT.booltyp; OPL.ResolveCC(y, x) END
  END Relation;

(* Integer arithmetic *)

  PROCEDURE Increment(VAR x, y: OPL.Item);
    VAR n: LONGINT;
  BEGIN
    IF y.mode = Imm THEN n := y.adr;
      IF (n >= -8) & (n <= 8) THEN
        IF n = 0 THEN OPL.Release(x)
        ELSIF n < 0 THEN OPL.Op1(opEa+opSZ+opRD, 5100H + ((-n) MOD 8)*200H, x)  (* SUBQ #-y, x *)
        ELSE OPL.Op1(opEa+opSZ+opRD, 5000H + (n MOD 8)*200H, x)  (* ADDQ #y, x *)
        END
      ELSE y.typ := x.typ; OPL.Op2(opImmEa+opSZ+opRD, 600H, y, x)  (* ADDI #y, x *)
      END
    ELSE OPL.Op2(opLS+opRnEa+opSZ+opRD, 0D100H, y, x)  (* ADD Dy, x *)
    END
  END Increment;

  PROCEDURE Decrement(VAR x, y: OPL.Item);
    VAR n: LONGINT;
  BEGIN
    IF y.mode = Imm THEN n := y.adr;
      IF (n >= -8) & (n <= 8) THEN
        IF n = 0 THEN OPL.Release(x)
        ELSIF n < 0 THEN OPL.Op1(opEa+opSZ+opRD, 5000H + ((-n) MOD 8)*200H, x)  (* ADDQ #-y, x *)
        ELSE OPL.Op1(opEa+opSZ+opRD, 5100H + (n MOD 8)*200H, x)  (* SUBQ #y, x *)
        END
      ELSE y.typ := x.typ; OPL.Op2(opImmEa+opSZ+opRD, 400H, y, x)  (* SUBI #y, x *)
      END
    ELSE OPL.Op2(opLS+opRnEa+opSZ+opRD, 9100H, y, x)  (* SUB Dy, x *)
    END
  END Decrement;

  PROCEDURE Add(VAR x, y: OPL.Item);
    VAR n: LONGINT;
  BEGIN n := y.adr;
    IF (y.mode = Imm) & (n >= -8) & (n <= 8) THEN
      IF n < 0 THEN OPL.Op1(opLD+opRx+opSZ, 5100H + ((-n) MOD 8)*200H, x)  (* SUBQ #-y, Dx *)
      ELSIF n > 0 THEN OPL.Op1(opLD+opRx+opSZ, 5000H + (n MOD 8)*200H, x)  (* ADDQ #y, Dx *)
      ELSE OPL.LoadD(x)
      END
    ELSE OPL.Op2(opLD+opEaRn+opSZ, 0D000H, y, x)  (* ADD y, Dx *)
    END
  END Add;

  PROCEDURE Sub(VAR x, y: OPL.Item);
    VAR n: LONGINT;
  BEGIN n := y.adr;
    IF (y.mode = Imm) & (n >= -8) & (n <= 8) THEN
      IF n < 0 THEN OPL.Op1(opLD+opRx+opSZ, 5000H + ((-n) MOD 8)*200H, x)  (* ADDQ #-y, Dx *)
      ELSIF n > 0 THEN OPL.Op1(opLD+opRx+opSZ, 5100H + (n MOD 8)*200H, x)  (* SUBQ #y, Dx *)
      ELSE OPL.LoadD(x)
      END
    ELSE OPL.Op2(opLD+opEaRn+opSZ, 9000H, y, x)  (* SUB y, Dx *)
    END
  END Sub;

  PROCEDURE Mul(VAR x, y: OPL.Item);
  BEGIN
    IF x.typ.form = LInt THEN OPL.Op2(opLD+opEaRwLong, 4C000800H, y, x)  (* MULS.L y, Dx *)
    ELSIF x.typ.form = Int THEN OPL.Op2(opLD+opEaRn, 0C1C0H, y, x)  (* MULS.W y, Dx *)
    ELSIF y.mode = Imm THEN OPL.Op2(opXLD+opEaRn, 0C1C0H, y, x)  (* MULS.W #y, Dx *)
    ELSE OPL.Op2(opXLS+opXLD+opRxRy, 0C1C0H, y, x)  (* MULS.W Dy, Dx *)
    END
  END Mul;

  PROCEDURE Positive(VAR y: OPL.Item);  (* the divisor in a register; trap 10 unless it is > 0 *)
  BEGIN
    IF y.mode # Imm THEN
      IF y.typ.form = SInt THEN OPL.LoadX(y); OPL.Op1(opRx, 4A80H, y)  (* TST.L Dy *)
      ELSE OPL.LoadD(y); OPL.Op1(opRx+opSZ, 4A00H, y)  (* TST Dy *)
      END;
      TrapCC(ccLE, ZeroTrap)
    END
  END Positive;

  PROCEDURE Div(VAR x, y: OPL.Item);
    VAR rem: OPL.Item;
  BEGIN Positive(y);
    IF x.typ.form = LInt THEN
      OPL.GetD(rem); OPL.Op2(opLD+opEaRwLong, 4C400800H + rem.adr, y, x);  (* DIVSL.L y, Drem:Dx *)
      OPL.Op1(opRx+opRD, 4A80H, rem); OPL.OpW(6C02H); OPL.Op1(opRx, 5380H, x)  (* TST.L Drem; BGE +2; SUBQ.L #1, Dx *)
    ELSE
      IF y.mode # Imm THEN OPL.LoadX(y) END;
      OPL.Op2(opXLD+opEaRn, 81C0H, y, x);  (* DIVS.W y, Dx; the remainder in the high word *)
      OPL.Op1(opRxLong+opKS, 0800001FH, x); OPL.OpW(6702H); OPL.Op1(opRx, 5340H, x)  (* BTST #31, Dx; BEQ +2; SUBQ.W #1, Dx *)
    END
  END Div;

  PROCEDURE Mod(VAR x, y: OPL.Item);
    VAR rem: OPL.Item;
  BEGIN Positive(y);
    IF x.typ.form = LInt THEN
      OPL.LoadD(y); OPL.GetD(rem);
      OPL.Op2(opKS+opXLD+opEaRwLong, 4C400800H + rem.adr, y, x); OPL.Release(x); x := rem;  (* DIVSL.L Dy, Drem:Dx *)
      OPL.Op1(opRx, 4A80H, x); OPL.OpW(6C02H); OPL.Op2(opRxRy, 0D080H, y, x)  (* TST.L Drem; BGE +2; ADD.L Dy, Drem *)
    ELSE
      OPL.LoadX(y);
      OPL.Op2(opXLD+opRxRy+opKS, 81C0H, y, x);  (* DIVS.W Dy, Dx *)
      OPL.Op1(opRx, 4840H, x); OPL.Op1(opRx, 4A40H, x); OPL.OpW(6C02H);  (* SWAP Dx; TST.W Dx; BGE +2 *)
      OPL.Op2(opRxRy, 0D040H, y, x)  (* ADD.W Dy, Dx *)
    END
  END Mod;

  PROCEDURE Compare(VAR x, y: OPL.Item; rel: INTEGER);
    VAR f: INTEGER; z: OPL.Item;
  BEGIN f := x.typ.form;
    IF (x.mode = Imm) OR (x.mode # Dn) & (y.mode = Dn) THEN z := x; x := y; y := z; rel := swapRel[rel] END;
    IF x.mode = Imm THEN OPL.LoadD(x) END;  (* both constants (SYSTEM.VAL of a REAL constant) *)
    IF f IN {Byte, Char..LInt, Set, NilTyp, Pointer, ProcTyp} THEN
      IF (y.mode = Imm) & (x.mode # An) THEN
        IF y.adr = 0 THEN OPL.Op1(opEa+opSZ, 4A00H, x)  (* TST *)
        ELSE y.typ := x.typ; OPL.Op2(opImmEa+opSZ, 0C00H, y, x)  (* CMPI *)
        END
      ELSE OPL.Op2(opLD+opEaRn+opSZ, 0B000H, y, x)  (* CMP y, Dx *)
      END
    ELSIF f = Bool THEN
      IF y.mode = Imm THEN OPL.Op1(opEa, 4A00H, x);  (* TST.B x *)
        IF y.adr # OPL.false THEN rel := invRel[rel] END
      ELSE
        IF y.mode = CCR THEN z := y; y := x; OPL.GetD(x); x.typ := OPT.booltyp; OPL.ResolveCC(z, x) END;
        IF x.mode = CCR THEN z := x; OPL.GetD(x); x.typ := OPT.booltyp; OPL.ResolveCC(z, x) END;
        OPL.Op2(opLD+opEaRn, 0B000H, y, x)  (* CMP.B y, Dx *)
      END
    ELSE (* strings *)
      z := x; OPL.Ref(z); OPL.Ref(y); OPL.GetD(x);
      OPL.Op2(opRxRy+opKS, 1018H, z, x); OPL.OpW(6706H);  (* loop: MOVE.B (Az)+, Dx; BEQ +6 *)
      OPL.Op2(opRxRy+opKS, 0B018H, y, x); OPL.OpL(67F86002H);  (* CMP.B (Ay)+, Dx; BEQ loop; BRA +2 *)
      OPL.Op2(opRxRy, 0B018H, y, x); OPL.Release(z)  (* CMP.B (Ay)+, Dx *)
    END;
    IF (f IN {Char, String}) OR (x.typ.comp IN {Array, DynArr}) THEN OPL.SetCC(x, cmpCCX[rel])
    ELSE OPL.SetCC(x, cmpCC[rel])
    END
  END Compare;

(* Miscellaneous *)

  PROCEDURE Convert*(VAR x: OPL.Item; f, g: LONGINT);
    VAR y, cr: OPL.Item;
  BEGIN
    IF g IN realSet THEN
      IF f IN {Byte, Char} THEN OPL.LoadX(x); x.typ := OPT.linttyp END;
      IF (x.mode = Imm) & (f IN intSet) THEN x.typ := OPT.linttyp END;
      OPL.LoadF(x);
      IF (g = Real) & (f = LReal) THEN  (* SHORT: rounded to single precision, kept in a data register *)
        y := x; OPL.GetD(x); OPL.OpW(0F200H + x.adr); OPL.OpW(6400H + y.adr*80H); OPL.Release(y); x.typ := OPT.realtyp  (* FMOVE.S FPy, Dx *)
      END
    ELSIF f IN intSet THEN
      IF g IN intSet THEN
        IF f < g THEN OPL.LoadX(x) ELSE OPL.LoadD(x) END  (* LONG, SHORT *)
      ELSIF g IN {Char, Byte} THEN OPL.LoadD(x)
      END
    ELSIF f IN realSet THEN  (* ENTIER: rounding toward minus infinity in the FPU control register *)
      OPL.LoadF(x); y := x; OPL.GetD(x); x.typ := OPT.linttyp; OPL.GetD(cr);
      OPL.Op1(opRxLong, 0F200B000H, cr);  (* FMOVE.L FPCR, Dcr *)
      OPL.Op2(opRxRy+opKS, 2000H, cr, x);  (* MOVE.L Dcr, Dx *)
      OPL.Op1(opRxLong, 08800004H, x);  (* BCLR #4, Dx *)
      OPL.Op1(opRxLong, 08C00005H, x);  (* BSET #5, Dx: RM = toward minus infinity *)
      OPL.Op1(opRxLong, 0F2009000H, x);  (* FMOVE.L Dx, FPCR *)
      OPL.OpW(0F200H + x.adr); OPL.OpW(6000H + y.adr*80H); OPL.Release(y);  (* FMOVE.L FPy, Dx *)
      OPL.Op1(opRxLong+opRD, 0F2009000H, cr)  (* FMOVE.L Dcr, FPCR *)
    ELSIF f IN {Byte, Char} THEN
      IF g IN {LInt, Int, SInt} THEN OPL.LoadX(x) END
    END
  END Convert;

  PROCEDURE ShiftOp(VAR x, y: OPL.Item; op: INTEGER);  (* op: 0 arithmetic, 1 logical, 3 rotation *)
    VAR dir, n: LONGINT;
  BEGIN
    IF y.mode = Imm THEN n := y.adr;
      IF n # 0 THEN
        IF n > 0 THEN dir := 100H ELSE dir := 0; n := -n; y.adr := n END;
        IF n <= 8 THEN OPL.Op1(opLD+opRx+opSZ, 0E000H + (n MOD 8)*200H + dir + op*8H, x)  (* SH #y, Dx *)
        ELSE OPL.Op2(opLS+opLD+opRyRx+opSZ, 0E020H + dir + op*8H, y, x)  (* SH Dy, Dx *)
        END
      ELSE OPL.LoadD(x)
      END
    ELSE OPL.LoadD(x);
      OPL.LoadX(y); y.typ := OPT.linttyp; OPL.Op1(opRx+opSZ, 4A00H, y);  (* the count as a LONGINT; TST.L Dy *)
      OPL.OpW(6B04H); OPL.Op2(opRyRx+opSZ+opKS, 0E120H + op*8H, y, x); OPL.OpW(6004H);  (* BMI +4; LEFT Dy, Dx; BRA +4 *)
      OPL.Op1(opRx+opSZ, 4400H, y); OPL.Op2(opRyRx+opSZ, 0E020H + op*8H, y, x)  (* NEG Dy; RIGHT Dy, Dx *)
    END
  END ShiftOp;

  PROCEDURE SetRange*(VAR x, y, z: OPL.Item);  (* x := {y .. z} *)
  BEGIN OPL.GetD(x); x.typ := OPT.settyp;
    IF (y.mode = Imm) & (y.adr = 0) THEN  (* MOVEQ #-2, Dx; LSL.L z, Dx; NOT.L Dx *)
      OPL.Op1(opRy, 70FEH, x); OPL.Op2(opLS+opRyRx, 0E1A8H, z, x); OPL.Op1(opRx, 4680H, x)
    ELSE
      IF y.mode = Imm THEN y.adr := SYSTEM.LSH(LONG(LONG(-1)), y.adr); y.typ := OPT.linttyp; OPL.Move(y, x, LInt)
      ELSE OPL.Op1(opRy, 70FFH, x); OPL.Op2(opLS+opRyRx, 0E1A8H, y, x)  (* MOVEQ #-1, Dx; LSL.L Dy, Dx *)
      END;
      IF z.mode = Imm THEN
        IF z.adr # 31 THEN z.adr := -SYSTEM.LSH(LONG(LONG(-1)), z.adr + 1) - 1; z.typ := OPT.linttyp;
          OPL.Op2(opEaRn, 0C080H, z, x)  (* AND.L #mask, Dx *)
        END
      ELSE OPL.GetD(y);  (* MOVEQ #-2, Dy; LSL.L Dz, Dy; NOT.L Dy; AND.L Dy, Dx *)
        OPL.Op1(opRy, 70FEH, y); OPL.Op2(opLS+opRyRx, 0E1A8H, z, y); OPL.Op1(opRx, 4680H, y); OPL.Op2(opRxRy, 0C080H, y, x)
      END
    END
  END SetRange;

(* Heap: the calls into the Kernel; KOPV saves the registers around them *)

  PROCEDURE NewRec*(typ: OPT.Struct);  (* Kernel.NewRec(tag): ADDRESS *)
    VAR tag: OPL.Item;
  BEGIN tag.mode := GlobDes; tag.obj := typ.strobj; tag.typ := OPT.linttyp; OPL.Push(tag, LInt);
    OPL.CallExt(OPL.KNewRec); DEC(OPL.stksize, 4)
  END NewRec;

  PROCEDURE SYSnew*(VAR size: OPL.Item);  (* Kernel.NewSys(size): ADDRESS *)
  BEGIN
    IF size.typ.form # LInt THEN OPL.LoadX(size); size.typ := OPT.linttyp END;
    OPL.Push(size, LInt); OPL.CallExt(OPL.KNewSys); DEC(OPL.stksize, 4)
  END SYSnew;

  PROCEDURE NewArr*(VAR nofel: OPL.Item; typ: OPT.Struct);
    (* NEW of a POINTER TO array: typ the array type; nofel the product of the open lengths (unused for a
      static array) *)
    VAR arg, tag: OPL.Item; nofdim, nofelem: LONGINT; eltyp: OPT.Struct;
  BEGIN
    eltyp := typ.BaseTyp;
    IF typ.comp = Array THEN nofdim := 0; SetImm(nofel, typ.n)
    ELSE nofdim := typ.n + 1;
      WHILE eltyp.comp = DynArr DO eltyp := eltyp.BaseTyp END
    END;
    nofelem := 1;
    WHILE eltyp.comp = Array DO nofelem := nofelem*eltyp.n; eltyp := eltyp.BaseTyp END;
    IF nofel.typ.form # LInt THEN OPL.LoadX(nofel); nofel.typ := OPT.linttyp END;
    IF nofelem # 1 THEN SetImm(arg, nofelem); Mul(nofel, arg) END;
    IF (eltyp.comp = Record) OR (eltyp.form = Pointer) THEN
      IF eltyp.comp = Record THEN tag.mode := GlobDes; tag.obj := eltyp.strobj; tag.typ := OPT.linttyp
      ELSE SetImm(tag, 0)  (* the Kernel has the descriptor of ARRAY OF POINTER *)
      END;
      OPL.Push(tag, LInt); OPL.Push(nofel, LInt); SetImm(arg, nofdim); OPL.Push(arg, LInt);
      OPL.CallExt(OPL.KNewArr); DEC(OPL.stksize, 12)
    ELSE  (* no pointers: a system block *)
      IF eltyp.size # 1 THEN SetImm(arg, eltyp.size); Mul(nofel, arg) END;
      SetImm(arg, 8*(nofdim DIV 2) + 4 + 12); Add(nofel, arg);
      SYSnew(nofel)
    END
  END NewArr;

  PROCEDURE SetDim*(VAR p, len: OPL.Item; dimtyp: OPT.Struct);  (* LEN(p^, dimtyp.n) := len, p in an An *)
    VAR d: OPL.Item;
  BEGIN
    d.mode := RegInd; d.adr := p.adr; d.disp := 8 + 4 + 4*dimtyp.n; d.typ := OPT.linttyp; OPL.MultiRef(p);
    IF len.typ.form # LInt THEN OPL.LoadX(len) END;
    len.typ := OPT.linttyp; OPL.Move(len, d, LInt); OPL.Release(d)
  END SetDim;

  PROCEDURE CheckLen*(VAR len: OPL.Item);  (* a length for NEW: trap 8 if < 1 *)
  BEGIN
    IF ranchk & (len.mode # Imm) THEN
      OPL.LoadX(len); OPL.Op1(opRx, 4A80H, len); TrapCC(ccLE, RangeTrap)
    END
  END CheckLen;

(* Strings and blocks *)

  PROCEDURE ^Len*(VAR x, len: OPL.Item; typ: OPT.Struct);

  PROCEDURE Copy*(VAR x, y: OPL.Item);  (* COPY(y, x): until 0X, at most LEN(x) - 1 characters, then 0X *)
    VAR n: OPL.Item;
  BEGIN
    IF x.typ.comp = DynArr THEN Len(x, n, x.typ); OPL.LoadD(n) ELSE SetImm(n, x.typ.n); OPL.LoadD(n) END;
    OPL.Ref(y); OPL.Ref(x);
    OPL.OpW(5380H + n.adr); OPL.OpW(6F08H);  (* SUBQ.L #1, Dn; BLE term *)
    OPL.OpW(10D8H + x.adr*200H + y.adr); OPL.OpW(6706H);  (* loop: MOVE.B (Ay)+, (Ax)+; BEQ done *)
    OPL.OpW(5380H + n.adr); OPL.OpW(66F8H);  (* SUBQ.L #1, Dn; BNE loop *)
    OPL.OpW(4210H + x.adr);  (* term: CLR.B (Ax) *)
    OPL.Release(n); OPL.Release(x); OPL.Release(y)  (* done *)
  END Copy;

  PROCEDURE SYSmove*(VAR x, y, z: OPL.Item);  (* z bytes from address y to address x *)
    VAR c: OPL.Item;
  BEGIN OPL.LoadA(x); OPL.LoadA(y);
    IF z.mode = Imm THEN
      IF z.adr > 0 THEN OPL.GetD(c); OPL.nMove(c.adr, x.adr*200H + y.adr, z.adr); OPL.Release(c) END
    ELSE
      OPL.LoadX(z); OPL.Op1(opRx, 4A80H, z); OPL.OpW(6F06H);  (* TST.L Dz; BLE done *)
      OPL.OpW(10D8H + x.adr*200H + y.adr); OPL.Op1(opRx, 5380H, z); OPL.OpW(66FAH);  (* loop: MOVE.B (Ay)+, (Ax)+; SUBQ.L #1, Dz; BNE loop *)
      OPL.Release(z)
    END;
    OPL.Release(x); OPL.Release(y)
  END SYSmove;

(* Monadic operators *)

  PROCEDURE MOp*(VAR x: OPL.Item; op: INTEGER);
    VAR f: INTEGER; link: LONGINT; i: OPL.Item;
  BEGIN
    CASE op OF
    | conv:  (* a set element *) i := x; OPL.GetD(x); OPL.Op1(opRx, 4280H, x);  (* CLR.L Dx *)
        IF i.mode = Imm THEN OPL.Op1(opRxLong, 8C00000H + i.adr MOD 32, x)  (* BSET #i, Dx *)
        ELSE OPL.Op2(opLS+opRyRx, 1C0H, i, x)  (* BSET Di, Dx *)
        END;
        x.typ := OPT.settyp
    | not:
        IF x.mode = Imm THEN x.adr := OPL.true - x.adr
        ELSIF x.mode # CCR THEN OPL.LoadCC(x); x.code := ccEQ
        ELSE x.code := OPL.InvertCC(x.code); link := x.alpha; x.alpha := x.beta; x.beta := link
        END
    | minus: f := x.typ.form;
        IF f IN intSet THEN OPL.Op1(opLD+opRx+opSZ, 4400H, x)  (* NEG Dx *)
        ELSIF f IN realSet THEN OPL.FOp1(1AH, x)  (* FNEG *)
        ELSE OPL.Op1(opLD+opRx, 4680H, x)  (* NOT.L Dx: a set *)
        END
    | abs:
        IF x.typ.form IN realSet THEN OPL.FOp1(18H, x)  (* FABS *)
        ELSE OPL.Op1(opLD+opRx+opSZ, 4A00H, x); OPL.OpW(6C02H); OPL.Op1(opRx+opSZ, 4400H, x)  (* TST Dx; BGE +2; NEG Dx *)
        END
    | cap:  (* only "a" .. "z" change *)
        OPL.LoadD(x); OPL.Op1(opRx, 0C00H, x); OPL.OpW(61H); OPL.OpW(6D0AH);  (* CMPI.B #"a", Dx; BLT end *)
        OPL.Op1(opRx, 0C00H, x); OPL.OpW(7AH); OPL.OpW(6E04H);  (* CMPI.B #"z", Dx; BGT end *)
        OPL.Op1(opRx, 400H, x); OPL.OpW(20H)  (* SUBI.B #20H, Dx *)
    | odd: OPL.Op1(opLD+opRx, 0E208H, x); OPL.SetCC(x, ccCS)  (* LSR.B #1, Dx *)
    | adr: OPL.Ref(x); x.mode := An
    | cc: OPL.SetCC(x, SHORT(x.adr))
    | val:
    END
  END MOp;

(* Dyadic operators *)

  PROCEDURE Mem(VAR x: OPL.Item);  (* x := Mem[x] *)
  BEGIN
    IF x.mode = Imm THEN x.mode := Abs ELSE OPL.LoadA(x); x.mode := RegInd; x.disp := 0 END
  END Mem;

  PROCEDURE Switch(VAR x, y: OPL.Item);
    VAR z: OPL.Item;
  BEGIN
    IF (x.mode = Imm) OR ~(x.mode IN {Dn, Fn}) & (y.mode IN {Dn, Fn}) THEN z := x; x := y; y := z END
  END Switch;

  PROCEDURE DOp*(VAR x, y: OPL.Item; op: INTEGER);
    VAR f: INTEGER; t: OPT.Struct;
  BEGIN f := x.typ.form;
    IF (x.mode = Pop) & (y.mode = Pop) THEN OPL.LoadD(y); OPL.LoadD(x) END;
    CASE op OF
    | times:
        IF f IN realSet THEN Switch(x, y); OPL.FOp2(23H, y, x)  (* FMUL *)
        ELSE Switch(x, y);
          IF f = Set THEN OPL.Op2(opLD+opEaRn, 0C080H, y, x)  (* AND.L y, Dx *)
          ELSE Mul(x, y)
          END
        END
    | slash:
        IF f IN realSet THEN OPL.FOp2(20H, y, x)  (* FDIV *)
        ELSE OPL.Op2(opLS+opLD+opRyRx, 0B180H, y, x)  (* EOR.L Dy, Dx: a set *)
        END
    | plus:
        IF f IN realSet THEN Switch(x, y); OPL.FOp2(22H, y, x)  (* FADD *)
        ELSE Switch(x, y);
          IF f = Set THEN OPL.Op2(opLD+opEaRn, 8080H, y, x)  (* OR.L y, Dx *)
          ELSE Add(x, y)
          END
        END
    | minus:
        IF f IN realSet THEN OPL.FOp2(28H, y, x)  (* FSUB *)
        ELSIF f = Set THEN
          IF y.mode = Imm THEN y.adr := -y.adr - 1; OPL.Op2(opLD+opEaRn+opSZ, 0C000H, y, x)  (* AND #~y, Dx *)
          ELSE t := x.typ; OPL.Op1(opLD+opRx, 4680H, y); OPL.Op2(opEaRn, 0C080H, x, y); x := y; x.typ := t  (* NOT.L Dy; AND.L x, Dy *)
          END
        ELSE Sub(x, y)
        END
    | div: Div(x, y)
    | mod: Mod(x, y)
    | and: And(x, y)
    | or: Or(x, y)
    | eql .. geq:
        IF f IN realSet THEN OPL.FOp2(38H, y, x); OPL.SetCC(x, cmpCCF[op])  (* FCMP *)
        ELSE Compare(x, y, op)
        END
    | in:
        IF x.mode = Imm THEN OPL.Op1(opLD+opRxLong+opRD, 8000000H + x.adr MOD 32, y)  (* BTST #x, Dy *)
        ELSE OPL.Op2(opLS+opLD+opRyRx+opRD, 100H, x, y)  (* BTST Dx, Dy *)
        END;
        x.mode := CCR; x.code := ccNE; x.alpha := 0; x.beta := 0
    | ash:
        IF (y.mode = Imm) & (y.adr = 1) THEN OPL.Op1(opLD+opRzRz+opSZ, 0D000H, x)  (* ADD Dx, Dx *)
        ELSE ShiftOp(x, y, 0)
        END
    | msk:  (* y constant *)
        IF y.adr = MIN(LONGINT) THEN y.adr := MAX(LONGINT) ELSE y.adr := -y.adr - 1 END;
        y.typ := x.typ; OPL.Op2(opLD+opEaRn+opSZ, 0C000H, y, x)  (* AND #~y, Dx *)
    | len:  (* LEN(x, y) of an open array, y constant *)
        t := x.typ; f := SHORT(y.adr); WHILE f > 0 DO t := t.BaseTyp; DEC(f) END;
        Len(x, y, t); OPL.Release(x); x := y
    | bit: Mem(x);
        IF y.mode = Imm THEN OPL.Op1(opEaLong, 8000000H + y.adr MOD 8, x)  (* BTST #y, x *)
        ELSE OPL.Op2(opLS+opRnEa, 100H, y, x)  (* BTST Dy, x *)
        END;
        OPL.SetCC(x, ccNE)
    | lsh: ShiftOp(x, y, 1)
    | rot: ShiftOp(x, y, 3)
    END
  END DOp;

(* Assignments *)

  PROCEDURE AStat*(VAR x, y: OPL.Item; op: INTEGER);
    VAR f: INTEGER; s: OPL.Item;
  BEGIN
    CASE op OF
    | incfn: Increment(x, y)
    | decfn: Decrement(x, y)
    | inclfn:
        IF y.mode = Imm THEN y.adr := SYSTEM.LSH(LONG(LONG(1)), y.adr); y.typ := OPT.linttyp; OPL.Op2(opImmEa+opRD, 80H, y, x)  (* ORI.L *)
        ELSE s := x; OPL.MultiRef(x); OPL.Op2(opLS+opLD+opRyRx, 1C0H, y, s); OPL.Move(s, x, Set); OPL.Release(x)  (* BSET *)
        END
    | exclfn:
        IF y.mode = Imm THEN y.adr := -SYSTEM.LSH(LONG(LONG(1)), y.adr) - 1; y.typ := OPT.linttyp; OPL.Op2(opImmEa+opRD, 280H, y, x)  (* ANDI.L *)
        ELSE s := x; OPL.MultiRef(x); OPL.Op2(opLS+opLD+opRyRx, 180H, y, s); OPL.Move(s, x, Set); OPL.Release(x)  (* BCLR *)
        END
    | copyfn: Copy(x, y)
    | getrfn: OPL.GetReg(x, y.adr)
    | putrfn: OPL.PutReg(y, x.adr)
    | getfn: f := x.typ.form; Mem(y); y.typ := x.typ;
        IF f IN realSet THEN OPL.FMove(y, x) ELSE OPL.Move(y, x, f) END;
        OPL.Release(x)
    | putfn: f := y.typ.form; Mem(x); x.typ := y.typ;
        IF f IN realSet THEN OPL.FMove(y, x) ELSE OPL.Move(y, x, f) END;
        OPL.Release(x)
    END
  END AStat;

(* Designators *)

  PROCEDURE Len*(VAR x, len: OPL.Item; typ: OPT.Struct);  (* len := LEN(x, typ.n), x an open array *)
  BEGIN len.typ := OPT.linttyp;
    IF x.dheap THEN len.mode := RegInd; len.adr := x.adr; len.disp := x.descr + 4 + 4*typ.n; OPL.MultiRef(len)
    ELSE OPL.LocalVar(len, SHORT(x.alpha), x.descr + 4 + 4*typ.n, FALSE)
    END
  END Len;

  PROCEDURE Size*(VAR x, size: OPL.Item; typ: OPT.Struct);  (* size := SIZE of x, x of type typ *)
    VAR l: OPL.Item;
  BEGIN
    IF typ.comp # DynArr THEN SetImm(size, typ.size)
    ELSE Size(x, size, typ.BaseTyp); Len(x, l, typ);
      IF size.mode = Imm THEN
        IF size.adr = 1 THEN size := l; OPL.LoadD(size) ELSE OPL.Op2(opLD+opEaRwLong, 4C000800H, l, size) END
      ELSE OPL.Op2(opLD+opEaRwLong, 4C000800H, l, size)  (* MULS.L len, Dsize *)
      END
    END
  END Size;

  PROCEDURE Field*(VAR x: OPL.Item; offset: LONGINT);
  BEGIN INC(x.disp, offset)
  END Field;

  PROCEDURE DeRef*(VAR x: OPL.Item);  (* x := x^ *)
    VAR btyp: OPT.Struct;
  BEGIN
    btyp := x.typ.BaseTyp; OPL.DeRef(x);
    IF btyp.comp = DynArr THEN x.disp := btyp.size + 8 + btyp.size MOD 8; x.dheap := TRUE; x.descr := 8
    ELSIF btyp.comp = Array THEN x.disp := 16
    END
  END DeRef;

  PROCEDURE ScaleTo(VAR y: OPL.Item; e: LONGINT);  (* Dy := Dy * 2^e *)
    VAR s: OPL.Item;
  BEGIN
    IF e > 0 THEN
      IF e <= 8 THEN OPL.OpW(0E180H + (e MOD 8)*200H + y.adr)  (* ASL.L #e, Dy *)
      ELSE SetImm(s, e); OPL.Op2(opLS+opRyRx, 0E1A0H, s, y)  (* ASL.L Ds, Dy *)
      END
    END
  END ScaleTo;

  PROCEDURE Index*(VAR x, y: OPL.Item);  (* x := x[y]; y in a data register, x indexed by it *)
    VAR len, size, p: OPL.Item; artyp, eltyp: OPT.Struct; elsize, scale, e: LONGINT;
  BEGIN
    artyp := x.typ; eltyp := artyp.BaseTyp;
    IF artyp.comp = Array THEN elsize := eltyp.size;
      IF y.mode = Imm THEN INC(x.disp, y.adr*elsize); RETURN END;
      OPL.LoadX(y); y.typ := OPT.linttyp;
      IF inxchk THEN SetImm(len, artyp.n); OPL.Op2(opImmEa+opKS, 0C80H, len, y); TrapCC(ccCC, IndexTrap) END  (* CMPI.L #n, Dy; TRAPCC *)
    ELSE (* open array: the lengths are read before x changes *)
      IF (y.mode = Imm) & (y.adr = 0) THEN RETURN END;
      OPL.LoadX(y); y.typ := OPT.linttyp;
      IF inxchk THEN Len(x, len, artyp); OPL.Op2(opEaRn+opKS, 0B080H, len, y); OPL.Release(len); TrapCC(ccCC, IndexTrap) END;  (* CMP.L len, Dy; TRAPCC *)
      IF eltyp.comp = DynArr THEN  (* the size of the element from the descriptor *)
        Size(x, size, eltyp); OPL.Op2(opEaRwLong, 4C000800H, size, y); elsize := 1  (* MULS.L size, Dy *)
      ELSE elsize := eltyp.size
      END
    END;
    (* scale: 1, 2, 4, 8 in the index; other powers of 2 by a shift, other sizes by a multiplication *)
    scale := OPL.Half;
    IF elsize = 2 THEN scale := OPL.Word ELSIF elsize = 4 THEN scale := OPL.Long ELSIF elsize = 8 THEN scale := OPL.Double
    ELSIF elsize > 1 THEN e := 0; WHILE (e < 30) & (ASH(1, e) < elsize) DO INC(e) END;
      IF ASH(1, e) = elsize THEN ScaleTo(y, e)
      ELSE SetImm(size, elsize); OPL.Op2(opEaRwLong, 4C000800H, size, y)  (* MULS.L #size, Dy *)
      END
    END;
    IF x.mode = Indexed THEN  (* x[i][j]: the index registers added, in bytes *)
      ScaleTo(y, scale); scale := OPL.Half;
      p.mode := Dn; p.adr := x.inxreg; ScaleTo(p, x.beta);
      OPL.OpW(0D080H + y.adr*200H + x.inxreg); DEC(OPL.register[OPL.Dreg, x.inxreg])  (* ADD.L Dprev, Dy *)
    ELSIF x.mode # RegInd THEN OPL.Ref(x)  (* MemInd, GlobVar *)
    END;
    x.mode := Indexed; x.inxreg := SHORT(y.adr); x.beta := scale; x.code := 800H
  END Index;

  PROCEDURE FPRegOf(VAR x: OPL.Item): INTEGER;  (* the register of the frame of a VAR parameter x *)
    VAR y: OPL.Item;
  BEGIN
    IF x.mode = MemInd THEN RETURN SHORT(x.adr)
    ELSE OPL.LocalVar(y, SHORT(x.alpha), 0, FALSE); OPL.Release(y); RETURN SHORT(y.adr)
    END
  END FPRegOf;

  PROCEDURE TypTest*(VAR x: OPL.Item; testtyp: OPT.Struct; lclass: SHORTINT; guard, equal: BOOLEAN);
    (* x a record (VAR parameter or p^) or a pointer; IS: the result as a condition *)
    VAR tag, tdes: OPL.Item;
  BEGIN
    IF typchk OR ~guard THEN
      IF guard & equal THEN  (* the exact type: p^ := q^, or a VAR record parameter assigned *)
        IF lclass = Nderef THEN tag.mode := RegInd; tag.adr := x.adr; tag.disp := -4
        ELSE tag.mode := RegInd; tag.adr := FPRegOf(x); tag.disp := x.descr + 4
        END;
        OPL.MultiRef(tag); tag.typ := OPT.linttyp;
        tdes.mode := GlobDes; tdes.obj := testtyp.strobj; tdes.typ := OPT.linttyp;
        OPL.Op2(opImmEa+opRD, 0C80H, tdes, tag); TrapCC(ccNE, ITGTrap)  (* CMPI.L #td, tag; TRAPNE *)
      ELSE
        IF testtyp.comp = Record THEN  (* VAR parameter: its tag at descr+4 in the frame *)
          tag.mode := RegInd; tag.adr := FPRegOf(x); tag.disp := x.descr + 4; tag.typ := OPT.linttyp; OPL.MultiRef(tag)
        ELSE testtyp := testtyp.BaseTyp; tag := x; OPL.MultiRef(x); OPL.LoadA(tag);
          tag.mode := RegInd; tag.disp := -4; tag.typ := OPT.linttyp
        END;
        OPL.LoadA(tag); tag.mode := RegInd; tag.disp := Tag0Offset - 4*testtyp.extlev; tag.typ := OPT.linttyp;
        tdes.mode := GlobDes; tdes.obj := testtyp.strobj; tdes.typ := OPT.linttyp;
        OPL.Op2(opImmEa+opRD, 0C80H, tdes, tag);  (* CMPI.L #td, base(tag) *)
        IF guard THEN TrapCC(ccNE, TGTrap) ELSE OPL.SetCC(x, ccEQ) END
      END
    END
  END TypTest;

(* Assignment and parameters *)

  PROCEDURE Assign*(VAR x, y: OPL.Item);  (* x := y *)
    VAR f, g: INTEGER;
  BEGIN g := x.typ.form; f := y.typ.form;
    IF (f # g) & (g <= LReal) & (y.mode # Imm) THEN Convert(y, f, g) END;
    IF (f # g) & (g IN realSet) & (y.mode = Imm) & (f IN intSet) THEN Convert(y, f, g) END;
    CASE g OF
    | Bool: IF y.mode = CCR THEN OPL.ResolveCC(y, x) ELSE OPL.Move(y, x, Bool) END
    | Byte, Char, SInt, Int, LInt, Set, NilTyp, Pointer, ProcTyp: OPL.Move(y, x, g)
    | Real, LReal: OPL.FMove(y, x)
    | Comp: IF f = String THEN OPL.BlkMove(y, x, y.beta) ELSE OPL.BlkMove(y, x, x.typ.size) END
    END;
    OPL.Release(x)
  END Assign;

  PROCEDURE PushLen(VAR l: OPL.Item);
  BEGIN
    IF l.typ.form # LInt THEN l.typ := OPT.linttyp END;
    OPL.Push(l, LInt)
  END PushLen;

  PROCEDURE DynArrBnd(VAR ap: OPL.Item; ftyp, atyp: OPT.Struct);
    (* the lengths of an open array parameter, the outermost first *)
    VAR l: OPL.Item;
  BEGIN
    IF ftyp.BaseTyp = OPT.bytetyp THEN  (* ARRAY OF SYSTEM.BYTE: the size in bytes *)
      Size(ap, l, atyp); PushLen(l)
    ELSE
      IF atyp.comp = Array THEN SetImm(l, atyp.n) ELSE Len(ap, l, atyp) END;
      PushLen(l);
      IF ftyp.BaseTyp.comp = DynArr THEN DynArrBnd(ap, ftyp.BaseTyp, atyp.BaseTyp) END
    END
  END DynArrBnd;

  PROCEDURE Param*(VAR ap: OPL.Item; fp: OPT.Object; class: SHORTINT);
    (* ap pushed for the formal parameter fp; the parameters are pushed in their order *)
    VAR f, g: INTEGER; tag, l: OPL.Item; ftyp: OPT.Struct;
  BEGIN ftyp := fp.typ; f := ftyp.comp;
    IF f = DynArr THEN  (* the lengths, then the address *)
      IF ap.typ.form = String THEN SetImm(l, ap.beta); PushLen(l)
      ELSIF (ftyp.BaseTyp = OPT.bytetyp) & (ap.typ.comp # DynArr) & (ap.typ.comp # Array) THEN SetImm(l, ap.typ.size); PushLen(l)
      ELSE DynArrBnd(ap, ftyp, ap.typ)
      END;
      OPL.RefToStk(ap)
    ELSIF fp.mode = VarPar THEN
      IF f = Record THEN  (* the tag, then the address *)
        IF class = Nvarpar THEN tag.mode := RegInd; tag.adr := FPRegOf(ap); tag.disp := ap.descr + 4; OPL.MultiRef(tag)
        ELSIF class = Nderef THEN tag.mode := RegInd; tag.adr := ap.adr; tag.disp := -4; OPL.MultiRef(tag)
        ELSE tag.mode := GlobDes; tag.obj := ap.typ.strobj
        END;
        tag.typ := OPT.linttyp; OPL.Push(tag, LInt)
      END;
      OPL.RefToStk(ap)
    ELSIF f IN {Record, Array} THEN OPL.RefToStk(ap)  (* the callee copies it *)
    ELSE g := ftyp.form; f := ap.typ.form;
      IF (f # g) & (g <= LReal) & (ap.mode # Imm) OR (g IN realSet) & (f IN intSet) THEN Convert(ap, f, g) END;
      CASE g OF
      | Bool:
          IF ap.mode = CCR THEN OPL.Push(ap, Bool) ELSE OPL.Push(ap, Bool) END
      | Byte, Char, SInt, Int, LInt, Set, NilTyp, Pointer, ProcTyp: OPL.Push(ap, g)
      | Real, LReal: OPL.FPush(ap, g)
      END
    END
  END Param;

(* Procedures *)

  PROCEDURE CallPV*(VAR x: OPL.Item);  (* a procedure variable *)
  BEGIN OPL.LoadA(x); OPL.Op1(opRx+opRD, 4E90H, x); x.typ := x.typ.BaseTyp  (* JSR (Ax) *)
  END CallPV;

  PROCEDURE MoveQ(n: LONGINT);  (* D0 := n *)
  BEGIN
    IF (n >= -80H) & (n < 80H) THEN OPL.OpW(7000H + n MOD 100H) ELSE OPL.OpW(203CH); OPL.OpL(n) END
  END MoveQ;

  PROCEDURE CopyPar*(adr, size: LONGINT);  (* a record or array value parameter onto the stack, below the frame *)
    VAR s: LONGINT;
  BEGIN
    INC(size, (-size) MOD 4);
    IF size > 0 THEN s := OPL.stksize; OPL.ADDA(-size, 7); OPL.stksize := s;  (* UNLK removes it *)
      OPL.OpW(206EH); OPL.OpW(adr); OPL.OpW(2D4FH); OPL.OpW(adr); OPL.OpW(224FH);  (* MOVEA.L adr(A6), A0; MOVE.L A7, adr(A6); MOVEA.L A7, A1 *)
      MoveQ(size DIV 4);
      OPL.OpW(22D8H); OPL.OpW(5380H); OPL.OpW(66FAH)  (* loop: MOVE.L (A0)+, (A1)+; SUBQ.L #1, D0; BNE loop *)
    END
  END CopyPar;

  PROCEDURE CopyDynArray*(adr: LONGINT; typ: OPT.Struct);  (* an open array value parameter onto the stack *)
    VAR x, size: OPL.Item;
  BEGIN
    OPL.LocalVar(x, OPL.level, adr, TRUE); x.typ := typ; Size(x, size, typ); OPL.Release(x);
    OPL.LoadD(size);  (* no other register is in use at the entry *)
    IF size.adr # 0 THEN OPL.OpW(2000H + size.adr) END;  (* MOVE.L Dsize, D0 *)
    OPL.Release(size);
    OPL.OpW(5680H); OPL.OpW(0C0BCH); OPL.OpL(-4); OPL.OpW(9FC0H);  (* ADDQ.L #3, D0; AND.L #-4, D0; SUBA.L D0, A7 *)
    OPL.OpW(206EH); OPL.OpW(adr); OPL.OpW(2D4FH); OPL.OpW(adr); OPL.OpW(224FH);  (* MOVEA.L adr(A6), A0; MOVE.L A7, adr(A6); MOVEA.L A7, A1 *)
    OPL.OpW(0E488H); OPL.OpW(6706H);  (* LSR.L #2, D0; BEQ done *)
    OPL.OpW(22D8H); OPL.OpW(5380H); OPL.OpW(66FAH)  (* loop: MOVE.L (A0)+, (A1)+; SUBQ.L #1, D0; BNE loop *)
  END CopyDynArray;

  PROCEDURE EnterProc*(proc: OPT.Object; dsize: LONGINT);  (* dsize: the size of the local variables, even *)
    CONST MaxPtrs = 16;
    VAR var: OPT.Object; ptrTab: ARRAY MaxPtrs + 1 OF LONGINT; n, i: INTEGER;
  BEGIN
    IF proc # NIL THEN OPL.FixProc(proc) END;
    IF dsize <= 8000H THEN OPL.OpW(4E56H); OPL.OpW(-dsize)  (* LINK.W A6, #-dsize *)
    ELSE OPL.OpW(480EH); OPL.OpL(-dsize)  (* LINK.L A6, #-dsize *)
    END;
    n := 0;
    IF ptrinit & (dsize > 0) & (proc # NIL) THEN  (* the pointers among the local variables, as in the other ROP2 back ends *)
      var := proc.scope.scope;
      WHILE (var # NIL) & (n <= MaxPtrs) DO OPL.FindPtrs(var.typ, var.adr, ptrTab, n); var := var.link END;
      IF (n <= MaxPtrs) & (dsize <= 8000H) THEN
        i := 0; WHILE i < n DO OPL.OpW(42AEH); OPL.OpW(ptrTab[i]); INC(i) END;  (* CLR.L ptr(A6) *)
        dsize := 0
      END
    END;
    IF ptrinit & (dsize > 0) & ((proc = NIL) OR (n > 0)) THEN  (* many pointers: the whole frame *)
      IF dsize <= 4*4 THEN
        WHILE dsize >= 4 DO OPL.OpW(42AEH); OPL.OpW(-dsize); DEC(dsize, 4) END;  (* CLR.L -dsize(A6) *)
        IF dsize > 0 THEN OPL.OpW(426EH); OPL.OpW(-dsize) END  (* CLR.W -dsize(A6) *)
      ELSE
        OPL.OpW(204FH);  (* MOVEA.L A7, A0 *)
        MoveQ(dsize DIV 4);
        OPL.OpW(4298H); OPL.OpW(5380H); OPL.OpW(66FAH);  (* loop: CLR.L (A0)+; SUBQ.L #1, D0; BNE loop *)
        IF ODD(dsize DIV 2) THEN OPL.OpW(4250H) END  (* CLR.W (A0) *)
      END
    END
  END EnterProc;

  PROCEDURE ReturnFromProc*(proc: OPT.Object; psize: LONGINT; result: BOOLEAN; VAR res: OPL.Item);
    VAR r: OPL.Item; f: INTEGER;
  BEGIN
    IF result THEN f := proc.typ.form; r.typ := proc.typ;
      IF (res.mode # CCR) & (res.typ.form # f) & (f <= LReal) & ((res.mode # Imm) OR (f IN realSet)) THEN
        Convert(res, res.typ.form, f)  (* as in an assignment *)
      END;
      IF f IN realSet THEN
        IF (res.mode = Fn) & (res.adr = 0) THEN OPL.Release(res)
        ELSE r.mode := Fn; r.adr := 0; INC(OPL.register[OPL.Freg, 0]); OPL.FMove(res, r); OPL.Release(r)
        END
      ELSIF (res.mode = Dn) & (res.adr = 0) THEN OPL.Release(res)
      ELSE r.mode := Dn; r.adr := 0; INC(OPL.register[OPL.Dreg, 0]);
        IF res.mode = CCR THEN OPL.ResolveCC(res, r) ELSE OPL.Move(res, r, f) END;
        OPL.Release(r)
      END
    END;
    OPL.OpW(4E5EH);  (* UNLK A6 *)
    IF psize = 8 THEN OPL.OpW(4E75H) ELSE OPL.OpW(4E74H); OPL.OpW(psize - 8) END  (* RTS, RTD #n *)
  END ReturnFromProc;

  PROCEDURE ReturnFromMod*;
  BEGIN OPL.OpW(4E5EH); OPL.OpW(4E75H)  (* UNLK A6; RTS *)
  END ReturnFromMod;

  PROCEDURE Case*(VAR x: OPL.Item; low, high: LONGINT; VAR tab: LONGINT; VAR L, Lelse: OPL.Label);
    (* the jump into a table of word offsets; L the table, Lelse the jumps to the else part *)
    VAR y: OPL.Item;
  BEGIN
    OPL.LoadX(x); x.typ := OPT.linttyp; Lelse := 0;
    IF low # 0 THEN SetImm(y, low); Sub(x, y) END;
    SetImm(y, high - low); OPL.Op2(opImmEa, 0C80H, y, x); OPL.BccLink(ccHI, Lelse);  (* CMPI.L #high-low, Dx; BHI else *)
    OPL.OpW(303BH + x.adr*200H); OPL.OpW(x.adr*1000H + 800H + 200H + 6);  (* MOVE.W 6(PC, Dx.L*2), Dx *)
    OPL.OpW(4EFBH); OPL.OpW(x.adr*1000H + 2);  (* JMP 2(PC, Dx.W) *)
    OPL.Release(x);
    L := OPL.pc; OPL.AllocCaseTab(high - low + 1, tab)
  END Case;

  PROCEDURE Init*(opt: SET);
    CONST inx = 0; ran = 2; typ = 3; ptr = 5;
  BEGIN
    inxchk := inx IN opt; ranchk := ran IN opt; typchk := typ IN opt; ptrinit := ptr IN opt
  END Init;

BEGIN
  cmpCC[eql] := ccEQ; cmpCC[neq] := ccNE; cmpCC[lss] := ccLT; cmpCC[leq] := ccLE; cmpCC[gtr] := ccGT; cmpCC[geq] := ccGE;
  cmpCCX[eql] := ccEQ; cmpCCX[neq] := ccNE; cmpCCX[lss] := ccCS; cmpCCX[leq] := ccLS; cmpCCX[gtr] := ccHI; cmpCCX[geq] := ccCC;
  cmpCCF[eql] := ccfEQ; cmpCCF[neq] := ccfNE; cmpCCF[lss] := ccfLT; cmpCCF[leq] := ccfLE; cmpCCF[gtr] := ccfGT; cmpCCF[geq] := ccfGE;
  swapRel[eql] := eql; swapRel[neq] := neq; swapRel[lss] := gtr; swapRel[leq] := geq; swapRel[gtr] := lss; swapRel[geq] := leq;
  invRel[eql] := neq; invRel[neq] := eql
END KOPC.
