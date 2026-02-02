/*
 * Example: Use pre-generated code.
 * Must compile and run pregenerate.jai before this program for it to work.
 *
 * First time and when protobuf schemas or pregenerate.jai are modified:
 *   jai 02a-pregenerate.jai; ./02a-pregenerate; jai 02b-use_generated.jai
 * Subsequent:
 *   jai 02b-use_generated.jai
 */

/*
 * Usually, we would use #import "Protobuf"; but because we are in the same repo,
 * we import it this way instead.
 */
// #import "Protobuf";
#import,dir "..";

#import,file "generated/some_things.proto.jai";
#import,file "generated/many_things.proto.jai";

main :: () {
    group: Group;
    group.group_name = "Players";
    array_add(*group.people, .{name = "Bob", age = 42, height_cm = 169.4});
    array_add(*group.people, .{name = "Jane", age = 28, height_cm = 171.8});

    print("group1: %\n", group);

    // Serialize to bytes. Allocates. Consider using ,,temp
    bytes := Serialize(group);
    defer array_free(bytes);
    print("  Encoded as bytes: %\n", bytes);

    // Send over a socket, or write to file, ...

    // Deserialize into structure
    decoded: Group;
    ok := Deserialize(*decoded, bytes);
    print("Deserialize Group from bytes: %\n", ifx ok "ok" else "failed");

    print("group2: %\n", decoded);
}

#import "Basic";
