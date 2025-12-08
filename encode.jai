/*
    Protobuf Encoding.

    All values are encoded 'backwards' -- from the last byte of the buffer until the first.
    This is required because Protobuf used TLV (Type, Length, Value), and to know the length
    we must first know how many bytes are needed to encode the value. While we're there, we
    may as well do the encoding.

    Start with index == storage buffer's count.
    Assign index to the result of each successive encoding call.
    Index can go negative -- this is not an error. It shows how many bytes would be required.
    This means to calculate the size for an allocation, you can just pass an empty []u8
    (or, optimistically a small [N]u8 if it might fit), and at the end call encode_calc_size()
    to get the required allocation size, and re-run the encoding.

    Example:
        rawbuf: [4096]u8;
        buf: []u8 = rawbuf;
        index: s64 = rawbuf.count;

        // Encoding message of the form
        //     1: { 4: "hello", 6: 100 }
        // Depth-first backwards-encode the values, so the length of submessages is known
        submessage_end := index;
        index = encode_VARINT(buf, index, 100, 6);
        index = encode_string(buf, index, "hello", 4);
        index = encode_LEN_from_index(buf, index, submessage_end, 1);

        size := encode_calc_size(buf, index); // 9 bytes
        message_bytes := encode_finish(buf, index); // []u8 of the final message
        if message_bytes {
            // send message_bytes over a socket, ...
        }
 */


tag :: (wire_type: WireType, field_number: int) -> u64 {
    assert(field_number >= 1 && field_number <= 536870911);
    return cast(u64, field_number << 3) | xx wire_type;
}

encode_tag :: (buf: []u8, index: s64, wire_type: WireType, field_number: int) -> index: s64 {
    return encode_VARINT(buf, index, tag(wire_type, field_number));
}

encode_VARINT_zigzag :: (buf: []u8, index: s64, value: s64, field_number: int = -1) -> index: s64 {
    return encode_VARINT(buf, index, zigzag(value), field_number);
}

encode_VARINT_nozigzag :: (buf: []u8, index: s64, value: s64, field_number: int = -1) -> index: s64 {
    as_u64 := cast,no_check(u64) value;
    return encode_VARINT(buf, index, as_u64, field_number);
}

encode_VARINT :: (buf: []u8, index: s64, value: u64, field_number: int = -1) -> index: s64 {
    most_significant_bit := bit_scan_reverse(value);
    used := 1 + (most_significant_bit - 1) / 7;

    index -= used;
    if index >= 0 {
        for i: 0..used-1 {
            databits: u8 = cast(u8, value & 0x7f);
            value >>= 7;
            more: u8 = xx ifx value == 0 then 0 else 0x80;

            buf.data[index + i] = databits | more;
        }
        assert(value == 0);
    }
    if field_number >= 0 then index = encode_tag(buf, index, .VARINT, field_number);
    return index;
}

encode_LEN :: (buf: []u8, index: s64, value: u64, field_number: int = -1) -> index: s64 {
    index = encode_VARINT(buf, index, value, -1);
    if field_number >= 0 then index = encode_tag(buf, index, .LEN, field_number);
    return index;
}

encode_LEN_from_index :: (buf: []u8, index: s64, submessage_end_index: s64, field_number: int = -1) -> index: s64 {
    // submessage_end_index should always be earlier, because index moves backwards
    assert(index <= submessage_end_index, "Submessage end index is before the current index! % is not <= %", index, submessage_end_index);
    value: u64 = xx (submessage_end_index - index);
    index = encode_VARINT(buf, index, value, -1);
    if field_number >= 0 then index = encode_tag(buf, index, .LEN, field_number);
    return index;
}

encode_I64 :: (buf: []u8, index: s64, value: float64, field_number := -1) -> index: s64 {
    used := 8;
    index -= used;
    if index >= 0 then memcpy(buf.data + index, *value, used);
    if field_number >= 0 then index = encode_tag(buf, index, .I64, field_number);
    return index;
}
encode_I64 :: (buf: []u8, index: s64, value: s64, field_number := -1) -> size: s64 {
    used := 8;
    index -= used;
    if index >= 0 then memcpy(buf.data + index, *value, used); #assert LITTLE_ENDIAN;
    if field_number >= 0 then index = encode_tag(buf, index, .I64, field_number);
    return index;
}

encode_I32 :: (buf: []u8, index: s64, value: s32, field_number := -1) -> size: s64 {
    used := 4;
    index -= used;
    if index >= 0 then memcpy(buf.data + index, *value, used); #assert LITTLE_ENDIAN;
    if field_number >= 0 then index = encode_tag(buf, index, .I32, field_number);
    return index;
}
encode_I32 :: (buf: []u8, index: s64, value: float32, field_number := -1) -> size: s64 {
    used := 4;
    index -= used;
    if index >= 0 then memcpy(buf.data + index, *value, used);
    if field_number >= 0 then index = encode_tag(buf, index, .I32, field_number);
    return index;
}

// Copy the bytes into the buf, without a LEN prefix
encode_bytes_value :: (buf: []u8, index: s64, value: []u8) -> size: s64 {
    index -= value.count;
    if index >= 0 {
        memcpy(buf.data + index, value.data, value.count);
    }
    return index;
}

encode_string :: (buf: []u8, index: s64, value: string, field_number := -1) -> size: s64 {
    return encode_bytes(buf, index, value.([]u8), field_number);
}

encode_bytes :: (buf: []u8, index: s64, value: []u8, field_number := -1) -> size: s64 {
    index = encode_bytes_value(buf, index, xx value);
    index = encode_LEN(buf, index, cast(u64) value.count);
    if field_number >= 0 then index = encode_tag(buf, index, .LEN, field_number);
    return index;
}

encode_calc_size :: (buf: []u8, index: s64) -> s64 {
    return buf.count - index;
}

encode_finish :: (buf: []u8, index: s64) -> []u8 {
    if index < 0 then return .[];
    return array_view(buf, index);
}

zigzag :: (n: s64) -> u64 {
    zig := n << 1;
    zag := n >> 63;
    return cast,no_check(u64) (zig ^ zag);
}

#import "Basic";
#import "String";
#import "Bit_Operations";
