From a specially crafted C header file, this Perl script can generate all
necessary (resource file, header, and function) stubs for creating an [Igor
Pro](https://www.igorpro.net) XOP.

See the file example-header.h for an example input file, the output is in the
files functionBodys.cpp, functions.cpp, functions.h, functions.rc.

Requirements: A recent version of Perl and utags from https://ctags.io.
Call the script as `./xop-stub-generator.pl example-header.h`.
