const std = @import("std");

const core = @import("core.zig");
const Tokenizer = @import("tokenizer.zig").Tokenizer;

pub const Parser = struct {
    index: usize,
    tokenizer: Tokenizer,
    tokens: std.ArrayList(core.Token),
    nodes: std.ArrayList(core.XMLNode),

    pub fn init(source: []const u8) Parser {
        return .{
            .index = 0,
            .tokenizer = Tokenizer.init(source),
            .tokens = .empty,
            .nodes = .empty,
        };
    }

    pub fn deinit(self: *Parser, allocator: std.mem.Allocator) void {
        for (self.nodes.items) |*node| node.deinit(allocator);

        self.nodes.deinit(allocator);
        self.tokens.deinit(allocator);
    }

    fn peek(self: *const Parser) ?core.Token {
        if (self.index >= self.tokens.items.len) return null;
        return self.tokens.items[self.index];
    }

    fn advance(self: *Parser) ?core.Token {
        const token = self.peek();
        if (token != null) {
            self.index += 1;
        }
        return token;
    }

    pub fn parse(self: *Parser, allocator: std.mem.Allocator) !void {
        while (self.tokenizer.next()) |token| try self.tokens.append(allocator, token);

        std.debug.print("Tokens totales obtenidos: {d}\n", .{self.tokens.items.len});

        const root = core.XMLNode{
            .tag = "root",
            .data = null,
            .children = .empty,
            .attributes = .init(allocator),
        };
        try self.nodes.append(allocator, root);

        var stack: std.ArrayList(*core.XMLNode) = .empty;
        defer stack.deinit(allocator);

        try stack.append(allocator, &self.nodes.items[0]);

        while (self.peek()) |token| {
            const current_parent = stack.getLast();

            switch (token.type) {
                .StartTag => {
                    const parsed = try Tokenizer.parseTagAndAttributes(allocator, token.text);

                    std.debug.print("Abriendo tag limpio: {s} (Atributos: {d})\n", .{ parsed.tag, parsed.attributes.count() });

                    const new_node = core.XMLNode{
                        .tag = parsed.tag,
                        .data = null,
                        .children = .empty,
                        .attributes = parsed.attributes,
                    };

                    try current_parent.children.append(allocator, new_node);

                    const inserted_child = &current_parent.children.items[current_parent.children.items.len - 1];
                    try stack.append(allocator, inserted_child);

                    _ = self.advance();
                },
                .EndTag => {
                    std.debug.print("Cerrando tag: {s}\n", .{token.text});

                    if (stack.items.len > 1) _ = stack.pop();

                    _ = self.advance();
                },
                .SelfClosingTag => {},
                .Text => {
                    if (token.text.len > 0) {
                        std.debug.print("Asignando texto a '{s}': {s}\n", .{ current_parent.tag, token.text });

                        current_parent.data = token.text;
                    }
                    _ = self.advance();
                },
                .Attribute => {},
                .Comment => {},
                else => _ = self.advance(),
            }
        }
    }
};
