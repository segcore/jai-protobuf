#import,dir "..";
#import "Basic";

compile_files :: string.[
    "google/protobuf/any.proto",
    "google/protobuf/api.proto",
    "google/protobuf/descriptor.proto",
    "google/protobuf/duration.proto",
    "google/protobuf/empty.proto",
    "google/protobuf/field_mask.proto",
    "google/protobuf/source_context.proto",
    // "google/protobuf/struct.proto", // no recursive definitions
    "google/protobuf/timestamp.proto",
    "google/protobuf/type.proto",
    "google/protobuf/wrappers.proto",
    "google/protobuf/c_sharp_features.proto",
    "google/protobuf/cpp_features.proto",
    "google/protobuf/go_features.proto",
    "google/protobuf/java_features.proto",
];

search_dirs :: string.["", "/usr/include"];

// Comment out if you want to debug failures at runtime instead of compile time
#insert #run generate_jai(..compile_files, search_dirs);

main :: () {
    print("----------------------\n");
    print("Generated Jai code at runtime\n");
    print("Searching in directories: %\n", search_dirs);
    for compile_files print("    %\n", it);
    print("----------------------\n");

    jai, failed_imports := generate_jai(..compile_files, search_dirs);
    print("%\n", jai);

    if failed_imports {
        log(">>> Warning: Failed imports: %", failed_imports);
        exit(1);
    }
}
