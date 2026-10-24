MODULE objects;  (** console object facade, kept for packages that import it *)

(* polpo: objects is not used any more. for consistency the console and the desktop share one
   module, Objects, with the same types (both are made on Objects0). objects stays so that older
   packages keep compiling; new code imports Objects. *)

IMPORT Files, Objects0;

CONST
  enum* = Objects0.enum; get* = Objects0.get; set* = Objects0.set;
  shallow* = Objects0.shallow; deep* = Objects0.deep;
  load* = Objects0.load; store* = Objects0.store;
  Inval* = Objects0.Inval; String* = Objects0.String; Int* = Objects0.Int;
  Real* = Objects0.Real; LongReal* = Objects0.LongReal; Char* = Objects0.Char;
  Bool* = Objects0.Bool;

TYPE
  Name* = Objects0.Name;
  Object* = Objects0.Object;
  Dummy* = Objects0.Dummy;
  Library* = Objects0.Library;
  ObjMsg* = Objects0.ObjMsg;
  Handler* = Objects0.Handler;
  ObjDesc* = Objects0.ObjDesc;
  AttrMsg* = Objects0.AttrMsg;
  LinkMsg* = Objects0.LinkMsg;
  CopyMsg* = Objects0.CopyMsg;
  BindMsg* = Objects0.BindMsg;
  FileMsg* = Objects0.FileMsg;
  FindMsg* = Objects0.FindMsg;
  DummyDesc* = Objects0.DummyDesc;
  Index* = Objects0.Index;
  IndexDesc* = Objects0.IndexDesc;
  Dictionary* = Objects0.Dictionary;
  DictionaryDesc* = Objects0.DictionaryDesc;
  LibDesc* = Objects0.LibDesc;
  NewProc* = Objects0.NewProc;
  EnumProc* = Objects0.EnumProc;

VAR LibBlockId*: CHAR; NewObj*: Object;

PROCEDURE Stamp*(VAR M: ObjMsg);
BEGIN Objects0.Stamp(M) END Stamp;

PROCEDURE ThisLibrary*(name: ARRAY OF CHAR): Library;
BEGIN RETURN Objects0.ThisLibrary(name) END ThisLibrary;

PROCEDURE FreeLibrary*(name: ARRAY OF CHAR);
BEGIN Objects0.FreeLibrary(name) END FreeLibrary;

PROCEDURE Enumerate*(P: EnumProc);
BEGIN Objects0.Enumerate(P) END Enumerate;

PROCEDURE Register*(ext: ARRAY OF CHAR; new: NewProc);
BEGIN Objects0.Register(ext, new) END Register;

PROCEDURE LoadLibrary*(L: Library; f: Files.File; pos: LONGINT; VAR len: LONGINT);
BEGIN Objects0.LoadLibrary(L, f, pos, len) END LoadLibrary;

PROCEDURE StoreLibrary*(L: Library; f: Files.File; pos: LONGINT; VAR len: LONGINT);
BEGIN Objects0.StoreLibrary(L, f, pos, len) END StoreLibrary;

PROCEDURE OpenLibrary*(L: Library);
BEGIN Objects0.OpenLibrary(L) END OpenLibrary;

PROCEDURE GetRef*(VAR D: Dictionary; name: ARRAY OF CHAR; VAR ref: INTEGER);
BEGIN Objects0.GetRef(D, name, ref) END GetRef;

PROCEDURE GetKey*(VAR D: Dictionary; name: ARRAY OF CHAR; VAR key: INTEGER);
BEGIN Objects0.GetKey(D, name, key) END GetKey;

PROCEDURE GetName*(VAR D: Dictionary; key: INTEGER; VAR name: ARRAY OF CHAR);
BEGIN Objects0.GetName(D, key, name) END GetName;

PROCEDURE PutName*(VAR D: Dictionary; key: INTEGER; name: ARRAY OF CHAR);
BEGIN Objects0.PutName(D, key, name) END PutName;

BEGIN
  LibBlockId := Objects0.LibBlockId;
  Objects0.Activate := NIL
END objects.
