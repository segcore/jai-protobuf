/**
 * Parse protobuf files and generate Jai
 * - Structs / Enums
 * - Serializer functions
 * - Deserializer functions
 */

ProtoFile :: struct {
    source_path: string; // Optional; file path to the original .proto file
    edition: string; // Edition or syntax version. Syntax "proto3" is edition "proto3".
    package: string; // Namespacing package, if found
    definitions: [..]ProtoDefinition;
    options: [..]ProtoOption;
    imports: [..]string;
}

ProtoDefinition :: struct {
    kind : ProtoDefinitionKind;
    name: string;
    fields : [..]ProtoField;
    options: [..]ProtoOption;
    one_ofs : [..]ProtoDefinition; // "oneof" subtypes
    subtypes : [..]ProtoDefinition; // "enum" and "message" subtypes defined here
    parent: *ProtoDefinition; // Definition which contains this. Null at the root.
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
    map: bool;
    map_key : string;
    map_value : string;
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

INDENT :: 4;

parse_proto_text :: (data: string, source_path: string = "") -> ProtoFile {
    out: ProtoFile;
    out.source_path = source_path;
    p: Parser;
    p.text = data;

    while parse_primary(*p, *out) {
    }

    logging_source_path := ifx source_path then source_path else "-";
    if !data {
        log("Parsing an empty protobuf text from %", logging_source_path, flags=.WARNING);
    } else if out.definitions.count == 0 {
        log("No definitions found when parsing %", logging_source_path, flags=.WARNING);
    }

    return out;
}

// Parse the protobuf description file
parse_proto_file :: (source_path: string) -> ProtoFile {
    return parse_proto_text(read_entire_file(source_path), source_path);
}


// Generate Jai code as a string.
// protobuf_import: Name of Protobuf module which will be imported within the generated text
generate_jai :: (p: ProtoFile, protobuf_import := "") -> string {
    if !p.definitions return "";

    sb: String_Builder;

    print(*sb, "// !!! Automatically generated code !!!\n");

    if p.source_path  print(*sb, "// Generated from %\n", p.source_path);
    print(*sb, "#import \"Hash_Table\";\n");
    print(*sb, "#import \"Basic\";\n");
    if protobuf_import {
        if wildcard_match(protobuf_import, "[./]*") print(*sb, "#import,dir \"%\";\n", protobuf_import);
        else print(*sb, "#import \"%\";\n", protobuf_import);
    }
    print(*sb, "\n");

    for p.definitions  generate_definition(*sb, it); 

    print(*sb, "\n");

    generate_jai_for_definitions(*sb, p.definitions);

    return builder_to_string(*sb);
}

// Generate Jai code for all files given, searching in given import directories.
generate_jai_for_all :: (input_protos: []string, import_dirs: []string = .[], protobuf_import := "") -> jai: string, failed_imports: []string {
    imported_protos: [..]string;
    defer array_free(imported_protos);
    array_add(*imported_protos, ..input_protos);

    failed_imports: [..]string;
    code_builder: String_Builder;

    for input_path : input_protos {
        proto_file := parse_proto_file(input_path);
        code := generate_jai(proto_file, protobuf_import=protobuf_import);
        if !code {
            array_add(*failed_imports, input_path);
            log("Failed to find input proto file '%'", input_path, flags=.WARNING);
            continue;
        }

        append(*code_builder, code);

        for import : proto_file.imports {
            import_recursive(*code_builder, import, import_dirs, protobuf_import, *imported_protos, *failed_imports);
        }
    }

    jai := builder_to_string(*code_builder);
    return jai, failed_imports;
}


// -------------
// You probably won't need functions below here.
// -------------

import_recursive :: (code_builder: *String_Builder, import_path: string, import_dirs: []string, protobuf_import: string, imported_protos: *[..]string, failed_imports: *[..]string) {
    found_this_import := false;
    for search_dir : import_dirs {
        full_import_path: string;
        if search_dir {
            full_import_path = sprint("%/%", search_dir, import_path,, temp);
        } else {
            full_import_path = import_path;
        }

        // Don't reimport the same files over and over
        if !array_find(imported_protos.*, full_import_path) {
            contents, ok := read_entire_file(full_import_path);
            if ok {
                log("Generating code for import '%'", import_path);
                import_proto_file := parse_proto_text(contents);
                code := generate_jai(import_proto_file, protobuf_import=protobuf_import);
                append(code_builder, code);
                array_add(imported_protos, full_import_path);
                found_this_import = true;

                for subimport : import_proto_file.imports {
                    import_recursive(code_builder, subimport, import_dirs, protobuf_import, imported_protos, failed_imports);
                }
                break;
            }
        }
    }

    if !found_this_import {
        array_add(failed_imports, import_path);
        log("Failed to find an import path for '%'", import_path, flags=.WARNING);
    }
}


generate_definition :: (sb: *String_Builder, definition: ProtoDefinition, indent_level := 0) {
    indent := indent_str(indent_level);
    if #complete definition.kind == {
        case .MESSAGE;
            print(sb, "%0% :: struct {\n", indent, definition.name);
            for definition.fields    generate_jai_field(sb, it, indent_level + 1);
            for definition.one_ofs   generate_definition(sb, it, indent_level + 1);
            for definition.subtypes  generate_definition(sb, it, indent_level + 1);
            print(sb, "%}\n", indent);
        case .ENUM;
            print(sb, "%0% :: enum {\n", indent, definition.name);
            for field : definition.fields {
                print(sb, "%    % :: %;\n", indent, field.name, formatInt(field.field_number, base=10));
            }
            print(sb, "%}\n", indent);
        case .ONE_OF;
            indent := indent_str(indent_level);
            // Generate Enum for Kind
            print(sb, "%0%_Kind :: enum {\n", indent, definition.name);
            print(sb, "%    _UNSET;\n", indent, definition.name);
            for field : definition.fields {
                print(sb, "%    %;\n", indent, field.name);
            }
            print(sb, "%}\n", indent);
            print(sb, "%0%2_kind: %2_Kind;\n", indent, definition.name);

            // Generate fields
            print(sb, "%using % : union {\n", indent, definition.name);
            for definition.fields  generate_jai_field(sb, it, indent_level + 1);
            print(sb, "%}\n", indent, definition.name);
    }
}


generate_jai_for_definitions :: (sb: *String_Builder, set: []ProtoDefinition) {
    for definition : set {
        generate_jai_for_definitions(sb, definition.subtypes);

        id_name := build_path_up(definition, "_");
        dotted_name := build_path_up(definition, ".");

        print(sb, "\n");
        print(sb, "ProtoType_% :: ProtoType.%;\n", id_name, definition.kind);

        if #complete definition.kind == {
            case .MESSAGE;
                print(sb, "Serialize :: (output: []u8, index: s64, message: %, field_number := -1, force := false) -> index: s64 {\n", dotted_name);
                print(sb, "    default: %;\n", dotted_name);
                print(sb, "    start_index := index;\n");

                // Serialise backwards because the encoder encodes the last bytes first
                // so it will end up in the normal 'forward' order
                for < field : definition.fields {
                    print(sb, "    ");
                    generate_jai_serialize_field(sb, field, field.repeated, field.required);
                }
                for < oneof : definition.one_ofs {
                    print(sb, "    if message.%_kind == {\n", oneof.name);
                    for field : oneof.fields {
                        print(sb, "        case .%1; ", field.name);
                        generate_jai_serialize_field(sb, field, required=true);
                    }
                    print(sb, "    }\n", oneof.name);
                }
                print(sb, "    if field_number >= 0 && (force || index != start_index)   index = encode_LEN_from_index(output, index, start_index, field_number);\n");
                print(sb, "    return index;\n");
                print(sb, "}\n");
                print(sb, "Serialize :: (message: %) -> []u8 { buf := NewArray(-Serialize(u8.[], 0, message), u8, false); Serialize(buf, buf.count, message); return buf; }\n", dotted_name);

                sbtmp: String_Builder;
                changed: bool;
                print(sb, "Deserialize :: (message: *%, bytes: []u8) -> ok: bool, used: s64 = 0 {\n", dotted_name);
                print(sb, "    buf := bytes;\n");
                print(sb, "    while buf {\n");
                print(sb, "        ok, wire_type, field_number := decode_tag(*buf);\n");
                print(sb, "        if !ok return false;\n");
                // Switch over wire's type, so we always advance over any unknown fields, and fields with mismatched types
                print(sb, "        if wire_type == {\n");

                changed = false;
                print(sb, "        case .VARINT;\n");
                print(sb, "            ok=, decoded_value := decode_VARINT(*buf);  if !ok return false;\n");
                print(*sbtmp, "            if field_number == {\n");
                for field : definition.fields  changed |= generate_jai_parse_field(*sbtmp, definition, field, .VARINT, field.repeated);
                for definition.one_ofs  for field: it.fields  changed |= generate_jai_parse_field(*sbtmp, it, field, .VARINT, false);
                print(*sbtmp, "            }\n");
                if changed  append_and_steal_buffers(sb, *sbtmp);
                reset(*sbtmp);

                changed = false;
                print(sb, "        case .I32;\n");
                print(sb, "            ok=, decoded_value := decode_I32(*buf);  if !ok return false;\n");
                print(*sbtmp, "            decoded_value_float := (*decoded_value).(*float32).*;\n");
                print(*sbtmp, "            if field_number == {\n");
                for field : definition.fields  changed |= generate_jai_parse_field(*sbtmp, definition, field, .I32, field.repeated);
                for definition.one_ofs  for field: it.fields  changed |= generate_jai_parse_field(*sbtmp, it, field, .I32, false);
                print(*sbtmp, "            }\n");
                if changed  append_and_steal_buffers(sb, *sbtmp);
                reset(*sbtmp);

                changed = false;
                print(sb, "        case .I64;\n");
                print(sb, "            ok=, decoded_value := decode_I64(*buf);  if !ok return false;\n");
                print(*sbtmp, "            decoded_value_float := (*decoded_value).(*float64).*;\n");
                print(*sbtmp, "            if field_number == {\n");
                for field : definition.fields  changed |= generate_jai_parse_field(*sbtmp, definition, field, .I64, field.repeated);
                for definition.one_ofs  for field: it.fields  changed |= generate_jai_parse_field(*sbtmp, it, field, .I64, false);
                print(*sbtmp, "            }\n");
                if changed  append_and_steal_buffers(sb, *sbtmp);
                reset(*sbtmp);

                changed = false;
                print(sb, "        case .LEN;\n");
                print(sb, "            ok=, _, submessage := decode_LEN(*buf);  if !ok return false;\n");
                print(*sbtmp, "            if field_number == {\n");
                for field : definition.fields  changed |= generate_jai_parse_field(*sbtmp, definition, field, .LEN, field.repeated);
                for definition.one_ofs  for field: it.fields  changed |= generate_jai_parse_field(*sbtmp, it, field, .LEN, false);
                print(*sbtmp, "            }\n");
                if changed  append_and_steal_buffers(sb, *sbtmp);
                reset(*sbtmp);

                print(sb, "        }\n");
                print(sb, "    }\n");
                // Messages always use all of the bytes
                print(sb, "    return true, bytes.count;\n");
                print(sb, "}\n");
            case .ENUM;
                print(sb, "Serialize :: (output: []u8, index: s64, enum_value: %, field_number := -1, force := false) -> index: s64 {\n", dotted_name);
                print(sb, "    value := cast,no_check(u64, enum_value);\n");
                print(sb, "    if force || value != 0  index = encode_VARINT(output, index, value, field_number);\n");
                print(sb, "    return index;\n");
                print(sb, "}\n");
                print(sb, "Deserialize :: (enum_value: *%, bytes: []u8) -> ok: bool, used: s64 {\n", dotted_name);
                print(sb, "    buf := bytes;\n");
                print(sb, "    ok, value := decode_VARINT(*buf);\n");
                print(sb, "    if !ok return false, 0;\n");
                print(sb, "    enum_value.* = xx,no_check value;\n");
                print(sb, "    used := bytes.count - buf.count;\n");
                print(sb, "    return true, used;\n");
                print(sb, "}\n");
            case .ONE_OF;
        }

        generate_jai_free_function(sb, definition, dotted_name);
    }
}

generate_jai_field :: (sb: *String_Builder, field: ProtoField, indent_level: int) {
    indent := indent_str(indent_level);
    if field.map {
        print(sb, "%0%: Table(%, %)", indent, field.name, jai_type(field.map_key), jai_type(field.map_value));
    } else if field.repeated {
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


generate_jai_free_function :: (sb: *String_Builder, definition: ProtoDefinition, dotted_name: string) {
    sb2: String_Builder;

    should_free :: (type: ProtoType) -> bool {
        if type == {
            case .STRING; #through;
            case .BYTES; #through;
            case .MESSAGE; return true;
            case; return false;
        }
    }
    free_function_name :: (type: ProtoType) -> string {
        if type == {
            case .STRING; return "free";
            case .BYTES; return "array_free";
            case .MESSAGE; return "FreeContents";
            case; assert(false, "Should not free %", type); return "?";
        }
    }
    pointer :: (type: ProtoType) -> string {
        if type == {
            case .MESSAGE; return "*";
        }
        return "";
    }

    for field : definition.fields {
        if field.map {
            free_key := should_free(proto_type(field.map_key));
            free_value := should_free(proto_type(field.map_value));
            if free_key || free_value {
                print(*sb2, "    for* v, k : message.% {", field.name);
                if free_key   print(*sb2, " %(k);", free_function_name(proto_type(field.map_key)));
                if free_value print(*sb2, " %(v);", free_function_name(proto_type(field.map_key)));
                print(*sb2, " }\n", field.name);
            }
            print(*sb2, "    deinit(*message.%1); message.%1 = .{};\n", field.name);
        } else if field.repeated {
            if should_free(field.type) {
                print(*sb2, "    for%  message.%  %(it);\n", pointer(field.type), field.name, free_function_name(field.type));
            }
            print(*sb2, "    array_reset(*message.%);\n", field.name);
        } else {
            newline := false;
            if should_free(field.type) {
                print(*sb2, "    %(%message.%);", free_function_name(field.type), pointer(field.type), field.name);
                newline = true;
            }
            if field.type == .STRING  print(*sb2, " message.% = \"\";", field.name);
            if newline print(*sb2, "\n");
        }
    }
    if builder_string_length(*sb2) == 0 {
        print(sb, "FreeContents :: inline (message: *%) {}\n", dotted_name);
    } else {
        print(sb, "FreeContents :: (message: *%) {\n", dotted_name);
        append_and_steal_buffers(sb, *sb2);
        print(sb, "}\n");
    }
}


generate_jai_serialize_field :: (sb: *String_Builder, field: ProtoField, repeated: bool = false, required: bool = false) {
    if field.map {
        print(sb, "for message.% { ", field.name);
    } else if repeated {
        print(sb, "for < message.% { ", field.name);
    } else {
        print(sb, "{ it := message.%; ", field.name);
    }

    may_omit := !(repeated || required);

    if field.map {
        print(sb, "end := index; ");
        generate_jai_serialize_value(sb, proto_type(field.map_value), 2, "it");
        print(sb, " ");
        generate_jai_serialize_value(sb, proto_type(field.map_key), 1, "it_index");
        print(sb, " index = encode_LEN_from_index(output, index, end, %);", formatInt(field.field_number));
    } else {
        omit_name := ifx may_omit then field.name else "";
        generate_jai_serialize_value(sb, field.type, field.field_number, "it", omit_name);
    }
    print(sb, " }\n");
}

generate_jai_serialize_value :: (sb: *String_Builder, type: ProtoType, field_number: int, id: string, omit_field_name: string = "") {
    may_omit := omit_field_name != "";

    if #complete wire_type_for(type) == {
    case .VARINT;
        if may_omit print(sb, "if % != default.%     ", id, omit_field_name);
        if should_zigzag(type) {
            print(sb, "index = encode_VARINT_zigzag(output, index, %, %);", id, formatInt(field_number));
        } else {
            print(sb, "index = encode_VARINT(output, index, xx,no_check %, %);", id, formatInt(field_number));
        }
    case .I32;
        if may_omit print(sb, "if % != default.%     ", id, omit_field_name);
        print(sb, "index = encode_I32(output, index, %, %);", id, formatInt(field_number));
    case .I64;
        if may_omit print(sb, "if % != default.%     ", id, omit_field_name);
        print(sb, "index = encode_I64(output, index, %, %);", id, formatInt(field_number));
    case .LEN;
        if type == {
        case .STRING;
            if may_omit print(sb, "if % != default.%     ", id, omit_field_name);
            print(sb, "index = encode_string(output, index, %, %);", id, formatInt(field_number));
        case .BYTES;
            if may_omit print(sb, "if !array_view_equal(message.%1, default.%1)     ", omit_field_name);
            print(sb, "index = encode_bytes(output, index, %, %);", id, formatInt(field_number));
        case .MESSAGE;
            force := ifx may_omit then "" else ", force=true";
            print(sb, "index = Serialize(output, index, %, %0%0);", id, formatInt(field_number), force);
        case;
            log("Unknown LEN field for %", type);
        }
    case .SGROUP;
    case .EGROUP;
    }
}

generate_jai_parse_field :: (sb: *String_Builder, definition: ProtoDefinition, field: ProtoField, wire_type: WireType, repeated: bool) -> bool {
    field_type := wire_type_for(field.type);

    known_type := true;

    // We have not detected the "real" types of subfields as Message vs Enum, and Message is assumed during parsing.
    // So we have some extra logic here to deal with it
    if field.type == .MESSAGE && !field.map {
        type_definition := resolve_definition(definition, field.type_name);
        if type_definition {
            if type_definition.kind == .ENUM {
                field_type = .VARINT;
            }
        } else {
            known_type = false;
        }
    }
    changed: bool = false;

    set_kind :: (sb: *String_Builder, definition: ProtoDefinition, field: ProtoField) {
        if definition.kind == .ONE_OF {
            print(sb, " message.%_kind = .%;", definition.name, field.name);
        }
    }

    if wire_type == {
        case .VARINT;
            if field_type == .VARINT || !known_type {
                print(sb, "            case %; ", formatInt(field.field_number));
                if !known_type  print(sb, "#if ProtoType_% == .ENUM { ", id_name_for(field.type_name,, temp));
                value_string := ifx should_zigzag(field.type) "unzigzag(decoded_value)" else "decoded_value";
                if repeated print(sb, "array_add(*message.%, xx,no_check %);", field.name, value_string);
                else        print(sb, "message.% = xx,no_check %;", field.name, value_string);
                set_kind(sb, definition, field);
                if !known_type  print(sb, " }");

                print(sb, "\n");
                changed = true;
            }
        case .I32;
            if field_type == .I32 {
                value_string := ifx field.type == .FLOAT "decoded_value_float" else "decoded_value";
                if repeated print(sb, "            case %; array_add(*message.%, %);", formatInt(field.field_number), field.name, value_string);
                else        print(sb, "            case %; message.% = %;",            formatInt(field.field_number), field.name, value_string);
                set_kind(sb, definition, field);
                print(sb, "\n");
                changed = true;
            }
        case .I64;
            if field_type == .I64 {
                value_string := ifx field.type == .DOUBLE "decoded_value_float" else "decoded_value";
                if repeated print(sb, "            case %; array_add(*message.%, %);", formatInt(field.field_number), field.name, value_string);
                else        print(sb, "            case %; message.% = %;",            formatInt(field.field_number), field.name, value_string);
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
                        else         print(sb, "message.% = copy_string(submessage.(string));", field.name);
                    case .BYTES;
                        if repeated  print(sb, "array_add(*message.%, array_copy(submessage));", field.name);
                        else         print(sb, "message.% = array_copy(submessage);", field.name);
                    case .MESSAGE;
                        // Could be a repeated enum, or a Message
                        // Messages consume all of the bytes, and repeated enums may not

                        if field.map {
                            // Each item is an individual Message with key=1; value=2;
                            key_proto := proto_type(field.map_key);
                            value_proto := proto_type(field.map_value);
                            key_wire := wire_type_for(key_proto);
                            value_wire := wire_type_for(value_proto);
                            indent_str := "                ";

                            decode_one :: (sb: *String_Builder, proto: ProtoType, wire: WireType, variable: string) {
                                if wire == {
                                    case .VARINT;
                                        print(sb, "ok=, varint := decode_VARINT(*submessage); ");
                                        fn := ifx should_zigzag(proto) "unzigzag(varint)" else "varint";
                                        print(sb, "got_%1, %1 = ok, xx,no_check %2;", variable, fn);
                                    case .I32;
                                        fn := ifx proto == .FLOAT "decode_I32_float" else "decode_I32";
                                        print(sb, "got_%1, %1 = %(*submessage);", variable, fn);
                                    case .I64;
                                        fn := ifx proto == .DOUBLE "decode_I64_float" else "decode_I64";
                                        print(sb, "got_%1, %1 = %(*submessage);", variable, fn);
                                    case .LEN;
                                        print(sb, "got_%1=, ptr := decode_string(*submessage); %1 = copy_string(ptr);", variable);
                                }
                            }

                            print(sb, " key: %; value: %; got_key := false; got_value := false; ", jai_type(key_proto, ""), jai_type(value_proto, ""));
                            print(sb, "while submessage {\n");
                            print(sb, "%ok=, wire_type, field_number := decode_tag(*submessage); if !ok return false;\n", indent_str);
                            print(sb, "%if field_number == 1 && wire_type == .% { ", indent_str, key_wire);
                            decode_one(sb, key_proto, key_wire, "key");
                            print(sb, " }\n%else if field_number == 2 && wire_type == .% { ", indent_str, value_wire);
                            decode_one(sb, value_proto, value_wire, "value");
                            print(sb, " }\n%else { ok = decode_skip(*submessage, wire_type); }\n", indent_str);
                            print(sb, "%if !ok return false;", indent_str);
                            print(sb, " }\n");
                            print(sb, "%table_set(*message.%, key, value);", indent_str, field.name);
                        } else if repeated {
                            print(sb, "while true { ok=, used := Deserialize(array_add(*message.%), submessage); if !ok return false; submessage = array_view(submessage, used); if !submessage break; }", field.name);
                        } else {
                            print(sb, "if !Deserialize(*message.%, submessage)  return false;", field.name);
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


resolve_definition :: (location: ProtoDefinition, type_name: string) -> *ProtoDefinition {
    result: *ProtoDefinition = null;
    // if type_name contains a . means that we need to descend into that subtype first
    left := find_index_from_left(type_name, ".");
    if left == 0 {
        // "." at the beginning, do not perform relative resolution
        return null;
    } else if left > 0 {
        subfield := slice(type_name, 0, left);
        right := slice(type_name, left + 1);
        for sub : location.subtypes {
            if sub.name == subfield {
                result = resolve_definition(sub, right);
                break;
            }
        }
    } else {
        // Find exact subtype with this name
        for* sub : location.subtypes {
            if sub.name == type_name {
                result = sub;
                break;
            }
        }
    }

    // No exact match, look higher up in the hierarchy for a matching name
    if !result && location.parent {
        result = resolve_definition(location.parent, type_name);
    }

    return result;
}


id_name_for :: (name: string) -> string {
    s := trim_left(name, "."); // global namespace strip
    if !contains(s, ".") return s;
    return replace(s, ".", "_");
}


build_path_up :: (definition: ProtoDefinition, separator: string) -> string {
    if !definition.parent  return definition.name;

    build :: (tmp: *String_Builder, definition: ProtoDefinition, separator: string) {
        if definition.parent  build(tmp, definition.parent, separator);
        if builder_string_length(tmp)  append(tmp, separator);
        append(tmp, definition.name);
    }

    tmp: String_Builder;
    init_string_builder(*tmp,, temp);
    build(*tmp, definition, separator);
    return builder_to_string(*tmp);
}


indent_str :: (indent_level: int) -> string {
    SPACES :: "                                        ";
    length := indent_level * INDENT;
    return slice(SPACES, 0, length);
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
            ok=, path := parse_import(p);
            if ok array_add(*out.imports, path);
        case "option";
            ok=, option := parse_option(p);
        case "package";
            ok=, package := parse_package(p);
            out.package = package;
        case "message";
            ok = parse_message(p, *out.definitions, null);
            return true;
        case "enum";
            parse_enum(p, *out.definitions, null);
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

parse_import :: (p: *Parser) -> ok: bool, path: string {
    // Called after "import" is popped
    t: Token;
    t = next(p);
    if t.kind == .ID {
        if t.text == "public" {
            t = next(p);
        }
        else return false, "";
    }
    if t.kind != .STRING return false, "";
    path := t.value;
    t = next(p);
    if t.kind != .SEMICOLON return false, path;
    return true, path;
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


parse_message :: (p: *Parser, output_array: *[..]ProtoDefinition, parent: *ProtoDefinition) -> ok: bool {
    ok, message_name := parse(p, .ID);
    if !ok return true;

    ok = parse(p, .OCURLY);
    if !ok return false;

    definition: *ProtoDefinition = array_add(output_array);
    definition.kind = .MESSAGE;
    definition.name = message_name;
    definition.parent = parent;

    ok = parse_message_fields(p, definition);
    return ok;
}


parse_enum :: (p: *Parser, output_array: *[..]ProtoDefinition, parent: *ProtoDefinition) -> ok: bool {
    ok, message_name := parse(p, .ID);
    if !ok return false;

    ok = parse(p, .OCURLY);
    if !ok return false;

    definition: *ProtoDefinition = array_add(output_array);
    definition.kind = .ENUM;
    definition.name = message_name;
    definition.parent = parent;

    t: Token;
    while t.kind != .EOF {
        t = peek(p);
        if t.kind == .CCURLY {
            next(p);
            break;
        }
        if t.kind == .ID {
            if t.text == {
                case "option";
                    while t.kind != .SEMICOLON && t.kind != .EOF { t = next(p); }
                case;
                    parse_field(p, definition);
            }
        } else {
            log("Unknown item in enum: %", t);
            next(p);
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
            case "message";  next(p); parse_message(p, *definition.subtypes, definition);
            case "enum";     next(p); parse_enum(p, *definition.subtypes, definition);
            case "extensions"; #through;
            case "option";
                while t.kind != .SEMICOLON && t.kind != .EOF { t = next(p); }
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

    // Field type
    if definition.kind != .ENUM {
        ok, type_name := parse(p, .ID);
        if !ok return false;

        if type_name == "map" {
            type_start := type_name;
            if !parse(p, .OANGLE) return false;
            ok=, key_name := parse(p, .ID);
            if !ok return false;

            if !parse(p, .COMMA) return false;
            ok=, value_name := parse(p, .ID);
            if !ok return false;

            ok=, end_point := parse(p, .CANGLE);
            if !ok return false;

            type_name.data = type_start.data;
            type_name.count = end_point.data - type_start.data + end_point.count;
            field.map = true;
            field.map_key = key_name;
            field.map_value = value_name;
            field.type_name = type_name;
            field.type = .MESSAGE; // Maps are repeated .MESSAGE on the wire
        } else {
            field.type_name = type_name;
            field.type = proto_type(type_name);
        }
    }

    // Field name
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

    if is_any(str[i], ",;{}[]<>=") {
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
            case "<";
                t.kind = .OANGLE;
                return t;
            case ">";
                t.kind = .CANGLE;
                return t;
            case "=";
                t.kind = .EQ;
                return t;
            case;
                assert(false, "Unreachable");
        }
    }

    if str[i] == "-" || (str[i] >= "0" && str[i] <= "9") {
        i += 1;
        while str[i] >= "0" && str[i] <= "9" {
            i += 1;
        }
        return Token.{kind = .NUMBER, text = slice(str, 0, i)};
    }

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
    OANGLE;
    CANGLE;
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
#import "File";
