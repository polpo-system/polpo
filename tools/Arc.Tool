Arc, the Oberon archives (.Arc of Compress, ETH Oberon System 3) in polpo

arc.Directory archive.Arc            the entries: name, compressed length, date
arc.Add archive.Arc file ...         adds or replaces files (LZSS); creates the archive
arc.Extract archive.Arc [file ...]   the named entries, or all of them
arc.Delete archive.Arc file ...      removes entries
arc.Create archive.Arc               an empty archive

Names have at most 31 characters. Entries that would land outside the current
directory (an absolute name, a ".." component) are skipped.

Encrypted archives

Add and Extract take a cipher before the archive:
  \C module.Command "key"

arc.Add \C CompressCrypt.Install "my key" secret.Arc notes.Text ~
arc.Extract \C CompressCrypt.Install "my key" secret.Arc ~
arc.Directory secret.Arc     (shows which entries are encrypted)

Without the key, an encrypted entry is refused ("a key is needed").

How the cipher plugs in: Compress0 does not import any cipher. It has two
procedure variables,
  Compress0.Encrypt, Compress0.Decrypt: Compress0.CryptProc
  CryptProc = PROCEDURE (VAR Rin: Files.Rider; nIn: LONGINT;
    VAR Rout: Files.Rider; key: ARRAY OF CHAR; VAR res: INTEGER)
and Compress0.InstallCrypt("module.Command", key) loads the module by name
(Modules.ThisMod), calls the command (Modules.ThisCommand), and keeps the key.
The command only sets the two variables. Compress0 calls Encrypt on the
compressed data of each entry it adds, and Decrypt on the data of each
encrypted entry it reads, with the key. The entry is marked encrypted in the
archive; the cipher's name is not stored, so whoever extracts must know it.

So a new cipher is a module of its own, compiled and installed separately,
with nothing to change in Compress0, arc or the archives:

  MODULE MyCrypt;
  IMPORT Files, Compress0;
  PROCEDURE Decrypt(VAR Rin: Files.Rider; nIn: LONGINT; VAR Rout: Files.Rider;
      key: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN (* nIn bytes from Rin, deciphered, to Rout *) res := Compress0.Done
  END Decrypt;
  PROCEDURE Encrypt(...);  (* the same, the other way *)
  PROCEDURE Install*;
  BEGIN Compress0.Decrypt := Decrypt; Compress0.Encrypt := Encrypt
  END Install;
  END MyCrypt.

  arc.Add \C MyCrypt.Install "key" archive.Arc file ~

The ciphers in polpo (toy ciphers, for compatibility, not for secrecy):
  CompressCrypt.Install   ETH System 3: each byte minus (decrypting: plus) a
                          character of the key
  Crypt0.Install          Crypt0 of the Voyager project (Heidelberg): a Park-
                          Miller stream seeded and stepped with the key
  Crypt0.InstallMod       the same stream over the whole key (oarc -c mod)
  Crypt0.InstallXor       the stream XOR the bytes (oarc -c xor)

oarc (github.com/norayr/oarc) does the same in the shell with voc:
  oarc add archive.Arc -c heidelberg -e "key" file   = Crypt0.Install
  oarc extract archive.Arc -c mod -e "key"           = Crypt0.InstallMod

In System 3 the desktop command takes the same option:
  Compress.Add \C CompressCrypt.Install "key" archive.Arc file ~
