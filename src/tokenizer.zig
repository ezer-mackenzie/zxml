const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const Io = std.Io;
const Writer = Io.Writer;

const core = @import("core.zig");

const Token = core.Token;
const TokenType = core.TokenType;

const Reader = @import("reader.zig").Reader;

pub const Tokenizer = struct {
    index: usize,
    source: []const u8,

    pub fn init(allocator: mem.Allocator, io: *const Io, path: []const u8) !Tokenizer {
        var reader: Reader = try .init(allocator, io, path);
        defer reader.deinit();

        _ = try reader.read();
        return initFromSource(reader.takeContent());
    }

    /// Uses the provided buffer without copying it; the buffer must remain alive while tokenizing.
    pub fn initFromSource(source: []const u8) Tokenizer {
        return .{
            .index = 0,
            .source = source,
        };
    }

    pub fn next(self: *Tokenizer) !?Token {
        if (self.index >= self.source.len) return null;

        const start = self.index;
        const current_char = self.source[start];

        if (current_char == '<') {
            self.index += 1;
            const tag_start = self.index;

            // Handle comments before scanning a regular tag.
            if (self.index + 2 < self.source.len and std.mem.eql(u8, self.source[self.index .. self.index + 3], "!--")) {
                self.index += 3; // Skip '!--'.
                const comment_start = self.index;

                while (self.index + 2 < self.source.len) {
                    if (mem.eql(u8, self.source[self.index .. self.index + 3], "-->")) break;
                    if (self.index + 1 < self.source.len and
                        mem.eql(u8, self.source[self.index .. self.index + 2], "--"))
                    {
                        return error.InvalidComment;
                    }
                    self.index += 1;
                }

                const comment_content = self.source[comment_start..self.index];

                if (self.index + 2 >= self.source.len) return error.UnterminatedComment;
                self.index += 3; // Skip '-->'.

                return .{ .type = .Comment, .content = comment_content, .self_closing = false };
            }

            // A quoted attribute can contain '>'; only an unquoted '>' ends the tag.
            var quote: ?u8 = null;
            while (self.index < self.source.len) : (self.index += 1) {
                const char = self.source[self.index];
                if (quote) |delimiter| {
                    if (char == delimiter) quote = null;
                } else if (char == '"' or char == '\'') {
                    quote = char;
                } else if (char == '>') {
                    break;
                }
            }

            if (self.index == self.source.len) {
                if (quote != null) return error.UnterminatedAttributeValue;
                return error.UnterminatedTag;
            }

            const raw_content = self.source[tag_start..self.index];

            if (self.index < self.source.len) self.index += 1; // Skip '>'.
            if (raw_content.len == 0 or mem.indexOfScalar(u8, " \t\n\r", raw_content[0]) != null) {
                return error.InvalidTagSyntax;
            }

            const tag_content = mem.trim(u8, raw_content, " \t\n\r");
            const is_end = mem.startsWith(u8, tag_content, "/");
            const is_self_closing = !is_end and mem.endsWith(u8, tag_content, "/");

            if (is_end) {
                if (tag_content.len == 1 or mem.indexOfScalar(u8, " \t\n\r", tag_content[1]) != null) {
                    return error.InvalidTagSyntax;
                }
                // Remove surrounding whitespace after the closing slash.
                const end_content = mem.trim(u8, tag_content[1..], " \t\n\r");

                return .{
                    .type = .EndTag,
                    .content = end_content,
                    .self_closing = is_self_closing,
                };
            }

            if (is_self_closing and raw_content[raw_content.len - 1] != '/') {
                return error.InvalidTagSyntax;
            }

            // Remove the trailing slash from self-closing tag content.
            return .{
                .type = if (is_self_closing) .SelfClosingTag else .StartTag,
                .content = if (is_self_closing)
                    mem.trimEnd(u8, tag_content[0 .. tag_content.len - 1], " \t\n\r")
                else
                    tag_content,
                .self_closing = is_self_closing,
            };
        }

        while (self.index < self.source.len and self.source[self.index] != '<') self.index += 1;

        return .{
            .type = .Text,
            .content = self.source[start..self.index],
        };
    }

    pub fn format(self: Tokenizer, writer: *Writer) Writer!void {
        _ = self;
        try writer.print("Tokenizer {{}}", .{});
    }
};

test "tokenizer marks self-closing tags" {
    var tokenizer = Tokenizer.initFromSource("<item />");
    const token = (try tokenizer.next()).?;

    try testing.expectEqual(TokenType.SelfClosingTag, token.type);
    try testing.expect(token.self_closing);
    try testing.expectEqualStrings("item", token.content);
    try testing.expect((try tokenizer.next()) == null);
}

test "tokenizer removes the closing slash from end tag content" {
    var tokenizer = Tokenizer.initFromSource("</item>");
    const token = (try tokenizer.next()).?;

    try testing.expectEqual(TokenType.EndTag, token.type);
    try testing.expectEqualStrings("item", token.content);
}

test "tokenizer does not end a tag at greater-than inside a quoted value" {
    var tokenizer = Tokenizer.initFromSource("<item value=\"a > b\"/>");
    const token = (try tokenizer.next()).?;

    try testing.expectEqual(TokenType.SelfClosingTag, token.type);
    try testing.expectEqualStrings("item value=\"a > b\"", token.content);
    try testing.expect((try tokenizer.next()) == null);
}

test "tokenizer rejects an unterminated tag" {
    var tokenizer = Tokenizer.initFromSource("<root");
    try testing.expectError(error.UnterminatedTag, tokenizer.next());
}

test "tokenizer rejects an unterminated quoted attribute value" {
    var tokenizer = Tokenizer.initFromSource("<item value=\"unfinished>");
    try testing.expectError(error.UnterminatedAttributeValue, tokenizer.next());
}

test "tokenizer rejects unterminated and malformed comments" {
    var unterminated = Tokenizer.initFromSource("<!--unfinished");
    try testing.expectError(error.UnterminatedComment, unterminated.next());

    var malformed = Tokenizer.initFromSource("<!--not--valid-->");
    try testing.expectError(error.InvalidComment, malformed.next());
}

test "tokenizer rejects whitespace in invalid tag-name positions" {
    var before_name = Tokenizer.initFromSource("< root/>");
    try testing.expectError(error.InvalidTagSyntax, before_name.next());

    var after_close_slash = Tokenizer.initFromSource("</ root>");
    try testing.expectError(error.InvalidTagSyntax, after_close_slash.next());

    var after_empty_slash = Tokenizer.initFromSource("<root/ >");
    try testing.expectError(error.InvalidTagSyntax, after_empty_slash.next());
}
