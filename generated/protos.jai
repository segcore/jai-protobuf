// !!! Automatically generated code !!!
// Generated from protos.proto

MyEnum :: enum {
    MyEnum_A :: 1;
    MyEnum_B :: 2;
    MyEnum_C :: 3;
}
Test1 :: struct {
    a: s32;
}
Test2 :: struct {
    my_enum: MyEnum;
    values: [..]float32;
    maybe_negative: s32;
    submessage: Test1;
}


// Serialize any message type into bytes. Allocates memory.
Serialize :: (message: $T) -> []u8 {
    buf: []u8;
    index := Serialize(buf, 0, message);
    array_resize(*buf, -index, false);
    index = Serialize(buf, buf.count, message);
    assert(index == 0, "Current index should be 0 but is %", index);
    return buf;
}


ProtoType_MyEnum :: ProtoType.ENUM;
FreeContents :: inline (message: *MyEnum) {}
Serialize :: (output: []u8, index: s64, enum_value: MyEnum, field_number := -1, force := false) -> index: s64 {
    value := cast(u64, enum_value);
    if force || value != 0  index = encode_VARINT(output, index, value, field_number);
    return index;
}
Parse :: (enum_value: *MyEnum, bytes: []u8) -> ok: bool, used: s64 {
    buf := bytes;
    ok, value := decode_VARINT(*buf);
    if !ok return false, 0;
    enum_value.* = xx,no_check value;
    used := bytes.count - buf.count;
    return true, used;
}

ProtoType_Test1 :: ProtoType.MESSAGE;
FreeContents :: inline (message: *Test1) {}
Serialize :: (output: []u8, index: s64, message: Test1, field_number := -1, force := false) -> index: s64 {
    default: Test1;
    start_index := index;
    { it := message.a; if it != default.a     index = encode_VARINT(output, index, xx,no_check it, 1); }
    if field_number >= 0 && (force || index != start_index)   index = encode_LEN_from_index(output, index, start_index, field_number);
    return index;
}
Parse :: (message: *Test1, bytes: []u8) -> ok: bool, used: s64 = 0 {
    buf := bytes;
    while buf {
        ok, wire_type, field_number := decode_tag(*buf);
        if !ok return false;
        if wire_type == {
        case .VARINT;
            ok=, decoded_value := decode_VARINT(*buf);  if !ok return false;
            if field_number == {
            case 1; message.a = xx,no_check decoded_value;
            }
        case .I32;
            ok=, decoded_value := decode_I32(*buf);  if !ok return false;
            decoded_value_float := (*decoded_value).(*float32).*;
            if field_number == {
            }
        case .I64;
            ok=, decoded_value := decode_I64(*buf);  if !ok return false;
            decoded_value_float := (*decoded_value).(*float64).*;
            if field_number == {
            }
        case .LEN;
            ok=, _, submessage := decode_LEN(*buf);  if !ok return false;
            if field_number == {
            }
        }
    }
    return true, bytes.count;
}

ProtoType_Test2 :: ProtoType.MESSAGE;
FreeContents :: (message: *Test2) {
    FreeContents(*message.my_enum);
    array_reset(*message.values);
    FreeContents(*message.submessage);
}
Serialize :: (output: []u8, index: s64, message: Test2, field_number := -1, force := false) -> index: s64 {
    default: Test2;
    start_index := index;
    { it := message.submessage; index = Serialize(output, index, it, 4); }
    { it := message.maybe_negative; if it != default.maybe_negative     index = encode_VARINT_zigzag(output, index, it, 3); }
    for < message.values { index = encode_I32(output, index, it, 2); }
    { it := message.my_enum; index = Serialize(output, index, it, 1); }
    if field_number >= 0 && (force || index != start_index)   index = encode_LEN_from_index(output, index, start_index, field_number);
    return index;
}
Parse :: (message: *Test2, bytes: []u8) -> ok: bool, used: s64 = 0 {
    buf := bytes;
    while buf {
        ok, wire_type, field_number := decode_tag(*buf);
        if !ok return false;
        if wire_type == {
        case .VARINT;
            ok=, decoded_value := decode_VARINT(*buf);  if !ok return false;
            if field_number == {
            case 1; #if ProtoType_MyEnum == .ENUM { message.my_enum = xx,no_check decoded_value; }
            case 3; message.maybe_negative = xx,no_check unzigzag(decoded_value);
            case 4; #if ProtoType_Test1 == .ENUM { message.submessage = xx,no_check decoded_value; }
            }
        case .I32;
            ok=, decoded_value := decode_I32(*buf);  if !ok return false;
            decoded_value_float := (*decoded_value).(*float32).*;
            if field_number == {
            case 2; array_add(*message.values, decoded_value_float);
            }
        case .I64;
            ok=, decoded_value := decode_I64(*buf);  if !ok return false;
            decoded_value_float := (*decoded_value).(*float64).*;
            if field_number == {
            }
        case .LEN;
            ok=, _, submessage := decode_LEN(*buf);  if !ok return false;
            if field_number == {
            case 1; if !Parse(*message.my_enum, submessage)  return false;
            case 2; while submessage {ok=, decoded_value := decode_I32_float(*submessage); if !ok return false; array_add(*message.values, decoded_value); }
            case 4; if !Parse(*message.submessage, submessage)  return false;
            }
        }
    }
    return true, bytes.count;
}
