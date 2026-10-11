Pishmish, a Gemini and Spartan browser in the desktop. A middle click on
a link follows it in the same viewer; Pishmish.Back and Pishmish.Reload
are in the menu of the viewer. Input prompts, certificate requests and
files that are not text are shown with commands to click.

Pishmish.Open gemini://geminiprotocol.net/ ~
Pishmish.Open gemini://tlgs.one/search ~           a search: it asks for input
Pishmish.Open spartan://mozz.us/ ~
Pishmish.Open gemini://bbs.geminispace.org/ /ident name ~      with an identity
Pishmish.Open ^                                     the selected URL

In a Pishmish viewer:
  Pishmish.Back            the page before
  Pishmish.Reload          the page again (also after a viewer got wider)
  Pishmish.Send text ~     the answer to an input prompt (written after it)
  Pishmish.Ident who       log in with the identity who and load the page again
  Pishmish.Ident none      without an identity
  Pishmish.Save name       the file of the page, to name

Identities (client certificates) are in ~/.config/dcs/idents, shared with
dcs, DCS and the Pascal dcs and pishmish; who is a prefix of the
fingerprint, the name or the mail, or a part of them.

DCS.Idents ~
DCS.NewIdent name mail@example.org ~      a new identity
