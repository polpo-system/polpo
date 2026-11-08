MODULE KOPV;  (* Copyright (c) Michael Franz, 1989-95 / mf 17.8.95 / se 10 Apr 97 *)
(* tree walker of the Motorola 68020 back end
  polpo: made from aOPV of ST-Oberon V4 (see KOPL), on the ROP2 front end; the storage allocation as in
  the other ROP2 back ends (VOPV), with the frame of KOPL:
  - parameters at positive offsets from A6, the first one highest; a nested procedure has the static link
    at 8(A6); sizes: 8 for LONGREAL, 4 for the others (a 1- or 2-byte value at the start of its 4 bytes:
    the stack stays aligned to 4); a VAR record its
    address and tag (8), an open array its descriptor (address and lengths), a record or array value
    parameter its address (the procedure copies it at its start);
  - local variables at negative offsets, global ones at negative offsets from sb. *)

  IMPORT OPM := ROPM, OPT := ROPT, OPL := KOPL, OPC := KOPC, SYSTEM;

  CONST
    (* object modes *)
    Var = 1; VarPar = 2; Con = 3; Fld = 4; Typ = 5; LProc = 6; XProc = 7;
    SProc = 8; CProc = 9; IProc = 10; Mod = 11; Head = 12; TProc = 13;

    (* symbol values and ops *)
    times = 1; slash = 2; div = 3; mod = 4; and = 5; plus = 6; minus = 7; or = 8; eql = 9;
    neq = 10; lss = 11; leq = 12; gtr = 13; geq = 14; in = 15; is = 16; ash = 17; msk = 18; len = 19;
    conv = 20; abs = 21; cap = 22; odd = 23; not = 33;
    adr = 24; cc = 25; bit = 26; lsh = 27; rot = 28; val = 29;

    (* structure forms *)
    Undef = 0; Byte = 1; Bool = 2; Char = 3; SInt = 4; Int = 5; LInt = 6;
    Real = 7; LReal = 8; Set = 9; String = 10; NilTyp = 11; NoTyp = 12;
    Pointer = 13; ProcTyp = 14; Comp = 15;
    Basic = 1; Array = 2; DynArr = 3; Record = 4;
    realSet = {Real, LReal};

    (* node classes *)
    Nvar = 0; Nvarpar = 1; Nfield = 2; Nderef = 3; Nindex = 4; Nguard = 5; Neguard = 6;
    Nconst = 7; Ntype = 8; Nproc = 9; Nupto = 10; Nmop = 11; Ndop = 12; Ncall = 13;
    Ninittd = 14; Nif = 15; Ncaselse = 16; Ncasedo = 17; Nenter = 18; Nassign = 19;
    Nifelse = 20; Ncase = 21; Nwhile = 22; Nrepeat = 23; Nloop = 24; Nexit = 25;
    Nreturn = 26; Nwith = 27; Ntrap = 28; Ncode = 30;

    (* function numbers *)
    assign = 0; newfn = 1; incfn = 13; decfn = 14; inclfn = 15; exclfn = 16; copyfn = 18;
    getfn = 24; putfn = 25; getrfn = 26; putrfn = 27; sysnewfn = 30; movefn = 31;

    (* procedure flags (conval.setval) *)
    hasBody = 1; isRedef = 2;

    (* item modes *)
    Dn = 14; An = 15; Fn = 16; RegInd = 17; MemInd = 18; GlobVar = 20; GlobProc = 23; Imm = 27; CCR = 28;

    WithTrap = 14; CaseTrap = 16; FuncTrap = 17;
    MaxMarks = 8192;  (* statements of a procedure for /f *)
    MaxCaseRange = 2048;

  VAR
    ExitChain: OPL.Label;
    findpc: BOOLEAN;
    nmarks: LONGINT; markPc, markPos: ARRAY MaxMarks OF LONGINT;

(* Storage allocation *)

  PROCEDURE Align(VAR offset: LONGINT; align: LONGINT);
  BEGIN
    IF align > 1 THEN INC(offset, (-offset) MOD align) END
  END Align;

  PROCEDURE NegAlign(VAR offset: LONGINT; align: LONGINT);
  BEGIN
    IF align > 1 THEN DEC(offset, offset MOD align) END
  END NegAlign;

  PROCEDURE Base(typ: OPT.Struct): LONGINT;  (* typ.comp # DynArr *)
  BEGIN
    WHILE typ.comp = Array DO typ := typ.BaseTyp END;
    IF typ.comp = Record THEN RETURN typ.align ELSE RETURN typ.size END
  END Base;

  PROCEDURE TypeSize*(typ: OPT.Struct);  (* also called from OPT.InStruct for arrays *)
    VAR f, c: INTEGER; offset, size, align, falign: LONGINT; fld: OPT.Object; btyp: OPT.Struct;
  BEGIN
    IF typ = OPT.undftyp THEN OPM.err(58)
    ELSIF typ.size = -1 THEN
      f := typ.form; c := typ.comp; btyp := typ.BaseTyp;
      IF c = Record THEN
        IF btyp = NIL THEN offset := 0; align := 1
        ELSE TypeSize(btyp); offset := btyp.size; align := btyp.align
        END;
        fld := typ.link;
        WHILE (fld # NIL) & (fld.mode = Fld) DO
          btyp := fld.typ; TypeSize(btyp);
          size := btyp.size; falign := Base(btyp); Align(offset, falign);
          fld.adr := offset; INC(offset, size);
          IF falign > align THEN align := falign END;
          fld := fld.link
        END;
        typ.align := align;
        Align(offset, Base(typ)); typ.size := offset;
        typ.n := -1  (* methods not counted yet *)
      ELSIF c = Array THEN TypeSize(btyp); typ.size := typ.n * btyp.size
      ELSIF f = Pointer THEN typ.size := OPM.PointerSize
      ELSIF f = ProcTyp THEN typ.size := OPM.ProcSize
      ELSE (* DynArr: address and lengths *)
        TypeSize(btyp);
        IF btyp.comp = DynArr THEN typ.size := btyp.size + 4 ELSE typ.size := 8 END
      END
    END
  END TypeSize;

  PROCEDURE ^Parameters(firstPar, proc: OPT.Object);
  PROCEDURE ^TProcedures(obj: OPT.Object);

  PROCEDURE CountTProcs(rec: OPT.Struct);
    VAR btyp: OPT.Struct;

    PROCEDURE TProcs(obj: OPT.Object);
      VAR redef: OPT.Object;
    BEGIN
      IF obj # NIL THEN
        TProcs(obj.left);
        IF obj.mode = TProc THEN
          OPT.FindField(obj.name, rec.BaseTyp, redef);
          IF redef # NIL THEN obj.adr := 10000H*(redef.adr DIV 10000H);
            IF ~(isRedef IN obj.conval.setval) THEN OPM.err(119) END
          ELSE obj.adr := 10000H*rec.n; INC(rec.n)
          END;
          IF ~(hasBody IN obj.conval.setval) THEN OPM.err(129) END
        END;
        TProcs(obj.right)
      END
    END TProcs;

  BEGIN
    IF rec.n = -1 THEN
      rec.n := 0; btyp := rec.BaseTyp;
      IF btyp # NIL THEN CountTProcs(btyp); rec.n := btyp.n END;
      TProcs(rec.link)
    END
  END CountTProcs;

  PROCEDURE TypeAlloc(typ: OPT.Struct);
    VAR f, c: INTEGER; fld: OPT.Object; btyp: OPT.Struct;
  BEGIN
    IF ~typ.allocated THEN
      typ.allocated := TRUE;
      TypeSize(typ);
      f := typ.form; c := typ.comp; btyp := typ.BaseTyp;
      IF c = Record THEN
        CountTProcs(typ); OPL.AllocTypDesc(typ);
        IF btyp # NIL THEN TypeAlloc(btyp) END;
        fld := typ.link;
        WHILE (fld # NIL) & (fld.mode = Fld) DO TypeAlloc(fld.typ); fld := fld.link END;
        TProcedures(typ.link)
      ELSIF f = Pointer THEN
        IF btyp = OPT.undftyp THEN OPM.Mark(128, typ.txtpos) ELSE TypeAlloc(btyp) END
      ELSIF f = ProcTyp THEN TypeAlloc(btyp); Parameters(typ.link, NIL)
      ELSE TypeAlloc(btyp)
      END
    END
  END TypeAlloc;

  PROCEDURE ParSize(par: OPT.Object): LONGINT;  (* the bytes a parameter takes on the stack *)
    VAR typ: OPT.Struct;
  BEGIN typ := par.typ;
    IF typ.comp = DynArr THEN RETURN typ.size
    ELSIF par.mode = VarPar THEN
      IF typ.comp = Record THEN RETURN 8 ELSE RETURN 4 END
    ELSIF typ.comp IN {Record, Array} THEN RETURN 4
    ELSIF typ.form = LReal THEN RETURN 8
    ELSE RETURN 4
    END
  END ParSize;

  PROCEDURE Parameters(firstPar, proc: OPT.Object);
    VAR par: OPT.Object; total, cum: LONGINT;
  BEGIN
    total := 0; par := firstPar;
    WHILE par # NIL DO TypeAlloc(par.typ); INC(total, ParSize(par)); par := par.link END;
    IF (proc # NIL) & (proc.mnolev > 0) THEN INC(total, 12) ELSE INC(total, 8) END;
    cum := 0; par := firstPar;
    WHILE par # NIL DO INC(cum, ParSize(par)); par.adr := total - cum; par.linkadr := par.adr; par := par.link END;
    IF proc # NIL THEN proc.conval.intval := total END
  END Parameters;

  PROCEDURE Variables(var: OPT.Object; VAR varSize: LONGINT);  (* negative offsets *)
    VAR adr, a: LONGINT;
  BEGIN adr := varSize;
    WHILE var # NIL DO
      TypeAlloc(var.typ); a := Base(var.typ); IF a > 4 THEN a := 4 END;
      NegAlign(adr, a); DEC(adr, var.typ.size); var.adr := adr; var.linkadr := adr;
      var := var.link
    END;
    NegAlign(adr, 4); varSize := adr
  END Variables;

  PROCEDURE ^Objects(obj: OPT.Object);

  PROCEDURE Procedure(obj: OPT.Object);
    VAR oldPos, size: LONGINT;
  BEGIN
    oldPos := OPM.errpos; OPM.errpos := obj.scope.adr;
    TypeAlloc(obj.typ);
    Parameters(obj.link, obj);
    IF ~(hasBody IN obj.conval.setval) THEN OPM.err(129) END;
    size := 0; Variables(obj.scope.scope, size); obj.conval.intval2 := -size;
    Objects(obj.scope.right);
    OPM.errpos := oldPos
  END Procedure;

  PROCEDURE TProcedures(obj: OPT.Object);
  BEGIN
    IF obj # NIL THEN
      TProcedures(obj.left);
      IF obj.mode = TProc THEN OPM.err(700) END;  (* type-bound procedures are not supported by the ROP2 back ends *)
      TProcedures(obj.right)
    END
  END TProcedures;

  PROCEDURE Objects(obj: OPT.Object);
  BEGIN
    IF obj # NIL THEN
      Objects(obj.left);
      IF obj.mode IN {Con, Typ} THEN TypeAlloc(obj.typ)
      ELSIF obj.mode IN {LProc, XProc, CProc, IProc} THEN Procedure(obj)
      END;
      Objects(obj.right)
    END
  END Objects;

  PROCEDURE Allocate*;
  BEGIN
    OPM.errpos := OPT.topScope.adr;
    Variables(OPT.topScope.scope, OPL.sb); NegAlign(OPL.sb, 8);  (* the loader rounds the size of the variables up to 8 *)
    Objects(OPT.topScope.right)
  END Allocate;

(* Expressions *)

  PROCEDURE ^expr(n: OPT.Node; VAR x: OPL.Item);
  PROCEDURE ^Call(n: OPT.Node; VAR x: OPL.Item);

  PROCEDURE design(n: OPT.Node; VAR x: OPL.Item);
    VAR obj: OPT.Object; y: OPL.Item;
  BEGIN
    x.dheap := FALSE;
    CASE n.class OF
    | Nvar: obj := n.obj;
        IF obj.mnolev <= 0 THEN x.mode := GlobVar; x.disp := 0; x.safe := TRUE;
          IF obj.mnolev = 0 THEN x.adr := obj.adr; x.obj := OPL.GlobData ELSE x.adr := 0; x.obj := obj END
        ELSE
          OPL.LocalVar(x, obj.mnolev, obj.adr, (obj.adr > 0) & (obj.typ.comp IN {Record, Array, DynArr}))
        END
    | Nvarpar: OPL.LocalVar(x, n.obj.mnolev, n.obj.adr, TRUE)
    | Nfield: design(n.left, x); OPC.Field(x, n.obj.adr)
    | Nderef:  (* also the pointer a function returns, as the front end makes for HUGEINT *)
        IF n.left.class = Ncall THEN expr(n.left, x) ELSE design(n.left, x) END;
        x.typ := n.left.typ; OPC.DeRef(x)
    | Nindex: design(n.left, x); expr(n.right, y); OPC.Index(x, y)
    | Nguard: design(n.left, x); OPC.TypTest(x, n.typ, 0, TRUE, FALSE)
    | Neguard: design(n.left, x); OPC.TypTest(x, n.typ, n.left.class, TRUE, TRUE)
    | Nproc: obj := n.obj; x.mode := GlobProc; x.obj := obj; x.adr := 0
    END;
    x.typ := n.typ
  END design;

  PROCEDURE ActualPar(n: OPT.Node; fp: OPT.Object);  (* pushed in their order *)
    VAR ap: OPL.Item; c: SHORTINT;
  BEGIN
    WHILE (n # NIL) & (fp # NIL) DO
      expr(n, ap);
      IF n.class = Nguard THEN c := n.left.class ELSE c := n.class END;
      OPC.Param(ap, fp, c);
      n := n.link; fp := fp.link
    END
  END ActualPar;

  PROCEDURE Call(n: OPT.Node; VAR x: OPL.Item);
    VAR proc: OPT.Object; restyp: OPT.Struct; regs: OPL.RegSet; before: LONGINT;
  BEGIN
    restyp := n.typ; OPL.SaveRegisters(regs);
    IF n.left.class = Nproc THEN proc := n.left.obj;
      IF proc.mode = TProc THEN OPM.err(700) END;
      before := OPL.stksize; ActualPar(n.right, n.obj); OPL.Call(OPL.stksize - before, proc)
    ELSE design(n.left, x);
      before := OPL.stksize; ActualPar(n.right, n.obj);
      OPC.CallPV(x); DEC(OPL.stksize, OPL.stksize - before)
    END;
    OPL.Result(x, restyp); OPL.RestoreRegisters(regs, x)
  END Call;

  PROCEDURE SYSval(VAR x: OPL.Item; f, g: INTEGER);  (* SYSTEM.VAL: the bits of x as a value of form g *)
    VAR y: OPL.Item;
  BEGIN
    IF x.mode = CCR THEN OPC.Relation(x) END;
    IF (x.mode = Fn) & ~(g IN realSet) THEN
      y := x; OPL.GetD(x);
      IF f = Real THEN OPL.OpW(0F200H + x.adr); OPL.OpW(6400H + y.adr*80H)  (* FMOVE.S FPy, Dx *)
      ELSE OPM.err(126)
      END;
      OPL.Release(y)
    END
  END SYSval;

  PROCEDURE expr(n: OPT.Node; VAR x: OPL.Item);
    VAR y, z: OPL.Item; f, g: SHORTINT; cval: OPT.Const; r: REAL;
  BEGIN
    x.dheap := FALSE;
    CASE n.class OF
    | Nconst: x.mode := Imm; cval := n.conval; x.typ := n.typ;
        CASE n.typ.form OF
        | Bool: IF cval.intval = 0 THEN x.adr := OPL.false ELSE x.adr := OPL.true END
        | Byte, Char, SInt, Int, LInt, NilTyp, Pointer, ProcTyp: x.adr := cval.intval
        | Set: x.adr := SYSTEM.VAL(LONGINT, cval.setval)
        | Real: r := SHORT(cval.realval); x.adr := SYSTEM.VAL(LONGINT, r)
        | LReal: OPL.LRealWords(cval.realval, x.adr, x.disp)
        | String:
            IF (n.obj = NIL) OR (n.obj.conval.intval = OPM.ConstNotAlloc) THEN
              OPL.AllocString(cval.ext^, cval.intval2, x.adr);
              IF n.obj # NIL THEN n.obj.conval.intval := x.adr END
            ELSE x.adr := n.obj.conval.intval
            END;
            x.mode := GlobVar; x.disp := 0; x.obj := OPL.GlobData; x.beta := cval.intval2
        END
    | Nupto: expr(n.left, y); expr(n.right, z); OPC.SetRange(x, y, z)
    | Nmop: expr(n.left, x);
        CASE n.subcl OF
        | is: OPC.TypTest(x, n.obj.typ, 0, FALSE, FALSE)
        | conv: f := x.typ.form; g := n.typ.form;
            IF g = Set THEN OPC.MOp(x, conv) ELSE OPC.Convert(x, f, g) END
        | val: SYSval(x, x.typ.form, n.typ.form)
        ELSE OPC.MOp(x, n.subcl)
        END
    | Ndop: expr(n.left, x);
        IF n.subcl = and THEN OPC.CondAnd(x)
        ELSIF n.subcl = or THEN OPC.CondOr(x)
        ELSE OPC.Relation(x)
        END;
        expr(n.right, y);
        IF (n.subcl # and) & (n.subcl # or) THEN OPC.Relation(y) END;
        OPC.DOp(x, y, n.subcl)
    | Ncall: Call(n, x)
    ELSE design(n, x)
    END;
    x.typ := n.typ
  END expr;

(* Statements *)

  PROCEDURE Checkpc;
  BEGIN
    IF findpc & (nmarks < MaxMarks) THEN markPc[nmarks] := OPL.pc; markPos[nmarks] := OPM.errpos; INC(nmarks) END
  END Checkpc;

  PROCEDURE Found;  (* /f: the first statement of the procedure whose code ends after the pc *)
    VAR i, at: LONGINT;
  BEGIN
    IF findpc & (OPL.pc > OPM.breakpc DIV 2) & OPM.noerr & (nmarks > 0) THEN
      at := OPM.breakpc DIV 2; i := 0;
      WHILE (i < nmarks - 1) & (markPc[i] <= at) DO INC(i) END;
      OPM.Mark(255, markPos[i])
    END;
    nmarks := 0
  END Found;

  PROCEDURE ^stat(n: OPT.Node);

  PROCEDURE IfStat(n: OPT.Node; withtrap: BOOLEAN);
    VAR x: OPL.Item; Lcfj, Lfix: OPL.Label; if: OPT.Node;
  BEGIN Lfix := 0; if := n.left;
    LOOP OPM.errpos := if.conval.intval; expr(if.left, x); OPL.CFJ(x, Lcfj); Checkpc; stat(if.right); if := if.link;
      IF if = NIL THEN EXIT END;
      OPL.FJ(Lfix); OPL.FixLink(Lcfj)
    END;
    IF (n.right # NIL) OR withtrap THEN OPL.FJ(Lfix); OPL.FixLink(Lcfj);
      IF withtrap THEN OPC.Trap(WithTrap); OPM.errpos := n.conval.intval; Checkpc ELSE stat(n.right) END
    ELSE OPL.FixLink(Lcfj)
    END;
    OPL.FixLink(Lfix)
  END IfStat;

  PROCEDURE CaseStat(n: OPT.Node);
    VAR x: OPL.Item; Lfix, L, Lelse: OPL.Label; case, lab: OPT.Node; tab, low, high: LONGINT;
  BEGIN
    expr(n.left, x); low := n.right.conval.intval; high := n.right.conval.intval2;
    IF high - low >= MaxCaseRange THEN OPM.err(209); high := low END;
    OPC.Case(x, low, high, tab, L, Lelse); Checkpc; Lfix := 0;
    OPL.FixLink(Lelse); OPL.CaseJump(L, tab, 0, high - low);
    IF n.right.conval.setval # {} THEN stat(n.right.right); OPL.FJ(Lfix) ELSE OPC.Trap(CaseTrap) END;
    case := n.right.left;
    WHILE case # NIL DO lab := case.left;
      WHILE lab # NIL DO OPL.CaseJump(L, tab, lab.conval.intval - low, lab.conval.intval2 - low); lab := lab.link END;
      stat(case.right); OPL.FJ(Lfix); case := case.link
    END;
    OPL.FixLink(Lfix)
  END CaseStat;

  PROCEDURE Enter(n: OPT.Node);
    VAR x: OPL.Item; proc, par: OPT.Object; name: ARRAY 64 OF CHAR;
  BEGIN
    proc := n.obj;
    IF proc = NIL THEN  (* the module body, at the start of the code *)
      nmarks := 0; OPC.EnterProc(NIL, 0); stat(n.right); OPC.ReturnFromMod; Found;
      OPL.TestRegs; OPL.TestStack;
      name := "$$"; OPL.OutRefPoint; OPL.OutRefName(name); OPL.OutRefs(OPT.topScope);
      INC(OPL.level); stat(n.left); DEC(OPL.level)
    ELSE
      INC(OPL.level); stat(n.left); DEC(OPL.level);
      IF proc.mode = TProc THEN OPM.err(700)
      ELSE
        nmarks := 0; OPC.EnterProc(proc, proc.conval.intval2);
        par := proc.link;
        WHILE par # NIL DO
          IF par.mode = Var THEN
            IF par.typ.comp = DynArr THEN OPC.CopyDynArray(par.adr, par.typ)
            ELSIF par.typ.comp IN {Record, Array} THEN OPC.CopyPar(par.adr, par.typ.size)
            END
          END;
          par := par.link
        END;
        stat(n.right);
        IF proc.typ # OPT.notyp THEN OPC.Trap(FuncTrap)
        ELSE OPC.ReturnFromProc(proc, proc.conval.intval, FALSE, x)
        END;
        Found; OPL.TestRegs; OPL.TestStack;
        COPY(proc.name, name); OPL.OutRefPoint; OPL.OutRefName(name); OPL.OutRefs(proc.scope.right)
      END
    END
  END Enter;

  PROCEDURE NewStat(n: OPT.Node);  (* NEW(p), NEW(p, len0, len1 ...) *)
    VAR x, y, p, nofel, l: OPL.Item; regs: OPL.RegSet; btyp, dimtyp: OPT.Struct;
      lens: ARRAY 32 OF OPL.Item; nlen, i: LONGINT; e: OPT.Node;
  BEGIN
    expr(n.left, x); btyp := x.typ.BaseTyp;
    IF btyp.comp = Record THEN
      OPL.SaveRegisters(regs); OPC.NewRec(btyp); OPL.Result(y, x.typ); OPL.RestoreRegisters(regs, y)
    ELSIF btyp.comp = Array THEN
      OPL.SaveRegisters(regs); OPC.NewArr(nofel, btyp); OPL.Result(y, x.typ); OPL.RestoreRegisters(regs, y)
    ELSE (* open arrays: the lengths in registers, kept across the call *)
      nlen := 0; e := n.right;
      WHILE (e # NIL) & (nlen < LEN(lens)) DO
        expr(e, lens[nlen]); OPL.LoadX(lens[nlen]); lens[nlen].typ := OPT.linttyp; OPC.CheckLen(lens[nlen]);
        INC(nlen); e := e.link
      END;
      OPL.SaveRegisters(regs);  (* the lengths kept; their registers still hold them, free now *)
      OPL.GetD(nofel); OPL.OpW(2000H + nofel.adr*200H + lens[0].adr); nofel.typ := OPT.linttyp;  (* MOVE.L Dlen0, Dnofel *)
      i := 1;
      WHILE i < nlen DO l := lens[i]; OPL.MultiRef(l); OPC.DOp(nofel, l, times); INC(i) END;
      OPC.NewArr(nofel, btyp); OPL.Result(y, x.typ); OPL.RestoreRegisters(regs, y);
      p := y; OPL.MultiRef(y); OPL.LoadA(p);
      dimtyp := btyp; i := 0;
      WHILE i < nlen DO OPC.SetDim(p, lens[i], dimtyp); dimtyp := dimtyp.BaseTyp; INC(i) END;
      OPL.Release(p)
    END;
    OPC.Assign(x, y)
  END NewStat;

  PROCEDURE stat(n: OPT.Node);
    VAR x, y, z: OPL.Item; L, Lcfj, prevExitChain: OPL.Label; subcl: SHORTINT; regs: OPL.RegSet;
  BEGIN
    WHILE (n # NIL) & OPM.noerr DO OPM.errpos := n.conval.intval; OPL.BegStat;
      CASE n.class OF
      | Nenter: Enter(n)
      | Ninittd:
      | Nassign: subcl := n.subcl;
          CASE subcl OF
          | assign:
              IF n.left.typ.form # Bool THEN expr(n.right, y); expr(n.left, x)
              ELSE expr(n.left, x); expr(n.right, y)
              END;
              OPC.Assign(x, y)
          | newfn: NewStat(n)
          | sysnewfn:
              expr(n.left, x); OPL.SaveRegisters(regs); expr(n.right, y); OPC.SYSnew(y);
              OPL.Result(z, x.typ); OPL.RestoreRegisters(regs, z); OPC.Assign(x, z)
          | movefn: expr(n.right.link, z); expr(n.right, y); expr(n.left, x); OPC.SYSmove(x, y, z)
          | incfn, decfn, inclfn, exclfn, copyfn, getfn, putfn, getrfn, putrfn:
              expr(n.right, y); expr(n.left, x); OPC.AStat(x, y, subcl)
          END
      | Ncall: Call(n, x)
      | Nifelse: IfStat(n, FALSE)
      | Ncase: CaseStat(n)
      | Nwhile: L := OPL.pc; expr(n.left, x); OPL.CFJ(x, Lcfj); Checkpc; stat(n.right); OPL.BJ(L); OPL.FixLink(Lcfj)
      | Nrepeat: L := OPL.pc; stat(n.left); expr(n.right, x); OPL.CBJ(x, L)
      | Nloop: prevExitChain := ExitChain; ExitChain := 0; L := OPL.pc; stat(n.left); OPL.BJ(L);
          OPL.FixLink(ExitChain); ExitChain := prevExitChain
      | Nexit: OPL.FJ(ExitChain)
      | Nreturn:
          IF n.obj = NIL THEN OPC.ReturnFromMod
          ELSE
            IF n.left # NIL THEN expr(n.left, x) END;
            OPC.ReturnFromProc(n.obj, n.obj.conval.intval, n.left # NIL, x)
          END
      | Nwith: IfStat(n, n.subcl = 0)
      | Ntrap: OPC.Trap(n.right.conval.intval)
      | Ncode: OPL.Put(n.right.conval.intval)
      END;
      Checkpc; OPL.EndStat; IF n.class # Nenter THEN OPL.TestRegs END; n := n.link
    END
  END stat;

  PROCEDURE Init*;
    CONST fpc = 8;
  BEGIN
    OPT.typeSize := TypeSize;
    OPL.Init(OPM.opt); OPC.Init(OPM.opt);
    findpc := fpc IN OPM.opt;
    IF ~findpc THEN OPM.breakpc := MAX(LONGINT) END;
    nmarks := 0; ExitChain := 0;
    Allocate
  END Init;

  PROCEDURE Module*;
  BEGIN
    OPM.NewRefObj(OPT.SelfName);
    stat(OPT.prog);
    IF findpc & OPM.noerr THEN OPM.err(254) END;
    IF OPM.noerr THEN OPL.OutCode ELSE OPM.DeleteRefObj END;
    OPL.Close
  END Module;

BEGIN Init
END KOPV.
