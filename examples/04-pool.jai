/*
 * Example: Using different memory allocation strategies, primarily focused
 * on the Flat_Pool (arena) allocator.
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
    // Real-world situations will likely want to use Protobuf encode and decode with
    // good allocation methods, so examples are covered in here.

    // Dummy message
    message: Person;
    message.name = "Bob";

    { // 1. No dynamic allocations (stack-allocated, or global, or in an existing struct buffer, ...)
        stack_buffer: [1024]u8;
        buffer_index := Serialize(stack_buffer, stack_buffer.count, message);
        if buffer_index >= 0 {
            message_bytes := encode_finish(stack_buffer, buffer_index);
            print("Succesfully encoded the message into a stack buffer. Used %/% bytes: %\n", message_bytes.count, stack_buffer.count, message_bytes);
        } else {
            // to see this message, you'll need to decrease the stack_buffer to 4 bytes or less.
            print("Failed to encode the message into % bytes. It required % bytes.\n", stack_buffer.count, encode_calc_size(stack_buffer, buffer_index));
        }
    }
    print("\n");

    { // 2. Temporary allocator, ONLY if the message is small and will definitely fit.
        bytes := Serialize(message,, temp);
        print("Temporary storage bytes: %\n", bytes);
    }
    print("\n");

    { // 3. The Flat_Pool allocator can be reset to clear all memory at once
        // by setting the pointer back to the beginning, so it is very cheap to free data.
        pool: Flat_Pool;
        pool_allocator: Allocator;
        pool_allocator.proc = flat_pool_allocator_proc;
        pool_allocator.data = *pool;

        buffer: []u8;

        // a) Push the whole context so all allocations go to the Flat_Pool
        pool_context := context;
        pool_context.allocator = pool_allocator;
        push_context pool_context {
            // Simulate 2 "packets" sent and received
            for 1..2 {
                defer reset(*pool); // Clear the pool at the end

                group: Group;
                group.group_name = sprint("Group %", it);
                for person_index: 1..2 {
                    person := array_add(*group.people);
                    person.name = sprint("Person % from group %", person_index, it);
                    person.age = person_index.(s32) + 30;
                }

                buffer = Serialize(group); // context allocator goes to the pool
                print("   -> Sending bytes:    %\n", buffer);
                // ...
                reconstructed: Group;
                Deserialize(*reconstructed, buffer);
                print("   <- Received bytes, reconstructed %\n", reconstructed);
                print("   --- % bytes in the pool\n", pool_size(pool));
                print("\n");
            }
        }

        // b) Alternatively use the push_allocator macro which defers the pop back to the original allocator
        {
            push_allocator(pool_allocator);
            defer reset(*pool);

            reconstructed: Group;
            Deserialize(*reconstructed, buffer);
            // ... use the data.
            // do NOT need to call FreeContents(*reconstructed);
        }

        // c) or override the allocator on individual calls
        {
            reconstructed: Group;
            Deserialize(*reconstructed, buffer,, pool_allocator); // comma-comma
            reset(*pool);
        }
    }
}

pool_size :: (pool: Flat_Pool) -> int {
    return pool.current_point - pool.memory_base;
}

#import "Basic";
#import "Flat_Pool";
