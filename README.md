# Protobuf implementation in Jai

Incomplete, but useful enough for simple Protobuf use-cases.

Generates struct and enum definitions, and serializers and de-serializer
functions for them.

- [x] Encode primitive types
- [x] Decode primitive types
- [ ] Parse protobuf description files
  - [x] Basic
  - [ ] Nested messages/enums
  - [ ] comments
  - [x] import (ignored)
  - [x] package (passed to user)
  - [x] reserved fields (ignored)
  - [x] options
    - [x] deprecated, packed, default
    - [ ] extensions
  - [ ] Any type
- [x] Generate Jai enums
- [x] Generate Jai structures
- [x] Generate Jai serializer functions
- [x] Generate Jai de-serializer functions
- [x] Repeated fields
  - [x] Unpacked repeated fields
  - [ ] Packed repeated fields - Encode
  - [x] Packed repeated fields - Decode
- [ ] Map types
- [ ] One-of types
- Field presence is not tracked.
