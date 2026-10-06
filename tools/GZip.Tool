GZip, gzip files (RFC 1952) with the zlib of ETH Oberon

gzip.Compress file [file.gz]     compresses (default output: file.gz)
gzip.Decompress file.gz [file]   decompresses (default output: the name
                                 without .gz)

The files are those of gzip, gunzip and tar -z. GZReaders and GZWriters do
the work and can be used by other modules: a GZReaders.Reader reads the plain
bytes of a .gz file, a GZWriters.Writer writes them compressed.

gzip.Compress notes.Text ~
gzip.Decompress notes.Text.gz notes2.Text ~
