const std = @import("std");
const Allocator = std.mem.Allocator;

const Node = struct {
    value: ?u8,
    probs: f64,
    left: ?*Node,
    right: ?*Node,
};

const CodeBlock = struct {
    bits: u256,
    len: u8,
};

pub const Encoded = struct {
    probs: []f64,
    encoded: []u8,
    compressed_length: usize,
    original_length: usize,
    bit_length: usize,

    const Self = @This();
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.probs);
        allocator.free(self.encoded);
    }
};

pub fn encode(allocator: Allocator, buffer: []u8) !Encoded {
    var encoded = Encoded{
        .probs = try allocator.alloc(f64, 256),
        .original_length = buffer.len,
        .encoded = undefined,
        .compressed_length = undefined,
        .bit_length = undefined,
    };
    @memset(encoded.probs, 0);

    const prob: f64 = 1 / @as(f64, @floatFromInt(buffer.len));
    for (buffer) |byte| {
        encoded.probs[byte] += prob;
    }

    std.debug.print("Tree: \n", .{});
    const node = buildTree(std.heap.page_allocator, encoded.probs);
    displayTree(allocator, node, "", true);

    var bitTable: [256]CodeBlock = undefined;
    @memset(&bitTable, .{ .bits = 0, .len = 0 });

    constructBitTable(&bitTable, node, 0, 0);
    encodeCodeBlock(allocator, &bitTable, &encoded, buffer);

    return encoded;
}

pub fn decode(allocator: Allocator, encoded: *Encoded) ![]u8 {
    const node = buildTree(std.heap.page_allocator, encoded.probs);
    var decoded = try allocator.alloc(u8, encoded.original_length);
    var curr: *Node = node;

    var idx: usize = 0;
    var idx2: usize = 0;

    for (0..encoded.bit_length) |bit| {
        if (bit != 0 and bit % 8 == 0) {
            idx2 += 1;
        }

        const shift: u3 = 7 - @as(u3, @intCast(bit % 8));
        const shifted_bit = @as(u8, 1) << shift;

        if ((encoded.encoded[idx2] & shifted_bit) == shifted_bit) {
            curr = curr.right.?;
        } else {
            curr = curr.left.?;
        }

        if (curr.value) |v| {
            decoded[idx] = v;
            idx += 1;
            curr = node;
        }
    }

    return decoded;
}

pub fn constructBitTable(table: []CodeBlock, node: *Node, bits: u256, len: u8) void {
    if (node.value) |value| {
        table[value].bits = bits;
        table[value].len = len;
    }

    if (node.left) |left| {
        constructBitTable(table, left, (bits << 1), len + 1);
    }

    if (node.right) |right| {
        constructBitTable(table, right, (bits << 1) + 1, len + 1);
    }
}

pub fn buildTree(allocator: Allocator, probs: []f64) *Node {
    var nonZeroNode: [256]*Node = undefined;
    var len: usize = 0;

    for (0..256) |idx| {
        if (probs[idx] > 0) {
            var node = allocator.create(Node) catch unreachable;
            node.value = @intCast(idx);
            node.probs = probs[idx];
            node.left = null;
            node.right = null;

            sortedInsertNode(nonZeroNode[0..], len, node);
            len += 1;
        }
    }

    while (len > 1) {
        const node1 = nonZeroNode[len - 1];
        const node2 = nonZeroNode[len - 2];
        len -= 2;

        var node = allocator.create(Node) catch unreachable;
        node.value = null;
        node.probs = node1.probs + node2.probs;
        node.left = node1;
        node.right = node2;

        sortedInsertNode(nonZeroNode[0..], len, node);
        len += 1;
    }

    return nonZeroNode[0];
}

pub fn displayTree(allocator: Allocator, node: *Node, prefix: []const u8, is_left: bool) void {
    if (node.right) |right| {
        const prefix_right = std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, if (is_left) "│   " else "    " }) catch unreachable;
        defer allocator.free(prefix_right);

        displayTree(allocator, right, prefix_right, false);
    }

    std.debug.print("{s}{s}{c}\n", .{ prefix, if (is_left) "└── " else "┌── ", node.value orelse '+' });

    if (node.left) |left| {
        const prefix_left = std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, if (!is_left) "│   " else "    " }) catch unreachable;
        defer allocator.free(prefix_left);

        displayTree(allocator, left, prefix_left, true);
    }
}

pub fn sortedInsertNode(array: []*Node, len: usize, node: *Node) void {
    if (len == 0) {
        array[0] = node;
        return;
    }

    var idx: usize = len;
    while (idx > 0 and array[idx - 1].probs < node.probs) {
        array[idx] = array[idx - 1];
        idx -= 1;
    }

    array[idx] = node;
}

pub fn encodeCodeBlock(allocator: Allocator, code_table: []CodeBlock, encoded: *Encoded, buffer: []u8) void {
    var len_bits: usize = 0;

    var bytes: []u8 = allocator.alloc(u8, buffer.len) catch unreachable;
    @memset(bytes, 0);

    var idx: usize = 0;
    var len: u8 = 8;
    for (buffer) |byte| {
        const code_block = code_table[byte];
        len_bits += code_block.len;
        if (len >= code_block.len) {
            len -= code_block.len;
            bytes[idx] = bytes[idx] | @as(u8, @truncate(code_block.bits << len));
        } else {
            var remain = code_block.len;
            while (remain > len) {
                remain = remain - len;
                bytes[idx] = bytes[idx] | @as(u8, @truncate(code_block.bits >> remain));
                idx += 1;
                len = 8;
            }
            len -= remain;
            bytes[idx] = bytes[idx] | @as(u8, @truncate(code_block.bits << len));
        }

        if (len == 0) {
            idx += 1;
            len = 8;
        }
    }

    encoded.encoded = bytes;
    encoded.bit_length = len_bits;
    encoded.compressed_length = idx + 1;
}
