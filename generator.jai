/**
 * Parse protobuf files
 */

ProtoFile :: struct {
    source_path: string; // Optional; file path to the original .proto file
    edition: string; // Edition or syntax version. Syntax "proto3" is edition "proto3".
    package: string; // Namespacing package, if found
    definitions: [..]ProtoDefinition;
    options: [..]ProtoOption;
}

ProtoDefinition :: struct {
    kind : ProtoDefinitionKind;
    name: string;
    fields : [..]ProtoField;
    options: [..]ProtoOption;
    one_ofs : [..]ProtoDefinition; // "oneof" subtypes
}

ProtoDefinitionKind :: enum {
    MESSAGE;
    ENUM;
    ONE_OF;
}

ProtoField :: struct {
    type : ProtoType;
    type_name : string;
    repeated : bool; // 0 or more items
    optional : bool; // metadata
    required : bool; // metadata
    packed : bool = true; // pack repeated fields
    deprecated : bool;
    field_number: int;
    name: string;
    default: string; // Default value
    options: [..]ProtoOption;
}

ProtoValue :: union {
    sint : s64;
    uint : u64;
    floating : float64;
    str: string;
    bytes: []u8;
}

ProtoOption :: struct {
    name: string;
    value: string;
}

parse_proto :: (data: string, source_path: string = "") -> ProtoFile {
    out: ProtoFile;
    out.source_path = source_path;
    p: Parser;
    p.text = data;

    while parse_primary(*p, *out) {
    }

    return out;
}

generate_jai_free_function :: (sb: *String_Builder, definition: ProtoDefinition) {
    sb2: String_Builder;
    for field : definition.fields {
        if field.repeated {
            if field.type == {
                case .STRING;
                    print(*sb2, "    for  message.%  free(it);\n", field.name);
                case .BYTES;
                    print(*sb2, "    for  message.%  array_free(it);\n", field.name);
                case .MESSAGE;
                    print(*sb2, "    for* message.%  FreeContents(it);\n", field.name);
            }
            print(*sb2, "    array_reset(*message.%);\n", field.name);
        } else {
            if field.type == {
                case .STRING;
                    print(*sb2, "    free(message.%1); message.%1 = \"\";\n", field.name);
                case .BYTES;
                    print(*sb2, "    array_reset(*message.%1);\n", field.name);
                case .MESSAGE;
                    print(*sb2, "    FreeContents(*message.%);\n", field.name);
            }
        }
    }
    if builder_string_length(*sb2) == 0 {
        print(sb, "FreeContents :: inline (message: *%) {}\n", definition.name);
    } else {
        print(sb, "FreeContents :: (message: *%) {\n", definition.name);
        append_and_steal_buffers(sb, *sb2);
        print(sb, "}\n");
    }
}

generate_jai :: (p: ProtoFile) -> string {
    sb: String_Builder;

    print(*sb, "// !!! Automatically generated code !!!\n");
    if p.source_path  print(*sb, "// Generated from %\n", p.source_path);
    print(*sb, "\n");

    for definition : p.definitions {
        if #complete definition.kind == {
            case .MESSAGE;
                print(*sb, "% :: struct {\n", definition.name);
                for definition.fields  generate_jai_field(*sb, it, "    ");
                for definition.one_ofs {
                    generate_jai_oneof_enum(*sb, it);
                    print(*sb, "    using % : union {\n", it.name);
                    for it.fields  generate_jai_field(*sb, it, "        ");
                    print(*sb, "    }\n", it.name);
                }
                print(*sb, "}\n");
            case .ENUM;
                print(*sb, "% :: enum {\n", definition.name);
                for field : definition.fields {
                    print(*sb, "    % :: %;\n", field.name, formatInt(field.field_number, base=10));
                }
                print(*sb, "}\n");
            case .ONE_OF;
        }
    }

    print(*sb, "\n\n");

    print(*sb, "// Serialize any message type into bytes. Allocates memory.\n");
    print(*sb, "Serialize :: (message: $T) -> []u8 {\n");
    print(*sb, "    buf: []u8;\n");
    print(*sb, "    index := Serialize(buf, 0, message);\n");
    print(*sb, "    array_resize(*buf, -index, false);\n");
    print(*sb, "    index = Serialize(buf, buf.count, message);\n");
    print(*sb, "    assert(index == 0, \"Current index should be 0 but is \%\", index);\n");
    print(*sb, "    return buf;\n");
    print(*sb, "}\n\n");

    for definition : p.definitions {
        print(*sb, "\n");
        print(*sb, "ProtoType_% :: ProtoType.%;\n", definition.name, definition.kind);

        generate_jai_free_function(*sb, definition);

        if #complete definition.kind == {
            case .MESSAGE;
                print(*sb, "Serialize :: (output: []u8, index: s64, message: %, field_number := -1, force := false) -> index: s64 {\n", definition.name);
                print(*sb, "    default: %;\n", definition.name);
                print(*sb, "    start_index := index;\n");

                // Serialise backwards because the encoder encodes the last bytes first
                // so it will end up in the normal 'forward' order
                for < field : definition.fields {
                    print(*sb, "    ");
                    generate_jai_serialize_field(*sb, field, field.repeated, field.required);
                }
                for < oneof : definition.one_ofs {
                    print(*sb, "    if message.%_kind == {\n", oneof.name);
                    for field : oneof.fields {
                        print(*sb, "        case .%1; ", field.name);
                        generate_jai_serialize_field(*sb, field, required=true);
                    }
                    print(*sb, "    }\n", oneof.name);
                }
                print(*sb, "    if field_number >= 0 && (force || index != start_index)   index = encode_LEN_from_index(output, index, start_index, field_number);\n");
                print(*sb, "    return index;\n");
                print(*sb, "}\n");

                sbtmp: String_Builder;
                changed: bool;
                print(*sb, "Parse :: (message: *%, bytes: []u8) -> ok: bool, used: s64 = 0 {\n", definition.name);
                print(*sb, "    buf := bytes;\n");
                print(*sb, "    while buf {\n");
                print(*sb, "        ok, wire_type, field_number := decode_tag(*buf);\n");
                print(*sb, "        if !ok return false;\n");
                // Switch over wire's type, so we always advance over any unknown fields, and fields with mismatched types
                print(*sb, "        if wire_type == {\n");

                changed = false;
                print(*sb, "        case .VARINT;\n");
                print(*sb, "            ok=, decoded_value := decode_VARINT(*buf);  if !ok return false;\n");
                print(*sbtmp, "            if field_number == {\n");
                for field : definition.fields  changed |= generate_jai_parse_field(*sbtmp, definition, field, .VARINT, field.repeated);
                for definition.one_ofs  for field: it.fields  changed |= generate_jai_parse_field(*sbtmp, it, field, .VARINT, false);
                print(*sbtmp, "            }\n");
                if changed  append_and_steal_buffers(*sb, *sbtmp);
                reset(*sbtmp);

                changed = false;
                print(*sb, "        case .I32;\n");
                print(*sb, "            ok=, decoded_value := decode_I32(*buf);  if !ok return false;\n");
                print(*sbtmp, "            decoded_value_float := (*decoded_value).(*float32).*;\n");
                print(*sbtmp, "            if field_number == {\n");
                for field : definition.fields  changed |= generate_jai_parse_field(*sbtmp, definition, field, .I32, field.repeated);
                for definition.one_ofs  for field: it.fields  changed |= generate_jai_parse_field(*sbtmp, it, field, .I32, false);
                print(*sbtmp, "            }\n");
                if changed  append_and_steal_buffers(*sb, *sbtmp);
                reset(*sbtmp);

                changed = false;
                print(*sb, "        case .I64;\n");
                print(*sb, "            ok=, decoded_value := decode_I64(*buf);  if !ok return false;\n");
                print(*sbtmp, "            decoded_value_float := (*decoded_value).(*float64).*;\n");
                print(*sbtmp, "            if field_number == {\n");
                for field : definition.fields  changed |= generate_jai_parse_field(*sbtmp, definition, field, .I64, field.repeated);
                for definition.one_ofs  for field: it.fields  changed |= generate_jai_parse_field(*sbtmp, it, field, .I64, false);
                print(*sbtmp, "            }\n");
                if changed  append_and_steal_buffers(*sb, *sbtmp);
                reset(*sbtmp);

                changed = false;
                print(*sb, "        case .LEN;\n");
                print(*sb, "            ok=, _, submessage := decode_LEN(*buf);  if !ok return false;\n");
                print(*sbtmp, "            if field_number == {\n");
                for field : definition.fields  changed |= generate_jai_parse_field(*sbtmp, definition, field, .LEN, field.repeated);
                for definition.one_ofs  for field: it.fields  changed |= generate_jai_parse_field(*sbtmp, it, field, .LEN, false);
                print(*sbtmp, "            }\n");
                if changed  append_and_steal_buffers(*sb, *sbtmp);
                reset(*sbtmp);

                print(*sb, "        }\n");
                print(*sb, "    }\n");
                // Messages always use all of the bytes
                print(*sb, "    return true, bytes.count;\n");
                print(*sb, "}\n");
            case .ENUM;
                print(*sb, "Serialize :: (output: []u8, index: s64, enum_value: %, field_number := -1, force := false) -> index: s64 {\n", definition.name);
                print(*sb, "    value := cast(u64, enum_value);\n");
                print(*sb, "    if force || value != 0  index = encode_VARINT(output, index, value, field_number);\n");
                print(*sb, "    return index;\n");
                print(*sb, "}\n");
                print(*sb, "Parse :: (enum_value: *%, bytes: []u8) -> ok: bool, used: s64 {\n", definition.name);
                print(*sb, "    buf := bytes;\n");
                print(*sb, "    ok, value := decode_VARINT(*buf);\n");
                print(*sb, "    if !ok return false, 0;\n");
                print(*sb, "    enum_value.* = xx,no_check value;\n");
                print(*sb, "    used := bytes.count - buf.count;\n");
                print(*sb, "    return true, used;\n");
                print(*sb, "}\n");
            case .ONE_OF;
        }
    }

    return builder_to_string(*sb);
}

generate_jai_field :: (sb: *String_Builder, field: ProtoField, indent: string) {
    if field.repeated {
        print(sb, "%0%: [..]%", indent, field.name, jai_type(field.type, field.type_name));
    } else {
        print(sb, "%0%: %", indent, field.name, jai_type(field.type, field.type_name));
    }
    if field.default print(sb, " = %", field.default);
    print(sb, ";");
    if field.deprecated print(sb, " @deprecated");
    if field.optional print(sb, " @optional");
    if field.required print(sb, " @required");
    print(sb, "\n");
}


generate_jai_oneof_enum :: (sb: *String_Builder, oneof: ProtoDefinition) {
    assert(oneof.kind == .ONE_OF);

    print(sb, "    %_Kind :: enum {\n", oneof.name);
    print(sb, "        _UNSET;\n", oneof.name);
    for field : oneof.fields {
        print(sb, "        %;\n", field.name);
    }
    print(sb, "    }\n");
    print(sb, "    %1_kind: %1_Kind;\n", oneof.name);
}


generate_jai_serialize_field :: (sb: *String_Builder, field: ProtoField, repeated: bool = false, required: bool = false) {
    if repeated {
        print(sb, "for < message.% { ", field.name);
    } else {
        print(sb, "{ it := message.%; ", field.name);
    }

    may_omit := !(repeated || required);

    if #complete wire_type_for(field.type) == {
    case .VARINT;
        if may_omit print(sb, "if it != default.%1     ", field.name);
        if should_zigzag(field.type) {
            print(sb, "index = encode_VARINT_zigzag(output, index, it, %); }\n", formatInt(field.field_number));
        } else {
            print(sb, "index = encode_VARINT(output, index, xx,no_check it, %); }\n", formatInt(field.field_number));
        }
    case .I32;
        if may_omit print(sb, "if it != default.%1     ", field.name);
        print(sb, "index = encode_I32(output, index, it, %); }\n", formatInt(field.field_number));
    case .I64;
        if may_omit print(sb, "if it != default.%1     ", field.name);
        print(sb, "index = encode_I64(output, index, it, %); }\n", formatInt(field.field_number));
    case .LEN;
        if field.type == {
        case .STRING;
            if may_omit print(sb, "if it != default.%1     ", field.name);
            print(sb, "index = encode_string(output, index, it, %); }\n", formatInt(field.field_number));
        case .BYTES;
            if may_omit print(sb, "if !array_view_equal(message.%1, default.%1)     ", field.name);
            print(sb, "index = encode_bytes(output, index, it, %); }\n", formatInt(field.field_number));
        case .MESSAGE;
            force := ifx may_omit then "" else ", force=true";
            print(sb, "index = Serialize(output, index, it, %1%2); }\n", formatInt(field.field_number), force);
        case;
            log("Unknown LEN field for %", field);
        }
    case .SGROUP;
    case .EGROUP;
    }
}

generate_jai_parse_field :: (sb: *String_Builder, definition: ProtoDefinition, field: ProtoField, wire_type: WireType, repeated: bool) -> bool {
    // We have not detected the "real" types of subfields as Message vs Enum, and Message is assumed during parsing.
    // So we have some extra logic here to deal with it
    field_type := wire_type_for(field.type);
    changed: bool = false;

    set_kind :: (sb: *String_Builder, definition: ProtoDefinition, field: ProtoField) {
        if definition.kind == .ONE_OF {
            print(sb, " message.%_kind = .%;", definition.name, field.name);
        }
    }

    if wire_type == {
        case .VARINT;
            maybe_enum := field.type == .MESSAGE;
            if field_type == .VARINT || maybe_enum {
                print(sb, "            case %; ", formatInt(field.field_number));
                if maybe_enum  print(sb, "#if ProtoType_% == .ENUM { ", field.type_name);
                value_string := ifx should_zigzag(field.type) "unzigzag(decoded_value)" else "decoded_value";
                if repeated print(sb, "array_add(*message.%, xx,no_check %);", field.name, value_string);
                else              print(sb, "message.% = xx,no_check %;", field.name, value_string);
                set_kind(sb, definition, field);
                if maybe_enum  print(sb, " }");
                print(sb, "\n");
                changed = true;
            }
        case .I32;
            if field_type == .I32 {
                value_string := ifx field.type == .FLOAT "decoded_value_float" else "decoded_value";
                if repeated print(sb, "            case %; array_add(*message.%, %);", formatInt(field.field_number), field.name, value_string);
                else              print(sb, "            case %; message.% = %;",            formatInt(field.field_number), field.name, value_string);
                set_kind(sb, definition, field);
                print(sb, "\n");
                changed = true;
            }
        case .I64;
            if field_type == .I64 {
                value_string := ifx field.type == .DOUBLE "decoded_value_float" else "decoded_value";
                if repeated print(sb, "            case %; array_add(*message.%, %);", formatInt(field.field_number), field.name, value_string);
                else              print(sb, "            case %; message.% = %;",            formatInt(field.field_number), field.name, value_string);
                set_kind(sb, definition, field);
                print(sb, "\n");
                changed = true;
            }
        case .LEN;
            if field_type == .LEN {
                print(sb, "            case %; ", formatInt(field.field_number));
                if field.type == {
                    case .STRING;
                        if repeated  print(sb, "array_add(*message.%, copy_string(submessage.(string)));", field.name);
                        else               print(sb, "message.% = copy_string(submessage.(string));", field.name);
                    case .BYTES;
                        if repeated  print(sb, "array_add(*message.%, array_copy(submessage));", field.name);
                        else               print(sb, "message.% = array_copy(submessage);", field.name);
                    case .MESSAGE;
                        // Could be a repeated enum, or a Message
                        // Messages consume all of the bytes, and repeated enums may not
                        if repeated {
                            print(sb, "while true { ok=, used := Parse(array_add(*message.%), submessage); if !ok return false; submessage = array_view(submessage, used); if !submessage break; }", field.name);
                        } else {
                            print(sb, "if !Parse(*message.%, submessage)  return false;", field.name);
                        }
                }
                set_kind(sb, definition, field);
                print(sb, "\n");
                changed = true;
            } else if repeated && field_type == .VARINT {
                print(sb, "            case %; while submessage {", formatInt(field.field_number));
                print(sb, "ok=, decoded_value := decode_VARINT(*submessage); if !ok return false;");
                value_string := ifx should_zigzag(field.type) "unzigzag(decoded_value)" else "decoded_value";
                print(sb, " array_add(*message.%, xx,no_check %); }\n", field.name, value_string);
                changed = true;
            } else if repeated && field_type == .I32 {
                print(sb, "            case %; while submessage {", formatInt(field.field_number));
                if field.type == .FLOAT print(sb, "ok=, decoded_value := decode_I32_float(*submessage); if !ok return false;");
                else                    print(sb, "ok=, decoded_value := decode_I32(*submessage); if !ok return false;");
                print(sb, " array_add(*message.%, decoded_value); }\n", field.name);
                changed = true;
            } else if repeated && field_type == .I64 {
                print(sb, "            case %; while submessage {", formatInt(field.field_number));
                if field.type == .DOUBLE print(sb, "ok=, decoded_value := decode_I64_float(*submessage); if !ok return false;");
                else                     print(sb, "ok=, decoded_value := decode_I64(*submessage); if !ok return false;");
                print(sb, " array_add(*message.%, decoded_value); }\n", field.name);
                changed = true;
            }
    }
    return changed;
}


#scope_file

parse_primary :: (p: *Parser, out: *ProtoFile) -> keep_going: bool {
    ok, id := parse(p, TokenKind.ID);
    if !ok {
        t := next(p);
        return t.kind != .EOF;
    }

    if id == {
        case "syntax"; #through;
        case "edition";
            ok = parse(p, TokenKind.EQ);
            if !ok return true;
            ok=, str := parse(p, TokenKind.STRING);
            if !ok return true;
            ok = parse(p, TokenKind.SEMICOLON);
            if !ok return true;
            out.edition = str;
        case "import";
            ok = parse_import(p);
        case "option";
            ok=, option := parse_option(p);
        case "package";
            ok=, package := parse_package(p);
            out.package = package;
        case "message";
            ok=, message_name := parse(p, .ID);
            if !ok return true;

            definition: *ProtoDefinition = array_add(*out.definitions);
            definition.kind = .MESSAGE;
            definition.name = message_name;

            ok = parse(p, .OCURLY);
            if !ok return true;

            parse_message_fields(p, definition);
            return true;
        case "enum";
            ok=, message_name := parse(p, .ID);
            if !ok return true;

            definition: *ProtoDefinition = array_add(*out.definitions);
            definition.kind = .ENUM;
            definition.name = message_name;

            ok = parse(p, .OCURLY);
            if !ok return true;
            t: Token;
            while t.kind != .EOF {
                t = peek(p);
                if t.kind == .CCURLY {
                    next(p);
                    break;
                }
                if t.kind == .ID {
                    parse_field(p, definition);
                } else {
                    log("Unknown item in enum: %", t);
                    next(p);
                }
            }
            return true;
        case;
            log("Unknown ID %", id);
    }

    return true;
}

parse_option :: (p: *Parser) -> ok: bool, option: ProtoOption {
    // "option" already popped
    t: Token;
    ok: bool;
    text: string;
    option: ProtoOption;

    ok, text = parse(p, .ID);
    if !ok return false, option;
    option.name = text;

    ok, text = parse(p, .EQ);
    if !ok return false, option;

    t = next(p);
    option.value = ifx t.value then t.value else t.text;

    parse(p, .SEMICOLON);
    return true, option;
}

parse_field_option :: (p: *Parser) -> ok:bool, option: ProtoOption {
    t: Token;
    option: ProtoOption;

    t = peek(p);
    if t.kind != .ID return false, option;
    option.name = t.text;
    next(p);

    if !parse(p, .EQ) return false, option;

    t = next(p);
    option.value = t.text;

    t = next(p);
    if t.kind == .CSQUARE then return true, option;
    if t.kind == .COMMA then return true, option;
    log("Unexpected field option token at end of option: %", t);
    return true, option;
}

parse_import :: (p: *Parser) -> ok: bool {
    // Called after "import" is popped
    t: Token;
    t = next(p);
    if t.kind == .ID {
        if t.text == "public" {
            t = next(p);
        }
        else return false;
    }
    if t.kind != .STRING return false;
    t = next(p);
    if t.kind != .SEMICOLON return false;
    return true;
}

parse_reserved :: (p: *Parser, definition: *ProtoDefinition) -> ok: bool {
    next(p); // The reserved word
    t: Token;
    // Skip all
    while true {
        t = next(p);
        if t.kind == {
        case .SEMICOLON; break;
        case .EOF; break;
        case .NUMBER;
        case .COMMA;
        case .STRING;
        case .ID; // Can be "1 to 200", and in editions plain "reserved foo;"
        case;
            log("Unknown token while parsing reserved fields: %", t);
            return false;
        }
    }
    return true;
}

parse_message_fields :: (p: *Parser, definition: *ProtoDefinition) -> ok: bool {
    t: Token;
    while true {
        t = peek(p);
        if t.kind == .EOF return false;
        if t.kind == .CCURLY {
            next(p);
            break;
        }
        if t.kind == .ID {
            if t.text == {
            case "reserved"; parse_reserved(p, definition);
            case "oneof";    parse_oneof(p, definition);
            case;
                parse_field(p, definition);
            }
        } else {
            log("Unknown item when looking for a message field: %", t);
            next(p);
        }
    }
    return true;
}

parse_oneof :: (p: *Parser, definition: *ProtoDefinition) -> ok: bool {
    next(p); // skip "oneof"
    t: Token;
    ok, text := parse(p, .ID);
    if !ok return false;

    item: ProtoDefinition;
    item.kind = .ONE_OF;
    item.name = text;

    ok, text = parse(p, .OCURLY);
    if !ok return false;

    ok = parse_message_fields(p, *item);
    if !ok return false;

    array_add(*definition.one_ofs, item);

    return true;
}

parse_package :: (p: *Parser) -> ok: bool, package: string {
    t: Token;

    ok, text := parse(p, .ID);
    if !ok return false, "";

    parse(p, .SEMICOLON);
    return true, text;
}


parse_field :: (p: *Parser, definition: *ProtoDefinition) -> ok: bool {
    field: *ProtoField = array_add(*definition.fields);

    while true {
        t : Token = peek(p);
        if t.text == {
            case "optional";
                field.optional = true;
                next(p);
            case "required";
                field.required = true;
                next(p);
            case "repeated";
                field.repeated = true;
                next(p);
            case;
                break;
        }
    }

    if definition.kind != .ENUM {
        ok, type_name := parse(p, .ID);
        if !ok return false;

        field.type_name = type_name;
        field.type = proto_type(type_name);
    }

    ok, name := parse(p, .ID);
    if !ok return false;
    field.name = name;

    ok = parse(p, .EQ);
    if !ok return false;

    ok=, number_str := parse(p, .NUMBER);
    if !ok return false;
    field.field_number = string_to_int(number_str);

    t := peek(p);
    if t.kind == .OSQUARE {
        next(p);
        while true {
            subok, option := parse_field_option(p);
            if !subok break;
            if option.name == {
                case "deprecated"; field.deprecated = option.value == "true";
                case "packed";     field.packed = option.value == "true";
                case "default";    field.default = option.value;
                case; array_add(*field.options, option);
            }
        }
    }

    ok = parse(p, .SEMICOLON);
    if !ok return false;

    return true;
}


parse :: (p: *Parser, kind: TokenKind) -> ok: bool, text: string {
    t := peek(p);
    if t.kind != kind {
        if t.kind != .EOF  log(" > Expected % but got %", kind, t);
        return false, "";
    }
    next(p);
    if t.value return true, t.value;
    return true, t.text;
}


next :: (p: *Parser) -> Token {
    t := peek(p);
    advance(*p.text, t.text.count);
    return t;
}

slice :: (str: string, index: int) -> string {
    return slice(str, index, str.count - index);
}

peek :: (p: *Parser) -> Token {
    // Eat whitespace and comments
    while p.text {
        if is_space(p.text[0]) {
            advance(*p.text);
        } else if starts_with(p.text, "//") {
            found_at := find_index_from_left(p.text, "\n");
            if found_at == -1 { advance(*p.text, p.text.count); break; }
            advance(*p.text, found_at + 1);
        } else if starts_with(p.text, "/*") {
            found_at := find_index_from_left(p.text, "*/");
            if found_at == -1 { log("Unterminated comment"); advance(*p.text, p.text.count); break; }
            advance(*p.text, found_at + 2);
        } else {
            break;
        }
    }

    str := p.text;
    if !str return .{kind = .EOF};
    t: Token;
    i := 0;

    if is_any(str[i], ",;{}[]=") {
        t.text = slice(str, 0, 1);
        if str[i] == {
            case ",";
                t.kind = .COMMA;
                return t;
            case ";";
                t.kind = .SEMICOLON;
                return t;
            case "{";
                t.kind = .OCURLY;
                return t;
            case "}";
                t.kind = .CCURLY;
                return t;
            case "[";
                t.kind = .OSQUARE;
                return t;
            case "]";
                t.kind = .CSQUARE;
                return t;
            case "=";
                t.kind = .EQ;
                return t;
            case;
                assert(false, "Unreachable");
        }
    }

    while str[i] >= "0" && str[i] <= "9" {
        i += 1;
    }
    if i return Token.{kind = .NUMBER, text = slice(str, 0, i)};

    while is_alnum(str[i]) || str[i] == "." {
        i += 1;
    }
    if i return Token.{kind = .ID, text = slice(str, 0, i)};

    if str[0] == "\"" {
        i += 1;
        while i < str.count {
            if str[i] == "\\" {
                i += 2;
            } else if str[i] == "\"" {
                i += 1;
                t.kind = .STRING;
                t.text = slice(str, 0, i);
                t.value = slice(str, 1, i - 2);
                return t;
            } else {
                i += 1;
            }
        }
        // If reaching here, no end-of-" is found, so fail
        t.kind = .UNKNOWN;
        t.text = slice(str, 0, i);
    }

    // Unknown, TODO: eat all we can
    t.kind = .UNKNOWN;
    t.text = slice(str, 0, 1);

    return t;
}


Parser :: struct {
    text: string;
}

TokenKind :: enum {
    UNKNOWN;
    EOF; // end-of-file (end of string)

    SEMICOLON;
    OCURLY;
    CCURLY;
    OSQUARE;
    CSQUARE;
    EQ;
    COMMA; // between reserved field values

    ID; // Identifier (name)
    NUMBER;
    STRING;
}

Token :: struct {
    kind: TokenKind;
    text: string;
    value: string;
}

#import "String";
#import "Basic";
