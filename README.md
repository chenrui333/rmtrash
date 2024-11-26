## rmtrash

**rmtrash** is a small utility that will move the file to OS X's Trash rather than obliterating the file (as rm does).


### Install

```shell
brew install --build-from-source tbxark/repo/rmtrash
```

### Usage

```
USAGE: trash-command [--recursive] [--force] <paths> ...

ARGUMENTS:
  <paths>                 The files or directories to move to trash.

OPTIONS:
  -r, --recursive         Recursively remove directories and their contents.
  -f, --force             Ignore nonexistent files and arguments, never prompt.
  -h, --help              Show help information.
```

### License
**rmtrash** is released under the MIT license. [See LICENSE](LICENSE) for details.