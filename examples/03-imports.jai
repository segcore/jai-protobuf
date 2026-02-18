/*
 * Example: Using protobuf messages which use import definitions
 *
 * Usage:
 *   jai 03-imports.jai
 *   ./03-imports
 */

// #import "Protobuf";
#import,dir "..";

search_dirs :: string.["", "/usr/include"];

// Insert the generated code.
// See .build/.added_strings_w2.jai
#insert #run generate_jai_wrapper("protos/importer.proto", search_dirs=search_dirs);

main :: () {
    thing: Thing;
    thing.timestamp.seconds = 42;
    thing.timestamp.nanos = 1234;

    print("Bytes: %\n", Serialize(thing));
}

#import "Basic";
#import "String";
#import "File";


#scope_file

// For convenience of the example, I include a copy of the protobuf contents
// so you don't need protobuf installed.
// Usually you would just call generate_jai() directly.
generate_jai_wrapper :: (compile_files: ..string, search_dirs: []string = .[]) -> jai: string {
    code, failed_imports := generate_jai(..compile_files, search_dirs);

    if failed_imports {
        log("Failed to import system files, but this example will embed the data for you anyway\n");
        missing_proto_contents :: #string END
            syntax = "proto3";
            package google.protobuf;
            message Timestamp {
              int64 seconds = 1;
              int32 nanos = 2;
            }
            message Any {
              string type_url = 1;
              bytes value = 2;
            }
        END;
        code = join(code, generate_jai(parse_proto_text(missing_proto_contents)));
    }

    return code;
}
