(* the console browser of the ROP2 ports (RISC-V, MIPS, ARMv7): the interface of a module from
   its symbol file in obj/<arch>/. From Browser of OLR ROP2 (RC 29.10.93, Peter Matthias
   2015-07-07), the viewers taken out: the definition is written to the terminal; the
   arguments and options as those of the x86 browser. *)

MODULE browser;

  IMPORT
    OPM := ROPM, OPS := ROPS, OPT := ROPT, Linux0, Modules, Root,
    Texts := texts, Oberon := Oberon0, out;

  CONST
    (* object modes *)
    Var = 1; VarPar = 2; Con = 3; Fld = 4; Typ = 5; LProc = 6; XProc = 7;
    SProc = 8; CProc = 9; IProc = 10; Mod = 11; Head = 12; TProc = 13;

    (* structure forms *)
    Undef = 0; Byte = 1; Bool = 2; Char = 3; SInt = 4; Int = 5; LInt = 6;
    Real = 7; LReal = 8; Set = 9; String = 10; NilTyp = 11; NoTyp = 12;
    Pointer = 13; ProcTyp = 14; Comp = 15;

    (* composite structure forms *)
    Basic = 1; Array = 2; DynArr = 3; Record = 4;

    (* module visibility of objects *)
    internal = 0; external = 1; externalR = 2;

  VAR
    W: Texts.Writer;
    option: CHAR;  (* "x": with addresses, offsets and sizes (/d) *)
    extend: BOOLEAN;  (* /e: records with the fields of their base types *)
    m: Modules.Module;

  PROCEDURE Ws(s: ARRAY OF CHAR); BEGIN Texts.WriteString(W, s) END Ws;
  PROCEDURE Wch(ch: CHAR); BEGIN Texts.Write(W, ch) END Wch;
  PROCEDURE Wi(i: LONGINT); BEGIN Texts.WriteInt(W, i, 0) END Wi;
  PROCEDURE Wln; BEGIN Texts.WriteLn(W) END Wln;

  PROCEDURE Mrk(vis: SHORTINT);  (* the export mark, as the x86 browser writes it *)
  BEGIN IF vis = external THEN Wch("*") ELSIF vis = externalR THEN Wch("-") END
  END Mrk;

  PROCEDURE Indent(i: INTEGER);
  BEGIN WHILE i > 0 DO Wch(9X); DEC(i) END
  END Indent;

  PROCEDURE ^Wtype(typ: OPT.Struct);
  PROCEDURE ^Wstruct(typ: OPT.Struct);

  PROCEDURE Wsign(result: OPT.Struct; par: OPT.Object);
    VAR paren, res, first: BOOLEAN;
  BEGIN first := TRUE;
    res := (result # NIL) (* hidden mthd *) & (result # OPT.notyp);
    paren := res OR (par # NIL);
    IF paren THEN Wch("(") END ;
    WHILE par # NIL DO
      IF ~first THEN Ws("; ") ELSE first := FALSE END ;
      IF option = "x" THEN Wi(par^.adr); Wch(" ") END ;
      IF par^.mode = VarPar THEN Ws("VAR ") END ;
      Ws(par^.name);
      WHILE (par^.link # NIL) & (par^.link^.typ = par^.typ) & (par^.link^.mode = par^.mode) DO  (* a, b: T *)
        par := par^.link; Ws(", "); IF option = "x" THEN Wi(par^.adr); Wch(" ") END; Ws(par^.name)
      END;
      Ws(": "); Wtype(par^.typ);
      par := par^.link
    END ;
    IF paren THEN Wch(")") END ;
    IF res THEN Ws(": "); Wtype(result) END
  END Wsign;

  PROCEDURE Objects(obj: OPT.Object; mode: SET);
    VAR i: LONGINT; m: INTEGER; s: SET; ext: OPT.ConstExt;
  BEGIN
    IF obj # NIL THEN
      Objects(obj^.left, mode);
      IF obj^.mode IN mode THEN
        CASE obj^.mode OF
        | Con:
            Indent(2); Ws(obj^.name); Mrk(obj^.vis); Ws(" = ");
            CASE obj^.typ^.form OF
            | Bool:
                IF obj^.conval^.intval = 1 THEN Ws("TRUE") ELSE Ws("FALSE") END
            | Char:
                IF (obj^.conval^.intval >= 32) & (obj^.conval^.intval <= 126) THEN
                  Wch(22X); Wch(CHR(obj^.conval^.intval)); Wch(22X)
                ELSE
                  i := obj^.conval^.intval DIV 16;
                  IF i > 9 THEN Wch(CHR(55 + i)) ELSE Wch(CHR(48 + i)) END ;
                  i := obj^.conval^.intval MOD 16;
                  IF i > 9 THEN Wch(CHR(55 + i)) ELSE Wch(CHR(48 + i)) END ;
                  Wch("X")
                END
            | SInt, Int, LInt:
                Wi(obj^.conval^.intval)
            | Set:
                Wch("{"); i := 0; s := obj^.conval^.setval;
                WHILE i <= MAX(SET) DO
                  IF i IN s THEN Wi(i); EXCL(s, i);
                    IF s # {} THEN Ws(", ") END
                  END ;
                  INC(i)
                END ;
                Wch("}")
            | Real:
                Texts.WriteReal(W, SHORT(obj^.conval^.realval), 16)
            | LReal:
                Texts.WriteLongReal(W, obj^.conval^.realval, 23)
            | String:
                Wch(22X); Ws(obj^.conval^.ext^); Wch(22X)
            | NilTyp:
                Ws("NIL")
            END ;
            Wch(";"); Wln
        | Typ:
            IF obj^.name # "" THEN Indent(2);
              IF obj^.typ^.strobj = obj THEN  (* canonical name *)
                Ws(obj^.name); Mrk(obj^.vis); Ws(" = "); Wstruct(obj^.typ)
              ELSE  (* alias *)
                Ws(obj^.name); Mrk(obj^.vis); Ws(" = "); Wtype(obj^.typ)
              END ;
              Wch(";"); Wln
            END
        | Var:
            Indent(2); IF option = "x" THEN Wi(obj^.adr); Wch(" ") END; Ws(obj^.name); Mrk(obj^.vis); Ws(": ");
            Wtype(obj^.typ); Wch(";"); Wln
        | XProc, CProc, IProc:
            Indent(1); Ws("PROCEDURE ");
            IF obj^.mode = IProc THEN Wch("+")
            ELSIF obj^.mode = CProc THEN Wch("-")
            END ;
            Ws(obj^.name); Wch("*");
            Wsign(obj^.typ, obj^.link);
            IF obj^.mode = CProc THEN
              ext := obj^.conval^.ext; m := ORD(ext^[0]); i := 1; Wch(" ");
              WHILE i <= m DO Wi(ORD(ext^[i]));
                IF i < m THEN Ws(", ") END ;
                INC(i)
              END ;
            END ;
            Wch(";"); Wln
        END
      END ;
      Objects(obj^.right, mode)
    END
  END Objects;

  PROCEDURE Wmthd(obj: OPT.Object);
  BEGIN
    IF obj # NIL THEN
      Wmthd(obj^.left);
      IF obj^.mode = TProc THEN
        Indent(3); Ws("PROCEDURE (");
        IF obj^.name # OPM.HdTProcName THEN
          IF obj^.link^.mode = VarPar THEN Ws("VAR ") END ;
          Ws(obj^.link^.name); Ws(": "); Wtype(obj^.link^.typ)
        END ;
        Ws(") "); Ws(obj^.name); Mrk(obj^.vis);
        Wsign(obj^.typ, obj^.link^.link);
        Wch(";");
        IF option = "x" THEN Indent(1);
          Ws("(* methno: "); Wi(obj^.adr DIV 10000H);  Ws(" *)")
        END ;
        Wln;
      END ;
      Wmthd(obj^.right)
    END
  END Wmthd;

  (* the fields of the record typ (not those of its base types) *)
  PROCEDURE Wfields(typ: OPT.Struct);
    VAR fld: OPT.Object;
  BEGIN
    fld := typ^.link;
    WHILE (fld # NIL) & (fld^.mode = Fld) DO
      IF (option = "x") OR (fld^.name[0] # "@") THEN Indent(3);
        IF option = "x" THEN Wi(fld^.adr); Wch(" ") END ;
        Ws(fld^.name); Mrk(fld^.vis);
        WHILE (option # "x") & (fld^.link # NIL) & (fld^.link^.mode = Fld) & (fld^.link^.typ = fld^.typ)
          & (fld^.link^.name[0] # "@") DO  (* a, b: T, as the x86 browser *)
          fld := fld^.link; Ws(", "); Ws(fld^.name); Mrk(fld^.vis)
        END;
        Ws(": "); Wtype(fld^.typ); Wch(";");
        Wln
      END ;
      fld := fld^.link
    END
  END Wfields;

  (* /e: the fields of the base types of a record, the first base type first *)
  PROCEDURE Wbases(typ: OPT.Struct);
  BEGIN
    IF typ^.BaseTyp # NIL THEN Wbases(typ^.BaseTyp) END;
    Indent(3); Ws("(* "); Wtype(typ); Ws(" *)"); Wln;
    Wfields(typ)
  END Wbases;

  PROCEDURE Wstruct(typ: OPT.Struct);

    PROCEDURE SysFlag;
    BEGIN
      IF typ^.sysflag # 0 THEN
        Wch("["); Wi(typ^.sysflag); Ws("] ")
      END
    END SysFlag;

  BEGIN
    CASE typ^.form OF
    | Undef:
        Ws("Undef")
    | Pointer:
        Ws("POINTER "); SysFlag; Ws("TO "); Wtype(typ^.BaseTyp)
    | ProcTyp:
        Ws("PROCEDURE"); SysFlag; Wsign(typ^.BaseTyp, typ^.link)
    | Comp:
        CASE typ^.comp OF
        | Array:
            Ws("ARRAY "); SysFlag; Wi(typ^.n); Ws(" OF "); Wtype(typ^.BaseTyp)
        | DynArr:
            Ws("ARRAY "); SysFlag; Ws("OF "); Wtype(typ^.BaseTyp)
        | Record:
            Ws("RECORD ");SysFlag;
            IF (typ^.BaseTyp # NIL) & ~extend THEN Wch("("); Wtype(typ^.BaseTyp); Wch(")") END ;
            Wln;
            IF (typ^.BaseTyp # NIL) & extend THEN Wbases(typ^.BaseTyp); Indent(3); Ws("(* own fields *)"); Wln END;
            Wfields(typ);
            Wmthd(typ^.link);
            Indent(2); Ws("END ");
            IF option = "x" THEN Indent(1);
              Ws("(* size: "); Wi(typ^.size); Ws(" align: "); Wi(typ^.align);
              Ws(" nofm: "); Wi(typ^.n); Ws(" *)")
            END
        END
    END
  END Wstruct;

  PROCEDURE Wtype(typ: OPT.Struct);
    VAR obj: OPT.Object;
  BEGIN
    obj := typ^.strobj;
    IF obj^.name # "" THEN
      IF typ^.mno # 0 THEN Ws(OPT.GlbMod[typ^.mno].name); Wch(".")
      ELSIF (typ = OPT.bytetyp) OR (typ = OPT.sysptrtyp) THEN Ws("SYSTEM.")
      ELSIF obj^.vis = internal THEN Wch("#")
      END ;
      Ws(obj^.name)
    ELSE
      IF (option = "x") & (typ^.ref > OPM.MaxStruct) THEN Wch("#"); Wi(typ^.ref - OPM.MaxStruct); Wch(" ") END ;
      Wstruct(typ)
    END
  END Wtype;

  (* the definition of the module name into T; FALSE if it has no symbol file *)
  PROCEDURE WModule(name: OPS.Name; T: Texts.Text): BOOLEAN;
    VAR i: INTEGER;
      beg, end: LONGINT; first, done: BOOLEAN;

    PROCEDURE Header(s: ARRAY OF CHAR);
    BEGIN
      beg := W.buf.len; Indent(1); Ws(s); Wln; end := W.buf.len
    END Header;

    PROCEDURE CheckHeader;
       VAR len: LONGINT;
    BEGIN
      len := T.len;
      IF end = W.buf.len THEN Texts.Append(T, W.buf); Texts.Delete(T, len+beg, len+end)
      ELSE Wln
      END
    END CheckHeader;

  BEGIN
    OPT.Import("@notself", name, done);
    IF done THEN
      Ws("DEFINITION "); Ws(name); Wch(";"); Wln; Wln;
      Header("IMPORT"); i := 1; first := TRUE;
      WHILE i < OPT.nofGmod DO
        IF first THEN first := FALSE; Indent(2) ELSE Ws(", ") END ;
        Ws(OPT.GlbMod[i].name);
        INC(i)
      END ;
      IF ~first THEN Wch(";"); Wln END ;
      CheckHeader;
      Header("CONST"); Objects(OPT.GlbMod[0].right, {Con}); CheckHeader;
      Header("TYPE"); Objects(OPT.GlbMod[0].right, {Typ}); CheckHeader;
      Header("VAR"); Objects(OPT.GlbMod[0].right, {Var}); CheckHeader;
      Objects(OPT.GlbMod[0].right, {XProc, IProc, CProc});
      Wln;
      Ws("END "); Ws(name); Wch("."); Wln; Texts.Append(T, W.buf)
    END;
    RETURN done
  END WModule;

  PROCEDURE Arch(VAR a: ARRAY OF CHAR);  (* the directory name of this port *)
  BEGIN
    IF Linux0.ARCH = "MIPS" THEN COPY("mips", a) ELSIF Linux0.ARCH = "ARMv7" THEN COPY("armv7", a) ELSE COPY("riscv", a) END
  END Arch;

  (** browser.ShowDef module [/d] [/e] -- the interface of module (or of the path src/.../X.Mod) *)
  PROCEDURE ShowDef*;
    VAR A, R, dummyR: Texts.Reader; arg, opt: ARRAY 256 OF CHAR; name: OPS.Name;
      T, dummyT: Texts.Text; i, j: INTEGER; ch: CHAR; arch: ARRAY 8 OF CHAR;
  BEGIN
    option := 0X; extend := FALSE;
    Texts.OpenArgs(A);
    IF ~Texts.Arg(A, arg) THEN out.String("usage: browser.ShowDef module [/d] [/e]  (browser.Help)"); out.Ln; RETURN END;
    WHILE Texts.Arg(A, opt) DO  (* /d /e, also \d or -d *)
      IF (opt[0] = "/") OR (opt[0] = "\") OR (opt[0] = "-") THEN
        i := 1; WHILE opt[i] # 0X DO
          IF opt[i] = "d" THEN option := "x" END;
          IF opt[i] = "e" THEN extend := TRUE END;
          INC(i)
        END
      END
    END;
    (* the module name: the file name of arg without its extension *)
    j := -1; i := 0; WHILE arg[i] # 0X DO IF arg[i] = "/" THEN j := i END; INC(i) END;
    i := 0; INC(j); WHILE (arg[j] # 0X) & (arg[j] # ".") & (i < LEN(name) - 1) DO name[i] := arg[j]; INC(i); INC(j) END;
    name[i] := 0X;
    Arch(arch); Root.Obj(arch, OPM.Dir);  (* obj/<arch>/ of the current directory, else of the root *)
    NEW(dummyT); Texts.Open(dummyT, ""); Texts.OpenReader(dummyR, dummyT, 0);
    OPM.Init(dummyR, Oberon.Log);
    OPT.Init(name, {}); OPT.SelfName := "AvoidErr154";
    NEW(T); Texts.Open(T, "");
    IF WModule(name, T) THEN
      Texts.OpenReader(R, T, 0); Texts.Read(R, ch);
      WHILE ~R.eot DO IF ch = 0DX THEN out.Ln ELSE out.Char(ch) END; Texts.Read(R, ch) END
    ELSE
      out.String("browser: no module "); out.String(name); out.String(" (no "); out.String(name);
      out.String(".Sym in "); out.String(OPM.Dir); out.String(")"); out.Ln
    END;
    OPT.Close
  END ShowDef;

  PROCEDURE Help*;
  BEGIN
    out.String("browser: the interface (definition) of a module, from its symbol file"); out.Ln;
    out.String("  browser.ShowDef module [/d] [/e]   what module exports: types, variables, procedures"); out.Ln;
    out.String("     /d  with offsets, addresses, sizes and method numbers"); out.Ln;
    out.String("     /e  records with the fields of their base types written out"); out.Ln;
    out.String("     module can be a path: browser.ShowDef src/cli/net.Mod"); out.Ln;
    out.String("examples: browser.ShowDef fs   browser.ShowDef Oberon0 /e"); out.Ln
  END Help;

BEGIN
  IF Linux0.ARCH="MIPS" THEN m:=Modules.ThisMod("MOPV");
  ELSIF Linux0.ARCH="RISC-V" THEN m:=Modules.ThisMod("VOPV");
  ELSIF Linux0.ARCH="ARMv7" THEN m:=Modules.ThisMod("AOPV");
  END;  (* the back end of this port: it sets OPT.typSize *)
  Texts.OpenWriter(W)
END browser.
