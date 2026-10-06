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

MODULE Compress0;	(* polpo: the archives of Compress (.Arc) for the console and the desktop; the commands
	are in arc (console) *)	(** portable *) (* (c) ejz, first version: 14.1.92, this version: 8.1.98 / 1.1.98 gs *)
	IMPORT Files, Modules, Texts := Texts0, Oberon := Oberon0;
				
	CONST
		BufferSize = 4*1024;
		IndexBitCount = 12;
		LengthBitCount = 4;
		WindowSize = 4096;
		RawLookAheadSize = 16;
		BreakEven = 1;
		LookAheadSize = RawLookAheadSize + BreakEven;
		TreeRoot = WindowSize;
		EndOfStream = 0;
		Unused = 0;
		Temp = "Compress.Temp";
		err1 = "Error in archive";
		err2 = " not found";
		err3 = "encryption key needed";
		xx = 32768;
		Menu = 0;
		Cmd = 1;
		EOFName = "~ ";
		Done *= 0;
		ArchiveNotFound *= 1;
		ErrorInArchive *= 2;
		EntryNotFound *= 3;
		ArchiveExists *= 4;
		FileError *= 5;
		KeyNeeded* = 6;
		DocumentsId = 07F7H;  (* Documents.Id: the bytes 0F7X, 07X *)
		DocId0 = 0F7X;
		DocId1 = 07X;
				
		(* extensions *)
		encryption* = 0;

	TYPE
		Node = RECORD
			parent, smallerChild, largerChild: INTEGER
		END;
		Name *= ARRAY 32 OF CHAR;
		Header* = RECORD
			name*: Name;
			length*, check: LONGINT;
			date*, time*: LONGINT;
			ratio*: REAL;
			extensions*: SET (* encryption *)
		END;
		List = POINTER TO ListDesc;
		ListDesc = RECORD
			name: ARRAY 64 OF CHAR;
			next: List
		END;
		HeaderList = POINTER TO HeaderListDesc;
		HeaderListDesc = RECORD
			header: Header;
			next: HeaderList
		END;
		EnumProc* = PROCEDURE (h: Header; VAR stop: BOOLEAN);
		CryptProc* = PROCEDURE (VAR Rin: Files.Rider; nIn: LONGINT; VAR Rout: Files.Rider; key: ARRAY OF CHAR; VAR res: INTEGER);

	VAR
		W: Texts.Writer;
		Buffer: ARRAY BufferSize OF CHAR;
		BufferPtr, CurBitNr, Len, maxLen: LONGINT;
		CurByte: LONGINT;
		Window: ARRAY WindowSize+RawLookAheadSize+1 OF CHAR;
		Tree: ARRAY WindowSize+1 OF Node;
		Err, verbose, sorted: BOOLEAN;
		cmdSource, help: INTEGER;
		headerList: HeaderList;
		Decrypt*, Encrypt*: CryptProc;
		curKey: ARRAY 64 OF CHAR;

	PROCEDURE ReadHeader(VAR R: Files.Rider; VAR h: Header; VAR err: BOOLEAN);
		VAR
			chk, pos: LONGINT;
			i: INTEGER;
	BEGIN
		pos := Files.Pos(R);
		Files.ReadBytes(R, h.name, 32);
		IF (h.name[0] = DocId0) & (h.name[1] = DocId1) THEN
			(* new doc-format skip header *)
			Files.Set(R, Files.Base(R), pos);
			Files.ReadInt(R, i);
			Files.ReadString(R, h.name);
			Files.ReadInt(R, i);
			Files.ReadInt(R, i);
			Files.ReadInt(R, i);
			Files.ReadInt(R, i);
			ReadHeader(R, h, err)
		ELSE
			IF R.eof & (R.res = 32) THEN
				h.name := EOFName;
				err := FALSE;
				RETURN
			END;
			Files.ReadLInt(R, h.length);
			Files.ReadLInt(R, h.check);
			Files.ReadLInt(R, h.date);
			Files.ReadLInt(R, h.time);
			Files.ReadReal(R, h.ratio);
			IF h.length < 0 THEN
				Files.ReadSet(R, h.extensions);
				h.length := -h.length
			ELSE
				h.extensions := {} 
			END;
			IF (h.ratio > 0.0) & (h.ratio < 1000000.0) THEN
				pos := 0; chk := 0;
				WHILE pos < 32 DO
					chk := chk+ORD(h.name[pos]);
					INC(pos)
				END;
				h.name[31] := 0X;
				chk := chk+h.length+ENTIER(h.ratio)+(h.time MOD xx)+(h.date MOD xx);
				err := chk # h.check
			ELSE
				err := TRUE
			END
		END
	END ReadHeader;
	
	PROCEDURE WriteHeader(VAR R: Files.Rider; VAR h: Header);
		VAR i: LONGINT;
	BEGIN
		IF curKey # "" THEN
			INCL(h.extensions, encryption)
		END;
		h.check := 0;
		i := 0;
		WHILE (i < 32) & (h.name[i] # 0X) DO
			h.check := h.check + ORD(h.name[i]);
			INC(i)
		END;
		WHILE i < 32 DO
			h.name[i] := 0X; INC(i)
		END;
		Oberon.GetClock(h.time, h.date);
		h.check := h.check+h.length+(h.time MOD xx)+(h.date MOD xx)+ENTIER(h.ratio);
		Files.WriteBytes(R, h.name, 32);
		IF h.extensions # {} THEN
			Files.WriteLInt(R, -h.length)
		ELSE
			Files.WriteLInt(R, h.length)
		END;
		Files.WriteLInt(R, h.check);
		Files.WriteLInt(R, h.date);
		Files.WriteLInt(R, h.time);
		Files.WriteReal(R, h.ratio);
		IF h.extensions # {} THEN
			Files.WriteSet(R, h.extensions)
		END
	END WriteHeader;

	PROCEDURE CopyFrom(VAR Ri, Ro: Files.Rider; len: LONGINT);
		VAR i: LONGINT;
	BEGIN
		Files.ReadBytes(Ri, Buffer, BufferSize);
		i := BufferSize;
		WHILE i <= len DO
			Files.WriteBytes(Ro, Buffer, BufferSize);
			Files.ReadBytes(Ri, Buffer, BufferSize);
			INC(i, BufferSize)
		END;
		Files.WriteBytes(Ro, Buffer, len MOD BufferSize)
	END CopyFrom;

	PROCEDURE CopyTo(VAR Ri, Ro: Files.Rider);
	BEGIN
		Files.ReadBytes(Ri, Buffer, BufferSize);
		WHILE ~Ri.eof DO
			Files.WriteBytes(Ro, Buffer, BufferSize);
			Files.ReadBytes(Ri, Buffer, BufferSize)
		END;
		Files.WriteBytes(Ro, Buffer, BufferSize-Ri.res)
	END CopyTo;

	PROCEDURE FlushBits(VAR R: Files.Rider);
	BEGIN
		IF CurBitNr # 7 THEN
			Buffer[BufferPtr] := CHR(CurByte);
			INC(BufferPtr)
		END;
		IF BufferPtr > 0 THEN
			Files.WriteBytes(R, Buffer, BufferPtr);
			INC(Len, BufferPtr)
		END
	END FlushBits;

	PROCEDURE InputBit(VAR R: Files.Rider): LONGINT;
		VAR h: LONGINT;
	BEGIN
		IF CurBitNr = 7 THEN
			IF BufferPtr = BufferSize THEN
				Files.ReadBytes(R, Buffer, BufferSize);
				INC(Len, BufferSize-R.res);
				IF Len >= (maxLen+BufferSize) THEN Err := TRUE END;
				BufferPtr := 0
			END;
			CurByte := ORD(Buffer[BufferPtr]);
			INC(BufferPtr)
		END;
		h := ASH(CurByte, -CurBitNr) MOD 2;
		DEC(CurBitNr);
		IF CurBitNr < 0 THEN CurBitNr := 7 END;
		RETURN h
	END InputBit;

	PROCEDURE InputBits(VAR R: Files.Rider; count: LONGINT): LONGINT;
		VAR i, h: LONGINT;
	BEGIN
		h := 0;
		i := count-1;
		WHILE i >= 0 DO
			IF CurBitNr = 7 THEN
				IF BufferPtr = BufferSize THEN
					Files.ReadBytes(R, Buffer, BufferSize);
					INC(Len, BufferSize-R.res);
					IF Len >= (maxLen+BufferSize) THEN Err := TRUE END;
					BufferPtr := 0
				END;
				CurByte := ORD(Buffer[BufferPtr]);
				INC(BufferPtr)
			END;
			IF ASH(CurByte, -CurBitNr) MOD 2 = 1 THEN
				h := h+ASH(1, i)
			END;
			DEC(CurBitNr);
			IF CurBitNr < 0 THEN CurBitNr := 7 END;
			DEC(i)
		END;
		RETURN h
	END InputBits;

	PROCEDURE OutputBit(VAR R: Files.Rider; bit: LONGINT);
	BEGIN
		IF bit = 1 THEN
			CurByte := CurByte+ASH(1, CurBitNr)
		END;
		DEC(CurBitNr);
		IF CurBitNr < 0 THEN
			Buffer[BufferPtr] := CHR(CurByte);
			INC(BufferPtr);
			IF BufferPtr = BufferSize THEN
				Files.WriteBytes(R,  Buffer, BufferSize);
				INC(Len, BufferSize);
				BufferPtr := 0
			END;
			CurBitNr := 7;
			CurByte := 0
		END
	END OutputBit;

	PROCEDURE OutputBits(VAR R: Files.Rider; bits, count: LONGINT);
		VAR i, h: LONGINT;
	BEGIN
		h := bits;
		i := count-1;
		WHILE i >= 0 DO
			IF ASH(h, -i) MOD 2 = 1 THEN
				CurByte := CurByte+ASH(1, CurBitNr)
			END;
			DEC(CurBitNr);
			IF CurBitNr < 0 THEN
				Buffer[BufferPtr] := CHR(CurByte);
				INC(BufferPtr);
				IF BufferPtr = BufferSize THEN
					Files.WriteBytes(R, Buffer, BufferSize);
					INC(Len, BufferSize);
					BufferPtr := 0
				END;
				CurBitNr := 7;
				CurByte := 0
			END;
			DEC(i)
		END
	END OutputBits;

	PROCEDURE Init();
		VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE i < WindowSize DO
			Tree[i].parent := Unused;
			Tree[i].smallerChild := Unused;
			Tree[i].largerChild := Unused;
			Window[i] := CHR(0);
			INC(i)
		END;
		Tree[i].parent := Unused;
		Tree[i].smallerChild := Unused;
		Tree[i].largerChild := Unused;
		WHILE i < WindowSize+RawLookAheadSize+1 DO
			Window[i] := CHR(0);
			INC(i)
		END
	END Init;

	PROCEDURE InitTree(r: INTEGER);
	BEGIN
		Tree[TreeRoot].largerChild := r;
		Tree[r].parent := TreeRoot;
		Tree[r].largerChild := Unused;
		Tree[r].smallerChild := Unused
	END InitTree;

	PROCEDURE ContractNode(oldNode, newNode: INTEGER);
	BEGIN
		help := Tree[oldNode].parent;
		Tree[newNode].parent := help;
		help := Tree[oldNode].parent;
		IF Tree[help].largerChild = oldNode THEN
			Tree[help].largerChild := newNode
		ELSE
			Tree[help].smallerChild := newNode
		END;
		Tree[oldNode].parent := Unused
	END ContractNode;

	PROCEDURE ReplaceNode(oldNode, newNode: INTEGER);
		VAR parent: INTEGER;
	BEGIN
		parent := Tree[oldNode].parent;
		IF Tree[parent].smallerChild = oldNode THEN
			Tree[parent].smallerChild := newNode
		ELSE
			Tree[parent].largerChild := newNode
		END;
		Tree[newNode] := Tree[oldNode];
		help := Tree[newNode].smallerChild;
		Tree[help].parent := newNode;
		help := Tree[newNode].largerChild;
		Tree[help].parent := newNode;
		Tree[oldNode].parent := Unused
	END ReplaceNode;

	PROCEDURE FindNextNode(node: INTEGER): INTEGER;
		VAR next: INTEGER;
	BEGIN
		next := Tree[node].smallerChild;
		WHILE Tree[next].largerChild # Unused DO
			next := Tree[next].largerChild
		END;
		RETURN next
	END FindNextNode;
	
	PROCEDURE DeleteString(p: INTEGER);
		VAR replacement: INTEGER;
	BEGIN
		IF Tree[p].parent = Unused THEN
			RETURN
		END;
		IF Tree[p].largerChild = Unused THEN
			ContractNode(p, Tree[p].smallerChild)
		ELSIF Tree[p].smallerChild = Unused THEN
			ContractNode(p, Tree[p].largerChild)
		ELSE
			replacement := FindNextNode(p);
			DeleteString(replacement);
			ReplaceNode(p, replacement)
		END
	END DeleteString;

	PROCEDURE AddString(newNode: INTEGER; VAR matchPosition: INTEGER): INTEGER;
		VAR i, testNode, delta, matchLength, child: INTEGER;
	BEGIN
		IF newNode = EndOfStream THEN
			RETURN 0
		END;
		testNode := Tree[TreeRoot].largerChild;
		matchLength := 0;
		LOOP
			i := 0;
			delta := 0;
			WHILE (i < LookAheadSize) & (delta = 0) DO
				delta := ORD(Window[newNode+i]) - ORD(Window[testNode+i]);
				INC(i)
			END;
			IF delta # 0 THEN DEC(i) END;
			IF i >= matchLength THEN
				matchLength := i;
				matchPosition := testNode;
				IF matchLength >= LookAheadSize THEN
					ReplaceNode(testNode, newNode);
					RETURN matchLength
				END;
			END;
			IF delta >= 0 THEN
				child := Tree[testNode].largerChild
			ELSE
				child := Tree[testNode].smallerChild
			END;
			IF child = Unused THEN
				IF delta >= 0 THEN
					Tree[testNode].largerChild := newNode
				ELSE
					Tree[testNode].smallerChild := newNode
				END;
				Tree[newNode].parent := testNode;
				Tree[newNode].largerChild := Unused;
				Tree[newNode].smallerChild := Unused;
				RETURN matchLength
			END;
			testNode := child
		END
	END AddString;

	PROCEDURE Compress(VAR Input, Output: Files.Rider; maxbytes: LONGINT);
		VAR
			i, lookAheadBytes, currentPosition, replaceCount, matchLength, matchPosition: INTEGER;
			ch: CHAR;
			bytesread: LONGINT;
	BEGIN
		Init();
		bytesread := 0;
		currentPosition := 1;
		i := 0;
		WHILE (i < LookAheadSize) & ~Input.eof & (bytesread < maxbytes) DO
			Files.Read(Input, ch);
			INC(bytesread);
			Window[currentPosition+i] := ch;
			IF currentPosition+i < RawLookAheadSize+1 THEN
				Window[currentPosition+i+WindowSize-1] := ch
			END;
			INC(i)
		END;
		IF Input.eof OR (bytesread >= maxbytes) THEN DEC(i) END;
		lookAheadBytes := i;
		InitTree(currentPosition);
		matchLength := 0;
		matchPosition := 0;
		WHILE lookAheadBytes > 0 DO
			IF matchLength > lookAheadBytes THEN
				matchLength := lookAheadBytes
			END;
			IF matchLength <= BreakEven THEN
				replaceCount := 1;
				OutputBit(Output, 1);
				OutputBits(Output, ORD(Window[currentPosition]), 8)
			ELSE
				OutputBit(Output, 0);
				OutputBits(Output, matchPosition, IndexBitCount);
				OutputBits(Output, matchLength-(BreakEven+1), LengthBitCount);
				replaceCount := matchLength
			END;
			i := 0;
			WHILE i < replaceCount DO
				DeleteString((currentPosition+LookAheadSize) MOD (WindowSize-1));
				Files.Read(Input, ch);
				INC(bytesread);
				IF Input.eof OR (bytesread >= maxbytes) THEN
					DEC(lookAheadBytes)
				ELSE
					Window[currentPosition+LookAheadSize] := ch;
					Window[(currentPosition+LookAheadSize) MOD (WindowSize-1)] := ch
				END;
				currentPosition := (currentPosition+1) MOD (WindowSize-1);
				IF lookAheadBytes # 0 THEN
					matchLength := AddString(currentPosition, matchPosition)
				END;
				INC(i)
			END
		END;
		OutputBit(Output, 0);
		OutputBits(Output, EndOfStream, IndexBitCount)
	END Compress;

	PROCEDURE Expand(VAR Input, Output: Files.Rider);
		VAR
			i, currentPosition, matchLength, matchPosition: INTEGER;
			ch: CHAR;
	BEGIN
		Err := FALSE;
		Init;
		currentPosition := 1;
		LOOP
			IF InputBit(Input) # 0 THEN
				ch := CHR(InputBits(Input, 8));
				Files.Write(Output, ch);
				Window[currentPosition] := ch;
				IF currentPosition < RawLookAheadSize+1 THEN
					Window[currentPosition+WindowSize-1] := ch
				END;
				currentPosition := (currentPosition+1) MOD (WindowSize-1)
			ELSE
				matchPosition := SHORT(InputBits(Input, IndexBitCount));
				IF matchPosition = EndOfStream THEN EXIT END;
				matchLength := SHORT(InputBits(Input, LengthBitCount));
				INC(matchLength, BreakEven);
				i := 0;
				WHILE i <= matchLength DO
					ch := Window[matchPosition+i];
					Files.Write(Output, ch);
					Window[currentPosition] := ch;
					IF currentPosition < RawLookAheadSize+1 THEN
						Window[currentPosition+WindowSize-1] := ch;
					END;
					currentPosition := (currentPosition+1) MOD (WindowSize-1);
					INC(i)
				END
			END;
			IF Err THEN RETURN END
		END
	END Expand;

(* Compress len Bytes form Ri to Ro. *)
	PROCEDURE CopyToArc(VAR Ri, Ro: Files.Rider; len: LONGINT; VAR h: Header);
		VAR
			F: Files.File;
			R: Files.Rider;
			len0: LONGINT;
			res: INTEGER;
	BEGIN
		res := Done;
		len0 := len; INC(len); Len := 0;
		BufferPtr := 0; CurBitNr := 7; CurByte := 0;
		IF encryption IN h.extensions THEN
			F := Files.New(""); Files.Set(R, F, 0);
			Compress(Ri, R, len);
			FlushBits(R); Files.Set(R, F, 0);
			len := Len; Len := Files.Pos(Ro);
			Encrypt(R, len, Ro, curKey, res); ASSERT(res = Done);
			Len := Files.Pos(Ro)-Len
		ELSE
			Compress(Ri, Ro, len);
			FlushBits(Ro)
		END;
		IF len0 < 1 THEN
			len0 := 1
		END;
		h.length := Len; h.ratio := 100*Len/len0
	END CopyToArc;

(* Expand a maximum of len Bytes from Ri to Ro.
	res:
		Done
		ErrorInArchive: error in compressed data *)
	PROCEDURE CopyFromArc(VAR Ri, Ro: Files.Rider; VAR h: Header; VAR res: INTEGER);
		VAR
			F: Files.File;
			R: Files.Rider;
	BEGIN
		res := Done; Len := 0;
		BufferPtr := BufferSize; CurBitNr := 7; CurByte := 0;
		IF encryption IN h.extensions THEN
			IF (Decrypt # NIL) & (curKey # "") THEN
				F := Files.New(""); Files.Set(R, F, 0);
				Decrypt(Ri, h.length, R, curKey, res); ASSERT(res = Done);
				maxLen := Files.Length(F); Files.Set(R, F, 0);
				Expand(R, Ro);
				Err := Err OR ((Len MOD BufferSize) # BufferPtr)
			ELSE
				Texts.WriteString(W, err3);
				Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
				res := KeyNeeded
			END
		ELSE
			maxLen := h.length;
			Expand(Ri, Ro)
		END;
		IF Err THEN
			res := ErrorInArchive
		END
	END CopyFromArc;




	PROCEDURE StringLen(str: ARRAY OF CHAR): INTEGER;
		VAR i: INTEGER;
	BEGIN
		i := 0;
		WHILE (i < LEN(str)) & (str[i] # CHR(0)) DO
			INC(i)
		END;
		RETURN i
	END StringLen;

	PROCEDURE Remove(VAR nameList: List; VAR name: Name);
		VAR cur, prev: List;
	BEGIN
		cur := nameList.next;
		prev := nameList;
		WHILE cur # NIL DO
			IF cur.name = name THEN
				prev.next := cur.next;
				RETURN
			ELSE
				prev := cur
			END;
			cur := cur.next
		END
	END Remove;

	PROCEDURE Search(nameList: List; VAR name: ARRAY OF CHAR): List;
	BEGIN
		WHILE nameList # NIL DO
			IF nameList.name = name THEN RETURN nameList END;
			nameList := nameList.next
		END;
		RETURN NIL
	END Search;

	PROCEDURE ClearCrypt*();
	BEGIN
		Decrypt := NIL; Encrypt := NIL; curKey := ""
	END ClearCrypt;

	PROCEDURE InstallCrypt*(install, key: ARRAY OF CHAR);
		VAR
			mod: Modules.Module;
			cmd: Modules.Command;
			i, j: LONGINT;
	BEGIN
		ClearCrypt(); COPY(key, curKey);
		i := 0;
		WHILE (install[i] # 0X) & (install[i] # ".") DO
			INC(i)
		END;
		IF install[i] = "." THEN
			install[i] := 0X; INC(i);
			mod := Modules.ThisMod(install);
			IF mod # NIL THEN
				j := 0;
				WHILE install[i] # 0X DO
					install[j] := install[i]; INC(i); INC(j)
				END;
				install[j] := 0X;
				cmd := Modules.ThisCommand(mod, install);
				IF cmd # NIL THEN
					cmd()
				END
			END
		END;
		ASSERT((Decrypt # NIL) & (Encrypt # NIL))
	END InstallCrypt;


	PROCEDURE Trimm(VAR name: ARRAY OF CHAR);
		VAR
			l, i, j: LONGINT;
			back: Name;
			ch: CHAR;
	BEGIN
		l := LEN(name);
		j := -1;
		i := 0;
		WHILE (i < l) & (name[i] # 0X) DO
			ch := name[i];
			IF (ch = "/") OR (ch = "\") THEN
				j := i
			END;
			INC(i)
		END;
		IF j >= 0 THEN
			COPY(name, back);
			j := j+1;
			i := 0;
			WHILE (j < l) & (back[j] # 0X) DO
				name[i] := back[j];
				INC(i);
				INC(j)
			END;
			name[i] := 0X
		END
	END Trimm;

	PROCEDURE NextName(VAR name: ARRAY OF CHAR);
		VAR
			i, l: LONGINT;
			ch: CHAR;
	BEGIN
		l := LEN(name);
		i := 0;
		WHILE (i < l) & (name[i] # 0X) DO
			INC(i)
		END;
		IF i >= l THEN
			name[l-1] := CHR(ORD(name[l-1])+1)
		ELSE
			ch := name[i-1];
			IF (ch >= "0") & (ch <= "8") THEN
				name[i-1] := CHR(ORD(name[i-1])+1)
			ELSE
				name[i] := "0";
				IF (i+1) < l THEN
					name[i+1] := 0X
				END
			END
		END
	END NextName;

	PROCEDURE *InsertHeadSort(h: Header; VAR stop: BOOLEAN);
	VAR
		newElem,prevElem,curElem: HeaderList;
	BEGIN
		NEW(newElem); newElem.header:= h;
		prevElem:= NIL; curElem:= headerList;
		WHILE (curElem # NIL) & (curElem.header.name < h.name) DO
			prevElem:= curElem; curElem:= curElem.next;
		END;
		newElem.next:= curElem;
		IF (prevElem = NIL) THEN headerList:= newElem; ELSE prevElem.next:= newElem; END;
	END InsertHeadSort;

(** Enumerate all entries in the archive (archive). Stop if stop (in enumProc) is set or if at end of archive.
		res:
			Done
			ArchiveNotFound: archive-file not found
			ErrorInArchive: internal error in archive-file *)
	PROCEDURE Enumerate*(archive: ARRAY OF CHAR; enumProc: EnumProc; sorted: BOOLEAN; VAR res: INTEGER);
		VAR
			ArcF: Files.File;
			R: Files.Rider;
			h: Header;
			err, stop: BOOLEAN;
	BEGIN
		IF sorted THEN
			headerList:= NIL;
			Enumerate(archive, InsertHeadSort, FALSE, res);
			IF res = Done THEN
				stop := FALSE;
				WHILE ~stop & (headerList # NIL) DO
					enumProc(headerList.header, stop); headerList:= headerList.next
				END
			END;
			headerList := NIL
		ELSE
			ArcF := Files.Old(archive);
			IF ArcF # NIL THEN
				err := FALSE;
				stop := FALSE;
				Files.Set(R, ArcF, 0);
				ReadHeader(R, h, err);
				WHILE (h.name # EOFName) & ~err & ~stop DO
					enumProc(h, stop);
					Files.Set(R, ArcF, Files.Pos(R)+h.length);
					ReadHeader(R, h, err)
				END;
				IF err THEN
					res := ErrorInArchive
				ELSE
					res := Done
				END
			ELSE
				res := ArchiveNotFound
			END
		END
	END Enumerate;

(** Add a new entry (file) to the archive (archive) with data read from R.
		file: input: name of the entry
				output: name choosen for entry (may differ if names collaps)
		res:
			Done
			ArchiveNotFound: archive-file not found
			ErrorInArchive: internal error in archive-file *)
	PROCEDURE AddFile*(archive: ARRAY OF CHAR; VAR file: ARRAY OF CHAR; VAR R: Files.Rider; len: LONGINT; VAR res: INTEGER);
		VAR
			ArcF: Files.File;
			Ra: Files.Rider;
			h: Header;
			pos: LONGINT;
			addL, ha: List;
			err: BOOLEAN;
	BEGIN
		ArcF := Files.Old(archive);
		IF ArcF # NIL THEN
			Files.Set(Ra, ArcF, 0);
			addL := NIL;
			pos := Files.Pos(Ra);
			ReadHeader(Ra, h, err);
			WHILE (h.name # EOFName) & ~err DO
				IF addL = NIL THEN
					NEW(addL); COPY(h.name, addL.name);
					addL.next := NIL
				ELSE
					NEW(ha); COPY(h.name, ha.name);
					ha.next := addL;
					addL := ha
				END;
				Files.Set(Ra, ArcF, Files.Pos(Ra)+h.length);
				pos := Files.Pos(Ra);
				ReadHeader(Ra, h, err)
			END;
			IF err THEN
				res := ErrorInArchive;
				RETURN
			END;
			Trimm(file);
			WHILE Search(addL, file) # NIL DO
				NextName(file)
			END;
			pos := Files.Pos(Ra);
			COPY(file, h.name);
			h.extensions := {};
			WriteHeader(Ra, h);
			CopyToArc(R, Ra, len, h);
			Files.Set(Ra, ArcF, pos);
			WriteHeader(Ra, h);
			Files.Close(ArcF);
			res := Done
		ELSE
			res := ArchiveNotFound
		END
	END AddFile;

	PROCEDURE WriteDocHead(VAR R: Files.Rider);
	BEGIN
				Files.WriteInt(R, DocumentsId);  (* polpo: Documents.Id of the desktop, archives stay the same *)
						Files.WriteString(R, "Compress.NewDoc");
		Files.WriteInt(R, 0);
		Files.WriteInt(R, 0);
		Files.WriteInt(R, 200);
		Files.WriteInt(R, 250)
	END WriteDocHead;

(** Delete entry (file) from the archive (archive).
		res:
			Done
			ArchiveNotFound: archive-file not found
			ErrorInArchive: internal error in archive-file
			EntryNotFound: no such entry (entry) found *)
	PROCEDURE DeleteFile*(archive, file: ARRAY OF CHAR; VAR res: INTEGER);
		VAR
			ArcF, TmpF: Files.File;
			Ra, Rt: Files.Rider;
			h: Header;
			err, del: BOOLEAN;
			pos: LONGINT;
	BEGIN
		ArcF := Files.Old(archive);
		IF ArcF # NIL THEN
			TmpF := Files.New(Temp);
			Files.Set(Rt, TmpF, 0);
			del := FALSE;
			Files.Set(Ra, ArcF, 0);
			ReadHeader(Ra, h, err);
			WHILE (h.name # EOFName) & ~err DO
				pos := Files.Pos(Ra);
				IF h.name = file THEN
					del := TRUE
				ELSE
					WriteHeader(Rt, h);
					Files.Set(Ra, ArcF, pos);
					CopyFrom(Ra, Rt, h.length)
				END;
				Files.Set(Ra, ArcF, pos+h.length);
				ReadHeader(Ra, h, err)
			END;
			IF err THEN
				res := ErrorInArchive
			ELSIF del THEN
				Files.Set(Rt, TmpF, 0);
				ArcF := Files.New(archive);
				Files.Set(Ra, ArcF, 0);
				WriteDocHead(Ra);
				CopyTo(Rt, Ra);
				Files.Register(ArcF);
				res := Done
			ELSE
				res := EntryNotFound
			END
		ELSE
			res := ArchiveNotFound
		END
	END DeleteFile;

(** Extract entry (file) from the archive (archive) and write its data to R.
		res:
			Done
			ArchiveNotFound: archive-file not found
			ErrorInArchive: internal error in archive-file
			EntryNotFound no such entry (entry) found *)
	PROCEDURE ExtractFile*(archive, file: ARRAY OF CHAR; VAR R: Files.Rider; VAR res: INTEGER);
		VAR
			ArcF: Files.File;
			Ra: Files.Rider;
			h: Header;
			err, found: BOOLEAN;
			pos: LONGINT;
	BEGIN
		ArcF := Files.Old(archive);
		IF ArcF # NIL THEN
			found := FALSE; res := Done;
			Files.Set(Ra, ArcF, 0);
			ReadHeader(Ra, h, err);
			WHILE (h.name # EOFName) & ~err & ~found DO
				pos := Files.Pos(Ra);
				IF h.name = file THEN
					found := TRUE;
					CopyFromArc(Ra, R, h, res)
				ELSE
					Files.Set(Ra, ArcF, pos+h.length);
					ReadHeader(Ra, h, err)
				END
			END;
			IF err THEN
				res := ErrorInArchive
			ELSIF ~found THEN
				res := EntryNotFound
			END
		ELSE
			res := ArchiveNotFound
		END
	END ExtractFile;

(** Extract all entries in archive (archive).
		res:
			Done
			ArchiveNotFound: archive-file not found
			ErrorInArchive: internal error in archive-file
			FileError: an entry file could not be created *)
	PROCEDURE ExtractAllFiles*(archive: ARRAY OF CHAR; VAR res: INTEGER);
		VAR
			ArcF, AddF: Files.File;
			Ra, RF: Files.Rider;
			h: Header;
			err: BOOLEAN;
			pos: LONGINT;
	BEGIN
		ArcF := Files.Old(archive);
		IF ArcF # NIL THEN
			Files.Set(Ra, ArcF, 0);
			ReadHeader(Ra, h, err);
			WHILE (h.name # EOFName) & ~err DO
				pos := Files.Pos(Ra);
				AddF := Files.New(h.name);
				IF AddF # NIL THEN
					Files.Set(RF, AddF, 0);
					CopyFromArc(Ra, RF, h, res);
					IF res = Done THEN
						Files.Register(AddF); Files.SetDate(AddF, h.time, h.date)
					ELSE
						RETURN
					END
				ELSE
					res := FileError;
					RETURN
				END;
				Files.Set(Ra, ArcF, pos+h.length);
				ReadHeader(Ra, h, err)
			END;
			IF err THEN
				res := ErrorInArchive
			ELSE
				res := Done
			END
		ELSE
			res := ArchiveNotFound
		END
	END ExtractAllFiles;

(** Create a new empty archive.
		res:
			Done
			ArchiveExists: archive allready existed
			FileError: archive-file could not be created *)
	PROCEDURE CreateArchive*(archive: ARRAY OF CHAR; VAR res: INTEGER);
		VAR
			ArcF: Files.File;
			R: Files.Rider;
	BEGIN
		ArcF := Files.Old(archive);
		IF ArcF = NIL THEN
			ArcF := Files.New(archive);
			IF ArcF = NIL THEN
				res := FileError
			ELSE
				Files.Set(R, ArcF, 0);
				WriteDocHead(R);
				Files.Register(ArcF);
				res := Done
			END
		ELSE
			res := ArchiveExists
		END
	END CreateArchive;




(** Document new-procedure for compress-archives.
		Old archive files can be opened with Desktops.OpenDoc old.arc(Compress.NewDoc) . *)

(** Compress.Directory:
	Display a list of all entries in an archive. If option "d" is used
	additional information on contents is given. If option "s" is used
	the output is sorted by filename.
	syntax:
		Compress.Directory Archive.Arc
		Compress.Directory /d Archive.Arc
		Compress.Directory ^
		Compress.Directory /d ^ *)


(** Compress.Add:
	Add files to an archive, if the archive not already exists, create
	a new one.
	syntax:
		Compress.Add Archive.Arc file1 file2 ... ~
		Compress.Add Archive.Arc ^ ~ *)

(** Compress.Delete
	Delete selected files from an archive.
	syntax:
		Compress.Delete Archive.Arc file1 file2 ... ~
		Compress.Delete Archive.Arc ^ ~ *)

(** Compress.Open
	Unpack a file from an archive and open it in a viewer.
	No file is written to disk.
	syntax:
		Compress.Open Archive.Arc file ~
		Compress.Open Archive.Arc ^ ~ *)

(** Compress.Extract
	Unpack selected files from an archive.
	syntax:
		Compress.Extract Archive.Arc file1 file2 ... ~
		Compress.Extract Archive.Arc ^ ~ *)


(** Compress.Rename
	Rename entries in a archive.
	syntax:
		Compress.Rename Archive.Arc old1 => new1 old2 => new2 ... ~ *)

(** Compress.ExtractAll
	Unpack all files from a list of archives.
	syntax:
		Compress.ExtractAll Archive1.Arc ... ~*)
		
BEGIN
	verbose := FALSE;
	Texts.OpenWriter(W)
END Compress0.
