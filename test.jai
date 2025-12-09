#load "module.jai";
#load "generator.jai";

main :: () {
    context.print_style.default_format_int.base = 16;
    context.print_style.default_format_int.minimum_digits = 2;

    test_misc();
    test_encode();
    test_decode();
    test_parse();
    test_generate();

    if tests_failed exit(1);
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

    // ----- message Test4 - repeated fields
    index = buf.count;
    index = encode_VARINT(buf, index, 3, 6);
    index = encode_VARINT(buf, index, 2, 6);
    index = encode_VARINT(buf, index, 1, 6);
    index = encode_string(buf, index, "hello", 4);
    print("Test4: %\n", encode_finish(rawbuf, index));

    // My example
    index = buf.count;
    index = encode_VARINT(buf, index, 100, 6);
    index = encode_string(buf, index, "hello", 4);
    index = encode_LEN_from_index(buf, index, submessage_end, 1);
    print("My example: %\n", encode_finish(buf, index));
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
}


BasicInput :: #string END
syntax = "proto3";

message Test1 {
    int32 a = 1;
}
END


CorpusInput :: #string END
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

test_parse :: () {
    p: ProtoFile;
    p = parse_proto(BasicInput);
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

    p = parse_proto(CorpusInput);
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
}


test_generate :: () {
    PRINT_GENERATED_CODE :: 0;

    {
        jai_code :: #run generate_jai(parse_proto(CorpusInput));
        #if PRINT_GENERATED_CODE print(jai_code);
        #insert jai_code;
        request: SearchRequest;
        request.query = "hello";
        request.page_number = 42;
        request.results_per_page = 69;
        request.corpus = .CORPUS_LOCAL;

        as_bytes := Serialize(request);
        print("Result = %\n", as_bytes);

        decoded: SearchRequest;
        Parse(*decoded, as_bytes);
        test_eq(decoded.query, request.query);
        test_eq(decoded.page_number, request.page_number);
        test_eq(decoded.results_per_page, request.results_per_page);
        test_eq(decoded.corpus, request.corpus);

        empty: SearchRequest;
        as_bytes = Serialize(empty);
        test_eq(as_bytes, u8.[]);
    }
}

// #run main();


//// --- Testing ---

equal :: (a : []$T, b : []T) -> bool {
    if a.count != b.count return false;
    for i : 0..a.count-1 {
        if a[i] != b[i] return false;
    }
    return true;
}

test_eq :: (a: $A, b: A, loc := #caller_location)
    #modify {
        ti := cast(*Type_Info) A;
        if ti.type == .ARRAY return false;
        return true;
    }
{
    if a != b {
        tests_failed += 1;
        log_error("ERROR: %\n   % != \n   %", loc_string(loc), a, b);
    }
}

test_eq :: (a: []$T, b: []T, loc := #caller_location) {
    if !equal(a, b) {
        tests_failed += 1;
        log_error("ERROR: %\n   % != \n   %", loc_string(loc), a, b);
    }
}

loc_string :: (loc: Source_Code_Location) -> string {
    return tprint("%:%:%", loc.fully_pathed_filename, formatInt(loc.line_number, base=10), formatInt(loc.character_number, base=10));
}

tests_failed := 0;
