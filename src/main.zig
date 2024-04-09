const std = @import("std");
const alloc = std.heap.c_allocator;
const java = @import("java.zig");
// imported values
const stdout = std.io.getStdOut().writer();
const cwd = std.fs.cwd();

pub fn main() !void {
    var argItter = try std.process.ArgIterator.initWithAllocator(alloc);
    defer argItter.deinit();

    _ = argItter.next();
    var fname = argItter.next().?[0..];
    var cf = try java.ClassFile.init(fname, alloc);
    var tmp_file = try cwd.createFile("encode_test.class", .{ .read = true });
    var open_file = try cwd.openFileZ(fname, .{});
    var tmp_writer = tmp_file.writer();
    try cf.encode(tmp_writer);
    var reopen = try cwd.openFile("encode_test.class", .{});
    var f1 = try reopen.readToEndAlloc(alloc, 1024 * 1024 * 1024);
    var f2 = try open_file.readToEndAlloc(alloc, 1024 * 1024 * 1024);
    if (std.mem.eql(u8, f1, f2)) {
        std.debug.print("{s} is working!!!\n", .{fname});
    } else {
        var a = if (f1.len <= f2.len) f1.len else f2.len;
        for (0..a) |c| {
            if (f1[c] != f2[c]) {
                std.debug.print("{s} is not working :( {d} != {d} discont @ idx {X}\n", .{ fname, f1.len, f2.len, c });
                break;
            }
        }
    }
    defer cf.deinit();
}
