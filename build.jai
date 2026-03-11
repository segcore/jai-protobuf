#!/usr/bin/env jai
// Compiles all tests, examples, and tools, and runs the tests and examples
// to sanity check that things work.
// Usage: jai build.jai

#import "Compiler";

verbose :: false; // debugging this program

#run {
    set_build_options_dc(.{do_output = false});

    t0 := seconds_since_init();

    compile("tests", "test.jai", run=true, quiet=false, dead_code_elimination=.NONE);
    compile("tests", "well-known.jai");
    compile("examples", "01-compiletime.jai", run=true);
    compile("examples", "02a-pregenerate.jai", run=true);
    compile("examples", "02b-use_generated.jai", run=true);
    compile("examples", "03-imports.jai", run=true);
    compile("examples", "04-pool.jai", run=true);
    compile("tools", "proto-to-jai.jai", args=.["protobuf-explorer-project.proto"]);
    compile("tools", "protobuf-explorer.jai");

    // If we get to the end, then everything worked
    print("\nSuccess! Completed in % seconds!\n", seconds_since_init() - t0);
}

compile :: (working_directory: string, file: string, run := false, args:[]string = .[], quiet := true, dead_code_elimination := Build_Options.dead_code_elimination.MODULES_ONLY) {
    auto_release_temp();

    print("### Compiling... %/%\n", working_directory, file);

    w := compiler_create_workspace(file);
    if !w  compiler_report("Workspace creation failed."); // exits with failure

    options := get_build_options(w);

    // Copy over the parameters used to build this program to the sub-programs
    options.Commonly_Propagated = get_build_options().Commonly_Propagated;
    options.text_output_flags = 0; // -quiet
    options.dead_code_elimination = dead_code_elimination;

    old_wd := get_working_directory();
    ok := set_working_directory(working_directory);
    assert(ok);
    new_wd := get_working_directory();
    #if OS == .WINDOWS {
        absolute_file := get_absolute_path(file);
    } else {
        absolute_file := sprint("%/%", new_wd, file);
    }
    {
        basename, path := get_basename_and_path(absolute_file);
        if verbose print("Split file path: % -> % and %\n", absolute_file, basename, path);

        if basename || path {
            if path {
                options.output_path = path;
                if verbose print("options.output_path = \"%\";\n", path);
            }

            if basename {
                options.output_executable_name = basename;
                if verbose print("options.output_executable_name = \"%\";\n", basename);
            }
        }
    }
    set_build_options(options, w);

    compiler_begin_intercept(w);
    add_build_file(absolute_file, w);
    if !message_loop(w) {
        log_error("Failed to compile program %", absolute_file);
        exit(1);
    }
    compiler_end_intercept(w);

    if run || args {
        output_executable := tprint("%0%0", options.output_path, options.output_executable_name);
        command_line: [..]string;
        defer array_reset(*command_line);
        array_add(*command_line, output_executable);
        array_add(*command_line, ..args);
        print("###   Run %\n", command_line);
        process_result, output_string, error_string := run_command(..command_line, capture_and_return_output=quiet);
        defer free(output_string);
        defer free(error_string);
        if process_result.exit_code != 0 {
            if output_string print("%\n", output_string);
            if error_string  print("%\n", error_string);
            if process_result.type == {
                case .EXITED;
                    compiler_report(sprint("RUN FAILED (%): exit code %\n", output_executable, process_result.exit_code));
                case .SIGNALED;
                    compiler_report(sprint("RUN FAILED (%): signal %\n", output_executable, process_result.signal));
                case;
                    compiler_report(sprint("RUN FAILED (%): %\n", output_executable, process_result));
            }
        }
    }

    ok = set_working_directory(old_wd);
    assert(ok);
}

message_loop :: (w: Workspace) -> ok: bool {
    ok := false;
    while true {
        message := compiler_wait_for_message();
        // for plugins if it.message it.message(it, message);
        if message.kind == .COMPLETE {
            message_complete := cast(*Message_Complete) message;
            ok = message_complete.error_code == .NONE;
            break;
        }
    }
    return ok;
}

#import "Basic";
#import "Process";
