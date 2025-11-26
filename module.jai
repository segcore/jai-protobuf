/*
    Protobuf module definitions
 */

#load "encode.jai";

LITTLE_ENDIAN :: true;

WireType :: enum {
    VARINT :: 0;
    I64    :: 1;
    LEN    :: 2;
    SGROUP :: 3;
    EGROUP :: 4;
    I32    :: 5;
}

ProtoType :: enum {
    // VARINT
    INT32; INT64; UINT32; UINT64; SINT32; SINT64; BOOL; ENUM;

    // I64
    FIXED64; SFIXED64; DOUBLE;

    // LEN
    STRING; BYTES; MESSAGE; PACKED_REPEATED;

    // I32
    FIXED32; SFIXED32; FLOAT;
}
