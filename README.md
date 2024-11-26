## rmtrash

**rmtrash** is a small utility that will move the file to OS X's Trash rather than obliterating the file (as rm does).


### Install

```shell
brew install --build-from-source tbxark/repo/rmtrash
```

### Usage

```
USAGE: rmtrash [--recursive] [--force] [--verbose] <paths> ...

ARGUMENTS:
  <paths>                 The files or directories to move to trash.

OPTIONS:
  -r, --recursive         Recursively remove directories and their contents.
  -f, --force             Ignore nonexistent files and arguments, never prompt.
  -v, --verbose           Print debugging information.
  -h, --help              Show help information.
```

Also, you can add the following aliases to your shell profile:

```shell
alias del="rmtrash"
alias trash="rmtrash"
alias rm="echo Use 'del', or the full path i.e. '/bin/rm'"
```

### License
**rmtrash** is released under the MIT license. [See LICENSE](LICENSE) for details.