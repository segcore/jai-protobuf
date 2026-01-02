# Protobuf implementation in Jai

Protobuf is supported at various levels and exposed to the user:
* primitive encode/decode functions
* parsing protobuf files (compile time or runtime)
* code generation (pre-generated)
* code generation (during build) (just #run it!)

Structures and enumerations are generated according to protobuf text descriptions.
See the [generated example code](./generated/protos.jai).
The generated code is very simple -- structures with public fields and types just
as a normal structure would be. Repeated fields use `[..]type` and can be used directly.
Use the language's context features to setup custom allocators.

The parser is very relaxed. It ignores anything it doesn't understand and just keeps
soldiering on. This is good in that it doesn't need every possible feature to be
implemented here to be able to parse realistic external files. It should work for
correct protobuf files, but presently gives poor messaging for failures/unknown features.

The parser/generator also does not follow all Protobuf rules, because it does not need
to in order to work. For example, you can use an Enum or Message from another protobuf
text file without importing it. The parser and code generation don't need it.
If the other file is eventually `#load` at build time, it will work. Otherwise, it will
be a compile time error. This simplifies the process too -- leveraging the compiler to
do all of the linking work. Afterall, it is going to have to do it anyway, so why
double up?

## Feature set

* [x] Encode primitive types
* [x] Decode primitive types
* [x] Parse protobuf description files
  * [x] Basic
  * [x] Nested messages/enums
  * [x] comments (ignored)
  * [x] import (ignored)
  * [x] package (passed to user)
  * [x] reserved fields (ignored)
  * [x] options
    * [x] deprecated, packed, default
  * [ ] `Any` type
* [x] Generate Jai enums
* [x] Generate Jai structures
* [x] Generate Jai serializer functions
* [x] Generate Jai de-serializer functions
* [x] Repeated fields
  * [x] Unpacked repeated fields
  * [ ] Packed repeated fields - Encode
  * [x] Packed repeated fields - Decode
* [x] Map types
* [x] One-of types

Not intended to be implemented:
* Field presence information
* Message "extensions"
