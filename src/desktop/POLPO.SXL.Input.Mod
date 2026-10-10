(* OBERON System 3

Copyright 1996 Team of the Institute of Computer Systems of ETH Zurich, ETH Center, CH-8092 Zurich,
e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon System 3 license contract.
The full text can be downloaded from ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/License.Text
or requested from the above-mentioned address.

Under the license terms dated it is in particular (a) prohibited to modify the interface of this module
in any way that disagrees with style or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)

MODULE Input;  (* pjm; xterm/sixel input v17; motion skip retained *)

(*
  Linux Native Oberon Input, p.matthias 1998
  xterm/sixel/vt340 adaptation, norayr chilingarian 2026

    2015-03-03  p.m.  first version for OLR on X11 and Framebuffer, derived from Display.Mod
    2015-03-10        fixed German characters in PollTTY
    2015-03-19  cleaned up, fixed PollX to make X11 working on MIPS & ARM again
    2015-03-26  prepared for copy&paste, added idle time when mouse button pressed
    2015-04-12  merged IdleFB and IdleX11, fixed Time for possible MIPS compiler bug
    2015-04-28  reduced idle time to 10ms
    2015-04-29  removed wait in PollX
    2015-05-15  turning of scrollwheel in X11 mouse does not send button press events any more
    2015-05-25  changed PollMouseFB
    2015-05-29  changed X11 character mapping
    2015-06-05  input event support  ( PollMouseFB, InitMouseFB ); use OMEVENT=/dev/input/eventX if correct device is not found
    2015-07-26  reading 32 bytes for events in PollX
    2015-12-01  PollX: Changed time arg. of Avail to 0 (otherwise pointer lags on MIPS)
    2016-08-24  Added HiDPI mode
    2026-05-19  xterm/sixel/vt340 adaptation

see www.kernel.org/doc/Documentation/input/imput.txt and /usr/include/linux/input.h for information how to use input events (for mouse)

*)

(**
Module Input is responsible for event timing, mouse and keyboard input.
*)

IMPORT  Linux0, Kernel, Display, Utf8, SYSTEM;

CONST
  ME="/dev/input/eventx";

  STDERR=2;
  KDSETMODE=4B3AH;

  TimeUnit* = Kernel.TimeUnit;  (** timer ticks per second ( fixed at 1000 for OLR).  *)

  SHIFT* = 0;  CTRL* = 1;  ALT* = 2;  (** for GetShiftState *)

(* X11 keystate *)
  Shift = 0; Lock = 1; Control = 2; NumLock=4; Win=6; Alt=7;
  CR = 0DX; LF = 0AX;

TYPE
(*
  PollMouse* = PROCEDURE (VAR keys: SET; VAR dx, dy, dz: INTEGER): BOOLEAN;  (** non-portable *)
  PollKeyboard* = PROCEDURE (VAR ch: CHAR; VAR keys: SET): BOOLEAN;  (** non-portable *)
*)
  TermIOs= RECORD
    ciflags, coflags, ccflags, clflags: SET;
    d: CHAR;
    ccc: ARRAY 23 OF CHAR;
  END;

  InputEvent=RECORD
        sec, usec: LONGINT;
        type, code: INTEGER;
        value: LONGINT;
  END;

  Chars* = POINTER TO ARRAY OF CHAR;  (* polpo: selection and clipboard text *)
  Event= RECORD
        code, detail: CHAR;
        sequence: INTEGER;
        time, a, b, c, d: LONGINT;
        ex, ey: INTEGER;
        f: LONGINT;
  END;
(* Events:

  KeyPress=2, KeyRelease=3, ButtonPress=4, ButtonRelease=5, MotionNotify=6, EnterNotify=7, LeaveNotify=8:
  a=root, b=event, c=child, d=rootx+100H*rooty, ex=eventx, xy=eventy, f=state+10000H*samescreen+1000000H*unused

  Expose=12:
  time=window, a=x+10000H*y, b=width+10000H*height

  PropertyNotify = 28
  time=window, a= Atom, b= timestamp, c=state

  SelectionClear=29:
  a=window, b=selection

  SelectionRequest=30:
  a=owner, b=requestor, c=selection, d=target, e=property, f=unused1

  SelectionNotify=31:
  a=requestor, b=selection, c=target, d=property, e= unused1, f=unused2

    KeyPress= RECORD
        code, detail: CHAR;
        sequence: INTEGER;
        time, root, event, child: LONGINT;
        rootx, rooty, eventx, eventy, state: INTEGER;
        samescreen, unused: CHAR;
    END;

    SelectionNotify= RECORD
        code, detail: CHAR;
        sequence: INTEGER;
        time, requestor, selection, target, property: LONGINT;
        unused1, unused2: LONGINT;
    END;
*)
CONST
  CURRENTTIME=0;
  XAPRIMARY = 1;
  XASTRING = 31;
  None= 0;

VAR
  clip*: Chars;  (* clipboard *)
  dfd: LONGINT;  (* Display Filedescriptor (X11 socket or /dev/fb0 *)
  mouseX, mouseY: INTEGER;
  keyss, keyState: SET;
  modState: LONGINT;  (* polpo: modifiers of the last key or mouse report, as X: 1 Shift, 4 Control, 8 Alt *)
  err: LONGINT;
  cb1, cb2: LONGINT;
  buf: ARRAY 32 OF CHAR; (* input char buffer *)
  utf: ARRAY 32 OF BOOLEAN;
  keywarn: BOOLEAN;

  fdset: SET;
  trace: BOOLEAN;
  mouseSkip, mouseMotionCount: LONGINT;

(* FB *)
  switching, onoberon: BOOLEAN;
  kbdfd: LONGINT;  (* keyboard fd *)
  mfd: LONGINT;  (* mouse fd *)
  oldtermios: TermIOs;

(* X11 *)
  CopyClip*, PasteClip*: PROCEDURE;  (* initialized in System *)
  Pause*: PROCEDURE;  (** polpo: Ctrl+Alt+P pauses or continues a command, set by Oberon *)
  lastPoll: LONGINT;  (* the time Time last read the keyboard *)
  pauseReq: BOOLEAN;  (* Ctrl+Alt+P was read, Pause is to be called *)
  x11, mmbe, iemouse: BOOLEAN;
  myProperty: LONGINT;

PROCEDURE WriteSH( str: ARRAY OF CHAR; i: LONGINT);
BEGIN
  Kernel.WriteString( str); Kernel.WriteHex( i, 8); Kernel.WriteLn;
END WriteSH;

PROCEDURE WriteString( str: ARRAY OF CHAR);
BEGIN
  Kernel.WriteString( str); Kernel.WriteLn;
END WriteString;

PROCEDURE WriteErr( str: ARRAY OF CHAR);
VAR res, len: LONGINT;
BEGIN
  Kernel.WriteString( str); Kernel.WriteLn;
  len:=0;
  WHILE (str[len]#0X) & (len < LEN(str)-1) DO INC( len) END;
  str[len]:=0AX;
  res:=Linux0.Write0(STDERR, SYSTEM.ADR(str), len+1);
END WriteErr;

PROCEDURE Put(ch: CHAR; isUTF: BOOLEAN);
BEGIN
  buf[cb2 MOD 32] := ch; utf[cb2 MOD 32] := isUTF; INC(cb2)
END Put;

PROCEDURE PutUnicode(u: LONGINT);
VAR s: ARRAY 4 OF CHAR; n, i: INTEGER;
BEGIN
  Utf8.Chr(u, s, n); i := 0;
  WHILE i < n DO Put(s[i], n > 1); INC(i) END
END PutUnicode;

PROCEDURE Str2Int( str: ARRAY OF CHAR; default: INTEGER): INTEGER;
VAR i, j: INTEGER; neg: BOOLEAN;
BEGIN
  IF str#"" THEN
    i:=0; j:=0;
    neg:=str[0]="-";
    IF neg THEN j:=1 END;
    WHILE (j<LEN(str)) & (str[j]>= "0") & (str[j]<= "9") DO
      i:=i*10+ORD(str[j])-ORD("0");
      INC(j);
    END;
    IF neg THEN i:=-i END;
    RETURN i
  END;
  RETURN default
END Str2Int;

PROCEDURE^ PollTTY;

PROCEDURE Avail( fd: SET; usec: LONGINT): BOOLEAN;
TYPE  TimeVal= RECORD tvsec, tvusec: LONGINT END;
VAR num: LONGINT; timeout: TimeVal;
BEGIN
  timeout.tvsec:=0; timeout.tvusec:= usec;    (* don't block at all *)
  num:= Linux0.Select0(32, SYSTEM.ADR(fd), 0, 0, SYSTEM.ADR(timeout));
  RETURN num>0;
END Avail;

PROCEDURE Idle( code: LONGINT);    (* code ignored *)
VAR x: BOOLEAN;
BEGIN
  x:=Avail( fdset, 10*1000);
  IF x & ~x11 THEN PollTTY END;
  (* Terminal sixel backend: let Display flush a pending coalesced frame.
     PutImage with zero size is treated as an idle tick by POLPO.SXL.Display. *)
  Display.PutImage(0, 0, 0, 0)
END Idle;

PROCEDURE PollMouseFB;
VAR e: InputEvent;  res: LONGINT; b: ARRAY 4 OF CHAR;
BEGIN
  WHILE Avail( {mfd}, 0) DO
    IF iemouse THEN
      res:= Linux0.Read0( mfd, SYSTEM.ADR( e), SIZE(InputEvent));
      IF e.type=1H THEN    (* EV_KEY *)
        IF e.value= 1 THEN  (* button press *)
          IF e.code=110H THEN INCL( keyss, 2);    (* left *)
          ELSIF e.code= 112H THEN INCL( keyss, 1); (* middle *)
          ELSIF e.code= 111H THEN INCL( keyss, 0);  (* right *)
          END;
        ELSIF e.value= 0 THEN  (* button release *)
          IF e.code= 110H THEN  EXCL( keyss, 2);  (* left *)
          ELSIF e.code= 112H THEN EXCL( keyss, 1); (* middle *)
          ELSIF e.code= 111H THEN EXCL( keyss, 0);  (* right *)
          END;
        END;
      ELSIF e.type=2H THEN  (* EV_REL *)
        IF e.code=0H THEN  (* relx *)
          INC(mouseX, SHORT(e.value));
        ELSIF e.code= 1H THEN   (* rely *)
          INC(mouseY, SHORT(e.value));
        END;
      END;
    ELSE  (* PS/2 mouse interface *)
      res:= Linux0.Read0( mfd, SYSTEM.ADR( b), 3);
    keyss:=SYSTEM.VAL( SET, LONG( ORD( b[0]) DIV 2 MOD 4 + ORD( b[0])  MOD 2*4));
      INC(mouseX,ORD(b[1])-ORD(b[0]) DIV 16 MOD 2 *256);
      DEC(mouseY, ORD(b[2])-ORD(b[0]) DIV 32 MOD 2 *256);
    END;
  END;
END PollMouseFB;

PROCEDURE ReadChar( VAR ch: CHAR);
BEGIN
  IF Linux0.Read0( kbdfd, SYSTEM.ADR(ch), 1)#1 THEN ch:=0X END;
  IF trace THEN Kernel.WriteHex( ORD( ch), 3) END;
END ReadChar;


PROCEDURE IsDigit(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch >= "0") & (ch <= "9")
END IsDigit;

PROCEDURE ReadDec(VAR n: LONGINT; VAR term: CHAR): BOOLEAN;
VAR ch: CHAR;
BEGIN
  n:=0; term:=0X;
  LOOP
    IF ~Avail({kbdfd}, 0) THEN RETURN FALSE END;
    ReadChar(ch);
    IF IsDigit(ch) THEN
      n:=n*10 + ORD(ch)-ORD("0")
    ELSE
      term:=ch;
      RETURN TRUE
    END
  END
END ReadDec;

PROCEDURE PollMouseSGR(): BOOLEAN;
VAR b, x, y: LONGINT; term: CHAR; btn: LONGINT; motion, applypos: BOOLEAN;
BEGIN
  (* xterm SGR mouse: ESC [ < b ; x ; y M/m
     With mode ?1016 enabled, x and y are pixel coordinates.
     xterm reports 1-based coordinates, so convert to 0-based framebuffer pixels.

     SXL_MOUSE_SKIP controls motion throttling:
       0 = apply every motion event
       1 = apply every second motion event
       2 = apply every third motion event
     Clicks/releases always update position and button state. *)
  IF ~ReadDec(b, term) OR (term # ";") THEN RETURN FALSE END;
  IF ~ReadDec(x, term) OR (term # ";") THEN RETURN FALSE END;
  IF ~ReadDec(y, term) THEN RETURN FALSE END;

  DEC(x); DEC(y);
  IF x < 0 THEN x:=0 END;
  IF y < 0 THEN y:=0 END;
  IF x >= Display.Width THEN x:=Display.Width-1 END;
  IF y >= Display.Height THEN y:=Display.Height-1 END;

  motion:=((b DIV 32) MOD 2)=1;
  applypos:=TRUE;
  IF motion & (mouseSkip>0) THEN
    INC(mouseMotionCount);
    applypos := (mouseMotionCount MOD (mouseSkip+1)) = 0
  END;

  (* Button transitions must never be skipped, otherwise clicks drift. *)
  IF ~motion OR applypos THEN
    mouseX:=SHORT(x); mouseY:=SHORT(y)
  END;

  btn:=b MOD 4;
  modState := 0;  (* SGR modifier bits: 4 Shift, 8 Meta, 16 Control *)
  IF ODD(b DIV 4) THEN INC(modState, 1) END;
  IF ODD(b DIV 8) THEN INC(modState, 8) END;
  IF ODD(b DIV 16) THEN INC(modState, 4) END;
  IF term = "M" THEN
    IF b >= 64 THEN
      (* wheel events ignored for now *)
    ELSIF motion THEN
      (* motion event: position already handled above; keep existing button state *)
    ELSIF btn = 0 THEN INCL(keyss, 2)     (* left *)
    ELSIF btn = 1 THEN INCL(keyss, 1)     (* middle *)
    ELSIF btn = 2 THEN INCL(keyss, 0)     (* right *)
    END
  ELSIF term = "m" THEN
    (* release; in SGR mode xterm normally says which button was released *)
    IF btn = 0 THEN EXCL(keyss, 2)
    ELSIF btn = 1 THEN EXCL(keyss, 1)
    ELSIF btn = 2 THEN EXCL(keyss, 0)
    ELSE keyss:={}
    END
  END;
  RETURN TRUE
END PollMouseSGR;

PROCEDURE MapCSIKey(n: LONGINT; VAR ch: CHAR);
BEGIN
  ch:=0X;
  CASE n OF
    1: ch:=0A8X;      (* Home *)
  | 2: ch:=0A0X;      (* Insert *)
  | 3: ch:=0A1X;      (* Delete *)
  | 4: ch:=0A9X;      (* End *)
  | 5: ch:=0A2X;      (* Page Up *)
  | 6: ch:=0A3X;      (* Page Down *)
  | 11: ch:=0A4X;     (* F1, xterm ESC [ 11 ~ *)
  | 12: ch:=0A5X;     (* F2 *)
  | 13: ch:=0A6X;     (* F3 *)
  | 14: ch:=0A7X;     (* F4 *)
  | 15: ch:=0F5X;     (* F5 *)
  | 17: ch:=0F6X;     (* F6 *)
  | 18: ch:=0F7X;     (* F7 *)
  | 19: ch:=0F8X;     (* F8 *)
  | 20: ch:=0F9X;     (* F9 *)
  | 21: ch:=0FAX;     (* F10 *)
  | 23: ch:=0FBX;     (* F11 *)
  | 24: ch:=0FCX;     (* F12 *)
  ELSE
  END
END MapCSIKey;

PROCEDURE PollTTY;
VAR ch, ch2, term: CHAR; n, m: LONGINT; isUTF: BOOLEAN;
BEGIN
IF Avail( {kbdfd}, 0) THEN  ReadChar( ch);
  isUTF := ORD(ch) >= 080H;
  modState := 0;
  IF (ch = 0C2X) & Avail( {kbdfd}, 0) THEN  (* polpo: xterm sends Ctrl+Alt+C as U+0083 (C2 83), Ctrl+Alt+P as U+0090 *)
    ReadChar( ch2);
    IF ch2 = 83X THEN Linux0.break := TRUE; ch := 0X
    ELSIF ch2 = 90X THEN pauseReq := TRUE; ch := 0X  (* Ctrl+Alt+P: U+0090 *)
    ELSE Put(ch, TRUE); ch := ch2
    END
  END;
  IF ( ch= 1BX) & Avail( {kbdfd}, 0) THEN
    isUTF := FALSE;
    ReadChar( ch);

    IF ch=03X THEN       (* polpo: Ctrl+Alt+C (Esc, then Ctrl+C) interrupts the running command *)
      Linux0.break := TRUE; ch:=0X
    ELSIF ch=10X THEN    (* polpo: Ctrl+Alt+P (Esc, then Ctrl+P) pauses or continues it *)
      pauseReq := TRUE; ch:=0X
    ELSIF ch="O" THEN       (* SS3: xterm often sends F1..F4 as ESC O P/Q/R/S *)
      ch:=0X;
      IF Avail({kbdfd}, 0) THEN
        ReadChar(ch2);
        IF ch2="P" THEN ch:=0A4X       (* F1 *)
        ELSIF ch2="Q" THEN ch:=0A5X    (* F2 *)
        ELSIF ch2="R" THEN ch:=0A6X    (* F3 *)
        ELSIF ch2="S" THEN ch:=0A7X    (* F4 *)
        ELSIF ch2="A" THEN ch:=0C1X    (* up *)
        ELSIF ch2="B" THEN ch:=0C2X    (* down *)
        ELSIF ch2="C" THEN ch:=0C3X    (* right *)
        ELSIF ch2="D" THEN ch:=0C4X    (* left *)
        ELSIF ch2="H" THEN ch:=0A8X    (* Home *)
        ELSIF ch2="F" THEN ch:=0A9X    (* End *)
        END
      END

    ELSIF ( ch= "[") & Avail( {kbdfd}, 0) THEN
      ReadChar( ch);
      IF ch="<" THEN
        IF PollMouseSGR() THEN ch:=0X END
      ELSIF ( ch>="A") & (ch<="D") THEN ch:= CHR( ORD(ch)+80H);
      ELSIF ch="H" THEN ch:=0A8X    (* Home *)
      ELSIF ch="F" THEN ch:=0A9X    (* End *)
      ELSIF ch="[" THEN     (* VT100/xterm old application function keys: ESC [ [ A..E *)
        ch:=0X;
        IF Avail( {kbdfd}, 0) THEN
          ReadChar(ch2);
          CASE ORD( ch2) OF
            65: ch:=0A4X;   (* F1 *)
          | 66: ch:=0A5X;   (* F2 *)
          | 67: ch:=0A6X;   (* F3 *)
          | 68: ch:=0A7X;   (* F4 *)
          | 69: ch:=0F5X;   (* F5 *)
          ELSE
          END
        END
      ELSIF IsDigit(ch) THEN
        n:=ORD(ch)-ORD("0"); term:=0X;
        WHILE Avail({kbdfd}, 0) & IsDigit(ch) DO
          ReadChar(ch);
          IF IsDigit(ch) THEN n:=n*10 + ORD(ch)-ORD("0")
          ELSE term:=ch
          END
        END;
        IF term="~" THEN
          MapCSIKey(n, ch)
        ELSIF (term=";") & ReadDec(m, term) THEN
          (* modified keys: ESC [ n ; m final, m-1 = 1 Shift + 2 Alt + 4 Control *)
          DEC(m);
          IF ODD(m) THEN INC(modState, 1) END;
          IF ODD(m DIV 2) THEN INC(modState, 8) END;
          IF ODD(m DIV 4) THEN INC(modState, 4) END;
          IF term="~" THEN MapCSIKey(n, ch)
          ELSIF (term>="A") & (term<="D") THEN ch:=CHR(ORD(term)+80H)
          ELSIF term="H" THEN ch:=0A8X
          ELSIF term="F" THEN ch:=0A9X
          ELSE ch:=0X
          END
        ELSE
          (* Ignore modified CSI forms like ESC [ 1 ; 2 P for now.
             Drain until a likely final byte so the sequence does not leak as text. *)
          WHILE (term#0X) & (term<"@") & Avail({kbdfd}, 0) DO ReadChar(term) END;
          ch:=0X
        END
      ELSE
        ch:=0X
      END;
    ELSE
      ch:=0X
    END;
  ELSIF ch=0AX THEN ch:= 0DX;
  END;
  (* xterm may send Backspace either as BS (^H, 08H) or DEL (7FH).
     Oberon text editing expects DEL for backspace, as in the X11 path. *)
  IF ch=08X THEN ch:=7FX END;
  IF ch#0X THEN
    Put(ch, isUTF);
    IF trace THEN WriteSH("->", ORD(ch)) END;
  END;
END;
END PollTTY;

PROCEDURE InternAtom(): LONGINT;
VAR b: ARRAY 8 OF LONGINT; res: LONGINT;
BEGIN
  b[0]:=16+ 6*10000H;
  b[1]:= 14;
  SYSTEM.MOVE( SYSTEM.ADR( "OberonProperty"), SYSTEM.ADR(b[ 2]), 14);
  res:=Linux0.Write0(dfd, SYSTEM.ADR(b),  24);
  res:=Linux0.Read0(dfd, SYSTEM.ADR(b),  32);
  IF trace THEN WriteSH("OberonProperty = ", b[2]) END;
  RETURN b[2];
END InternAtom;

PROCEDURE GetProperty( VAR event: Event);
VAR res: LONGINT; b: ARRAY 8 OF LONGINT;
BEGIN
  IF trace THEN
    Kernel.WriteString("GetProperty seq, win, atom, time, state");
    Kernel.WriteHex( event.sequence, 9  );
    Kernel.WriteHex( event.time, 9  );
    Kernel.WriteHex( event.a, 9  );
    Kernel.WriteHex( event.b, 9  );
    Kernel.WriteHex( event.c, 9  ); Kernel.WriteLn;
  END;
  b[0]:=20+6*10000H;    (* GetProperty *)
  b[1]:= Display.wid;
  b[2]:= myProperty;    (* property *)
  b[3]:= 0;  (* any type *)
  b[4]:= 0;  (* offset; *)
  b[5]:= 8192;  (*length;*)
  res:=Linux0.Write0( dfd, SYSTEM.ADR(b), 24);
  res:=Linux0.Read0( dfd, SYSTEM.ADR(b), 32);
  IF b[1]>0 THEN
    NEW( clip, b[4]);
    res:=Linux0.Read0( dfd, SYSTEM.ADR( clip^), b[4]);
    IF res=b[4] THEN WriteString( clip^)
    ELSE WriteString( "selection failed")
    END;
  END;
END GetProperty;

PROCEDURE Copy*;
VAR b: ARRAY 4 OF LONGINT; res: LONGINT;
BEGIN
  IF x11 THEN
    b[0]:=22+4*10000H;  (* SetSelectionOwner *)
    b[1]:=Display.wid;
    b[2]:=XAPRIMARY;
    b[3]:=CURRENTTIME;
    res:=Linux0.Write0(dfd, SYSTEM.ADR(b),  16);
  END;
END Copy;

PROCEDURE GetSelectionOwner(): LONGINT;
VAR b: ARRAY 8 OF LONGINT; res: LONGINT;
BEGIN
  b[0]:=23+2*10000H;
  b[1]:=XAPRIMARY;
  res:=Linux0.Write0(dfd, SYSTEM.ADR(b),  8);
  res:=Linux0.Read0(dfd, SYSTEM.ADR(b),  32);
  RETURN b[2];
END GetSelectionOwner;

PROCEDURE Paste*;
VAR b: ARRAY 6 OF LONGINT; res: LONGINT;
BEGIN
  IF x11 THEN
    b[0]:=24+6*10000H;  (* ConvertSelection *)
    b[1]:=Display.wid;
    b[2]:=XAPRIMARY;
    b[3]:=XASTRING;
    b[4]:= myProperty;
    b[5]:=CURRENTTIME;
    res:=Linux0.Write0(dfd, SYSTEM.ADR(b),  24);
  END;
END Paste;

PROCEDURE SendSelection(VAR event: Event);
VAR res: LONGINT;
    e: ARRAY 11 OF LONGINT;
    p: ARRAY 6 OF LONGINT;
BEGIN
  IF clip = NIL THEN
    WriteString("SendSelection: clip = NIL!");
    RETURN
  END;
  e[0]:=  25+11*10000H;  (* SendEvent *)
  e[1]:=  event.b; (*Display.scn.root;*)
  e[2]:=  0;
  e[0+3]:= 31; (* SelectionNotify *)
  e[1+3]:= CURRENTTIME;
  e[2+3]:= event.b;  (*requestor *)
  e[3+3]:= XAPRIMARY;
  e[4+3]:= event.d;  (* target *)
  IF (event.c = XAPRIMARY)  & (event.d = XASTRING) THEN
    e[5+3] := event.ex + 10000H*event.ey;  (*property *)

    p[0]:=18+0*100H+(6+(LEN(clip^)+3) DIV 4)*10000H;  (* ChangeProperty *)
    p[1]:= event.b;  (*requestor*)
    p[2]:= event.ex + 10000H*event.ey;  (*property*)
    p[3]:= event.d; (* target*)
    p[4]:= 8;  (* format (bits) *)
    p[5]:= LEN(clip^);
    res:=Linux0.Write0(dfd, SYSTEM.ADR(p),  6*4);
    res:=Linux0.Write0(dfd, SYSTEM.ADR(clip^),  (LEN(clip^)+3) DIV 4*4);
  ELSE
    IF trace THEN WriteString("Failed: ") END;
    e[5+3] := None  (*property *)
  END;
  IF trace THEN
    WriteString("SelectionRequest: "); WriteSH( "Time: ",event.time);
    WriteSH( "owner: ",event.a);   WriteSH( "requestor: ",event.b);   WriteSH( "selection: ",event.c);
    WriteSH( "target: ", event.d);  WriteSH( "property: ",event.ex+10000H*event.ey);
  END;
  res:=Linux0.Write0(dfd, SYSTEM.ADR(e),  44);
END SendSelection;

PROCEDURE ReceiveSelection (VAR event: Event);
BEGIN
  IF trace THEN
    WriteString("SelectionNotify: "); WriteSH( "Time: ", event.time);
    WriteSH( "owner: ",event.a);   WriteSH( "requestor: ",event.b);   WriteSH( "selection: ",event.c);
    WriteSH( "target: ", event.d);  WriteSH( "property: ",event.ex+10000H*event.ey);
  END;
  IF (event.b = XAPRIMARY) & (event.d=myProperty) THEN
    GetProperty(event);
  END
END ReceiveSelection;

PROCEDURE PollX;
VAR
  st: LONGINT; brk, pz: BOOLEAN;
  detail, code, state, sym, grp, h, i, res, w, sw: LONGINT;
  event: Event;
  c: CHAR;
BEGIN
  WHILE Avail( {dfd}, 0) DO
    res:=Linux0.Read0(dfd, SYSTEM.ADR(event),  32);
    IF res # 32 THEN
      WriteString("PollX: short X11 read");
      RETURN
    END;
    IF res=32 THEN
      code:= ORD(event.code) MOD 32;
      detail:= ORD( event.detail);
      IF code=2 THEN    (* KeyPress *)
        state:=event.f MOD 10000H;
        grp := state DIV 2000H MOD 4; state := state MOD 2000H;
        IF ODD(state DIV 80H) THEN state:=2 + state MOD 2;
        ELSIF state MOD 8=2 THEN state:=1;
        ELSIF state MOD 8 =3 THEN state:=2;
        ELSIF ODD(state DIV 10H) & (detail>=4DH) & (detail<=5BH) THEN state:=1;  (* Num-Lock *)
        ELSIF state>=7 THEN  WriteSH("X11: event.state: ", event.f ); state:= state MOD 8;
        END;
        INC(state, grp*2);
        sym:=Display.X11GetSym(detail, state);
        (* polpo: Ctrl+Pause/Break and Ctrl+Alt+C interrupt the running command (trap 13), as Ctrl+C
           in the terminal of loksh does *)
        st := event.f MOD 10000H;
        brk := ODD(st DIV 4) & ((sym = 0FF13H) OR (sym = 0FF6BH) OR ODD(st DIV 8) & (CAP(CHR(sym MOD 100H)) = "C") & (sym < 100H));
        pz := ODD(st DIV 4) & ODD(st DIV 8) & (CAP(CHR(sym MOD 100H)) = "P") & (sym < 100H);  (* Ctrl+Alt+P: pause *)
        IF trace THEN
          Kernel.WriteString("detail: "); Kernel.WriteHex(detail, 8); Kernel.WriteString(" symbol: "); Kernel.WriteHex( sym, 8);  WriteSH(" state: ", event.f);
        END;
        c:= CHR( sym MOD 100H);
        IF detail=024H THEN c:=0DX;  (* cr (enter) *)
        ELSIF detail= 6FH THEN c:=0C1X;  (* ^ *)
        ELSIF detail= 71H THEN c:=0C4X;  (* <- *)
        ELSIF detail= 74H THEN c:=0C2X;  (* v *)
        ELSIF detail= 72H THEN c:=0C3X;  (* -> *)
        ELSIF (detail=25H) OR (detail=69H) THEN
          INCL( keyState, Control); c:=0X;
          IF mmbe THEN  (* middle mouse button emulation *)
            INCL( keyss, 1);    (* LCtrl middle mouse button emulation *)
          END;
        ELSIF sym=0FE52H THEN c:=5EX;    (* ^ *)
        ELSIF sym=0FE53H THEN c:= 7EX;    (*  ntilde  *)
        ELSIF sym=0FE03H THEN c:= 0X;    (*  Alt Gr  *)
        ELSIF (sym >= 0FE08H) & (sym <= 0FE11H) THEN c:=0X
        ELSIF sym >=0FF00H THEN
          IF sym >= 01000000H THEN
            PutUnicode(sym MOD 01000000H); c:=0X
          ELSE
            c:=0X; sym:=sym MOD 100H;
            IF sym=063H THEN c:=0A0X END;
            IF sym=050H THEN c:=0A8X END;
            IF sym=055H THEN c:=0A2X END;
            IF sym=0FFH THEN c:=0A1X END;
            IF sym=057H THEN c:=0A9X END;
            IF sym=056H THEN c:=0A3X END;
            IF sym=008H THEN c:=7FX END;
            IF sym=01BH THEN c:=0A5X END;
            IF sym=009H THEN c:=09X END;
            IF sym DIV 2=0BEH DIV 2 THEN c:=CHR(0A4H+sym MOD 2) END;
            IF sym DIV 2=0C0H DIV 2 THEN c:=CHR(0A6H+sym MOD 2) END;
            IF (sym>=0C2H) & (sym<=0C9H) THEN c:=CHR(sym-0C2H+0F5H) END;
            IF sym=0AFH THEN c:="/" END;
            IF sym=0AAH THEN c:="*" END;
            IF sym=0ADH THEN c:="-" END;
            IF sym=0ABH THEN c:="+" END;
            IF sym=0ACH THEN c:="," END;
            IF sym=09FH THEN c:=0A1X END;
            IF (sym>=0B0H) & (sym<=0B9H) THEN c:=CHR(sym MOD 16 + ORD("0")) END;
            IF sym=08DH THEN c:=0DX END;
            IF sym=097H THEN c:=0C1X END;
            IF sym=096H THEN c:=0C4X END;
            IF sym=099H THEN c:=0C2X END;
            IF sym=098H THEN c:=0C3X END
          END

        ELSE
          IF ORD(c) >= 0A0H THEN PutUnicode(ORD(c)); c:=0X END
        END;

        IF brk THEN Linux0.break := TRUE
        ELSIF pz THEN pauseReq := TRUE
        ELSIF sym=0AFEH THEN Paste;  (* ctrl-v *)
        ELSIF c#0X THEN
          Put(c, FALSE);
        END;
      ELSIF code= 3 THEN  (* KeyRelease *)
        IF (detail=25H) OR (detail=69H) THEN
          EXCL(keyState, Control);
          IF mmbe THEN EXCL( keyss, 1) END; (* LCtrl , RCtrl middle mouse button emulation*)
        END;
      ELSIF code= 4 THEN  (* ButtonPress *)
        IF detail<4 THEN
          INCL( keyss, 3- detail);
          IF detail=2 THEN mmbe:= FALSE END;
        END;
      ELSIF code= 5 THEN
        IF detail<4 THEN  (* ButtonRelease *)
          EXCL( keyss, 3- detail);
        END;
      ELSIF code= 6 THEN  (* MotionNotify, absolute values *)
        mouseX:= event.ex DIV SHORT(Display.Zoom);
        mouseY:= event.ey DIV SHORT(Display.Zoom);
      ELSIF code = 11 THEN  (* KeymapNotify*)
        WriteString("KeymapNotify");
      ELSIF code= 12 THEN  (* Expose *)
        w:= (event.b)  MOD 10000H;
        h:= (event.b DIV 10000H) MOD 10000H;
        IF w> Display.Width*Display.Zoom THEN w:= Display.Width*Display.Zoom END;
        IF h> Display.Height*Display.Zoom THEN h:= Display.Height*Display.Zoom END;
        Display.PutImage( event.a MOD 10000H, Display.Height*Display.Zoom-h-(event.a DIV 10000H), w , h);
      ELSIF code=15 THEN   (* VisibilityChange *)
      ELSIF code= 28 THEN    (* PropertyNotify *)
      ELSIF code = 29 THEN  (* SelectionClear *)
        WriteString("ClearSelection");
(*        selection:=NIL;  *)
      ELSIF code= 30 THEN  (* SelectionRequest, SendSelection *)
        IF (CopyClip # NIL) & (event.a # event.b) THEN
          CopyClip;
          IF clip # NIL THEN
            SendSelection( event);
            clip:=NIL;
          ELSE
            WriteString("PollX: clip = NIL after CopyClip");
          END
        END;
      ELSIF code= 31 THEN  (* SelectionNotify, ReceiveSelection *)
        IF PasteClip# NIL THEN
          ReceiveSelection( event);
          PasteClip;
          clip:=NIL;
        END;
      ELSIF code=0 THEN  (* error *)
        IF err<32  THEN
          WriteSH("PollX: Received error no. ", detail);
          WriteSH("PollX: error. ", event.time);
          WriteSH("PollX: opcode. ", event.a);
          INC(err);
        END;
  (*      IF detail=0 THEN Kernel.Shutdown( 1) END; *)
      ELSE
        WriteSH("Event Error... ", code);
        WriteSH("Event detail... ", detail);
      END;
(*    ELSE
      WriteSH("Res Error... ", res);*)
    END;
(*  ELSE*)
(*    IF Avail( {dfd}, 0*1000) THEN END;  (* wait... *)*)
  END;
END PollX;

(* ---- Interface ---- *)

  (** Returns the number of keystrokes in the keyboard input buffer. *)
(* polpo: the pause key was read: Oberon.Pause, which may run the desktop until it is read again *)
PROCEDURE CheckPause;
BEGIN
  IF pauseReq & (Pause # NIL) THEN pauseReq := FALSE; Pause END
END CheckPause;

PROCEDURE Available*(): INTEGER;
BEGIN
  IF x11 THEN PollX()
  ELSE PollTTY()
  END;
  IF Linux0.break THEN Linux0.break := FALSE; HALT( 113) END;  (* polpo: an interrupt key was read *)
  CheckPause;
  RETURN SHORT(cb2-cb1);
END Available;

(* GetMouseEvent - Read a mouse event *)

(** Reads the current mouse position x, y and the key state of the mouse buttons
(also called keys). The mouse buttons are numbered from the right to the left as
0, 1, 2 (i.e. 1 is the middle mouse button). For example, when the left and middle
buttons are pressed, keys will be set to {1, 2}. *)

PROCEDURE Mouse*(VAR keys: SET; VAR x, y: INTEGER);
BEGIN
  IF x11 THEN PollX
  ELSIF mfd>=0 THEN PollMouseFB
  ELSE
    WHILE Avail({kbdfd}, 0) DO PollTTY END
  END;
  IF mouseX>=Display.Width THEN mouseX:=Display.Width-1 END;
  IF mouseX<0 THEN mouseX:=0 END;
  IF mouseY>=Display.Height THEN mouseY:=Display.Height-1 END;
  IF mouseY<0  THEN mouseY:= 0 END;
  x:= (mouseX ); y:= (Display.Height-1-mouseY) ;
  keys:= keyss;
END Mouse;

(** Read a character from the keyboard buffer. Blocks if no character is available. *)
PROCEDURE ReadUTF8*(VAR ch: CHAR; VAR isUTF: BOOLEAN);
BEGIN
  WHILE cb2<= cb1 DO
    Idle(0);
    IF x11 THEN PollX()
    ELSE PollTTY()
    END;
    IF Linux0.break THEN Linux0.break := FALSE; HALT( 113) END;
    CheckPause
  END;
  ch:= buf[ cb1 MOD 32];
  isUTF := utf[cb1 MOD 32];
  INC( cb1);
END ReadUTF8;

PROCEDURE Read*(VAR ch: CHAR);
VAR isUTF: BOOLEAN;
BEGIN ReadUTF8(ch, isUTF)
END Read;

(** Returns the elapsed number of timer ticks from Oberon startup. *)
PROCEDURE Time*(): LONGINT;
VAR t: LONGINT;
BEGIN
  t := Kernel.GetTimer();
  IF t - lastPoll >= 100 THEN  (* polpo: the interrupt keys reach also loops that only watch the clock *)
    lastPoll := t;
    IF x11 THEN PollX() ELSE PollTTY() END
  END;
  IF Linux0.break THEN Linux0.break := FALSE; HALT( 113) END;
  CheckPause;
  RETURN t (*MOD 80000000H MIPS compiler does not like this...*);
END  Time;

(** Restricts the extent of the mouse coordinates returned by Mouse. *)
PROCEDURE SetMouseLimits*(x, y, w, h: INTEGER);
BEGIN
END SetMouseLimits;

(** Return the state of the shift keys. *)
PROCEDURE KeyState*(VAR keys: SET);
BEGIN
  keys:= {};
  IF ODD(modState) THEN INCL(keys, SHIFT) END;
  IF ODD(modState DIV 4) THEN INCL(keys, CTRL) END;
  IF ODD(modState DIV 8) THEN INCL(keys, ALT) END
END KeyState;

(*
PROCEDURE *UnsafeBreak;
VAR note1, note2, note3: ARRAY 32 OF CHAR;
BEGIN
  note1 := "Warning: Interrupting a module";
  note2 := "may invalidate its invariants";
  note3 := "and make it unstable.";
  HALT(24)
END UnsafeBreak;
*)

PROCEDURE SwitchConHandler;
CONST VTRELDISP=5605H;
      VTAUTO=0;
      VTPROCESS=01H;
      VTACKACQ= 02H;
VAR res: LONGINT;
BEGIN
  IF switching THEN RETURN END;
  switching:= TRUE;
  IF onoberon THEN
    WriteString("switching to con");
    fdset:={};
    Display.SetClip( 0, 0, 0, 0);
    res:=Linux0.IOCtl0( kbdfd, KDSETMODE, 0);   (* text mode =0 *)
    res:=Linux0.IOCtl0( kbdfd, VTRELDISP, VTPROCESS);
    onoberon:=FALSE;
  ELSE
    WriteString("switching back to oberon");
    (* ack switch back, mmap framebuffer, restore framebuffer, grab mouse*)
    res:=Linux0.IOCtl0( kbdfd, KDSETMODE, 1);   (* graphics mode =1 *)
    res:=Linux0.IOCtl0( kbdfd, VTRELDISP, VTACKACQ);
    Put(0F7X, FALSE);  (* F7, redraw display *)
    Display.ResetClip;
    fdset:={kbdfd, mfd};
    onoberon:= TRUE;
  END;
  switching:= FALSE;
END SwitchConHandler;

PROCEDURE InitMouseFB;
CONST cmd=801F4520H;
VAR res, i, l: LONGINT; s: ARRAY 20 OF CHAR; c: CHAR;
BEGIN
  Kernel.GetConfig("OMEVENT", s);
  IF s="" THEN
    s:=ME;
    c:="0";
    REPEAT
      IF ORD(c)>ORD("9") THEN WriteErr("Can't open /dev/input/eventX"); Kernel.Shutdown( 1)END;
      s[16]:= c;
      mfd:=Linux0.Openat0( Linux0.ATFDCWD, SYSTEM.ADR(s), Linux0.ORDonly, 0);
      IF mfd<=0 THEN Kernel.WriteString( "Can't open "); Kernel.WriteString(s); Kernel.WriteHex( -mfd, 9); Kernel.WriteLn END;
      res:=Linux0.IOCtl0(mfd, cmd, SYSTEM.ADR(l));
      mfd:=Linux0.Close0(mfd);
      c:=CHR( ORD(c)+1);
    UNTIL (l DIV 2 MOD 4 =3);
  END;
  mfd:=Linux0.Openat0( Linux0.ATFDCWD, SYSTEM.ADR(s), Linux0.ORDonly, 0);
  IF mfd<=0 THEN Kernel.WriteString( "Can't open "); Kernel.WriteString(s); Kernel.WriteLn; Kernel.Shutdown( 1) END;
  iemouse:=s[11]#"m";  (* /dev/input/mouseX|mice *)
  IF iemouse THEN
    res:=Linux0.IOCtl0(mfd, cmd, SYSTEM.ADR(l));
    IF (l DIV 2 MOD 4 #3) THEN Kernel.WriteString( s); Kernel.WriteString(" not a mouse device."); Kernel.WriteLn; Kernel.Shutdown( 1) END;
  END;
END InitMouseFB;

PROCEDURE TTYtcSetAttr( VAR io: TermIOs);
CONST TCSETSFLUSH= 540EH;  (* MIPS: 5410H ?? ARM, X86: 5404H*)
VAR err: LONGINT;
BEGIN
  err:= Linux0.IOCtl0( kbdfd, Linux0.TCSETSF, SYSTEM.ADR( io));
  IF err#0 THEN WriteSH("Input.tcsetattr:", err) END;
END TTYtcSetAttr;

PROCEDURE TTYtcGetAttr( VAR io: TermIOs);
CONST TCGETS= 540DH;  (* MIPS: 540DH??; ARM, X86: 5401H *)
VAR err: LONGINT;
BEGIN
  err:= Linux0.IOCtl0( kbdfd, Linux0.TCGETS, SYSTEM.ADR( io));
  IF err#0 THEN WriteSH("Input.tcgetattr:", err) END;
END TTYtcGetAttr;

PROCEDURE InitKbdFB;
CONST (*x86, ARM: VMIN=6; MIPS: 4*)
  VTIME=5;
  ICANON= 2H;  ECHO= 8H; ISIG=1H; IEXTEN=8000H; IXON=400H; ICRNL=100H; OPOST=1H;
  VTGETMODE=5601H;
  VTSETMODE=5602H;
  KDGETMODE=4B3BH;
  KDSKBMODE= 4B45H;
TYPE   mode= RECORD mode, waitv: CHAR;
          relsig, acqsig: INTEGER;
          frsig: INTEGER
        END;
VAR kbdtermios: TermIOs; m: mode; res: LONGINT;
BEGIN
  onoberon:=TRUE;
  kbdfd:=Linux0.Openat0( Linux0.ATFDCWD, SYSTEM.ADR("/dev/tty"), Linux0.ORDWR, 0);
  IF kbdfd<0 THEN
    WriteErr("Can't open /dev/tty");
    Kernel.Shutdown(1)
  END;
  res:=Linux0.IOCtl0( kbdfd, KDSETMODE, 1);   (* graphics mode =1 *)
  TTYtcGetAttr( oldtermios);
  kbdtermios:=oldtermios;
  kbdtermios.clflags := kbdtermios.clflags - SYSTEM.VAL( SET, ICANON + ECHO + ISIG + IEXTEN );
  kbdtermios.ciflags := kbdtermios.ciflags - SYSTEM.VAL( SET, IXON + ICRNL );
  kbdtermios.coflags := kbdtermios.coflags - SYSTEM.VAL( SET, OPOST );
  kbdtermios.ccc[Linux0.VMIN] := 1X;
  kbdtermios.ccc[VTIME] := 0X;
  TTYtcSetAttr( kbdtermios);
  res:=Linux0.IOCtl0( kbdfd, VTGETMODE, SYSTEM.ADR( m));
  IF res#0 THEN WriteSH("Display.InitKbd: res= ", res) END;
(* console switching *)
  res:=Linux0.IOCtl0( kbdfd, KDSKBMODE, 3);  (* 0 raw , 1 xlate, 2 mediaraw, 3 unicode *)
  IF res#0 THEN WriteString("Display.InitKbdFB failed to set mode") END;
  m.mode:=1X;  (* was 1; VT_AUTO=0, VT_PROCESS=1; VT_ACKACQ=2 *)
  m.acqsig:= Linux0.SIGUSR1;
  m.relsig:= Linux0.SIGUSR2;
  res:= Linux0.IOCtl0( kbdfd, VTSETMODE, SYSTEM.ADR( m));
  res:= Linux0.SetSignal( Linux0.SIGUSR1, SwitchConHandler);
  res:= Linux0.SetSignal( Linux0.SIGUSR2, SwitchConHandler);
END InitKbdFB;

PROCEDURE CloseFB;
VAR res: LONGINT;
BEGIN
  res:=Linux0.IOCtl0( kbdfd, KDSETMODE, 0);    (* text mode *)
  TTYtcSetAttr( oldtermios);
  res:= Linux0.Close0( kbdfd);
  res:= Linux0.Close0( mfd);
END CloseFB;


PROCEDURE WriteStdout( s: ARRAY OF CHAR);
VAR i, res: LONGINT;
BEGIN
  i:=0;
  WHILE (i<LEN(s)) & (s[i]#0X) DO INC(i) END;
  IF i>0 THEN res:=Linux0.Write0(1, SYSTEM.ADR(s), i) END
END WriteStdout;

PROCEDURE WriteCSI( s: ARRAY OF CHAR);
VAR b: ARRAY 64 OF CHAR; i, j, res: LONGINT;
BEGIN
  b[0]:=1BX; b[1]:="["; i:=0; j:=2;
  WHILE (i<LEN(s)) & (s[i]#0X) & (j<LEN(b)-1) DO b[j]:=s[i]; INC(i); INC(j) END;
  res:=Linux0.Write0(1, SYSTEM.ADR(b), j)
END WriteCSI;

(** polpo: s[0..n-1] becomes the clipboard (Ctrl+C): sent to the terminal with OSC 52,
  xterm puts it on the clipboard of the system when it allows (disallowedWindowOps) *)
PROCEDURE SetClipboard*(VAR s: ARRAY OF CHAR; n: LONGINT);
CONST B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
VAR b: ARRAY 72 OF CHAR; tab: ARRAY 65 OF CHAR; i, j, k, v, res: LONGINT;
BEGIN
  IF n > LEN(s) THEN n := LEN(s) END;
  tab := B64;
  b[0] := 1BX; b[1] := "]"; b[2] := "5"; b[3] := "2"; b[4] := ";"; b[5] := "c"; b[6] := ";";
  res := Linux0.Write0(1, SYSTEM.ADR(b), 7);
  i := 0; j := 0;
  WHILE i < n DO
    v := ORD(s[i]) * 10000H; k := 1;
    IF i + 1 < n THEN INC(v, ORD(s[i+1]) * 100H); INC(k) END;
    IF i + 2 < n THEN INC(v, ORD(s[i+2])); INC(k) END;
    b[j] := tab[v DIV 40000H MOD 64]; b[j+1] := tab[v DIV 1000H MOD 64];
    IF k > 1 THEN b[j+2] := tab[v DIV 40H MOD 64] ELSE b[j+2] := "=" END;
    IF k > 2 THEN b[j+3] := tab[v MOD 64] ELSE b[j+3] := "=" END;
    INC(j, 4); INC(i, 3);
    IF j >= 64 THEN res := Linux0.Write0(1, SYSTEM.ADR(b), j); j := 0 END
  END;
  b[j] := 07X; res := Linux0.Write0(1, SYSTEM.ADR(b), j + 1)
END SetClipboard;

(** polpo: the clipboard of other programs comes from the terminal's own paste *)
PROCEDURE RequestClipboard*(): BOOLEAN;
BEGIN RETURN FALSE
END RequestClipboard;

PROCEDURE CloseTerm;
BEGIN
  TTYtcSetAttr( oldtermios);
  WriteCSI("?1016l"); WriteCSI("?1006l"); WriteCSI("?1003l"); WriteCSI("?1000l"); WriteCSI("?25h"); WriteCSI("0m")
END CloseTerm;

PROCEDURE Init;
VAR kbdtermios: TermIOs; bdata: ARRAY 64 OF CHAR;
CONST VTIME=5; ICANON=2H; ECHO=8H; ISIG=1H; IEXTEN=8000H; IXON=400H; ICRNL=100H; OPOST=1H;
BEGIN
  keywarn:= FALSE; err:= 0; mmbe:= FALSE; switching:= FALSE;
  x11:=FALSE; mfd:=-1; kbdfd:=0; dfd:=Display.InitX11();
  mouseX:=Display.Width DIV 2; mouseY:=Display.Height DIV 2; keyss:={};
  mouseSkip:=0; mouseMotionCount:=0;
  Kernel.GetConfig("SXL_MOUSE_SKIP", bdata);
  mouseSkip:=Str2Int(bdata, 0);
  IF mouseSkip<0 THEN mouseSkip:=0 END;
  fdset:={kbdfd};
  WriteCSI("?1003h");  (* xterm all-motion mouse reports *)
  WriteCSI("?1006h");  (* SGR mouse coordinates: ESC [ < b ; x ; y M/m *)
  WriteCSI("?1016h");  (* SGR-pixels: report pixel coordinates, not character cells *)

  TTYtcGetAttr( oldtermios);
  kbdtermios:=oldtermios;
  kbdtermios.clflags := kbdtermios.clflags - SYSTEM.VAL( SET, ICANON + ECHO + ISIG + IEXTEN );
  kbdtermios.ciflags := kbdtermios.ciflags - SYSTEM.VAL( SET, IXON + ICRNL );
  kbdtermios.coflags := kbdtermios.coflags - SYSTEM.VAL( SET, OPOST );
  kbdtermios.ccc[Linux0.VMIN] := 1X;
  kbdtermios.ccc[VTIME] := 0X;
  TTYtcSetAttr( kbdtermios);

  Kernel.Idle:=Idle;
  Kernel.InstallTermHandler( CloseTerm);
END Init;

BEGIN
  trace:=Kernel.trace="Input";
  CopyClip:=NIL; PasteClip:=NIL;
  Init;
END Input.

(** Remarks:

1. Keyboard character codes correspond to the ASCII character set.
Some other important codes are:

  F1, SETUP  0A4X
  F2, NEUTRALISE  0A5X
  F3, SCRL  0A6X  (used in Draw)
  F4, NOSCRL  0A7X  (used in Draw)
  UP ARROW  0C1X
  RIGHT ARROW  0C3X
  DOWN ARROW  0C2X
  LEFT ARROW  0C4X
  INSERT  0A0X

2. On some platforms, SetMouseLimits may not influence the physical movement
of the mouse cursor itself, only the magnitude of the coordinates returned by Mouse.
*)
