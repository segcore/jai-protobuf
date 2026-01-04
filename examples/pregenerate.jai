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

GENERATED_FILE_IMPORT_PATH :: "../..";

main :: () {
    protos := string.[
        "some_things.proto",
        "many_things.proto",
    ];

    error := false;
    make_directory_if_it_does_not_exist("generated");
    for src : protos {
        code := generate_jai(parse_proto_file(src), GENERATED_FILE_IMPORT_PATH);

        outpath := tprint("generated/%.jai", src);
        ok := write_entire_file(outpath, code);

        if ok print("Generated '%'\n", outpath);
        else  print("Failed to write file '%'\n", outpath);
        error ||= !ok;
    }

    if error exit(1);
}

#import "Basic";
#import "File";
