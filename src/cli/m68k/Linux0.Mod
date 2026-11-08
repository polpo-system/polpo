MODULE Linux0;  (* rc/ard/nm/jm/devil/pjm/rml*)

(* Linux interface for the Motorola 68020 and later (m68k, big-endian) *)

(* OBERON System 3, Release 2.2.

Copyright 1997 Team of the Institute of Computer Systems of ETH Zuerich,
ETH Center, CH-8092 Zuerich, e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon 
System 3 license contract.  The full text can be requested from the 
above-mentioned address, or downloaded from

  "ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/license.txt;A"

Under the license terms stated it is in particular (a) prohibited to modify
the interface of this module in any way that disagrees with the style
or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)

(*  polpo: made from the PowerPC Linux0.

  A system call: the number in D0, the arguments in D1..D5 and A0, trap #0; the result in D0, -errno
  on an error. The compiler passes the parameters on the stack (see KOPL): a stub puts them into the
  registers with SYSTEM.PUTREG and calls Sys, which does not touch them.

  Syscall numbers in arch/m68k/kernel/syscalls/syscall.tbl of the Linux sources. m68k aligns 32-bit
  fields of the kernel's structures to 2 bytes (struct stat64).
*)

IMPORT SYSTEM;

CONST
  ARCH*="M68K";
  ObjPrefix*="m68k/";
  StatModeOfs* = 14;  (** the offset of st_mode in Status (struct stat64) *)
  ObjTag*=36F6H;  (* x86: 0AFX; arml: 0F5X; arm: 36FBH; mips: 36F9H; mipsbe: 36F8H; ppc: 36F7H; m68k: 36F6H *)
  RegSize*=32;
  PageSize*=1000H;

  TRAP0=4E40H;  (* trap #0 *)
  XTRAP*=50FAH;  (* TRAPcc.W #nr: the traps of the compiler, nr in the next word; + cc*100H *)

  (* registers: 0..7 D0..D7, 8..15 A0..A7, as in SYSTEM.GETREG and in SigContext.regs *)
  SP*=15; FP*=14; LR*=0; ARI*=0;  (* no link register; LR and ARI are not used on m68k *)

  ATFDCWD*=-100;  (* use current working directory *)

  (** Open( .. ) flags *)
  ORDonly*= 0;  OWRonly*= 1;  ORDWR*=2;  OCREAT*= 40H;  OEXCL*= 80H;  OTRUNC*= 200H;  OAPPEND*=400H;  ODSYNC*=1000H;
  ODirectory*=4000H;
  (** FLock( .. ) *)
  LOCKEX*= 2;  LOCKNB*= 4;  LOCKUN*= 8;
  (** LSeek *)
  SEEKSET*=0;  SEEKCURRENT*=1;  SEEKEND*=2;
  (** Mmap *)
  MAPSHARED*=1; MAPPRIVATE*=2; MAPANONYMOUS*=20H;

  (* Termios used in Input (FB): the generic numbers *)
  VMIN*= 6;
  TCGETS*= 5401H;
  TCSETSF*= 5404H;

  (** Socket *)
  SOCKSTREAM*=1;

  SIGHUP= 1;    (* Hang up ; X11 quits *)
  SIGINT*= 2;      (* interrupt   ctrl-c *)
  SIGQUIT= 3;    (* quit *)
  SIGILL* = 4;      (* invalid instruction *)
  SIGTRAP*= 5;
  SIGABRT= 6;
  SIGBUS=7;
  SIGFPE* = 8;    (* TRAPcc, CHK: the traps of the compiler *)
  SIGKILL*= 9;  (* kill *)
  SIGUSR1*= 10;
  SIGSEGV*= 11;  (* segmentation fault *)
  SIGUSR2*= 12;  (* used by DisplayLinuxFB for console switching *)
  SIGPIPE= 13;
  SIGALRM= 14;
  SIGTERM = 15;
  SIGCHLD*= 17;  (* child quit *)
  SIGCONT*= 18;
  SIGSTOP= 19;
  SIGTTIN= 21;
  SIGTTOU= 22;
  SIGPROF= 29;
  SIGXCPU= 30;
  SIGXFSZ= 31;

  RegDist*=1;  (* SC.regs =32 bit *)
  RegOff*=0;  (* SC.regs[i + RegOff] is register i *)

TYPE
  Proc*= PROCEDURE;
  TrapHandler* = PROCEDURE ( trap, fp, pc, page: LONGINT);

  Status* = RECORD  (* struct stat64 of m68k: st_mode at 14, st_size at 40 (the low word at 44), st_mtime at 68 *)
    pad0: ARRAY 10 OF LONGINT;  (* 0 *)
    sizeh, size*, blksize*, blocksh, blocks*: LONGINT;  (* 40 *)
    atime*, atimens, mtime*, mtimens, ctime*, ctimens: LONGINT;  (* 60 *)
    inoh, ino: LONGINT;  (* 84 *)
    pad1: ARRAY 8 OF LONGINT
  END;

  SockAddrUn*= RECORD
    pf*: INTEGER;
    path*: ARRAY 64 OF CHAR;
  END;

  (* the ucontext the kernel passes to a SA_SIGINFO handler: uc_flags, uc_link, uc_stack (3 words),
     then uc_mcontext: version, D0..D7, A0..A7, pc, sr, the FPU control registers (3 words) and
     FP0..FP7 (3 words each) *)
  SigContext*= POINTER TO RECORD
    flags, link, sssp, ssflags, sssize, version: LONGINT;
    regs*: ARRAY 16 OF LONGINT;
    pc*, sr: LONGINT;
    fpcntl: ARRAY 3 OF LONGINT;
    fpregs*: ARRAY 24 OF LONGINT
  END;

  SigInfo*= POINTER TO RECORD
    signo*, errno*, code*, adr*: LONGINT;  (* adr: the instruction of a TRAPcc or CHK, the address of a fault *)
  END;

VAR
  break*: BOOLEAN;  (** has ctrl-break been pressed? set by Kernel *)
  StackOrg*: LONGINT;  (** highest address on stack (single-process system); set by Kernel *)
  Regs*: ARRAY 32 OF LONGINT;
  FRegs*: ARRAY 64 OF LONGINT;

(* the system call nr with the arguments already in D1..D5, A0 *)
PROCEDURE Sys(nr: LONGINT): LONGINT;
VAR r: LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, nr);
  SYSTEM.CODE( TRAP0);
  SYSTEM.GETREG( 0, r);
  RETURN r
END Sys;

PROCEDURE Exit0*(status: LONGINT);
VAR r: LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, status);
  r := Sys( 247)  (* exit_group *)
END Exit0;

PROCEDURE StoreRegs*( adr: LONGINT);  (* register n to adr+4*n, for the stack scan of Kernel.GC *)
BEGIN
  SYSTEM.PUTREG( 8, adr);
  SYSTEM.CODE( 48D07FFFH)  (* MOVEM.L D0-D7/A0-A6, (A0) *)
END StoreRegs;

PROCEDURE SIGAction0( signum, act, oldact: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, signum); SYSTEM.PUTREG( 2, act); SYSTEM.PUTREG( 3, oldact);
  SYSTEM.PUTREG( 4, 8);  (* the size of the signal mask *)
  RETURN Sys( 174)  (* rt_sigaction *)
END SIGAction0;

PROCEDURE CacheFlush0*( adr, bytes: LONGINT): LONGINT;  (* new code in the instruction cache *)
BEGIN
  SYSTEM.PUTREG( 1, adr); SYSTEM.PUTREG( 2, 1); SYSTEM.PUTREG( 3, 3); SYSTEM.PUTREG( 4, bytes);
  RETURN Sys( 123)  (* cacheflush: FLUSH_SCOPE_LINE, FLUSH_CACHE_BOTH *)
END CacheFlush0;

PROCEDURE Fork0*(): LONGINT;
BEGIN
  RETURN Sys( 2)  (* fork *)
END Fork0;

PROCEDURE Execve0*( filename, argv, envp: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, filename); SYSTEM.PUTREG( 2, argv); SYSTEM.PUTREG( 3, envp);
  RETURN Sys( 11)  (* execve *)
END Execve0;

PROCEDURE Waitpid0*( pid, status, options: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, pid); SYSTEM.PUTREG( 2, status); SYSTEM.PUTREG( 3, options);
  RETURN Sys( 7)  (* waitpid *)
END Waitpid0;

PROCEDURE Openat0*( dfd, name, flags, mode: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, dfd); SYSTEM.PUTREG( 2, name); SYSTEM.PUTREG( 3, flags); SYSTEM.PUTREG( 4, mode);
  RETURN Sys( 288)  (* openat *)
END Openat0;

PROCEDURE Readlinkat0*( dfd, name, buf, bufsiz: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, dfd); SYSTEM.PUTREG( 2, name); SYSTEM.PUTREG( 3, buf); SYSTEM.PUTREG( 4, bufsiz);
  RETURN Sys( 298)  (* readlinkat *)
END Readlinkat0;

PROCEDURE Close0*( fd: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd);
  RETURN Sys( 6)  (* close *)
END Close0;

PROCEDURE Fsync0*( fd: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd);
  RETURN Sys( 118)  (* fsync: write the file's data to the disk *)
END Fsync0;

PROCEDURE Read0*( fd, buf, num: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd); SYSTEM.PUTREG( 2, buf); SYSTEM.PUTREG( 3, num);
  RETURN Sys( 3)  (* read *)
END Read0;

PROCEDURE Readv0*( fd, vect, cnt: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd); SYSTEM.PUTREG( 2, vect); SYSTEM.PUTREG( 3, cnt);
  RETURN Sys( 145)  (* readv *)
END Readv0;

PROCEDURE Write0*( fd, buf, num: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd); SYSTEM.PUTREG( 2, buf); SYSTEM.PUTREG( 3, num);
  RETURN Sys( 4)  (* write *)
END Write0;

PROCEDURE Writev0*( fd, vect, cnt: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd); SYSTEM.PUTREG( 2, vect); SYSTEM.PUTREG( 3, cnt);
  RETURN Sys( 146)  (* writev *)
END Writev0;

PROCEDURE Brk0*( adr: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, adr);
  RETURN Sys( 45)  (* brk *)
END Brk0;

PROCEDURE MProtect0*( adr, len, prot: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, adr); SYSTEM.PUTREG( 2, len); SYSTEM.PUTREG( 3, prot);
  RETURN Sys( 125)  (* mprotect *)
END MProtect0;

PROCEDURE FStat0*( fd, stat: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd); SYSTEM.PUTREG( 2, stat);
  RETURN Sys( 197)  (* fstat64 *)
END FStat0;

PROCEDURE Mmap20*( addr, len, prot, flags, fd, off: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, addr); SYSTEM.PUTREG( 2, len); SYSTEM.PUTREG( 3, prot); SYSTEM.PUTREG( 4, flags); SYSTEM.PUTREG( 5, fd); SYSTEM.PUTREG( 8, off);
  RETURN Sys( 192)  (* mmap2: the offset in pages *)
END Mmap20;

PROCEDURE Munmap0*( addr, len: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, addr); SYSTEM.PUTREG( 2, len);
  RETURN Sys( 91)  (* munmap *)
END Munmap0;

PROCEDURE LSeek0*( fd, pos, whence: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd); SYSTEM.PUTREG( 2, pos); SYSTEM.PUTREG( 3, whence);
  RETURN Sys( 19)  (* lseek *)
END LSeek0;

PROCEDURE FLock0*( fd, arg: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd); SYSTEM.PUTREG( 2, arg);
  RETURN Sys( 143)  (* flock *)
END FLock0;

PROCEDURE Ftruncate0*( fd, len: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd); SYSTEM.PUTREG( 2, len);
  RETURN Sys( 93)  (* ftruncate *)
END Ftruncate0;

PROCEDURE UTimensat0*( dirfd, name, utimebuf, flags: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, dirfd); SYSTEM.PUTREG( 2, name); SYSTEM.PUTREG( 3, utimebuf); SYSTEM.PUTREG( 4, flags);
  RETURN Sys( 316)  (* utimensat *)
END UTimensat0;

PROCEDURE GetTimeOfDay*( tv, tz: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, tv); SYSTEM.PUTREG( 2, tz);
  RETURN Sys( 78)  (* gettimeofday *)
END GetTimeOfDay;

PROCEDURE Renameat0*( olddfd, old, newdfd, new, flags: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, olddfd); SYSTEM.PUTREG( 2, old); SYSTEM.PUTREG( 3, newdfd); SYSTEM.PUTREG( 4, new); SYSTEM.PUTREG( 5, flags);
  RETURN Sys( 351)  (* renameat2 *)
END Renameat0;

PROCEDURE MkDir0*( name, mode: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, name); SYSTEM.PUTREG( 2, mode);
  RETURN Sys( 39)  (* mkdir *)
END MkDir0;

PROCEDURE Mkdirat0*( dirfd, name, mode: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, dirfd); SYSTEM.PUTREG( 2, name); SYSTEM.PUTREG( 3, mode);
  RETURN Sys( 289)  (* mkdirat: a directory relative to dirfd *)
END Mkdirat0;

PROCEDURE Fchmodat0*( dirfd, name, mode: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, dirfd); SYSTEM.PUTREG( 2, name); SYSTEM.PUTREG( 3, mode);
  RETURN Sys( 299)  (* fchmodat: the permissions of name relative to dirfd *)
END Fchmodat0;

PROCEDURE ChDir0*( name: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, name);
  RETURN Sys( 12)  (* chdir *)
END ChDir0;

PROCEDURE UnLinkat0*( dirfd, name, flags: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, dirfd); SYSTEM.PUTREG( 2, name); SYSTEM.PUTREG( 3, flags);
  RETURN Sys( 294)  (* unlinkat *)
END UnLinkat0;

PROCEDURE Mremap0*( oldaddr, oldsize, newsize, flags, naddr: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, oldaddr); SYSTEM.PUTREG( 2, oldsize); SYSTEM.PUTREG( 3, newsize); SYSTEM.PUTREG( 4, flags); SYSTEM.PUTREG( 5, naddr);
  RETURN Sys( 163)  (* mremap, MREMAP_MAYMOVE = 1 *)
END Mremap0;

PROCEDURE FStatat0*( dirfd, name, stat, flags: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, dirfd); SYSTEM.PUTREG( 2, name); SYSTEM.PUTREG( 3, stat); SYSTEM.PUTREG( 4, flags);
  RETURN Sys( 293)  (* fstatat64 *)
END FStatat0;

PROCEDURE GetDents0*( fd, bufptr, count: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd); SYSTEM.PUTREG( 2, bufptr); SYSTEM.PUTREG( 3, count);
  RETURN Sys( 220)  (* getdents64 *)
END GetDents0;

PROCEDURE Socket0*( domain, type, protocol: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, domain); SYSTEM.PUTREG( 2, type); SYSTEM.PUTREG( 3, protocol);
  RETURN Sys( 356)  (* socket *)
END Socket0;

PROCEDURE Connect0*( sockfd, servaddr, addrlen: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, sockfd); SYSTEM.PUTREG( 2, servaddr); SYSTEM.PUTREG( 3, addrlen);
  RETURN Sys( 359)  (* connect *)
END Connect0;

PROCEDURE Shmget0*( key, size, shmflag: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, key); SYSTEM.PUTREG( 2, size); SYSTEM.PUTREG( 3, shmflag);
  RETURN Sys( 395)  (* shmget *)
END Shmget0;

PROCEDURE Shmat0*( shmid, addr, flags: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, shmid); SYSTEM.PUTREG( 2, addr); SYSTEM.PUTREG( 3, flags);
  RETURN Sys( 397)  (* shmat *)
END Shmat0;

PROCEDURE Shmdt0*( addr: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, addr);
  RETURN Sys( 398)  (* shmdt *)
END Shmdt0;

PROCEDURE ShmCtl0*( buf, cmd, shmid: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, shmid); SYSTEM.PUTREG( 2, cmd); SYSTEM.PUTREG( 3, buf);
  RETURN Sys( 396)  (* shmctl: shmid, cmd, buf in this order *)
END ShmCtl0;

PROCEDURE IOCtl0*( d, r1, r2: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, d); SYSTEM.PUTREG( 2, r1); SYSTEM.PUTREG( 3, r2);
  RETURN Sys( 54)  (* ioctl *)
END IOCtl0;

PROCEDURE Mount0*( src, target, type, flags, data: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, src); SYSTEM.PUTREG( 2, target); SYSTEM.PUTREG( 3, type); SYSTEM.PUTREG( 4, flags); SYSTEM.PUTREG( 5, data);
  RETURN Sys( 21)  (* mount *)
END Mount0;

PROCEDURE FinitModule0*( fd, params, flags: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd); SYSTEM.PUTREG( 2, params); SYSTEM.PUTREG( 3, flags);
  RETURN Sys( 348)  (* finit_module *)
END FinitModule0;

PROCEDURE Setsid0*(): LONGINT;
BEGIN
  RETURN Sys( 66)  (* setsid *)
END Setsid0;

PROCEDURE Sync0*(): LONGINT;
BEGIN
  RETURN Sys( 36)  (* sync *)
END Sync0;

PROCEDURE Reboot0*( magic1, magic2, cmd, arg: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, magic1); SYSTEM.PUTREG( 2, magic2); SYSTEM.PUTREG( 3, cmd); SYSTEM.PUTREG( 4, arg);
  RETURN Sys( 88)  (* reboot *)
END Reboot0;

PROCEDURE Select0*( n, readfds, writefds, execptfds, timeout: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, n); SYSTEM.PUTREG( 2, readfds); SYSTEM.PUTREG( 3, writefds); SYSTEM.PUTREG( 4, execptfds); SYSTEM.PUTREG( 5, timeout);
  RETURN Sys( 142)  (* _newselect *)
END Select0;

PROCEDURE Bind0*( fd, addr, len: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd); SYSTEM.PUTREG( 2, addr); SYSTEM.PUTREG( 3, len);
  RETURN Sys( 358)  (* bind *)
END Bind0;

PROCEDURE Listen0*( fd, backlog: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd); SYSTEM.PUTREG( 2, backlog);
  RETURN Sys( 360)  (* listen *)
END Listen0;

PROCEDURE Accept40*( fd, addr, lenadr, flags: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd); SYSTEM.PUTREG( 2, addr); SYSTEM.PUTREG( 3, lenadr); SYSTEM.PUTREG( 4, flags);
  RETURN Sys( 361)  (* accept4 *)
END Accept40;

PROCEDURE GetSockName0*( fd, addr, lenadr: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd); SYSTEM.PUTREG( 2, addr); SYSTEM.PUTREG( 3, lenadr);
  RETURN Sys( 364)  (* getsockname *)
END GetSockName0;

PROCEDURE GetPeerName0*( fd, addr, lenadr: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd); SYSTEM.PUTREG( 2, addr); SYSTEM.PUTREG( 3, lenadr);
  RETURN Sys( 365)  (* getpeername *)
END GetPeerName0;

PROCEDURE SetSockOpt0*( fd, level, name, val, len: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd); SYSTEM.PUTREG( 2, level); SYSTEM.PUTREG( 3, name); SYSTEM.PUTREG( 4, val); SYSTEM.PUTREG( 5, len);
  RETURN Sys( 363)  (* setsockopt *)
END SetSockOpt0;

PROCEDURE GetSockOpt0*( fd, level, name, val, lenadr: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd); SYSTEM.PUTREG( 2, level); SYSTEM.PUTREG( 3, name); SYSTEM.PUTREG( 4, val); SYSTEM.PUTREG( 5, lenadr);
  RETURN Sys( 362)  (* getsockopt *)
END GetSockOpt0;

PROCEDURE Shutdown0*( fd, how: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd); SYSTEM.PUTREG( 2, how);
  RETURN Sys( 370)  (* shutdown *)
END Shutdown0;

PROCEDURE SendTo0*( fd, buf, len, flags, addr, addrlen: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd); SYSTEM.PUTREG( 2, buf); SYSTEM.PUTREG( 3, len); SYSTEM.PUTREG( 4, flags); SYSTEM.PUTREG( 5, addr); SYSTEM.PUTREG( 8, addrlen);
  RETURN Sys( 366)  (* sendto *)
END SendTo0;

PROCEDURE RecvFrom0*( fd, buf, len, flags, addr, lenadr: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 1, fd); SYSTEM.PUTREG( 2, buf); SYSTEM.PUTREG( 3, len); SYSTEM.PUTREG( 4, flags); SYSTEM.PUTREG( 5, addr); SYSTEM.PUTREG( 8, lenadr);
  RETURN Sys( 368)  (* recvfrom *)
END RecvFrom0;

(* the 32-bit fields of a chain at base + 2*L: the distance in words to the previous one, 0 ending the chain,
  and an offset to entry; see KOPL *)
PROCEDURE Fixup*( base, entry, L: LONGINT; data: BOOLEAN);
VAR a, d: LONGINT; w: INTEGER;
BEGIN
  IF (entry#0) & (L # 0) THEN
    REPEAT
      a := base + 2*L; SYSTEM.GET( a, w); d := LONG( w) MOD 10000H;
      SYSTEM.GET( a + 2, w); SYSTEM.PUT( a, entry + LONG( w));
      DEC( L, d)
    UNTIL d = 0
  END
END Fixup;

PROCEDURE SetSignal*( nr: LONGINT; handler: Proc): LONGINT;
TYPE
  SigAction = RECORD
    handler: Proc;
    flags: SET;
    restorer: Proc;
    mask, mask2: SET;
  END;
VAR h: SigAction;
BEGIN
  h.handler:= handler;
  h.flags:={ 2, 30};  (* SA_SIGINFO (signal, siginfo and ucontext on the stack), SA_NODEFER *)
  h.restorer:=NIL; h.mask:={}; h.mask2:={};
  RETURN SIGAction0( nr, SYSTEM.ADR(h), 0);
END SetSignal;

PROCEDURE CopyRegs*( sc: SigContext);
VAR i: LONGINT;
BEGIN
  i := 0; WHILE i < 16 DO Regs[i] := sc.regs[i]; INC(i) END;
  i := 0; WHILE i < 24 DO FRegs[i] := sc.fpregs[i]; INC(i) END
END CopyRegs;

(* polpo: the nonblocking sockets of Sockets, as unixNet of norayr/Internet has them, made of Socket0,
  Accept40, IOCtl0, GetSockOpt0, SetSockOpt0 and Select0 with the numbers of this architecture *)
PROCEDURE SocketNonblocking0*( domain, type, protocol: LONGINT): LONGINT;
CONST SockNonblock = 800H; SockCloexec = 80000H;
BEGIN
  RETURN Socket0( domain, type + SockNonblock + SockCloexec, protocol)
END SocketNonblocking0;

(** clear (blocking) or set O_NONBLOCK of fd *)
PROCEDURE SetBlocking0*( fd: LONGINT; blocking: BOOLEAN): LONGINT;
CONST FIONBIO = 5421H;
VAR on: LONGINT;
BEGIN
  IF blocking THEN on := 0 ELSE on := 1 END;
  RETURN IOCtl0( fd, FIONBIO, SYSTEM.ADR( on))
END SetBlocking0;

(** accept a connection of fd as a nonblocking socket, closed on exec *)
PROCEDURE AcceptNonblocking0*( fd, addr, lenadr: LONGINT): LONGINT;
CONST SockNonblock = 800H; SockCloexec = 80000H;
BEGIN
  RETURN Accept40( fd, addr, lenadr, SockNonblock + SockCloexec)
END AcceptNonblocking0;

(** a result of Connect0: the connection is still being made *)
PROCEDURE Pending0*( result: LONGINT): BOOLEAN;
CONST EINPROGRESS = 115; EALREADY = 114;
BEGIN
  RETURN (result = -EINPROGRESS) OR (result = -EALREADY)
END Pending0;

(** a result of a nonblocking call: it would have to wait *)
PROCEDURE WouldBlock0*( result: LONGINT): BOOLEAN;
CONST EAGAIN = 11;
BEGIN
  RETURN result = -EAGAIN
END WouldBlock0;

(** a result of a call interrupted by a signal *)
PROCEDURE Interrupted0*( result: LONGINT): BOOLEAN;
CONST EINTR = 4;
BEGIN
  RETURN result = -EINTR
END Interrupted0;

(** the pending error of socket fd (SO_ERROR), negative; 0 if none *)
PROCEDURE SocketError0*( fd: LONGINT): LONGINT;
CONST SolSocket = 1; SoError = 4;
VAR e, n, r: LONGINT;
BEGIN
  e := 0; n := 4; r := GetSockOpt0( fd, SolSocket, SoError, SYSTEM.ADR( e), SYSTEM.ADR( n));
  IF r < 0 THEN RETURN r END;
  RETURN -e
END SocketError0;

(** SO_LINGER of 0 seconds: closing fd resets the connection and drops the data not sent *)
PROCEDURE Abortive0*( fd: LONGINT): LONGINT;
CONST SolSocket = 1; SoLinger = 13;
VAR l: ARRAY 2 OF LONGINT;
BEGIN
  l[ 0] := 1; l[ 1] := 0;
  RETURN SetSockOpt0( fd, SolSocket, SoLinger, SYSTEM.ADR( l[ 0]), 8)
END Abortive0;

(** wait up to ms milliseconds (below 0: without a limit) until fd can be read (write: written), or has
  an error or was closed by the other side: 0 at the timeout, above 0 when ready, below 0 an error. Made
  with select, fd must be below 1024 *)
PROCEDURE Poll0*( fd: LONGINT; write: BOOLEAN; ms: LONGINT): LONGINT;
VAR set: ARRAY 32 OF SET; tv: ARRAY 2 OF LONGINT; i, t: LONGINT;
BEGIN
  IF fd < 0 THEN RETURN -9 END;
  IF fd >= 1024 THEN RETURN -22 END;
  i := 0; WHILE i < 32 DO set[ i] := {}; INC( i) END;
  INCL( set[ fd DIV 32], fd MOD 32);
  t := 0;
  IF ms >= 0 THEN tv[ 0] := ms DIV 1000; tv[ 1] := ms MOD 1000 * 1000; t := SYSTEM.ADR( tv[ 0]) END;
  IF write THEN RETURN Select0( fd + 1, 0, SYSTEM.ADR( set[ 0]), 0, t)
  ELSE RETURN Select0( fd + 1, SYSTEM.ADR( set[ 0]), 0, 0, t)
  END
END Poll0;

END Linux0.
