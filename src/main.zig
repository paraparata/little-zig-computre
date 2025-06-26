pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    // Get arguments
    const pac = std.heap.page_allocator;
    const args = try std.process.argsAlloc(pac);
    defer std.process.argsFree(pac, args);

    // process.args will always has at least one argument: path of executable program
    if (args.len < 2) {
        std.debug.print("lzc [image-file1] ...\n", .{});
        return error.ExpectedArgument;
    }

    // Since we only need a filename. We don't need more arguments
    if (args.len != 2) {
        return error.ExpectedOnlyOneFilename;
    }

    const filename = args[1];

    // String concatenation
    // Refer to test_slice.zig in https://ziglang.org/documentation/master/#Slices
    var start_index: usize = 0;
    _ = &start_index;
    var path_arr: [100]u8 = undefined;
    const path_slice = path_arr[start_index..];
    // Output generated file to `generated` directory
    const path = try std.fmt.bufPrint(path_slice, "{s}", .{filename});

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var lzc = Lzc.init(stdin.any(), stdout.any());
    try lzc.run(file);
}

const std = @import("std");
const Lzc = @import("./lzc.zig");
