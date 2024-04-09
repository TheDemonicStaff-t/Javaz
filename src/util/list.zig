const std = @import("std");
// imported structures
const Allocator = std.mem.Allocator;

pub fn List(comptime t: type) type {
    // create a custom struct for each list
    return struct {
        const Self = @This(); // used for init function mainly
        const T = t;
        list: []T,
        count: usize = 0,
        capacity: usize = 256,
        a: Allocator,

        pub fn init(a: Allocator) !Self {
            // create a new list
            return Self{
                .list = try a.alloc(T, 256),
                .a = a,
            };
        }

        pub fn add(self: *Self, val: anytype) !void {
            // check if buffer resize is required
            if (self.*.count == self.*.capacity) {
                self.*.list = try self.*.a.realloc(self.*.list, self.*.capacity + 256);
                self.*.capacity += 256;
            }

            // add new element
            self.*.list[self.*.count] = val;
            self.*.count += 1;
        }

        pub fn toArray(self: *Self) ![]T {
            // resize list and change ownership
            defer {
                self.*.count = 0;
            }
            return try self.*.a.realloc(self.*.list, self.*.count);
        }

        pub fn deinit(self: *Self) void {
            // free all leftover memory (unless .toArray is used)
            if (self.*.count != 0) {
                self.*.a.free(self.*.list);
                self.*.count = 0;
            }
        }

        test init {
            const a = std.heap.c_allocator;
            var l = try List.init(usize, a);
            l.deinit();
        }

        test add {
            const x: []usize = [3]usize{ 4, 2, 0 };
            const a = std.heap.c_allocator;
            var l = try List.init(usize, a);
            defer l.deinit();

            l.add(4);
            l.add(2);
            l.add(0);

            for (l.list, 0..3) |v, i| try std.testing.expect(v == x[i]);
        }

        test toArray {
            const a = std.heap.c_allocator;
            var l = try List.init(usize, a);

            l.add(4);
            l.add(2);
            l.add(0);

            var tmp = l.toArray();
            defer a.free(tmp);

            try std.testing.expect(tmp.len == 3);
        }
    };
}
