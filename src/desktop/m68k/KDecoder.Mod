MODULE KDecoder;  (* the code of a 68020 object file as text *)
(*
  KDecoder.Obj X [\r]       opens a viewer with obj/m68k/X.Obj: its blocks and its code
  KDecoder.File X out [\r]  writes the same as plain text into the file out (also in the console)
  \r adds the reference block (procedures and their variables).

  The 32-bit fields the loader fills (global variables, constants, type descriptors, procedures of
  other modules, see KOPL) are shown by the name of their object: sb-24 is a global variable or a
  constant of the module, Files.Read a procedure of another module. Branch targets get labels,
  procedures their names from the reference block, and the jump table of a CASE is shown as data.
*)

  IMPORT Texts, Oberon, Viewers, MenuViewers, TextFrames, Files, Fonts, Out, SYSTEM, Root;

  CONST
    Tag = 36F6H;
    nlen = 320;
    CodeLength = 65000;  (* words of 16 bits *)
    MaxNames = 2000;
    MaxProcs = 1000;

  TYPE
    Name = ARRAY nlen OF CHAR;
    Short = ARRAY 48 OF CHAR;

  VAR
    W: Texts.Writer;
    T: Texts.Text;
    R: Files.Rider;
    code: ARRAY CodeLength OF INTEGER;
    label: ARRAY CodeLength OF INTEGER;  (* > 0: label number + 1 *)
    linkAt: ARRAY CodeLength OF INTEGER;  (* > 0: the field of a chain, index + 1 into names *)
    names: ARRAY MaxNames OF Short;
    nnames: LONGINT;
    procName: ARRAY MaxProcs OF Short;
    procStart: ARRAY MaxProcs OF LONGINT;  (* in words of 16 bits *)
    nprocs, nlabels: LONGINT;
    nhw, pc, start: LONGINT;  (* the code in words of 16 bits; the word being read; the instruction's first *)
    emit, showref: BOOLEAN;
    col: LONGINT;  (* characters written since the start of the mnemonic *)
    lastCmp: LONGINT;  (* the value of the last CMPI.L: high - low of a CASE *)
    table: LONGINT;  (* > 0: the entries of the jump table after the JMP just decoded *)
    cc: ARRAY 16 OF ARRAY 4 OF CHAR;
    fcc: ARRAY 32 OF ARRAY 6 OF CHAR;
    fop: ARRAY 128 OF ARRAY 8 OF CHAR;
    fmt: ARRAY 9 OF CHAR;

(* output; nothing in the first pass, which only finds the labels *)

  PROCEDURE Ch(c: CHAR);
  BEGIN IF emit THEN Texts.Write(W, c); INC(col) END
  END Ch;

  PROCEDURE Str(s: ARRAY OF CHAR);
    VAR i: LONGINT;
  BEGIN
    IF emit THEN Texts.WriteString(W, s); i := 0; WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END; INC(col, i) END
  END Str;

  PROCEDURE Hex(x, n: LONGINT);  (* n digits *)
    VAR a: ARRAY 8 OF CHAR; j, d: LONGINT;
  BEGIN
    IF emit THEN j := 0;
      WHILE j < 8 DO d := x MOD 16; x := SYSTEM.LSH(x, -4);
        IF d > 9 THEN a[j] := CHR(d - 10 + ORD("A")) ELSE a[j] := CHR(d + ORD("0")) END; INC(j)
      END;
      WHILE n > 0 DO DEC(n); Texts.Write(W, a[n]) END
    END
  END Hex;

  PROCEDURE Int(x: LONGINT);
  BEGIN IF emit THEN Texts.WriteInt(W, x, 0) END
  END Int;

  PROCEDURE Num(x: LONGINT);  (* small numbers in decimal, others in hexadecimal *)
  BEGIN
    IF (x > -100000) & (x < 100000) THEN Int(x)
    ELSIF x < 0 THEN Ch("-"); Hex(-x, 8); Ch("H")
    ELSE Hex(x, 8); Ch("H")
    END
  END Num;

  PROCEDURE Ln;
  BEGIN IF emit THEN Texts.WriteLn(W) END
  END Ln;

(* the code *)

  PROCEDURE Word(): LONGINT;  (* the next word, unsigned *)
    VAR w: LONGINT;
  BEGIN
    IF pc < nhw THEN w := LONG(code[pc]) MOD 10000H ELSE w := 0 END;
    INC(pc); RETURN w
  END Word;

  PROCEDURE Signed(w: LONGINT): LONGINT;
  BEGIN IF w >= 8000H THEN RETURN w - 10000H ELSE RETURN w END
  END Signed;

  PROCEDURE Long(): LONGINT;
    VAR h: LONGINT;
  BEGIN h := Word(); RETURN SYSTEM.LSH(h, 16) + Word()
  END Long;

  PROCEDURE ProcAt(p: LONGINT): LONGINT;  (* the procedure starting at word p, or -1 *)
    VAR i: LONGINT;
  BEGIN i := 0;
    WHILE (i < nprocs) & (procStart[i] # p) DO INC(i) END;
    IF i = nprocs THEN i := -1 END;
    RETURN i
  END ProcAt;

  PROCEDURE Target(t: LONGINT);  (* a branch target in bytes from the start of the code *)
    VAR p, k: LONGINT;
  BEGIN p := t DIV 2; k := ProcAt(p);
    IF k >= 0 THEN Str(procName[k])
    ELSIF ~ODD(t) & (p >= 0) & (p < nhw) THEN
      IF ~emit & (label[p] = 0) THEN INC(nlabels); label[p] := SHORT(nlabels) END;
      IF label[p] > 0 THEN Ch("L"); Int(label[p]) ELSE Hex(t, 5); Ch("H") END
    ELSE Hex(t, 8); Ch("H")
    END
  END Target;

  PROCEDURE AbsLong;  (* an absolute long field: the object of its chain, or the address *)
    VAR p, off: LONGINT;
  BEGIN p := pc;
    IF (p < nhw) & (linkAt[p] > 0) THEN
      Str(names[linkAt[p] - 1]); off := Signed(LONG(code[p + 1]) MOD 10000H); INC(pc, 2);
      IF off > 0 THEN Ch("+"); Num(off) ELSIF off < 0 THEN Num(off) END
    ELSE Hex(Long(), 8); Ch("H")
    END
  END AbsLong;

  PROCEDURE Reg(r: LONGINT);  (* 0..7 D0..D7, 8..15 A0..A7 (A6 FP, A7 SP) *)
  BEGIN
    IF r = 14 THEN Str("A6") ELSIF r = 15 THEN Str("SP")
    ELSIF r >= 8 THEN Ch("A"); Ch(CHR(r - 8 + ORD("0")))
    ELSE Ch("D"); Ch(CHR(r + ORD("0")))
    END
  END Reg;

  PROCEDURE Index(ext: LONGINT);  (* the index register of an extension word *)
  BEGIN
    Reg(SYSTEM.LSH(ext, -12) MOD 16);
    IF ODD(SYSTEM.LSH(ext, -11)) THEN Str(".L") ELSE Str(".W") END;
    IF SYSTEM.LSH(ext, -9) MOD 4 # 0 THEN Ch("*"); Int(ASH(1, SYSTEM.LSH(ext, -9) MOD 4)) END
  END Index;

  PROCEDURE Extension(base: LONGINT; pcrel: BOOLEAN);  (* (d8, An, Xn) and the full format of the 68020 *)
    VAR ext, bd, od, bds, iis: LONGINT; first: BOOLEAN;
  BEGIN
    ext := Word();
    IF ~ODD(SYSTEM.LSH(ext, -8)) THEN  (* brief *)
      bd := ext MOD 100H; IF bd >= 80H THEN DEC(bd, 100H) END;
      Num(bd); Ch("(");
      IF pcrel THEN Str("PC") ELSE Reg(base + 8) END;
      Ch(","); Index(ext); Ch(")")
    ELSE
      bds := SYSTEM.LSH(ext, -4) MOD 4; iis := ext MOD 8; bd := 0; od := 0;
      IF bds = 2 THEN bd := Signed(Word()) ELSIF bds = 3 THEN bd := Long() END;
      IF iis MOD 4 = 2 THEN od := Signed(Word()) ELSIF iis MOD 4 = 3 THEN od := Long() END;
      Ch("("); IF iis # 0 THEN Ch("[") END;
      first := TRUE;
      IF bds > 1 THEN Num(bd); first := FALSE END;
      IF ~ODD(SYSTEM.LSH(ext, -7)) THEN  (* base register *)
        IF ~first THEN Ch(",") END; first := FALSE;
        IF pcrel THEN Str("PC") ELSE Reg(base + 8) END
      END;
      IF (iis >= 4) & (iis # 0) THEN Ch("]") END;
      IF ~ODD(SYSTEM.LSH(ext, -6)) THEN  (* index *)
        IF ~first THEN Ch(",") END; first := FALSE; Index(ext)
      END;
      IF (iis # 0) & (iis < 4) THEN Ch("]") END;
      IF iis MOD 4 > 1 THEN Ch(","); Num(od) END;
      Ch(")")
    END
  END Extension;

  PROCEDURE EA(mode, r, size: LONGINT);  (* size of an immediate: 1, 2, 4 bytes; 8 a double, 12 extended *)
    VAR v: LONGINT;
  BEGIN
    CASE mode OF
    | 0: Reg(r)
    | 1: Reg(r + 8)
    | 2: Ch("("); Reg(r + 8); Ch(")")
    | 3: Ch("("); Reg(r + 8); Str(")+")
    | 4: Str("-("); Reg(r + 8); Ch(")")
    | 5: Num(Signed(Word())); Ch("("); Reg(r + 8); Ch(")")
    | 6: Extension(r, FALSE)
    | 7:
        CASE r OF
        | 0: Hex(Word(), 4); Str("H.W")
        | 1: AbsLong
        | 2: v := Signed(Word()); Target(2*pc - 2 + v); Str("(PC)")
        | 3: Extension(0, TRUE)
        | 4: Ch("#");
            IF size = 1 THEN Num(Word() MOD 100H)
            ELSIF size = 2 THEN Num(Signed(Word()))
            ELSIF size = 4 THEN
              IF (pc < nhw) & (linkAt[pc] > 0) THEN AbsLong ELSE Num(Long()) END
            ELSE Hex(Long(), 8); Hex(Long(), 8); IF size = 12 THEN Hex(Long(), 8) END; Ch("H")
            END
        ELSE Str("?")
        END
    END
  END EA;

  PROCEDURE Size(s: LONGINT): LONGINT;  (* the size field 0, 1, 2 as bytes; the suffix written *)
  BEGIN
    IF s = 0 THEN Str(".B"); RETURN 1 ELSIF s = 1 THEN Str(".W"); RETURN 2 ELSE Str(".L"); RETURN 4 END
  END Size;

  PROCEDURE Op(s: ARRAY OF CHAR);
  BEGIN Str(s)
  END Op;

  PROCEDURE Tab;  (* the operands start in column 10 of the mnemonic *)
  BEGIN IF emit THEN REPEAT Ch(" ") UNTIL col >= 10 END
  END Tab;

  PROCEDURE RegList(m: LONGINT; reverse: BOOLEAN);  (* the mask of MOVEM: bit 0 D0 .. bit 15 A7 *)
    VAR i, j, r: LONGINT; first: BOOLEAN;
  BEGIN
    IF reverse THEN r := 0; i := 0; WHILE i < 16 DO r := r * 2 + m MOD 2; m := m DIV 2; INC(i) END; m := r END;
    first := TRUE; i := 0;
    WHILE i < 16 DO
      IF ODD(SYSTEM.LSH(m, -i)) THEN
        j := i; WHILE (j < 15) & (j # 7) & ODD(SYSTEM.LSH(m, -(j + 1))) DO INC(j) END;
        IF ~first THEN Ch("/") END; first := FALSE;
        Reg(i); IF j > i THEN Ch("-"); Reg(j) END;
        i := j + 1
      ELSE INC(i)
      END
    END
  END RegList;

  PROCEDURE Fpu(w: LONGINT);  (* the line F instructions of the FPU (coprocessor 1) *)
    VAR c, cls, f, src, dst, t, m, mode, r: LONGINT;
  BEGIN
    mode := SYSTEM.LSH(w, -3) MOD 8; r := w MOD 8; t := SYSTEM.LSH(w, -6) MOD 8;
    IF t = 0 THEN c := Word(); cls := SYSTEM.LSH(c, -13);
      src := SYSTEM.LSH(c, -10) MOD 8; dst := SYSTEM.LSH(c, -7) MOD 8;
      CASE cls OF
      | 0: Op(fop[c MOD 80H]); Str(".X"); Tab; Str("FP"); Int(src); Str(",FP"); Int(dst)
      | 2: Op(fop[c MOD 80H]); Ch("."); Ch(fmt[src]); Tab;
          IF src = 0 THEN f := 4 ELSIF src = 1 THEN f := 4 ELSIF src = 4 THEN f := 2 ELSIF src = 5 THEN f := 8
          ELSIF src = 6 THEN f := 1 ELSE f := 12
          END;
          EA(mode, r, f); Str(",FP"); Int(dst)
      | 3: Op("FMOVE."); Ch(fmt[src]); Tab; Str("FP"); Int(dst); Ch(","); EA(mode, r, 4)
      | 4, 5: Op("FMOVE.L"); Tab;
          IF cls = 5 THEN
            IF ODD(SYSTEM.LSH(c, -12)) THEN Str("FPCR") ELSIF ODD(SYSTEM.LSH(c, -11)) THEN Str("FPSR") ELSE Str("FPIAR") END;
            Ch(","); EA(mode, r, 4)
          ELSE EA(mode, r, 4); Ch(",");
            IF ODD(SYSTEM.LSH(c, -12)) THEN Str("FPCR") ELSIF ODD(SYSTEM.LSH(c, -11)) THEN Str("FPSR") ELSE Str("FPIAR") END
          END
      | 6, 7: Op("FMOVEM.X"); Tab; m := c MOD 100H; f := 0; src := 0;
          IF cls = 6 THEN EA(mode, r, 12); Ch(",") END;  (* memory to registers *)
          IF SYSTEM.LSH(c, -11) MOD 4 = 0 THEN  (* predecrement: bit 0 FP0 *)
            WHILE src < 8 DO IF ODD(SYSTEM.LSH(m, -src)) THEN IF f > 0 THEN Ch("/") END; Str("FP"); Int(src); INC(f) END; INC(src) END
          ELSE  (* bit 7 FP0 *)
            WHILE src < 8 DO IF ODD(SYSTEM.LSH(m, -(7 - src))) THEN IF f > 0 THEN Ch("/") END; Str("FP"); Int(src); INC(f) END; INC(src) END
          END;
          IF cls = 7 THEN Ch(","); EA(mode, r, 12) END
      ELSE Op("F?"); Tab; Hex(c, 4)
      END
    ELSIF t = 1 THEN c := Word();
      IF mode = 1 THEN Op("FDB"); Str(fcc[c MOD 32]); Tab; Reg(r); Ch(","); f := Signed(Word()); Target(2*pc - 2 + f)
      ELSIF (mode = 7) & (r >= 2) THEN Op("FTRAP"); Str(fcc[c MOD 32]);
        IF r = 2 THEN Tab; Ch("#"); Num(Word()) ELSIF r = 3 THEN Tab; Ch("#"); Num(Long()) END
      ELSE Op("FS"); Str(fcc[c MOD 32]); Tab; EA(mode, r, 1)
      END
    ELSIF (t = 2) OR (t = 3) THEN
      IF (w = 0F280H) & (pc < nhw) & (code[pc] = 0) THEN Op("FNOP"); INC(pc)
      ELSE Op("FB"); Str(fcc[w MOD 32]);
        IF t = 2 THEN Str(".W"); Tab; f := Signed(Word()); Target(2*pc - 2 + f)
        ELSE Str(".L"); Tab; f := Long(); Target(2*pc - 4 + f)
        END
      END
    ELSIF t = 4 THEN Op("FSAVE"); Tab; EA(mode, r, 4)
    ELSIF t = 5 THEN Op("FRESTORE"); Tab; EA(mode, r, 4)
    ELSE Op("DC.W"); Tab; Hex(w, 4); Ch("H")
    END
  END Fpu;

  PROCEDURE Decode;  (* the instruction at pc *)
    VAR w, op, mode, r, rx, s, n, d, ext, i: LONGINT;
  BEGIN
    w := Word(); op := SYSTEM.LSH(w, -12); mode := SYSTEM.LSH(w, -3) MOD 8; r := w MOD 8;
    rx := SYSTEM.LSH(w, -9) MOD 8; s := SYSTEM.LSH(w, -6) MOD 4;
    CASE op OF
    | 0:
        IF ODD(SYSTEM.LSH(w, -8)) THEN
          IF mode = 1 THEN Op("MOVEP"); Tab; Hex(w, 4)
          ELSE
            CASE s OF 0: Op("BTST") | 1: Op("BCHG") | 2: Op("BCLR") | 3: Op("BSET") END;
            Tab; Reg(rx); Ch(","); EA(mode, r, 1)
          END
        ELSE
          CASE rx OF
          | 0: Op("ORI") | 1: Op("ANDI") | 2: Op("SUBI") | 3: Op("ADDI") | 5: Op("EORI") | 6: Op("CMPI")
          | 4: CASE s OF 0: Op("BTST") | 1: Op("BCHG") | 2: Op("BCLR") | 3: Op("BSET") END;
              Tab; Ch("#"); Int(Word() MOD 100H); Ch(","); EA(mode, r, 1); RETURN
          ELSE Op("DC.W"); Tab; Hex(w, 4); Ch("H"); RETURN
          END;
          IF (mode = 7) & (r = 4) THEN  (* to CCR, SR *)
            IF s = 0 THEN Tab; Ch("#"); Num(Word() MOD 100H); Str(",CCR") ELSE Tab; Ch("#"); Num(Word()); Str(",SR") END
          ELSE n := Size(s); Tab;
            IF (rx = 6) & (s = 2) THEN  (* CMPI.L: a CASE checks the range with it *)
              IF (pc < nhw) & (linkAt[pc] > 0) THEN EA(7, 4, 4) ELSE lastCmp := Long(); Ch("#"); Num(lastCmp) END
            ELSE EA(7, 4, n)
            END;
            Ch(","); EA(mode, r, n)
          END
        END
    | 1, 2, 3:  (* MOVE *)
        IF op = 1 THEN n := 1 ELSIF op = 3 THEN n := 2 ELSE n := 4 END;
        d := SYSTEM.LSH(w, -6) MOD 8;
        IF d = 1 THEN Op("MOVEA") ELSE Op("MOVE") END;
        IF n = 1 THEN Str(".B") ELSIF n = 2 THEN Str(".W") ELSE Str(".L") END;
        Tab; EA(mode, r, n); Ch(","); EA(d, rx, n)
    | 4:
        IF w = 4E71H THEN Op("NOP")
        ELSIF w = 4E75H THEN Op("RTS")
        ELSIF w = 4E74H THEN Op("RTD"); Tab; Ch("#"); Num(Signed(Word()))
        ELSIF w = 4E73H THEN Op("RTE")
        ELSIF w = 4E77H THEN Op("RTR")
        ELSIF w = 4E76H THEN Op("TRAPV")
        ELSIF w = 4AFCH THEN Op("ILLEGAL")
        ELSIF w DIV 10H = 4E4H THEN Op("TRAP"); Tab; Ch("#"); Int(w MOD 10H)
        ELSIF w DIV 8 = 4E50H DIV 8 THEN Op("LINK.W"); Tab; Reg(r + 8); Str(",#"); Num(Signed(Word()))
        ELSIF w DIV 8 = 4808H DIV 8 THEN Op("LINK.L"); Tab; Reg(r + 8); Str(",#"); Num(Long())
        ELSIF w DIV 8 = 4E58H DIV 8 THEN Op("UNLK"); Tab; Reg(r + 8)
        ELSIF w DIV 40H = 4E80H DIV 40H THEN Op("JSR"); Tab; EA(mode, r, 4)
        ELSIF w DIV 40H = 4EC0H DIV 40H THEN Op("JMP"); Tab;
          EA(mode, r, 4);
          IF (mode = 7) & (r = 3) & (lastCmp >= 0) THEN table := lastCmp + 1; lastCmp := -1 END  (* a CASE: the table follows *)
        ELSIF w DIV 8 = 4840H DIV 8 THEN Op("SWAP"); Tab; Reg(r)
        ELSIF w DIV 40H = 4840H DIV 40H THEN Op("PEA"); Tab; EA(mode, r, 4)
        ELSIF w DIV 8 = 4880H DIV 8 THEN Op("EXT.W"); Tab; Reg(r)
        ELSIF w DIV 8 = 48C0H DIV 8 THEN Op("EXT.L"); Tab; Reg(r)
        ELSIF w DIV 8 = 49C0H DIV 8 THEN Op("EXTB.L"); Tab; Reg(r)
        ELSIF (w DIV 80H MOD 2 = 1) & (w DIV 200H MOD 2 = 0) & (SYSTEM.LSH(w, -8) MOD 16 IN {8, 0CH}) & (mode >= 2) THEN  (* MOVEM *)
          Op("MOVEM"); IF ODD(SYSTEM.LSH(w, -6)) THEN Str(".L") ELSE Str(".W") END; Tab; ext := Word();
          IF ODD(SYSTEM.LSH(w, -10)) THEN EA(mode, r, 4); Ch(","); RegList(ext, FALSE)
          ELSE RegList(ext, mode = 4); Ch(","); EA(mode, r, 4)
          END
        ELSIF w DIV 40H = 4C00H DIV 40H THEN ext := Word();
          IF ODD(SYSTEM.LSH(ext, -11)) THEN Op("MULS.L") ELSE Op("MULU.L") END; Tab; EA(mode, r, 4); Ch(",");
          IF ODD(SYSTEM.LSH(ext, -10)) THEN Reg(ext MOD 8); Ch(":") END; Reg(SYSTEM.LSH(ext, -12) MOD 8)
        ELSIF w DIV 40H = 4C40H DIV 40H THEN ext := Word();
          IF ODD(SYSTEM.LSH(ext, -11)) THEN Op("DIVS") ELSE Op("DIVU") END;
          IF ~ODD(SYSTEM.LSH(ext, -10)) & (ext MOD 8 # SYSTEM.LSH(ext, -12) MOD 8) THEN Str("L") END;
          Str(".L"); Tab; EA(mode, r, 4); Ch(",");
          IF ext MOD 8 # SYSTEM.LSH(ext, -12) MOD 8 THEN Reg(ext MOD 8); Ch(":") END; Reg(SYSTEM.LSH(ext, -12) MOD 8)
        ELSIF w MOD 200H DIV 40H = 7 THEN Op("LEA"); Tab; EA(mode, r, 4); Ch(","); Reg(rx + 8)
        ELSIF w MOD 200H DIV 40H = 6 THEN Op("CHK.W"); Tab; EA(mode, r, 2); Ch(","); Reg(rx)
        ELSIF w MOD 200H DIV 40H = 4 THEN Op("CHK.L"); Tab; EA(mode, r, 4); Ch(","); Reg(rx)
        ELSE
          CASE SYSTEM.LSH(w, -8) MOD 16 OF
          | 0: IF s = 3 THEN Op("MOVE"); Tab; Str("SR,"); EA(mode, r, 2) ELSE Op("NEGX"); n := Size(s); Tab; EA(mode, r, n) END
          | 2: IF s = 3 THEN Op("MOVE"); Tab; Str("CCR,"); EA(mode, r, 2) ELSE Op("CLR"); n := Size(s); Tab; EA(mode, r, n) END
          | 4: IF s = 3 THEN Op("MOVE"); Tab; EA(mode, r, 2); Str(",CCR") ELSE Op("NEG"); n := Size(s); Tab; EA(mode, r, n) END
          | 6: IF s = 3 THEN Op("MOVE"); Tab; EA(mode, r, 2); Str(",SR") ELSE Op("NOT"); n := Size(s); Tab; EA(mode, r, n) END
          | 0AH: IF s = 3 THEN Op("TAS"); Tab; EA(mode, r, 1) ELSE Op("TST"); n := Size(s); Tab; EA(mode, r, n) END
          ELSE Op("DC.W"); Tab; Hex(w, 4); Ch("H")
          END
        END
    | 5:
        IF s = 3 THEN
          IF mode = 1 THEN Op("DB"); Str(cc[SYSTEM.LSH(w, -8) MOD 16]); Tab; Reg(r); Ch(","); d := Signed(Word()); Target(2*pc - 2 + d)
          ELSIF (mode = 7) & (r = 2) THEN Op("TRAP"); Str(cc[SYSTEM.LSH(w, -8) MOD 16]); Str(".W"); Tab; Ch("#"); Num(Word())
          ELSIF (mode = 7) & (r = 3) THEN Op("TRAP"); Str(cc[SYSTEM.LSH(w, -8) MOD 16]); Str(".L"); Tab; Ch("#"); Num(Long())
          ELSIF (mode = 7) & (r = 4) THEN Op("TRAP"); Str(cc[SYSTEM.LSH(w, -8) MOD 16])
          ELSE Op("S"); Str(cc[SYSTEM.LSH(w, -8) MOD 16]); Tab; EA(mode, r, 1)
          END
        ELSE
          IF ODD(SYSTEM.LSH(w, -8)) THEN Op("SUBQ") ELSE Op("ADDQ") END;
          n := Size(s); Tab; Ch("#"); IF rx = 0 THEN Int(8) ELSE Int(rx) END; Ch(","); EA(mode, r, n)
        END
    | 6:
        d := w MOD 100H; n := SYSTEM.LSH(w, -8) MOD 16;
        IF n = 0 THEN Op("BRA") ELSIF n = 1 THEN Op("BSR") ELSE Op("B"); Str(cc[n]) END;
        IF d = 0 THEN Str(".W"); Tab; d := Signed(Word()); Target(2*pc - 2 + d)
        ELSIF d = 0FFH THEN Str(".L"); Tab; d := Long(); Target(2*pc - 4 + d)
        ELSE Str(".S"); Tab; IF d >= 80H THEN DEC(d, 100H) END; Target(2*pc + d)
        END
    | 7: d := w MOD 100H; IF d >= 80H THEN DEC(d, 100H) END; Op("MOVEQ"); Tab; Ch("#"); Num(d); Ch(","); Reg(rx)
    | 8, 0CH:
        IF w MOD 200H DIV 40H = 3 THEN
          IF op = 8 THEN Op("DIVU.W") ELSE Op("MULU.W") END; Tab; EA(mode, r, 2); Ch(","); Reg(rx)
        ELSIF w MOD 200H DIV 40H = 7 THEN
          IF op = 8 THEN Op("DIVS.W") ELSE Op("MULS.W") END; Tab; EA(mode, r, 2); Ch(","); Reg(rx)
        ELSIF (op = 0CH) & ((w MOD 200H DIV 8 = 28H) OR (w MOD 200H DIV 8 = 29H) OR (w MOD 200H DIV 8 = 31H)) THEN Op("EXG"); Tab;
          IF w MOD 200H DIV 8 = 28H THEN Reg(rx); Ch(","); Reg(r)
          ELSIF w MOD 200H DIV 8 = 29H THEN Reg(rx + 8); Ch(","); Reg(r + 8)
          ELSE Reg(rx); Ch(","); Reg(r + 8)
          END
        ELSIF w MOD 200H DIV 10H = 10H THEN IF op = 8 THEN Op("SBCD") ELSE Op("ABCD") END; Tab; Hex(w, 4)
        ELSE
          IF op = 8 THEN Op("OR") ELSE Op("AND") END; n := Size(s); Tab;
          IF ODD(SYSTEM.LSH(w, -8)) THEN Reg(rx); Ch(","); EA(mode, r, n) ELSE EA(mode, r, n); Ch(","); Reg(rx) END
        END
    | 9, 0DH, 0BH:
        d := SYSTEM.LSH(w, -6) MOD 8;
        IF (d = 3) OR (d = 7) THEN
          IF op = 9 THEN Op("SUBA") ELSIF op = 0DH THEN Op("ADDA") ELSE Op("CMPA") END;
          IF d = 3 THEN Str(".W"); n := 2 ELSE Str(".L"); n := 4 END; Tab; EA(mode, r, n); Ch(","); Reg(rx + 8)
        ELSIF op = 0BH THEN
          IF d < 3 THEN Op("CMP"); n := Size(s); Tab; EA(mode, r, n); Ch(","); Reg(rx)
          ELSIF mode = 1 THEN Op("CMPM"); n := Size(s); Tab; EA(3, r, n); Ch(","); EA(3, rx, n)
          ELSE Op("EOR"); n := Size(s); Tab; Reg(rx); Ch(","); EA(mode, r, n)
          END
        ELSE
          IF op = 9 THEN Op("SUB") ELSE Op("ADD") END;
          IF (d >= 4) & (mode <= 1) THEN Str("X"); n := Size(s); Tab; EA(mode * 4, r, n); Ch(","); EA(mode * 4, rx, n)
          ELSE n := Size(s); Tab;
            IF d >= 4 THEN Reg(rx); Ch(","); EA(mode, r, n) ELSE EA(mode, r, n); Ch(","); Reg(rx) END
          END
        END
    | 0EH:
        IF s = 3 THEN
          IF ODD(SYSTEM.LSH(w, -11)) THEN Op("BF"); Tab; Hex(w, 4); Ch(" "); Hex(Word(), 4)
          ELSE
            CASE SYSTEM.LSH(w, -9) MOD 4 OF 0: Op("AS") | 1: Op("LS") | 2: Op("ROX") | 3: Op("RO") END;
            IF ODD(SYSTEM.LSH(w, -8)) THEN Str("L") ELSE Str("R") END; Str(".W"); Tab; EA(mode, r, 2)
          END
        ELSE
          CASE SYSTEM.LSH(w, -3) MOD 4 OF 0: Op("AS") | 1: Op("LS") | 2: Op("ROX") | 3: Op("RO") END;
          IF ODD(SYSTEM.LSH(w, -8)) THEN Str("L") ELSE Str("R") END; n := Size(s); Tab;
          IF ODD(SYSTEM.LSH(w, -5)) THEN Reg(rx) ELSE Ch("#"); IF rx = 0 THEN Int(8) ELSE Int(rx) END END;
          Ch(","); Reg(r)
        END
    | 0FH:
        IF rx = 1 THEN Fpu(w) ELSE Op("DC.W"); Tab; Hex(w, 4); Ch("H") END
    ELSE Op("DC.W"); Tab; Hex(w, 4); Ch("H")
    END
  END Decode;

  PROCEDURE Extra(from: LONGINT);  (* the extension words of an instruction, on a line of their own *)
  BEGIN
    IF pc - from > 1 THEN
      Texts.WriteString(W, "         "); INC(from);
      WHILE from < pc DO Texts.Write(W, " "); Hex(LONG(code[from]) MOD 10000H, 4); INC(from) END;
      Texts.WriteLn(W)
    END
  END Extra;

  PROCEDURE Table(n: LONGINT);  (* the n entries of a CASE table at pc: offsets in bytes from its start *)
    VAR base: LONGINT;
  BEGIN base := pc;
    WHILE (n > 0) & (pc < nhw) DO
      IF emit THEN Texts.WriteString(W, "  "); Hex(2*pc, 5); Texts.WriteString(W, ":  DC.W "); END;
      Target(2*base + Signed(Word()));
      IF emit THEN Texts.WriteLn(W) END;
      DEC(n)
    END
  END Table;

  PROCEDURE Code;  (* all instructions, twice: the first pass finds the labels *)
    VAR k: LONGINT;
  BEGIN
    emit := FALSE; nlabels := 0; pc := 0; lastCmp := -1; table := 0;
    WHILE pc < nhw DO Decode; IF table > 0 THEN Table(table); table := 0 END END;
    emit := TRUE; pc := 0; lastCmp := -1; k := 0;
    WHILE pc < nhw DO
      WHILE (k < nprocs) & (procStart[k] <= pc) DO
        IF procStart[k] = pc THEN Texts.WriteLn(W); Texts.WriteString(W, procName[k]); Texts.Write(W, ":"); Texts.WriteLn(W) END;
        INC(k)
      END;
      IF label[pc] > 0 THEN Texts.Write(W, "L"); Texts.WriteInt(W, label[pc], 0); Texts.Write(W, ":"); Texts.WriteLn(W) END;
      start := pc;
      Texts.WriteString(W, "  "); Hex(2*pc, 5); Texts.WriteString(W, ":  ");
      col := 0; Decode; Texts.WriteLn(W); Extra(start);
      IF table > 0 THEN Table(table); table := 0 END;
      IF W.buf.len > 8000 THEN Texts.Append(T, W.buf) END
    END
  END Code;

(* the object file *)

  PROCEDURE NameOf(s: ARRAY OF CHAR): LONGINT;
  BEGIN
    IF nnames < MaxNames THEN COPY(s, names[nnames]); INC(nnames) END;
    RETURN nnames
  END NameOf;

  PROCEDURE Chain(L, n: LONGINT);  (* the fields of the chain from L get the name n *)
    VAR d, k: LONGINT;
  BEGIN k := 0;
    WHILE (L > 0) & (L < nhw - 1) & (k < CodeLength) DO
      linkAt[L] := SHORT(n); d := LONG(code[L]) MOD 10000H;
      IF d = 0 THEN L := 0 ELSE DEC(L, d) END; INC(k)
    END
  END Chain;

  PROCEDURE Block(tag: CHAR; bn: ARRAY OF CHAR);
    VAR ch: CHAR;
  BEGIN
    Texts.WriteLn(W); Files.Read(R, ch);
    IF ch # tag THEN Texts.WriteString(W, "******* not a block "); Hex(ORD(tag), 2); Texts.WriteLn(W) END;
    Texts.WriteString(W, bn); Texts.WriteLn(W)
  END Block;

  PROCEDURE Join(VAR d: ARRAY OF CHAR; a, b: ARRAY OF CHAR);
    VAR i, j: LONGINT;
  BEGIN i := 0; j := 0;
    WHILE (a[j] # 0X) & (i < LEN(d) - 1) DO d[i] := a[j]; INC(i); INC(j) END; j := 0;
    WHILE (b[j] # 0X) & (i < LEN(d) - 1) DO d[i] := b[j]; INC(i); INC(j) END;
    d[i] := 0X
  END Join;

  PROCEDURE ReadIn;
    VAR fprint, refsize, datasize, consize, codesize, k, nofmod, newrec, newsys, newarr, datalink, lastEnd, e, n,
        nofnewmeth, nofptr2, i, j, f: LONGINT;
      nofexp, nofdesc, nofcom, nofptr: INTEGER;
      modname, name, nm: Name; s: Short;
      mods: ARRAY 64 OF Short;
      links, lname, lentry: ARRAY 2000 OF LONGINT; nlinks: LONGINT;  (* lentry: the word of a LinkProc, else -1 *)
      ch: CHAR;
  BEGIN
    Files.ReadLInt(R, refsize); Files.ReadInt(R, nofexp); Files.ReadInt(R, nofdesc); Files.ReadInt(R, nofcom);
    Files.ReadInt(R, nofptr); Files.ReadNum(R, nofmod); Files.ReadNum(R, newrec); Files.ReadNum(R, newsys);
    Files.ReadNum(R, newarr); Files.ReadNum(R, datalink); Files.ReadNum(R, datasize); Files.ReadNum(R, consize);
    Files.ReadNum(R, codesize); Files.ReadString(R, modname);
    Texts.WriteString(W, modname); Texts.WriteLn(W); Texts.WriteLn(W);
    Texts.WriteString(W, "code size  : "); Texts.WriteInt(W, 4*codesize, 0); Texts.WriteLn(W);
    Texts.WriteString(W, "data size  : "); Texts.WriteInt(W, datasize, 0); Texts.WriteLn(W);
    Texts.WriteString(W, "const size : "); Texts.WriteInt(W, consize, 0); Texts.WriteLn(W);
    nlinks := 0;
    i := 0; WHILE i < LEN(lentry) DO lentry[i] := -1; INC(i) END;
    links[0] := datalink; lname[0] := NameOf("sb"); links[1] := newrec; lname[1] := NameOf("Kernel.NewRec");
    links[2] := newsys; lname[2] := NameOf("Kernel.NewSys"); links[3] := newarr; lname[3] := NameOf("Kernel.NewArr"); nlinks := 4;
  (* ImpBlk *)
    Block(81X, "imports:"); i := 0;
    WHILE i < nofmod DO INC(i); Files.ReadString(R, name); COPY(name, mods[i]); Texts.WriteString(W, mods[i]); Texts.WriteLn(W) END;
  (* ExpBlk *)
    Block(82X, "exports:"); Files.Read(R, ch);
    WHILE ch # 0X DO
      IF ch = 9X THEN  (* the address of a procedure of this module, named after the refs *)
        Files.ReadNum(R, e); Files.ReadNum(R, k); Texts.WriteString(W, "LinkProc entry="); Hex(4*e, 5);
        Texts.WriteString(W, " link="); Hex(2*k, 5);
        IF nlinks < LEN(links) THEN links[nlinks] := k; lname[nlinks] := NameOf("proc"); lentry[nlinks] := 2*e; INC(nlinks) END
      ELSE
        Files.ReadString(R, name); Files.ReadNum(R, fprint);
        CASE ch OF
        | 1X: Texts.WriteString(W, "Const  "); Texts.WriteString(W, name)
        | 2X: Texts.WriteString(W, "Type   "); Texts.WriteString(W, name)
        | 3X: Texts.WriteString(W, "Var    "); Texts.WriteString(W, name); Files.ReadNum(R, k);
            Texts.WriteString(W, " sb"); Texts.WriteInt(W, k, 0)
        | 4X: Texts.WriteString(W, "Proc   "); Texts.WriteString(W, name); Files.ReadNum(R, k);
            Texts.WriteString(W, " entry="); Hex(4*k, 5)
        | 5X: Texts.WriteString(W, "CProc  "); Texts.WriteString(W, name)
        | 6X: Texts.WriteString(W, "Struct "); Texts.WriteString(W, name); Files.ReadNum(R, fprint)
        | 8X: Texts.WriteString(W, "TDesc  ");
            IF name = "" THEN Texts.WriteString(W, "(anonymous)"); Files.ReadNum(R, k); s := "TD"
            ELSE Texts.WriteString(W, name); k := fprint; Join(s, "TD ", name)
            END;
            IF nlinks < LEN(links) THEN links[nlinks] := k; lname[nlinks] := NameOf(s); INC(nlinks) END;
            Files.ReadNum(R, k); Texts.WriteString(W, " size="); Texts.WriteInt(W, k, 0); Files.ReadNum(R, k);
            IF k # -1 THEN Files.ReadString(R, name); IF name = "" THEN Files.ReadNum(R, k) END END;
            Files.ReadNum(R, k); Files.ReadNum(R, k); Files.ReadNum(R, nofnewmeth); Files.ReadNum(R, nofptr2);
            WHILE nofnewmeth > 0 DO Files.ReadNum(R, k); Files.ReadNum(R, k); DEC(nofnewmeth) END;
            Texts.WriteString(W, " pointers"); WHILE nofptr2 > 0 DO Files.ReadNum(R, k); Texts.Write(W, " "); Texts.WriteInt(W, k, 0); DEC(nofptr2) END
        ELSE Texts.WriteString(W, "?")
        END
      END;
      Texts.WriteLn(W); Files.Read(R, ch)
    END;
  (* CmdBlk *)
    Block(83X, "commands:"); i := 0;
    WHILE i < nofcom DO Files.ReadString(R, name); Files.ReadNum(R, k);
      Texts.WriteString(W, name); Texts.WriteString(W, "  "); Hex(4*k, 5); Texts.WriteLn(W); INC(i)
    END;
  (* PtrBlk *)
    Block(84X, "pointers:"); i := 0;
    WHILE i < nofptr DO Files.ReadNum(R, k); Texts.WriteString(W, "sb"); Texts.WriteInt(W, k, 0); Texts.WriteLn(W); INC(i) END;
  (* ConstBlk *)
    Block(87X, "constants:"); i := 0;
    WHILE i < consize DO
      Hex(i, 4); Texts.WriteString(W, ":  "); j := 0; name := "";
      WHILE (i < consize) & (j < 16) DO Files.Read(R, ch); Hex(ORD(ch), 2); Texts.Write(W, " ");
        IF (ch >= " ") & (ch < 7FX) THEN name[j] := ch ELSE name[j] := "." END; INC(i); INC(j)
      END;
      name[j] := 0X; Texts.WriteString(W, "  "); Texts.WriteString(W, name); Texts.WriteLn(W)
    END;
  (* CodeBlk *)
    Files.Read(R, ch);
    IF ch # 88X THEN Texts.WriteString(W, "******* no code block"); Texts.WriteLn(W); RETURN END;
    nhw := 2*codesize; IF nhw > CodeLength THEN nhw := CodeLength END; i := 0;
    WHILE i < nhw DO Files.ReadLInt(R, k);
      code[i] := SHORT(SYSTEM.LSH(k, -16) MOD 10000H - 10000H * (SYSTEM.LSH(k, -31) MOD 2));
      code[i+1] := SHORT(k MOD 10000H - 10000H * (k MOD 10000H DIV 8000H));
      label[i] := 0; label[i+1] := 0; linkAt[i] := 0; linkAt[i+1] := 0; INC(i, 2)
    END;
  (* UseBlk *)
    Block(89X, "uses:"); i := 0;
    WHILE i < nofmod DO INC(i); Files.Read(R, ch);
      WHILE ch # 0X DO Files.ReadString(R, name); Files.ReadNum(R, fprint);
        Join(nm, mods[i], "."); Join(nm, nm, name); COPY(nm, s); k := 0;
        CASE ch OF
        | 3X, 4X: Files.ReadNum(R, k)
        | 8X: IF name = "" THEN Files.ReadNum(R, k); Join(s, "TD ", mods[i]) ELSE k := fprint; Join(s, "TD ", nm) END
        ELSE
        END;
        IF (ch = 3X) OR (ch = 4X) OR (ch = 8X) THEN
          Texts.WriteString(W, "  "); Texts.WriteString(W, s); Texts.WriteLn(W);
          IF nlinks < LEN(links) THEN links[nlinks] := k; lname[nlinks] := NameOf(s); INC(nlinks) END
        END;
        Files.Read(R, ch)
      END
    END;
  (* RefBlk: the procedures *)
    nprocs := 0; lastEnd := 0;
    IF showref THEN Block(8AX, "refs:") ELSE Files.Read(R, ch) END;
    Files.Read(R, ch);
    WHILE ~R.eof & (ch = 0F8X) DO
      Files.ReadNum(R, e); Files.ReadNum(R, k); Files.ReadNum(R, k); Files.ReadNum(R, k); Files.ReadNum(R, k);
      Files.ReadString(R, name);
      IF nprocs < MaxProcs THEN COPY(name, procName[nprocs]); procStart[nprocs] := 2*lastEnd; INC(nprocs) END;
      IF showref THEN Texts.WriteString(W, name); Texts.WriteString(W, "  "); Hex(4*lastEnd, 5); Texts.WriteLn(W) END;
      lastEnd := e; Files.Read(R, ch);
      WHILE ~R.eof & (ch >= 1X) & (ch <= 3X) DO
        Files.Read(R, ch); Files.ReadNum(R, k); Files.ReadString(R, name);
        IF showref THEN Texts.WriteString(W, "    "); Texts.WriteString(W, name); Texts.WriteString(W, " ");
          Texts.WriteInt(W, k, 0); Texts.WriteLn(W)
        END;
        Files.Read(R, ch)
      END
    END;
    i := 0;
    WHILE i < nlinks DO
      IF lentry[i] >= 0 THEN j := ProcAt(lentry[i]); IF j >= 0 THEN COPY(procName[j], names[lname[i] - 1]) END END;
      Chain(links[i], lname[i]); INC(i)
    END;
    Texts.WriteLn(W); Texts.WriteString(W, "code:"); Texts.WriteLn(W); Texts.Append(T, W.buf);
    Code;
    Texts.Append(T, W.buf)
  END ReadIn;

  PROCEDURE Decoded(VAR name: ARRAY OF CHAR): BOOLEAN;  (* T := the text of obj/m68k/name.Obj *)
    VAR f: Files.File; fname: Name; tag: INTEGER; i, j: LONGINT;
  BEGIN
    Root.Obj("m68k", fname); i := 0; WHILE fname[i] # 0X DO INC(i) END; j := 0;
    WHILE (name[j] # 0X) & (name[j] # ".") & (i < LEN(fname) - 5) DO fname[i] := name[j]; INC(i); INC(j) END;
    fname[i] := 0X; Join(fname, fname, ".Obj");
    f := Files.Old(fname);
    IF f = NIL THEN Out.String(fname); Out.String(" not found"); Out.Ln; RETURN FALSE END;
    Files.Set(R, f, 0); T := TextFrames.Text(""); nnames := 0; nprocs := 0; nhw := 0; emit := TRUE;
    Files.ReadInt(R, tag);
    IF tag = Tag THEN ReadIn
    ELSE Texts.WriteString(W, fname); Texts.WriteString(W, ": not a 68020 object file"); Texts.WriteLn(W); Texts.Append(T, W.buf)
    END;
    Files.Close(f);
    RETURN TRUE
  END Decoded;

  PROCEDURE GetArgs(VAR S: Texts.Scanner);  (* the parameters, or the selection *)
    VAR text: Texts.Text; beg, end, time: LONGINT;
  BEGIN
    Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF (S.line # 0) OR (S.class # Texts.Name) THEN
      Oberon.GetSelection(text, beg, end, time);
      IF time >= 0 THEN Texts.OpenScanner(S, text, beg); Texts.Scan(S) END
    END
  END GetArgs;

  PROCEDURE Obj*;  (** KDecoder.Obj Module [\r] *)
    VAR S: Texts.Scanner; name, title: Name; x, y: INTEGER; v: Viewers.Viewer;
  BEGIN
    GetArgs(S);
    IF S.class # Texts.Name THEN RETURN END;
    COPY(S.s, name); Texts.Scan(S);
    showref := (S.class = Texts.Char) & ((S.c = "\") OR (S.c = "/")) & (S.nextCh = "r");
    IF Decoded(name) THEN
      Join(title, name, ".Dec");
      Oberon.AllocateUserViewer(0, x, y);
      v := MenuViewers.New(TextFrames.NewMenu(title, "System.Close  System.Copy  System.Grow  Edit.Search "),
        TextFrames.NewText(T, 0), TextFrames.menuH, x, y)
    END
  END Obj;

  PROCEDURE File*;  (** KDecoder.File Module out [\r]: the same text, plain, into the file out *)
    VAR A: Texts.Reader; name, out, opt: Name;
  BEGIN
    Texts.OpenArgs(A);
    IF ~Texts.Arg(A, name) OR ~Texts.Arg(A, out) THEN
      Out.String("usage: KDecoder.File Module out [\r]   writes obj/m68k/Module.Obj decoded into the plain text out,"); Out.Ln;
      Out.String("  with \r also the procedures and variables of the reference block"); Out.Ln; RETURN
    END;
    showref := Texts.Arg(A, opt) & ((opt = "\r") OR (opt = "/r"));
    IF Decoded(name) THEN Texts.StoreFile(out, T, TRUE); Out.String(out); Out.String(" written"); Out.Ln END
  END File;

  PROCEDURE Init;
  BEGIN
    cc[0] := "T"; cc[1] := "F"; cc[2] := "HI"; cc[3] := "LS"; cc[4] := "CC"; cc[5] := "CS"; cc[6] := "NE"; cc[7] := "EQ";
    cc[8] := "VC"; cc[9] := "VS"; cc[10] := "PL"; cc[11] := "MI"; cc[12] := "GE"; cc[13] := "LT"; cc[14] := "GT"; cc[15] := "LE";
    fcc[0] := "F"; fcc[1] := "EQ"; fcc[2] := "OGT"; fcc[3] := "OGE"; fcc[4] := "OLT"; fcc[5] := "OLE"; fcc[6] := "OGL"; fcc[7] := "OR";
    fcc[8] := "UN"; fcc[9] := "UEQ"; fcc[10] := "UGT"; fcc[11] := "UGE"; fcc[12] := "ULT"; fcc[13] := "ULE"; fcc[14] := "NE"; fcc[15] := "T";
    fcc[16] := "SF"; fcc[17] := "SEQ"; fcc[18] := "GT"; fcc[19] := "GE"; fcc[20] := "LT"; fcc[21] := "LE"; fcc[22] := "GL"; fcc[23] := "GLE";
    fcc[24] := "NGLE"; fcc[25] := "NGL"; fcc[26] := "NLE"; fcc[27] := "NLT"; fcc[28] := "NGE"; fcc[29] := "NGT"; fcc[30] := "SNE"; fcc[31] := "ST";
    fmt := "LSXPWDB?";
  END Init;

  PROCEDURE InitF;
    VAR i: LONGINT;
  BEGIN
    i := 0; WHILE i < 128 DO fop[i] := "F?"; INC(i) END;
    fop[0] := "FMOVE"; fop[1] := "FINT"; fop[2] := "FSINH"; fop[3] := "FINTRZ"; fop[4] := "FSQRT"; fop[6] := "FLOGNP1";
    fop[8] := "FETOXM1"; fop[9] := "FTANH"; fop[10] := "FATAN"; fop[12] := "FASIN"; fop[13] := "FATANH"; fop[14] := "FSIN";
    fop[15] := "FTAN"; fop[16] := "FETOX"; fop[17] := "FTWOTOX"; fop[18] := "FTENTOX"; fop[20] := "FLOGN"; fop[21] := "FLOG10";
    fop[22] := "FLOG2"; fop[24] := "FABS"; fop[25] := "FCOSH"; fop[26] := "FNEG"; fop[28] := "FACOS"; fop[29] := "FCOS";
    fop[30] := "FGETEXP"; fop[31] := "FGETMAN"; fop[32] := "FDIV"; fop[33] := "FMOD"; fop[34] := "FADD"; fop[35] := "FMUL";
    fop[36] := "FSGLDIV"; fop[37] := "FREM"; fop[38] := "FSCALE"; fop[39] := "FSGLMUL"; fop[40] := "FSUB"; fop[56] := "FCMP";
    fop[58] := "FTST"; fop[40H] := "FSMOVE"; fop[41H] := "FSSQRT"; fop[44H] := "FDMOVE"; fop[45H] := "FDSQRT";
    fop[58H] := "FSABS"; fop[5AH] := "FSNEG"; fop[5CH] := "FDABS"; fop[5EH] := "FDNEG"; fop[60H] := "FSDIV"; fop[62H] := "FSADD";
    fop[63H] := "FSMUL"; fop[64H] := "FDDIV"; fop[66H] := "FDADD"; fop[67H] := "FDMUL"; fop[68H] := "FSSUB"; fop[6CH] := "FDSUB"
  END InitF;

BEGIN
  Texts.OpenWriter(W); Texts.SetFont(W, Fonts.This("Ttyp0-14-Unicode.Scn.Fnt")); Init; InitF
END KDecoder.
