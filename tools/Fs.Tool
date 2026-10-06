Fs, directories and files of Linux in the console

fs.Pwd                       the current directory
fs.Cd [path]                 changes it ($HOME without a path; ~ is $HOME)
fs.Ls [-l] [-a] [path ...]   the files, sorted; -l type, size, date (UTC); -a dot files too
fs.Mkdir path ...            new directories
fs.Rm file ...               removes files
fs.Rmdir path ...            removes empty directories
fs.Mv old new                renames or moves (into new if it is a directory)
fs.Cp from to                copies a file (into to if it is a directory)

loksh runs its commands in one process: after fs.Cd, texts.Show name, xxs.Open name
and the others find a plain name in the new directory first, then on the search path
of the polpo root (the root, share/, tools/, fonts/).

fs.Cd ~/src
texts.Show notes.Text
