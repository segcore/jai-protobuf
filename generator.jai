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
    definitions: *ProtoDefinition; // Definitions list, can use for expansion on this
    options: [..]ProtoOption;
    imports: [..]string;
}

ProtoFileSet :: struct {
    imported_protos: [..]string;
    failed_imports: [..]string;
    root: ProtoFileTree;
}

ProtoFileTree :: struct {
    package: string;
    merged_package: ProtoFile;
    children: [..]ProtoFileTree;
}

// Has a for_expansion to loop over siblings
ProtoDefinition :: struct {
    kind : ProtoDefinitionKind;
    name: string;
    fields : [..]ProtoField;
    options: [..]ProtoOption;

    // Intrusive tree definition. Children are circular linked lists
    // Avoiding [..]ProtoDefinition for pointer stability of parents
    parent: *ProtoDefinition; // Definition which contains this. Null at the root.
    first_child: *ProtoDefinition; // First child of this node in the tree
    next_sibling: *ProtoDefinition; // Next sibling child in the tree
    prev_sibling: *ProtoDefinition; // Previous sibling child in the tree
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

parse_proto_text :: (data: string, source_path: string = "") -> ProtoFile, ok: bool {
    out: ProtoFile;
    out.source_path = source_path;
    p: Parser;
    p.text = data;

    ok := false;
    while parse_primary(*p, *out) {
        ok = true;
    }

    logging_source_path := ifx source_path then source_path else "-";
    if !data {
        log("Parsing an empty protobuf text from %", logging_source_path, flags=.WARNING);
        ok = false;
    } else if out.definitions == null {
        log("No definitions found when parsing %", logging_source_path, flags=.WARNING);
    }

    return out, ok;
}

// Parse the protobuf description file
parse_proto_file :: (source_path: string) -> ProtoFile, ok: bool {
    proto_file, ok := parse_proto_text(read_entire_file(source_path), source_path);
    return proto_file, ok;
}

parse_proto_files :: (input_protos: ..string, search_dirs: []string = .[""]) -> ProtoFileSet, ok: bool {
    set: ProtoFileSet;
    ok := parse_proto_files_set(*set, ..input_protos, search_dirs);
    return set, ok;
}

// Generate Jai code for all files given, searching in given import directories.
generate_jai :: (input_protos: ..string, search_dirs: []string = .[""], protobuf_import := "") -> jai: string, failed_imports: []string {
    jai, failed_imports := generate_jai(*parse_proto_files(..input_protos, search_dirs), protobuf_import=protobuf_import);
    return jai, failed_imports;
}

// Generate Jai code for the file set
generate_jai :: (set: *ProtoFileSet, protobuf_import := "") -> jai: string, failed_imports: []string {
    code_builder: String_Builder;

    generate_recursive :: (sb: *String_Builder, node: ProtoFileTree, protobuf_import: string) {
        mangle(*node.merged_package);
        code := generate_jai(node.merged_package, protobuf_import=protobuf_import);
        append(sb, code);
        // Loop backwards so the dependencies are a little more likely to come first...
        // For when it is inserted at a non-top-level location
        for< node.children generate_recursive(sb, it, protobuf_import);
    }

    generate_recursive(*code_builder, set.root, protobuf_import);

    jai := builder_to_string(*code_builder);
    return jai, set.failed_imports;
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

    packages := ifx contains(p.package, ".") then split(p.package, ".",, temp) else .[p.package];
    for packages if it print(*sb, "% :: struct { // package namespace\n", it);
    for p.definitions  generate_definition(*sb, it, p.package); 
    for<packages if it print(*sb, "} // package namespace: %\n", it);

    print(*sb, "\n");
    for p.definitions  generate_jai_proto_type(*sb, p.package, it);

    print(*sb, "\n");
    generate_jai_for_definitions(*sb, p.definitions, p);

    return builder_to_string(*sb);
}


// -------------
// You probably won't need functions below here.
// -------------

reset :: (set: *ProtoFileSet) {
    array_reset(*set.imported_protos);
    array_reset(*set.failed_imports);
}

parse_proto_files_set :: (set: *ProtoFileSet, input_protos: ..string, search_dirs: []string = string.[""]) -> ok: bool {
    found_something := false;

    for input_path : input_protos {
        // If the lookup has already failed, just skip it
        if array_find(set.failed_imports, input_path) {
            continue input_path;
        }
        for search_dir : search_dirs {
            full_import_path: string;
            if search_dir {
                full_import_path = sprint("%/%", search_dir, input_path,, temp);
            } else {
                full_import_path = input_path;
            }

            // Don't reimport the same files over and over
            if array_find(set.imported_protos, full_import_path) {
                continue input_path;
            }

            log("Search for % at %\n", input_path, full_import_path, flags = .VERBOSE_ONLY);

            // Accept the import if the file exists, even if the file is empty
            no_logger :: (message: string, data: *void, info: Log_Info) {}
            contents, ok := read_entire_file(full_import_path,, logger=no_logger);
            if ok {
                log("Parsing protobuf file '%'", full_import_path);
                proto_file := parse_proto_text(contents, input_path);

                array_add(*set.imported_protos, full_import_path);
                found_something = true;

                add_proto_tree_file(set, proto_file);
                parse_proto_files_set(set, ..proto_file.imports, search_dirs);
                continue input_path;
            }
        }

        // If we reach here, we've failed to import it
        array_add(*set.failed_imports, input_path);
        log("Failed to find an import path for '%'", input_path, flags=.WARNING);
    }

    return found_something;
}

add_proto_tree_file :: (set: *ProtoFileSet, proto_file: ProtoFile) {
    node := *set.root;
    package := proto_file.package;
    while package {
        found, left, right := split_from_left(package, ".");
        child: *ProtoFileTree;
        for* node.children {
            if it.package == left {
                child = it;
                break;
            }
        }
        if !child {
            child = array_add(*node.children);
            child.package = left;
        }
        node = child;
        package = right;
    }

    merge_proto_files(*node.merged_package, proto_file);
}

merge_proto_files :: (destination: *ProtoFile, source: ProtoFile) {
    if destination.source_path && source.source_path
        destination.source_path = join(destination.source_path, source.source_path, separator=", ",, temp);
    else if source.source_path  destination.source_path = source.source_path;
    destination.package = source.package;
    array_add(*destination.options, ..source.options);
    array_add(*destination.imports, ..source.imports);

    if destination.definitions == null && source.definitions == null {
        // nothing
    } else if destination.definitions == null && source.definitions != null {
        destination.definitions = source.definitions;
    } else if destination.definitions != null && source.definitions == null {
        // nothing
    } else if destination.definitions != null && source.definitions != null {
        // merge
        dest_last := destination.definitions.prev_sibling;
        source_last := source.definitions.prev_sibling;

        dest_last.next_sibling = source.definitions;
        source.definitions.prev_sibling = dest_last;
        source_last.next_sibling = destination.definitions;
        destination.definitions.prev_sibling = source_last;
    }
}

generate_jai_proto_type :: (sb: *String_Builder, package: string, definiton: ProtoDefinition) {
    if definiton.kind == {
        case .MESSAGE; #through;
        case .ENUM;
            id_name := build_path_up(package, definiton, "_");
            print(sb, "ProtoType_% :: ProtoType.%;\n", id_name, definiton.kind);
    }
    for definiton.first_child  generate_jai_proto_type(sb, package, it);
}

// Mangles any name to avoid Jai keywords and builtins
// Input name may include ".", then each token will be mangled independently and recombined
mangle :: (name: string) -> string {
    mangled_name := name;
    reserved :: string.[
        "Any",
        "int",

        "break",
        "case",
        "cast",
        "continue",
        "defer",
        "else",
        "enum",
        "enum_flags",
        "for",
        "if",
        "ifx",
        "inline",
        "interface",
        "no_inline",
        "push_context",
        "remove",
        "return",
        "struct",
        "then",
        "union",
        "using",
        "while",
        "xx",
    ];

    // Try to avoid allocations
    needs_mangle := false;

    section := name;
    while section {
        found, left, right := split_from_left(section, ".");
        if array_find(reserved, left) {
            needs_mangle = true;
            break;
        }
        section = right;
    }

    if needs_mangle {
        sb: String_Builder;
        section := name;
        while section {
            found, left, right := split_from_left(section, ".");
            append(*sb, left);
            if array_find(reserved, left) {
                append(*sb, "_");
            }
            if right append(*sb, ".");
            section = right;
        }
        mangled_name = builder_to_string(*sb);
    }
    return mangled_name;
}

mangle :: (proto_file: *ProtoFile) {
    for* definition: proto_file.definitions {
        definition.name = mangle(definition.name);
        for* field : definition.fields {
            field.name = mangle(field.name);
            field.map_key = mangle(field.map_key);
            field.map_value = mangle(field.map_value);
            field.type_name = mangle(field.type_name);
        }
    }
}

generate_definition :: (sb: *String_Builder, definition: ProtoDefinition, package: string, indent_level := 0) {
    indent := indent_str(indent_level);
    name := mangle(definition.name);
    if #complete definition.kind == {
        case .MESSAGE;
            print(sb, "%0% :: struct {", indent, name);
            if package  print(sb, " // %.%", package, name);
            print(sb, "\n", indent, name);
            for definition.fields       generate_jai_field(sb, it, indent_level + 1);
            for definition.first_child  generate_definition(sb, it, package, indent_level + 1);
            print(sb, "%}\n", indent);
        case .ENUM;
            print(sb, "%0% :: enum {\n", indent, name);
            for field : definition.fields {
                print(sb, "%    % :: %;\n", indent, field.name, formatInt(field.field_number, base=10));
            }
            print(sb, "%}\n", indent);
        case .ONE_OF;
            indent := indent_str(indent_level);
            // Generate Enum for Kind
            print(sb, "%0%_Kind :: enum {\n", indent, name);
            print(sb, "%    _UNSET;\n", indent, name);
            for field : definition.fields {
                print(sb, "%    %;\n", indent, field.name);
            }
            print(sb, "%}\n", indent);
            print(sb, "%0%2_kind: %2_Kind;\n", indent, name);

            // Generate fields
            print(sb, "%using % : union {\n", indent, name);
            for definition.fields  generate_jai_field(sb, it, indent_level + 1);
            print(sb, "%}\n", indent, name);
    }
}


generate_jai_for_definitions :: (sb: *String_Builder, set: *ProtoDefinition, proto_file: ProtoFile) {
    for definition : set {
        generate_jai_for_definitions(sb, definition.first_child, proto_file);

        dotted_name := build_path_up(proto_file.package, definition, ".");

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
                for < :one_ofs oneof : definition.first_child {
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
                for field : definition.fields  changed |= generate_jai_parse_field(*sbtmp, proto_file, definition, field, .VARINT, field.repeated);
                for :one_ofs definition.first_child  for field: it.fields  changed |= generate_jai_parse_field(*sbtmp, proto_file, it, field, .VARINT, false);
                print(*sbtmp, "            }\n");
                if changed  append_and_steal_buffers(sb, *sbtmp);
                reset(*sbtmp);

                changed = false;
                print(sb, "        case .I32;\n");
                print(sb, "            ok=, decoded_value := decode_I32(*buf);  if !ok return false;\n");
                print(*sbtmp, "            decoded_value_float := (*decoded_value).(*float32).*;\n");
                print(*sbtmp, "            if field_number == {\n");
                for field : definition.fields  changed |= generate_jai_parse_field(*sbtmp, proto_file, definition, field, .I32, field.repeated);
                for :one_ofs definition.first_child  for field: it.fields  changed |= generate_jai_parse_field(*sbtmp, proto_file, it, field, .I32, false);
                print(*sbtmp, "            }\n");
                if changed  append_and_steal_buffers(sb, *sbtmp);
                reset(*sbtmp);

                changed = false;
                print(sb, "        case .I64;\n");
                print(sb, "            ok=, decoded_value := decode_I64(*buf);  if !ok return false;\n");
                print(*sbtmp, "            decoded_value_float := (*decoded_value).(*float64).*;\n");
                print(*sbtmp, "            if field_number == {\n");
                for field : definition.fields  changed |= generate_jai_parse_field(*sbtmp, proto_file, definition, field, .I64, field.repeated);
                for :one_ofs definition.first_child  for field: it.fields  changed |= generate_jai_parse_field(*sbtmp, proto_file, it, field, .I64, false);
                print(*sbtmp, "            }\n");
                if changed  append_and_steal_buffers(sb, *sbtmp);
                reset(*sbtmp);

                changed = false;
                print(sb, "        case .LEN;\n");
                print(sb, "            ok=, _, submessage := decode_LEN(*buf);  if !ok return false;\n");
                print(*sbtmp, "            if field_number == {\n");
                for field : definition.fields  changed |= generate_jai_parse_field(*sbtmp, proto_file, definition, field, .LEN, field.repeated);
                for :one_ofs definition.first_child  for field: it.fields  changed |= generate_jai_parse_field(*sbtmp, proto_file, it, field, .LEN, false);
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
                continue;
        }

        generate_jai_free_function(sb, definition, dotted_name, proto_file);
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
    // Enums are marked as message types, and need the . prefix to be automatically inferred as an enum constant
    if field.default print(sb, " = %2%1", field.default, ifx field.type == .MESSAGE ".");
    print(sb, ";");
    if field.deprecated print(sb, " @deprecated");
    // if field.optional print(sb, " @optional"); // This is really noisy for files which mark everything optional
    if field.required print(sb, " @required");
    print(sb, "\n");
}


generate_jai_free_function :: (sb: *String_Builder, definition: ProtoDefinition, dotted_name: string, proto_file: ProtoFile) {
    sb2: String_Builder;

    should_free :: (proto_file: ProtoFile, location: ProtoDefinition, type: ProtoType, type_name: string) -> bool {
        if type == {
            case .MESSAGE;
                resolved := resolve_definition(proto_file, location, type_name);
                return !resolved || resolved.kind == .MESSAGE;
            // Fields are no longer allocated. But this may be required later if we add a DeepCopy
            case .STRING; #through;
            case .BYTES; return false;
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
            free_key := should_free(proto_file, definition, proto_type(field.map_key), field.map_key);
            free_value := should_free(proto_file, definition, proto_type(field.map_value), field.map_value);
            if free_key || free_value {
                print(*sb2, "    for* v, k : message.% {", field.name);
                if free_key   print(*sb2, " %(k);", free_function_name(proto_type(field.map_key)));
                if free_value print(*sb2, " %(v);", free_function_name(proto_type(field.map_value)));
                print(*sb2, " }\n", field.name);
            }
            print(*sb2, "    deinit(*message.%1); message.%1 = .{};\n", field.name);
        } else if field.repeated {
            if should_free(proto_file, definition, field.type, field.type_name) {
                print(*sb2, "    for%  message.%  %(it);\n", pointer(field.type), field.name, free_function_name(field.type));
            }
            print(*sb2, "    array_reset(*message.%);\n", field.name);
        } else {
            if should_free(proto_file, definition, field.type, field.type_name) {
                print(*sb2, "    %(%message.%);", free_function_name(field.type), pointer(field.type), field.name);
                if field.type == .STRING  print(*sb2, " message.% = \"\";", field.name);
                print(*sb2, "\n");
            }
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

generate_jai_parse_field :: (sb: *String_Builder, proto_file: ProtoFile, definition: ProtoDefinition, field: ProtoField, wire_type: WireType, repeated: bool) -> bool {
    field_type := wire_type_for(field.type);

    known_type := true;
    resolved_type_id := id_name_for(field.type_name,, temp);

    // We have not detected the "real" types of subfields as Message vs Enum, and Message is assumed during parsing.
    // So we have some extra logic here to deal with it
    if field.type == .MESSAGE && !field.map {
        type_definition := resolve_definition(proto_file, definition, field.type_name);
        if type_definition {
            if type_definition.kind == .ENUM {
                field_type = .VARINT;
            }
            resolved_type_id = build_path_up(proto_file.package, type_definition, "_");
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
                if !known_type  print(sb, "#if ProtoType_% == .ENUM { ", resolved_type_id);
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
                        if repeated  print(sb, "array_add(*message.%, submessage.(string));", field.name);
                        else         print(sb, "message.% = submessage.(string);", field.name);
                    case .BYTES;
                        if repeated  print(sb, "array_add(*message.%, submessage);", field.name);
                        else         print(sb, "message.% = submessage;", field.name);
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
                                        print(sb, "%1 = xx,no_check %2;", variable, fn);
                                    case .I32;
                                        fn := ifx proto == .FLOAT "decode_I32_float" else "decode_I32";
                                        print(sb, "ok, %1 = %(*submessage);", variable, fn);
                                    case .I64;
                                        fn := ifx proto == .DOUBLE "decode_I64_float" else "decode_I64";
                                        print(sb, "ok, %1 = %(*submessage);", variable, fn);
                                    case .LEN;
                                        if proto == .MESSAGE {
                                            // Must be a message, because enum has wire type VARINT
                                            // We've only decoded the tag so far, so decode the LEN value, then decode the message
                                            print(sb, "ok=, used:, subsub := decode_LEN(*submessage); ok = Deserialize(*%1, subsub);", variable);
                                        } else if proto == .STRING {
                                            print(sb, "ok, %1 = decode_string(*submessage);", variable);
                                        } else if proto == .BYTES {
                                            print(sb, "ok, %1 = decode_bytes(*submessage);", variable);
                                        } else {
                                            assert(false, "Unknown type %. Wire type %, variable %", proto, wire, variable);
                                        }
                                }
                            }

                            resolved_type_id := jai_type(value_proto, field.map_value);
                            if value_proto == .MESSAGE {
                                value_type := resolve_definition(proto_file, definition, field.map_value);
                                if value_type {
                                    resolved_type_id = build_path_up(proto_file.package, value_type, ".");
                                }
                            }

                            print(sb, " key: %; value: %; ", jai_type(key_proto, field.map_key), resolved_type_id);
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


resolve_definition :: (proto_file: ProtoFile, location: ProtoDefinition, type_name: string) -> *ProtoDefinition {
    result: *ProtoDefinition = null;
    // if type_name contains a . means that we need to descend into that subtype first
    left := find_index_from_left(type_name, ".");
    if left == 0 {
        // "." at the beginning, do not perform relative resolution
        return null;
    } else if left > 0 {
        subfield := slice(type_name, 0, left);
        right := slice(type_name, left + 1);
        for sub : location.first_child {
            if sub.name == subfield {
                result = resolve_definition(proto_file, sub, right);
                break;
            }
        }
    } else {
        // Find exact subtype with this name
        for* sub : location.first_child {
            if sub.name == type_name {
                result = sub;
                break;
            }
        }
    }

    // No exact match, look higher up in the hierarchy for a matching name
    if !result && location.parent {
        result = resolve_definition(proto_file, location.parent, type_name);
    }

    // No match in a root element, lookup in the global namespace
    if !result && !location.parent {
        for* definition : proto_file.definitions {
            root_name: string;
            type_name2 := type_name;
            if left == 0 {
                type_name2 = slice(type_name2, 1);
                left = find_index_from_left(type_name2, ".");
            }

            if left >= 0 {
                subfield := slice(type_name2, 0, left);
                right := slice(type_name2, left + 1);
                if definition.name == subfield {
                    return resolve_definition(proto_file, definition, right);
                }
            } else {
                if definition.name == type_name2 {
                    result = definition;
                    break;
                }
            }
        }
    }

    return result;
}


id_name_for :: (name: string) -> string {
    s := trim_left(name, "."); // global namespace strip
    if !contains(s, ".") return s;
    return replace(s, ".", "_");
}


build_path_up :: (package: string, definition: ProtoDefinition, separator: string) -> string {
    if !package && !definition.parent  return definition.name;

    build :: (tmp: *String_Builder, definition: ProtoDefinition, separator: string) {
        if definition.parent  build(tmp, definition.parent, separator);
        if builder_string_length(tmp)  append(tmp, separator);
        name := mangle(definition.name);
        append(tmp, name);
    }

    tmp: String_Builder;
    init_string_builder(*tmp,, temp);
    for split(package, ".",, temp) {
        if it {
            if builder_string_length(*tmp)  append(*tmp, separator);
            append(*tmp, it);
        }
    }
    build(*tmp, definition, separator);
    return builder_to_string(*tmp);
}


indent_str :: (indent_level: int) -> string {
    SPACES :: "                                        ";
    length := indent_level * INDENT;
    return slice(SPACES, 0, length);
}

// For expansion, loops all siblings of this element
for_expansion :: (first_sibling: *ProtoDefinition, body: Code, flags: For_Flags) #expand {
    if first_sibling == null return;

    child_index := 0;
    #if (flags & .REVERSE) {
        first := first_sibling.prev_sibling;
    } else {
        first := first_sibling;
    }
    iterator := first;
    while true {
        #if flags & .POINTER {
            `it := iterator;
        } else {
            `it := iterator.*;
        }
        `it_index := child_index;

        defer {
            child_index += 1;
            #if (flags & .REVERSE) {
                iterator = iterator.prev_sibling;
            } else {
                iterator = iterator.next_sibling;
            }

            if iterator == first {
                break;
            }
        }

        #insert (remove=#assert(false)) body;
    }
}

// For expansion picking only one_ofs. Usage: "for :one_ofs xxx"
one_ofs :: (first_sibling: *ProtoDefinition, body: Code, flags: For_Flags) #expand {
    for *=cast(bool, flags & .POINTER), <=cast(bool, flags & .REVERSE)  raw_it, raw_index : first_sibling {
        if raw_it.kind != .ONE_OF then continue;

        `it := raw_it;
        `it_index := raw_index;

        #insert body;
    }
}

#scope_file

parse_primary :: (p: *Parser, out: *ProtoFile) -> keep_going: bool {
    t := peek(p);
    id: string;
    ok := true;
    while t.kind != .ID {
        if t.kind == {
            case .EOF; return false;
            case .SEMICOLON; // allow trailing ; without complaining
                t = next(p);
            case;
                // print the warning
                parse(p, .ID);
                t = next(p);
        }
    }
    id = t.text;
    next(p);

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
            append_sibling(*out.definitions, parse_message(p, null));
            return true;
        case "enum";
            append_sibling(*out.definitions, parse_enum(p, null));
            return true;
        case "service";
            skip_service(p);
        case "extend";
            skip_extend(p);
        case;
            log("Unknown ID %", id);
    }

    return true;
}

skip_service :: (p: *Parser) {
    ok := parse(p, .ID);

    ok = parse(p, .OCURLY);
    t := peek(p);
    while true {
        if t.kind == {
            case .EOF; return;
            case .CCURLY; break;
            case; t = next(p);
        }
    }
}

skip_extend :: (p: *Parser) {
    ok := parse(p, .ID);

    ok = parse(p, .OCURLY);
    t := peek(p);
    while true {
        if t.kind == {
            case .EOF; return;
            case .CCURLY; break;
            case; t = next(p);
        }
    }
}

append_sibling :: (first_child: **ProtoDefinition, new_child: *ProtoDefinition) {
    if new_child == null return;
    if first_child.* == null {
        first_child.* = new_child;
        new_child.next_sibling = new_child;
        new_child.prev_sibling = new_child;
    } else {
        old_last := first_child.*.prev_sibling;
        old_last.next_sibling = new_child;
        first_child.*.prev_sibling = new_child;
        new_child.prev_sibling = old_last;
        new_child.next_sibling = first_child.*;
    }
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

    // Extension attributes of the form (abc.def).foo = "value"
    // We don't support extensions, so they're ignored and skipped over
    if t.kind == .OPAREN {
        while t.kind != .CPAREN {
            t = next(p);
            if t.kind == .EOF return false, option;
        }
        // Optional ID
        t = next(p);
        if t.kind == .ID t = next(p);
        if t.kind == .EQ t = next(p);
        else {
            skip_to(p, .CSQUARE);
            return false, option;
        }
        skip_to(p, .CSQUARE);
        return false, option;
    }

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
        if t.text == "public" || t.text == "weak" {
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


parse_message :: (p: *Parser, parent: *ProtoDefinition) -> *ProtoDefinition {
    ok, message_name := parse(p, .ID);
    if !ok return null;

    ok = parse(p, .OCURLY);
    if !ok return null;

    definition: *ProtoDefinition = New(ProtoDefinition);
    definition.kind = .MESSAGE;
    definition.name = message_name;
    definition.parent = parent;

    ok = parse_message_fields(p, definition);
    return definition;
}


parse_enum :: (p: *Parser, parent: *ProtoDefinition) -> *ProtoDefinition {
    ok, message_name := parse(p, .ID);
    if !ok return null;

    ok = parse(p, .OCURLY);
    if !ok return null;

    definition: *ProtoDefinition = New(ProtoDefinition);
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

    return definition;
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
            case "oneof";    next(p); append_sibling(*definition.first_child, parse_oneof(p, definition));
            case "message";  next(p); append_sibling(*definition.first_child, parse_message(p, definition));
            case "enum";     next(p); append_sibling(*definition.first_child, parse_enum(p, definition));
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

parse_oneof :: (p: *Parser, parent: *ProtoDefinition) -> *ProtoDefinition {
    t: Token;
    ok, text := parse(p, .ID);
    if !ok return null;
    name := text;

    ok, text = parse(p, .OCURLY);
    if !ok return null;

    item: *ProtoDefinition = New(ProtoDefinition);
    item.kind = .ONE_OF;
    item.name = name;
    item.parent = parent;

    ok = parse_message_fields(p, item);
    return item;
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

skip_to :: (p: *Parser, kinds: ..TokenKind) -> ok: bool {
    while true {
        t := next(p);
        if array_find(kinds, t.kind) return true;
        if t.kind == .EOF break;
    }
    return false;
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

    if is_any(str[i], ",;(){}[]<>=") {
        t.text = slice(str, 0, 1);
        if str[i] == {
            case ",";
                t.kind = .COMMA;
                return t;
            case ";";
                t.kind = .SEMICOLON;
                return t;
            case "(";
                t.kind = .OPAREN;
                return t;
            case ")";
                t.kind = .CPAREN;
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

    if str[i] == "-" || str[i] == "+" || is_digit(str[i]) {
        i += 1;
        // while str[i] >= "0" && str[i] <= "9" {
        while is_digit(str[i]) || is_alpha(str[i]) || str[i] == "." || str[i] == "-" || str[i] == "+" {
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
    OPAREN;
    CPAREN;
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
