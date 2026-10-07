# compiler.Compile options reference

## Quick Help

From the command line:
```bash
bin/x86/loksh compiler.Compile          # Shows help
bin/x86/loksh compiler.Compile /help    # Shows help
bin/x86/loksh compiler.Help             # Shows help
```

## Basic Usage

```bash
bin/x86/loksh compiler.Compile [options] file1.Mod [file2.Mod ...]
```

## Runtime Check Options

By default, the compiler enables runtime checks. Use these options to **disable** checks:

| Option | Description | Default | Use Case |
|--------|-------------|---------|----------|
| `/x` | Disable **index checking** | ON | Disable for performance after testing |
| `/v` | Disable overflow checking | ON | Disable for performance after testing |
| `/t` | Disable type checking | ON | Not recommended - can cause crashes |
| `/p` | Disable pointer initialization | ON | Dangerous - can cause crashes |
| `/a` | Disable assertions | ON | Disable in production builds |
| `/z` | Disable full stack initialization | ON | Disable for performance |
| `/q` | Disable trace | ON | Disable trace output |

### Example: Fast Production Build
```bash
# Disable all runtime checks for maximum performance
bin/x86/loksh compiler.Compile /x /v /t /p /a /z /q MyModule.Mod
```

### Example: Safe Development Build
```bash
# Use defaults (all checks enabled) for development
bin/x86/loksh compiler.Compile MyModule.Mod
```

## Symbol File Options

Symbol files (.Sym) contain module interface information for separate compilation.

| Option | Description | When to Use |
|--------|-------------|-------------|
| `/s` | Generate **new** symbol file | When interface changes (new exports) |
| `/e` | Generate **extended** symbol file | When adding to interface (preserving compatibility) |
| `/i` | Symbol file **inside** the `.Obj` (Native Oberon) | Only for compatibility: by default the compiler writes `Module.Sym` apart and a smaller `Module.Obj` |

The x86 compiler writes the interface to `obj/x86/Module.Sym` and the code to `obj/x86/Module.Obj`,
as the other ports do. A module compiled with `/i` (or before polpo had separate symbol files)
has its symbol file in the `.Obj`; the compiler and the browser read it from there when there
is no `.Sym`.

### Example: First Compilation
```bash
bin/x86/loksh compiler.Compile /s MyModule.Mod
```

### Example: Recompilation (no interface change)
```bash
# No /s needed - reuses existing symbol file
bin/x86/loksh compiler.Compile MyModule.Mod
```

## Language Mode Options

| Option | Description | Features |
|--------|-------------|----------|
| `/1` | **Oberon-1** mode | Classic Oberon language |
| `/2` | **Oberon-2** mode | Adds type-bound procedures, read-only export |

### Example: Oberon-2 with type-bound procedures
```bash
bin/x86/loksh compiler.Compile /2 ObjectOrientedModule.Mod
```

## System Options

| Option | Description | Use Case |
|--------|-------------|----------|
| `/S` | Enable **system checking** | When using SYSTEM module |
| `/n` | **No files** mode | Syntax check only, no output |
| `/f` | **Find PC** mode | Debugging - locate error by PC |
| `/w` | Enable **warnings** | Show additional warnings |
| `/X` | Use module name as **prefix** | Avoid name collisions |
| `/T` | **Trace procedures** | Debug procedure calls |

### Example: Syntax Check Only
```bash
bin/x86/loksh compiler.Compile /n Test.Mod
```

### Example: Show All Warnings
```bash
bin/x86/loksh compiler.Compile /w MyModule.Mod
```

## Output Control Options

### Extension: `/.ext`

Change the output file extension (default is `.Obj`):

```bash
# Use .o extension
bin/x86/loksh compiler.Compile /.o MyModule.Mod
# Creates: MyModule.o
```

### Path: `/Ppath`

Set output directory:

```bash
# Output to x86/ directory
bin/x86/loksh compiler.Compile /Px86/ MyModule.Mod
# Creates: x86/MyModule.Obj

# Output to build/obj/ directory
bin/x86/loksh compiler.Compile /Pbuild/obj/ MyModule.Mod
# Creates: build/obj/MyModule.Obj
```

### Prefix: `/Oprefix`

Add prefix to output filename:

```bash
# Add "Debug_" prefix
bin/x86/loksh compiler.Compile /ODebug_ MyModule.Mod
# Creates: Debug_MyModule.Obj
```

## Common Combinations

### Development Build (All Checks)
```bash
bin/x86/loksh compiler.Compile /s /w MyModule.Mod
```
- New symbol file
- All runtime checks enabled
- Show warnings

### Production Build (Optimized)
```bash
bin/x86/loksh compiler.Compile /x /v /a /z MyModule.Mod
```
- No index checking
- No overflow checking
- No assertions
- No full stack init
- Symbol file reused

### Cross-Platform Build
```bash
bin/x86/loksh compiler.Compile /Px86/ /s Module1.Mod Module2.Mod Module3.Mod
```
- Output to x86/ directory
- Generate new symbol files
- Compile multiple modules

### Quick Syntax Check
```bash
bin/x86/loksh compiler.Compile /n /w Test.Mod
```
- No output files
- Show warnings
- Fast check

## Multiple Files

Compile multiple modules in one command:

```bash
bin/x86/loksh compiler.Compile /s Module1.Mod Module2.Mod Module3.Mod
```

Options apply to all files unless you want different options per file (then compile separately).

## Option Order

Options can appear anywhere before or between filenames:

```bash
# All equivalent:
bin/x86/loksh compiler.Compile /s /w File.Mod
bin/x86/loksh compiler.Compile /w File.Mod /s
bin/x86/loksh compiler.Compile File1.Mod /s File2.Mod /w File3.Mod
```

## Error Messages

### "not found"
The .Mod source file doesn't exist or path is wrong.

### "generation of new symbol file not allowed"
You need to use `/s` option when adding new exports to a module.

### "symbol file mismatch"
The imported module's interface has changed. Recompile the imported module with `/s`, then recompile your module.

## Tips

1. **Always use `/s` for first compilation** or when interface changes
2. **Use `/w` during development** to catch potential issues
3. **Disable checks carefully** - only after thorough testing
4. **Use `/Ppath/` to organize** build outputs
5. **Test with all checks** enabled before disabling any

## Debugging Options

When debugging compiler issues:

```bash
# Maximum verbosity
bin/x86/loksh compiler.Compile /w /T /s MyModule.Mod

# Check syntax only
bin/x86/loksh compiler.Compile /n MyModule.Mod

# Trace procedures
bin/x86/loksh compiler.Compile /T MyModule.Mod
```
