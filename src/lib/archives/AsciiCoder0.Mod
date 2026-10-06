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

MODULE AsciiCoder0;	(** portable *)
(* polpo: the coding of AsciiCoder (Compress, Expand, Code, Decode) on the modules shared by the
   console and the desktop; the desktop commands are in AsciiCoder, the console ones in asciicoder *)

	IMPORT Texts := Texts0, Files;

	CONST
		Base = 48; StopBase = 35;
		N = 16384;

	VAR
		w: Texts.Writer;
		table: ARRAY N OF CHAR;	(* hash table for compression *)

	PROCEDURE Compress*(src, dest: Files.File);	(* due to Stefan Ludwig *)
		VAR hash, byte, bit, i: LONGINT; ch: CHAR; from, to: Files.Rider;
	BEGIN
		i := 0; REPEAT table[i] := 0X; INC(i) UNTIL i = N;
		Files.Set(from, src, 0); Files.Set(to, dest, 0);
		i := Files.Length(src); Files.WriteNum(to, i);
		IF i > 0 THEN
			hash := 0; bit := 0; byte := 0;
			REPEAT
				Files.Read(from, ch);
				IF table[hash] = ch THEN	(* 0 bit for correct prediction *)
					INC(bit); IF bit = 8 THEN Files.Write(to, CHR(byte)); byte := 0; bit := 0 END
				ELSE	(* Incorrect prediction -> 1'xxxx'xxxx bits where x = ch[0..7] *)
					table[hash] := ch; INC(byte, ASH(1, bit)); INC(bit);
					IF bit = 8 THEN Files.Write(to, CHR(byte)); Files.Write(to, ch);  byte := 0; bit := 0
					ELSE Files.Write(to, CHR(byte+ASH(ORD(ch), bit) MOD 256)); byte := ASH(ORD(ch), bit) DIV 256
					END
				END;
				DEC(i); hash := (16*hash+ORD(ch)) MOD N	(* hash value *)
			UNTIL i = 0;
			IF bit # 0 THEN Files.Write(to, CHR(byte)) END	(* write last byte *)
		END
	END Compress;

	PROCEDURE Expand*(src, dest: Files.File);	(* due to Stefan Ludwig *)
		VAR hash, val, byte, bit, i: LONGINT; ch: CHAR; from, to: Files.Rider;
	BEGIN
		i := 0; REPEAT table[i] := 0X; INC(i) UNTIL i = N;
		Files.Set(from, src, 0); Files.Set(to, dest, 0);
		Files.ReadNum(from, i);
		IF i > 0 THEN
			Files.Read(from, ch); val := ORD(ch); bit := 0; hash := 0;
			REPEAT
				INC(bit);
				IF ODD(val) THEN	(* Incorrect prediction -> 1'xxxx'xxxx *)
					Files.Read(from, ch);
					IF bit = 8 THEN byte := ORD(ch)
					ELSE byte := val DIV 2 + ASH(ORD(ch), 8-bit) MOD 256; val := ASH(ORD(ch), -bit)
					END;
					table[hash] := CHR(byte)
				ELSE byte := ORD(table[hash]); val := val DIV 2	(* correct prediction *)
				END;
				hash := (16*hash+byte) MOD N; Files.Write(to, CHR(byte)); DEC(i);
				IF bit = 8 THEN Files.Read(from, ch); val := ORD(ch); bit := 0 END
			UNTIL i = 0
		END
	END Expand;

	PROCEDURE Code*(from: Files.File; to: Texts.Text);
		VAR byte, rest, div, factor, packs: INTEGER; ch: CHAR; r: Files.Rider;
	BEGIN Files.Set(r, from, 0); Files.Read(r, ch); byte := ORD(ch); rest := 0; div := 64; factor  := 1; packs := 0;
		WHILE ~r.eof DO Texts.Write(w, CHR(Base + rest + (byte MOD div) * factor)); rest := byte DIV div;
			IF div = 4 THEN Texts.Write(w, CHR(Base + rest));
				rest := 0; div := 64; factor  := 1; INC(packs);
				IF packs = 19 THEN Texts.WriteLn(w); packs := 0 END
			ELSE factor := factor * 4; div := div DIV 4
			END;
			Files.Read(r, ch); byte := ORD(ch)
		END;
		IF div = 64 THEN Texts.Write(w, CHR(StopBase))
		ELSIF div = 16 THEN Texts.Write(w, CHR(Base + rest)); Texts.Write(w, CHR(StopBase + 1))
		ELSIF div = 4 THEN Texts.Write(w, CHR(Base + rest)); Texts.Write(w, CHR(StopBase + 2))
		END;
		Texts.WriteLn(w); Texts.Append(to, w.buf)
	END Code;

	PROCEDURE Decode*(from: Texts.Text; VAR pos: LONGINT; to: Files.File; VAR ok: BOOLEAN);
		VAR rest, div, factor, byte: INTEGER; ch: CHAR; r: Texts.Reader; w: Files.Rider;
	BEGIN Texts.OpenReader(r, from, pos); Files.Set(w, to, 0); factor := 1; div := 256; rest := 0;
		REPEAT Texts.Read(r, ch) UNTIL (ch > " ") OR r.eot;
		WHILE ~r.eot & (ch >= CHR(Base)) & (ch < CHR(Base + 64)) DO byte := ORD(ch) - Base;
			IF factor # 1 THEN Files.Write(w, CHR(rest + (byte MOD div) * factor));
				rest := byte DIV div; div := div * 4; factor := factor DIV 4
			ELSE rest := byte; div := 4; factor := 64
			END;
			REPEAT Texts.Read(r, ch) UNTIL (ch > " ") OR r.eot
		END;
		byte := ORD(ch) - StopBase;
		ok := (byte = 0) & (div = 256) OR (byte = 1) & (div = 16) OR (byte = 2) & (div = 64) & (rest = 0);
		pos := Texts.Pos(r)
	END Decode;

BEGIN Texts.OpenWriter(w)
END AsciiCoder0.
