MODULE unixNet;  (** the system calls of voc's module unixNet, on polpo's Linux0: modules shared with voc
  (Sockets, DNS, Internet, NetSystem, the tls modules) import unixNet on both systems *)

IMPORT Linux0;

CONST
  ARCH* = Linux0.ARCH;
  ATFDCWD* = Linux0.ATFDCWD;
  ORDonly* = Linux0.ORDonly;

PROCEDURE GetTimeOfDay*(tv, tz: LONGINT): LONGINT;
BEGIN RETURN Linux0.GetTimeOfDay(tv, tz)
END GetTimeOfDay;

PROCEDURE Select0*(n, readfds, writefds, exceptfds, timeout: LONGINT): LONGINT;
BEGIN RETURN Linux0.Select0(n, readfds, writefds, exceptfds, timeout)
END Select0;

PROCEDURE Openat0*(dirfd, name, flags, mode: LONGINT): LONGINT;
BEGIN RETURN Linux0.Openat0(dirfd, name, flags, mode)
END Openat0;

PROCEDURE Close0*(fd: LONGINT): LONGINT;
BEGIN RETURN Linux0.Close0(fd)
END Close0;

PROCEDURE Read0*(fd, buf, num: LONGINT): LONGINT;
BEGIN RETURN Linux0.Read0(fd, buf, num)
END Read0;

PROCEDURE Write0*(fd, buf, num: LONGINT): LONGINT;
BEGIN RETURN Linux0.Write0(fd, buf, num)
END Write0;

PROCEDURE Socket0*(domain, type, protocol: LONGINT): LONGINT;
BEGIN RETURN Linux0.Socket0(domain, type, protocol)
END Socket0;

PROCEDURE SocketNonblocking0*(domain, type, protocol: LONGINT): LONGINT;
BEGIN RETURN Linux0.SocketNonblocking0(domain, type, protocol)
END SocketNonblocking0;

PROCEDURE AcceptNonblocking0*(fd, addr, lenadr: LONGINT): LONGINT;
BEGIN RETURN Linux0.AcceptNonblocking0(fd, addr, lenadr)
END AcceptNonblocking0;

PROCEDURE Pending0*(result: LONGINT): BOOLEAN;
BEGIN RETURN Linux0.Pending0(result)
END Pending0;

PROCEDURE WouldBlock0*(result: LONGINT): BOOLEAN;
BEGIN RETURN Linux0.WouldBlock0(result)
END WouldBlock0;

PROCEDURE Interrupted0*(result: LONGINT): BOOLEAN;
BEGIN RETURN Linux0.Interrupted0(result)
END Interrupted0;

PROCEDURE SocketError0*(fd: LONGINT): LONGINT;
BEGIN RETURN Linux0.SocketError0(fd)
END SocketError0;

PROCEDURE Abortive0*(fd: LONGINT): LONGINT;
BEGIN RETURN Linux0.Abortive0(fd)
END Abortive0;

PROCEDURE Poll0*(fd: LONGINT; write: BOOLEAN; ms: LONGINT): LONGINT;
BEGIN RETURN Linux0.Poll0(fd, write, ms)
END Poll0;

PROCEDURE SetBlocking0*(fd: LONGINT; blocking: BOOLEAN): LONGINT;
BEGIN RETURN Linux0.SetBlocking0(fd, blocking)
END SetBlocking0;

PROCEDURE Connect0*(fd, addr, len: LONGINT): LONGINT;
BEGIN RETURN Linux0.Connect0(fd, addr, len)
END Connect0;

PROCEDURE Bind0*(fd, addr, len: LONGINT): LONGINT;
BEGIN RETURN Linux0.Bind0(fd, addr, len)
END Bind0;

PROCEDURE Listen0*(fd, backlog: LONGINT): LONGINT;
BEGIN RETURN Linux0.Listen0(fd, backlog)
END Listen0;

PROCEDURE Accept40*(fd, addr, lenadr, flags: LONGINT): LONGINT;
BEGIN RETURN Linux0.Accept40(fd, addr, lenadr, flags)
END Accept40;

PROCEDURE GetSockName0*(fd, addr, lenadr: LONGINT): LONGINT;
BEGIN RETURN Linux0.GetSockName0(fd, addr, lenadr)
END GetSockName0;

PROCEDURE GetPeerName0*(fd, addr, lenadr: LONGINT): LONGINT;
BEGIN RETURN Linux0.GetPeerName0(fd, addr, lenadr)
END GetPeerName0;

PROCEDURE SetSockOpt0*(fd, level, name, val, len: LONGINT): LONGINT;
BEGIN RETURN Linux0.SetSockOpt0(fd, level, name, val, len)
END SetSockOpt0;

PROCEDURE GetSockOpt0*(fd, level, name, val, lenadr: LONGINT): LONGINT;
BEGIN RETURN Linux0.GetSockOpt0(fd, level, name, val, lenadr)
END GetSockOpt0;

PROCEDURE Shutdown0*(fd, how: LONGINT): LONGINT;
BEGIN RETURN Linux0.Shutdown0(fd, how)
END Shutdown0;

PROCEDURE SendTo0*(fd, buf, len, flags, addr, addrlen: LONGINT): LONGINT;
BEGIN RETURN Linux0.SendTo0(fd, buf, len, flags, addr, addrlen)
END SendTo0;

PROCEDURE RecvFrom0*(fd, buf, len, flags, addr, lenadr: LONGINT): LONGINT;
BEGIN RETURN Linux0.RecvFrom0(fd, buf, len, flags, addr, lenadr)
END RecvFrom0;

END unixNet.
