/*
 * Example: Using a Flat_Pool (arena) allocator
 *
 * Usage:
 *   jai 04-pool.jai
 *   ./04-pool
 */

// #import "Protobuf";
#import,dir "..";

// Insert the generated code.
// See .build/.added_strings_w2.jai
#insert #run generate_jai("protos/some_things.proto");

main :: () {
    // The pool allocator can be reset to clear all memory at once
    pool: Flat_Pool;
    pool_allocator: Allocator;
    pool_allocator.proc = flat_pool_allocator_proc;
    pool_allocator.data = *pool;

    // A context which can be easily pushed/popped as required
    pool_context := context;
    pool_context.allocator = pool_allocator;

    buffer: []u8;

    // Push the whole context to reset everything
    push_context pool_context {
        // Simulate 5 "packets" arriving
        for 1..5 {
            defer reset(*pool); // Clear the pool at the end

            group: Group;
            group.group_name = sprint("Group %", it);
            for person_index: 1..2 {
                person := array_add(*group.people);
                person.name = sprint("Person % from group %", person_index, it);
                person.age = person_index.(s32) + 30;
            }

            buffer = Serialize(group);
            print("   -> Sending bytes:    %\n", buffer);
            // ...
            reconstructed: Group;
            Deserialize(*reconstructed, buffer);
            print("   <- Received bytes, reconstructed %\n", reconstructed);
            print("   --- % bytes in the pool\n", pool_size(pool));
            print("\n");
        }
    }

    // Alternatively use the push_allocator macro
    {
        push_allocator(pool_allocator);
        defer reset(*pool);

        reconstructed: Group;
        Deserialize(*reconstructed, buffer);
        // ... use the data.
        // do NOT need to call FreeContents(*reconstructed);
    }

    // Or override the allocator on individual calls
    {
        reconstructed: Group;
        Deserialize(*reconstructed, buffer,, pool_allocator); // comma-comma
        reset(*pool);
    }
}

pool_size :: (pool: Flat_Pool) -> int {
    return pool.current_point - pool.memory_base;
}

#import "Basic";
#import "Flat_Pool";
