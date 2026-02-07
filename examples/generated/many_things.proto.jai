// !!! Automatically generated code !!!
// Generated from examples/protos/many_things.proto
#import "Hash_Table";
#import "Basic";

MyEnum :: enum {
    MyEnum_A :: 0;
    MyEnum_B :: 1;
    MyEnum_C :: 2;
}
SimpleHolder :: struct {
    a: s32;
}
ManyThings :: struct {
    my_enum: MyEnum;
    values: [..]float32;
    maybe_negative: s32 = 42;
    submessage: SimpleHolder;
    something: string = "hello"; @deprecated
    subtype_value: SubType;
    name_mapping: Table(string, s32);
    Plant_Kind :: enum {
        _UNSET;
        tree;
        flowers;
    }
    Plant_kind: Plant_Kind;
    using Plant : union {
        tree: bool;
        flowers: u32;
    }
    SubType :: enum {
        SubType_Q :: 0;
        SubType_W :: 1;
        SubType_E :: 2;
    }
}


ProtoType_MyEnum :: ProtoType.ENUM;
Serialize :: (output: []u8, index: s64, enum_value: MyEnum, field_number := -1, force := false) -> index: s64 {
    value := cast,no_check(u64, enum_value);
    if force || value != 0  index = encode_VARINT(output, index, value, field_number);
    return index;
}
Deserialize :: (enum_value: *MyEnum, bytes: []u8) -> ok: bool, used: s64 {
    buf := bytes;
    ok, value := decode_VARINT(*buf);
    if !ok return false, 0;
    enum_value.* = xx,no_check value;
    used := bytes.count - buf.count;
    return true, used;
}
FreeContents :: inline (message: *MyEnum) {}

ProtoType_SimpleHolder :: ProtoType.MESSAGE;
Serialize :: (output: []u8, index: s64, message: SimpleHolder, field_number := -1, force := false) -> index: s64 {
    default: SimpleHolder;
    start_index := index;
    { it := message.a; if it != default.a     index = encode_VARINT(output, index, xx,no_check it, 1); }
    if field_number >= 0 && (force || index != start_index)   index = encode_LEN_from_index(output, index, start_index, field_number);
    return index;
}
Serialize :: (message: SimpleHolder) -> []u8 { buf := NewArray(-Serialize(u8.[], 0, message), u8, false); Serialize(buf, buf.count, message); return buf; }
Deserialize :: (message: *SimpleHolder, bytes: []u8) -> ok: bool, used: s64 = 0 {
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
        case .I64;
            ok=, decoded_value := decode_I64(*buf);  if !ok return false;
        case .LEN;
            ok=, _, submessage := decode_LEN(*buf);  if !ok return false;
        }
    }
    return true, bytes.count;
}
FreeContents :: inline (message: *SimpleHolder) {}

ProtoType_ManyThings_SubType :: ProtoType.ENUM;
Serialize :: (output: []u8, index: s64, enum_value: ManyThings.SubType, field_number := -1, force := false) -> index: s64 {
    value := cast,no_check(u64, enum_value);
    if force || value != 0  index = encode_VARINT(output, index, value, field_number);
    return index;
}
Deserialize :: (enum_value: *ManyThings.SubType, bytes: []u8) -> ok: bool, used: s64 {
    buf := bytes;
    ok, value := decode_VARINT(*buf);
    if !ok return false, 0;
    enum_value.* = xx,no_check value;
    used := bytes.count - buf.count;
    return true, used;
}
FreeContents :: inline (message: *ManyThings.SubType) {}

ProtoType_ManyThings :: ProtoType.MESSAGE;
Serialize :: (output: []u8, index: s64, message: ManyThings, field_number := -1, force := false) -> index: s64 {
    default: ManyThings;
    start_index := index;
    for message.name_mapping { end := index; index = encode_VARINT(output, index, xx,no_check it, 2); index = encode_string(output, index, it_index, 1); index = encode_LEN_from_index(output, index, end, 7); }
    { it := message.subtype_value; index = Serialize(output, index, it, 6); }
    { it := message.something; if it != default.something     index = encode_string(output, index, it, 5); }
    { it := message.submessage; index = Serialize(output, index, it, 4); }
    { it := message.maybe_negative; if it != default.maybe_negative     index = encode_VARINT_zigzag(output, index, it, 3); }
    for < message.values { index = encode_I32(output, index, it, 2); }
    { it := message.my_enum; index = Serialize(output, index, it, 1); }
    if message.Plant_kind == {
        case .tree; { it := message.tree; index = encode_VARINT(output, index, xx,no_check it, 10); }
        case .flowers; { it := message.flowers; index = encode_VARINT(output, index, xx,no_check it, 11); }
    }
    if field_number >= 0 && (force || index != start_index)   index = encode_LEN_from_index(output, index, start_index, field_number);
    return index;
}
Serialize :: (message: ManyThings) -> []u8 { buf := NewArray(-Serialize(u8.[], 0, message), u8, false); Serialize(buf, buf.count, message); return buf; }
Deserialize :: (message: *ManyThings, bytes: []u8) -> ok: bool, used: s64 = 0 {
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
            case 4; #if ProtoType_SimpleHolder == .ENUM { message.submessage = xx,no_check decoded_value; }
            case 6; message.subtype_value = xx,no_check decoded_value;
            case 10; message.tree = xx,no_check decoded_value; message.Plant_kind = .tree;
            case 11; message.flowers = xx,no_check decoded_value; message.Plant_kind = .flowers;
            }
        case .I32;
            ok=, decoded_value := decode_I32(*buf);  if !ok return false;
            decoded_value_float := (*decoded_value).(*float32).*;
            if field_number == {
            case 2; array_add(*message.values, decoded_value_float);
            }
        case .I64;
            ok=, decoded_value := decode_I64(*buf);  if !ok return false;
        case .LEN;
            ok=, _, submessage := decode_LEN(*buf);  if !ok return false;
            if field_number == {
            case 1; if !Deserialize(*message.my_enum, submessage)  return false;
            case 2; while submessage {ok=, decoded_value := decode_I32_float(*submessage); if !ok return false; array_add(*message.values, decoded_value); }
            case 4; if !Deserialize(*message.submessage, submessage)  return false;
            case 5; message.something = copy_string(submessage.(string));
            case 7;  key: string; value: s32; while submessage {
                ok=, wire_type, field_number := decode_tag(*submessage); if !ok return false;
                if field_number == 1 && wire_type == .LEN { ok, ptr := decode_string(*submessage); key = copy_string(ptr); }
                else if field_number == 2 && wire_type == .VARINT { ok=, varint := decode_VARINT(*submessage); value = xx,no_check varint; }
                else { ok = decode_skip(*submessage, wire_type); }
                if !ok return false; }
                table_set(*message.name_mapping, key, value);
            }
        }
    }
    return true, bytes.count;
}
FreeContents :: (message: *ManyThings) {
    FreeContents(*message.my_enum);
    array_reset(*message.values);
    FreeContents(*message.submessage);
    free(message.something); message.something = "";
    FreeContents(*message.subtype_value);
    for* v, k : message.name_mapping { free(k); }
    deinit(*message.name_mapping); message.name_mapping = .{};
}
