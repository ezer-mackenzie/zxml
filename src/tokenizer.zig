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
};
