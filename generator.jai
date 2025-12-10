/**
 * Parse protobuf files
 */

ProtoFile :: struct {
    edition: string; // Edition or syntax version. Syntax "proto3" is edition "proto3".
    definitions: [..]ProtoDefinition;
}

ProtoDefinition :: struct {
    kind : ProtoDefinitionKind;
    name: string;
    fields : [..]ProtoField;
}

ProtoDefinitionKind :: enum {
    MESSAGE;
    ENUM;
}

ProtoField :: struct {
    type : ProtoType;
    type_name : string;
    repeated : bool; // 0 or more items
    optional : bool; // metadata
    required : bool; // metadata
    field_number: int;
    name: string;
    default: string; // Default value
}

ProtoValue :: union {
    sint : s64;
    uint : u64;
    floating : float64;
    str: string;
    bytes: []u8;
}

parse_proto :: (data: string) -> ProtoFile {
    out: ProtoFile;
    p: Parser;
    p.text = data;

    while parse_primary(*p, *out) {
    }

    return out;
}

generate_jai :: (p: ProtoFile) -> string {
    sb: String_Builder;

    print(*sb, "// !!! Automatically generated code !!!\n\n");

    for definition : p.definitions {
        if #complete definition.kind == {
            case .MESSAGE;
                print(*sb, "% :: struct {\n", definition.name);
                for field : definition.fields {
                    if field.repeated {
                        print(*sb, "    %: [..]%", field.name, jai_type(field.type, field.type_name));
                    } else {
                        print(*sb, "    %: %", field.name, jai_type(field.type, field.type_name));
                    }
                    if field.default print(*sb, " = %", field.default);
                    print(*sb, ";");
                    if field.optional print(*sb, " @optional");
                    if field.required print(*sb, " @required");
                    print(*sb, "\n");
                }
                print(*sb, "}\n");
            case .ENUM;
                print(*sb, "% :: enum {\n", definition.name);
                for field : definition.fields {
                    print(*sb, "    % :: %;\n", field.name, formatInt(field.field_number, base=10));
                }
                print(*sb, "}\n");
        }
    }

    print(*sb, "\n\n");

    print(*sb, "Serialize :: (message: $T) -> []u8 {\n");
    print(*sb, "    buf: []u8;\n");
    print(*sb, "    index := Serialize(buf, 0, message);\n");
    print(*sb, "    array_resize(*buf, -index, false);\n");
    print(*sb, "    index = Serialize(buf, buf.count, message);\n");
    print(*sb, "    assert(index == 0, \"Current index should be 0 but is \%\", index);\n");
    print(*sb, "    return buf;\n");
    print(*sb, "}\n\n");

    for definition : p.definitions {
        if #complete definition.kind == {
            case .MESSAGE;
                print(*sb, "ProtoType_% :: ProtoType.%;\n", definition.name, definition.kind);
                print(*sb, "Serialize :: (output: []u8, index: s64, message: %, field_number := -1, force := false) -> index: s64 {\n", definition.name);
                print(*sb, "    default: %;\n", definition.name);
                print(*sb, "    start_index := index;\n");

                // Serialise backwards because the encoder encodes the last bytes first
                // so it will end up in the normal 'forward' order
                for < field : definition.fields {
                    wire_type := wire_type_for(field.type);

                    if field.repeated {
                        print(*sb, "    for < message.% { ", field.name);
                    } else {
                        print(*sb, "    { it := message.%; ", field.name);
                    }

                    may_omit := !(field.repeated || field.required);

                    if #complete wire_type == {
                        case .VARINT;
                            if may_omit print(*sb, "if it != default.%1     ", field.name);
                            if should_zigzag(field.type) {
                                print(*sb, "index = encode_VARINT_zigzag(output, index, it, %); }\n", formatInt(field.field_number));
                            } else {
                                print(*sb, "index = encode_VARINT(output, index, xx,no_check it, %); }\n", formatInt(field.field_number));
                            }
                        case .I32;
                            if may_omit print(*sb, "if it != default.%1     ", field.name);
                            print(*sb, "index = encode_I32(output, index, it, %); }\n", formatInt(field.field_number));
                        case .I64;
                            if may_omit print(*sb, "if it != default.%1     ", field.name);
                            print(*sb, "index = encode_I64(output, index, it, %); }\n", formatInt(field.field_number));
                        case .LEN;
                            if field.type == {
                                case .STRING;
                                    if may_omit print(*sb, "if it != default.%1     ", field.name);
                                    print(*sb, "index = encode_string(output, index, it, %); }\n", formatInt(field.field_number));
                                case .BYTES;
                                    if may_omit print(*sb, "if !array_view_equal(message.%1, default.%1)     ", field.name);
                                    print(*sb, "index = encode_bytes(output, index, it, %); }\n", formatInt(field.field_number));
                                case .MESSAGE;
                                    force := ifx may_omit then "" else ", force=true";
                                    print(*sb, "index = Serialize(output, index, it, %1%2); }\n", formatInt(field.field_number), force);
                                case;
                                    log("Unknown LEN field for %", field);
                            }
                        case .SGROUP;
                        case .EGROUP;
                    }
                }
                print(*sb, "    if field_number >= 0 && (force || index != start_index)   index = encode_LEN_from_index(output, index, start_index, field_number);\n");
                print(*sb, "    return index;\n");
                print(*sb, "}\n\n");

                print(*sb, "Parse :: (message: *%, bytes: []u8) -> ok: bool, used: s64 = 0 {\n", definition.name);
                print(*sb, "    buf := bytes;\n");
                print(*sb, "    while buf {\n");
                print(*sb, "        ok, wire_type, field_number := decode_tag(*buf);\n");
                print(*sb, "        if !ok return false;\n");
                print(*sb, "        if field_number == {\n");
                for field : definition.fields {
                    wire_type := wire_type_for(field.type);

                    print(*sb, "            case %;\n", formatInt(field.field_number));
                    // TODO: Primitive types may be PACKED repeated, making .LEN also a valid type for the primitives
                    print(*sb, "                if wire_type == .% {\n", wire_type);
                    if #complete wire_type == {
                        case .VARINT;
                            if should_zigzag(field.type) {
                                print(*sb, "                    ok=, value := decode_VARINT_zigzag(*buf);\n", field.name);
                                print(*sb, "                    if !ok return false;\n");
                                if field.repeated  print(*sb, "                    array_add(*message.%, xx,no_check value);\n", field.name);
                                else               print(*sb, "                    message.% = xx,no_check value;\n", field.name);
                            } else {
                                print(*sb, "                    ok=, value := decode_VARINT(*buf);\n");
                                print(*sb, "                    if !ok return false;\n");
                                if field.repeated  print(*sb, "                    array_add(*message.%, xx,no_check value);\n", field.name);
                                else               print(*sb, "                    message.% = xx,no_check value;\n", field.name);
                            }
                        case .I32;
                            if field.type == .FLOAT print(*sb, "                    ok=, value := decode_I32_float(*buf);\n", field.name);
                            else                    print(*sb, "                    ok=, value := decode_I32(*buf);\n", field.name);
                            print(*sb, "                    if !ok return false;\n");
                            if field.repeated  print(*sb, "                    array_add(*message.%, value);\n", field.name);
                            else               print(*sb, "                    message.% = value;\n", field.name);
                        case .I64;
                            if field.type == .DOUBLE print(*sb, "                    ok=, value := decode_I64_float(*buf);\n", field.name);
                            else                     print(*sb, "                    ok=, value := decode_I64(*buf);\n", field.name);
                            print(*sb, "                    if !ok return false;\n");
                            if field.repeated  print(*sb, "                    array_add(*message.%, value);\n", field.name);
                            else               print(*sb, "                    message.% = value;\n", field.name);
                        case .LEN;
                            // Len which is not a message or enum
                            print(*sb, "                    ok=, _, submessage := decode_LEN(*buf);\n", field.name);
                            print(*sb, "                    if !ok return false;\n");
                            if field.type == {
                                case .STRING;
                                    if field.repeated  print(*sb, "                    array_add(*message.%, copy_string(submessage.(string)));\n", field.name);
                                    else               print(*sb, "                    message.% = copy_string(submessage.(string));\n", field.name);
                                case .BYTES;
                                    if field.repeated  print(*sb, "                    array_add(*message.%, array_copy(submessage));\n", field.name);
                                    else               print(*sb, "                    message.% = array_copy(submessage);\n", field.name);
                                case .MESSAGE;
                                    // Could be a repeated enum, or a Message
                                    // Messages consume all of the bytes, and repeated enums may not
                                    if field.repeated {
                                        print(*sb, "                    ok=, used := Parse(array_add(*message.%), submessage); if !ok return false;\n", field.name);
                                    } else {
                                        print(*sb, "                    ok=, used := Parse(*message.%, submessage); if !ok return false;\n", field.name);
                                    }
                                    // Not .LEN type, so must be an enum
                                    print(*sb, "                } else if wire_type == .VARINT {\n");
                                    if field.repeated {
                                        print(*sb, "                    ok=, used := Parse(array_add(*message.%), buf); if !ok return false;\n", field.name);
                                    } else {
                                        print(*sb, "                    ok=, used := Parse(*message.%, buf); if !ok return false;\n", field.name);
                                    }
                                    print(*sb, "                    buf = array_view(buf, used);\n");
                                case .PACKED_REPEATED;
                            }
                        case .SGROUP;
                        case .EGROUP;
                    }
                    print(*sb, "                }\n");
                }
                print(*sb, "        }\n");
                print(*sb, "    }\n");
                // Messages always use all of the bytes
                print(*sb, "    return true, bytes.count;\n");
                print(*sb, "}\n\n");
            case .ENUM;
                print(*sb, "ProtoType_% :: ProtoType.%;\n", definition.name, definition.kind);
                print(*sb, "Serialize :: (output: []u8, index: s64, enum_value: %, field_number := -1, force := false) -> index: s64 {\n", definition.name);
                print(*sb, "    value := cast(u64, enum_value);\n");
                print(*sb, "    if force || value != 0  index = encode_VARINT(output, index, value, field_number);\n");
                print(*sb, "    return index;\n");
                print(*sb, "}\n\n");
                print(*sb, "Parse :: (enum_value: *%, bytes: []u8) -> ok: bool, used: s64 {\n", definition.name);
                print(*sb, "    buf := bytes;\n");
                print(*sb, "    ok, value := decode_VARINT(*buf);\n");
                print(*sb, "    if !ok return false, 0;\n");
                print(*sb, "    enum_value.* = xx,no_check value;\n");
                print(*sb, "    used := bytes.count - buf.count;\n");
                print(*sb, "    return true, used;\n");
                print(*sb, "}\n\n");
        }
    }

    return builder_to_string(*sb);
}

#scope_file

parse_primary :: (p: *Parser, out: *ProtoFile) -> keep_going: bool {
    ok, id := parse(p, TokenKind.ID);
    if !ok {
        t := next(p);
        return t.kind != .EOF;
    }

    if id == {
        case "syntax";
            ok = parse(p, TokenKind.EQ);
            if !ok return true;
            ok=, str := parse(p, TokenKind.STRING);
            if !ok return true;
            ok = parse(p, TokenKind.SEMICOLON);
            if !ok return true;
            out.edition = str;
        case "message";
            ok=, message_name := parse(p, .ID);
            if !ok return true;

            definition: *ProtoDefinition = array_add(*out.definitions);
            definition.kind = .MESSAGE;
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
                    log("Unknown item in message: %", t);
                    next(p);
                }
            }
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

    if definition.kind == .MESSAGE {
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

    ok = parse(p, .SEMICOLON);
    if !ok return false;

    return true;
}


parse :: (p: *Parser, kind: TokenKind) -> ok: bool, text: string {
    t := peek(p);
    if t.kind != kind {
        log(" > Expected % but got %", kind, t);
        return false, "";
    }
    next(p);
    if t.value return true, t.value;
    return true, t.text;
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
    EQ;

    ID; // Identifier (name)
    NUMBER;
    STRING;
}

Token :: struct {
    kind: TokenKind;
    text: string;
    value: string;
}

next :: (p: *Parser) -> Token {
    t := peek(p);
    advance(*p.text, t.text.count);
    return t;
}

peek :: (p: *Parser) -> Token {
    p.text = trim_left(p.text);
    str := p.text;
    if !str return .{kind = .EOF};
    t: Token;
    i := 0;

    if is_any(str[i], ";{}=") {
        t.text = slice(str, 0, 1);
        if str[i] == {
            case ";";
                t.kind = .SEMICOLON;
                return t;
            case "{";
                t.kind = .OCURLY;
                return t;
            case "}";
                t.kind = .CCURLY;
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

    while is_alnum(str[i]) {
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

#import "String";
