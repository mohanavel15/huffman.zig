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

    pub fn serialize(self: *const Self, allocator: Allocator) ![]u8 {
        const probs = encodeToBytes(f64, &self.probs[0], self.probs.len);
        const probs_len = encodeToBytes(usize, &probs.len, 1);
        const compressed_len = encodeToBytes(usize, &self.compressed_length, 1);
        const original_len = encodeToBytes(usize, &self.original_length, 1);
        const bit_len = encodeToBytes(usize, &self.bit_length, 1);

        const total_len = probs.len + probs_len.len + compressed_len.len + original_len.len + bit_len.len + self.compressed_length;

        const final_buf = try allocator.alloc(u8, total_len);
        @memcpy(final_buf[0..8], bit_len);
        @memcpy(final_buf[8..16], original_len);
        @memcpy(final_buf[16..24], probs_len);

        var start: usize = 24;
        @memcpy(final_buf[start .. start + probs.len], probs);
        start += probs.len;

        @memcpy(final_buf[start .. start + 8], compressed_len);
        start += 8;

        @memcpy(final_buf[start .. start + self.compressed_length], self.encoded[0..self.compressed_length]);

        return final_buf;
    }

    pub fn deserialize(buffer: []u8) Self {
        var start: usize = 0;
        const bit_len = decodeFromBytes(usize, buffer[start .. start + 8])[0];
        start += 8;

        const original_len = decodeFromBytes(usize, buffer[start .. start + 8])[0];
        start += 8;

        const probs_len = decodeFromBytes(usize, buffer[start .. start + 8])[0];
        start += 8;

        const probs = decodeFromBytes(f64, buffer[start .. start + probs_len]);
        start += probs_len;

        const compress_len = decodeFromBytes(usize, buffer[start .. start + 8])[0];
        start += 8;

        const compressed = buffer[start .. start + compress_len];

        return Encoded{
            .probs = @constCast(probs),
            .original_length = original_len,
            .bit_length = bit_len,
            .compressed_length = compress_len,
            .encoded = @constCast(compressed),
        };
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
    const node = buildTree(allocator, encoded.probs);
    defer destroyTree(allocator, node);

    displayTree(allocator, node, "", true);

    var bitTable: [256]CodeBlock = undefined;
    @memset(&bitTable, .{ .bits = 0, .len = 0 });

    constructBitTable(&bitTable, node, 0, 0);
    encodeCodeBlock(allocator, &bitTable, &encoded, buffer);

    return encoded;
}

pub fn decode(allocator: Allocator, encoded: *Encoded) ![]u8 {
    const node = buildTree(allocator, encoded.probs);
    defer destroyTree(allocator, node);

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

pub fn destroyTree(allocator: Allocator, node: *Node) void {
    defer allocator.destroy(node);
    if (node.left) |left| {
        destroyTree(allocator, left);
    }

    if (node.right) |right| {
        destroyTree(allocator, right);
    }
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

// ------------------------ General  ------------------------ //

fn encodeToBytes(comptime T: type, buf: *const T, len: usize) []const u8 {
    return @as([*]const u8, @ptrCast(buf))[0 .. len * @sizeOf(T)];
}

fn decodeFromBytes(comptime T: type, bytes: []const u8) []const T {
    const t_size = @sizeOf(T);
    std.debug.assert(bytes.len % t_size == 0);

    const aligned_ptr: [*]align(@alignOf(T)) const u8 = @alignCast(bytes.ptr);
    return @as([*]const T, @ptrCast(aligned_ptr))[0 .. bytes.len / t_size];
}
