## rmtrash

**rmtrash** is a small utility that will move the file to OS X's Trash rather than obliterating the file (as rm does).


### Install

```shell
brew install --build-from-source tbxark/repo/rmtrash
```

### Syntax

```
rmtrash [-f | --force] {[-i | --interactive[=always]] | [-I | --interactive=once] |
   [--interactive=never]} [--one-file-system] [--no-preserve-root |
   --preserve-root] [-r | -R | --recursive] [-d | --dir] [-v | --verbose] 
   FILE...

rmtrash --help

rmtrash --version
```

### Options

| **-f**, **--force**             | Ignore nonexistant files, and never prompt before removing.  |
| :------------------------------ | ------------------------------------------------------------ |
| **-i**                          | Prompt before every removal.                                 |
| **-I**                          | Prompt once before removing more than three files, or when removing recursively. This option is less intrusive than **-i**, but still gives protection against most mistakes. |
| **--interactive**[**=***WHEN*]  | Prompt according to *WHEN*: **never**, **once** (**-I**), or **always** (**-i**). If *WHEN* is not specified, then prompt once. |
| **--one-file-system**           | When removing a hierarchy recursively, skip any directory that is on a file system different from that of the corresponding command line argument |
| **--no-preserve-root**, **-x**  | Do not treat "**/**" (the root directory) in any special way. |
| **--preserve-root**             | Do not remove "**/**" (the root directory), which is the default behavior. |
| **-r**, **-R**, **--recursive** | Remove directories and their contents recursively.           |
| **-d**, **--dir**               | Remove empty directories. This option permits you to remove a directory without specifying **-r**/**-R**/**--recursive**, provided that the directory is empty. In other words, **rmtrash -d** is equivalent to using **rmdir**. |
| **-v**, **--verbose**           | Verbose mode; explain at all times what is being done.       |
| **--help**                      | Display a help message, and exit.                            |
| **--version**                   | Display version information, and exit.                       |

### Usage notes

If the **-I**/**--interactive=once** option is given, and there are more than three files or the **-r**/**-R**/**--recursive** options are specified, **rm** prompts before deleting anything. If the user does not respond **yes**/**y**/**Y** to the prompt, the entire command is aborted.

If a file is unwritable, stdin is a terminal, and the **-f**/**--force** option is not given, or the **-i** or **--interactive=always** option is given, **rm** prompts the user for whether to remove the file. If the response is not **yes**/**y**/**Y**, the file is skipped.

Also, you can add the following aliases to your shell profile:

```shell
alias del="rmtrash"
alias trash="rmtrash"
alias rm="echo Use 'del', or the full path i.e. '/bin/rm'"
```

### Known issues

- **rm** cannot remove current directory but **rmtrash** can, But I think this is not a bug

### License
**rmtrash** is released under the MIT license. [See LICENSE](LICENSE) for details.
