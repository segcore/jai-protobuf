#import,dir "..";

my_window: Window_Type;
window_width  : s32 = 1920;
window_height : s32 = 1080;

KB :: 1024;
MB :: 1024 * KB;
GB :: 1024 * MB;
MAX_FILE_SIZE :: 100*MB;

PROJECT_FILE :: "explorer.pex";
TIP_FAIL :: "Failed to decode";

current_time: float64;
last\  _time: float64;


current_theme: s32 = xx Default_Themes.Default;
my_theme: Overall_Theme;  // This gets filled out by calling the Theme_Proc for current_theme.
THEME_NAMES : [THEME_COUNT] string : .[
    "Default",
    "Grayscale",
    "Bentonite",
    "Nimbus",
    "Blood Vampire",
    "Freddie Freeloader",
    "HIGH CONTRAST"
];

FileType :: enum {
    AUTO;
    PROTO;
    BYTES;
}

FileBytes :: struct {
    file_path: string;
    bytes: []u8;
}

FileProto :: struct {
    file_path: string;  // File path this came from
    primary: ProtoFile; // The parsed file as loaded directly (no imports)
    set: ProtoFileSet;  // The processed set of proto files (after imports)
}

file_bytes: [..]FileBytes;
file_protos: [..]FileProto;
search_directories: [..]string;
saved_tooltips: [..]Rect;
selected_file_bytes: s32;
colour_index := 0;

main :: () {
    array_add(*search_directories, "", "/usr/include");

    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();

        // Windows is very bad at thread-switching by default unless you do this. Sad.
        Windows.timeBeginPeriod(1);
    }

    #if OS != .ANDROID {
        path := path_strip_filename(get_path_of_running_executable());
        set_working_directory(path);
    }

    WANTED_MSAA :: 8;
    my_window = create_window(window_width, window_height, "A Window", wanted_msaa = WANTED_MSAA);
    msaa := Simp.prepare_window(my_window, wanted_msaa = WANTED_MSAA);
    log("Wanted MSAA: %\nChosen MSAA: %", WANTED_MSAA, msaa);

    #if OS == .WINDOWS {
        Windows.DragAcceptFiles(my_window, cast(Windows.BOOL) true);
    } else #if OS == .LINUX {
        X11 :: #import "X11";
        typelist := string.["url/url", "text/uri-list", "text/plain", "application/octet-stream"];
        X11.enable_drag_and_drop(my_window, typelist);
    } else #if OS == .MACOS {
        #import "Objective_C";
        #import "Objective_C/AppKit";
        types := NSArray(NSPasteboardType).arrayWithObject(NSPasteboardTypeFileURL);
        NSView.registerForDraggedTypes(my_window, types);
    }


    // Actual render size in pixels can be different from the window dimensions we specified above (for example on high-resolution displays on macOS/iOS).
    window_width, window_height = Simp.get_render_dimensions(my_window);

    Simp.set_render_target(my_window, .LEFT_HANDED);
    my_init_fonts();
    ui_init();

    load_project("explorer.pex");

    quit := false;
    while !quit {
        current_time = seconds_since_init();
        dt := cast(float)(current_time - last_time);
        Clamp(*dt, 0, 0.1);
        last_time = current_time;

        Input.update_window_events();

        for Input.get_window_resizes() {
            Simp.update_window(it.window);  // Simp will do nothing if it doesn't care about this window.

            if it.window == my_window {
                should_reinit := (it.width != window_width) || (it.height != window_height);

                window_width  = it.width;
                window_height = it.height;

                if should_reinit my_init_fonts();  // Resize the font for the new window size.
            }
        }

        for event: Input.events_this_frame {
            if event.type == .QUIT then quit = true;

            getrect_handle_event(event);

            if event.type == {

              case .KEYBOARD;
                if event.key_pressed && event.key_code == .ESCAPE {
                    active_widget_deactivate_all();
                }
                if event.key_pressed && event.key_code == #char "-" {
                    quit = true;
                }

              case .DRAG_AND_DROP_FILES;
                for event.files input_file(it);

                // :AndroidLifeCycle :AndroidWindowSurfaceRecreation
              // case .WINDOW;
              //   if event.window_event_type == {
              //     case .MOVED_TO_BACKGROUND;
              //       Simp.disable_window(event.window);
              //       my_window = WT.INVALID_WINDOW;
              //
              //     case .MOVED_TO_FOREGROUND;
              //       Simp.enable_window(event.window);
              //       my_window = event.window;
            }
        }

        draw_one_frame();

        sleep_milliseconds(10);
        reset_temporary_storage();
        colour_index = 0;
        saved_tooltips.count = 0;
    }
}

draw_one_frame :: () {
    proc := default_theme_procs[current_theme];
    my_theme = proc();
    my_theme.font = my_font;
    set_default_theme(my_theme);  // Just in case we don't explicitly pass themes sometimes...!
    colour_index = 0;

    bg_col := my_theme.background_color;
    Simp.clear_render_target(bg_col.x, bg_col.y, bg_col.z, 1);

    x, y, width, height := get_dimensions(my_window, true);
    ui_per_frame_update(my_window, width, height, current_time);

    sb: String_Builder; init_string_builder(*sb,, temp);
    r: Rect;
    // 'k' is some resolution-adjusting unit of distance. Right now it is
    // 1/10 of the screen height, so, 108 pixels at 1920x1080.
    k := window_height * .1;

    add_new_input_files := false;
    choices: [..]string;
    defer array_reset(*choices);

    // Draw the title:
    label_theme := my_theme.label_theme;
    label_theme.font       = my_font;
    label_height := my_font.character_height*1.5;
    r = get_rect(0, 0, xx window_width, label_height);
    label(r, "Protobuf Explorer", *label_theme);

    // Select a protobuf bytes buffer
    r = get_rect(0, label_height, xx window_width, k*0.25);
    for file_bytes array_add(*choices, it.file_path,, temp);
    changed, state := dropdown(r, choices, *selected_file_bytes);
    if choices.count == 0 && state.open && state.open_t < 0.1 {
        add_new_input_files = true;
    }


    // Add a new file to load
    button_theme := my_theme.button_theme;
    button_theme.font = my_font;
    button_theme.enable_variable_frame_thickness = true;
    r = get_rect(k*0.5, 1*k, 3*k, my_font.character_height*1.5);
    button_theme.label_theme.alignment = .Center;
    if button(r, "Add File", *button_theme) || add_new_input_files {
        files := select_files();
        for file : files {
            input_file(file);
        }
    }

    r.x += r.w * 1.1;
    if button(r, "Save Project", *button_theme) {
        save_project(PROJECT_FILE);
    }

    // The current hex dump of the protobuf message
    label_theme.alignment_pad_ems = 0;
    label_theme.alignment = Text_Alignment.Left;
    r = get_rect(k*0.5, 1.8*k, width-2*k, my_font.character_height*1.5);
    reset(*sb);
    if selected_file_bytes >= 0 && selected_file_bytes < file_bytes.count {
        selected : *FileBytes = *file_bytes[selected_file_bytes];

        filename := path_filename(selected.file_path);
        label(r, filename, *label_theme);

        r.y += r.h;
        label_theme.font = smol_font;
        r.h = smol_font.character_height*1.5;
        label(r, tprint("Full path: %  (% bytes)", selected.file_path, selected.bytes.count), *label_theme);
        r.y += r.h;

        // debugging
            label(r, to_hex(selected.bytes), *label_theme);
            r.y += r.h;

        decompose(selected.bytes, *r);
    }

    // Draw tooltip
    tooltip := get_active_tooltip();
    if tooltip.text {
        r = saved_tooltips[tooltip.int_data];
        r.y += r.h;
        r.w = 1000;
        label(r, tooltip.text, *label_theme);
    }

    draw_popups();

    // ----- end
    Simp.immediate_flush();
    Simp.swap_buffers(my_window);
}

decompose_draw :: (buf_used: []u8, start_position: *Rect, tooltip: string, wire_type: WireType) {
    if buf_used.count == 0 return;

    text := to_hex(buf_used);
    width := Simp.prepare_text(smol_font, text);
    start_position.w = xx width;

    colour := next_colour();
    register_tooltip(tooltip, start_position);
    theme := my_theme.label_theme;
    theme.alignment = .Center;
    // button(start_position, text, identifier=buf.count);
    rect_position := start_position.*;
    rect_position.x -= smol_font.em_width * 0.1;
    rounded_rectangle(rect_position, my_theme.button_theme.rectangle_shape, colour, my_theme.button_theme.frame_color);
    label_from_prepared_text(start_position, smol_font, *theme, do_scissor=false);
    start_position.x += width;
}

decompose :: (bytes: []u8, start_position: *Rect) {
    buf := bytes;

    atom: ProtobufAtom;
    for :protobuf_atoms atom, range : bytes {
        if atom.tag_ok {
            tip := tprint("type(%) %, field number %", atom.wire_type.(int), atom.wire_type, atom.field_number);
            decompose_draw(atom.tag_view, start_position, tip, xx -1);
        }
        if atom.value_ok {
            if #complete atom.wire_type == {
                case .LEN;
                    tip := tprint("LEN %", atom.length);
                    decompose_draw(atom.value_view, start_position, tip, atom.wire_type);
                    tip = tprint("LEN payload (length=%)", atom.length);
                    decompose_draw(atom.submessage, start_position, tip, atom.wire_type);
                case .VARINT;
                    tip := tprint("VARINT value=%  (zigzag: %)", atom.varint, atom.varint_zigzag);
                    decompose_draw(atom.value_view, start_position, tip, atom.wire_type);
                case .I64;
                    tip := tprint("I64 value=%  (float64: %)", atom.I64_int, atom.I64_float);
                    decompose_draw(atom.value_view, start_position, tip, atom.wire_type);
                case .I32;
                    tip := tprint("I32 value=%  (float32: %)", atom.I32_int, atom.I32_float);
                    decompose_draw(atom.value_view, start_position, tip, atom.wire_type);
                case .SGROUP;
                case .EGROUP;
            }
        }

        if atom.failed_view {
            decompose_draw(buf, start_position, TIP_FAIL, xx -1);
        }
    }
}

register_tooltip :: (text: string, object_position: Rect) {
    tooltip(text, int_data=saved_tooltips.count);
    get_status_flags(object_position);
    array_add(*saved_tooltips, object_position);
}

next_colour :: () -> Vector4 {
    hue := colour_index * 360.0 / 16.5;
    colour_index += 1;
    sat := 1.0;
    value := 1.0;
    r, g, b := hsv_to_rgb(hue, sat, value);
    result: Vector4 = .{r, g, b, 0.5};
    return result;
}

my_init_fonts :: () {
    pixel_height := window_height / 24;

    font_bytes :: #run () -> []u8 {
        contents := read_entire_file("resources/OpenSans-BoldItalic.ttf");
        assert(contents != "", "Failed to read font file");
        return contents.([]u8);
    }();

    my_font = Simp.get_font_at_size(font_bytes, pixel_height);
    smol_font = Simp.get_font_at_size(font_bytes, pixel_height/2);
    assert(my_font != null);
}

select_files :: () -> []string {
    #if OS == .LINUX {
        command :: string.["zenity", "--file-selection", "--multiple", "--separator=\n"];
        ret, output := run_command(..command, capture_and_return_output=true,, temp);
        if ret.exit_code != 0 {
            log("File selection failed: %\n", ret, flags=.WARNING);
        }
        output = trim(output);
        if output {
            files := split(output, "\n",, temp);
            return files;
        }
    } else {
        // TODO: Other operating systems
        // Maybe just use tinyfiledialogs or a similar system?
        // https://github.com/native-toolkit/libtinyfiledialogs
    }
    return .[];
}

input_file :: (path: string, file_type: FileType = .AUTO) -> bool {
    in, ok := file_open(path);
    if !ok return false;
    defer file_close(*in);

    length := file_length(in);
    if length >= MAX_FILE_SIZE {
        // TODO: graphical indication...
        log("File is too large, ignoring it: length=%, path=%", length, path);
        return false;
    }

    contents:, ok = read_entire_file(in);
    if !ok return false;

    proto_file := parse_proto_text(contents, path,, logger=silent);
    if file_type == .AUTO {
        if proto_file.definitions {
            file_type = .PROTO;
        } else {
            file_type = .BYTES;
        }
    }
    if file_type == .PROTO {
        log("=== Input file -> proto. %\n", path);

        fp: *FileProto;
        for* file_protos if it.file_path == path { fp = it; break; }
        if !fp then fp = array_add(*file_protos);

        free(fp.file_path);
        // @leak most of the memory of the existing one, if it was found

        fp.file_path = copy_string(path);
        fp.primary = proto_file;
        add_proto_tree_file(*fp.set, proto_file);
        parse_proto_files_set(*fp.set, ..proto_file.imports, search_dirs=search_directories);
    } else {
        log("=== Input file -> bytes. %\n", path);

        fb: *FileBytes;
        for* file_bytes if it.file_path == path { fb = it; break; }
        if !fb then fb = array_add(*file_bytes);

        free(fb.file_path);
        array_reset(*fb.bytes);

        fb.file_path = copy_string(path);
        fb.bytes = xx contents;
    }

    return ok;
}

save_project :: (path: string) -> bool {
    project: Project;
    project.theme = current_theme;
    for file_bytes  array_add(*project.file_bytes, it.file_path);
    for file_protos array_add(*project.file_protos, it.file_path);
    array_add(*project.search_directories, ..search_directories);
    project.selected_file_bytes = selected_file_bytes;

    // Not in temp, because it might be big... but it probably won't be really.
    bytes := Serialize(project);
    defer array_reset(*bytes);
    log("Saving project to '%'", path);
    return write_entire_file(path, bytes.(string));
}

load_project :: (path: string) -> bool {
    log("Loading project at '%'", path);
    defer log("Loading finished for '%'", path);
    project: Project;
    // Not in temp, because it might be big... but it probably won't be actually.
    bytes, ok := read_entire_file(path);
    defer free(bytes);
    if !ok {
        log("Failed to read project file '%'", path, flags=.WARNING);
        return false;
    }

    ok = Deserialize(*project, bytes.([]u8));
    defer free(bytes);
    if !ok {
        log("Failed to deserialize project file '%'", path, flags=.WARNING);
        return false;
    }

    // Validate
    if project.theme < 0 || project.theme >= THEME_COUNT then project.theme = xx Default_Themes.Default;

    // Good to go!
    current_theme = project.theme;
    selected_file_bytes = project.selected_file_bytes;
    search_directories.count = 0;
    file_bytes.count = 0;
    file_protos.count = 0;
    array_add(*search_directories, ..project.search_directories);
    for project.file_bytes   input_file(it, .BYTES);
    for project.file_protos  input_file(it, .PROTO);

    return ok;
}

from_hex_char :: (char: u8) -> u8 {
    if char >= "0" && char <= "9" {
        return char - "0";
    } else if char >= "A" && char <= "F" {
        return char - "A" + 10;
    } else if char >= "a" && char <= "f" {
        return char - "a" + 10;
    } else {
        assert(false, "char must be hex");
        return 0;
    }
}

to_hex_char :: (nibble: u8) -> u8 {
    if nibble < 10 {
        return nibble + "0";
    } else if nibble < 16 {
        return nibble - 10 + "A";
    } else {
        assert(false, "Cannot fit into a single hexadecimal character: %", nibble);
        return "0";
    }
}

build_hex :: (sb: *String_Builder, bytes: []u8, separator := "") {
    for byte : bytes {
        n1 := (byte >> 4) & 0x0F;
        n2 := (byte >> 0) & 0x0F;
        append(sb, to_hex_char(n1));
        append(sb, to_hex_char(n2));
        append(sb, separator);
    }
}

to_hex :: (bytes: []u8) -> string {
    sb: String_Builder;
    init_string_builder(*sb,, temp);
    build_hex(*sb, bytes, " ");
    return builder_to_string(*sb,, temp);
}

silent :: (message: string, data: *void, info: Log_Info) {}

my_font: *Simp.Dynamic_Font;
smol_font: *Simp.Dynamic_Font;

Simp  :: #import "Simp";
Input :: #import "Input";
#import "GetRect_LeftHanded";

#import "Window_Creation";

#import "Basic";
#import "Math";
#import "System";
#import "String";
#import "File";
#import "Process";

#insert #run generate_jai("protobuf-explorer-project.proto");
