MODULE linker;  (** 68020: linker.Link is the 68020 boot linker (see rlinker) *)
  IMPORT rlinker;

  PROCEDURE Link*;
  BEGIN rlinker.Link
  END Link;

  PROCEDURE Help*;
  BEGIN rlinker.Help
  END Help;

END linker.
