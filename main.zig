const huffman = @import("huffman.zig");
const std = @import("std");

const Allocator = std.mem.Allocator;
const process = std.process;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory Leaked in Compress File!");
        }
    }

    const allocator = gpa.allocator();

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Invalid Arguments\n", .{});
        return;
    }

    const mode = args[1];
    const filename = args[2];

    if (std.mem.eql(u8, mode, "-c")) {
        try compress_file(allocator, filename);
    } else if (std.mem.eql(u8, mode, "-d")) {
        try decompress_file(allocator, filename);
    } else {
        std.debug.print("Invalid Arguments", .{});
    }
}

fn compress_file(allocator: Allocator, filename: []const u8) !void {
    const original_file = try std.fs.cwd().openFile(filename, .{});
    defer original_file.close();

    const buffer = try original_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(buffer);

    var encoded = try huffman.encode(allocator, buffer);
    defer encoded.deinit(allocator);

    const filename_compress = std.fmt.allocPrint(allocator, "{s}.huffman", .{filename}) catch unreachable;
    defer allocator.free(filename_compress);

    const compressed_file = try std.fs.cwd().createFile(filename_compress, .{});
    defer compressed_file.close();

    const final_buf = try encoded.serialize(allocator);
    defer allocator.free(final_buf);

    try compressed_file.writeAll(final_buf);
}

pub fn decompress_file(allocator: Allocator, filename: []const u8) !void {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const buffer = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(buffer);

    var encoded = huffman.Encoded.deserialize(buffer);

    const decoded = try huffman.decode(allocator, &encoded);
    defer allocator.free(decoded);

    const decoded_file = try std.fs.cwd().createFile(filename[0 .. filename.len - 8], .{});
    defer decoded_file.close();

    try decoded_file.writeAll(decoded);
}
