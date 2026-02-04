/*
 * Example: Generate code only, to be consumed by another project.
 * Avoids the cost of the code generation for each compile, but you
 * need to remember to regenerate it when the .proto files are modified.
 * Or have a fancier metaprogram do that for you.
 */

/*
 * Usually, we would use #import "Protobuf"; but because we are in the same repo,
 * we import it this way instead.
 */
// #import "Protobuf";
#import,dir "..";

main :: () {
    protos :: string.[
        "protos/some_things.proto",
    ];

    outpath :: "generated/protobuf_definitions.jai";
    make_directory_if_it_does_not_exist("generated");

    jai, failed_imports := generate_jai(protos);
    ok := write_entire_file(outpath, jai);

    if ok print("Generated '%'\n", outpath);
    else  print("Failed to write file '%'\n", outpath);

    if failed_imports  print("Failed to import %\n", failed_imports);
    ok = ok && !failed_imports;
    if !ok  exit(1);
}

#import "Basic";
#import "File";
