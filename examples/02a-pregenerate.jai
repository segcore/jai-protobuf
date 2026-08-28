/*
 * Example: Generate code only, to be consumed by another build target.
 * Avoids the cost of the code generation for each compile, but you
 * need to remember to regenerate it when the .proto files are modified.
 * Or have a fancier metaprogram do that for you.
 *
 * Usage: jai 02a-pregenerate.jai
 * Runs at compile-time, does not need (nor generate) an executable.
 */

/*
 * Usually, we would use #import "Protobuf"; but because we are in the same repo,
 * we import it this way instead.
 */
// #import "Protobuf";
#import,dir "..";

// We can just run the generator at compile time, since we have access to that in Jai.
// This follows a similar pattern to the bindings generator.

// It is optional. Just comment out this run block and you get a runtime executable version.
// It might be easier to debug in that form.
#run {
    #import "Compiler";
    set_build_options_dc(.{do_output = false});
    main();
}

main :: () {
    protos :: string.[
        "protos/some_things.proto",
    ];

    outpath :: "generated/protobuf_definitions.jai";
    make_directory_if_it_does_not_exist("generated");

    jai, failed_imports := generate_jai(..protos);
    ok := write_entire_file(outpath, jai);

    if ok print("Generated '%'\n", outpath);
    else  print("Failed to write file '%'\n", outpath);

    if failed_imports  print("Failed to import %\n", failed_imports);
    ok = ok && !failed_imports;
    if !ok  exit(1);
}

#import "Basic";
#import "File";
