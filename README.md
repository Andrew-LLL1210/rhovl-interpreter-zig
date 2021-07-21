# RHOVL Interpreter - Zig

This project is an attempt by me to get comfortable with Zig by writing an interpreter
for one of my esolangs, RHOVL (esolangs.org/wiki/RHOVL). This implementation is not complete
in accordance to the spec; in particular, the syntax `(EXPR)` for preserving the carry value
is not implemented, and there is no implementation for input (via `#`) at all.
For a fully-featured RHOVL interpreter, see my python project [here](github.com/Andrew-LLL1210/rhovl-interpreter).

# Features

- [x] evaluate basic RHOVL commands
- [x] conditional `if` and `while` loops
- [x] three types of `for` statement
- [ ] ask user for input
- [ ] pass file input to RHOVL program
- [ ] store subroutines in variables
- [ ] specify what file to interpret from (defaults to source.txt)

I am currently trying to figure out how to get command line arguments in the interpreter.
This will allow for file input and interpreting of files other than source.txt