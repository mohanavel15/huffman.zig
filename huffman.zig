const std = @import("std");
const Allocator = std.mem.Allocator;

const Node = struct {
    value: ?u8,
    probs: f64,
    left: ?*Node,
    right: ?*Node,
};

const CodeBlock = struct {
    bits: u8,
    len: u8,
};

pub const Encoded = struct {
    probs: []f64,
    encoded: []u8,
    compressed_length: usize,
    original_length: usize,
    bit_length: usize,
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
    const node = buildTree(encoded.probs);
    displayTree("", node);

    var bitTable: [256]CodeBlock = undefined;
    @memset(&bitTable, .{ .bits = 0, .len = 0 });

    constructBitTable(&bitTable, node, 0, 0);
    encodeCodeBlock(&bitTable, &encoded, buffer);

    return encoded;
}

pub fn decode(allocator: Allocator, encoded: *Encoded) ![]u8 {
    const node = buildTree(encoded.probs);
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

pub fn constructBitTable(table: []CodeBlock, node: *Node, bits: u8, len: u8) void {
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

pub fn buildTree(probs: []f64) *Node {
    var nonZeroNode: [256]*Node = undefined;
    var len: usize = 0;

    for (0..256) |idx| {
        if (probs[idx] > 0) {
            var node = std.heap.page_allocator.create(Node) catch unreachable;
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

        var node = std.heap.page_allocator.create(Node) catch unreachable;
        node.value = null;
        node.probs = node1.probs + node2.probs;
        node.left = node1;
        node.right = node2;

        sortedInsertNode(nonZeroNode[0..], len, node);
        len += 1;
    }

    return nonZeroNode[0];
}

pub fn displayTree(prefix: []const u8, node: *Node) void {
    std.debug.print("{s}[{c}]\n", .{ prefix, node.value orelse '+' });

    const prefix1 = std.fmt.allocPrint(std.heap.page_allocator, "{s}\t", .{prefix}) catch unreachable;
    defer std.heap.page_allocator.free(prefix1);

    if (node.left) |left| {
        displayTree(prefix1, left);
    }

    if (node.right) |right| {
        displayTree(prefix1, right);
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

pub fn encodeCodeBlock(code_table: []CodeBlock, encoded: *Encoded, buffer: []u8) void {
    var len_bits: usize = 0;

    var bytes: []u8 = std.heap.page_allocator.alloc(u8, buffer.len) catch unreachable;
    @memset(bytes, 0);

    var idx: usize = 0;
    var len: usize = 8;
    for (buffer) |byte| {
        const code_block = code_table[byte];
        len_bits += code_block.len;
        if (len >= code_block.len) {
            len -= code_block.len;
            bytes[idx] = bytes[idx] | (code_block.bits << @as(u3, @intCast(len)));
        } else {
            const remain = code_block.len - len;
            bytes[idx] = bytes[idx] | (code_block.bits >> @as(u3, @intCast(remain)));
            idx += 1;
            len = 8;
            len -= remain;
            bytes[idx] = bytes[idx] | (code_block.bits << @as(u3, @intCast(len)));
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
