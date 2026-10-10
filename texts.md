# Reading the Configuration: Oberon.Text

Oberon.Text is the configuration text of the system. The desktop reads System.FontScale,
System.LineSpacing, System.InitCommands and the other settings from it, and any program can keep
settings of its own there and read them in the same way. This note shows how the text is written
and how a module reads it.

## The text

Oberon.Text is a list of entries of the form Name = value. A value is a number, a name, a string
in quotes, or a group in braces, which holds more entries or a list of items. Comments are written
between {* and *}. Here is the beginning of the System section, and a section a tool of your own
might have:

    System = {
      FontScale = 150  {* screen font scale in percent *}
      LineSpacing = 150
      InitCommands = { { System.OpenLog } { System.Open System.Tool } }
    }

    MyTool = {
      Size = 10
      Host = "example.org"
      Colors = { red green blue }
    }

Oberon.Text may be a plain text or an Oberon text. It is found through the file search path: in
the current directory first, then in polpo's directory (and share/ and tools/). So a copy in the
current directory overrides the one of polpo, which is handy for trying settings without
changing the real one.

## The scanner

A module asks for a value with a scanner, an ordinary Texts.Scanner:

    Oberon0.OpenScanner(S, "Section.Key")   (* console modules, src/common/Oberon0.Mod *)
    Oberon.OpenScanner(S, "Section.Key")    (* desktop modules; it calls Oberon0.OpenScanner *)

The key is a dotted path through the groups, to any depth, as "Printer.LPRPrinter.Resolution".
After the call the scanner stands on the value, and S.class tells what it found. Texts.Int means
an integer, in S.i; Texts.Real a real number, in S.x; Texts.Name or Texts.String a name or a
string, in S.s. If the value is a group, the scanner is already inside it, on its first item, and
you keep calling Texts.Scan(S) until the closing brace (a Texts.Char with S.c = "}") or S.eot;
System.Init walks InitCommands in this way. If the key is not in Oberon.Text at all, S.class is
Texts.Inval, and the module uses a default.

(Note: the text is kept in memory and read again only when the date of the file changes. So
lookups are cheap, and an edited Oberon.Text is noticed without restarting anything.)

## An example

A console module (desktop modules import Texts and Oberon and call Oberon.OpenScanner instead):

    MODULE mytool;
    IMPORT Texts := texts, Oberon := Oberon0, out;

    PROCEDURE Show*;
      VAR S: Texts.Scanner; size: LONGINT;
    BEGIN
      size := 12;  (* the default *)
      Oberon.OpenScanner(S, "MyTool.Size");
      IF S.class = Texts.Int THEN size := S.i END;
      out.String("size "); out.Int(size, 0); out.Ln;

      Oberon.OpenScanner(S, "MyTool.Host");
      IF S.class IN {Texts.Name, Texts.String} THEN out.String(S.s); out.Ln END;

      Oberon.OpenScanner(S, "MyTool.Colors");  (* a group: the scanner is on "red" *)
      WHILE (S.class = Texts.Name) & ~S.eot DO
        out.String(S.s); out.Char(" "); Texts.Scan(S)
      END;
      out.Ln
    END Show;

    END mytool.

With the MyTool section above in Oberon.Text it prints:

    $ bin/x86/loksh mytool.Show
    size 10
    example.org
    red green blue

## An environment variable first

Sometimes it is useful to override a setting for one run without touching Oberon.Text. The desktop
does this for the font scale: the environment variable OFONTSCALE wins over System.FontScale.
The same pattern in a module of your own reads the environment first and Oberon.Text only when the
variable is not set:

    Kernel.GetConfig("MYTOOLSIZE", s);
    IF s[0] # 0X THEN (* convert s *)
    ELSE
      Oberon.OpenScanner(S, "MyTool.Size");
      IF S.class = Texts.Int THEN size := S.i END
    END

## Details

Names are case-sensitive, and each part of a key has at most 31 characters. Names and strings are
read into S.s, which holds 63 characters, so a longer string is cut. When a key appears twice, the
first entry wins. A group in braces without a name is skipped, which is in fact how comments work;
so braces inside a comment must be balanced.
