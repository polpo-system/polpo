MODULE OBH;    (*NW 7.6.87 / 11.7.93 / as 26.11.98 *)

(*  Peter Matthias
    2016-01-13  Changed Result to use VFP registers for REAL results
*)

  IMPORT SYSTEM, OBS, OBT, OBE, OBC, OC := OBM, HugeInt;

  CONST MaxTemps = 127;  (* polpo: temporaries of HUGEINT in a procedure, see Enter *)

  TYPE
    LabelRange* = RECORD low*, high*: LONGINT; label*: LONGINT END ;

  VAR
    clrchk* : BOOLEAN;
    curProcParamSize* : LONGINT; (* size of params of the current procedure. Used by Return *)
    hugeNext*: INTEGER;  (* polpo: temporaries of HUGEINT used in the statement, OBP sets 0 before each *)
    hugeMax: INTEGER; hugePatch, hugeFrame: LONGINT;  (* temporaries of the procedure, the instruction that
      reserves them below its variables (see Enter), the size of the variables *)
    hugeMod, hugeScope: OBT.Object;  (* HugeInt, imported for the module of scope hugeScope *)

  PROCEDURE Leng(L: LONGINT); (* pushs L onto the stack *)
  VAR y: OBT.Item;
  BEGIN
    OBE.MakeConstItem(y,L,OBT.linttyp); OBE.PushWord(y);
  END Leng;

  PROCEDURE MoveBlock(VAR x, y: OBT.Item; s: LONGINT); (* x=dest, y=src *)
  VAR reg, cnt : LONGINT;
  BEGIN 
    IF s > 0 THEN
      IF x.mode=OC.Var2 THEN (* We're pushing it onto the stack! (preindexed with writeback) *)
        OBC.PutDP1(OBC.ADD,x.r,x.r,x.a); 
        x.mode:=OC.Var; x.a:=0;
      END;
      OBE.loadAdr(x); OBE.loadAdr(y); OBC.GetReg(reg); OBC.GetReg(cnt);
      IF s>0 THEN (* Move bytes *)
        IF s<3 THEN (* one or two bytes -> no loop (loop would have more instrs) *)
          WHILE s>0 DO
            OBC.PutSDT(OBC.LDRBpost,reg,y.r,1);
            OBC.PutSDT(OBC.STRBpost,reg,x.r,1);
            DEC(s)
          END
        ELSE 
          OBC.Reserve(6);  (* polpo: no flush of the constants inside the loop, its branch goes back 3 *)
          OBC.LoadConst(cnt,s);
          OBC.PutSDT(OBC.LDRBpost,reg,y.r,1);
          OBC.PutSDT(OBC.STRBpost,reg,x.r,1);
          OBC.PutDP1(OBC.SUB,cnt,cnt,1);
          OBC.PutB(OBC.B,OBC.pc-3); OBC.SetCondition(OBC.pc-1,OBC.NE);
          OBC.FreeReg(cnt)
        END
      END;
      OBC.FreeReg(reg)
    END
  END MoveBlock;

  PROCEDURE DynArrBnd(ftyp, atyp: OBT.Struct; lev, basereg, adr: LONGINT; varpar: BOOLEAN);
  VAR f: INTEGER; y, z: OBT.Item;
  BEGIN (* ftyp.form = DynArr *)
    y.mode := OC.Var;  y.r:=basereg; 
    IF varpar & (ftyp.BaseTyp.form = OC.Byte) THEN
      IF atyp.form # OC.DynArr THEN
        (* IF (atyp.form # OC.Array) OR (atyp.BaseTyp.size > 1) THEN OBS.Mark(-1) END ; *)
        Leng(atyp.size)
      ELSE 
        y.lev := lev; y.a := adr + atyp.adr; y.typ := OBT.linttyp;
        atyp := atyp.BaseTyp;
        IF atyp.form # OC.DynArr THEN
          IF atyp.size > 1 THEN
            OBE.MakeConstItem(z,atyp.size,OBT.linttyp); OBE.load(z);
            OBE.load(y); OBC.PutMUL(OBC.MUL,y.r,z.r,y.r,0); (* MULD z, Ry *)
          END
        ELSE 
          OBE.load(y); OBC.FreeRegs(OBC.UsedRegisters()+{basereg}); (* polpo: load freed basereg *)
          REPEAT 
            z.mode := OC.Var; z.r:=basereg; z.lev := lev; z.a := atyp.adr + adr; z.typ := OBT.linttyp;
            OBE.load(z); OBC.FreeRegs(OBC.UsedRegisters()+{basereg}); (* polpo: load freed basereg *)
            OBC.PutMUL(OBC.MUL,y.r,z.r,y.r,0);  (* MULD Rz, Ry *)
            atyp := atyp.BaseTyp
          UNTIL atyp.form # OC.DynArr;
          IF atyp.size > 1 THEN
            OBE.MakeConstItem(z,atyp.size,OBT.linttyp); OBE.load(z);
            OBC.PutMUL(OBC.MUL,y.r,z.r,y.r,0) (* MULD z, Ry *)
          END
        END ;
        OBE.PushWord(y); 
      END
    ELSE
      LOOP 
        f := atyp.form;
        IF f = OC.Array THEN Leng(atyp.size DIV atyp.BaseTyp.size)
        ELSIF f = OC.DynArr THEN y.lev := lev; y.a := atyp.adr + adr; y.typ:=OBT.linttyp; OBE.PushWord(y);
          (* polpo: the load freed basereg, a temporary register for an open array on the heap (p^); the next
             length was loaded into it, and the address of the array after it *)
          OBC.FreeRegs(OBC.UsedRegisters()+{basereg}); y.r := basereg
        ELSE OBS.Mark(66); EXIT
        END ;
        ftyp := ftyp.BaseTyp; atyp := atyp.BaseTyp;
        IF ftyp.form # OC.DynArr THEN
          IF ftyp # atyp THEN
            IF ~varpar & (ftyp.form = OC.Pointer) & (atyp.form = OC.Pointer) THEN
              ftyp := ftyp.BaseTyp; atyp := atyp.BaseTyp;
              IF (ftyp.form = OC.Record) & (atyp.form = OC.Record) THEN
                WHILE (ftyp # atyp) & (atyp # NIL) DO atyp := atyp.BaseTyp END ;
                IF atyp = NIL THEN OBS.Mark(113) END
              ELSE OBS.Mark(67)
              END
            ELSE OBS.Mark(67)
            END
          END ;
          EXIT
        END
      END
    END
  END DynArrBnd;

  PROCEDURE Trap*(n: INTEGER);
  BEGIN
    OBC.PutSWI(OBC.AL,n);
  END Trap;

  PROCEDURE CompareParLists*(x, y: OBT.Object);
  VAR xt, yt: OBT.Struct;
  BEGIN
    WHILE x # NIL DO
      IF y # NIL THEN
        xt := x.typ; yt := y.typ;
        WHILE (xt.form = OC.DynArr) & (yt.form = OC.DynArr) DO
          xt := xt.BaseTyp; yt := yt.BaseTyp
        END ;
        IF x.mode # y.mode THEN OBS.Mark(115)
        ELSIF xt # yt THEN
          IF (xt.form = OC.ProcTyp) & (yt.form = OC.ProcTyp) THEN
            CompareParLists(xt.link, yt.link)
          ELSE OBS.Mark(115)
          END
        END ;
        y := y.next
      ELSE OBS.Mark(116)
      END ;
      x := x.next
    END ;
    IF (y # NIL) & (y.mode <= OC.Par) & (y.a0 > 0) THEN OBS.Mark(117) END
  END CompareParLists;

  (* polpo: HUGEINT. OBT makes it an ARRAY 2 OF LONGINT, the low word first (the byte order of ARM); its operations
    are compiled into calls of the module HugeInt (imported for the purpose), its constant expressions computed
    with HugeInt. The functions of HugeInt write the result into a temporary variable and return its address.
    The temporaries are 8 bytes each below the variables of the procedure: Enter reserves them with an instruction
    PatchTemps fills in at the end of the body, when their number is known; a statement uses them from the first.
    A constant of type HUGEINT keeps its low word in a and its high word in b. A function returning a HUGEINT has
    an hidden last parameter VAR @r: HUGEINT and returns the address of @r (see OBT.HugeRef). *)

  PROCEDURE ^Param*(VAR ap: OBT.Item; f: OBT.Object; VAR psize : LONGINT);
  PROCEDURE ^HugeToReal(VAR x: OBT.Item; typ: OBT.Struct);

  PROCEDURE IsInt(VAR x: OBT.Item): BOOLEAN;
  BEGIN RETURN (x.typ = OBT.hinttyp) OR (x.typ.form IN {OC.SInt, OC.Int, OC.LInt})
  END IsInt;

  PROCEDURE Hidden*(fp: OBT.Object): BOOLEAN;  (* the hidden parameter of a function returning a HUGEINT *)
  BEGIN RETURN (fp # NIL) & (fp.name = "@r")
  END Hidden;

  (* the registers item x holds *)
  PROCEDURE ItemRegs(VAR x: OBT.Item): SET;
    VAR s: SET;
  BEGIN s := {};
    IF x.mode = OC.Reg THEN INCL(s, x.r)
    ELSIF (x.mode IN {OC.Var, OC.Var1, OC.Var2, OC.Par, OC.Par1}) & (x.lev >= 0) THEN
      IF (x.r >= 0) & (x.r < OBC.FP) THEN INCL(s, x.r) END;
      IF (x.mode = OC.Var1) & (x.a >= 0) & (x.a < OBC.FP) THEN INCL(s, x.a) END;
      IF (x.mode = OC.Par1) & (x.b >= 0) & (x.b < OBC.FP) THEN INCL(s, x.b) END
    END;
    RETURN s
  END ItemRegs;

  (* a temporary of type HUGEINT, the hugeNext-th of the statement *)
  PROCEDURE Temp(VAR t: OBT.Item);
  BEGIN
    IF hugeNext >= MaxTemps THEN OBS.Mark(215); hugeNext := 0 END;
    t.mode := OC.Var; t.r := OBC.FP; t.lev := OBC.level; t.b := 0; t.obj := NIL; t.typ := OBT.hinttyp;
    t.a := -(hugeFrame + 8 * (hugeNext + 1));
    INC(hugeNext); IF hugeNext > hugeMax THEN hugeMax := hugeNext END
  END Temp;

  (* x, a HUGEINT variable, := the words lo, hi *)
  PROCEDURE StoreWords(VAR x, lo, hi: OBT.Item);
    VAR w: OBT.Item; r: LONGINT;
  BEGIN
    OBE.loadAdr(x); r := x.r; OBE.load(lo); OBE.load(hi);
    w.mode := OC.Var; w.r := r; w.a := 0; w.b := 0; w.lev := OBC.level; w.typ := OBT.linttyp; w.obj := NIL;
    OBE.store(w, lo);
    w.mode := OC.Var; w.r := r; w.a := 4; w.b := 0; w.lev := OBC.level; w.typ := OBT.linttyp; w.obj := NIL;
    OBE.store(w, hi)
  END StoreWords;

  (* the words of x, an integer or a HUGEINT constant *)
  PROCEDURE Words(VAR x, lo, hi: OBT.Item);
    VAR r: LONGINT;
  BEGIN
    IF x.mode = OC.Const THEN
      OBE.MakeConstItem(lo, x.a, OBT.linttyp);
      IF x.typ = OBT.hinttyp THEN OBE.MakeConstItem(hi, x.b, OBT.linttyp)
      ELSIF x.a < 0 THEN OBE.MakeConstItem(hi, -1, OBT.linttyp)
      ELSE OBE.MakeConstItem(hi, 0, OBT.linttyp)
      END
    ELSE
      lo := x; OBE.load(lo); lo.typ := OBT.linttyp;
      OBC.GetReg(r); OBC.PutDP(OBC.MOV, r, 0, lo.r, 31*8+4);  (* the sign, ASR 31 *)
      hi.mode := OC.Reg; hi.r := r; hi.a := 0; hi.b := 0; hi.typ := OBT.linttyp; hi.lev := OBC.level; hi.obj := NIL
    END
  END Words;

  (* x, an integer or a HUGEINT, becomes a HUGEINT variable *)
  PROCEDURE ToHuge(VAR x: OBT.Item);
    VAR t, d, lo, hi: OBT.Item;
  BEGIN
    IF (x.typ # OBT.hinttyp) OR (x.mode = OC.Const) THEN
      Temp(t); d := t; Words(x, lo, hi); StoreWords(d, lo, hi); x := t
    END
  END ToHuge;

  (* x := y, HUGEINT variables; x may be a parameter pushed *)
  PROCEDURE MoveHuge(VAR x, y: OBT.Item);
    VAR r: LONGINT;
  BEGIN
    IF x.mode = OC.Var2 THEN (* pushed, as in MoveBlock *)
      OBC.PutDP1(OBC.ADD, x.r, x.r, x.a); x.mode := OC.Var; x.a := 0
    END;
    OBE.loadAdr(x); OBE.loadAdr(y); OBC.GetReg(r);
    OBC.PutSDT(OBC.LDR, r, y.r, 0); OBC.PutSDT(OBC.STR, r, x.r, 0);
    OBC.PutSDT(OBC.LDR, r, y.r, 4); OBC.PutSDT(OBC.STR, r, x.r, 4);
    OBC.FreeReg(r); OBC.Release(x); OBC.Release(y)
  END MoveHuge;

  (* x := y, x a HUGEINT variable *)
  PROCEDURE HugeAssign(VAR x, y: OBT.Item);
    VAR lo, hi: OBT.Item;
  BEGIN
    IF (y.typ = OBT.hinttyp) & (y.mode # OC.Const) THEN MoveHuge(x, y)
    ELSIF IsInt(y) THEN Words(y, lo, hi); StoreWords(x, lo, hi)
    ELSE OBS.Mark(113)
    END
  END HugeAssign;

  PROCEDURE Assign*(VAR x, y: OBT.Item; param: BOOLEAN); (* x=dest; y=src *)
  VAR f, g, s, vsz : LONGINT; p, q: OBT.Struct; tag, tdes: OBT.Item;
  BEGIN
    IF (x.typ = OBT.hinttyp) & (x.mode # OC.Const) THEN  (* polpo *)
      IF param & IsInt(y) THEN ToHuge(y) END;
      IF param & (y.typ # OBT.hinttyp) THEN OBS.Mark(113); RETURN END;
      IF param OR (y.typ = OBT.hinttyp) & (y.mode # OC.Const) THEN MoveHuge(x, y) ELSE HugeAssign(x, y) END;
      RETURN
    END;
    IF (y.typ = OBT.hinttyp) & (x.typ.form IN {OC.Real, OC.LReal}) THEN HugeToReal(y, x.typ) END;  (* polpo *)
    f := x.typ.form; g := y.typ.form;
    IF x.mode = OC.Const THEN OBS.Mark(56)
    ELSIF( f # OC.ProcTyp) & (y.mode = OC.LProc) THEN OBS.Mark(55)
    END;
    CASE f OF
      OC.Undef, OC.String:
      | OC.Byte:
          IF g IN {OC.Undef, OC.Byte, OC.Char, OC.SInt} THEN OBE.store(x,y);
          ELSE OBS.Mark(113)
          END

      | OC.Bool:
          IF (y.mode = OC.CC) OR (g = OC.Bool) THEN OBE.store(x,y);
          ELSE OBS.Mark(113)
          END

      | OC.Char, OC.SInt, OC.Set: 
          IF g = f THEN OBE.store(x,y)
          ELSE OBS.Mark(113)
          END

      | OC.Int:
          IF g IN {OC.Int, OC.SInt} THEN OBE.store(x,y) 
          ELSE OBS.Mark(113)
          END

      | OC.LInt:
          IF g IN {OC.LInt, OC.Int, OC.SInt} THEN OBE.store(x,y);
          ELSE OBS.Mark(113)
          END

      | OC.Real:
          IF g = OC.Real THEN OBE.store(x,y);
          ELSIF (OC.SInt <= g) & (g <= OC.LInt) THEN
            OBE.convertIntToReal(y,OBT.realtyp);
            OBE.store(x,y)
          ELSE OBS.Mark(113)
          END

      | OC.LReal:
          IF g = OC.LReal THEN 
            IF param THEN OBE.PushLReal(y) ELSE OBE.storeLReal(x,y) END;
          ELSIF g = OC.Real THEN 
            OBE.convertRealToLReal(y);
            IF param THEN OBE.PushLReal(y) ELSE OBE.storeLReal(x,y) END;
          ELSIF (OC.SInt <= g) & (g <= OC.LInt) THEN 
            OBE.convertIntToReal(y,OBT.lrltyp);
            IF param THEN OBE.PushLReal(y) ELSE OBE.storeLReal(x,y) END;
          ELSE OBS.Mark(113)
          END

      | OC.SysPtr: 
          IF (x.typ = y.typ) OR (g = OC.Pointer) THEN OBE.store(x,y)
          ELSIF g = OC.NilTyp THEN OBE.MakeConstItem(y,0,x.typ); OBE.store(x,y);
          ELSE OBS.Mark(113)
          END

      | OC.Pointer:
          IF x.typ = y.typ THEN OBE.store(x,y)
          ELSIF  f = OC.SysPtr THEN y.typ:=x.typ; OBE.store(x,y)
          ELSIF g = OC.NilTyp THEN OBE.MakeConstItem(y,0,x.typ); OBE.store(x,y);
          ELSIF g = OC.Pointer THEN
            p := x.typ.BaseTyp; q := y.typ.BaseTyp;
            IF (p.form = OC.Record) & (q.form = OC.Record) THEN
              WHILE (q # p) & (q # NIL) DO q := q.BaseTyp END ;
              IF q # NIL THEN OBE.store(x,y) ELSE OBS.Mark(113) END
            ELSE OBS.Mark(113)
            END
          ELSE OBS.Mark(113)
          END

      | OC.Array:
          s := x.typ.size;
          IF x.typ = y.typ THEN MoveBlock(x, y, s)
          ELSIF (g = OC.String) & (x.typ.BaseTyp.form = OC.Char) THEN
            s := y.b; vsz := x.typ.size;  (*check length of string*)
            IF s > vsz THEN OBS.Mark(114) END ;
            MoveBlock(x, y, s)
          ELSIF (g = OC.Char) & (y.mode = OC.Const) & (x.typ.BaseTyp.form = OC.Char) THEN
            OBE.ConstCharToString(y); g := y.typ.form;
            s := y.b; vsz := x.typ.size;  (*check length of string*)
            IF s > vsz THEN OBS.Mark(114) END ;
            MoveBlock(x, y, s)
          ELSE OBS.Mark(113)
          END

      | OC.DynArr: 
          s := x.typ.size;
          IF param THEN (*formal parameter is open array*)
            IF (g = OC.Char) & (y.mode=OC.Const) & (x.typ.BaseTyp.form = OC.Char) THEN
              y.typ := OBT.stringtyp; g:=OC.String;
              NEW(y.obj); NEW(y.obj.ext); 
              y.obj.ext.entered:=FALSE; y.obj.ext.str[0]:=CHR(y.a); y.obj.ext.str[1]:=0X; y.b:=2; 
            END;
            IF (g = OC.String) & (x.typ.BaseTyp.form = OC.Char) THEN Leng(y.b)
            ELSIF ~(y.mode IN {OC.Var,OC.Var1,OC.Par, OC.Par1}) THEN OBS.Mark(59) 
            ELSE DynArrBnd(x.typ, y.typ, y.lev, y.r, y.a, FALSE)
            END ;
            IF g = OC.DynArr THEN OBE.DynArrAdr(y); OBE.PushWord(y);
            ELSE OBE.loadAdr(y); OBE.PushWord(y);
            END
          ELSE OBS.Mark(113)
          END

      | OC.Record: 
          s := x.typ.size;
          IF x.typ # y.typ THEN
            IF g = OC.Record THEN
              q := y.typ.BaseTyp;
              WHILE (q # NIL) & (q # x.typ) DO q := q.BaseTyp END ;
              IF q = NIL THEN OBS.Mark(113) END
            ELSE OBS.Mark(113)
            END
          END;
          IF OBC.typchk & ~param &          
            ( (x.mode IN {OC.Var,OC.Par})  & (x.obj = OBC.wasderef)  (* p^ := *)
              OR (x.mode = OC.Par) & (x.obj # NIL) & (x.obj # OBC.wasderef) )  (* varpar := *) THEN
            tag := x; tag.typ:=OBT.linttyp; 
            tdes.mode := OC.Var; tdes.lev := -x.typ.mno; tdes.r:=OBC.PC; tdes.a := x.typ.adr; tdes.typ:=OBT.linttyp;
            IF x.obj = OBC.wasderef THEN 
              IF tag.mode=OC.Var THEN tag.a := - 4
              ELSIF tag.mode=OC.Par THEN tag.b:=-4
              ELSE HALT(215)
              END;
            ELSE tag.mode := OC.Var; INC(tag.a, 4)
            END;
            OBE.load(tdes); OBE.load(tag);
            OBC.PutDP(OBC.CMP,0,tdes.r,tag.r,0);
            OBC.PutSWI(OBC.NE,OC.ImplTypeGuardTrap);
            OBC.Release(tdes); OBC.Release(tag);
          END;
          MoveBlock(x, y, s)

      | OC.ProcTyp:
          IF (x.typ = y.typ) OR (y.typ.form = OC.NilTyp) THEN OBE.store(x,y);
          ELSIF (y.mode = OC.LProc) & (y.lev <= 0) THEN
            (*procedure y to proc. variable x; check compatibility*)
            IF x.typ.BaseTyp = y.typ THEN
              CompareParLists(x.typ.link, y.obj.dsc);
              OBE.loadAdr(y); OBE.store(x,y);
            ELSE OBS.Mark(113)
            END
          ELSE OBS.Mark(111)
          END
          
      | OC.NoTyp, OC.NilTyp:
          OBS.Mark(111)
    END
  END Assign;

  PROCEDURE TempVar*(VAR x : OBT.Item);
  (** Creates a temporary integer var on the stack and assigns it the value of x *)
  VAR y : OBT.Item;
  BEGIN
    IF x.typ.size>4 THEN HALT(204) END;
    
    y.mode:=OC.Var2; y.a:=-4;  y.r:=OBC.SP; y.typ:=OBT.linttyp; (* to keep stack aligned! won't cause problems if y is not LInt *)
    OBE.store(y,x);
    x.mode:=OC.Var;  x.r:=OBC.SP; x.a:=0; x.typ:=y.typ;
  END TempVar;
  
  PROCEDURE RemoveTempVars*(n : INTEGER);
  BEGIN
    ASSERT(n>=0);
    IF n>0 THEN OBC.PutDP1(OBC.ADD,OBC.SP,OBC.SP,n*4) END;
  END RemoveTempVars;
  
  PROCEDURE PrepCall*(VAR x: OBT.Item; VAR fpar: OBT.Object);
  BEGIN
    IF x.mode = OC.LProc THEN
      fpar := x.obj.dsc; 
    ELSIF (x.typ # NIL) & (x.typ.form = OC.ProcTyp) THEN
      fpar := x.typ.link;
    ELSE OBS.Mark(121); fpar := NIL; x.typ := OBT.undftyp
    END
  END PrepCall;

  PROCEDURE Param*(VAR ap: OBT.Item; f: OBT.Object; VAR psize : LONGINT);
  VAR q: OBT.Struct; fp, z: OBT.Item; 
  BEGIN
    IF (ap.typ = OBT.hinttyp) & (f.typ.form = OC.DynArr) & (f.typ.BaseTyp # OBT.bytetyp) THEN OBS.Mark(66) END;  (* polpo *)
    IF (ap.typ = OBT.hinttyp) & (f.mode = OC.Var) & (f.typ.form IN {OC.Real, OC.LReal}) THEN HugeToReal(ap, f.typ) END;
    fp.mode := OC.Var2; fp.r:=OBC.SP; fp.typ := f.typ;
    IF f.mode = OC.Par THEN (*VAR parameter*)
      IF ap.mode >= OC.Const THEN OBS.Mark(122) END ;
      IF fp.typ.form = OC.DynArr THEN
        DynArrBnd(fp.typ, ap.typ, ap.lev, ap.r, ap.a, TRUE);
        IF ap.typ.form = OC.DynArr THEN OBE.DynArrAdr(ap)
        ELSE OBE.loadAdr(ap)
        END;
        OBE.PushWord(ap);
      ELSIF (fp.typ.form = OC.Record) & (ap.typ.form = OC.Record) THEN
        q := ap.typ;
        WHILE (q # fp.typ) & (q # NIL) DO q := q.BaseTyp END ;
        IF q # NIL THEN
          IF (ap.mode = OC.Par) & (ap.obj # NIL) & (ap.obj # OBC.wasderef) THEN
            (*actual par is VAR-par*)
            z:=ap;  z.mode := OC.Var; z.a := z.a + 4; z.typ:=OBT.linttyp; OBE.PushWord(z); (* push type desc addr *)
            z:=ap;  z.mode := OC.Var; z.typ:=OBT.linttyp; OBE.PushWord(z); (* push addr *)
          ELSIF (ap.mode IN {OC.Var, OC.Par}) & (ap.obj = OBC.wasderef) THEN
            (*actual par is p^*)
            z:=ap; IF ap.mode=OC.Par THEN z.b:=- 4 ELSE z.a:=-4 END; z.typ:=OBT.linttyp; OBE.PushWord(z); (* push type desc addr *)
            z:=ap; OBE.loadAdr(z); z.typ:=OBT.linttyp; OBE.PushWord(z); (* push addr *)
          ELSE
            z.mode := OC.Var; z.r:=OBC.PC; z.lev := -ap.typ.mno; z.a := ap.typ.adr; z.typ:=OBT.linttyp; OBE.PushWord(z); 
            OBE.loadAdr(ap); OBE.PushWord(ap);
          END
        ELSE OBS.Mark(111)
        END
      ELSIF (fp.typ = OBT.sysptrtyp) & (ap.typ.form = OC.Pointer) THEN
        OBE.loadAdr(ap); OBE.PushWord(ap)
      ELSIF (ap.typ = fp.typ) OR ((fp.typ.form = OC.Byte) & (ap.typ.form IN {OC.Char, OC.SInt})) OR
          (ap.typ = OBT.hinttyp) & (fp.typ.form = OC.Array) & (fp.typ.size = 8) & (fp.typ.BaseTyp = OBT.linttyp) THEN
        (* polpo: a HUGEINT for a HugeInt.Huge, the calls OBH makes *)
        IF (ap.mode = OC.Par) & (ap.b = 0) THEN (*actual var par*) ap.mode := OC.Var; ap.typ:=OBT.linttyp; OBE.PushWord(ap);
        ELSE OBE.loadAdr(ap); OBE.PushWord(ap);
        END
      ELSE OBS.Mark(123)
      END
    ELSE
      fp.a:=f.a0-psize;
      Assign(fp, ap, TRUE)
    END;
    psize:=f.a0;
  END Param;

  PROCEDURE Call*(VAR x: OBT.Item);
  VAR  sL: OBT.Item; 
  BEGIN
    IF x.mode = OC.LProc THEN
      IF x.lev >= 0 THEN
        IF x.lev > 0 THEN
          IF x.lev=OBC.level THEN (* Push current FP as static link *)
            sL.mode:=OC.Reg; sL.r:=OBC.FP; sL.typ:=OBT.linttyp; OBE.PushWord(sL)
          ELSE
            sL.mode := OC.Var; sL.typ:=OBT.linttyp; sL.lev:=x.lev+1; sL.r:=OBC.FP; sL.a:=8;
            OBE.load(sL);
            OBC.PutBDT(OBC.STMDB,OBC.SP,{sL.r},TRUE); (* static link *)
            OBC.Release(sL)
          END
        END ;
        IF x.a = -1 THEN OBC.PutBabs(OBC.BL,x.obj.a1); x.obj.a1:=OBC.pc-1; (* forward link *)
        ELSE OBC.PutB(OBC.BL,x.a);
        END
      ELSE OBC.PutBext(-x.lev,x.a);
      END
    ELSIF (x.mode < OC.Const) & (x.typ.form # OC.Undef) THEN
      OBE.load(x);
      OBC.PutDP(OBC.MOV,OBC.LR,0,OBC.PC,0);
      OBC.PutDP(OBC.MOV,OBC.PC,0,x.r,0);
      x.typ := x.typ.BaseTyp 
    ELSE OBS.Mark(121)
    END
    (*function result is marked when restoring registers*)    
  END Call;

  PROCEDURE HugeProc(name: ARRAY OF CHAR): OBT.Object;
    VAR scope, obj: OBT.Object;
  BEGIN
    scope := OBT.topScope; WHILE scope.a0 > 0 DO scope := scope.dsc END;
    IF (hugeMod = NIL) OR (hugeScope # scope) THEN
      hugeMod := OBT.ImportHidden("HugeInt", OBE.modName); hugeScope := scope
    END;
    obj := NIL;
    IF hugeMod # NIL THEN obj := OBT.FindIn(hugeMod, name); IF obj = NIL THEN OBS.Mark(0) END END;
    RETURN obj
  END HugeProc;

  (* res := HugeInt.name(a[0], ... a[n-1]) *)
  PROCEDURE HugeCall(name: ARRAY OF CHAR; VAR a: ARRAY OF OBT.Item; n: INTEGER; VAR res: OBT.Item);
    VAR proc, fpar: OBT.Object; p: OBT.Item; gR, gF, keep, R: SET; i: INTEGER; psize: LONGINT;
  BEGIN
    proc := HugeProc(name);
    IF proc = NIL THEN res.mode := OC.Const; res.a := 0; res.b := 0; res.typ := OBT.undftyp; res.obj := NIL
    ELSE
      OBE.MakeItem(proc, p, -hugeMod.a0); PrepCall(p, fpar);
      keep := {}; i := 0; WHILE i < n DO keep := keep + ItemRegs(a[i]); INC(i) END;
      OBC.SaveRegistersKeep(gR, gF, keep); R := OBC.UsedRegisters();
      psize := 0;
      IF OBT.IsParam(fpar) THEN psize := fpar.a0 + fpar.typ.size; psize := (psize + 3) DIV 4 * 4 END;
      i := 0;
      WHILE (i < n) & (fpar # NIL) DO Param(a[i], fpar, psize); fpar := fpar.next; OBC.FreeRegs(R); INC(i) END;
      Call(p); OBC.RestoreRegisters(gR, gF, p);
      IF p.typ = OBT.notyp THEN OBC.FreeReg(p.r) END;
      res := p
    END
  END HugeCall;

  (* x := the HUGEINT HugeInt.name(t, a1, a2) leaves in a new temporary t *)
  PROCEDURE HugeValue(name: ARRAY OF CHAR; VAR x, a1, a2: OBT.Item; n: INTEGER);
    VAR a: ARRAY 3 OF OBT.Item;
  BEGIN
    Temp(a[0]); a[1] := a1; a[2] := a2; HugeCall(name, a, n, x);
    IF x.mode = OC.Reg THEN x.mode := OC.Var; x.a := 0; x.b := 0; x.typ := OBT.hinttyp; x.lev := OBC.level; x.obj := NIL END
  END HugeValue;

  (* x, if a HUGEINT, becomes a value of the real type typ *)
  PROCEDURE HugeToReal(VAR x: OBT.Item; typ: OBT.Struct);
    VAR h: HugeInt.Huge; lr: LONGREAL; r: REAL; a: ARRAY 1 OF OBT.Item;
  BEGIN
    IF x.typ = OBT.hinttyp THEN
      IF x.mode = OC.Const THEN
        HugeInt.Pack(h, x.a, x.b); lr := HugeInt.Real(h);
        IF typ = OBT.realtyp THEN r := SHORT(lr); x.b := 0; SYSTEM.PUT(SYSTEM.ADR(x.a), r); x.typ := OBT.realtyp
        ELSE SYSTEM.PUT(SYSTEM.ADR(x.a), lr); x.typ := OBT.lrltyp
        END
      ELSE
        a[0] := x; HugeCall("Real", a, 1, x);
        IF typ = OBT.realtyp THEN OBE.convertLRealToReal(x) END
      END
    END
  END HugeToReal;

  (* x op y, constant integers, one a HUGEINT *)
  PROCEDURE HugeConstOp(op: INTEGER; VAR x, y: OBT.Item);
    VAR a, b, r: HugeInt.Huge; lo, hi, c: LONGINT; t: BOOLEAN; lr: LONGREAL; rr: REAL;
  BEGIN
    IF x.typ = OBT.hinttyp THEN HugeInt.Pack(a, x.a, x.b) ELSIF x.a < 0 THEN HugeInt.Pack(a, x.a, -1) ELSE HugeInt.Pack(a, x.a, 0) END;
    IF y.typ = OBT.hinttyp THEN HugeInt.Pack(b, y.a, y.b) ELSIF y.a < 0 THEN HugeInt.Pack(b, y.a, -1) ELSE HugeInt.Pack(b, y.a, 0) END;
    HugeInt.Unpack(b, lo, hi);
    IF (op = OC.times) OR (op = OC.plus) OR (op = OC.minus) OR (op = OC.div) OR (op = OC.mod) THEN
      IF op = OC.times THEN t := HugeInt.MulOvf(r, a, b); IF t THEN OBS.Mark(204) END
      ELSIF op = OC.plus THEN t := HugeInt.AddOvf(r, a, b); IF t THEN OBS.Mark(206) END
      ELSIF op = OC.minus THEN t := HugeInt.SubOvf(r, a, b); IF t THEN OBS.Mark(207) END
      ELSIF (hi < 0) OR (hi = 0) & (lo = 0) THEN OBS.Mark(237); HugeInt.Pack(r, 1, 0)
      ELSIF op = OC.div THEN c := HugeInt.Div(r, a, b)
      ELSE c := HugeInt.Mod(r, a, b)
      END;
      HugeInt.Unpack(r, lo, hi); OBE.HugeConst(x, lo, hi)
    ELSIF op = OC.slash THEN
      IF (lo = 0) & (hi = 0) THEN OBS.Mark(205); rr := 1.0 ELSE rr := SHORT(HugeInt.Real(a) / HugeInt.Real(b)) END;
      x.mode := OC.Const; x.b := 0; SYSTEM.PUT(SYSTEM.ADR(x.a), rr); x.typ := OBT.realtyp
    ELSIF (op >= OC.eql) & (op <= OC.geq) THEN
      c := HugeInt.Cmp(a, b);
      CASE op OF
        OC.eql: t := c = 0 | OC.neq: t := c # 0 | OC.lss: t := c < 0 | OC.leq: t := c <= 0 | OC.gtr: t := c > 0 | OC.geq: t := c >= 0
      END;
      x.mode := OC.Const; x.b := 0; x.typ := OBT.booltyp; IF t THEN x.a := 1 ELSE x.a := 0 END
    ELSE OBS.Mark(100)
    END
  END HugeConstOp;

  (* x op y, one a HUGEINT (OBE.Op) *)
  PROCEDURE HugeOp(op: INTEGER; VAR x, y: OBT.Item);
    VAR z, t: OBT.Item; a: ARRAY 2 OF OBT.Item; lo, hi: LONGINT;
  BEGIN
    IF (x.typ.form IN {OC.Real, OC.LReal}) OR (y.typ.form IN {OC.Real, OC.LReal}) THEN
      IF x.typ = OBT.hinttyp THEN HugeToReal(x, y.typ) ELSE HugeToReal(y, x.typ) END;
      OBE.Op(op, x, y)
    ELSIF ~IsInt(x) OR ~IsInt(y) THEN OBS.Mark(100); x.typ := OBT.undftyp
    ELSIF (x.mode = OC.Const) & (y.mode = OC.Const) THEN HugeConstOp(op, x, y)
    ELSIF (op = OC.times) OR (op = OC.plus) OR (op = OC.minus) OR (op = OC.div) OR (op = OC.mod) THEN
      IF ((op = OC.div) OR (op = OC.mod)) & (y.mode = OC.Const) THEN
        lo := y.a; IF y.typ = OBT.hinttyp THEN hi := y.b ELSIF lo < 0 THEN hi := -1 ELSE hi := 0 END;
        IF (hi < 0) OR (hi = 0) & (lo = 0) THEN OBS.Mark(237) END  (* DIV and MOD want a divisor > 0 *)
      END;
      ToHuge(x); ToHuge(y);
      CASE op OF
        OC.times: HugeValue("Mul", z, x, y, 3)
      | OC.plus: HugeValue("Add", z, x, y, 3)
      | OC.minus: HugeValue("Sub", z, x, y, 3)
      | OC.div: HugeValue("Div", z, x, y, 3)
      | OC.mod: HugeValue("Mod", z, x, y, 3)
      END;
      x := z
    ELSIF op = OC.slash THEN
      HugeToReal(x, OBT.realtyp); HugeToReal(y, OBT.realtyp);
      IF x.typ.form IN {OC.SInt, OC.Int, OC.LInt} THEN OBE.convertIntToReal(x, OBT.realtyp) END;
      IF y.typ.form IN {OC.SInt, OC.Int, OC.LInt} THEN OBE.convertIntToReal(y, OBT.realtyp) END;
      OBE.Op(op, x, y)
    ELSIF (op >= OC.eql) & (op <= OC.geq) THEN
      ToHuge(x); ToHuge(y); a[0] := x; a[1] := y; HugeCall("Cmp", a, 2, z);
      OBE.MakeConstItem(t, 0, OBT.linttyp); x := z; OBE.Op(op, x, t)
    ELSIF op = OC.and THEN OBS.Mark(94)
    ELSIF op = OC.or THEN OBS.Mark(95)
    ELSE OBS.Mark(100)
    END
  END HugeOp;

  (* op x, x a HUGEINT, op = plus or minus (OBE.MOp) *)
  PROCEDURE HugeMOp(op: INTEGER; VAR x: OBT.Item);
    VAR h, r: HugeInt.Huge; lo, hi: LONGINT; z: OBT.Item;
  BEGIN
    IF op = OC.minus THEN
      IF x.mode = OC.Const THEN
        HugeInt.Pack(h, x.a, x.b);
        IF HugeInt.NegOvf(r, h) THEN OBS.Mark(203) ELSE HugeInt.Unpack(r, lo, hi); OBE.HugeConst(x, lo, hi) END
      ELSE HugeValue("Neg", z, x, x, 2); x := z
      END
    END
  END HugeMOp;

  (* the first parameter x of the standard procedure fctno, if it is about HUGEINT (OBE.StPar1) *)
  PROCEDURE HugeStd1(fctno: LONGINT; VAR x: OBT.Item): BOOLEAN;
    VAR h, r: HugeInt.Huge; lo, hi: LONGINT; z: OBT.Item; a: ARRAY 1 OF OBT.Item;
  BEGIN
    IF (fctno = OBT.FnLong) & (x.typ.form = OC.LInt) THEN
      IF x.mode = OC.Const THEN IF x.a < 0 THEN x.b := -1 ELSE x.b := 0 END; x.typ := OBT.hinttyp
      ELSE ToHuge(x)
      END;
      RETURN TRUE
    ELSIF (fctno = OBT.FnMin) & (x.mode = OC.Typ) & (x.typ = OBT.hinttyp) THEN OBE.HugeConst(x, 0, MIN(LONGINT)); RETURN TRUE
    ELSIF (fctno = OBT.FnMax) & (x.mode = OC.Typ) & (x.typ = OBT.hinttyp) THEN OBE.HugeConst(x, -1, MAX(LONGINT)); RETURN TRUE
    ELSIF (x.typ # OBT.hinttyp) OR (x.mode = OC.Typ) THEN RETURN FALSE
    END;
    CASE fctno OF
      OBT.FnAbs:
        IF x.mode = OC.Const THEN
          IF x.b < 0 THEN HugeInt.Pack(h, x.a, x.b);
            IF HugeInt.NegOvf(r, h) THEN OBS.Mark(203) ELSE HugeInt.Unpack(r, lo, hi); OBE.HugeConst(x, lo, hi) END
          END
        ELSE HugeValue("Abs", z, x, x, 2); x := z
        END
    | OBT.FnOdd:
        IF x.mode = OC.Const THEN x.typ := OBT.booltyp; IF ODD(x.a) THEN x.a := 1 ELSE x.a := 0 END; x.b := 0
        ELSE a[0] := x; HugeCall("Short", a, 1, x); OBE.load(x); OBC.PutDP1(OBC.TST, 0, x.r, 1); OBC.Release(x);
          OBE.setCC(x, OBC.NE)
        END
    | OBT.FnShort:
        IF x.mode = OC.Const THEN
          IF (x.b # 0) & (x.b # -1) OR (x.b = 0) & (x.a < 0) OR (x.b = -1) & (x.a >= 0) THEN OBS.Mark(203); x.a := 1 END;
          x.b := 0; x.typ := OBT.linttyp
        ELSE a[0] := x; HugeCall("Short", a, 1, x)
        END
    | OBT.FnLen: OBS.Mark(131); x.typ := OBT.undftyp
    | OBT.FnInc, OBT.FnDec: IF x.mode >= OC.Const THEN OBS.Mark(112) END
    | OBT.FnAsh:
    ELSE RETURN FALSE
    END;
    RETURN TRUE
  END HugeStd1;

  (* the second parameter x of the standard procedure fctno, the first p, if it is about HUGEINT (OBE.StPar2) *)
  PROCEDURE HugeStd2(fctno: LONGINT; VAR p, x: OBT.Item): BOOLEAN;
    VAR h, r: HugeInt.Huge; lo, hi: LONGINT; z: OBT.Item; a: ARRAY 2 OF OBT.Item;
  BEGIN
    IF (fctno = OBT.FnSysVal) & ((p.typ = OBT.hinttyp) OR (x.typ = OBT.hinttyp)) THEN
      IF x.mode IN {OC.Var, OC.Var1, OC.Par, OC.Par1} THEN x.typ := p.typ; p := x ELSE OBS.Mark(126) END;
      RETURN TRUE
    ELSIF p.typ # OBT.hinttyp THEN
      IF ((fctno = OBT.FnInc) OR (fctno = OBT.FnDec)) & (x.typ = OBT.hinttyp) THEN OBS.Mark(111); p.typ := OBT.notyp; RETURN TRUE END;
      RETURN FALSE
    END;
    IF (fctno = OBT.FnInc) OR (fctno = OBT.FnDec) THEN
      IF ~IsInt(x) THEN OBS.Mark(111)
      ELSIF x.typ = OBT.hinttyp THEN
        ToHuge(x); a[0] := p; a[1] := x;
        IF fctno = OBT.FnInc THEN HugeCall("Inc", a, 2, z) ELSE HugeCall("Dec", a, 2, z) END
      ELSE
        a[0] := p; a[1] := x;
        IF fctno = OBT.FnInc THEN HugeCall("IncL", a, 2, z) ELSE HugeCall("DecL", a, 2, z) END
      END;
      p.typ := OBT.notyp; RETURN TRUE
    ELSIF fctno = OBT.FnAsh THEN
      IF ~(x.typ.form IN {OC.SInt, OC.Int, OC.LInt}) THEN OBS.Mark(111)
      ELSIF (p.mode = OC.Const) & (x.mode = OC.Const) THEN
        HugeInt.Pack(h, p.a, p.b);
        IF HugeInt.AshOvf(r, h, x.a) THEN OBS.Mark(208) ELSE HugeInt.Unpack(r, lo, hi); OBE.HugeConst(p, lo, hi) END
      ELSE ToHuge(p); HugeValue("Ash", z, p, x, 3); p := z
      END;
      RETURN TRUE
    END;
    RETURN FALSE
  END HugeStd2;

  (* the temporary for the result of a function returning a HUGEINT, pushed as its hidden parameter fp *)
  PROCEDURE HiddenParam*(fp: OBT.Object; VAR psize: LONGINT);
    VAR t: OBT.Item;
  BEGIN Temp(t); Param(t, fp, psize)
  END HiddenParam;

  (* x, the result of a function returning a HUGEINT, becomes the variable it points to *)
  PROCEDURE HugeResult*(VAR x: OBT.Item);
  BEGIN
    IF x.mode = OC.Reg THEN x.mode := OC.Var; x.a := 0; x.b := 0; x.typ := OBT.hinttyp; x.lev := OBC.level; x.obj := NIL END
  END HugeResult;

  PROCEDURE Enter*(mode: SHORTINT; dsize : LONGINT);
  VAR zero, cnt : OBT.Item;
  BEGIN 
    OBC.CheckCodeSize; 
    OBC.PutBDT(OBC.STMDB,OBC.SP,{OBC.FP,OBC.LR},TRUE(*writeback*)); (* Store FP and LR *)
    OBC.PutDP(OBC.MOV,OBC.FP,0,OBC.SP,0); (* Set new FP *)
    IF mode#OC.Mod THEN
      IF dsize>0 THEN
        IF clrchk THEN 
          ASSERT(dsize MOD 4 = 0);
          OBE.MakeConstItem(zero,0,OBT.linttyp);
          OBE.MakeConstItem(cnt,dsize DIV 4, OBT.linttyp);
          OBE.load(zero); 
          IF cnt.a < 5 THEN  (* 4 or less words -> no loop *)
            WHILE cnt.a > 0 DO OBE.PushWord(zero);  DEC(cnt.a) END
            (* zero is release by OBE.PushWord *)
          ELSE (* 5 or more words -> loop *)
            OBE.load(cnt);
            DEC(OBC.allowConstFlushing);
            OBE.PushWord(zero);
            OBC.PutDP1(OBC.SUB,cnt.r,cnt.r,1);
            OBC.PutB(OBC.B,OBC.pc-2); OBC.SetCondition(OBC.pc-1,OBC.NE);
            INC(OBC.allowConstFlushing);
            OBC.Release(cnt)
            (* zero is release by OBE.PushWord *)
          END
        ELSE
          OBC.PutDP1(OBC.SUB,OBC.SP,OBC.SP,dsize)
        END
      END
    END;
    (* polpo: the temporaries of HUGEINT below the variables; PatchTemps puts in their size *)
    hugeFrame := dsize; IF mode = OC.Mod THEN hugeFrame := 0 END;
    hugeMax := 0; hugeNext := 0;
    OBC.PutDP1(OBC.SUB, OBC.SP, OBC.SP, 0); hugePatch := OBC.pc - 1
  END Enter;

  (* polpo: at the end of a body: the temporaries of HUGEINT reserved by Enter *)
  PROCEDURE PatchTemps*;
  BEGIN
    IF hugeMax > 0 THEN
      IF ~OBC.PatchDP1(hugePatch, 8 * LONG(hugeMax)) THEN OBS.Mark(215) END
    END;
    hugeMax := 0
  END PatchTemps;

  PROCEDURE CopyDynArray*(adr: LONGINT; typ: OBT.Struct);
  VAR size : OBT.Item; r,src : LONGINT;

    PROCEDURE DynArrSize(typ: OBT.Struct);
    VAR len: OBT.Item;
    BEGIN
      IF typ.form = OC.DynArr THEN 
        DynArrSize(typ.BaseTyp);
        len.mode := OC.Var; len.r:=OBC.FP; len.lev := OBC.level; len.typ := OBT.linttyp; len.a := adr + typ.adr; OBE.load(len);
        IF size.mode=OC.Const THEN
          IF size.a # 1 THEN OBE.load(size); OBC.PutMUL(OBC.MUL,size.r,len.r,size.r,0); OBC.Release(len);
          ELSE size:=len; OBE.load(size);
          END
        ELSE
          OBC.PutMUL(OBC.MUL,size.r,len.r,size.r,0); OBC.Release(len);
        END;
      ELSE
        OBE.MakeConstItem(size,typ.size,OBT.linttyp);
      END
    END DynArrSize;
    
  BEGIN
    DynArrSize(typ);  (* load total byte size of dyn array *)
    OBC.PutDP(OBC.SUB,OBC.SP,OBC.SP,size.r,0); 
    IF typ.BaseTyp.size < 4 THEN
      (* size is not necessarily a multiple of four -> make sure that SP stays aligned *)
      OBC.PutDP1(OBC.BIC,OBC.SP,OBC.SP,3); 
    END;
    OBC.GetReg(r); 
    OBC.GetReg(src); OBC.PutSDT(OBC.LDR,src,OBC.FP,adr);
    DEC(OBC.allowConstFlushing);
    IF typ.BaseTyp.size<4 THEN
      (* Source may be not aligned (neither word nor halfword), so copy byte by byte *)
      OBC.PutDP1(OBC.SUB,size.r,size.r,1);  
      OBC.PutSDT1(OBC.LDRB,r,src,size.r,0);
      OBC.PutSDT1(OBC.STRB,r,OBC.SP,size.r,0);
      OBC.PutB(OBC.B,OBC.pc-3); OBC.SetCondition(OBC.pc-1,OBC.NE); (* Cond code set by SUB instr *)
    ELSE
      (* Source is word-aligned, copy fast *)
      OBC.PutDP1(OBC.SUB,size.r,size.r,4);  
      OBC.PutSDT1(OBC.LDR,r,src,size.r,0);
      OBC.PutSDT1(OBC.STR,r,OBC.SP,size.r,0);
      OBC.PutB(OBC.B,OBC.pc-3); OBC.SetCondition(OBC.pc-1,OBC.NE); (* Cond code set by SUB instr *)
    END;
    INC(OBC.allowConstFlushing);
    OBC.PutSDT(OBC.STR,OBC.SP,OBC.FP,adr); (* store new address of data *)
    OBC.FreeRegs({})
  END CopyDynArray;
(*  
  PROCEDURE Result*(VAR x: OBT.Item; typ: OBT.Struct);
  VAR res: OBT.Item; regs : SET;
  BEGIN
    regs:=OBC.UsedRegisters();
    res.typ:=typ; res.r:=0; res.mode:=OC.Reg; OBC.FreeReg(0);
    IF typ.form=OC.LReal THEN res.mode:=OC.RegX; res.a:=1; OBC.FreeReg(1) END;
    Assign(res, x, FALSE);
    OBC.FreeRegs(regs);
  END Result;
*)
  PROCEDURE Result*(VAR x: OBT.Item; typ: OBT.Struct);
  VAR res, d: OBT.Item; regs: SET; par: OBT.Object;
  BEGIN
    IF typ = OBT.hptrtyp THEN  (* polpo: x into the hidden parameter, its address the result *)
      par := OBT.topScope.next; WHILE (par # NIL) & ~Hidden(par) DO par := par.next END;
      IF par = NIL THEN OBS.Mark(124); RETURN END;
      OBE.MakeItem(par, d, OBC.level); HugeAssign(d, x);
      OBE.MakeItem(par, x, OBC.level); x.mode := OC.Var; x.b := 0; x.typ := typ  (* the address in the parameter *)
    END;
    res.typ:=typ; res.r:=0;
    IF (typ.form=OC.LReal) OR (typ.form=OC.Real) THEN
      regs:=OBC.UsedRegistersF(); 
      res.mode:=OC.RegX;    
      OBC.FreeRegF(0);
      Assign(res, x, FALSE);
      OBC.FreeRegsF(regs);
    ELSE
      regs:=OBC.UsedRegisters();
      res.mode:=OC.Reg;
      OBC.FreeReg(0);
      Assign(res, x, FALSE);
      OBC.FreeRegs(regs);
    END
  END Result;

  PROCEDURE Return*(fromModBody : BOOLEAN);
  BEGIN 
    OBC.PutDP(OBC.MOV,OBC.SP,0,OBC.FP,0);
    IF fromModBody THEN
      OBC.PutBDT(OBC.LDMIA,OBC.SP,{OBC.FP,OBC.PC},TRUE);
    ELSE
      IF curProcParamSize=0 THEN
        OBC.PutBDT(OBC.LDMIA,OBC.SP,{OBC.FP,OBC.PC},TRUE);
      ELSE
        OBC.PutSDT(OBC.LDRpost,OBC.FP,OBC.SP,4); (* Restore old FP *)
        OBC.PutSDT(OBC.LDRpost,OBC.PC,OBC.SP,4+curProcParamSize); (* Return to caller *);
      END
    END
  END Return;

  PROCEDURE CaseIn*(VAR x: OBT.Item; VAR jmpadrloc, else: LONGINT);
  VAR limreg : LONGINT;
  BEGIN 
    else:=0;
    IF x.typ.form IN {OC.LInt, OC.Int, OC.SInt, OC.Char} THEN
      OBE.load(x);
      OBC.GetReg(limreg); 
      DEC(OBC.allowConstFlushing);
      OBC.PutSDT(OBC.LDR,limreg,OBC.PC,OBC.pc*4+10*4); (* load upper limit *)
      OBC.PutDP(OBC.CMP,0,x.r,limreg,0);
      OBC.PutBabs(OBC.B,else); OBC.SetCondition(OBC.pc-1,OBC.GT); else:=OBC.pc-1;
      OBC.PutSDT(OBC.LDR,limreg,OBC.PC,OBC.pc*4+8*4); (* load lower limit *)
      OBC.PutDP(OBC.CMP,0,x.r,limreg,0);
      OBC.PutBabs(OBC.B,else); OBC.SetCondition(OBC.pc-1,OBC.LT); else:=OBC.pc-1;
      OBC.PutDP(OBC.SUB,x.r,x.r,limreg,0);
      OBC.PutSDT(OBC.LDR,limreg,OBC.PC,OBC.pc*4+8); (* Load address of jump table *)
      OBC.PutSDT1(OBC.LDR,OBC.PC,limreg,x.r,2*8); (* Load adress of case-code *)
      OBC.FreeReg(limreg);
      jmpadrloc:=OBC.pc;
      INC(OBC.pc,3); (* Make space for jmp-tab-addr, upper limit, lower limit *)
      INC(OBC.allowConstFlushing);
      OBC.FlushConsts
    ELSE
      jmpadrloc:=0;
      OBS.Mark(125);
    END
  END CaseIn;

  PROCEDURE CaseOut*(jmpadrloc, L, else, n: LONGINT;  VAR tab: ARRAY OF LabelRange);
  VAR i, j: LONGINT;
  BEGIN 
    OBC.FlushConsts; (* this is important if the jump table is large! *)

    (* store limits and address of jump-table *)
    IF n>0 THEN i:=tab[n-1].high; j:=tab[0].low; ELSE i:=-1; j:=0 END;
    OBC.PutWordAt(jmpadrloc,OBC.pc*4); OBC.AddAbsFixup(jmpadrloc);
    OBC.PutWordAt(jmpadrloc+1,i);
    OBC.PutWordAt(jmpadrloc+2,j);
    
    (*generate jump table*)
    i:=tab[0].low;
    FOR j:=0 TO n-1 DO
      WHILE i<tab[j].low DO OBC.PutWord(else*4); OBC.AddAbsFixup(OBC.pc-1); INC(i) END;
      WHILE i<=tab[j].high DO OBC.PutWord(tab[j].label*4); OBC.AddAbsFixup(OBC.pc-1); INC(i) END;
    END;
    OBC.FixLink(L)
  END CaseOut;

BEGIN
  OBE.hugeOp := HugeOp; OBE.hugeMOp := HugeMOp; OBE.hugeStd1 := HugeStd1; OBE.hugeStd2 := HugeStd2
END OBH.
