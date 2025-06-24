pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    // Get arguments
    // const pac = std.heap.page_allocator;
    // const args = try std.process.argsAlloc(pac);
    // defer std.process.argsFree(pac, args);
    //
    // // process.args will always has at least one argument: path of executable program
    // if (args.len < 2) {
    //     std.debug.print("lzc [image-file1] ...\n", .{});
    //     return error.ExpectedArgument;
    // }
    //
    // // Since we only need a filename. We don't need more arguments
    // if (args.len != 2) {
    //     return error.ExpectedOnlyOneFilename;
    // }
    //
    // const filename = args[1];
    //
    // // String concatenation
    // // Refer to test_slice.zig in https://ziglang.org/documentation/master/#Slices
    // var start_index: usize = 0;
    // _ = &start_index;
    // var path_arr: [100]u8 = undefined;
    // const path_slice = path_arr[start_index..];
    // // Output generated file to `generated` directory
    // const path = try std.fmt.bufPrint(path_slice, "generated/{s}", .{filename});
    //
    // const file = try std.fs.cwd().createFile(path, .{});
    // defer file.close();

    const lzc = Lzc.init(stdout.any());

    try stdout.print("Init..\nmem len: {} | reg len: {}\n", .{ lzc.memory.len, lzc.reg.len });

    try bw.flush();
}

// test "simple test" {
//     var list = std.ArrayList(i32).init(std.testing.allocator);
//     defer list.deinit();
//     try list.append(42);
//     try std.testing.expectEqual(@as(i32, 42), list.pop());
// }
//
// test "fuzz example" {
//     const Context = struct {
//         fn testOne(context: @This(), input: []const u8) anyerror!void {
//             _ = context;
//             try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
//         }
//     };
//     try std.testing.fuzz(Context{}, Context.testOne, .{});
// }

const std = @import("std");
const Lzc = @import("./lzc.zig");
