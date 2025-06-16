const huffman = @import("huffman.zig");
const std = @import("std");

pub fn main() !void {
    var encoded = huffman.encode(@constCast("Helloooo"));
    const decoded = huffman.decode(&encoded);

    std.debug.print("{s}\n", .{decoded});
}
