MODULE Linux0;  (* rc/ard/nm/jm/devil/pjm/rml*)

(*Linux interface for RISC-V  *)

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

(*  Peter Matthias
  2015-12-09  split OLR.Kernel.Mod to OLR.ARM.Linux0.Mod and OLR.MIPS.Linux0.Mod
  2016-04-07  OLR.MIPS.Linux0.Mod: Fixed Open flags
  2016-04-07  OLR.*.Linux0.Mod: added ODSYNC* open flag
  2016-04-15  added Exit0 Fork0 Execve0 Waitpid0
  2016-05-31  ported to RISC-V
  2016-10-05  moved signal handling from Kernel

  Syscall numbers in /usr/include/asm-generic/unistd.h

  SetClock not implemented ( only superuser can change time)
  reboot does not work
  Mmap
Wrapper Procedure for SYSCALL:

PROCEDURE SysCall( a, b, c, d, e, f, g: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 25, 4009);        (* Syscall nr to R2 *)
  SYSTEM.CODE( SYSCALL);          
  SYSTEM.CODE( JALR);            (* error is in R7 *)
END SysCall;

Not fixed for ROP2 compiler; prolog and epilog still written

See setcontext.S, getcontext.S from:
https://gitlab.cs.fau.de/osek-v/riscv-gnu-toolchain/blob/1872ff6b98eeeb7a2182ef0a82a71733c79c3fec/glibc/sysdeps/unix/sysv/linux/riscv/getcontext.Shttps://gitlab.cs.fau.de/osek-v/riscv-gnu-toolchain/tree/1872ff6b98eeeb7a2182ef0a82a71733c79c3fec/glibc/sysdeps/unix/sysv/linux/riscv
*)

IMPORT SYSTEM;

CONST
  ARCH*="RISC-V";
  ObjPrefix*="riscv/";
  StatModeOfs* = 16;  (** the offset of st_mode in Status (struct stat64) *)
  ObjTag*=36FDH;  (* x86: 0AFX; arml: 0F5X; arm: 36FBH; mips: 36F9H; mipst: 36FAH *)
  RegSize*=32;
  PageSize*=1000H;
  B32=0;  (* was 8 *)

  ECALL=73H;  JALR= 8067H;  LWr14=01012703H;  LWr15= 01412783H;  FENCEI=100FH;  XTRAP*=702BH;

  (* registers for RISC-V *)
  LR*=1; SP*=2; FP*=8;  ARI*=10;  T2=7;      (* mips: SP*=29; FP*=30; LR*=31;*)
  NRR=17;    (* syscall no. register *)

  ATFDCWD*=-100;  (* use current working directory *)

  (** Open( .. ) flags *)  (* old values: OCREAT*= 100H;  OEXCL*= 400H;  OAPPEND*=8H; *)(* same on ARM, MIPS, x86 *)
  ONonBlock=800H;  (* don't block on RISC-V, to be removed*)
  ORDonly*= 0;  OWRonly*= 1;  ORDWR*=2+ONonBlock;  OCREAT*= 40H;  OEXCL*= 80H;  OTRUNC*= 200H;  OAPPEND*=400H;  ODSYNC*=1000H;
  ODirectory*=10000H;
  (** FLock( .. ) *)
  LOCKEX*= 2;  LOCKNB*= 4;  LOCKUN*= 8;
  (** LSeek *)
  SEEKSET*=0;  SEEKCURRENT*=1;  SEEKEND*=2;
  (** Mmap *)
  MAPSHARED*=1; MAPPRIVATE*=2; MAPANONYMOUS*=20H;  (* ARM: 20H; MIPS: 800H *)

(*  PROTEXEC= PROTREAD=1  ; PROTWRITE=2  PROTNONE=  *)

  (* Termios used in Input (FB) *)
(* MIPS *)
  VMIN*=4;
  TCGETS*= 540DH;
  TCSETSF*=5410H;

  (** Socket *)
  SOCKSTREAM*=1;    (* was 1 for X86 and ARM, 2 for MIPS *)

(* Common *)
  SIGHUP= 1;    (* Hang up ; X11 quits *)
  SIGINT*= 2;      (* interrupt   ctrl-c *)
  SIGQUIT= 3;    (* quit  ctrl-# , ctrl-4 ?, PrintScreen? *)
  SIGILL* = 4;      (* invalid instruction ?*)
  SIGTRAP*= 5;    (* HALT( x) not used in RISC-V *)
  SIGABRT= 6;
  SIGBUS=7;  (* dummy, not used in RISC-V *)
  SIGFPE* = 8;    (* DIV 0 *)
  SIGKILL*= 9;  (* kill *)
  SIGUSR1*= 10;  (*  *)
  SIGSEGV*= 11;  (* segmentation fault *)
  SIGUSR2*= 12;  (* used by DisplayLinuxFB for console switching *)
  SIGPIPE= 13;  (* in KDE alt-F4 *)
  SIGALRM= 14;  (* signal  from alarm(1) *)
  SIGTERM = 15;  (* ctrl-alt-del *)
  SIGCHLD*= 17;  (* child quit *)
  SIGCONT*= 18;
  SIGSTOP= 19;
  SIGTTIN= 21;  (* virtual alarm ?? *)
  SIGTTOU= 22;  (* profile signal *)
  SIGPROF= 29;
  SIGXCPU= 30;
  SIGXFSZ= 31;

  RegDist*=1;  (* SC.regs =32 bit *)

TYPE
  Proc*= PROCEDURE;
  TrapHandler* = PROCEDURE ( trap, fp, pc, page: LONGINT);

  (* polpo: asm-generic struct stat layout (st_mode at offset 16, as on x86 and ARM);
     filled from statx by FStat0/FStatat0, since RV32 Linux has no stat syscalls *)
  Status* = RECORD
    stdev, stdevh, stino, stinoh: LONGINT;  (* 0 *)
    stmode, stnlink, stuid, stgid: LONGINT;  (* 16 *)
    rdev, rdevh, pad1, pad2: LONGINT;  (* 32 *)
    size*, sizeh, blksize*, pad3: LONGINT;  (* 48 *)
    blocks*, blocksh, atime*, atimens: LONGINT;  (* 64 *)
    mtime*, mtimens, ctime*, ctimens: LONGINT;  (* 80 *)
    pad4: ARRAY 16 OF LONGINT
  END;

  Timespec64 = RECORD sec, sech, nsec, nsech: LONGINT END;  (* struct __kernel_timespec *)

  SockAddrUn*= RECORD
    pf*: INTEGER;
    path*: ARRAY 64 OF CHAR;  (* was 30 for MIPS; 64 for ARM *)
  END;

(* RISC-V *)
  SigContext*= POINTER TO RECORD
    dummy: ARRAY 8 OF LONGINT;
    pc*: LONGINT;
    regs*: ARRAY 32 OF LONGINT;
    fpregs*: ARRAY 64 OF LONGINT;
  END;

  SigInfo*= POINTER TO RECORD  (* dummy, not yet used *)
    dummy: ARRAY 24 OF LONGINT;
    signo, code, errno, adr*, instr: LONGINT;
  END;

VAR
  break*: BOOLEAN;  (** has ctrl-break been pressed? polpo: here, as on x86 and ARM; set by Kernel *)
  StackOrg*: LONGINT;  (** highest address on stack (single-process system); polpo: set by Kernel *)
  Regs*: ARRAY 32 OF LONGINT;
  FRegs*: ARRAY 64 OF LONGINT;

PROCEDURE Exit0*(status: LONGINT);
CONST EXIT0= 1;
BEGIN
  SYSTEM.PUTREG( NRR, 93);        (* Syscall nr to R2 EXECVE *)
  SYSTEM.CODE( ECALL);
END Exit0;
  
PROCEDURE Clone0( flags, stack, ptid: LONGINT):LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 220);        (* clone; tls and ctid are not used without CLONE_SETTLS/CHILD_SETTID *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Clone0;

PROCEDURE Fork0*():LONGINT;
BEGIN
  RETURN Clone0( 17, 0, 0)        (* SIGCHLD: fork on RISC-V, which has no fork syscall *)
END Fork0;

PROCEDURE Execve0*( filename, argv, envp: LONGINT):LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 221);        (* execve *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Execve0;

PROCEDURE Waitid0( idtype, id, infop, options, rusage: LONGINT):LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 95);        (* waitid; RV32 has no wait4 *)
  SYSTEM.CODE( LWr14);            (* 5th parameter from sp+16 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Waitid0;

PROCEDURE Waitpid0*( pid, status, options: LONGINT):LONGINT;
(* waitpid with waitid: the siginfo (code at 8, pid at 12, status at 20) gives the wait status *)
VAR info: ARRAY 32 OF LONGINT; idtype, r, code, st: LONGINT;
BEGIN
  r := 0; WHILE r < 32 DO info[ r] := 0; INC( r) END;
  IF pid = -1 THEN idtype := 0
  ELSIF pid > 0 THEN idtype := 1
  ELSE idtype := 2; pid := -pid
  END;
  r := Waitid0( idtype, pid, SYSTEM.ADR( info), options + 4, 0);  (* + WEXITED *)
  IF r < 0 THEN RETURN r END;
  code := info[ 2]; st := info[ 5];
  IF code = 1 THEN st := st MOD 256 * 256      (* CLD_EXITED *)
  ELSIF code = 2 THEN st := st MOD 128          (* CLD_KILLED *)
  ELSIF code = 3 THEN st := st MOD 128 + 128    (* CLD_DUMPED *)
  ELSE st := st MOD 256 * 256 + 7FH             (* CLD_STOPPED, CLD_TRAPPED *)
  END;
  IF (status # 0) & (info[ 3] # 0) THEN SYSTEM.PUT( status, st) END;
  RETURN info[ 3]
END Waitpid0;

PROCEDURE Openat0*( dfd, name, flags, mode: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 56);        (* 56, openat Syscall nr to R2 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Openat0;

PROCEDURE Readlinkat0*( dfd, name, buf, bufsiz: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 78);        (* readlinkat *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Readlinkat0;

PROCEDURE Close0*( fd: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 57);        (* close *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Close0;

PROCEDURE Read0*( fd, buf, num: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 63);        (* Syscall nr to R2 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Read0;

PROCEDURE Readv0*( fd, vect, cnt: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 65);        (* Syscall nr to R2 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Readv0;

PROCEDURE Write0*( fd, buf, num: LONGINT): LONGINT;  
BEGIN
  SYSTEM.PUTREG( NRR, 64);    (* write *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Write0;

PROCEDURE Writev0*( fd, vect, cnt: LONGINT): LONGINT;  
BEGIN
  SYSTEM.PUTREG( NRR, 66);    (* writev *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Writev0;

PROCEDURE Brk0*( adr: LONGINT):LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 214);    (* brk *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Brk0;
(*
PROCEDURE Creat0*( name, mode: LONGINT): LONGINT;
BEGIN
  RETURN Open0( name, OCREAT+OWRonly+ OTRUNC, mode)
END Creat0;
*)
PROCEDURE MProtect0*( adr, len, prot: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 226);    (* mprotect *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END MProtect0;

PROCEDURE SIGAction0( signum, act, oldact: LONGINT): LONGINT;  
BEGIN
  SYSTEM.PUTREG( NRR,134);    (* sigaction was 4067*)
  SYSTEM.PUTREG( 13, 8);  (* rt_sigaction, mask size ? *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END SIGAction0;

(* polpo: RV32 Linux has only 64-bit time syscalls and statx; raw wrappers for them *)
PROCEDURE ClockGettime64( clk, ts: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 403);  (* clock_gettime64 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END ClockGettime64;

PROCEDURE Statx( dfd, name, flags, mask, buf: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 291);  (* statx *)
  SYSTEM.CODE( LWr14);    (* 5th parameter from sp+16 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Statx;

PROCEDURE PSelect6T64( n, readfds, writefds, exceptfds, timeout: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 413);  (* pselect6_time64 *)
  SYSTEM.CODE( LWr14);
  SYSTEM.CODE( 6793H);    (* R15:=0, no signal mask *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END PSelect6T64;

PROCEDURE UTimensatT64( dirfd, name, times, flags: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 412);  (* utimensat_time64 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END UTimensatT64;

(* Fill a Status record at address stat from a statx buffer b. *)
PROCEDURE StatxToStatus( VAR b: ARRAY OF LONGINT; stat: LONGINT);
VAR st: Status; i: LONGINT;
BEGIN
  FOR i := 0 TO LEN(st.pad4)-1 DO st.pad4[i] := 0 END;
  st.stdev := b[34]*100H + b[35]; st.stdevh := 0;  (* dev major, minor *)
  st.stino := b[8]; st.stinoh := b[9];
  st.stmode := b[7] MOD 10000H; st.stnlink := b[4]; st.stuid := b[5]; st.stgid := b[6];
  st.rdev := b[32]*100H + b[33]; st.rdevh := 0; st.pad1 := 0; st.pad2 := 0;
  st.size := b[10]; st.sizeh := b[11]; st.blksize := b[1]; st.pad3 := 0;
  st.blocks := b[12]; st.blocksh := b[13];
  st.atime := b[16]; st.atimens := b[18];
  st.mtime := b[28]; st.mtimens := b[30];
  st.ctime := b[24]; st.ctimens := b[26];
  SYSTEM.MOVE( SYSTEM.ADR(st), stat, SIZE(Status))
END StatxToStatus;

PROCEDURE FStat0*( fd, stat: LONGINT): LONGINT;
VAR b: ARRAY 64 OF LONGINT; empty: ARRAY 4 OF CHAR; r: LONGINT;
BEGIN
  empty[0] := 0X;
  r := Statx( fd, SYSTEM.ADR(empty), 1000H (* AT_EMPTY_PATH *), 7FFH (* STATX_BASIC_STATS *), SYSTEM.ADR(b));
  IF r = 0 THEN StatxToStatus( b, stat) END;
  RETURN r
END FStat0;

PROCEDURE Mmap20*( addr, len, prot, flags, fd, off: LONGINT):LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 222);        (* 222?? Syscall nr to R2 mmap64: 4210, mmap: 4090*)
  SYSTEM.CODE( LWr14);            (* LW r14, sp+16 *)
  SYSTEM.CODE( LWr15);            (* LW r15, sp+20 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Mmap20;

PROCEDURE Munmap0*( addr, len: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 215);        (* Syscall nr to R2 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Munmap0;

PROCEDURE CacheFlush0*( adr, bytes: LONGINT): LONGINT;
BEGIN
  SYSTEM.CODE( FENCEI);
  RETURN 0;
END CacheFlush0;

(* Files *)

PROCEDURE LLSeek0*( fd, offsethigh, offsetlow, resultadr, whence: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 62);        (* 62 llseek *)
  SYSTEM.CODE( LWr14);            (* LW r14, sp+16 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END LLSeek0;

PROCEDURE LSeek0*( fd, offset, whence: LONGINT): LONGINT;
VAR a: ARRAY 2 OF LONGINT; b: LONGINT;
BEGIN
  b:=LLSeek0( fd, 0, offset, SYSTEM.ADR(a), whence);
  IF b=0 THEN RETURN a[0] END;
  RETURN b
END LSeek0;

PROCEDURE FLock0*( fd, arg: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 32);        (* Syscall nr to R2 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END FLock0;

PROCEDURE Ftruncate640*( fd, lenLo, lenHi: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 46);        (* ftruncate64 of RV32: the length in A1 (low), A2 (high) *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Ftruncate640;

(* polpo: was system call 64, which is write on RISC-V *)
PROCEDURE Ftruncate0*( fd, len: LONGINT): LONGINT;
BEGIN
  RETURN Ftruncate640( fd, len, 0)
END Ftruncate0;

PROCEDURE UTimensat0*( dirfd, name, utimebuf, flags: LONGINT):LONGINT;
VAR t: ARRAY 2 OF Timespec64; i, p: LONGINT;
BEGIN
  p := 0;
  IF utimebuf # 0 THEN  (* two 32-bit struct timespec to struct __kernel_timespec *)
    FOR i := 0 TO 1 DO
      SYSTEM.GET( utimebuf+8*i, t[i].sec); SYSTEM.GET( utimebuf+8*i+4, t[i].nsec);
      IF t[i].sec < 0 THEN t[i].sech := -1 ELSE t[i].sech := 0 END;
      t[i].nsech := 0
    END;
    p := SYSTEM.ADR(t[0])
  END;
  RETURN UTimensatT64( dirfd, name, p, flags)
END UTimensat0;

PROCEDURE GetTimeOfDay*(tv, tz: LONGINT): LONGINT;
VAR ts: Timespec64; r: LONGINT;
BEGIN
  r := ClockGettime64( 0 (* CLOCK_REALTIME *), SYSTEM.ADR(ts));
  IF (r = 0) & (tv # 0) THEN SYSTEM.PUT( tv, ts.sec); SYSTEM.PUT( tv+4, ts.nsec DIV 1000) END;
  RETURN r
END GetTimeOfDay;

PROCEDURE Renameat0*( olddfd, old, newdfd, new, flags: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 276);        (* renameat2: RISC-V has no renameat (38) *)
  SYSTEM.CODE( LWr14);            (* polpo: flags, argument 5, from the stack (was garbage: EINVAL) *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Renameat0;

PROCEDURE Mkdirat0*( dfd, name, mode: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 34);        (* mkdirat: Syscall nr to A7 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Mkdirat0;

(* RISC-V has no mkdir: mkdirat in the current directory (polpo: the path and the mode move to
   A1, A2, so not with registers here) *)
PROCEDURE MkDir0*( name, mode: LONGINT): LONGINT;
BEGIN
  RETURN Mkdirat0( ATFDCWD, name, mode)
END MkDir0;

PROCEDURE ChDir0*( name: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 49);        (* chdir: Syscall nr to A7 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END ChDir0;

PROCEDURE UnLinkat0*( dfd, name, flags: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 35);        (* unlinkat!! Syscall nr to R2 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END UnLinkat0;

PROCEDURE Mremap0*( oldaddr, oldsize, newsize, flags, naddr: LONGINT): LONGINT;
(* MREMAP_MAYMOVE=1 *)
BEGIN
  SYSTEM.PUTREG( NRR, 216);        (* Syscall nr to R2 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Mremap0;

PROCEDURE FStatat0*( dfd, name, stat, flags: LONGINT): LONGINT;
VAR b: ARRAY 64 OF LONGINT; r: LONGINT;
BEGIN
  r := Statx( dfd, name, flags, 7FFH (* STATX_BASIC_STATS *), SYSTEM.ADR(b));
  IF r = 0 THEN StatxToStatus( b, stat) END;
  RETURN r
END FStatat0;

PROCEDURE GetDents0*( fd, bufptr, count: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 61);        (* Syscall nr to R2 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END GetDents0;

PROCEDURE Socket0*( domain, type, protocol: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 198);        (* was 41, 198 Syscall nr to R2 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Socket0;

PROCEDURE Connect0*( sockfd, servaddr, addrlen: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 203);        (* was 203 Syscall nr to R2 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Connect0;

PROCEDURE Shmget0*( key, size, shmflag: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 194);        (* Syscall nr to R2 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Shmget0;

PROCEDURE Shmat0*(shmid, addr, flags: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 196);        (* Syscall nr to R2 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Shmat0;

PROCEDURE Shmdt0*(addr: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 197);        (* Syscall nr to R2 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Shmdt0;

PROCEDURE ShmCtl0*(buf, cmd, shmid: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 195);        (* Syscall nr to R2 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END ShmCtl0;

PROCEDURE IOCtl0*( d, r1, r2: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 29);        (* Syscall nr to R2 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END IOCtl0;

PROCEDURE Select0*( n, readfds, writefds, execptfds, timeout: LONGINT): LONGINT;
VAR ts: Timespec64; usec, p: LONGINT;
BEGIN
  p := 0;
  IF timeout # 0 THEN  (* struct timeval to struct __kernel_timespec *)
    SYSTEM.GET( timeout, ts.sec); SYSTEM.GET( timeout+4, usec);
    IF ts.sec < 0 THEN ts.sech := -1 ELSE ts.sech := 0 END;
    ts.nsec := usec*1000; ts.nsech := 0; p := SYSTEM.ADR(ts)
  END;
  RETURN PSelect6T64( n, readfds, writefds, execptfds, p)
END Select0;

(* Linux0.Fixup and  MBootLinker.FixupV are same, don't optimize as in VDecoder.Obj  *)
PROCEDURE Fixup*( base, entry, L: LONGINT; data: BOOLEAN);  
CONST (* instruction format *)
  LB=3H; ADDI= 13H; SB=23H; LUI=37H; JALR=67H; JAL=6FH;
  IMM12=1000H;
VAR L1, c1, c2: LONGINT;
BEGIN
  IF (entry#0) & (L # 0) THEN
    REPEAT
      L1 := L; SYSTEM.GET( base+L1*4, c1);
      IF c1 MOD 80H= JAL THEN  (* procedure call, UJ format *)  (* to be fixed in OPL.Exit, adjustLink ? *)
        L := L1 + ASH(ASH( c1, -31), 18)+ASH( c1, -22) MOD 200H+ASH( ASH(c1, -20) MOD 2, 9)+ASH( ASH(c1, -12) MOD 100H, 10)+1;
        SYSTEM.PUT( base+L1*4, LUI+ASH(T2, 7)+ASH( ASH(entry,-12)  +ASH( entry, -11) MOD 2, 12)); 
        SYSTEM.PUT( base+L1*4+4, JALR+ASH(LR, 7)+ASH(T2, 15)+ASH( entry MOD IMM12, 20));
      ELSE
        L := L1  + ASH(c1, -15)+1;
        SYSTEM.GET( base+L1*4+4, c2); INC(c2, entry);
        SYSTEM.PUT( base+L1*4, LUI+ASH(T2, 7)+ASH( ASH(c2,-12)  +ASH( c2, -11) MOD 2, 12)); 
        IF c1 MOD 80H DIV 8 = SB DIV 8 THEN  (* store, store fp *)
          SYSTEM.PUT( base+L1*4+4, c1 MOD 80H +ASH( c2 MOD 20H, 7)+ASH(ASH( c1, -12) MOD 8H, 12)+
            ASH( T2, 15) +ASH(ASH(c1, -7) MOD 20H, 20)+ ASH( ASH( c2, -5) MOD 80H , 25));  (* s-type *)
        ELSE                            (* load, loadfp, addi *)
          SYSTEM.PUT( base+L1*4+4, ASH( c2 MOD 1000H, 20)+ ASH( T2, 15)+c1 MOD 8000H);
        END;
      END;
    UNTIL (L = L1) (*OR (L<0) OR (L>LEN(m.code^))*)
  END
END Fixup;

PROCEDURE SetSignal*( nr: LONGINT; handler: Proc): LONGINT;
TYPE
  SigAction = RECORD
    handler: Proc;
    flags, mask: SET;
    restorer: Proc;
  END;
VAR h: SigAction;
BEGIN
  h.handler:= handler;
  h.flags:={ 30};  (* was{ 30, 2}30=SA_NODEFER, 28=SARESTART, 26=RESTORER 2=SIGINFO?*)
  h.mask:={}; h.restorer:=NIL;
  RETURN SIGAction0( nr, SYSTEM.ADR(h), 0);
END SetSignal;

PROCEDURE CopyRegs*( sc: SigContext);
VAR i: LONGINT;
BEGIN
  i:=32;
  REPEAT
    DEC(i);
    Regs[i]:=sc.regs[i];
    FRegs[i]:=sc.fpregs[i];
    FRegs[i+32]:=sc.fpregs[i+32];
  UNTIL i=0;
END CopyRegs;

(* polpo: sockets, direct system calls (not socketcall); data also with Read0/Write0 *)

PROCEDURE Bind0*( fd, addr, len: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 200);
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Bind0;

PROCEDURE Listen0*( fd, backlog: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 201);
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Listen0;

PROCEDURE Accept40*( fd, addr, lenadr, flags: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 242);
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Accept40;

PROCEDURE GetSockName0*( fd, addr, lenadr: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 204);
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END GetSockName0;

PROCEDURE GetPeerName0*( fd, addr, lenadr: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 205);
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END GetPeerName0;

PROCEDURE SetSockOpt0*( fd, level, name, val, len: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 208);
  SYSTEM.CODE( LWr14);    (* 5th parameter from sp+16 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END SetSockOpt0;

PROCEDURE GetSockOpt0*( fd, level, name, val, lenadr: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 209);
  SYSTEM.CODE( LWr14);    (* 5th parameter from sp+16 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END GetSockOpt0;

PROCEDURE Shutdown0*( fd, how: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 210);
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END Shutdown0;

PROCEDURE SendTo0*( fd, buf, len, flags, addr, addrlen: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 206);
  SYSTEM.CODE( LWr14);    (* 5th parameter from sp+16 *)
  SYSTEM.CODE( LWr15);    (* 6th parameter from sp+20 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END SendTo0;

PROCEDURE RecvFrom0*( fd, buf, len, flags, addr, lenadr: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( NRR, 207);
  SYSTEM.CODE( LWr14);    (* 5th parameter from sp+16 *)
  SYSTEM.CODE( LWr15);    (* 6th parameter from sp+20 *)
  SYSTEM.CODE( ECALL);
  SYSTEM.CODE( JALR);
END RecvFrom0;

END Linux0.

