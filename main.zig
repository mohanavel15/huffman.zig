const huffman = @import("huffman.zig");
const std = @import("std");

pub fn main() !void {
    const message =
        \\ In computer science and information theory,
        \\ a Huffman code is a particular type of optimal
        \\ prefix code that is commonly used for lossless
        \\ data compression. The process of finding or using
        \\ such a code is Huffman coding, an algorithm
        \\ developed by David A. Huffman while he was a
        \\ Sc.D. student at MIT, and published in the 1952 paper
        \\ "A Method for the Construction of Minimum-Redundancy Codes"
    ;

    var encoded = try huffman.encode(std.heap.page_allocator, @constCast(message));
    const decoded = try huffman.decode(std.heap.page_allocator, &encoded);

    std.debug.print("----Raw----\n", .{});
    std.debug.print("Length: {}\n", .{message.len});
    std.debug.print("Bits: {}\n", .{message.len * 8});

    std.debug.print("----Encoded----\n", .{});
    std.debug.print("Length: {}\n", .{encoded.compressed_length});
    std.debug.print("Bits: {}\n", .{encoded.bit_length});

    std.debug.print("----Decoded----\n", .{});
    std.debug.print("Lossless {}\n", .{std.mem.eql(u8, @constCast(message), decoded)});
    std.debug.print("{s}\n", .{decoded});
}
