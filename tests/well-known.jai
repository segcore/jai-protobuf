#import,dir "..";

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
];
search_dirs :: string.["", "/usr/include"];

#insert #run generate_jai(..compile_files, search_dirs);

main :: () {
}
