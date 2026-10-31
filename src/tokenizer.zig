const std = @import("std");

const core = @import("core.zig");

pub const Tokenizer = struct {
    source: []const u8,
    index: usize,

    pub fn init(source: []const u8) Tokenizer {
        return .{
            .source = source,
            .index = 0,
        };
    }

    pub fn next(self: *Tokenizer) ?core.Token {
        if (self.index >= self.source.len) return null;

        const start = self.index;
        const current_char = self.source[start];

        if (current_char == '<') {
            self.index += 1;
            const tag_start = self.index;

            while (self.index < self.source.len and self.source[self.index] != '>') {
                self.index += 1;
            }

            const tag_content = self.source[tag_start..self.index];

            if (self.index < self.source.len) {
                self.index += 1;
            }

            const is_end = tag_content.len > 0 and tag_content[0] == '/';

            return core.Token{
                .type = if (is_end) .EndTag else .StartTag,
                .text = tag_content,
            };
        } else {
            while (self.index < self.source.len and self.source[self.index] != '<') {
                self.index += 1;
            }

            return core.Token{
                .type = .Text,
                .text = self.source[start..self.index],
            };
        }
    }

    pub fn parseTagAndAttributes(allocator: std.mem.Allocator, raw_text: []const u8) !struct { tag: []const u8, attributes: std.StringHashMap([]const u8) } {
        var attributes: std.StringHashMap([]const u8) = .init(allocator);

        var iter = std.mem.tokenizeAny(u8, raw_text, "\t\n\r");
        const tag_name = iter.next() orelse raw_text;

        while (iter.next()) |token| {
            if (std.mem.indexOfScalar(u8, token, '=')) |eq_idx| {
                const key = token[0..eq_idx];
                var val = token[eq_idx + 1 ..];

                if (val.len >= 2 and ((val[0] == '"' and val[val.len - 1] == '"') or (val[0] == '\'' and val[val.len - 1] == '\''))) {
                    val = val[1 .. val.len - 1];
                }

                try attributes.put(key, val);
            }
        }

        var it = attributes.iterator();
        while (it.next()) |entry| {
            // entry.key_ptr.* y entry.value_ptr.* obtienen los valores desreferenciados
            std.debug.print("  {s} => {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        return .{ .tag = tag_name, .attributes = attributes };
    }
};
