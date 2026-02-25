/*
    Protobuf module definitions
 */

#load "encode.jai";
#load "decode.jai";
#load "generator.jai";

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
    STRING; BYTES; MESSAGE; // PACKED_REPEATED; but this contains a specific type inside

    // I32
    FIXED32; SFIXED32; FLOAT;
}

// Holds a single decoded (tag, value) item from a Protobuf serialization
ProtobufAtom :: struct {
    // Buffer views of various parts of the message
    atom_view:  []u8; // The byte range which this atom succesfully consumed in total
    tag_view:   []u8; // Byte range of the tag (field_number + wire_type)
    value_view: []u8; // Byte range of the value part

    // tag information
    tag_ok: bool;
    wire_type: WireType;
    field_number: int;

    // Value parts of the message
    value_ok: bool;

    length: s64;        // of LEN messages
    varint: u64;        // of VARINT (treated as u64)
    varint_zigzag: s64; // of VARINT (treated as a zigzagged signed encoding)
    I64_int: s64;       // of I64 (treated as an int)
    I64_float: float64; // of I64 (treated as a float)
    I32_int: s32;       // of I32 (treated as an int)
    I32_float: float32; // of I32 (treated as a float)

    // LEN payload
    submessage: []u8;

    // Failed to parse (may be present even when tag_ok=true, indicating that the tag succeeded but the value failed)
    // This will contain the remaining bytes of the buffer
    failed_view: []u8;
};


wire_type_for :: (proto_type: ProtoType) -> WireType {
    if #complete proto_type == {
        case .INT32; #through;
        case .INT64; #through;
        case .UINT32; #through;
        case .UINT64; #through;
        case .SINT32; #through;
        case .SINT64; #through;
        case .BOOL; #through;
        case .ENUM;
            return .VARINT;
        case .FIXED64; #through;
        case .SFIXED64; #through;
        case .DOUBLE;
            return .I64;
        case .STRING; #through;
        case .BYTES; #through;
        case .MESSAGE;
            return .LEN;
        case .FIXED32; #through;
        case .SFIXED32; #through;
        case .FLOAT;
            return .I32;
    }
}

should_zigzag :: (proto_type: ProtoType) -> bool {
    if proto_type == {
        case .SINT32; #through;
        case .SINT64;
            return true;
        case;
            return false;
    }
}

proto_type :: (type_name: string) -> ProtoType {
    if type_name == {
        case "int32";
            return .INT32;
        case "int64";
            return .INT64;
        case "uint32";
            return .UINT32;
        case "uint64";
            return .UINT64;
        case "sint32";
            return .SINT32;
        case "sint64";
            return .SINT64;
        case "bool";
            return .BOOL;
        case "enum";
            return .ENUM;
        case "fixed64";
            return .FIXED64;
        case "sfixed64";
            return .SFIXED64;
        case "double";
            return .DOUBLE;
        case "string";
            return .STRING;
        case "bytes";
            return .BYTES;
        case "message";
            return .MESSAGE;
        case "fixed32";
            return .FIXED32;
        case "sfixed32";
            return .SFIXED32;
        case "float";
            return .FLOAT;
        case;
            // Could be an enum or message
            return .MESSAGE;
    }
}

jai_type :: (type: ProtoType, type_name: string) -> string {
    if #complete type == {
        case .INT32; #through;
        case .SINT32; #through;
        case .FIXED32; #through;
        case .SFIXED32;
            return "s32";
        case .INT64; #through;
        case .SINT64; #through;
        case .FIXED64; #through;
        case .SFIXED64;
            return "s64";
        case .UINT32;
            return "u32";
        case .UINT64;
            return "u64";
        case .BOOL;
            return "bool";
        case .FLOAT;
            return "float32";
        case .DOUBLE;
            return "float64";
        case .STRING;
            return "string";
        case .BYTES;
            return "[]u8";
        case .ENUM;
            // Trim the "global" namespace prefix
            return trim_left(type_name, ".");
        case .MESSAGE;
            return trim_left(type_name, ".");
    }
}

jai_type :: (type_name: string) -> string {
    type := proto_type(type_name);
    return jai_type(type, type_name);
}

array_view_equal :: (a: []u8, b: []u8) -> bool {
    if a.count != b.count return false;
    equal := memcmp(a.data, b.data, a.count) == 0;
    return equal;
}
