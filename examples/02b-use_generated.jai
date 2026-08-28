/*
 * Example: Use pre-generated code.
 * Must run the pre-generation code before this program, for it to work.
 *
 * First time setup and when protobuf schemas or pregenerate.jai are modified:
 *   jai 02a-pregenerate.jai;   // This generates the file we load here
 *   jai 02b-use_generated.jai  // Actually build this
 *   ./02b-use-generated
 * Subsequent:
 *   jai 02b-use_generated.jai
 *   ./02b-use-generated
 */

/*
 * Usually, we would use #import "Protobuf"; but because we are in the same repo,
 * we import it this way instead.
 */
// #import "Protobuf";
#import,dir "..";

#load "generated/protobuf_definitions.jai";

main :: () {
    group: Group;
    group.group_name = "Players";
    array_add(*group.people, .{name = "Bob", age = 42, height_cm = 169.4});
    array_add(*group.people, .{name = "Jane", age = 28, height_cm = 171.8});

    print("group1: %\n", group);

    // Serialize to bytes. Allocates. Consider setting allocators in real programs.
    bytes := Serialize(group);
    defer array_reset(*bytes);
    print("  Encoded as bytes: %\n", bytes);

    // Send over a socket, or write to file, ...

    // Deserialize into structure
    decoded: Group;
    ok := Deserialize(*decoded, bytes); // May allocate (e.g. repeated elements)
    print("Deserialize Group from bytes: %\n", ifx ok "ok" else "failed");

    print("group2: %\n", decoded);
    FreeContents(*decoded);
}

#import "Basic";
