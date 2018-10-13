# Factorio Tools

This repository contains two tools which support the [Factorio Calculator](https://kirkmcdonald.github.io/calc.html) ([repo](https://github.com/KirkMcDonald/kirkmcdonald.github.io)).

`factoriocalc` loads data from a Factorio installation, starts an HTTP server hosting the calculator, and opens it in a browser. It provides a quick and easy way to use a custom combination of mods with the calculator.

`factoriodump` is used to load data from a Factorio installation, and write the data files and sprite sheet used by the calculator. It is primarily a tool which supports development of the calculator.

## How to build

You will need:

* [Go](https://golang.org)
* [packr](https://github.com/gobuffalo/packr)
* A C compiler
* Lua 5.3
* The Lua libraries [LuaFileSystem](http://keplerproject.github.io/luafilesystem/) and [LuaZip](https://github.com/mpeterv/luazip) (both available from LuaRocks)

Change into either tool's subdirectory and build it with:

```text
$ packr build
```
