MODULE Linux0;  (* rc/ard/nm/jm/devil/pjm/rml*)

(* Linux interface for PowerPC (32-bit, big-endian) *)

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

(*  polpo: made from the MIPS and RISC-V Linux0 (Peter Matthias 2015-2016).

  A system call: the number in r0, the arguments in r3..r8, sc; on an error CR0.SO is set and
  r3 holds the positive error number. The stubs return -errno then, as on the other ports:
    li r0, nr; sc; bnslr; neg r3, r3; blr
  The compiler passes 4 arguments in r3..r6 and the others on the stack, from sp+16: the
  stubs with 5 or 6 arguments load r7 and r8 from there (the stubs are leaf procedures
  without a frame).

  Syscall numbers in arch/powerpc/kernel/syscalls/syscall.tbl of the Linux sources.
*)

IMPORT SYSTEM;

CONST
  ARCH*="PPC";
  ObjPrefix*="ppc/";
  StatModeOfs* = 16;  (** the offset of st_mode in Status (struct stat64) *)
  ObjTag*=36F7H;  (* x86: 0AFX; arml: 0F5X; arm: 36FBH; mips: 36F9H; mipsbe: 36F8H; ppc: 36F7H *)
  RegSize*=32;
  PageSize*=1000H;

  SC=44000002H; BNSLR=4C830020H; NEG3=7C6300D0H; BLR=4E800020H;  (* sc; bnslr; neg r3, r3; blr *)
  LWr7=80E10010H; LWr8=81010014H;  (* lwz r7, 16(r1); lwz r8, 20(r1) *)
  XTRAP*=0FE00000H;  (* twi 31, r0, nr: the traps of the compiler, nr in the low 16 bits *)

  (* registers for PowerPC *)
  SP*=1; FP*=31; LR*=0; ARI*=3;  (* LR: the return address is in r0 while a procedure saves it *)

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

  (* Termios used in Input (FB): the PowerPC numbers; c_cc starts at offset 16 *)
  VMIN*=4;  (* the index of c_cc[VMIN] (5) in the c_cc of TermIOs records, which have c_line first *)
  TCGETS*= 402C7413H;
  TCSETSF*=802C7416H;

  (** Socket *)
  SOCKSTREAM*=1;

  SIGHUP= 1;    (* Hang up ; X11 quits *)
  SIGINT*= 2;      (* interrupt   ctrl-c *)
  SIGQUIT= 3;    (* quit *)
  SIGILL* = 4;      (* invalid instruction *)
  SIGTRAP*= 5;    (* twi: the traps of the compiler, HALT *)
  SIGABRT= 6;
  SIGBUS=7;
  SIGFPE* = 8;
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

  Status* = RECORD  (* struct stat64 of PowerPC, big-endian: the high word of a 64-bit field first *)
    stdevh, stdev, stinoh, stino: LONGINT;  (* 0 *)
    stmode, stnlink, stuid, stgid: LONGINT;  (* 16 *)
    rdevh, rdev, pad1, pad2: LONGINT;  (* 32 *)
    sizeh, size*, blksize*, pad3: LONGINT;  (* 48 *)
    blocksh, blocks*, atime*, atimens: LONGINT;  (* 64 *)
    mtime*, mtimens, ctime*, ctimens: LONGINT;  (* 80 *)
    pad4: ARRAY 16 OF LONGINT
  END;

  SockAddrUn*= RECORD
    pf*: INTEGER;
    path*: ARRAY 64 OF CHAR;
  END;

  (* the ucontext the kernel passes to a SA_SIGINFO handler: uc_flags, uc_link, uc_stack, uc_pad,
     uc_regs, uc_sigmask, uc_maskext, uc_pad2 (192 bytes), then uc_mcontext: 48 general
     registers (r0..r31, nip, msr, orig_r3, ctr, link, xer, ccr, mq, trap, dar, dsisr, result),
     the floating point registers and fpscr *)
  SigContext*= POINTER TO RECORD
    dummy: ARRAY 48 OF LONGINT;
    regs*: ARRAY 32 OF LONGINT;
    pc*, msr, origr3, ctr, lnk*, xer, ccr, mq, trap, dar*, dsisr, result: LONGINT;
    gpad: ARRAY 4 OF LONGINT;
    fpregs*: ARRAY 66 OF LONGINT;
  END;

  SigInfo*= POINTER TO RECORD
    signo*, errno*, code*, adr*: LONGINT;
  END;

VAR
  break*: BOOLEAN;  (** has ctrl-break been pressed? set by Kernel *)
  StackOrg*: LONGINT;  (** highest address on stack (single-process system); set by Kernel *)
  Regs*: ARRAY 32 OF LONGINT;
  FRegs*: ARRAY 64 OF LONGINT;

PROCEDURE Exit0*(status: LONGINT);
BEGIN
  SYSTEM.PUTREG( 0, 234);  (* exit_group *)
  SYSTEM.CODE( SC)
END Exit0;

PROCEDURE Fork0*():LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 2);  (* fork *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Fork0;

PROCEDURE Execve0*( filename, argv, envp: LONGINT):LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 11);  (* execve *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Execve0;

PROCEDURE Waitpid0*( pid, status, options: LONGINT):LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 7);  (* waitpid *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Waitpid0;

PROCEDURE StoreRegs*( adr: LONGINT);  (* register n to adr+4*n, for the stack scan of Kernel.GC *)
BEGIN
  SYSTEM.CODE( 0BC230004H);  (* stmw r1, 4(r3) *)
  SYSTEM.CODE( BLR)
END StoreRegs;

PROCEDURE SIGAction0( signum, act, oldact: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 173);  (* rt_sigaction *)
  SYSTEM.PUTREG( 6, 8);  (* the size of the signal mask *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END SIGAction0;

PROCEDURE CacheFlush0*( adr, bytes: LONGINT): LONGINT;  (* new code in the instruction cache *)
BEGIN
  SYSTEM.CODE( 7C832214H);  (* add r4, r3, r4: the end *)
  SYSTEM.CODE( 54630034H);  (* rlwinm r3, r3, 0, 0, 26: down to a 32-byte line *)
  SYSTEM.CODE( 7C00186CH);  (* loop: dcbst 0, r3 *)
  SYSTEM.CODE( 7C0004ACH);  (* sync *)
  SYSTEM.CODE( 7C001FACH);  (* icbi 0, r3 *)
  SYSTEM.CODE( 38630020H);  (* addi r3, r3, 32 *)
  SYSTEM.CODE( 7C032040H);  (* cmplw r3, r4 *)
  SYSTEM.CODE( 4180FFECH);  (* blt loop *)
  SYSTEM.CODE( 7C0004ACH);  (* sync *)
  SYSTEM.CODE( 4C00012CH);  (* isync *)
  SYSTEM.CODE( 38600000H);  (* li r3, 0 *)
  SYSTEM.CODE( BLR)
END CacheFlush0;

PROCEDURE Openat0*( dfd, name, flags, mode: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 286);  (* openat *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Openat0;

PROCEDURE Readlinkat0*( dfd, name, buf, bufsiz: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 296);  (* readlinkat *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Readlinkat0;

PROCEDURE Close0*( fd: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 6);  (* close *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Close0;

PROCEDURE Fsync0*( fd: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 118);  (* fsync: write the file's data to the disk *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Fsync0;

PROCEDURE Read0*( fd, buf, num: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 3);  (* read *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Read0;

PROCEDURE Readv0*( fd, vect, cnt: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 145);  (* readv *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Readv0;

PROCEDURE Write0*( fd, buf, num: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 4);  (* write *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Write0;

PROCEDURE Writev0*( fd, vect, cnt: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 146);  (* writev *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Writev0;

PROCEDURE Brk0*( adr: LONGINT):LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 45);  (* brk *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Brk0;

PROCEDURE MProtect0*( adr, len, prot: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 125);  (* mprotect *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END MProtect0;

PROCEDURE FStat0*( fd, stat: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 197);  (* fstat64 *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END FStat0;

PROCEDURE Mmap20*( addr, len, prot, flags, fd, off: LONGINT):LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 192);  (* mmap2: the offset in pages *)
  SYSTEM.CODE( LWr7);  (* the 5th argument from the stack *)
  SYSTEM.CODE( LWr8);  (* the 6th *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Mmap20;

PROCEDURE Munmap0*( addr, len: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 91);  (* munmap *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Munmap0;

PROCEDURE LSeek0*( fd, pos, whence: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 19);  (* lseek *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END LSeek0;

PROCEDURE FLock0*( fd, arg: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 143);  (* flock *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END FLock0;

PROCEDURE Ftruncate0*( fd, len: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 93);  (* ftruncate *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Ftruncate0;

PROCEDURE UTimensat0*( dirfd, name, utimebuf, flags: LONGINT):LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 304);  (* utimensat *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END UTimensat0;

PROCEDURE GetTimeOfDay*( tv, tz: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 78);  (* gettimeofday *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END GetTimeOfDay;

PROCEDURE Renameat0*( olddfd, old, newdfd, new, flags: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 357);  (* renameat2 *)
  SYSTEM.CODE( LWr7);  (* the 5th argument from the stack *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Renameat0;

PROCEDURE MkDir0*( name, mode: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 39);  (* mkdir *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END MkDir0;

PROCEDURE Mkdirat0*( dirfd, name, mode: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 287);  (* mkdirat: a directory relative to dirfd *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Mkdirat0;

PROCEDURE Fchmodat0*( dirfd, name, mode: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 297);  (* fchmodat: the permissions of name relative to dirfd *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Fchmodat0;

PROCEDURE ChDir0*( name: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 12);  (* chdir *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END ChDir0;

PROCEDURE UnLinkat0*( dirfd, name, flags: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 292);  (* unlinkat *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END UnLinkat0;

PROCEDURE Mremap0*( oldaddr, oldsize, newsize, flags, naddr: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 163);  (* mremap, MREMAP_MAYMOVE = 1 *)
  SYSTEM.CODE( LWr7);  (* the 5th argument from the stack *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Mremap0;

PROCEDURE FStatat0*( dirfd, name, stat, flags: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 291);  (* fstatat64 *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END FStatat0;

PROCEDURE GetDents0*( fd, bufptr, count: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 202);  (* getdents64 *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END GetDents0;

PROCEDURE Socket0*( domain, type, protocol: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 326);  (* socket *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Socket0;

PROCEDURE Connect0*( sockfd, servaddr, addrlen: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 328);  (* connect *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Connect0;

PROCEDURE Shmget0*( key, size, shmflag: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 395);  (* shmget *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Shmget0;

PROCEDURE Shmat0*( shmid, addr, flags: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 397);  (* shmat *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Shmat0;

PROCEDURE Shmdt0*( addr: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 398);  (* shmdt *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Shmdt0;

PROCEDURE ShmCtl0*( buf, cmd, shmid: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 396);  (* shmctl: shmid, cmd, buf in this order *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END ShmCtl0;

PROCEDURE IOCtl0*( d, r1, r2: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 54);  (* ioctl *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END IOCtl0;

PROCEDURE Mount0*( src, target, type, flags, data: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 21);  (* mount *)
  SYSTEM.CODE( LWr7);  (* the 5th argument from the stack *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Mount0;

PROCEDURE FinitModule0*( fd, params, flags: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 353);  (* finit_module *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END FinitModule0;

PROCEDURE Setsid0*(): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 66);  (* setsid *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Setsid0;

PROCEDURE Sync0*(): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 36);  (* sync *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Sync0;

PROCEDURE Reboot0*( magic1, magic2, cmd, arg: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 88);  (* reboot *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Reboot0;

PROCEDURE Select0*( n, readfds, writefds, execptfds, timeout: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 142);  (* _newselect *)
  SYSTEM.CODE( LWr7);  (* the 5th argument from the stack *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Select0;

PROCEDURE Bind0*( fd, addr, len: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 327);  (* bind *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Bind0;

PROCEDURE Listen0*( fd, backlog: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 329);  (* listen *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Listen0;

PROCEDURE Accept40*( fd, addr, lenadr, flags: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 344);  (* accept4 *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Accept40;

PROCEDURE GetSockName0*( fd, addr, lenadr: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 331);  (* getsockname *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END GetSockName0;

PROCEDURE GetPeerName0*( fd, addr, lenadr: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 332);  (* getpeername *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END GetPeerName0;

PROCEDURE SetSockOpt0*( fd, level, name, val, len: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 339);  (* setsockopt *)
  SYSTEM.CODE( LWr7);  (* the 5th argument from the stack *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END SetSockOpt0;

PROCEDURE GetSockOpt0*( fd, level, name, val, lenadr: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 340);  (* getsockopt *)
  SYSTEM.CODE( LWr7);  (* the 5th argument from the stack *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END GetSockOpt0;

PROCEDURE Shutdown0*( fd, how: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 338);  (* shutdown *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END Shutdown0;

PROCEDURE SendTo0*( fd, buf, len, flags, addr, addrlen: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 335);  (* sendto *)
  SYSTEM.CODE( LWr7);  (* the 5th argument from the stack *)
  SYSTEM.CODE( LWr8);  (* the 6th *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END SendTo0;

PROCEDURE RecvFrom0*( fd, buf, len, flags, addr, lenadr: LONGINT): LONGINT;
BEGIN
  SYSTEM.PUTREG( 0, 337);  (* recvfrom *)
  SYSTEM.CODE( LWr7);  (* the 5th argument from the stack *)
  SYSTEM.CODE( LWr8);  (* the 6th *)
  SYSTEM.CODE( SC); SYSTEM.CODE( BNSLR); SYSTEM.CODE( NEG3); SYSTEM.CODE( BLR)
END RecvFrom0;
(* Linux0.Fixup and rlinker.FixupP are the same: see the top of POPL for the two linked words *)
PROCEDURE Fixup*( base, entry, L: LONGINT; data: BOOLEAN);
CONST T2=12; ADDIS=3C000000H; ADDI=38000000H; MTCTR=7C0903A6H; BCTRL=4E800421H;
VAR L1, c1, c2, a, d: LONGINT;
BEGIN
  IF (entry#0) & (L # 0) THEN
    REPEAT
      L1 := L; SYSTEM.GET( base+L1*4, c1);
      IF c1 DIV 4000000H MOD 64 = 18 THEN  (* bl: a call into another module *)
        d := c1 MOD 4000000H DIV 4; IF d >= 800000H THEN DEC(d, 1000000H) END;
        L := L1 + d + 1; a := entry;
        SYSTEM.PUT( base+L1*4, ADDIS + ASH(T2, 21) + ASH(a + 8000H, -16) MOD 10000H);
        SYSTEM.PUT( base+L1*4+4, ADDI + ASH(T2, 21) + ASH(T2, 16) + a MOD 10000H);
        SYSTEM.PUT( base+L1*4+8, MTCTR + ASH(T2, 21));
        SYSTEM.PUT( base+L1*4+12, BCTRL)
      ELSE  (* load, store, addi with the offset in the next word *)
        d := c1 MOD 10000H; IF d >= 8000H THEN DEC(d, 10000H) END;
        L := L1 + d + 1;
        SYSTEM.GET( base+L1*4+4, c2); a := entry + c2;
        SYSTEM.PUT( base+L1*4, ADDIS + ASH(T2, 21) + ASH(a + 8000H, -16) MOD 10000H);
        SYSTEM.PUT( base+L1*4+4, c1 - c1 MOD 200000H + ASH(T2, 16) + a MOD 10000H)
      END
    UNTIL L = L1
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
  h.flags:={ 2, 30};  (* SA_SIGINFO (siginfo and ucontext in r4, r5), SA_NODEFER *)
  h.restorer:=NIL; h.mask:={}; h.mask2:={};
  RETURN SIGAction0( nr, SYSTEM.ADR(h), 0);
END SetSignal;

PROCEDURE CopyRegs*( sc: SigContext);
VAR i: LONGINT;
BEGIN
  i:=32;
  REPEAT
    DEC(i);
    IF i = LR THEN Regs[i]:=sc.lnk ELSE Regs[i]:=sc.regs[i] END;  (* the return address of a leaf procedure; others save r0 *)
    FRegs[2*i]:=sc.fpregs[2*i];
    FRegs[2*i+1]:=sc.fpregs[2*i+1];
  UNTIL i=0;
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
CONST FIONBIO = 8004667EH;
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
