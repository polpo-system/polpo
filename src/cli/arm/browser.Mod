MODULE browser;  (* the console browser of the ARM port: the interface of a module from its symbol
  file in obj/arm/. From ABrowser (MH/JT/PRK 24.9.96), the viewers taken out: the definition is
  written to the terminal; the arguments and options as those of the x86 browser. *)


  (* 5.12.94 mh: fixed output of REAL and LONGREAL numbers *)
  (* 5.12.94 mh: fixed output of record types *)
  (* 9.1.96: pr: fixed correct reader initialisation in the OpenSym proc *)
  (* 18.8.97: prk: OberonX port *)
  (* 24.12.98: as: SharkOberon port *)
(*
  Peter Matthias
  2015-07-07  using OBM.prefix:="arm/" 
*)

IMPORT OBT, OBS, OBM, Files, Root, Texts := texts, Oberon := Oberon0, out, SYSTEM;

CONST

  LogMsg = "Browser MH/JT/prk/as";

  showAdr = 0; expandTypes = 1;

VAR
  W: Texts.Writer;
  LogMsgPrinted, first, showObj: BOOLEAN;
  sysImported: BOOLEAN;
  syspos: LONGINT;
  option: SET;  (* showAdr, expandTypes *)
  Hex: ARRAY 17 OF CHAR;

  (* ---------------------- output ----------------------- *)

PROCEDURE Str (s: ARRAY OF CHAR);
BEGIN Texts.WriteString(W, s) 
END Str;

PROCEDURE Ch (ch: CHAR); 
BEGIN Texts.Write(W, ch) 
END Ch;

PROCEDURE Num (i: LONGINT);
BEGIN Texts.WriteInt(W, i, 0);
END Num;

PROCEDURE Ln; 
BEGIN Texts.WriteLn(W) 
END Ln;

PROCEDURE Indent (i: INTEGER);  
BEGIN
  WHILE i > 0 DO Ch(9X); DEC(i) END
END Indent;

PROCEDURE WriteFlags (obj: OBT.Object);
END WriteFlags;

PROCEDURE WriteConstValue (obj: OBT.Object);
  VAR i: INTEGER; y: LONGINT; s: SET;  lr : LONGREAL;
BEGIN
  y := obj.a0;
  CASE obj.typ^.form OF
    | OBM.SInt, OBM.Int, OBM.LInt:  Texts.WriteInt(W, y, 0)
    | OBM.Real:  Texts.WriteReal(W, SYSTEM.VAL(REAL, obj.a0), 15)
    | OBM.LReal:  SYSTEM.GET(SYSTEM.ADR(obj.a0),lr); Texts.WriteLongReal(W, lr, 23) 
    | OBM.Bool:  IF y = 0 THEN Str("FALSE") ELSE Str("TRUE") END 
    | OBM.Char:
      IF (y >= 32) & (y <= 126) THEN 
        Ch(22X); Ch(CHR(y)); Ch(22X)
      ELSE i := SHORT(y DIV 16);
        IF i > 0 THEN
          IF i > 9 THEN Ch("0") END;
          Ch(Hex[i])
        END;
        Ch(Hex[y MOD 16]); Ch("X")
      END
    | OBM.Set:
      Ch("{"); y := 0; s := SYSTEM.VAL(SET,obj.a0);
      WHILE y <= MAX(SET) DO
        IF y IN s THEN Texts.WriteInt(W, y, 0); EXCL(s, y);
          IF s # {} THEN Str(", ") END
        END;
        INC(y)
      END;
      Ch("}")
    | OBM.NilTyp:  Str("NIL")
    | OBM.String: Ch(22X); Str(obj.ext.str); Ch(22X)
  END
END WriteConstValue;

PROCEDURE ^ WriteType (typ: OBT.Struct; i: INTEGER; arrDone: BOOLEAN);

PROCEDURE WriteBase (typ: OBT.Struct);  
  VAR base: OBT.Struct;
BEGIN
  base := typ^.BaseTyp;
  IF base # NIL THEN
    Str(" ("); 
    WriteType(typ^.BaseTyp, 0, FALSE);
    IF expandTypes IN option THEN WriteBase(typ^.BaseTyp) END;
    Ch(")")
  END
END WriteBase;

PROCEDURE WriteFields (VAR obj: OBT.Object; i: INTEGER; recField: BOOLEAN);
  VAR typ: OBT.Struct; mode: INTEGER;
BEGIN
  typ := obj^.typ; mode := obj^.mode;
  LOOP
    IF recField & (showAdr IN option) THEN Ch("["); Num(obj.a0); Str("] ") END;
    Str(obj^.name); IF recField THEN Ch("*") END;  (* polpo: the export mark, as on x86 *)
    obj := obj.next;
    IF (obj = NIL) OR (obj^.mode # mode) OR (obj^.typ # typ) THEN EXIT END;
    Str(", ");
  END;
  Str(": "); WriteType(typ, i + 1, FALSE)
END WriteFields;

PROCEDURE WriteParams (param: OBT.Object; res: OBT.Struct);
BEGIN
  IF (param # NIL) OR (res # OBT.notyp) THEN
    Ch("(");  (* polpo: Name*(..., PROCEDURE(..., as on x86 *)
    WHILE (param # NIL) DO
      IF param.mode = OBM.Par THEN Str("VAR ") END;
      IF param.name = "" THEN
        WriteType(param.typ, 0, FALSE);
        param := param.next;
        IF param # NIL THEN Str(", ") END
      ELSE
        WriteFields(param, 0, FALSE);
        IF param # NIL THEN Str("; ") END
      END
    END;
    Ch(")");
  END;
  IF res # OBT.notyp THEN Str(": "); WriteType(res, 0, FALSE) END
END WriteParams;

PROCEDURE WriteProc (obj: OBT.Object);
BEGIN
  IF showAdr IN option THEN Ch("["); Num(obj^.a0); Str("] ") END;
  Str("PROCEDURE ");
  Str(obj^.name); Ch("*");
  WriteParams(obj^.dsc, obj^.typ);
  Ch(";");
  WriteFlags (obj)
END WriteProc;

PROCEDURE WriteFieldList (obj: OBT.Object; i: INTEGER);
BEGIN
  WHILE (obj # NIL) & (obj^.mode = OBM.Fld) DO
    IF obj.name="" THEN obj:=obj.next
    ELSE
      Indent(i);
      WriteFields(obj, i, TRUE); Ch(";");
      Ln
    END
  END
END WriteFieldList;

PROCEDURE WriteInstVars (typ: OBT.Struct; i: INTEGER; extlev: INTEGER);
BEGIN
  IF typ # NIL THEN
    IF (extlev > 0) & (expandTypes IN option) THEN
      WriteInstVars(typ^.BaseTyp, i, extlev);
      Indent(i); Str("(* "); Str(OBT.GlbMod[typ.mno-1].name); Ch("."); Str(typ^.strobj.name); Str(" *)"); Ln
    END;
    WriteFieldList(typ^.link, i);
  END
END WriteInstVars;

PROCEDURE WriteInterval(typ: OBT.Struct);
BEGIN
  IF typ.form=OBM.Array THEN Texts.WriteInt(W, typ.size DIV typ.BaseTyp.size, 0)
  END
END WriteInterval;

PROCEDURE WriteForm (typ: OBT.Struct; i: INTEGER; arrDone: BOOLEAN);
  VAR open: BOOLEAN;
BEGIN
  IF typ^.form = OBM.Record THEN
    Str("RECORD"); WriteBase(typ);
    IF typ.strobj # NIL THEN WriteFlags (typ.strobj) END;
    IF showAdr IN option THEN Str(" [size = "); Num( typ^.size); Ch("]") END;
    IF typ^.link # NIL (*OR (expandTypes IN option)*) THEN
      Ln; WriteInstVars(typ, i, typ.extlev); Indent(i - 1) ELSE Ch(" ")
    END;
    Str("END")
  ELSIF typ^.form IN {OBM.Array, OBM.DynArr} THEN
    IF ~arrDone THEN Str("ARRAY ") END;
    open := (typ.form = OBM.DynArr) & ~arrDone;    (*open array*)
    IF typ.form = OBM.Pointer THEN typ := typ.BaseTyp END;
    IF open THEN Str("OF ")  (* polpo: ARRAY OF, not ARRAY  OF *)
    ELSE WriteInterval(typ);
      IF typ^.BaseTyp.form IN {OBM.Array, OBM.DynArr} THEN Str(", ") ELSE Str(" OF ") END
    END;
    WriteType(typ^.BaseTyp, i, ~open)
  ELSIF typ^.form = OBM.Pointer THEN
    Str("POINTER TO ");
    WriteType(typ^.BaseTyp, i, FALSE);
  ELSIF typ^.form = OBM.ProcTyp THEN
    Str("PROCEDURE");
    WriteParams(typ^.link, typ^.BaseTyp)
  END
END WriteForm;

PROCEDURE WriteType (typ: OBT.Struct; i: INTEGER; arrDone: BOOLEAN);
BEGIN
  IF (typ^.strobj # NIL)  THEN (* named type *)
    IF (typ = OBT.bytetyp) OR (typ = OBT.sysptrtyp) THEN
      Str("SYSTEM."); sysImported := TRUE;
    ELSIF (typ^.mno > 1) OR ((typ^.mno = 1) & showObj) THEN
      Str(OBT.GlbMod[typ^.mno-1]^.name); Ch(".");
    END;
    Str(typ^.strobj^.name)
  ELSE (* anonymous type *) WriteForm(typ, i, arrDone)
  END
END WriteType;

PROCEDURE WriteObject (VAR obj: OBT.Object; mode: INTEGER);
  VAR h: OBT.Object;
BEGIN
  IF mode = OBM.Const THEN
    IF first THEN Indent(1); Str("CONST"); Ln; first := FALSE END;
    Indent(2); Str(obj.name); Str("* = "); WriteConstValue(obj); Ch(";");
    Ln;
  ELSIF mode = OBM.Var THEN
    IF first THEN Indent(1); Str("VAR"); Ln; first := FALSE END;
    Indent(2);
    IF showAdr IN option THEN Str(" ["); Num(obj.a0); Str("] "); END;
    Str(obj.name);
    Str("*: "); WriteType(obj^.typ, 3, FALSE); Ch(";");
    Ln;
  ELSIF mode = OBM.Typ THEN
    IF first THEN Indent(1); Str("TYPE"); Ln; first := FALSE END;
    Indent(2);
    Str(obj^.name); Str("* = ");
    IF (obj.typ.strobj#NIL) & (obj.typ.strobj#obj) THEN WriteType(obj^.typ, 0, FALSE);  (* alias type *)
    ELSE WriteForm(obj^.typ, 3, FALSE);  
    END;
    Ch(";"); Ln;
  ELSIF mode = OBM.LProc THEN first := FALSE; Indent(1); WriteProc(obj); Ln;
  END
END WriteObject;

PROCEDURE WriteImports;
  VAR i: INTEGER;
BEGIN
  i := 1; (* assume that OBT.GlbMod[0] is "self" *)
  first := TRUE;
  WHILE i < OBT.nofGmod DO
    IF first THEN Indent(1); Str("IMPORT"); Ln; Indent(2); first := FALSE; syspos := W.buf.len ELSE Str(", ") END;
    Str(OBT.GlbMod[i]^.name);
    IF showAdr IN option THEN Str(" ["); Texts.WriteHex(W, OBT.GlbMod[i]^.a0); Ch("]"); END;
    INC(i);
  END;
  IF ~first THEN Ch(";"); Ln; Ln END;
END WriteImports;

PROCEDURE WriteScope (obj: OBT.Object; mode: INTEGER);
  VAR list: ARRAY 1024 OF OBT.Object; n, i, j: INTEGER; o: OBT.Object;
BEGIN
  first := TRUE; n := 0;
  WHILE (obj#NIL) & (n < LEN(list)) DO  (* polpo: sorted by name, as on x86 *)
    IF obj.mode=mode THEN
      i := n; WHILE (i > 0) & (list[i-1].name > obj.name) DO list[i] := list[i-1]; DEC(i) END;
      list[i] := obj; INC(n)
    END;
    obj:=obj.next
  END;
  j := 0; WHILE j < n DO o := list[j]; WriteObject(o, mode); INC(j) END;
  IF ~first THEN Ln END
END WriteScope;

PROCEDURE WriteModule (mod: ARRAY OF CHAR);
  VAR anchor: OBT.Object;
BEGIN
  anchor := OBT.topScope.dsc;
  Str("DEFINITION ");
  WriteFlags (OBT.topScope.dsc);
  Str(mod);
  IF showAdr IN option THEN Str(" ["); Texts.WriteHex(W, OBT.GlbMod[0].a0); Ch("]") END;
  Ch(";"); Ln; Ln;
  syspos := W.buf.len; sysImported := FALSE;
  WriteImports;
  WriteScope(anchor, OBM.Const);
  WriteScope(anchor, OBM.Typ);
  WriteScope(anchor, OBM.Var);
  WriteScope(anchor, OBM.LProc);
  Str("END "); Str(mod); Ch(".")
END WriteModule;

PROCEDURE DisplayW;  (* the definition, written to the terminal *)
VAR T: Texts.Text; R: Texts.Reader; ch: CHAR;
BEGIN
  NEW(T); Texts.Open(T, ""); Texts.Append(T, W.buf);
  IF sysImported & ~showObj THEN
    IF OBT.nofGmod > 1 THEN Str("SYSTEM, ") ELSE Ch(09X); Str("IMPORT SYSTEM;"); Ln; Ln END;
    Texts.Insert(T, syspos, W.buf);
  END;
  Texts.OpenReader(R, T, 0); Texts.Read(R, ch);
  WHILE ~R.eot DO IF ch = 0DX THEN out.Ln ELSIF ch # 0X THEN out.Char(ch) END; Texts.Read(R, ch) END;
  out.Ln
END DisplayW;

  (* ------------------------ symbol file ------------------- *)

PROCEDURE Find(name: ARRAY OF CHAR; VAR res: OBT.Object);  (*this is OBT.FindImport, not OBT.Find!*)
  VAR obj: OBT.Object;
BEGIN obj := OBT.topScope.dsc;
  WHILE (obj # NIL) & (obj.name # name) DO obj := obj.next END ;
  IF (obj # NIL) & (obj.mode = OBM.Typ) & ~obj.marked THEN obj := NIL END ;
  res := obj
END Find;


PROCEDURE ReadSym (name: ARRAY OF CHAR);
  VAR dummyT: Texts.Text; dummyR: Texts.Reader; selfname: ARRAY 32 OF CHAR; obj : OBT.Object; dummy : INTEGER;
    filename : ARRAY 32 OF CHAR;
BEGIN
  NEW(dummyT); Texts.Open(dummyT, ""); Texts.OpenReader( dummyR, dummyT, 0);    (* Bug fixed *)
  OBT.Init; OBT.OpenScope(0);
  selfname[0]:=1X; selfname[1]:=0X;
  OBT.Import(name, selfname, name);
  COPY(name,OBS.name);
  OBT.Find(obj,dummy); OBT.topScope:=obj
END ReadSym;

  (* ---------------- user interface --------------- *)

PROCEDURE Append (VAR d: ARRAY OF CHAR; s: ARRAY OF CHAR);
  VAR i, j: INTEGER; ch: CHAR;
BEGIN
  i := 0; WHILE d[i] # 0X DO INC(i) END;
  j := 0; REPEAT ch := s[j]; d[i] := ch; INC(i); INC(j) UNTIL ch = 0X
END Append;

(** browser.ShowDef module [/d] [/e] -- the interface of module (or of the path src/.../X.Mod) *)
PROCEDURE ShowDef*;
  VAR A: Texts.Reader; arg, opt: ARRAY 256 OF CHAR; symname: ARRAY 320 OF CHAR; mod: ARRAY 32 OF CHAR;
    f: Files.File; i, j: INTEGER;
BEGIN
  OBS.scanerr := FALSE; option := {};
  Texts.OpenArgs(A);
  IF ~Texts.Arg(A, arg) THEN out.String("usage: browser.ShowDef module [/d] [/e]  (browser.Help)"); out.Ln; RETURN END;
  WHILE Texts.Arg(A, opt) DO  (* /d /e, also \d or -d *)
    IF (opt[0] = "/") OR (opt[0] = "\") OR (opt[0] = "-") THEN
      i := 1;
      WHILE opt[i] # 0X DO
        IF opt[i] = "d" THEN INCL(option, showAdr) END;
        IF opt[i] = "e" THEN INCL(option, expandTypes) END;
        INC(i)
      END
    END
  END;
  (* the module name: the file name of arg without its extension *)
  j := -1; i := 0; WHILE arg[i] # 0X DO IF arg[i] = "/" THEN j := i END; INC(i) END;
  i := 0; INC(j); WHILE (arg[j] # 0X) & (arg[j] # ".") & (i < LEN(mod) - 1) DO mod[i] := arg[j]; INC(i); INC(j) END;
  mod[i] := 0X;
  Root.Obj("arm", OBM.prefix);  (* obj/arm/ of the current directory, else of the root *)
  OBM.MakeFileName(mod, symname, OBM.SFext); f := Files.Old(symname);
  IF f = NIL THEN
    out.String("browser: no module "); out.String(mod); out.String(" (no "); out.String(symname); out.String(")"); out.Ln; RETURN
  END;
  ReadSym(mod);
  IF ~OBS.scanerr THEN showObj := FALSE; WriteModule(mod); DisplayW
  ELSE out.String("browser: cannot read "); out.String(symname); out.Ln
  END
END ShowDef;

PROCEDURE Help*;
BEGIN
  out.String("browser: the interface (definition) of a module, from its symbol file"); out.Ln;
  out.String("  browser.ShowDef module [/d] [/e]   what module exports: types, variables, procedures"); out.Ln;
  out.String("     /d  with addresses and offsets"); out.Ln;
  out.String("     /e  records with the fields of their base types written out"); out.Ln;
  out.String("     module can be a path: browser.ShowDef src/cli/net.Mod"); out.Ln;
  out.String("examples: browser.ShowDef fs   browser.ShowDef Oberon0 /e"); out.Ln
END Help;

BEGIN
  Hex := "0123456789ABCDEF";
  Texts.OpenWriter(W);
  LogMsgPrinted := FALSE;
END browser.
