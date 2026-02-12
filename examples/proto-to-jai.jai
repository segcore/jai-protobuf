default_search_dirs :: string.["", "/usr/include"];
program_name: string;

SUPPORT_STDIN :: OS != .WINDOWS;

usage :: () {
    print("Converts protobuf message descriptions to Jai source code.\n\n");
    print("Usage: % [options] [-f] files...\n", ifx program_name else "proto-to-jai");
    print("options:\n");
    print("     -h | -help         Print this usage information\n");
    print("     -I {search_dir}    Add search directory. Can be used more than once.\n");
    print("     -o {output_file}   Set the output file path. If empty (default), write to stdout.\n");
#if SUPPORT_STDIN {
    print("     -                  Read from standard input, instead of from a file\n");
}
    print("     files...           List the protobuf text files to convert to Jai code.\n");
}

main :: () {
    files: [..]string;
    search: [..]string;
    output_path := "";

    array_add(*search, ..default_search_dirs);

    CollectKind :: enum {
        FILES;
        SEARCH_DIR;
        OUTPUT;
    };
    collect: CollectKind;
    args := get_command_line_arguments();
    if args {
        program_name = args[0];
        args = array_view(args, 1);
    }

    for arg: args {
        if arg == "-f" {
            collect = .FILES;
        } else if arg == "-I" {
            collect = .SEARCH_DIR;
        } else if arg == "-o" {
            collect = .OUTPUT;
        } else if arg == "-h" || arg == "-help" || arg == "?" || arg == "-?" || arg == "/?" {
            usage();
            exit(1);
        } else if arg == "-" {
            array_add(*files, arg);
        } else if arg[0] == "-" {
            print("Error: unknown flag %\n\n", arg);
            usage();
            exit(1);
        } else if #complete collect == {
            case .FILES;
                array_add(*files, arg);
            case .SEARCH_DIR;
                array_add(*search, arg);
                collect = .FILES;
            case .OUTPUT;
                output_path = arg;
                collect = .FILES;
        }

    }

    if !files {
        print("Error: no input files\n\n", to_standard_error=true);
        usage();
        exit(1);
    }

    ok: bool;
    set: ProtoFileSet;
    #if SUPPORT_STDIN {
        stdin_proto_file: ProtoFile;
        for files {
            if it == "-" {
                #import "POSIX";
                stdin_file := File.{stdin};
                stdin_data := read_entire_file(stdin_file);

                stdin_proto_file, ok = parse_proto_text(stdin_data, "-stdin-");
                if !ok {
                    print("Error: parsing standard input text failed\n", to_standard_error=true);
                }
                remove it;
            }
        }
        add_proto_tree_file(*set, stdin_proto_file);
        parse_proto_files_set(*set, stdin_proto_file.imports, search);
    }

    parse_proto_files_set(*set, files, search);

    jai, failed_imports := generate_jai(*set);

    if failed_imports {
        print("WARNING: failed imports %\n", failed_imports, to_standard_error=true);
        // continue on; print what we can.
    }
    if jai == "" {
        print("Error: failed to generate any code.\n", to_standard_error=true);
        exit(1);
    }

    if output_path == "" {
        write_string(jai);
    } else {
        ok = write_entire_file(output_path, jai);
        if ok print("Generated '%'\n", output_path);
        else  { print("Failed to write '%'\n", output_path); exit(1); }
    }
}

#import,dir "..";
#import "File";
#import "Basic";
