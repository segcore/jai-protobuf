/*
 * Example: Using different memory allocation strategies.
 *
 * Usage:
 *   jai 04-memory-allocation.jai
 *   ./04-memory-allocation
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

    { // 1. User-supplied buffer. Can be used without any dynamic allocations (stack-allocated, or global, or in an existing struct buffer, ...)
        print("===== Stack buffer =====\n");
        stack_buffer: [1024]u8;
        message_bytes, required_size := Serialize(message, stack_buffer);
        if message_bytes {
            print("Succesfully encoded the message into a stack buffer. Used %/% bytes: %\n", message_bytes.count, stack_buffer.count, message_bytes);
        } else {
            // to see this message, you'll need to decrease the stack_buffer to 4 bytes or less.
            print("Failed to encode the message into % bytes. It required % bytes.\n", stack_buffer.count, required_size);
        }

        // An example that might be seen in network traffic
        // This is not "no dynamic allocation", but it is re-using the encode buffer for all encode calls
        // This has the added benefit that when the buffer is large enough, it is all encoded
        // in a single pass, so is the fastest encoding that you can get
        MyNetworkSender :: struct {
            socket: int;
            encode_buffer: [..]u8;
            receive_buffer: [..]u8;
            encode_buffer_if_fixed_size_is_ok: [4096]u8;
        }
        network_send :: (socket: int, bytes: []u8) {
            // pretend this is real
            print("Sending on socket %: bytes %\n", socket, bytes);
        }
        send_serialized_protobuf_over_the_network :: (net: *MyNetworkSender, person: Person) {
            message_bytes, required_size := Serialize(person, net.encode_buffer);
            if !message_bytes {
                // Exact required_size would be enough, but then each call might
                // keep re-allocating e.g. 1 byte larger, which is slow.
                array_resize(*net.encode_buffer, 2 * required_size, initialize=false);
                message_bytes = Serialize(person, net.encode_buffer);
            }
            network_send(net.socket, message_bytes);
        }
        net: MyNetworkSender = .{ socket = 3 };
        defer array_reset(*net.encode_buffer);
        send_serialized_protobuf_over_the_network(*net, message);
    }
    print("\n");

    { // 2. Temporary allocator, ONLY if the message is small and will definitely fit.
        print("===== Temporary storage =====\n");
        bytes := Serialize(message,, temp);
        print("Temporary storage bytes: %\n", bytes);
    }
    print("\n");

    {
        // 3. The Flat_Pool allocator can be reset to clear all memory at once
        // by setting the pointer back to the beginning, so it is very cheap to free data,
        // and subsequent allocations will re-use the same memory region, so will be faster.
        print("===== Flat pool =====\n");
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

    { // 4. Finally, if you really need it, the general purpose heap allocator
        print("===== Default allocator =====\n");
        bytes := Serialize(message);
        defer array_reset(*bytes); // Remember to free!
        print("Default allocator storage bytes: %\n", bytes);

        // ...

        received: Person;
        Deserialize(*received, bytes);
        // ... use it until finished

        // The deserialized message must be freed (if it contains dynamic memory)
        // In particular, if in the message's recursive expanded struct, contain any repeated elements ([..]arrays) or map<>.
        FreeContents(*received);
        // Trivial free procedures are still generated, but are empty and marked inline, so should be quite free.
    }
}

pool_size :: (pool: Flat_Pool) -> int {
    return pool.current_point - pool.memory_base;
}

#import "Basic";
#import "Flat_Pool";
