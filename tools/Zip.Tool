Zip, zip archives (deflate) with Zip of ETH Oberon

In the console (package zip):
zip.Directory archive.zip             the entries: name, size, compressed size
zip.Add archive.zip file ...          adds files; creates the archive
zip.Extract archive.zip [file ...]    the named entries, or all; directories
                                      are made, entries outside the current
                                      directory are skipped
zip.Delete archive.zip file ...       removes entries

The archives are those of zip and unzip (deflated or stored, no encryption).

In the desktop (package zip-desktop):
ZipTool.Directory archive.zip ~      ZipTool.Directory \d archive.zip ~
ZipTool.Add [\level [\strategy]] archive.zip file ... ~
                                      level 0 (stored) .. 9 (best),
                                      strategy 0 .. 2
ZipTool.Extract [\o] archive.zip file ... ~   \o overwrites existing files,
ZipTool.ExtractAll [\o] archive.zip ... ~     otherwise they become .Bak
ZipTool.Delete archive.zip file ... ~
ZipTool.Open archive.zip ~            the directory in a viewer
