/*
    Protobuf message decoding primitives
 */

decode_tag :: (buf: *[]u8) -> ok: bool, wire_type: WireType, field_number: int {
    ok, value := decode_VARINT(buf);
    wire_type := cast(WireType, value & 0b111);
    field_number := cast(int, value >> 3);
    return ok, wire_type, field_number;
}

decode_skip :: (buf: *[]u8, wire_type: WireType) -> ok: bool {
    ok: bool = false;
    if wire_type == {
        case .VARINT; ok = decode_VARINT(buf);
        case .LEN; ok = decode_LEN(buf);
        case .I32; ok = decode_I32(buf);
        case .I64; ok = decode_I64(buf);
    }
    return ok;
}

decode_VARINT_zigzag :: (buf: *[]u8) -> ok: bool, value: s64 {
    ok, uval := decode_VARINT(buf);
    return ok, unzigzag(uval);
}

decode_VARINT :: (buf: *[]u8) -> ok: bool, value: u64 {
    need_more := true;
    index := 0;
    value : u64 = 0;
    shift := 0;
    bufs := buf.*;
    while need_more && index < buf.count {
        next_byte := bufs[index];
        need_more = cast(bool, next_byte & 0x80);
        databits: u64 = next_byte & 0x7F;
        value = value + (databits << shift);
        shift += 7;
        if need_more && shift >= 64 {
            log("Protobuf VARINT too big to be valid. More than 70 bits!", flags = Log_Flags.WARNING);
            return false, value;
        }
        index += 1;
    }
    try_advance(buf, index);
    ok := !need_more;
    return ok, value;
}

decode_LEN :: (buf: *[]u8) -> ok: bool, length: s64, submessage: []u8 {
    ok, value := decode_VARINT(buf);
    len := cast(s64) value;
    submessage: []u8;
    if ok {
        submessage = array_view(buf.*, 0, len);
        ok = submessage.count == len;
        try_advance(buf, len);
    }
    return ok, len, submessage;
}

decode_string :: (buf: *[]u8) -> ok: bool, str: string {
    ok, _, bytes := decode_LEN(buf);
    str := cast(string)bytes;
    return ok, str;
}

decode_I64 :: (buf: *[]u8) -> ok: bool, value: s64 {
    size := 8;
    if buf.count >= size then {
        value: s64 = 0;
        memcpy(*value, buf.*.data, size); #assert LITTLE_ENDIAN;
        try_advance(buf, size);
        return true, value;
    } else {
        buf.* = .[];
        return false, 0;
    }
}

decode_I64_float :: (buf: *[]u8) -> ok: bool, value: float64 {
    ok, value := decode_I64(buf);
    return ok, (*value).(*float64).*;
}

decode_I32 :: (buf: *[]u8) -> ok: bool, value: s32 {
    size := 4;
    if buf.count >= size then {
        value: s32 = 0;
        memcpy(*value, buf.*.data, size); #assert LITTLE_ENDIAN;
        try_advance(buf, size);
        return true, value;
    } else {
        buf.* = .[];
        return false, 0;
    }
}
decode_I32_float :: (buf: *[]u8) -> ok: bool, value: float32 {
    ok, value := decode_I32(buf);
    return ok, (*value).(*float32).*;
}

unzigzag :: (value: u64) -> s64 {
    if value & 1 {
        return -cast(s64, value / 2) - 1;
    } else {
        return cast(s64, value / 2);
    }
}

try_advance :: (buf: *[]u8, index: int) {
    if index >= buf.count then buf.* = .[];
    else buf.* = array_view(buf.*, index);
}

#import "Math";
