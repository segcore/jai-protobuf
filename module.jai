/*
    Protobuf module definitions
 */

#load "encode.jai";
#load "decode.jai";

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
        case .MESSAGE; #through;
        case .PACKED_REPEATED;
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
        case "packed_repeated";
            return .PACKED_REPEATED;
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
            return type_name;
        case .MESSAGE;
            return type_name;
        case .PACKED_REPEATED;
            return "int"; // TODO
    }
}

array_view_equal :: (a: []u8, b: []u8) -> bool {
    if a.count != b.count return false;
    equal := memcmp(a.data, b.data, a.count) == 0;
    return equal;
}
