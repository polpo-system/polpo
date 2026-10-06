(* OBERON System 3, Release 2.3.

Copyright 1999 ETH Zrich Institute for Computer Systems, 
ETH Center, CH-8092 Zrich. e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon 
System 3 license contract. The full text can be downloaded from

	"ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/license.txt;A"

Under the license terms stated it is in particular (a) prohibited to modify
the interface of this module in any way that disagrees with the style
or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)

MODULE AsciiCoder;	(* polpo: the desktop commands; the coding is in AsciiCoder0 *)	(** portable *) (* Wolfgang Weck 14 Dec 93, compression due to Stefan Ludwig/ jm modified for System 3 *)
	
	IMPORT Oberon, Texts, Files, Display, AsciiCoder0;

	TYPE
		NameList = POINTER TO NameDesc;
		NameDesc = RECORD
			next: NameList;
			name: ARRAY 64 OF CHAR
		END;

	VAR
		w: Texts.Writer;

	PROCEDURE OpenViewer(name: ARRAY OF CHAR; text: Texts.Text);
	BEGIN
		Oberon.OpenText(name, text, Display.Width DIV 8 * 3 + 20, Display.Height DIV 2)
	END OpenViewer;

	PROCEDURE ReadFileNames(t: Texts.Text; beg, end: LONGINT; VAR names: NameList; VAR pos: LONGINT);
		VAR last, n: NameList; s: Texts.Scanner;
	BEGIN NEW(names); last := names; Texts.OpenScanner(s, t, beg); pos := beg; Texts.Scan(s);
		WHILE (pos < end) & ((s.class = Texts.String) OR (s.class = Texts.Name)) DO NEW(n); last.next := n; last := n;
			COPY(s.s, n.name);
			pos := Texts.Pos(s); Texts.Scan(s)
		END;
		last.next := NIL; names := names.next; pos := Texts.Pos(s)
	END ReadFileNames;

	PROCEDURE CodeFiles*;
		VAR pos, beg, end, time: LONGINT; compress: BOOLEAN; names, n: NameList;
			f, f1: Files.File; text: Texts.Text; s: Texts.Scanner; 
	BEGIN pos := Oberon.Par.pos; compress := FALSE;
		Texts.OpenScanner(s, Oberon.Par.text, pos); Texts.Scan(s);
		IF (s.line = 0) & (s.class = Texts.Char)  & (s.c = "%") THEN compress := TRUE; pos := Texts.Pos(s); Texts.Scan(s) END;
		IF (s.line = 0) & (s.class = Texts.Char)  & (s.c = "^") THEN Oberon.GetSelection(text, beg, end, time);
			IF time >= 0 THEN ReadFileNames(text, beg, end, names, time) ELSE names := NIL END
		ELSE ReadFileNames(Oberon.Par.text, pos, Oberon.Par.text.len, names, time)
		END;
		IF names # NIL THEN n := names; NEW(text); Texts.Open(text, "");
			Texts.WriteString(w, "AsciiCoder.CodeFiles"); Texts.WriteLn(w);
			REPEAT f := Files.Old(n.name); Texts.WriteString(w, n.name);
				IF f = NIL THEN Texts.WriteString(w, " not found"); n.name := ""
				ELSE Texts.WriteString(w, " coding"); Texts.Append(Oberon.Log, w.buf);
					IF compress THEN f1 := Files.New(""); AsciiCoder0.Compress(f, f1); f := f1 END;
					AsciiCoder0.Code(f, text)
				END;
				Texts.WriteLn(w); Texts.Append(Oberon.Log, w.buf); n := n.next
			UNTIL n = NIL;
			Texts.WriteString(w,"AsciiCoder.DecodeFiles ");
			IF compress THEN Texts.WriteString(w, "% ") END;
			REPEAT
				IF names.name # "" THEN Texts.WriteString(w, names.name); Texts.Write(w, " ") END;
				names := names.next
			UNTIL names = NIL;
			Texts.Write(w, "~"); Texts.WriteLn(w); Texts.WriteLn(w); Texts.Insert(text, 0, w.buf);
			Texts.WriteInt(w, text.len, 0); Texts.WriteString(w, " characters"); Texts.WriteLn(w);
			Texts.Append(Oberon.Log, w.buf);
			OpenViewer("AsciiCoder.CodeFiles", text)
		END
	END CodeFiles;

	PROCEDURE DecodeFiles*;
		VAR pos, beg, end, time: LONGINT; i, res: INTEGER; ch: CHAR; ok, compress: BOOLEAN;
			f, f1: Files.File; text: Texts.Text; s: Texts.Scanner; names: NameList; bakname: ARRAY 256 OF CHAR;
	BEGIN text := Oberon.Par.text; pos := Oberon.Par.pos; compress := FALSE;
		Texts.OpenScanner(s, text, pos); Texts.Scan(s);
		IF (s.line = 0) & (s.class = Texts.Char)  & (s.c = "%") THEN compress := TRUE; pos := Texts.Pos(s); Texts.Scan(s) END;
		IF (s.line = 0) & (s.class = Texts.Char)  & (s.c = "@") THEN Oberon.GetSelection(text, beg, end, time);
			IF time >= 0 THEN ReadFileNames(text, beg, end, names, pos) ELSE names := NIL END
		ELSE ReadFileNames(text, pos, text.len, names, pos)
		END;
		Texts.WriteString(w, "AsciiCoder.DecodeFiles"); Texts.WriteLn(w); ok := TRUE;
		WHILE (names # NIL) & ok DO f := Files.New(names.name);
			Texts.WriteString(w, names.name); Texts.WriteString(w, " decoding"); Texts.Append(Oberon.Log, w.buf);
			i := 0; ch := names.name[0];
			WHILE ch # 0X DO bakname[i] := ch; INC(i); ch := names.name[i] END;
			bakname[i] := "."; bakname[i + 1] := "B"; bakname[i + 2] := "a"; bakname[i + 3] := "k"; bakname[i + 4] := 0X;
			Files.Rename(names.name, bakname, res); AsciiCoder0.Decode(text, pos, f, ok);
			IF ok THEN
				IF compress THEN f1 := Files.New(names.name); AsciiCoder0.Expand(f, f1); f := f1 END;
				Files.Register(f)
			ELSE Texts.WriteString(w, " error.")
			END;
			Texts.WriteLn(w); Texts.Append(Oberon.Log, w.buf); names := names.next
		END
	END DecodeFiles;
	
	PROCEDURE CodeText*;
		VAR beg, end, time: LONGINT; compress: BOOLEAN;
			f, f1: Files.File; t, text: Texts.Text; s: Texts.Scanner; len: LONGINT;
	BEGIN compress := FALSE;
		Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(s);
		IF (s.line = 0) & (s.class = Texts.Char)  & (s.c = "%") THEN compress := TRUE; Texts.Scan(s) END;
		IF (s.line = 0) & (s.class = Texts.Char) THEN t := NIL;
			IF s.c = "*" THEN t := Oberon.MarkedText()
			ELSIF s.c = "@" THEN Oberon.GetSelection(text, beg, end, time);
				IF time >= 0 THEN NEW(t); Texts.Open(t, ""); Texts.Save(text, beg, end, w.buf); Texts.Append(t, w.buf) END
			END;
			IF t # NIL THEN f := Files.New(""); (*Files.Set(r, f, 0); 
				Files.Write(r, 0F0X); Files.Write(r, 01X); Texts.Store(r, t); *)
				Texts.Store(t, f, 0, len);
				NEW(text); Texts.Open(text, "");
				Texts.WriteString(w, "AsciiCoder.DecodeText");
				IF compress THEN Texts.WriteString(w, " %") END;
				Texts.WriteLn(w); Texts.WriteLn(w); Texts.Append(text, w.buf);
				IF compress THEN f1 := Files.New(""); AsciiCoder0.Compress(f, f1); f := f1 END;
				AsciiCoder0.Code(f, text); OpenViewer("AsciiCoder.CodeText", text);
				Texts.WriteString(w, "AsciiCoder.CodeText "); Texts.WriteInt(w, text.len, 0);
				Texts.WriteString(w, " characters"); Texts.WriteLn(w); Texts.Append(Oberon.Log, w.buf)
			END
		END
	END CodeText;

	PROCEDURE DecodeText*;
		VAR pos, beg, end, time: LONGINT; ok, compress: BOOLEAN;
			f, f1: Files.File; text: Texts.Text; s: Texts.Scanner; len: LONGINT;
	BEGIN compress := FALSE; pos := Oberon.Par.pos; f := Files.New("");
		Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(s);
		IF (s.line = 0) & (s.class = Texts.Char)  & (s.c = "%") THEN compress := TRUE; pos := Texts.Pos(s); Texts.Scan(s) END;
		IF (s.line = 0) & (s.class = Texts.Char)  & (s.c = "@") THEN Oberon.GetSelection(text, beg, end, time);
			IF time >= 0 THEN AsciiCoder0.Decode(text, beg, f, ok) ELSE ok := FALSE END
		ELSE AsciiCoder0.Decode(Oberon.Par.text, pos, f, ok)
		END;
		IF ok THEN
			IF compress THEN f1 := Files.New(""); AsciiCoder0.Expand(f, f1); f := f1 END;
			NEW(text); Texts.Open(text, ""); (*Files.Set(r, f, 2); Texts.Load(r, text);*) Texts.Load(text, f, 1, len);
			OpenViewer("AsciiCoder.DecodeText", text)
		ELSE Texts.WriteString(w, "AsciiCoder.DecodeText error."); Texts.WriteLn(w); Texts.Append(Oberon.Log, w.buf)
		END
	END DecodeText;

BEGIN Texts.OpenWriter(w)
END AsciiCoder.

AsciiCoder.CodeText *
AsciiCoder.DecodeText
