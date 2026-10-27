const std = @import("std");

pub const TokenType = enum {
    StartTag,
    EndTag,
    SelfClosingTag,
    Text,
    Attribute,
    Comment,
};

pub const Token = struct {
    type: TokenType,
    text: []const u8,
};

pub const XMLNode = struct {
    tag: []const u8,
    attributes: std.StringHashMap([]const u8),
    text: ?[]const u8 = null,
    children: std.ArrayList(*XMLNode),

    pub fn deinit(self: *XMLNode, allocator: std.mem.Allocator) void {
        for (self.children.items) |child| {
            child.deinit(allocator);
            allocator.destroy(child);
        }

        self.children.deinit();
        self.attributes.deinit();
    }
};

