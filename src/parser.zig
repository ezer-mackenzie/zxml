const std = @import("std");

const core = @import("core.zig");

pub const Parser = struct {
    tokens: []const core.Token,
    index: usize,

    pub fn init(tokens: []const core.Token) Parser {
        return .{ .tokens = tokens, .index = 0 };
    }

    fn peek(self: *const Parser) ?core.Token {
        if (self.index >= self.tokens.len) return null;
        return self.tokens[self.index];
    }

    fn advance(self: *Parser) ?core.Token {
        const token = self.peek();
        
        if (token != null) {
            self.index += 1;
        }

        return token;
    }

    pub fn parse(self: *Parser) void {
        while (self.peek()) |token| {
            switch (token.type) {
                .StartTag => {
                    std.debug.print("Parser procesando apertura: {s}\n", .{token.text});
                    _ = self.advance();
                },
                .EndTag => {
                    std.debug.print("Parser procesando cierre: {s}\n", .{token.text});
                    _ = self.advance();
                },
                .Text => {
                    if (token.text.len > 0) {
                        std.debug.print("Parser procesando texto: {s}\n", .{token.text});
                    }
                    _ = self.advance();
                },
                else => {
                    // Manejar otros tokens si los hay
                    _ = self.advance();
                },
            }
        }
    }
};
