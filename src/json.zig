const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;

const core = @import("core.zig");
const Document = core.Document;
const Node = core.Node;

pub const Json = struct {
    allocator: Allocator,
    output: ArrayList(u8) = .empty,
    has_document: bool = false,

    pub fn init(allocator: Allocator) Json {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Json) void {
        self.output.deinit(self.allocator);
    }

    pub fn writeDocument(self: *Json, document: Document) !void {
        if (self.has_document) return error.DocumentAlreadyWritten;

        const output_start = self.output.items.len;
        errdefer self.output.items.len = output_start;

        try self.writeSlice("{\"prologue\":{\"version\":");
        try self.writeString(document.prologue.version);
        try self.writeSlice(",\"encoding\":");
        try self.writeString(document.prologue.encoding);
        try self.writeSlice(",\"standalone\":");
        try self.writeSlice(if (document.prologue.standalone) "true" else "false");
        try self.writeSlice("},\"content\":[");

        var wrote_content = false;
        var wrote_root = false;
        for (document.content.items) |part| {
            if (part == .root and (document.root == null or wrote_root)) continue;
            if (wrote_content) try self.output.append(self.allocator, ',');
            switch (part) {
                .comment => |comment| try self.writeComment(comment),
                .root => {
                    try self.writeNode(document.root.?);
                    wrote_root = true;
                },
            }
            wrote_content = true;
        }

        if (!wrote_root) {
            if (document.root) |root| {
                if (wrote_content) try self.output.append(self.allocator, ',');
                try self.writeNode(root);
            }
        }
        try self.writeSlice("]}");
        self.has_document = true;
    }

    /// Transfers the serialized buffer to the caller.
    pub fn toOwnedSlice(self: *Json) ![]u8 {
        if (!self.has_document) return error.DocumentNotWritten;
        const output = try self.output.toOwnedSlice(self.allocator);
        self.has_document = false;
        return output;
    }

    /// Serializes one document. The caller owns the returned slice.
    pub fn stringify(allocator: Allocator, document: Document) ![]u8 {
        var json: Json = .init(allocator);
        defer json.deinit();

        try json.writeDocument(document);
        return json.toOwnedSlice();
    }

    fn writeNode(self: *Json, node: Node) !void {
        try self.writeSlice("{\"type\":\"element\",\"name\":");
        try self.writeString(node.metadata.tag);
        try self.writeSlice(",\"attributes\":{");

        var keys: ArrayList([]const u8) = .empty;
        defer keys.deinit(self.allocator);
        var attributes = node.metadata.attributes.iterator();
        while (attributes.next()) |entry| {
            try keys.append(self.allocator, entry.key_ptr.*);
        }
        mem.sort([]const u8, keys.items, {}, lessThan);

        for (keys.items, 0..) |key, index| {
            if (index > 0) try self.output.append(self.allocator, ',');
            try self.writeString(key);
            try self.output.append(self.allocator, ':');
            try self.writeString(node.metadata.attributes.get(key).?);
        }

        try self.writeSlice("},\"content\":[");
        for (node.content.items, 0..) |part, index| {
            if (index > 0) try self.output.append(self.allocator, ',');
            switch (part) {
                .text => |text| {
                    try self.writeSlice("{\"type\":\"text\",\"value\":");
                    try self.writeString(text);
                    try self.output.append(self.allocator, '}');
                },
                .comment => |comment| try self.writeComment(comment),
                .element => |child| try self.writeNode(child),
            }
        }
        try self.writeSlice("]}");
    }

    fn writeComment(self: *Json, comment: []const u8) !void {
        try self.writeSlice("{\"type\":\"comment\",\"value\":");
        try self.writeString(comment);
        try self.output.append(self.allocator, '}');
    }

    fn writeString(self: *Json, value: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;

        const hex = "0123456789abcdef";
        try self.output.append(self.allocator, '"');
        for (value) |byte| {
            switch (byte) {
                '"' => try self.writeSlice("\\\""),
                '\\' => try self.writeSlice("\\\\"),
                '\x08' => try self.writeSlice("\\b"),
                '\t' => try self.writeSlice("\\t"),
                '\n' => try self.writeSlice("\\n"),
                '\x0c' => try self.writeSlice("\\f"),
                '\r' => try self.writeSlice("\\r"),
                0...0x07, 0x0b, 0x0e...0x1f => {
                    try self.writeSlice("\\u00");
                    try self.output.append(self.allocator, hex[byte >> 4]);
                    try self.output.append(self.allocator, hex[byte & 0x0f]);
                },
                else => try self.output.append(self.allocator, byte),
            }
        }
        try self.output.append(self.allocator, '"');
    }

    fn writeSlice(self: *Json, value: []const u8) !void {
        try self.output.appendSlice(self.allocator, value);
    }
};

/// Convenience API for callers that only need a serialized slice.
pub fn stringify(allocator: Allocator, document: Document) ![]u8 {
    return Json.stringify(allocator, document);
}

fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return mem.order(u8, lhs, rhs) == .lt;
}

test "JSON export preserves document order, mixed content, and sorted attributes" {
    const Parser = @import("parser.zig").Parser;
    const allocator = testing.allocator;
    var parser: Parser = try .initFromSource(
        allocator,
        "<!--top--><root z=\"last\" a=\"first\">before<b/>after<!--inside--></root><!--bottom-->",
        false,
    );
    defer parser.deinit();
    try parser.parse();

    const sjson = try stringify(allocator, parser.document);
    defer allocator.free(sjson);

    try testing.expectEqualStrings(
        "{\"prologue\":{\"version\":\"1.0\",\"encoding\":\"utf-8\",\"standalone\":false}," ++
            "\"content\":[{\"type\":\"comment\",\"value\":\"top\"}," ++
            "{\"type\":\"element\",\"name\":\"root\",\"attributes\":{\"a\":\"first\",\"z\":\"last\"}," ++
            "\"content\":[{\"type\":\"text\",\"value\":\"before\"}," ++
            "{\"type\":\"element\",\"name\":\"b\",\"attributes\":{},\"content\":[]}," ++
            "{\"type\":\"text\",\"value\":\"after\"}," ++
            "{\"type\":\"comment\",\"value\":\"inside\"}]}," ++
            "{\"type\":\"comment\",\"value\":\"bottom\"}]}",
        sjson,
    );

    var parsed_json = try std.json.parseFromSlice(std.json.Value, allocator, sjson, .{});
    defer parsed_json.deinit();
    try testing.expect(parsed_json.value == .object);
}

test "JSON export escapes control characters and preserves UTF-8" {
    const Parser = @import("parser.zig").Parser;
    const allocator = testing.allocator;
    var parser: Parser = try .initFromSource(allocator, "<root>á\n\t\"\\</root>", false);
    defer parser.deinit();
    try parser.parse();

    const sjson = try stringify(allocator, parser.document);
    defer allocator.free(sjson);

    try testing.expect(std.unicode.utf8ValidateSlice(sjson));
    try testing.expect(mem.endsWith(u8, sjson, "\"value\":\"á\\n\\t\\\"\\\\\"}]}]}"));
}

test "JSON writer is single-use until its output is transferred" {
    const Parser = @import("parser.zig").Parser;
    const allocator = testing.allocator;
    var parser: Parser = try .initFromSource(allocator, "<root/>", false);
    defer parser.deinit();
    try parser.parse();

    var json: Json = .init(allocator);
    defer json.deinit();
    try testing.expectError(error.DocumentNotWritten, json.toOwnedSlice());
    try json.writeDocument(parser.document);
    try testing.expectError(error.DocumentAlreadyWritten, json.writeDocument(parser.document));

    const output = try json.toOwnedSlice();
    defer allocator.free(output);
    try testing.expectEqualStrings(
        "{\"prologue\":{\"version\":\"1.0\",\"encoding\":\"utf-8\",\"standalone\":false}," ++
            "\"content\":[{\"type\":\"element\",\"name\":\"root\",\"attributes\":{},\"content\":[]}]}",
        output,
    );
}

test "JSON export rejects invalid UTF-8 strings" {
    const Parser = @import("parser.zig").Parser;
    const allocator = testing.allocator;
    var parser: Parser = try .initFromSource(allocator, "<root/>", false);
    defer parser.deinit();
    try parser.parse();

    parser.document.prologue.version = &.{0xff};
    try testing.expectError(error.InvalidUtf8, Json.stringify(allocator, parser.document));
}
