#import,dir ".";
#import "File";
#import "Hash_Table";
#import "Basic";
#import "String";

main :: () {
    context.print_style.default_format_int.base = 16;
    context.print_style.default_format_int.minimum_digits = 2;

    test_misc();
    test_encode();
    test_decode();
    test_parse();
    test_generate();
    test_generate_from_file();

    if tests_failed exit(1);
    print("All tests passed!\n");
}

test_misc :: () {
    // Test free functions
    test_eq(tag(.VARINT, 1), 0b1_000);
    test_eq(zigzag(0), 0);
    test_eq(zigzag(-1), 1);
    test_eq(zigzag(1), 2);
    test_eq(zigzag(-2), 3);
    test_eq(zigzag(2), 4);
    test_eq(zigzag(0x7fffffff), 0xfffffffe);
    test_eq(zigzag(-0x80000000), 0xffffffff);
    test_eq(zigzag(0x7fffffff_ffffffff), 0xffffffff_fffffffe);
    test_eq(zigzag(-0x80000000_00000000), 0xffffffff_ffffffff);

    test_eq(unzigzag(0), 0);
    test_eq(unzigzag(1), -1);
    test_eq(unzigzag(2), 1);
    test_eq(unzigzag(3), -2);
    test_eq(unzigzag(4), 2);
    test_eq(unzigzag(0xfffffffe), 0x7fffffff);
    test_eq(unzigzag(0xffffffff), -0x80000000);
    test_eq(unzigzag(0xffffffff_fffffffe), 0x7fffffff_ffffffff);
    test_eq(unzigzag(0xffffffff_ffffffff), -0x80000000_00000000);
}

test_encode :: () {
    rawbuf: [4096]u8;
    buf: []u8 = rawbuf;
    encoded: []u8;
    index: s64;

    // ----- "A Simple Message" from the docs
    // Test encoded messages
    // We encode backwards so we know the lengths of all sub-fields
    index = rawbuf.count;
    index = encode_VARINT(buf, index, 150);
    test_eq(encode_finish(rawbuf, index), u8.[0x96, 0x01]);
    index = encode_tag(buf, index, .VARINT, 1);
    test_eq(encode_finish(rawbuf, index), u8.[0x08, 0x96, 0x01]);

    // or the simpler way
    index = rawbuf.count;
    index = encode_VARINT(buf, index, 150, 1);
    test_eq(encode_finish(rawbuf, index), u8.[0x08, 0x96, 0x01]);
    // --------------

    // ----- message Test2 - LEN-encoded field
    index = buf.count;
    index = encode_string(buf, index, "testing", 2);
    test_eq(encode_finish(rawbuf, index), u8.[0x12, 0x07, "t", "e", "s", "t", "i", "n", "g"]);

    // ----- message Test3 - submessages
    index = buf.count;
    submessage_end := index;
    // Test1.a = 150
    index = encode_VARINT(buf, index, 150, 1);
    // Wrap the message
    index = encode_LEN(buf, index, cast(u64, submessage_end - index), 3);
    test_eq(encode_finish(rawbuf, index), u8.[0x1a, 0x03, 0x08, 0x96, 0x01]);

    // My example
    index = buf.count;
    index = encode_VARINT(buf, index, 0, 16);
    test_eq(encode_finish(buf, index), u8.[0b1000_0000, 0b0000_0001, 0]);
    
}

test_decode :: () {
    buf: []u8;
    ok: bool;
    wire_type: WireType;
    field_number: int;
    u: u64;
    s: s64;
    len: s64;
    submessage: []u8;

    { // Sample 1
        buf = .[0x08, 0x96, 0x01];
        ok, wire_type, field_number = decode_tag(*buf);
        test_eq(ok, true);
        test_eq(wire_type, .VARINT);
        test_eq(field_number, 1);

        ok, u = decode_VARINT(*buf);
        test_eq(ok, true);
        test_eq(u, 150);
    }

    { // Test2
        buf = .[0x12, 0x07, 0x74, 0x65, 0x73, 0x74, 0x69, 0x6e, 0x67];
        ok, wire_type, field_number = decode_tag(*buf);
        test_eq(ok, true);
        test_eq(wire_type, .LEN);
        test_eq(field_number, 2);

        ok, len, submessage = decode_LEN(*buf);
        test_eq(ok, true);
        test_eq(len, 7);
        test_eq(submessage, cast([]u8)"testing");

        test_eq(buf.count, 0);
        ok, wire_type, field_number = decode_tag(*buf);
        test_eq(ok, false);
    }

    { // Test3
        buf = .[0x1a, 0x03, 0x08, 0x96, 0x01];
        ok, wire_type, field_number = decode_tag(*buf);
        test_eq(ok, true);
        test_eq(wire_type, .LEN);
        test_eq(field_number, 3);

        ok, len, submessage = decode_LEN(*buf);
        test_eq(ok, true);
        test_eq(len, 3);
        test_eq(submessage, u8.[0x08, 0x96, 0x01]);
        {
            buf := submessage; @shadow;
            ok, wire_type, field_number = decode_tag(*buf);
            test_eq(ok, true);
            test_eq(wire_type, .VARINT);
            test_eq(field_number, 1);

            ok, u = decode_VARINT(*buf);
            test_eq(ok, true);
            test_eq(u, 150);
        }

        test_eq(buf.count, 0);
        ok, wire_type, field_number = decode_tag(*buf);
        test_eq(ok, false);
    }

    {
        encbuf: [100]u8;
        decbuf: [100]u8;
        buf: []u8;

        index := encode_tag(encbuf, encbuf.count, .I64, 1);
        buf = encode_finish(encbuf, index);
        ok, wire_type, field_number := decode_tag(*buf);
        test_eq(ok, true);
        test_eq(wire_type, .I64);
        test_eq(field_number, 1);

        index = encode_tag(encbuf, encbuf.count, .I64, 16);
        buf = encode_finish(encbuf, index);
        ok, wire_type, field_number = decode_tag(*buf);
        test_eq(ok, true);
        test_eq(wire_type, .I64);
        test_eq(field_number, 16);

        index = encode_tag(encbuf, encbuf.count, .I64, 17);
        buf = encode_finish(encbuf, index);
        ok, wire_type, field_number = decode_tag(*buf);
        test_eq(ok, true);
        test_eq(wire_type, .I64);
        test_eq(field_number, 17);

        index = encode_tag(encbuf, encbuf.count, .I64, 100);
        buf = encode_finish(encbuf, index);
        ok, wire_type, field_number = decode_tag(*buf);
        test_eq(ok, true);
        test_eq(wire_type, .I64);
        test_eq(field_number, 100);

        index = encode_tag(encbuf, encbuf.count, .I64, 10000);
        buf = encode_finish(encbuf, index);
        ok, wire_type, field_number = decode_tag(*buf);
        test_eq(ok, true);
        test_eq(wire_type, .I64);
        test_eq(field_number, 10000);
    }
}


ProtoBasic1 :: #string END
syntax = "proto3";

message Test1 {
    int32 a = 1;
}
END


ProtoCorpus :: #string END
syntax = "proto3";

enum Corpus {
    CORPUS_UNSPECIFIED = 0;
    CORPUS_UNIVERSAL = 1;
    CORPUS_WEB = 2;
    CORPUS_IMAGES = 3;
    CORPUS_LOCAL = 4;
    CORPUS_NEWS = 5;
    CORPUS_PRODUCTS = 6;
    CORPUS_VIDEO = 7;
}

message SearchRequest {
    string query = 1;
    int32 page_number = 2;
    int32 results_per_page = 3;
    Corpus corpus = 4;
}
END

ProtoRepeated :: #string END
    syntax = "proto3";
    message Point2D {
        repeated int32 x = 1;
        repeated int32 y = 2;
    }
END;

ProtoAllTypes :: #string END
    syntax = "proto3";
    enum SomeEnum {
        ENUM_ZERO = 0;
        ENUM_ONE = 1;
    }
    message SubMessage {
        float x = 54;
    }
    message AllTypes {
        int32      _i32      = 1;
        int64      _i64      = 2;
        uint32     _u32      = 3;
        uint64     _u64      = 4;
        bool       _bool     = 5;
        sint32     _sint32   = 6;
        sint64     _sint64   = 7;
        fixed32    _fixed32  = 8;
        sfixed32   _sfixed32 = 9;
        float      _float    = 10;
        fixed64    _fixed64  = 11;
        sfixed64   _sfixed64 = 12;
        double     _double   = 13;
        string     _string   = 14;
        bytes      _bytes    = 15;
        SomeEnum   _enum     = 16;
        SubMessage _message  = 17;

        repeated int32      rep_i32      = 31;
        repeated int64      rep_i64      = 32;
        repeated uint32     rep_u32      = 33;
        repeated uint64     rep_u64      = 34;
        repeated bool       rep_bool     = 35;
        repeated sint32     rep_sint32   = 36;
        repeated sint64     rep_sint64   = 37;
        repeated fixed32    rep_fixed32  = 38;
        repeated sfixed32   rep_sfixed32 = 39;
        repeated float      rep_float    = 40;
        repeated fixed64    rep_fixed64  = 41;
        repeated sfixed64   rep_sfixed64 = 42;
        repeated double     rep_double   = 43;
        repeated string     rep_string   = 44;
        repeated bytes      rep_bytes    = 45;
        repeated SomeEnum   rep_enum     = 46;
        repeated SubMessage rep_message  = 47;
    }
END;

ProtoOneOf :: #string END
message OneOf {
    int32 x = 1;
    oneof Plant {
        bool tree = 2;
        float twigs = 3;
    }
}
END;

test_parse :: () {
    p: ProtoFile;
    p = parse_proto_text(ProtoBasic1);
    test_eq(p.edition, "proto3");
    test_eq(p.definitions.count, 1);
    if p.definitions.count {
        test_eq(p.definitions[0].kind, .MESSAGE);
        test_eq(p.definitions[0].fields.count, 1);
        test_eq(p.definitions[0].fields[0].type_name, "int32");
        test_eq(p.definitions[0].fields[0].type, .INT32);
        test_eq(p.definitions[0].fields[0].name, "a");
        test_eq(p.definitions[0].fields[0].field_number, 1);
    }

    jai_code := generate_jai(p);
    test_eq(true, contains(jai_code, #string END
Test1 :: struct {
    a: s32;
}
    END));

    p = parse_proto_text(ProtoCorpus);
    jai_code = generate_jai(p);
    test_eq(true, contains(jai_code, #string END
Corpus :: enum {
    CORPUS_UNSPECIFIED :: 0;
    CORPUS_UNIVERSAL :: 1;
    CORPUS_WEB :: 2;
    CORPUS_IMAGES :: 3;
    CORPUS_LOCAL :: 4;
    CORPUS_NEWS :: 5;
    CORPUS_PRODUCTS :: 6;
    CORPUS_VIDEO :: 7;
}
    END));
    test_eq(true, contains(jai_code, #string END
SearchRequest :: struct {
    query: string;
    page_number: s32;
    results_per_page: s32;
    corpus: Corpus;
}
    END));


    p = parse_proto_text(ProtoRepeated);
    jai_code = generate_jai(p);
    test_eq(true, contains(jai_code, #string END
Point2D :: struct {
    x: [..]s32;
    y: [..]s32;
}
    END));

    p = parse_proto_text(#string END
        // With comments
        /* two kinds
            message X { int32 x = 1; }
        */
        message Y { int32 y = 1; /* int32 z = 2; */ }
    END);
    test_eq(p.definitions.count, 1);
    test_eq(p.definitions[0].name, "Y");
    test_eq(p.definitions[0].fields.count, 1);
    test_eq(p.definitions[0].fields[0].name, "y");

    // import, package, reserved, and options
    p = parse_proto_text(#string END
        edition = "2023";
        import "dir/other.proto";
        import public "dir/something.proto";
        package testies.two;

        message Test {
            float sicles = 69 [default = 1337];
            float lump = 70 [deprecated = true, default = 0];
            reserved 42, 100 to 200;
            reserved "ok", "dude"; // proto3
            reserved whatever, man; // edition 2023
        }
    END);
    test_eq(p.edition, "2023");
    test_eq(p.imports.count, 2);
    test_eq(p.imports[0], "dir/other.proto");
    test_eq(p.imports[1], "dir/something.proto");
    test_eq(p.package, "testies.two");
    test_eq(p.definitions.count, 1);
    test_eq(p.definitions[0].name, "Test");
    test_eq(p.definitions[0].fields.count, 2);
    test_eq(p.definitions[0].fields[0].name, "sicles");
    test_eq(p.definitions[0].fields[0].default, "1337");
    test_eq(p.definitions[0].fields[0].deprecated, false);
    test_eq(p.definitions[0].fields[1].name, "lump");
    test_eq(p.definitions[0].fields[1].default, "0");
    test_eq(p.definitions[0].fields[1].deprecated, true);

    // oneof parsing
    p = parse_proto_text(#string END
        message Body {
            float x = 1;
            oneof Appendage {
                int32 arms = 2;
                int32 legs = 3;
                float body_girth = 4;
            }
            double time = 8;
        }
    END);
    test_eq(p.definitions.count, 1);
    test_eq(p.definitions[0].name, "Body");
    test_eq(p.definitions[0].fields.count, 2);
    test_eq(p.definitions[0].fields[0].name, "x");
    test_eq(p.definitions[0].fields[1].name, "time");
    test_eq(p.definitions[0].one_ofs.count, 1);
    test_eq(p.definitions[0].one_ofs[0].name, "Appendage");
    test_eq(p.definitions[0].one_ofs[0].fields.count, 3);
    test_eq(p.definitions[0].one_ofs[0].fields[0].name, "arms");
    test_eq(p.definitions[0].one_ofs[0].fields[1].name, "legs");
    test_eq(p.definitions[0].one_ofs[0].fields[2].name, "body_girth");
    test_eq(p.definitions[0].one_ofs[0].fields[2].type, .FLOAT);

    // Nested Enum parsing
    p = parse_proto_text(#string END
        message M {
            int32 x = 1;

            enum E {
                v0 = 0;
                v1 = 1;
            }

            E v = 2;
        }
    END);
    test_eq(p.definitions.count, 1);
    test_eq(p.definitions[0].name, "M");
    test_eq(p.definitions[0].fields.count, 2);
    test_eq(p.definitions[0].fields[0].name, "x");
    test_eq(p.definitions[0].fields[1].name, "v");
    test_eq(p.definitions[0].subtypes.count, 1);
    test_eq(p.definitions[0].subtypes[0].name, "E");
    test_eq(p.definitions[0].subtypes[0].kind, .ENUM);
    test_eq(p.definitions[0].subtypes[0].fields.count, 2);
    test_eq(p.definitions[0].subtypes[0].fields[0].name, "v0");
    test_eq(p.definitions[0].subtypes[0].fields[1].name, "v1");
}


test_generate :: () {
    PRINT_GENERATED_CODE :: 0;

    {
        jai_code :: #run generate_jai(parse_proto_text(ProtoCorpus));
        #if PRINT_GENERATED_CODE { print("%\n\n", jai_code); }
        else {
            #insert jai_code;
            request: SearchRequest;
            request.query = "hello";
            request.page_number = 42;
            request.results_per_page = 69;
            request.corpus = .CORPUS_LOCAL;

            as_bytes := Serialize(request);

            decoded: SearchRequest;
            Deserialize(*decoded, as_bytes);
            test_eq(decoded.query, request.query);
            test_eq(decoded.page_number, request.page_number);
            test_eq(decoded.results_per_page, request.results_per_page);
            test_eq(decoded.corpus, request.corpus);
            FreeContents(*decoded);

            empty: SearchRequest;
            as_bytes = Serialize(empty);
            test_eq(as_bytes, u8.[]);
        }
    }

    {
        jai_code :: #run generate_jai(parse_proto_text(ProtoRepeated));
        #if PRINT_GENERATED_CODE { print("%\n\n", jai_code); }
        else {
            #insert jai_code;

            points: Point2D;
            array_add(*points.x, 1, 2, 3);
            array_add(*points.y, 9, 8, 7);
            as_bytes := Serialize(points);
            test_eq(as_bytes, u8.[0x08, 0x01, 0x08, 0x02, 0x08, 0x03, 0x10, 0x09, 0x10, 0x08, 0x10, 0x07]);

            decoded: Point2D;
            Deserialize(*decoded, as_bytes);
            test_eq(decoded.x.([]s32), .[1, 2, 3]);
            test_eq(decoded.y.([]s32), .[9, 8, 7]);
            FreeContents(*decoded);
        }
    }

    {
        jai_code :: #run generate_jai(parse_proto_text(ProtoAllTypes));
        #if PRINT_GENERATED_CODE { print("%\n\n", jai_code); }
        else {
            #insert jai_code;

            all_types: AllTypes;
            as_bytes := Serialize(all_types);
            test_eq(as_bytes, u8.[]);

            all_types._i32 = 99999;
            all_types._i64 = 99999;
            all_types._u32 = 99999;
            all_types._u64 = 99999;
            all_types._bool = true;
            all_types._sint32 = -99999;
            all_types._sint64 = -99999;
            all_types._fixed32 = -99999;
            all_types._sfixed32 = -99999;
            all_types._float = -99999;
            all_types._fixed64 = -99999;
            all_types._sfixed64 = -99999;
            all_types._double = -99999;
            all_types._string = "xxx";
            all_types._bytes = u8.[1,50,255];
            all_types._enum = .ENUM_ONE;
            all_types._message = SubMessage.{-1234.5};
            // Repeated must still encode 0s
            array_add(*all_types.rep_i32, 0, 1, -88888);
            array_add(*all_types.rep_i64, 0, 1, -88888);
            array_add(*all_types.rep_u32, 0, 1, 88888);
            array_add(*all_types.rep_u64, 0, 1, 88888);
            array_add(*all_types.rep_bool, true, false, true);
            array_add(*all_types.rep_sint32, 0, 1, -88888);
            array_add(*all_types.rep_sint64, 0, 1, -88888);
            array_add(*all_types.rep_fixed32, 0, 1, -88888);
            array_add(*all_types.rep_sfixed32, 0, 1, -88888);
            array_add(*all_types.rep_float, 0, 1, -88888);
            array_add(*all_types.rep_fixed64, 0, 1, -88888);
            array_add(*all_types.rep_sfixed64, 0, 1, -88888);
            array_add(*all_types.rep_double, 0, 1, -88888);
            array_add(*all_types.rep_string, "", "aaa", "bbbbb");
            array_add(*all_types.rep_bytes, .[], .[22, 0], .[44, 255, 77]);
            array_add(*all_types.rep_enum, .ENUM_ONE, .ENUM_ZERO, .ENUM_ONE);
            array_add(*all_types.rep_message, .{0.0}, .{1238.1}, .{-51285.12});
            as_bytes = Serialize(all_types);

            decoded: AllTypes;
            Deserialize(*decoded, as_bytes);

            test_eq(decoded._i32, all_types._i32);
            test_eq(decoded._i64, all_types._i64);
            test_eq(decoded._u32, all_types._u32);
            test_eq(decoded._u64, all_types._u64);
            test_eq(decoded._bool, all_types._bool);
            test_eq(decoded._sint32, all_types._sint32);
            test_eq(decoded._sint64, all_types._sint64);
            test_eq(decoded._fixed32, all_types._fixed32);
            test_eq(decoded._sfixed32, all_types._sfixed32);
            test_eq(decoded._float, all_types._float);
            test_eq(decoded._fixed64, all_types._fixed64);
            test_eq(decoded._sfixed64, all_types._sfixed64);
            test_eq(decoded._double, all_types._double);
            test_eq(decoded._string, all_types._string);
            test_eq(decoded._bytes, all_types._bytes);
            test_eq(decoded._enum, all_types._enum);
            test_eq(decoded._message.x, all_types._message.x);
            test_eq(decoded.rep_i32, all_types.rep_i32);
            test_eq(decoded.rep_i64, all_types.rep_i64);
            test_eq(decoded.rep_u32, all_types.rep_u32);
            test_eq(decoded.rep_u64, all_types.rep_u64);
            test_eq(decoded.rep_bool, all_types.rep_bool);
            test_eq(decoded.rep_sint32, all_types.rep_sint32);
            test_eq(decoded.rep_sint64, all_types.rep_sint64);
            test_eq(decoded.rep_fixed32, all_types.rep_fixed32);
            test_eq(decoded.rep_sfixed32, all_types.rep_sfixed32);
            test_eq(decoded.rep_float, all_types.rep_float);
            test_eq(decoded.rep_fixed64, all_types.rep_fixed64);
            test_eq(decoded.rep_sfixed64, all_types.rep_sfixed64);
            test_eq(decoded.rep_double, all_types.rep_double);
            test_eq(decoded.rep_string, all_types.rep_string);
            test_eq(decoded.rep_bytes, all_types.rep_bytes);
            test_eq(decoded.rep_enum, all_types.rep_enum);
            test_eq(decoded.rep_message.count, all_types.rep_message.count);
            for decoded.rep_message  test_eq(it.x, all_types.rep_message[it_index].x);
            FreeContents(*decoded);
        }
    }

    {
        jai_code :: #run generate_jai(parse_proto_text(ProtoOneOf));
        #if PRINT_GENERATED_CODE { print("%\n\n", jai_code); }
        else {
            #insert jai_code;

            message: OneOf;
            as_bytes := Serialize(message);
            test_eq(as_bytes, u8.[]);

            message.x = 1234;
            message.twigs = 1.0;
            message.Plant_kind = .twigs;
            as_bytes = Serialize(message);

            decoded: OneOf;
            Deserialize(*decoded, as_bytes);

            test_eq(decoded.x, 1234);
            test_eq(decoded.Plant_kind, .twigs);
            test_eq(decoded.twigs, 1.0);
            FreeContents(*decoded);
        }
    }

    {
        jai_code :: #run generate_jai(parse_proto_text(#string END
            message M {
                int32 x = 1;

                enum E {
                    v0 = 0;
                    v1 = 1;
                }

                E v = 2;
            }
        END));
        #if PRINT_GENERATED_CODE { print("%\n\n", jai_code); }
        else {
            #insert jai_code;

            message: M;
            as_bytes := Serialize(message);
            test_eq(as_bytes, u8.[]);

            message.x = 7;
            message.v = .v1;

            as_bytes = Serialize(message);
            // M.x = 7 --> field_number=1, wire_type=VARINT --> c000_1'000 = 08. Value -> 7 --> final: 08 07
            // M.v = 1 --> field_number=2, wire_type=VARINT --> c001_0'000 = 10. Value -> 1 --> final: 10 01
            test_eq(as_bytes, u8.[0x08, 0x07, 0x10, 0x01]);

            decoded: M;
            Deserialize(*decoded, as_bytes);
            test_eq(decoded.x, message.x);
            test_eq(decoded.v, message.v);
            FreeContents(*decoded);
        }
    }

    {
        jai_code :: #run generate_jai(parse_proto_text(#string END
            message M {
                int32 x = 1;

                message Sub {
                    int32 subx = 1;
                    int32 suby = 2;
                }

                Sub sub = 2;
            }
        END));
        #if PRINT_GENERATED_CODE { print("%\n\n", jai_code); }
        else {
            #insert jai_code;

            message: M;
            as_bytes := Serialize(message);
            test_eq(as_bytes, u8.[]);

            message.sub.subx = 2;
            message.sub.suby = 3;
            as_bytes = Serialize(message);
            // LEN: [Sub]
            // Sub.subx -> 000_1000, 0x02 -> 0x0802
            // Sub.suby -> 001_0000, 0x03 -> 0x1003
            // -> LEN(wire:2) of 4, field_number=2 -> 001_0'010 0x04 [bytes] -> 0x1204 []
            test_eq(as_bytes, u8.[0x12, 0x04, 0x08, 0x02, 0x10, 0x03]);

            decoded: M;
            Deserialize(*decoded, as_bytes);
            test_eq(decoded.sub.subx, message.sub.subx);
            test_eq(decoded.sub.suby, message.sub.suby);
            FreeContents(*decoded);
        }
    }

    {
        jai_code :: #run generate_jai(parse_proto_text(#string END
            message M {
                enum MyEnum {
                    v0 = 0;
                    v1 = 1;
                }
                message Sub {
                    MyEnum evalue = 2;
                }
                Sub sub = 1;
            }
        END));
        #if PRINT_GENERATED_CODE { print("%\n\n", jai_code); }
        else {
            #insert jai_code;

            message: M;
            as_bytes := Serialize(message);
            test_eq(as_bytes, u8.[]);

            message.sub.evalue = .v1;
            as_bytes = Serialize(message);
            // sub.evalue = .v1 -> value = 1, VARINT, field_number=2; --> 001_0'000 0x01 = 0x1001
            // sub: LEN(wire:2) of above length (2), field_number=1 -> 000_1'010 0x02 = 0x0A02
            test_eq(as_bytes, u8.[0x0A, 0x02, 0x10, 0x01]);

            decoded: M;
            Deserialize(*decoded, as_bytes);
            test_eq(decoded.sub.evalue, message.sub.evalue);
            FreeContents(*decoded);
        }
    }

    {
        jai_code :: #run generate_jai(parse_proto_text(#string END
            message M {
                enum MyEnum {
                    v0 = 0;
                    v1 = 1;
                }
                message Sub {
                    M.MyEnum evalue = 2;
                }
                Sub sub = 1;
            }
        END));
        #if PRINT_GENERATED_CODE { print("%\n\n", jai_code); }
        else {
            #insert jai_code;

            message: M;
            as_bytes := Serialize(message);
            test_eq(as_bytes, u8.[]);

            message.sub.evalue = .v1;
            as_bytes = Serialize(message);
            // sub.evalue = .v1 -> value = 1, VARINT, field_number=2; --> 001_0'000 0x01 = 0x1001
            // sub: LEN(wire:2) of above length (2), field_number=1 -> 000_1'010 0x02 = 0x0A02
            test_eq(as_bytes, u8.[0x0A, 0x02, 0x10, 0x01]);

            decoded: M;
            Deserialize(*decoded, as_bytes);
            test_eq(decoded.sub.evalue, message.sub.evalue);
            FreeContents(*decoded);
        }
    }

    {
        jai_code :: #run generate_jai(parse_proto_text(#string END
            message M {
                message Sub {
                    enum MyEnum {
                        v0 = 0;
                        v1 = 1;
                    }
                    Sub.MyEnum evalue = 2;
                }
                Sub sub = 1;
                Sub.MyEnum xvalue = 3;
            }
        END));
        #if PRINT_GENERATED_CODE { print("%\n\n", jai_code); }
        else {
            #insert jai_code;

            message: M;
            as_bytes := Serialize(message);
            test_eq(as_bytes, u8.[]);

            message.sub.evalue = .v1;
            message.xvalue = .v1;
            as_bytes = Serialize(message);
            test_eq(as_bytes, u8.[0x0A, 0x02, 0x10, 0x01, 0x18, 0x01]);

            decoded: M;
            Deserialize(*decoded, as_bytes);
            test_eq(decoded.sub.evalue, message.sub.evalue);
            test_eq(decoded.xvalue, message.xvalue);
            FreeContents(*decoded);
        }
    }

    {
        jai_code :: #run generate_jai(parse_proto_text(#string END
            message M {
                message Sub {
                    enum MyEnum {
                        v0 = 0;
                        v1 = 1;
                    }
                    .M.Sub.MyEnum evalue = 2;
                }
                Sub sub = 1;
                .M.Sub.MyEnum xvalue = 3;
            }
        END));
        #if PRINT_GENERATED_CODE { print("%\n\n", jai_code); }
        else {
            #insert jai_code;

            message: M;
            as_bytes := Serialize(message);
            test_eq(as_bytes, u8.[]);

            message.sub.evalue = .v1;
            message.xvalue = .v1;
            as_bytes = Serialize(message);
            test_eq(as_bytes, u8.[0x0A, 0x02, 0x10, 0x01, 0x18, 0x01]);

            decoded: M;
            Deserialize(*decoded, as_bytes);
            test_eq(decoded.sub.evalue, message.sub.evalue);
            test_eq(decoded.xvalue, message.xvalue);
            FreeContents(*decoded);
        }
    }

    {
        jai_code :: #run generate_jai(parse_proto_text(#string END
            message M {
                map<string, int32> name_mapping = 1;
                int32 x = 2;
            }
        END));
        #if PRINT_GENERATED_CODE { print("%\n\n", jai_code); }
        else {
            #insert jai_code;

            message: M;
            as_bytes := Serialize(message);
            test_eq(as_bytes, u8.[]);

            table_set(*message.name_mapping, "hello", 15);
            as_bytes = Serialize(message);
            // name_mapping is a repeated Message of { key=1; value=2; } on the wire
            // name_mapping[0].key == "hello" -> 000_1'010 0x05 "hello" -> 0x0A 05 "h" "e" "l" "l" "o"
            // name_mapping[0].value == 15 -> 001_0'000 0x0F -> 0x10 0F
            // Wrapped up in a LEN for the message, field_number = 1;
            //  LEN(wire:2) length 9 [] -> 000_1'010 0x09, [] -> 0x0A 0x09
            test_eq(as_bytes, u8.[0x0A, 0x09, 0x0A, 0x05, "h", "e", "l", "l", "o", 0x10, 0x0F]);

            decoded: M;
            Deserialize(*decoded, as_bytes);
            found, value := table_find(*decoded.name_mapping, "hello");
            test_eq(found, true);
            test_eq(value, 15);
            FreeContents(*decoded);

            // Free should remove all
            found, value = table_find(*decoded.name_mapping, "hello");
            test_eq(found, false);
            test_eq(value, 0);

            // Add multiple strings
            table_set(*message.name_mapping, "beef", 42);
            table_set(*message.name_mapping, "hawk", 701);
            as_bytes = Serialize(message);

            // Decode
            decoded = .{};
            Deserialize(*decoded, as_bytes);
            found, value = table_find(*decoded.name_mapping, "hello");
            test_eq(found, true);
            test_eq(value, 15);
            found, value = table_find(*decoded.name_mapping, "beef");
            test_eq(found, true);
            test_eq(value, 42);
            found, value = table_find(*decoded.name_mapping, "hawk");
            test_eq(found, true);
            test_eq(value, 701);
        }
    }

    {
        jai_code :: #run generate_jai(parse_proto_text(#string END
            message Struct {
                map<string, Value> fields = 1;
            }
            message Value {
                int32 x = 4;
            }
        END));
        #if PRINT_GENERATED_CODE { print("%\n\n", jai_code); }
        else {
            #insert jai_code;

            message: Struct;
            as_bytes := Serialize(message);
            test_eq(as_bytes, u8.[]);

            table_set(*message.fields, "hello", Value.{15});
            as_bytes = Serialize(message);
            // name_mapping is a repeated Message of { key=1; value=2; } on the wire
            // name_mapping[0].key == "hello" -> 000_1'010 0x05 "hello" -> 0x0A 05 "h" "e" "l" "l" "o"
            // name_mapping[0].value == Value.{15} -> LEN record containing VARINT =15
            // VARINT: 15: with tag=4
            // 010_0'000 0x0F -> 0x20 0F
            //                .value: LEN of 2, tag=2 -> 0001_0'010 0x02 -> 0x12 0x02
            // Wrapped up in a LEN for the message, field_number = 1;
            //  LEN(wire:2) length 11 [] -> 000_1'010 0x0b, [] -> 0x0A 0x09
            test_eq(as_bytes, u8.[0x0A, 0x0B, 0x0A, 0x05, "h", "e", "l", "l", "o", 0x12, 0x02, 0x20, 0x0F]);

            decoded: Struct;
            Deserialize(*decoded, as_bytes);
            found, value := table_find(*decoded.fields, "hello");
            test_eq(found, true);
            test_eq(value.x, 15);
            FreeContents(*decoded);
        }
    }
}


test_generate_from_file :: () {
    input_path :: "examples/protos/many_things.proto";
    output_path :: "examples/generated/many_things.proto.jai";
    make_directory_if_it_does_not_exist("examples/generated");

    resulting_code := generate_jai(parse_proto_file(input_path));
    ok := write_entire_file(output_path, resulting_code);
    test_eq(ok, true);
    if ok print("Generated %\n", output_path);
    else  print("Failed to generate %\n", output_path);
}


//// --- Testing ---

equal_bytes :: (a : []u8, b : []u8) -> bool {
    if a.count != b.count return false;
    for i : 0..a.count-1 {
        if a[i] != b[i] return false;
    }
    return true;
}

equal :: (a : []$T, b : []T) -> bool {
    if a.count != b.count return false;
    for i : 0..a.count-1 {
        if !equal(a[i], b[i]) return false;
    }
    return true;
}

equal :: (a : $T, b : T) -> bool
    #modify {
        ti := cast(*Type_Info) T;
        return ti.type != .ARRAY;
    }
{
    return a == b;
}

test_eq :: (a: $A, b: A, loc := #caller_location) {
    if !equal(a, b) {
        tests_failed += 1;
        log_error("ERROR: %\n   % != \n   %", loc_string(loc), a, b);
    }
}

loc_string :: (loc: Source_Code_Location) -> string {
    return tprint("%:%:%", loc.fully_pathed_filename, formatInt(loc.line_number, base=10), formatInt(loc.character_number, base=10));
}

tests_failed := 0;
