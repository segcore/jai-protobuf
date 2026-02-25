/*
    Protobuf Decoding.

    All values are encoded in forwards-order directly into the buffer.

    Most of these are primitive functions, but see also decode_atom() and protobuf_atoms().

    Example:
        buffer: []u8 = .[0x08, 0x96, 0x01];
        for :protobuf_atoms atom : buffer {
            if atom.tag_ok {
                print("Decoded wire_type=%, field_number=%, using a total of % bytes\n",
                    atom.wire_type, atom.field_number, atom.atom_view.count);
            }
        }
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

decode_bytes :: (buf: *[]u8) -> ok: bool, bytes: []u8 {
    ok, _, bytes := decode_LEN(buf);
    return ok, bytes;
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

// Extract the next atom (tag and value) from a Protobuf serialization
decode_atom :: (buf: *[]u8) -> ProtobufAtom {
    atom: ProtobufAtom;
    atom.atom_view = buf.*;

    atom.tag_view = buf.*;
    atom.tag_ok, atom.wire_type, atom.field_number = decode_tag(buf);
    atom.tag_view.count -= buf.count;

    if atom.tag_ok {
        atom.value_view = buf.*;
        if #complete atom.wire_type == {
            case .LEN;
                value_ok, length, submessage := decode_LEN(buf);
                atom.value_ok = value_ok;
                atom.value_view.count -= (buf.count + submessage.count);
                atom.length = length;
                atom.submessage = submessage;
            case .VARINT;
                value_ok, value := decode_VARINT(buf);
                atom.value_ok = value_ok;
                atom.value_view.count -= buf.count;
                atom.varint = value;
                atom.varint_zigzag = unzigzag(value);
            case .I64;
                value_ok, value := decode_I64(buf);
                atom.value_ok = value_ok;
                atom.value_view.count -= buf.count;
                converted := (*value).(*float64).*;
                atom.I64_int = value;
                atom.I64_float = converted;
            case .I32;
                value_ok, value := decode_I32(buf);
                atom.value_ok = value_ok;
                atom.value_view.count -= buf.count;
                converted := (*value).(*float32).*;
                atom.I32_int = value;
                atom.I32_float = converted;
            case .SGROUP; #through;
            case .EGROUP;
                atom.value_ok = true; // OK; no value
                atom.value_view.count = 0;
            case; // Invalid wire type decoded
                atom.value_ok = false;
                atom.value_view.count = 0;
        }
    }

    atom.atom_view.count -= buf.count;

    // We need to return the failed view in the same atom because when iteratively
    // calling this we would start decoding the next byte as if it were a tag
    // instead of just a failed part of the value
    ok := atom.tag_ok && atom.value_ok;
    if !ok {
        atom.failed_view = buf.*;
        buf.count = 0;
    }

    return atom;
}

// `for_expansion` which returns successive protobuf atoms until the buffer is exhausted
protobuf_atoms :: (bytes: *[]u8, body: Code, flags: For_Flags) #expand {
    #assert (flags & .POINTER) == 0;
    #assert (flags & .REVERSE) == 0;

    buf := bytes.*;
    atom_count := 0;

    while buf.count > 0 {
        atom := decode_atom(*buf);

        `it := atom;
        `it_index := atom_count;
        atom_count += 1;

        #insert body;
    }
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
