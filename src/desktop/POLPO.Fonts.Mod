(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)
(*
    peter matthias
    2015-04-21  using portable version of GetCharObj, using Putx from ARM due to aligment restrictions in ARM
    polpo: font scaling. scale (percent) maps a requested screen font of size n to the existing
      font file nearest to n*scale/100, same family first; the font keeps its requested name,
      so texts are stored unchanged. SetScale reloads loaded fonts; broadcast ScaleMsg afterwards.
  *)

MODULE Fonts;  (** portable *) (*JG 16.3.94*)

(**
The Module Fonts implement the Oberon font manager. Fonts are collections 
of characters, each character being a pattern and and metric data.
*)

  IMPORT SYSTEM, Linux0, Kernel, Files, Objects, Display, Root;

  CONST substitute* = -1; font* = 0; metric* = 1; (** Font types. *)
    TraceMissing = TRUE;  TraceAlias = FALSE;
    MaxRef = 32767;  (* polpo: the largest glyph index + 1 a font file may have *)
    
  TYPE 
    Char* = POINTER TO CharDesc;
    Font* = POINTER TO FontDesc;

    CharDesc* = RECORD (Objects.ObjDesc)  (** The objects in a font library. *)  (* Note: offset used in GetCharObj *)
      dx*, x*, y*, w*, h*: INTEGER;  (** Character width, pattern offset (x, y), pattern size (w, h). *)
      pat*: Display.Pattern  (** Character raster data. *)
    END;

    FontDesc* = RECORD (Objects.LibDesc)
      type*: SHORTINT;  (** Substitute, font, or metric. *)
      height*, minX*, maxX*, minY*, maxY*: INTEGER;  (** Font height, extremal values of characters in font. *)
      maxRef*: INTEGER  (** highest valid glyph index + 1; 256 for 8-bit fonts, larger for Unicode fonts *)
    END;

    RunRec = RECORD beg, end: INTEGER END;
    Runs = POINTER TO ARRAY OF RunRec;

    BoxRec = RECORD
      dx, x, y, w, h: INTEGER
    END;
    Boxes = POINTER TO ARRAY OF BoxRec;
    ScaleMsg* = RECORD (Display.FrameMsg)  (** broadcast after SetScale: frames adapt their metrics *)
      oldH*, newH*: INTEGER  (** height of the default font before and after *)
    END;

  VAR FontId*: CHAR;  (** Initial character of font files (.Fnt). *)
      Default*: Font;  (** Default system screen font (typically Oberon10.Scn.Fnt). *)
      theChar: Char;
      conv: BOOLEAN;
      scale*: INTEGER;  (** font scale in percent; 0 until decided *)
   
  PROCEDURE Put1 (VAR a: LONGINT; x: INTEGER);
  VAR y: SHORTINT;
  BEGIN y := SHORT(x); SYSTEM.PUT(a, y); INC(a)
  END Put1;
   
  PROCEDURE Put2 (VAR a: LONGINT; x: LONGINT);
  VAR y: INTEGER;
  BEGIN 
    y := SHORT(x); 
    SYSTEM.PUT(a, CHR(y)); SYSTEM.PUT(a+1,CHR(y DIV 256)); INC(a,2);
  END Put2;
   
  PROCEDURE Put4 (VAR a: LONGINT; x: LONGINT);
  BEGIN
    SYSTEM.PUT(a, CHR(x)); x:=x DIV 256;
    SYSTEM.PUT(a+1, CHR(x)); x:=x DIV 256;
    SYSTEM.PUT(a+2, CHR(x)); x:=x DIV 256;
    SYSTEM.PUT(a+3, CHR(x));
    INC(a,4);
  END Put4;

  PROCEDURE ReadInt (VAR R: Files.Rider; VAR x: INTEGER);
  VAR c0: CHAR; s1: SHORTINT;
  BEGIN Files.Read(R, c0); Files.Read(R, s1); x := s1; x := x * 100H + ORD(c0)
  END ReadInt;

(*
  PROCEDURE *GetCharObj (L: Objects.Library; ref: INTEGER; VAR obj: Objects.Object);
  CODE {SYSTEM.i386}
    MOV EAX, L[EBP]
    MOV EAX, 4[EAX]  ; Objects.LibDesc ind
    MOVSX EBX, ref[EBP]
    MOV EAX, [EAX][EBX*4]
    MOV ECX, theChar
    MOVZX DX, BYTE -3[EAX] ;dx
    MOV 24[ECX], DX
    MOVSX DX, BYTE -2[EAX] ;x
    MOV 26[ECX], DX
    MOVSX DX, BYTE -1[EAX] ;y
    MOV 28[ECX], DX
    MOVZX DX, BYTE [EAX] ;w
    MOV 30[ECX], DX
    MOVZX DX, BYTE 1[EAX] ;h
    MOV 32[ECX], DX
    MOV 36[ECX], EAX
    MOV EAX, obj[EBP]
    MOV [EAX], ECX
  END GetCharObj;
*)

    (* portable version *)
  PROCEDURE GetCharObj (L: Objects.Library; ref: INTEGER; VAR obj: Objects.Object);
  VAR m: LONGINT; h1: SHORTINT; h2: LONGINT; ch: CHAR;
  BEGIN
    SYSTEM.GET(SYSTEM.VAL(LONGINT, L) + 4, m); (* L.ind *)
    IF (ref < 0) OR (ref >= L(Font).maxRef) THEN  (* polpo: outside the index: the null character *)
      h2 := m + LONG(L(Font).maxRef) * SIZE(LONGINT) + 3
    ELSE
      SYSTEM.GET(m + LONG(ref) * SIZE(LONGINT), h2) (* pat adr*)
    END;
    theChar.pat := h2; 
    SYSTEM.GET(h2-3, h1); theChar.dx := h1; 
    SYSTEM.GET(h2-2, h1); theChar.x := h1;
    SYSTEM.GET(h2-1, h1); theChar.y := h1;
    SYSTEM.GET(h2, ch); theChar.w := ORD(ch);  (*width & height always positive*)
    SYSTEM.GET(h2+1,ch); theChar.h := ORD(ch);
    obj := theChar
  END GetCharObj;

(** Return the character and data of ch in a font. *)
  PROCEDURE GetChar* (F: Font; ch: CHAR; VAR dx, x, y, w, h: INTEGER; VAR pat: Display.Pattern);
  VAR obj: Objects.Object;
  BEGIN F.GetObj(F, ORD(ch), obj);
    WITH obj: Char DO
      dx := obj.dx; x := obj.x; y := obj.y; w := obj.w; h := obj.h; pat := obj.pat
    END
  END GetChar;

  (* polpo: a font file is refused (and the font substituted) unless its runs ascend within
     0..MaxRef and its boxes fit the bytes of the index *)
  PROCEDURE Internalize (F: Font; VAR R: Files.Rider; type: SHORTINT): BOOLEAN;
  VAR ch: CHAR;
      NofRuns, NofBoxes, i, k, l, m, maxEnd: INTEGER;
      idxSz, NofBytes, RasterBase, A, a, n: LONGINT;
      run: Runs;
      box: Boxes;
  BEGIN
    Files.Read(R, ch); (*family*)
    Files.Read(R, ch); (*variant*)
    ReadInt(R, F.height);
    ReadInt(R, F.minX); ReadInt(R, F.maxX);
    ReadInt(R, F.minY); ReadInt(R, F.maxY);
    ReadInt(R, NofRuns);
    IF R.eof OR (NofRuns < 0) OR (NofRuns > MaxRef) THEN RETURN FALSE END;
    NEW(run, NofRuns);
    n := 0; k := 0; m := 0;
    WHILE k # NofRuns DO
      ReadInt(R, run[k].beg); ReadInt(R, run[k].end);
      IF (run[k].beg < m) OR (run[k].end < run[k].beg) OR (run[k].end > MaxRef) THEN RETURN FALSE END;
      m := run[k].end; n := n + run[k].end - run[k].beg;
      INC(k)
    END;
    IF n > MaxRef THEN RETURN FALSE END;
    NofBoxes := SHORT(n);
    (* index covers 0..maxEnd-1; minimum 256 for backward compatibility *)
    maxEnd := 256; k := 0;
    WHILE k # NofRuns DO
      IF run[k].end > maxEnd THEN maxEnd := run[k].end END;
      INC(k)
    END;
    idxSz := LONG(maxEnd) * 4;
    F.maxRef := maxEnd;
    NEW(box, NofBoxes);
    l := 0;
    WHILE l # NofBoxes DO
      ReadInt(R, box[l].dx);
      ReadInt(R, box[l].x); ReadInt(R, box[l].y);
      ReadInt(R, box[l].w); ReadInt(R, box[l].h);
      IF (box[l].w < 0) OR (box[l].w > 255) OR (box[l].h < 0) OR (box[l].h > 255) THEN RETURN FALSE END;
      INC(l)
    END;
    IF R.eof THEN RETURN FALSE END;
    F.type := type;
    IF type = font THEN
      NofBytes := idxSz + 29; l := 0;
      WHILE l # NofBoxes DO
        NofBytes := NofBytes + 5 + (box[l].w + 7) DIV 8 * box[l].h; INC(l)
      END;
      SYSTEM.NEW(F.ind, NofBytes);
      RasterBase := SYSTEM.VAL(LONGINT, F.ind);
      A := RasterBase; a := A + idxSz;
      Put1(a, 12); Put1(a, 0); Put1(a, -3); Put1(a, 12); Put1(a, 12); (*null char*)
      Put2(a, 0FFFH);
      Put2(a, 0801H); Put2(a, 0801H); Put2(a, 0801H); Put2(a, 0801H); Put2(a, 0801H);
      Put2(a, 0801H); Put2(a, 0801H); Put2(a, 0801H); Put2(a, 0801H); Put2(a, 0801H);
      Put2(a, 0FFFH);
      k := 0; l := 0; m := 0;
      WHILE k < NofRuns DO
        WHILE m < run[k].beg DO Put4(A, RasterBase + idxSz + 3); INC(m) END;
        WHILE m < run[k].end DO Put4(A, a + 3);
          Put1(a, box[l].dx);
          Put1(a, box[l].x); Put1(a, box[l].y);
          Put1(a, box[l].w); Put1(a, box[l].h);
          i := (box[l].w + 7) DIV 8 * box[l].h;
          WHILE i # 0 DO Files.Read(R, ch); Put1(a, ORD(ch)); DEC(i) END;
          INC(l); INC(m)
        END;
        INC(k)
      END;
      WHILE m < maxEnd DO Put4(A, RasterBase + idxSz + 3); INC(m) END
    ELSE (*type := metric*)
      SYSTEM.NEW(F.ind, idxSz + 5 + NofBoxes*5);
      RasterBase := SYSTEM.VAL(LONGINT, F.ind);
      A := RasterBase; a := A + idxSz;
      Put1(a, 12); Put1(a, 0); Put1(a, -3); Put1(a, 12); Put1(a, 12); (*null char*)
      k := 0; l := 0; m := 0;
      WHILE k < NofRuns DO
        WHILE m < run[k].beg DO Put4(A, RasterBase + idxSz + 3); INC(m) END;
        WHILE m < run[k].end DO Put4(A, a + 3);
          Put1(a, box[l].dx);
          Put1(a, box[l].x); Put1(a, box[l].y);
          Put1(a, box[l].w); Put1(a, box[l].h);
          INC(l); INC(m)
        END;
        INC(k)
      END;
      WHILE m < maxEnd DO Put4(A, RasterBase + idxSz + 3); INC(m) END
    END;
    RETURN TRUE
  END Internalize;

  (* polpo: a font with only the null character, when there is no other *)
  PROCEDURE Empty (F: Font);
  VAR A, a, RasterBase: LONGINT; m: INTEGER;
  BEGIN
    F.height := 12; F.minX := 0; F.maxX := 12; F.minY := -3; F.maxY := 9; F.maxRef := 256;
    SYSTEM.NEW(F.ind, 256 * 4 + 29);
    RasterBase := SYSTEM.VAL(LONGINT, F.ind);
    A := RasterBase; a := A + 256 * 4;
    Put1(a, 12); Put1(a, 0); Put1(a, -3); Put1(a, 12); Put1(a, 12); (*null char*)
    Put2(a, 0FFFH);
    m := 0; WHILE m < 10 DO Put2(a, 0801H); INC(m) END;
    Put2(a, 0FFFH);
    m := 0; WHILE m < 256 DO Put4(A, RasterBase + 256 * 4 + 3); INC(m) END
  END Empty;

  PROCEDURE^ OpenFont(name: ARRAY OF CHAR; VAR f: Files.File);

  PROCEDURE Substitute (F: Font);
  VAR f: Files.File; R: Files.Rider; id: CHAR; t: SHORTINT;
  BEGIN
    IF (Default # NIL) & (Default.ind # NIL) THEN
      F.height := Default.height;
      F.minX := Default.minX; F.maxX := Default.maxX;
      F.minY := Default.minY; F.maxY := Default.maxY;
      F.ind := Default.ind; F.maxRef := Default.maxRef
    ELSE  (* polpo: no default font yet (the desktop is not loaded): Oberon10, else an empty font *)
      OpenFont("Oberon10.Scn.Fnt", f); id := 0X; t := substitute;
      IF f # NIL THEN Files.Set(R, f, 0); Files.Read(R, id); Files.Read(R, t) END;
      IF (id # FontId) OR (t # font) OR ~Internalize(F, R, font) THEN Empty(F) END
    END;
    F.type := substitute;
    IF TraceMissing THEN
      Kernel.WriteString("Missing: ");  Kernel.WriteString(F.name);  Kernel.WriteLn
    END
  END Substitute;

  PROCEDURE OpenFont(name: ARRAY OF CHAR; VAR f: Files.File);
  VAR path: ARRAY 128 OF CHAR; i, j: INTEGER;
  BEGIN
    f := Files.Old(name);
    IF f = NIL THEN
      COPY("fonts/", path); i := 6; j := 0;
      WHILE name[j] # 0X DO path[i] := name[j]; INC(i); INC(j) END;
      path[i] := 0X;
      f := Files.Old(path)
    END
  END OpenFont;

  (* Does the font file name exist in the current directory, fonts/ or <root>/fonts/? (quietly) *)
  PROCEDURE Exists(VAR name: ARRAY OF CHAR): BOOLEAN;
    VAR path: ARRAY 320 OF CHAR; i, j, k, fd, res: LONGINT;
  BEGIN
    k := 0;
    WHILE k < 3 DO
      i := 0;
      IF k = 1 THEN path := "fonts/"; i := 6
      ELSIF k = 2 THEN Root.Join("fonts/", path); WHILE path[i] # 0X DO INC(i) END
      END;
      j := 0; WHILE (name[j] # 0X) & (i < LEN(path)-1) DO path[i] := name[j]; INC(i); INC(j) END;
      path[i] := 0X;
      fd := Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR(path[0]), Linux0.ORDonly, 0);
      IF fd > 0 THEN res := Linux0.Close0(fd); RETURN TRUE END;
      INC(k)
    END;
    RETURN FALSE
  END Exists;

  (* Decide the scale if it is not set: the environment variable OFONTSCALE, else from the
     screen resolution (Display.DPI, 96 dpi = 100%), else 100. *)
  PROCEDURE DecideScale;
    VAR s: ARRAY 16 OF CHAR; i, v: LONGINT;
  BEGIN
    IF scale = 0 THEN
      Kernel.GetConfig("OFONTSCALE", s);
      v := 0; i := 0;
      WHILE (s[i] >= "0") & (s[i] <= "9") DO v := v*10 + ORD(s[i]) - ORD("0"); INC(i) END;
      IF (v = 0) & (Display.DPI >= 120) THEN v := (LONG(Display.DPI)*100 DIV 96 + 12) DIV 25 * 25 END;
      IF v < 50 THEN v := 100 ELSIF v > 800 THEN v := 800 END;
      scale := SHORT(v)
    END
  END DecideScale;

  (** For a screen font name "<family><size><style>.Scn.Fnt": sname is the existing font file
    of the same family and style nearest to size*percent/100, at most tol sizes away (tol < 0:
    a quarter of that size). found is FALSE if there is none, or if name is not such a font name. *)
  PROCEDURE NearestName*(name: ARRAY OF CHAR; percent, tol: LONGINT; VAR sname: ARRAY OF CHAR; VAR found: BOOLEAN);
    VAR i, j, k, n, size, target, d, cand: LONGINT; rest: ARRAY 32 OF CHAR;
  BEGIN
    found := FALSE;
    i := 0; WHILE (CAP(name[i]) >= "A") & (CAP(name[i]) <= "Z") DO INC(i) END;
    j := i; size := 0;
    WHILE (name[j] >= "0") & (name[j] <= "9") DO size := size*10 + ORD(name[j]) - ORD("0"); INC(j) END;
    IF (i = 0) OR (size = 0) THEN RETURN END;
    k := 0; WHILE (name[j] # 0X) & (k < LEN(rest)-1) DO rest[k] := name[j]; INC(j); INC(k) END;
    rest[k] := 0X;
    IF (k < 8) OR (rest[k-8] # ".") OR (rest[k-7] # "S") OR (rest[k-6] # "c") OR (rest[k-5] # "n") THEN RETURN END;
    target := (size*percent + 50) DIV 100; IF tol < 0 THEN tol := target DIV 4 + 1 END; d := 0;
    WHILE ~found & (d <= tol) DO
      n := 0;
      WHILE ~found & (n < 2) DO
        IF n = 0 THEN cand := target + d ELSE cand := target - d END;
        IF (cand > 0) & ((n = 0) OR (d > 0)) THEN
          COPY(name, sname); k := i;  (* family, then size, then the rest *)
          IF cand >= 100 THEN sname[k] := CHR(cand DIV 100 + ORD("0")); INC(k) END;
          IF cand >= 10 THEN sname[k] := CHR(cand DIV 10 MOD 10 + ORD("0")); INC(k) END;
          sname[k] := CHR(cand MOD 10 + ORD("0")); INC(k);
          j := 0; WHILE rest[j] # 0X DO sname[k] := rest[j]; INC(k); INC(j) END;
          sname[k] := 0X;
          found := Exists(sname)
        END;
        INC(n)
      END;
      INC(d)
    END
  END NearestName;

  (* the existing screen font file nearest to name at the current scale, see NearestName *)
  PROCEDURE ScaledName(VAR name, sname: ARRAY OF CHAR; VAR found: BOOLEAN);
  BEGIN
    found := FALSE; DecideScale;
    IF scale # 100 THEN NearestName(name, scale, -1, sname, found) END
  END ScaledName;

  (* OpenFont, with scaling the scaled font file if there is one near enough, else NIL *)
  PROCEDURE OpenScaled(VAR name: ARRAY OF CHAR; VAR f: Files.File; scaled: BOOLEAN);
    VAR sname: Objects.Name; found: BOOLEAN;
  BEGIN
    IF scaled THEN
      ScaledName(name, sname, found);
      IF found THEN OpenFont(sname, f) ELSE f := NIL END
    ELSE OpenFont(name, f)
    END
  END OpenScaled;

  (* Find the font file of L: its name, the Default alias, or Syntax as Oberon. *)
  PROCEDURE Resolve (L: Font; VAR f: Files.File; scaled: BOOLEAN);
  VAR i, j: LONGINT; name: Objects.Name;
  BEGIN
    OpenScaled(L.name, f, scaled);
    IF f = NIL THEN
      COPY(L.name, name);  name[7] := 0X;
      IF name = "Default" THEN
        IF TraceAlias THEN Kernel.WriteString(L.name);  Kernel.WriteString(" -> ") END;
        IF Default # NIL THEN COPY(Default.name, name) ELSE name := "Oberon10.Scn.Fnt" END;
        IF (name[0] = "S") & (name[1] = "y") & (name[2] = "n") & (name[3] = "t") & (name[4] = "a") & (name[5] = "x") THEN
          name := "Oberon10.Scn.Fnt"  (* polpo: a Syntax default is drawn with the Oberon family *)
        END;
        i := 0;  WHILE (name[i] # 0X) & ((name[i] < "0") OR (name[i] > "9")) DO INC(i) END;
        j := 7;  WHILE L.name[j] # 0X DO name[i] := L.name[j];  INC(i);  INC(j) END;
        name[i] := 0X;
        IF TraceAlias THEN Kernel.WriteString(name);  Kernel.WriteLn END;
        OpenScaled(name, f, scaled)  (* polpo: L keeps its requested name *)
      ELSE
        name[6] := 0X;
        IF conv & (name = "Syntax") THEN
          IF TraceAlias THEN Kernel.WriteString(L.name);  Kernel.WriteString(" -> ") END;
          name := "Oberon10.Scn.Fnt";  (* polpo: Syntax is drawn with the Oberon family; Default may be a Syntax font now *)
          j := 0;  WHILE (name[j] # 0X) & ((name[j] < "0") OR (name[j] > "9")) DO INC(j) END;
          i := 6;  WHILE (L.name[i] >= "0") & (L.name[i] <= "9") DO name[j] := L.name[i];  INC(i);  INC(j) END;
          IF L.name[i] = "m" THEN name[j] := "b";  INC(i);  INC(j) END;  (* Syntax medium -> Oberon bold *)
          WHILE L.name[i] # 0X DO name[j] := L.name[i];  INC(i);  INC(j) END;
          name[j] := 0X;
          IF TraceAlias THEN Kernel.WriteString(name);  Kernel.WriteLn END;
          OpenScaled(name, f, scaled)  (* polpo: L keeps its requested name, texts keep Syntax *)
        END
      END
    END
  END Resolve;

  PROCEDURE *Load (L: Objects.Library);
  VAR f: Files.File; R: Files.Rider; id: CHAR; i: LONGINT;
      name: Objects.Name;
  BEGIN
    WITH L: Font DO
      DecideScale;
      f := NIL;
      IF scale # 100 THEN Resolve(L, f, TRUE) END;  (* scaled font file, if there is one *)
      IF f = NIL THEN Resolve(L, f, FALSE) END;
      IF f # NIL THEN
        Files.Set(R, f, 0); Files.Read(R, id);
        IF id = FontId THEN Files.Read(R, L.type);
          IF ((L.type = metric) OR (L.type = font)) & Internalize(L, R, L.type) THEN (* loaded *) ELSE Substitute(L) END
        ELSE Substitute(L) END
      ELSE COPY(L.name, name); i := 0;
        WHILE name[i] # 0X DO INC(i) END;
        IF (i >= 8) & (name[i-8] = ".") & (name[i-7] = "M") & (name[i-6] = "d") THEN
          name[i-7] := "P"; name[i-6] := "r"; OpenFont(name, f);
          IF f # NIL THEN
            Files.Set(R, f, 0); Files.Read(R, id);
            IF id = FontId THEN Files.Read(R, L.type);
              IF ((L.type = metric) OR (L.type = font)) & Internalize(L, R, metric) THEN (* loaded *) ELSE Substitute(L) END
            ELSE Substitute(L) END
          ELSE Substitute(L) END
        ELSE Substitute(L) END
      END
    END
  END Load;

  PROCEDURE ReloadFont (L: Objects.Library);
  BEGIN
    IF (L # NIL) & (L IS Font) & (L(Font).type # substitute) THEN Load(L) END
  END ReloadFont;

  (** Set the font scale in percent and reload all loaded fonts at the new scale. Broadcast a
    ScaleMsg afterwards, so that frames lay out their texts again. *)
  PROCEDURE SetScale* (percent: INTEGER);
  BEGIN
    IF percent < 50 THEN percent := 50 ELSIF percent > 800 THEN percent := 800 END;
    IF percent # scale THEN
      scale := percent;
      ReloadFont(Default);
      Objects.Enumerate(ReloadFont)
    END
  END SetScale;

(** Load and cache a font. *)
  PROCEDURE This* (name: ARRAY OF CHAR): Font;
  VAR L: Objects.Library;
  BEGIN
    L := Objects.ThisLibrary(name);
    IF (L # NIL) & (L IS Font) THEN RETURN L(Font) ELSE RETURN NIL END
  END This;

  PROCEDURE *New (): Objects.Library;
  VAR F: Font;
  BEGIN NEW(F);
    F.Load := Load; F.GetObj := GetCharObj; RETURN F
  END New;

  PROCEDURE Init;
  VAR s: ARRAY 8 OF CHAR;
  BEGIN
    FontId := Objects.LibBlockId; NEW(theChar);
    Kernel.GetConfig("FontConv", s);
    conv := s[0] # "0";
    scale := 0;
    Objects.Register("Fnt", New)
  END Init;
  
BEGIN
  Init
END Fonts.
