/*
 * Example: insert Protobuf-generated code during compilation, and use it immediately.
 *
 * Usage:
 *   jai 01-compiletime.jai
 *   ./01-compiletime
 */

/*
 * Usually, we would use #import "Protobuf"; but because we are in the same repo,
 * we import it this way instead.
 */
// #import "Protobuf";
#import,dir "..";

// Insert the generated code.
// See .build/.added_strings_w2.jai
#insert #run generate_jai(.["protos/some_things.proto"]);

main :: () {
    group: Group;
    group.group_name = "Players";
    array_add(*group.people, .{name = "Bob", age = 42, height_cm = 169.4});
    array_add(*group.people, .{name = "Jane", age = 28, height_cm = 171.8});

    print("group1: %\n", group);

    // Serialize to bytes. Allocates. Consider using ,,temp
    bytes := Serialize(group);
    defer array_reset(*bytes);
    print("  Encoded as bytes: %\n", bytes);

    // Send over a socket, or write to file, ...

    // Deserialize into structure
    decoded: Group;
    ok := Deserialize(*decoded, bytes);
    print("Deserialize Group from bytes: %\n", ifx ok "ok" else "failed");

    print("group2: %\n", decoded);
}

#import "Basic";
