Iris, a picture viewer for the desktop of polpo

Iris.Open name      opens a picture file in a viewer
Iris.Open ^         the selected name
Iris.Info           (in the menu of an Iris viewer) the name and size of its picture

Drag the picture with any mouse button to see the rest of it.
System.Copy (in the menu) opens a second viewer of the same picture.

Oberon pictures (.pic) are read by Pictures itself; other formats need their
converters, installed with portia and listed in PictureConverters of Oberon.Text:
  portia.Install gif jpeg bmp tga pcx ico iff xpm

Iris.Open ~/Pictures/photo.jpg
