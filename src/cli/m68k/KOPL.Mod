MODULE KOPL;  (* Copyright (c) Michael Franz, 1989-95 / mf 24.7.95 se 16 Aug 97 *)
(* low level code generator for the Motorola 68020 and later, with a floating point unit (68881, 68882,
  68040, 68060)
  polpo: made from aOPL of ST-Oberon V4 (Simon Egli's Atari ST port of ETH Oberon V4: Michael Franz's MacOberon
  code generator with a 68000 mode added by Simon Egli, se), on the ROP2 front end and the ROP2 object file.
  ST-Oberon came with its sources and was published in the ETH Oberon archive; polpo uses them under the
  ETH Oberon licence (LICENSE.ETH).

  Code is a sequence of 16-bit words; pc counts them. The object file holds the code as 32-bit words
  (pc rounded up to an even count), and every procedure starts at a multiple of 4 bytes, as entries
  and commands are counted in 32-bit words there.

  Registers: D0..D7 and A0..A4 are temporaries of the expressions, FP0..FP7 of the floating point ones;
  A5 is not used; A6 is the frame pointer (LINK A6), A7 the stack pointer. The caller saves the live
  registers around a call (MOVEM), so no register survives a call by itself.

  Parameters are pushed in their order, the first one at the highest address, each in 4 bytes or more
  (the stack stays aligned to 4); a nested procedure gets the static link last, at 8(A6). The callee
  removes them (RTD). Results: D0, FP0 for REAL and
  LONGREAL.

  Global variables are at negative offsets from sb, the start of the code; the constants (strings)
  are below them. A global variable, a constant, a type descriptor, the address of a procedure and a
  call into another module are absolute long addresses that the loader writes (Linux0.Fixup): in the
  code the 32-bit field holds the distance in words to the previous field of the same object (16
  bits, 0 ends the chain) and a 16-bit offset to add to the address of the object.
*)

  IMPORT OPM := ROPM, OPS := ROPS, OPT := ROPT, Files, SYSTEM;

  CONST
    (* structure forms *)
    Undef = 0; Byte = 1; Bool = 2; Char = 3; SInt = 4; Int = 5; LInt = 6;
    Real = 7; LReal = 8; Set = 9; String = 10; NilTyp = 11; NoTyp = 12;
    Pointer = 13; ProcTyp = 14; Comp = 15;
    Basic = 1; Array = 2; DynArr = 3; Record = 4;

    (* object modes *)
    Var = 1; VarPar = 2; Con = 3; Fld = 4; Typ = 5; LProc = 6; XProc = 7;
    CProc = 9; IProc = 10; TProc = 13;

    (* module visibility of objects *)
    internal = 0; external = 1; externalR = 2;

    (* history of imported objects *)
    removed = 4; inconsistent = 5;

    (* data sizes *)
    Half* = 0; Word* = 1; Long* = 2; Double* = 3; Other* = 4;

    (* register kinds; the frame pointer A6; the last address register of the expressions *)
    Dreg* = 0; Areg* = 1; Freg* = 2; FPR* = 6; MaxAreg* = 4;

    (* BOOLEAN values *)
    false* = 0; true* = 1;

    (* conditions; negative: floating point predicates *)
    ccT* = 0; ccF* = 1; ccHI* = 2; ccLS* = 3; ccCC* = 4; ccCS* = 5; ccNE* = 6; ccEQ* = 7;
    ccVC* = 8; ccVS* = 9; ccPL* = 10; ccMI* = 11; ccGE* = 12; ccLT* = 13; ccGT* = 14; ccLE* = 15;
    ccfEQ* = -1; ccfNE* = -14; ccfGT* = -18; ccfGE* = -19; ccfLT* = -20; ccfLE* = -21;

    (* item modes *)
    Dn* = 14; An* = 15; Fn* = 16; RegInd* = 17; MemInd* = 18; Indexed* = 19;
    GlobVar* = 20; GlobDes* = 21; GlobProc* = 23; Pop* = 25; Abs* = 26; Imm* = 27; CCR* = 28;

    (* modifiers of Op1 and Op2 *)
    bitSZ = 14; bitKS = 13; bitRD = 12; bitLS = 11; bitXLS = 10; bitLD = 8; bitXLD = 7;
    (* formats of Op1 *)
    opNOP1 = 5; opRx = 6; opRxLong = 7; opRy = 8; opRyLong = 9; opEa = 10;
    opEaLong = 11; opRwLong = 12; opRzRz = 13; opRzRzLong = 14;
    (* formats of Op2 *)
    opNOP2 = 16; opRyRx = 17; opRxRy = 18; opEaRn = 19; opRnEa = 20; opImmEa = 21; opEaRwLong = 22; opRwEaLong = 23;

    (* traps *)
    ZeroTrap* = 10;

    (* restrictions *)
    CodeLength = 65000;  (* words of 16 bits *)
    CodeLim = CodeLength - 1000;
    ConstLength = 16384;  (* strings, reals; conx is an INTEGER *)
    MaxComs = 128;
    MaxExts = 15;
    MaxFwd = 2048;  (* procedures called before their code *)

    NOP = 4E71H;

  TYPE
    Label* = LONGINT;

    Item* = RECORD
      mode*, inxreg*: INTEGER;
      typ*: OPT.Struct;
      adr*, disp*, descr*: LONGINT;
      alpha*, beta*: LONGINT;  (* CCR: true and false jumps; MemInd: level; Indexed: beta the scale *)
      code*: INTEGER;  (* CCR: condition; Indexed: 0 index word, 800H index long *)
      safe*: BOOLEAN;  (* not NIL *)
      dheap*: BOOLEAN;  (* open array: its descriptor at descr(adr), else in the frame of level alpha *)
      obj*: OPT.Object  (* GlobVar, GlobDes, GlobProc: the object of the chain *)
    END;

    RegSet* = ARRAY 3 OF ARRAY 8 OF SHORTINT;

  VAR
    level*: SHORTINT;
    pc*: LONGINT;
    sb*: LONGINT;  (* negative: the size of the global variables *)
    register*: RegSet;
    fpu*, c00*: BOOLEAN;  (* c00: 68000 code; not finished for polpo *)
    stksize*, maxstksize*: LONGINT;
    KNewRec*, KNewSys*, KNewArr*, GlobData*: OPT.Object;
    mRg: LONGINT;
    regerr, hostBig, CodeOvF: BOOLEAN;
    code: ARRAY CodeLength + 64 OF INTEGER;
    constant: ARRAY ConstLength OF CHAR;
    conx: LONGINT;
    nofdesc: INTEGER;
    fwdProc: ARRAY MaxFwd OF OPT.Object;
    fwdLink: ARRAY MaxFwd OF LONGINT;
    nfwd: LONGINT;
    mvInstr, fmtInstr, szInstr: ARRAY 16 OF INTEGER;
    szInstrL: ARRAY 16 OF LONGINT;
    sizeCode: ARRAY 16 OF INTEGER;
    dump*: BOOLEAN;  (* OutCode also writes the code to <module>.code, for a disassembler *)

  PROCEDURE err(n: INTEGER);
  BEGIN OPM.err(n)
  END err;

(* Code words *)

  PROCEDURE OpW*(w: LONGINT);
  BEGIN
    IF pc < CodeLength THEN code[pc] := SHORT(w MOD 10000H - 10000H * (w MOD 10000H DIV 8000H)); INC(pc)
    ELSIF ~CodeOvF THEN err(210); CodeOvF := TRUE
    END
  END OpW;

  PROCEDURE OpL*(l: LONGINT);
  BEGIN OpW(SYSTEM.LSH(l, -16)); OpW(l)
  END OpL;

  PROCEDURE GetWord(at: LONGINT): LONGINT;  (* the word at, unsigned *)
  BEGIN RETURN LONG(code[at]) MOD 10000H
  END GetWord;

  PROCEDURE SetWord(at, w: LONGINT);
  BEGIN code[at] := SHORT(w MOD 10000H - 10000H * (w MOD 10000H DIV 8000H))
  END SetWord;

  PROCEDURE Put*(w: LONGINT);  (* SYSTEM.CODE: one word if w fits 16 bits, else two *)
  BEGIN
    IF (w >= 0) & (w < 10000H) THEN OpW(w) ELSE OpL(w) END
  END Put;

  PROCEDURE Align4*;  (* the next word at a multiple of 4 bytes *)
  BEGIN IF ODD(pc) THEN OpW(NOP) END
  END Align4;

  PROCEDURE BegStat*;
  BEGIN
    IF pc > CodeLim THEN
      IF ~CodeOvF THEN err(210); CodeOvF := TRUE END;
      pc := 0
    END
  END BegStat;

  PROCEDURE EndStat*;
  END EndStat;

(* Chains the loader fixes: an absolute long field of 2 words at pc *)

  PROCEDURE Link*(obj: OPT.Object; offset: LONGINT);
    VAR d: LONGINT;
  BEGIN
    IF (offset < -8000H) OR (offset >= 8000H) THEN err(913); offset := 0 END;
    IF obj.linkadr = 0 THEN d := 0 ELSE d := pc - obj.linkadr END;
    IF d >= 10000H THEN err(914); d := 0 END;
    obj.linkadr := pc; OpW(d); OpW(offset)
  END Link;

(* Constants *)

  PROCEDURE AllocConst(cadr, len: LONGINT; VAR adr: LONGINT; align: LONGINT);
  BEGIN
    WHILE ((conx - len) MOD align) # 0 DO DEC(conx); constant[conx] := 0X END;
    IF conx - len < 255 THEN err(230); conx := LEN(constant) - 1 END;
    DEC(conx, len);
    adr := conx - LEN(constant) + sb;  (* sb is negative *)
    SYSTEM.MOVE(cadr, SYSTEM.ADR(constant[conx]), len)
  END AllocConst;

  PROCEDURE AllocString*(VAR s: ARRAY OF CHAR; len: LONGINT; VAR adr: LONGINT);
  BEGIN AllocConst(SYSTEM.ADR(s[0]), len, adr, 4)
  END AllocString;

  (* the two 32-bit words of a LONGREAL, the high one first, whatever the byte order of the host *)
  PROCEDURE LRealWords*(r: LONGREAL; VAR hi, lo: LONGINT);
  BEGIN
    IF hostBig THEN SYSTEM.GET(SYSTEM.ADR(r), hi); SYSTEM.GET(SYSTEM.ADR(r) + 4, lo)
    ELSE SYSTEM.GET(SYSTEM.ADR(r), lo); SYSTEM.GET(SYSTEM.ADR(r) + 4, hi)
    END
  END LRealWords;

  PROCEDURE AllocTypDesc*(typ: OPT.Struct);   (* typ.comp = Record *)
    VAR obj: OPT.Object; name: OPS.Name;
  BEGIN
    IF (typ.strobj = NIL) OR (typ.strobj.mnolev > 0) THEN OPT.IdFPrint(typ);  (* before deleting name *)
      (* insert a global object of that type, in order to find it in OutCode *)
      name := "@"; OPT.Insert(name, obj); obj.name := "";  (* avoid err 1 *)
      obj.mode := Typ; obj.typ := typ; typ.strobj := obj
    END;
    IF typ.extlev > MaxExts THEN err(233) END
  END AllocTypDesc;

(* Case tables *)

  PROCEDURE AllocCaseTab*(n: LONGINT; VAR tab: LONGINT);
  BEGIN tab := pc;
    IF pc < CodeLim - n THEN INC(pc, n) ELSE err(210) END
  END AllocCaseTab;

  PROCEDURE CaseJump*(L: Label; tab, from, to: LONGINT);  (* jump table in byte offsets from L *)
    VAR i, j: LONGINT;
  BEGIN i := tab + from; j := tab + to;
    WHILE i <= j DO SetWord(i, 2*(pc - L)); INC(i) END
  END CaseJump;

(* Relative branches: Bcc.W with the chain in its displacement (the word of the previous one, 0 ends) *)

  PROCEDURE Fixup*(loc: Label);
  BEGIN
    IF 2*(pc - loc) >= 8000H THEN err(211) END;
    SetWord(loc, 2*(pc - loc))
  END Fixup;

  PROCEDURE FixLink*(loc: Label);
    VAR tmp: LONGINT;
  BEGIN
    WHILE loc # 0 DO tmp := GetWord(loc); Fixup(loc); loc := tmp END
  END FixLink;

  PROCEDURE FixLinkWith*(loc, withloc: Label);
    VAR tmp: LONGINT;
  BEGIN
    WHILE loc # 0 DO tmp := GetWord(loc); SetWord(loc, 2*(withloc - loc)); loc := tmp END
  END FixLinkWith;

  PROCEDURE MergedLinks*(loc0, loc1: Label): Label;
    VAR loc2, adr: LONGINT;
  BEGIN
    IF loc0 # 0 THEN loc2 := loc0;
      LOOP adr := GetWord(loc2);
        IF adr = 0 THEN EXIT ELSE loc2 := adr END
      END;
      SetWord(loc2, loc1); RETURN loc0
    ELSE RETURN loc1
    END
  END MergedLinks;

(* Conditions *)

  PROCEDURE ^MRG(VAR x: Item);
  PROCEDURE ^XTN(VAR x: Item);
  PROCEDURE ^MultiRef*(VAR x: Item);
  PROCEDURE ^Release*(VAR x: Item);
  PROCEDURE ^Op1*(fmt: INTEGER; op: LONGINT; VAR dest: Item);
  PROCEDURE ^Op2*(fmt: INTEGER; op: LONGINT; VAR src, dest: Item);

  PROCEDURE BccLink*(cond: INTEGER; VAR L: Label);
  BEGIN
    IF cond < 0 THEN OpW(0F280H - cond) ELSE OpW(6000H + cond*100H) END;  (* FBcc.W, Bcc.W *)
    OpW(L); L := pc - 1
  END BccLink;

  PROCEDURE BccBack*(cond: INTEGER; L: Label);
    VAR disp: LONGINT;
  BEGIN disp := 2*(L - pc - 1);
    IF disp < -8000H THEN err(211) END;
    IF cond < 0 THEN OpW(0F280H - cond); OpW(disp)
    ELSIF disp >= -126 THEN OpW(6000H + cond*100H + disp MOD 100H)
    ELSE OpW(6000H + cond*100H); OpW(disp)
    END
  END BccBack;

  PROCEDURE InvertCC*(cond: INTEGER): INTEGER;
  BEGIN
    IF cond < 0 THEN
      IF cond > ccfGT THEN RETURN -15 - cond ELSE RETURN -47 - cond END
    ELSIF ODD(cond) THEN RETURN cond - 1
    ELSE RETURN cond + 1
    END
  END InvertCC;

  PROCEDURE SetCC*(VAR x: Item; cond: INTEGER);
  BEGIN Release(x); x.typ := OPT.booltyp; x.mode := CCR; x.code := cond; x.alpha := 0; x.beta := 0
  END SetCC;

  PROCEDURE LoadCC*(VAR x: Item);  (* into the condition codes *)
  BEGIN
    MRG(x); OpW(4A00H + mRg); XTN(x); Release(x);  (* TST.B x *)
    x.mode := CCR; x.code := ccNE; x.alpha := 0; x.beta := 0
  END LoadCC;

  PROCEDURE Scc(VAR cnd, dest: Item);  (* dest := 0FFH or 0 by the condition, then NEG.B: TRUE is 1 *)
    VAR d2: Item;
  BEGIN
    d2 := dest; MultiRef(dest);
    IF cnd.code < 0 THEN MRG(dest); OpW(0F240H + mRg); OpW(-cnd.code); XTN(dest)  (* FScc.B *)
    ELSE MRG(dest); OpW(50C0H + mRg + cnd.code*100H); XTN(dest)  (* Scc.B *)
    END;
    MRG(d2); OpW(4400H + mRg); XTN(d2); Release(d2)  (* NEG.B *)
  END Scc;

  PROCEDURE ResolveCC*(VAR cnd, dest: Item);  (* the condition into dest *)
    VAR L: Label; dest2: Item;
  BEGIN
    IF (cnd.alpha = 0) & (cnd.beta = 0) THEN Scc(cnd, dest)
    ELSE dest2 := dest; MultiRef(dest);
      IF cnd.code # ccT THEN BccLink(InvertCC(cnd.code), cnd.beta) END;  (* B~cond Fjmp *)
      FixLink(cnd.alpha); MRG(dest); OpW(103CH + (mRg MOD 8)*200H + (mRg DIV 8)*40H); OpW(true); XTN(dest);
      L := 0; BccLink(ccT, L); FixLink(cnd.beta);  (* Tjmp: MOVE.B #1, dest; BRA continue *)
      MRG(dest2); OpW(4200H + mRg); XTN(dest2); Release(dest2);  (* Fjmp: CLR.B dest2 *)
      Fixup(L)
    END
  END ResolveCC;

(* Traps: TRAPcc.W #n (SIGFPE, the address of the instruction in the signal) *)

  PROCEDURE Trap*(n: LONGINT);
  BEGIN OpW(50FAH); OpW(n)  (* TRAPT.W #n *)
  END Trap;

  PROCEDURE TrapCC*(VAR cnd: Item; n: LONGINT);  (* trap if cnd holds *)
  BEGIN
    IF (cnd.alpha = 0) & (cnd.beta = 0) & (cnd.code >= 0) THEN OpW(50FAH + cnd.code*100H); OpW(n)  (* TRAPcc.W #n *)
    ELSE
      IF cnd.code < 0 THEN BccBack(InvertCC(cnd.code), pc + 4)  (* FBcc.W over the trap *)
      ELSIF cnd.code # ccT THEN BccBack(InvertCC(cnd.code), pc + 3)  (* Bcc.S over the trap *)
      END;
      FixLink(cnd.alpha); Trap(n); FixLink(cnd.beta)
    END
  END TrapCC;

(* Control *)

  PROCEDURE FJ*(VAR loc: Label);
  BEGIN OpW(6000H); OpW(loc); loc := pc - 1  (* BRA.W *)
  END FJ;

  PROCEDURE BJ*(loc: Label);
  BEGIN BccBack(ccT, loc)
  END BJ;

  PROCEDURE CFJ*(VAR x: Item; VAR loc: Label);  (* on false; IF and WHILE *)
  BEGIN
    IF x.mode = CCR THEN
      IF x.code = ccT THEN loc := 0 ELSE loc := x.beta; BccLink(InvertCC(x.code), loc) END;
      FixLink(x.alpha)
    ELSIF x.mode = Imm THEN loc := 0;
      IF x.adr = false THEN BccLink(ccT, loc) END
    ELSE LoadCC(x); loc := 0; BccLink(ccEQ, loc)
    END
  END CFJ;

  PROCEDURE CBJ*(VAR x: Item; loc: Label);  (* on false; REPEAT *)
  BEGIN
    IF x.mode = CCR THEN
      IF x.code # ccT THEN BccBack(InvertCC(x.code), loc) END;
      FixLinkWith(x.beta, loc); FixLink(x.alpha)
    ELSIF x.mode # Imm THEN LoadCC(x); BccBack(ccEQ, loc)
    ELSIF x.adr = false THEN BccBack(ccT, loc)
    END
  END CBJ;

(* Registers *)

  PROCEDURE AllocA(VAR n: LONGINT);
    VAR i: INTEGER;
  BEGIN i := MaxAreg;
    LOOP
      IF register[Areg, i] = 0 THEN n := i; register[Areg, i] := 1; RETURN
      ELSIF i = 0 THEN n := 0; err(215); RETURN
      ELSE DEC(i)
      END
    END
  END AllocA;

  PROCEDURE GetA*(VAR x: Item);
  BEGIN x.mode := An; AllocA(x.adr)
  END GetA;

  PROCEDURE GetD*(VAR x: Item);
    VAR i: INTEGER;
  BEGIN x.mode := Dn; i := 7;
    LOOP
      IF register[Dreg, i] = 0 THEN x.adr := i; register[Dreg, i] := 1; RETURN
      ELSIF i = 0 THEN x.adr := 0; err(215); RETURN
      ELSE DEC(i)
      END
    END
  END GetD;

  PROCEDURE GetF*(VAR x: Item);
    VAR i: INTEGER;
  BEGIN x.mode := Fn; i := 7;
    LOOP
      IF register[Freg, i] = 0 THEN x.adr := i; register[Freg, i] := 1; RETURN END;
      IF i = 0 THEN x.adr := 0; err(215); RETURN ELSE DEC(i) END
    END
  END GetF;

  PROCEDURE MultiRef*(VAR x: Item);
  BEGIN
    IF x.mode = Dn THEN INC(register[Dreg, x.adr])
    ELSIF x.mode IN {An, RegInd, MemInd, Indexed} THEN INC(register[Areg, x.adr]);
      IF x.mode = Indexed THEN INC(register[Dreg, x.inxreg]) END
    ELSIF x.mode = Fn THEN INC(register[Freg, x.adr])
    END
  END MultiRef;

  PROCEDURE Release*(VAR x: Item);
  BEGIN
    IF x.mode = Dn THEN DEC(register[Dreg, x.adr])
    ELSIF x.mode IN {An, RegInd, MemInd, Indexed} THEN DEC(register[Areg, x.adr]);
      IF x.mode = Indexed THEN DEC(register[Dreg, x.inxreg]) END
    ELSIF x.mode = Fn THEN DEC(register[Freg, x.adr])
    END
  END Release;

  PROCEDURE ReleaseAll*;
    VAR i, j: INTEGER;
  BEGIN i := Dreg;
    WHILE i <= Freg DO j := 0; WHILE j <= 7 DO register[i, j] := 0; INC(j) END; INC(i) END;
    register[Areg, FPR] := 1; register[Areg, 7] := 1  (* never allocated *)
  END ReleaseAll;

(* Addresses *)

  PROCEDURE ^ADDA*(val, reg: LONGINT);

  PROCEDURE Small(d: LONGINT): BOOLEAN;
  BEGIN RETURN (d >= -8000H) & (d < 8000H)
  END Small;

  PROCEDURE MRG(VAR x: Item);  (* mode and register of the effective address; some addresses need code first *)
    VAR reg, disp: LONGINT;
  BEGIN
    CASE x.mode OF
    | Dn: mRg := x.adr
    | An: mRg := 8H + x.adr
    | RegInd: disp := x.disp;
        IF disp = 0 THEN mRg := 10H + x.adr
        ELSIF Small(disp) THEN mRg := 28H + x.adr
        ELSE mRg := 30H + x.adr  (* (bd.L, An) *)
        END
    | MemInd: disp := x.disp; DEC(register[Areg, x.adr]); AllocA(reg);
        IF Small(x.descr) THEN OpW(2068H + reg*200H + x.adr); OpW(x.descr)  (* MOVEA.L d16(Ax), Areg *)
        ELSE OpW(2070H + reg*200H + x.adr); OpW(170H); OpL(x.descr)  (* MOVEA.L (bd.L, Ax), Areg *)
        END;
        x.mode := RegInd; x.adr := reg;
        IF disp = 0 THEN mRg := 10H + reg
        ELSIF Small(disp) THEN mRg := 28H + reg
        ELSE mRg := 30H + reg
        END
    | Indexed: mRg := 30H + x.adr
    | GlobVar: disp := x.adr + x.disp;
        IF Small(disp) THEN mRg := 39H  (* absolute long *)
        ELSE AllocA(reg); OpW(41F9H + reg*200H); Link(x.obj, 0);  (* LEA (object).L, Areg *)
          x.mode := RegInd; x.adr := reg; x.disp := disp; mRg := 30H + reg
        END
    | GlobDes, GlobProc, Imm: mRg := 3CH
    | Abs: mRg := 39H
    | Pop: mRg := 1FH
    END
  END MRG;

  PROCEDURE XTN(VAR x: Item);  (* the extension words of the effective address *)
    VAR inx, disp: LONGINT; hi, lo: LONGINT;
  BEGIN
    CASE x.mode OF
    | Dn, An, Pop:
    | RegInd: disp := x.disp;
        IF disp # 0 THEN
          IF Small(disp) THEN OpW(disp) ELSE OpW(170H); OpL(disp) END
        END
    | Indexed: disp := x.disp; inx := x.inxreg*1000H + x.beta*200H + x.code;
        IF (disp >= -80H) & (disp < 80H) THEN OpW(inx + disp MOD 100H)
        ELSIF Small(disp) THEN OpW(inx + 120H); OpW(disp)  (* full format, bd.W *)
        ELSE OpW(inx + 130H); OpL(disp)  (* full format, bd.L *)
        END
    | GlobVar: Link(x.obj, x.adr + x.disp)
    | GlobDes, GlobProc: Link(x.obj, 0)
    | Abs: OpL(x.adr)
    | Imm:
        CASE x.typ.form OF
        | NilTyp: OpL(0)
        | Byte, Bool, Char, SInt: OpW(x.adr MOD 100H)
        | Int: OpW(x.adr)
        | LInt, Real, Set, ProcTyp, Pointer: OpL(x.adr)
        | LReal: OpL(x.adr); OpL(x.disp)  (* the high word in adr *)
        END
    END
  END XTN;

(* Moves *)

  PROCEDURE ^Ref*(VAR x: Item);

  PROCEDURE Move*(VAR src, dest: Item; f: INTEGER);
    VAR val, dmRg: LONGINT;
  BEGIN
    IF src.mode = Imm THEN val := src.adr;
      IF (val = 0) & (src.typ.form # LReal) THEN
        IF dest.mode = An THEN OpW(91C8H + dest.adr*200H + dest.adr)  (* SUBA.L An, An *)
        ELSE MRG(dest); OpW(4200H + mRg + szInstr[f]); XTN(dest)  (* CLR *)
        END
      ELSIF (dest.mode = Dn) & (val >= -80H) & (val < 80H) & (f IN {SInt, Int, LInt, Set, Pointer, ProcTyp, NilTyp}) THEN
        OpW(7000H + dest.adr*200H + val MOD 100H)  (* MOVEQ *)
      ELSE MRG(dest); OpW((mRg MOD 8)*200H + (mRg DIV 8)*40H + 3CH + mvInstr[f]);
        CASE f OF
        | Byte, Bool, Char, SInt: OpW(val MOD 100H)
        | Int: OpW(val)
        | LInt, Real, Set, ProcTyp, Pointer, NilTyp: OpL(val)
        END;
        XTN(dest)
      END
    ELSE MRG(dest); dmRg := mRg; MRG(src);
      OpW(mvInstr[f] + mRg + (dmRg MOD 8)*200H + (dmRg DIV 8)*40H); XTN(src); XTN(dest); Release(src)
    END
  END Move;

  PROCEDURE nMove*(c, rMMr: LONGINT; n: LONGINT);  (* n bytes from (As)+ to (Ad)+, Dc the counter *)
  BEGIN
    IF n <= 16 THEN
      WHILE n > 3 DO OpW(20D8H + rMMr); DEC(n, 4) END  (* MOVE.L (As)+, (Ad)+ *)
    ELSE
      IF n DIV 4 < 80H THEN OpW(7000H + c*200H + n DIV 4) ELSE OpW(203CH + c*200H); OpL(n DIV 4) END;  (* MOVEQ/MOVE.L #n DIV 4, Dc *)
      OpW(20D8H + rMMr); OpW(5380H + c); OpW(66FAH);  (* loop: MOVE.L (As)+, (Ad)+; SUBQ.L #1, Dc; BNE loop *)
      n := n MOD 4
    END;
    IF n = 1 THEN OpW(1090H + rMMr)  (* MOVE.B (As), (Ad) *)
    ELSIF n = 2 THEN OpW(3090H + rMMr)  (* MOVE.W (As), (Ad) *)
    ELSIF n = 3 THEN OpW(30D8H + rMMr); OpW(1090H + rMMr)  (* MOVE.W (As)+, (Ad)+;  MOVE.B (As), (Ad) *)
    END
  END nMove;

  PROCEDURE BlkMove*(VAR src, dest: Item; n: LONGINT);
    VAR rMMr, dmRg: LONGINT; c: Item;
  BEGIN (* n > 0 *)
    IF (n <= 4) & (n # 3) & (src.mode # Imm) THEN
      MRG(dest); dmRg := mRg; MRG(src); rMMr := mRg + (dmRg MOD 8)*200H + (dmRg DIV 8)*40H;
      IF n = 4 THEN OpW(2000H + rMMr) ELSIF n = 2 THEN OpW(3000H + rMMr) ELSE OpW(1000H + rMMr) END;
      XTN(src); XTN(dest); Release(src)
    ELSE Ref(src); Ref(dest); GetD(c); nMove(c.adr, dest.adr*200H + src.adr, n); Release(c); Release(src)
    END
  END BlkMove;

  PROCEDURE FMove*(VAR src, dest: Item);  (* REAL or LONGREAL *)
    VAR f: INTEGER; s: Item;
  BEGIN
    IF dest.mode = Fn THEN
      IF src.mode = Fn THEN OpL(0F2000000H + src.adr*400H + dest.adr*80H); Release(src)  (* FMOVE FPs, FPd *)
      ELSE f := src.typ.form;
        IF (src.mode = Imm) & (f = LReal) THEN OpW(0F23CH); OpW(5400H + dest.adr*80H); OpL(src.adr); OpL(src.disp)
        ELSE MRG(src); OpW(0F200H + mRg); OpW(4000H + fmtInstr[f] + dest.adr*80H); XTN(src)
        END;
        Release(src)
      END
    ELSIF src.mode = Fn THEN f := dest.typ.form;
      MRG(dest); OpW(0F200H + mRg); OpW(6000H + fmtInstr[f] + src.adr*80H); XTN(dest); Release(src)  (* FMOVE FPs, ea *)
    ELSIF dest.typ.form = Real THEN Move(src, dest, Real)
    ELSE (* LONGREAL from memory to memory *)
      s := src; GetF(src); FMove(s, src); FMove(src, dest)
    END
  END FMove;

  PROCEDURE Push*(VAR src: Item; f: INTEGER);
    (* every value takes 4 bytes or more, so that the stack stays aligned to 4 for the stack scan of the
      collector; a 1- or 2-byte value is at the address of its 4 bytes *)
  BEGIN
    IF f IN {Byte, Bool, Char, SInt, Int} THEN
      IF src.mode = Imm THEN
        IF f = Int THEN OpW(2F3CH); OpL(SYSTEM.LSH(src.adr MOD 10000H, 16))  (* MOVE.L #val*10000H, -(SP) *)
        ELSE OpW(2F3CH); OpL(SYSTEM.LSH(src.adr MOD 100H, 24))  (* MOVE.L #val*1000000H, -(SP) *)
        END
      ELSIF src.mode = CCR THEN
        IF src.code # ccT THEN BccLink(InvertCC(src.code), src.beta) END;
        FixLink(src.alpha); OpW(2F3CH); OpL(SYSTEM.LSH(LONG(LONG(true)), 24)); OpW(6002H); FixLink(src.beta); OpW(42A7H)
        (* Tjmp: MOVE.L #1000000H, -(SP); BRA +2; Fjmp: CLR.L -(SP) *)
      ELSE OpW(598FH);  (* SUBQ.L #4, A7 *)
        MRG(src);
        IF f = Int THEN OpW(3E80H + mRg) ELSE OpW(1E80H + mRg) END;  (* MOVE.W or MOVE.B src, (A7) *)
        XTN(src); Release(src)
      END
    ELSIF src.mode = Imm THEN OpW(2F3CH); OpL(src.adr)  (* MOVE.L #val, -(SP) *)
    ELSE MRG(src); OpW(mvInstr[f] + 0F00H + mRg); XTN(src); Release(src)  (* MOVE.L src, -(A7) *)
    END;
    INC(stksize, 4);
    src.mode := Pop;
    IF stksize > maxstksize THEN maxstksize := stksize END
  END Push;

  PROCEDURE FPush*(VAR src: Item; f: INTEGER);  (* REAL or LONGREAL *)
  BEGIN
    IF src.mode = Fn THEN OpW(0F227H); OpW(6000H + fmtInstr[f] + src.adr*80H)  (* FMOVE.f FPn, -(SP) *)
    ELSIF f = Real THEN MRG(src); OpW(2F00H + mRg); XTN(src)  (* MOVE.L src, -(SP) *)
    ELSIF src.mode = Imm THEN OpW(2F3CH); OpL(src.disp); OpW(2F3CH); OpL(src.adr)
    ELSE Ref(src); OpW(2F28H + src.adr); OpW(4); OpW(2F10H + src.adr)  (* MOVE.L 4(As), -(SP); MOVE.L (As), -(SP) *)
    END;
    Release(src); src.mode := Pop;
    IF f = Real THEN INC(stksize, 4) ELSE INC(stksize, 8) END;
    IF stksize > maxstksize THEN maxstksize := stksize END
  END FPush;

  PROCEDURE SaveRegisters*(VAR rs: RegSet);  (* the live registers onto the stack *)
    VAR i, n, m: INTEGER; fm, gr, gm: LONGINT;
  BEGIN
    rs := register; gr := 1; gm := 0; n := 0; m := 0; fm := 0;
    (* MOVEM -(A7) mask: bit 15 D0 .. bit 8 D7, bit 7 A0 .. bit 0 A7 *)
    i := MaxAreg; WHILE i >= 0 DO IF register[Areg, i] # 0 THEN INC(gm, ASH(1, 7 - i)); INC(n) END; DEC(i) END;
    i := 7; WHILE i >= 0 DO IF register[Dreg, i] # 0 THEN INC(gm, ASH(1, 15 - i)); INC(n) END; DEC(i) END;
    (* FMOVEM -(A7) mask: bit 0 FP0 .. bit 7 FP7 *)
    i := 0; WHILE i <= 7 DO IF register[Freg, i] # 0 THEN INC(fm, ASH(1, i)); INC(m) END; INC(i) END;
    IF n > 0 THEN OpW(48E7H); OpW(gm) END;  (* MOVEM.L regs, -(A7) *)
    IF fm # 0 THEN OpW(0F227H); OpW(0E000H + fm) END;  (* FMOVEM.X fregs, -(A7) *)
    INC(stksize, LONG(n)*4 + LONG(m)*12);
    IF stksize > maxstksize THEN maxstksize := stksize END;
    ReleaseAll
  END SaveRegisters;

  PROCEDURE Result*(VAR x: Item; typ: OPT.Struct);  (* the result of a function *)
  BEGIN x.typ := typ;
    IF typ # OPT.notyp THEN
      IF typ.form IN {Real, LReal} THEN x.mode := Fn; x.adr := 0; INC(register[Freg, 0])
      ELSE x.mode := Dn; x.adr := 0; INC(register[Dreg, 0])
      END
    END
  END Result;

  PROCEDURE RestoreRegisters*(rs: RegSet; VAR x: Item);
    (* rs: the registers before the call, which SaveRegisters saved; x: the result of the call (D0, FP0),
      moved first to a register free in rs if that one is in use there *)
    VAR i, n, m: INTEGER; fm, gm: LONGINT; y: Item; saved: RegSet;
  BEGIN
    saved := rs;
    IF (x.typ # OPT.notyp) & (x.mode IN {Dn, Fn}) THEN
      IF x.mode = Fn THEN
        IF rs[Freg, 0] # 0 THEN register := rs; GetF(y); rs := register;
          OpW(0F200H); OpW(y.adr*80H); x.adr := y.adr  (* FMOVE FP0, FPy *)
        ELSE INC(rs[Freg, 0])
        END
      ELSE
        IF rs[Dreg, 0] # 0 THEN register := rs; GetD(y); rs := register;
          OpW(2000H + y.adr*200H); x.adr := y.adr  (* MOVE.L D0, Dy *)
        ELSE INC(rs[Dreg, 0])
        END
      END
    END;
    gm := 0; fm := 0; n := 0; m := 0;
    (* MOVEM (A7)+ mask: bit 0 D0 .. bit 7 D7, bit 8 A0 .. bit 15 A7 *)
    i := 0; WHILE i <= 7 DO IF saved[Dreg, i] # 0 THEN INC(gm, ASH(1, i)); INC(n) END; INC(i) END;
    i := 0; WHILE i <= MaxAreg DO IF saved[Areg, i] # 0 THEN INC(gm, ASH(1, 8 + i)); INC(n) END; INC(i) END;
    (* FMOVEM (A7)+ mask: bit 7 FP0 .. bit 0 FP7 *)
    i := 0; WHILE i <= 7 DO IF saved[Freg, i] # 0 THEN INC(fm, ASH(1, 7 - i)); INC(m) END; INC(i) END;
    IF fm # 0 THEN OpW(0F21FH); OpW(0D000H + fm) END;  (* FMOVEM.X (A7)+, fregs *)
    IF n > 0 THEN OpW(4CDFH); OpW(gm) END;  (* MOVEM.L (A7)+, regs *)
    DEC(stksize, LONG(n)*4 + LONG(m)*12);
    register := rs
  END RestoreRegisters;

(* Register moves *)

  PROCEDURE LoadA*(VAR x: Item);
    VAR y: Item;
  BEGIN IF x.mode # An THEN y := x; GetA(x); Move(y, x, LInt) END
  END LoadA;

  PROCEDURE LoadD*(VAR x: Item);
    VAR y: Item;
  BEGIN IF x.mode # Dn THEN y := x; GetD(x); Move(y, x, x.typ.form) END
  END LoadD;

  PROCEDURE LoadF*(VAR x: Item);
    VAR y: Item;
  BEGIN IF x.mode # Fn THEN y := x; GetF(x); FMove(y, x); x.typ := OPT.lrltyp END
  END LoadF;

  PROCEDURE LoadX*(VAR x: Item);  (* sign extended to 32 bits; CHAR zero extended *)
    VAR y: Item; f, mode: INTEGER;
  BEGIN f := x.typ.form; mode := x.mode;
    IF f IN {Char, Byte, Bool} THEN
      IF mode = Imm THEN y := x; y.typ := OPT.linttyp; GetD(x); Move(y, x, LInt)
      ELSE y := x; GetD(x); OpW(7000H + x.adr*200H); Move(y, x, Char)  (* MOVEQ #0, Dx; MOVE.B *)
      END
    ELSE
      IF mode = Imm THEN f := LInt; x.typ := OPT.linttyp END;
      IF mode # Dn THEN y := x; GetD(x); Move(y, x, f) END;
      IF mode # Imm THEN
        IF sizeCode[f] = Half THEN OpW(49C0H + x.adr)  (* EXTB.L Dx *)
        ELSIF sizeCode[f] = Word THEN OpW(48C0H + x.adr)  (* EXT.L Dx *)
        END
      END
    END
  END LoadX;

(* Procedure calls *)

  PROCEDURE StaticLink*(lev: SHORTINT);  (* the frame pointer of level lev onto the stack *)
    VAR areg: LONGINT; ldiff: SHORTINT;
  BEGIN ldiff := level - lev;
    IF ldiff = 0 THEN OpW(2F0EH)  (* MOVE.L A6, -(A7) *)
    ELSIF ldiff = 1 THEN OpW(2F2EH); OpW(8)  (* MOVE.L 8(A6), -(A7) *)
    ELSE AllocA(areg); OpW(206EH + areg*200H); OpW(8);  (* MOVEA.L 8(A6), Ax *)
      WHILE ldiff > 2 DO DEC(ldiff); OpW(2068H + areg*200H + areg); OpW(8) END;  (* MOVEA.L 8(Ax), Ax *)
      OpW(2F28H + areg); OpW(8); DEC(register[Areg, areg])  (* MOVE.L 8(Ax), -(A7) *)
    END;
    INC(stksize, 4); IF stksize > maxstksize THEN maxstksize := stksize END
  END StaticLink;

  PROCEDURE FindFwd(proc: OPT.Object): LONGINT;
    VAR i: LONGINT;
  BEGIN i := 0;
    WHILE (i < nfwd) & (fwdProc[i] # proc) DO INC(i) END;
    RETURN i
  END FindFwd;

  PROCEDURE CallLocal*(proc: OPT.Object);  (* BSR to a procedure of this module *)
    VAR i, disp: LONGINT;
  BEGIN
    IF proc.adr # 0 THEN (* compiled *) disp := proc.adr*4 - 2*pc - 2;
      IF disp >= -80H THEN OpW(6100H + disp MOD 100H)
      ELSIF disp >= -8000H THEN OpW(6100H); OpW(disp)
      ELSE OpW(61FFH); OpL(disp)  (* BSR.L *)
      END
    ELSE i := FindFwd(proc);
      IF i = nfwd THEN
        IF nfwd < MaxFwd THEN fwdProc[nfwd] := proc; fwdLink[nfwd] := 0; INC(nfwd) ELSE err(211); RETURN END
      END;
      OpW(61FFH); OpW(SYSTEM.LSH(fwdLink[i], -16)); OpW(fwdLink[i]); fwdLink[i] := pc - 2  (* BSR.L, the chain in its displacement *)
    END
  END CallLocal;

  PROCEDURE FixProc*(proc: OPT.Object);  (* proc starts here: aligned, its entry set, its forward calls fixed *)
    VAR i, loc, next, disp: LONGINT;
  BEGIN
    Align4; proc.adr := pc DIV 2;
    i := FindFwd(proc);
    IF i < nfwd THEN loc := fwdLink[i];
      WHILE loc # 0 DO
        next := SYSTEM.LSH(GetWord(loc), 16) + GetWord(loc + 1); disp := 2*(pc - loc);
        SetWord(loc, SYSTEM.LSH(disp, -16)); SetWord(loc + 1, disp); loc := next
      END;
      fwdProc[i] := NIL; fwdLink[i] := 0
    END
  END FixProc;

  PROCEDURE CallExt*(obj: OPT.Object);  (* JSR (abs).L, fixed by the loader *)
  BEGIN OpW(4EB9H); Link(obj, 0)
  END CallExt;

  PROCEDURE Call*(psize: LONGINT; proc: OPT.Object);  (* the parameters are pushed; the callee removes them *)
    VAR i, n: LONGINT; s: OPS.String;
  BEGIN
    IF proc # NIL THEN
      IF proc.mode = CProc THEN s := proc.conval.ext^; n := ORD(s[0]); i := 1;
        WHILE i < n DO OpW(ORD(s[i])*100H + ORD(s[i+1])); INC(i, 2) END;
        IF i = n THEN err(260) END
      ELSIF proc.mnolev < 0 THEN CallExt(proc)
      ELSE
        IF proc.mnolev > 0 THEN StaticLink(proc.mnolev); INC(psize, 4) END;
        CallLocal(proc)
      END;
      IF stksize + 8 > maxstksize THEN maxstksize := stksize + 8 END;
      DEC(stksize, psize)
    END
  END Call;

(* SYSTEM.GETREG and PUTREG: 0..7 D0..D7, 8..15 A0..A7 *)

  PROCEDURE GetReg*(VAR x: Item; reg: LONGINT);  (* x := register *)
    VAR y: Item; f: INTEGER;
  BEGIN f := x.typ.form;
    IF f IN {Real, LReal} THEN y.mode := Fn; y.adr := reg MOD 8; y.typ := x.typ; INC(register[Freg, y.adr]); FMove(y, x)
    ELSE MRG(x); OpW(mvInstr[f] + (mRg MOD 8)*200H + (mRg DIV 8)*40H + reg MOD 16); XTN(x)
    END;
    Release(x)
  END GetReg;

  PROCEDURE PutReg*(VAR x: Item; reg: LONGINT);  (* register := x *)
    VAR y: Item; f: INTEGER;
  BEGIN f := x.typ.form; y.typ := x.typ;
    IF f IN {Real, LReal} THEN y.mode := Fn; y.adr := reg MOD 8; FMove(x, y)
    ELSE
      IF reg MOD 16 < 8 THEN y.mode := Dn; y.adr := reg MOD 8
      ELSE y.mode := An; y.adr := reg MOD 8;
        IF f < Int THEN f := Int; IF x.mode # Imm THEN LoadX(x) END END
      END;
      Move(x, y, f)
    END
  END PutReg;

(* Instruction formats *)

  PROCEDURE Op1*(fmt: INTEGER; op: LONGINT; VAR dest: Item);
    VAR v: SET;
  BEGIN v := SYSTEM.VAL(SET, LONG(fmt));
    IF bitSZ IN v THEN INC(op, szInstrL[dest.typ.form]) END;
    IF (bitLD IN v) & (dest.mode # Dn) THEN LoadD(dest) ELSIF bitXLD IN v THEN LoadX(dest) END;
    CASE fmt MOD 32 OF
    | opNOP1:
    | opRx: OpW(op + dest.adr)
    | opRxLong: OpL(op + dest.adr*10000H)
    | opRy: OpW(op + dest.adr*200H)
    | opRyLong: OpL(op + dest.adr*2000000H)
    | opEa: MRG(dest); OpW(op + mRg); XTN(dest)
    | opEaLong: MRG(dest); OpW(SYSTEM.LSH(op, -16) + mRg); OpW(op); XTN(dest)
    | opRwLong: OpL(op + dest.adr*1000H)
    | opRzRz: OpW(op + dest.adr*200H + dest.adr)
    | opRzRzLong: OpL(op + dest.adr*2000000H + dest.adr*10000H)
    END;
    IF bitRD IN v THEN Release(dest) END
  END Op1;

  PROCEDURE Op2*(fmt: INTEGER; op: LONGINT; VAR src, dest: Item);
    VAR v: SET;
  BEGIN v := SYSTEM.VAL(SET, LONG(fmt));
    IF bitSZ IN v THEN INC(op, szInstrL[dest.typ.form]) END;
    IF (bitLS IN v) & (src.mode # Dn) THEN LoadD(src) ELSIF bitXLS IN v THEN LoadX(src) END;
    IF (bitLD IN v) & (dest.mode # Dn) THEN LoadD(dest) ELSIF bitXLD IN v THEN LoadX(dest) END;
    CASE fmt MOD 32 OF
    | opNOP2:
    | opRyRx: OpW(op + src.adr*200H + dest.adr)
    | opRxRy: OpW(op + dest.adr*200H + src.adr)
    | opEaRn: MRG(src); OpW(op + mRg + dest.adr*200H); XTN(src)
    | opRnEa: MRG(dest); OpW(op + mRg + src.adr*200H); XTN(dest)
    | opImmEa: MRG(dest); OpW(op + mRg); XTN(src); XTN(dest)
    | opEaRwLong: MRG(src); OpW(SYSTEM.LSH(op, -16) + mRg); OpW(op + dest.adr*1000H); XTN(src)
    | opRwEaLong: MRG(dest); OpW(SYSTEM.LSH(op, -16) + mRg); OpW(op + src.adr*1000H); XTN(dest)
    END;
    IF ~(bitKS IN v) THEN Release(src) END;
    IF bitRD IN v THEN Release(dest) END
  END Op2;

  PROCEDURE FOp1*(op: LONGINT; VAR dest: Item);  (* the result in an FP register *)
    VAR src: Item;
  BEGIN
    IF dest.mode = Fn THEN OpW(0F200H); OpW(op + dest.adr*400H + dest.adr*80H)
    ELSE src := dest; GetF(dest); MRG(src); OpW(0F200H + mRg); OpW(op + 4000H + fmtInstr[src.typ.form] + dest.adr*80H);
      XTN(src); Release(src)
    END
  END FOp1;

  PROCEDURE FOp2*(op: LONGINT; VAR src, dest: Item);  (* dest := dest op src, in an FP register *)
    VAR aux: Item;
  BEGIN
    IF dest.mode # Fn THEN aux := dest; GetF(dest); FMove(aux, dest) END;
    IF src.mode = Fn THEN OpW(0F200H); OpW(op + src.adr*400H + dest.adr*80H)
    ELSIF (src.mode = Imm) & (src.typ.form = LReal) THEN OpW(0F23CH); OpW(op + 5400H + dest.adr*80H); OpL(src.adr); OpL(src.disp)
    ELSE MRG(src); OpW(0F200H + mRg); OpW(op + 4000H + fmtInstr[src.typ.form] + dest.adr*80H); XTN(src)
    END;
    Release(src)
  END FOp2;

(* Auxiliary *)

  PROCEDURE ADDA*(val, reg: LONGINT);  (* add a constant to an address register *)
  BEGIN
    IF val # 0 THEN
      IF (val > 0) & (val <= 8) THEN OpW(5088H + (val MOD 8)*200H + reg)  (* ADDQ.L #val, Ar *)
      ELSIF (val < 0) & (val >= -8) THEN OpW(5188H + ((-val) MOD 8)*200H + reg)  (* SUBQ.L #-val, Ar *)
      ELSIF Small(val) THEN OpW(41E8H + reg*200H + reg); OpW(val)  (* LEA val(Ar), Ar *)
      ELSE OpW(0D1FCH + reg*200H); OpL(val)  (* ADDA.L #val, Ar *)
      END;
      IF reg = 7 THEN DEC(stksize, val);
        IF (val < 0) & (stksize > maxstksize) THEN maxstksize := stksize END
      END
    END
  END ADDA;

(* Addresses *)

  PROCEDURE Ref*(VAR x: Item);  (* the address of x into an address register: x.mode := RegInd, disp 0 *)
    VAR reg: LONGINT;
  BEGIN
    IF (x.mode = RegInd) & (x.adr # FPR) & (register[Areg, x.adr] = 1) THEN ADDA(x.disp, x.adr); IF x.dheap THEN DEC(x.descr, x.disp) END
    ELSE AllocA(reg);
      IF (x.mode = MemInd) & Small(x.descr) THEN DEC(register[Areg, x.adr]);
        OpW(2068H + reg*200H + x.adr); OpW(x.descr); ADDA(x.disp, reg)  (* MOVEA.L d(Ax), Areg *)
      ELSE MRG(x); OpW(41C0H + mRg + reg*200H); XTN(x); Release(x)  (* LEA x, Areg *)
      END;
      x.adr := reg
    END;
    x.mode := RegInd; x.disp := 0
  END Ref;

  PROCEDURE RefToStk*(VAR x: Item);  (* push the address of x *)
  BEGIN
    IF (x.mode = MemInd) & (x.disp = 0) & Small(x.descr) THEN OpW(2F28H + x.adr); OpW(x.descr)  (* MOVE.L d(Ax), -(SP) *)
    ELSE MRG(x); OpW(4840H + mRg); XTN(x)  (* PEA x *)
    END;
    Release(x);
    INC(stksize, 4); IF stksize > maxstksize THEN maxstksize := stksize END
  END RefToStk;

  PROCEDURE NilCheck*(VAR x: Item);  (* x addressed through a pointer: a NIL pointer traps on access anyway *)
  BEGIN x.safe := TRUE
  END NilCheck;

  PROCEDURE DeRef*(VAR x: Item);  (* x := x^ *)
    VAR reg: LONGINT;
  BEGIN
    IF x.mode # An THEN AllocA(reg);
      MRG(x); OpW(2040H + mRg + reg*200H); XTN(x); Release(x); x.adr := reg  (* MOVEA.L x, Areg *)
    END;
    x.mode := RegInd; x.disp := 0; x.safe := FALSE
  END DeRef;

  PROCEDURE LocalVar*(VAR x: Item; lev: INTEGER; adr: LONGINT; indirect: BOOLEAN);
    VAR reg: LONGINT; ldiff: INTEGER;
  BEGIN ldiff := level - lev;
    IF ldiff = 0 THEN INC(register[Areg, FPR]); x.adr := FPR
    ELSE AllocA(reg); x.adr := reg; OpW(206EH + reg*200H); OpW(8);  (* MOVEA.L 8(A6), Ax: the static link *)
      WHILE ldiff > 1 DO DEC(ldiff); OpW(2068H + reg*200H + reg); OpW(8) END  (* MOVEA.L 8(Ax), Ax *)
    END;
    IF indirect THEN x.mode := MemInd; x.disp := 0; x.descr := adr; x.alpha := lev
    ELSE x.mode := RegInd; x.disp := adr
    END;
    x.safe := TRUE; x.dheap := FALSE
  END LocalVar;

  PROCEDURE TestRegs*;
    VAR i: INTEGER;
  BEGIN
    IF ~regerr & OPM.noerr THEN
      i := MaxAreg; WHILE i >= 0 DO IF register[Areg, i] # 0 THEN err(-(1008 + i)); regerr := TRUE END; DEC(i) END;
      i := 7; WHILE i >= 0 DO IF register[Dreg, i] # 0 THEN err(-(1000 + i)); regerr := TRUE END; DEC(i) END;
      i := 7; WHILE i >= 0 DO IF register[Freg, i] # 0 THEN err(-(1100 + i)); regerr := TRUE END; DEC(i) END;
      IF regerr THEN OPM.LogWStr(" at pc "); OPM.LogWNum(2*pc, 1) END
    END;
    ReleaseAll  (* after a statement no register is in use *)
  END TestRegs;

  PROCEDURE TestStack*;
  BEGIN
    IF ~regerr & OPM.noerr & (stksize # 0) THEN err(-1050); OPM.LogWNum(stksize, 1); stksize := 0 END
  END TestStack;

(* Reference information: as the ROP2 back ends write it (Kernel.FindProcU); the end of each procedure in
  32-bit words, no saved registers, the frame of A6 *)

  PROCEDURE OutRefPoint*;
  BEGIN
    OPM.RefW(0F8X); OPM.RefWNum((pc + 1) DIV 2);
    OPM.RefWNum(0); OPM.RefWNum(0); OPM.RefWNum(0); OPM.RefWNum(0)
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
      OutRefs(obj.left);
      IF (obj.mode = Var) OR (obj.mode = VarPar) THEN
        f := obj.typ.form;
        IF (f IN {Byte .. Set, Pointer, ProcTyp}) OR (obj.typ.comp = Array) & (obj.typ.BaseTyp.form = Char) THEN
          IF (obj.mode = Var) & ((obj.typ.comp # Array) OR (obj.adr < 0)) THEN OPM.RefW(1X)
          ELSE OPM.RefW(3X)  (* also an array value parameter: its slot holds the address of the copy (KOPC.CopyPar) *)
          END;
          IF obj.typ.comp = Array THEN OPM.RefW(0FX) ELSE OPM.RefW(CHR(f)) END;
          OPM.RefWNum(obj.adr);
          OutRefName(obj.name)
        END
      END;
      OutRefs(obj.right)
    END
  END OutRefs;

(* Object file *)

  PROCEDURE FindPtrs*(typ: OPT.Struct; adr: LONGINT; VAR tab: ARRAY OF LONGINT; VAR last: INTEGER);
    VAR fld: OPT.Object; btyp: OPT.Struct; i, n: LONGINT; last1: INTEGER;

    PROCEDURE Add(adr: LONGINT);
    BEGIN IF last < LEN(tab) THEN tab[last] := adr; INC(last) END
    END Add;

  BEGIN
    IF typ.form = Pointer THEN Add(adr)
    ELSIF typ.comp = Record THEN
      btyp := typ.BaseTyp;
      IF btyp # NIL THEN FindPtrs(btyp, adr, tab, last) END;
      fld := typ.link;
      WHILE (fld # NIL) & (fld.mode = Fld) DO
        IF fld.name = OPM.HdPtrName THEN Add(fld.adr + adr)
        ELSE FindPtrs(fld.typ, fld.adr + adr, tab, last)
        END;
        fld := fld.link
      END
    ELSIF typ.comp = Array THEN
      btyp := typ.BaseTyp; n := typ.n;
      WHILE btyp.comp = Array DO n := btyp.n * n; btyp := btyp.BaseTyp END;
      IF (btyp.form = Pointer) OR (btyp.comp = Record) THEN
        last1 := last; FindPtrs(btyp, adr, tab, last);
        IF last # last1 THEN i := 1;
          WHILE (i < n) & (last < LEN(tab)) DO INC(adr, btyp.size); FindPtrs(btyp, adr, tab, last); INC(i) END
        END
      END
    END
  END FindPtrs;

  PROCEDURE WLink(obj: OPT.Object);
  BEGIN OPM.ObjWNum(obj.linkadr)
  END WLink;

  PROCEDURE WName(VAR name: OPS.Name);
    VAR ch: CHAR; i: INTEGER;
  BEGIN i := 0;
    REPEAT ch := name[i]; OPM.ObjW(ch); INC(i) UNTIL ch = 0X
  END WName;

  PROCEDURE WTDesc(typ: OPT.Struct);
    VAR btyp: OPT.Struct; nofinhmth, nofptr, i: INTEGER;
      ptrTab: ARRAY OPM.MaxPtr + 1 OF LONGINT;
  BEGIN
    IF typ.ref >= 0 THEN
      btyp := typ.BaseTyp;
      typ.ref := -nofdesc - 1; INC(nofdesc);
      OPM.ObjW(8X); WName(typ.strobj.name);
      IF typ.strobj.name = "" THEN OPT.FPrintStr(typ); OPM.ObjWNum(typ.pvfp) END;
      WLink(typ.strobj); OPM.ObjWNum(typ.size);
      IF btyp = NIL THEN nofinhmth := 0; OPM.ObjWNum(-1)
      ELSE nofinhmth := SHORT(btyp.n);
        OPM.ObjWNum(btyp.mno); WName(btyp.strobj.name);
        IF btyp.strobj.name = "" THEN OPT.FPrintStr(btyp); OPM.ObjWNum(btyp.pvfp) END
      END;
      OPM.ObjWNum(typ.n);  (* methods *)
      OPM.ObjWNum(nofinhmth);
      OPM.ObjWNum(0);  (* new methods: none, type-bound procedures are refused *)
      nofptr := 0; FindPtrs(typ, 0, ptrTab, nofptr);
      IF nofptr > OPM.MaxPtr THEN err(221) END;
      OPM.ObjWNum(nofptr);
      i := 0;
      WHILE i < nofptr DO OPM.ObjWNum(ptrTab[i]); INC(i) END
    END
  END WTDesc;

  PROCEDURE DumpCode;
    VAR f: Files.File; r: Files.Rider; name: ARRAY 64 OF CHAR; i, n: LONGINT;
  BEGIN
    COPY(OPT.SelfName, name); i := 0; WHILE name[i] # 0X DO INC(i) END;
    name[i] := "."; name[i+1] := "c"; name[i+2] := "o"; name[i+3] := "d"; name[i+4] := "e"; name[i+5] := 0X;
    f := Files.New(name); Files.Set(r, f, 0); n := 0;
    WHILE n < pc DO Files.Write(r, CHR(GetWord(n) DIV 100H)); Files.Write(r, CHR(GetWord(n) MOD 100H)); INC(n) END;
    Files.Register(f)
  END DumpCode;

  PROCEDURE OutCode*;
    VAR i, nofexp, nofcom, nofptr: INTEGER; n: LONGINT;
      obj: OPT.Object;
      ptrTab: ARRAY OPM.MaxGPtr + 1 OF LONGINT;
      ComTab: ARRAY MaxComs OF OPT.Object;

    PROCEDURE Export(obj: OPT.Object);

      PROCEDURE WStruct(obj: OPT.Object);
        VAR strobj: OPT.Object; typ: OPT.Struct;
      BEGIN
        typ := obj.typ; strobj := typ.strobj;
        IF (strobj = obj) & (typ.form = Comp) THEN  (* not an alias *)
          IF (strobj.name # "") & (typ.ref # OPM.MaxStruct) THEN  (* named and exported type *)
            INC(nofexp, 2);  (* pbfp and pvfp *)
            OPM.ObjW(6X); WName(strobj.name); OPT.FPrintStr(typ);
            OPM.ObjWNum(typ.pbfp); OPM.ObjWNum(typ.pvfp)
          END;
          IF typ.comp = Record THEN WTDesc(obj.typ) END
        END
      END WStruct;

    BEGIN
      IF obj # NIL THEN
        Export(obj.left);
        IF obj.history # removed THEN
          IF obj.vis # internal THEN OPT.FPrintObj(obj);
            IF obj.mode = Con THEN INC(nofexp);
              OPM.ObjW(1X); WName(obj.name); OPM.ObjWNum(obj.fprint)
            ELSIF obj.mode = Typ THEN INC(nofexp);
              OPM.ObjW(2X); WName(obj.name); OPM.ObjWNum(obj.fprint); WStruct(obj)
            ELSIF obj.mode = Var THEN INC(nofexp);
              OPM.ObjW(3X); WName(obj.name); OPM.ObjWNum(obj.fprint); OPM.ObjWNum(obj.adr);
              FindPtrs(obj.typ, obj.adr, ptrTab, nofptr)
            ELSIF obj.mode IN {XProc, IProc} THEN INC(nofexp);
              OPM.ObjW(4X); WName(obj.name); OPM.ObjWNum(obj.fprint); OPM.ObjWNum(obj.adr);
              IF obj.linkadr # 0 (* assigned *) THEN OPM.ObjW(9X); OPM.ObjWNum(obj.adr); WLink(obj) END;
              IF (obj.link = NIL) & (obj.typ = OPT.notyp) THEN  (* command *)
                IF nofcom < MaxComs THEN ComTab[nofcom] := obj; INC(nofcom)
                ELSE err(232); nofcom := 0
                END
              END
            ELSIF obj.mode = CProc THEN INC(nofexp);
              OPM.ObjW(5X); WName(obj.name); OPM.ObjWNum(obj.fprint)
            END
          ELSIF obj.mode = Typ THEN WStruct(obj)
          ELSIF obj.mode = Var THEN FindPtrs(obj.typ, obj.adr, ptrTab, nofptr)
          ELSIF (obj.mode IN {LProc, XProc, IProc}) & (obj.linkadr # 0) THEN  (* assigned *)
            OPM.ObjW(9X); OPM.ObjWNum(obj.adr); WLink(obj)
          END
        END;
        Export(obj.right)
      END
    END Export;

    PROCEDURE Use(obj: OPT.Object);
      VAR typ: OPT.Struct; strobj: OPT.Object;
    BEGIN
      IF obj # NIL THEN
        Use(obj.left);
        IF obj.used THEN OPT.FPrintObj(obj);
          IF obj.mode = Con THEN
            OPM.ObjW(1X); WName(obj.name); OPM.ObjWNum(obj.fprint)
          ELSIF obj.mode = Typ THEN
            OPM.ObjW(2X); WName(obj.name); OPM.ObjWNum(obj.fprint)
          ELSIF obj.mode = Var THEN
            OPM.ObjW(3X); WName(obj.name); OPM.ObjWNum(obj.fprint); WLink(obj)
          ELSIF obj.mode IN {XProc, IProc} THEN
            OPM.ObjW(4X); WName(obj.name); OPM.ObjWNum(obj.fprint); WLink(obj)
          ELSIF obj.mode = CProc THEN
            OPM.ObjW(5X); WName(obj.name); OPM.ObjWNum(obj.fprint)
          END
        END;
        IF obj.mode = Typ THEN typ := obj.typ; strobj := typ.strobj;
          IF (typ.form = Comp) & (strobj = obj) THEN OPT.FPrintStr(typ);
            IF strobj.name # "" THEN
              IF typ.pvused THEN OPM.ObjW(7X); WName(strobj.name); OPM.ObjWNum(typ.pvfp);
                IF obj.history = inconsistent THEN OPT.FPrintErr(obj, 249) END
              ELSIF typ.pbused THEN OPM.ObjW(6X); WName(strobj.name); OPM.ObjWNum(typ.pbfp)
              END
            END;
            IF (typ.comp = Record) & (strobj.linkadr # 0) THEN
              OPM.ObjW(8X); WName(strobj.name);
              IF strobj.name = "" THEN OPM.ObjWNum(typ.pvfp) END;
              WLink(strobj)
            END
          END
        END;
        Use(obj.right)
      END
    END Use;

  BEGIN
    i := 0;
    WHILE i < nfwd DO
      IF fwdProc[i] # NIL THEN OPM.Mark(129, fwdProc[i].scope.adr) END;  (* called, never compiled *)
      INC(i)
    END;
    WHILE pc MOD 4 # 0 DO OpW(NOP) END;  (* an even number of 32-bit words, as the loaders count the module block *)
    WHILE (conx MOD 8) # 0 DO DEC(conx); constant[conx] := 0X END;
  (* HeaderBlk *)
    nofexp := 0; nofdesc := 0; nofcom := 0; nofptr := 0;
    OPM.ObjWNum(OPT.nofGmod - 1); WLink(KNewRec); WLink(KNewSys); WLink(KNewArr);
    WLink(GlobData); OPM.ObjWNum(-sb);
    OPM.ObjWNum(LEN(constant) - conx);
    OPM.ObjWNum(pc DIV 2); WName(OPT.SelfName);
  (* ImpBlk *)
    OPM.ObjW(81X); i := 1;
    WHILE i < OPT.nofGmod DO WName(OPT.GlbMod[i].name); INC(i) END;
  (* ExpBlk *)
    OPM.ObjW(82X);
    Export(OPT.topScope.right);  (* exports, commands and pointers *)
    IF nofptr > OPM.MaxGPtr THEN err(222) END;
    OPM.ObjW(0X);
  (* CmdBlk *)
    OPM.ObjW(83X); i := 0;
    WHILE i < nofcom DO obj := ComTab[i]; WName(obj.name); OPM.ObjWNum(obj.adr); INC(i) END;
  (* PtrBlk *)
    OPM.ObjW(84X); i := 0;
    WHILE i < nofptr DO OPM.ObjWNum(ptrTab[i]); INC(i) END;
  (* ConstBlk *)
    OPM.ObjW(87X);
    n := 0;
    WHILE n < LEN(constant) - conx DO constant[n] := constant[conx + n]; INC(n) END;
    OPM.ObjWBytes(constant, LEN(constant) - conx);
  (* CodeBlk: 32-bit words, the first word of the code in the high half *)
    OPM.ObjW(88X); n := 0;
    WHILE n < pc DO OPM.ObjWLInt(SYSTEM.LSH(GetWord(n), 16) + GetWord(n + 1)); INC(n, 2) END;
  (* UseBlk *)
    OPM.ObjW(89X); i := 1;
    WHILE i < OPT.nofGmod DO Use(OPT.GlbMod[i].right); OPM.ObjW(0X); INC(i) END;
  (* RefBlk written in OPM.RegisterRefObj *)
    IF OPM.noerr THEN OPM.RegisterRefObj(nofexp, nofdesc, nofcom, nofptr) END;
    OPM.pc := pc DIV 2; OPM.sb := sb;
    IF dump & OPM.noerr THEN DumpCode END
  END OutCode;

  PROCEDURE Init*(opt: SET);
    VAR w: LONGINT; c: CHAR;
  BEGIN
    w := 1; SYSTEM.GET(SYSTEM.ADR(w), c); hostBig := c = 0X;
    fpu := TRUE; c00 := FALSE;
    pc := 0; level := 0; sb := 0; conx := LEN(constant); nfwd := 0;
    stksize := 0; maxstksize := 0; regerr := FALSE; CodeOvF := FALSE;
    KNewRec.linkadr := 0; KNewSys.linkadr := 0; KNewArr.linkadr := 0; GlobData.linkadr := 0;
    ReleaseAll
  END Init;

  PROCEDURE Close*;
    VAR i: LONGINT;
  BEGIN i := 0; WHILE i < nfwd DO fwdProc[i] := NIL; INC(i) END; nfwd := 0
  END Close;

BEGIN
  NEW(KNewRec); NEW(KNewSys); NEW(KNewArr); NEW(GlobData);
  mvInstr[Byte] := 1000H; mvInstr[Bool] := 1000H; mvInstr[Char] := 1000H; mvInstr[SInt] := 1000H; mvInstr[Int] := 3000H;
  mvInstr[LInt] := 2000H; mvInstr[Real] := 2000H; mvInstr[Set] := 2000H; mvInstr[NilTyp] := 2000H;
  mvInstr[ProcTyp] := 2000H; mvInstr[Pointer] := 2000H;
  szInstr[Int] := 40H; szInstr[LInt] := 80H; szInstr[Real] := 80H; szInstr[Set] := 80H; szInstr[NilTyp] := 80H;
  szInstr[ProcTyp] := 80H; szInstr[Pointer] := 80H;
  szInstrL[Int] := 40H; szInstrL[LInt] := 80H; szInstrL[Real] := 80H; szInstrL[Set] := 80H; szInstrL[NilTyp] := 80H;
  szInstrL[ProcTyp] := 80H; szInstrL[Pointer] := 80H;
  fmtInstr[SInt] := 6*400H; fmtInstr[Int] := 4*400H; fmtInstr[LInt] := 0; fmtInstr[Real] := 400H; fmtInstr[LReal] := 5*400H;
  sizeCode[Byte] := Half; sizeCode[Bool] := Half; sizeCode[Char] := Half; sizeCode[SInt] := Half;
  sizeCode[Int] := Word; sizeCode[LInt] := Long; sizeCode[Real] := Long; sizeCode[LReal] := Double; sizeCode[Set] := Long;
  sizeCode[NilTyp] := Long; sizeCode[ProcTyp] := Long; sizeCode[Pointer] := Long
END KOPL.
