DCS, the digital command system in the desktop: Gemini and Spartan
requests, each answer in a viewer (the URL, the status, the meta, the
body as it arrived). The console version is dcs (loksh dcs.Help).
Middle click a command; ~ ends its parameters.

DCS.Get gemini://geminiprotocol.net/ ~
DCS.Get gemini://geminiprotocol.net/ /follow ~
DCS.Get spartan://mozz.us/ ~
DCS.Get gemini://bbs.geminispace.org/ /ident name ~      log in with an identity
DCS.Get gemini://example.org/search "two words" ~        input (the query)
DCS.Get gemini://geminiprotocol.net/ /save ~             to a file named after the URL
DCS.Get gemini://geminiprotocol.net/ /output page.gmi ~
DCS.Get gemini://geminiprotocol.net/ /fingerprint ~      the SHA-256 of the certificate
DCS.Get gemini://geminiprotocol.net/ /pin sha256 ~       require that certificate
DCS.Get gemini://geminiprotocol.net/ /tofu ~             trust on first use

Identities (client certificates) are in ~/.config/dcs/idents; /ident
takes a prefix of the fingerprint, the name, the mail, or a part of
them.

DCS.Idents ~
DCS.NewIdent name mail@example.org ~      a new P-256 key, self-signed
DCS.Get url /cert file.crt /key file.key ~
