AsciiCoder, files and texts as plain ASCII, for mail, and back

In the console (package asciicoder):
asciicoder.Code [%] out.txt file ...   codes the files into the plain file
                                       out.txt (% compresses them first)
asciicoder.Decode in.txt [dir]         the files of such a text, into dir

In the desktop (package asciicoder-desktop):
AsciiCoder.CodeFiles file ... ~    the code of the files in a viewer
AsciiCoder.CodeFiles ^             the files of the selected list
AsciiCoder.DecodeFiles @           writes the files of the code starting at
                                   the selection (their names precede it)
AsciiCoder.CodeText *              the text of the marked viewer, coded
AsciiCoder.CodeText @              the selected text, coded
AsciiCoder.DecodeText @            the text coded from the selection, in a
                                   viewer
A % after the command name compresses (expands) as well:
AsciiCoder.CodeFiles % file ... ~    AsciiCoder.DecodeFiles % @

The code is the same in both: the console reads what the desktop wrote and
the other way round, and both read the AsciiCoder texts of ETH Oberon. A coded
text starts with the line "AsciiCoder.DecodeFiles [%] file ... ~".
