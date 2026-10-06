Tar, tar archives, plain or gzip compressed

tar.List archive               the entries and their sizes
tar.Pack archive path ...      the files, and the directories with everything in
                               them, into a new archive; gzip compressed when the
                               name ends with .gz or .tgz
tar.Unpack archive dir [n]     files and directories into dir, without the first
                               n components of their paths

Unpack reads an archive that starts as a gzip file (.tar.gz, .tgz) through
GZReaders. Ustar, the pax headers of GitHub and GNU long names are understood;
links and devices are skipped, and so are entries that would land outside dir.
The archives of GitHub put everything in name-branch/: n = 1 drops it.
Pack writes ustar (GNU long names for longer paths), for tar and tar -z.

tar.Pack notes.tgz Notes ~
tar.List master.tar.gz ~
tar.Unpack master.tar.gz arden 1 ~
