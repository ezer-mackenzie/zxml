const std = @import("std");

pub const ZXMLErrors = error{
    UnsupportedFile,
    NotAnXmlDocument,
};

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
    data: ?[]const u8 = null,
    children: std.ArrayList(XMLNode),

    pub fn deinit(self: *XMLNode, allocator: std.mem.Allocator) void {
        for (self.children.items) |*child| child.deinit(allocator);

        self.children.deinit(allocator);
        self.attributes.deinit();
    }
};

pub const XMLNodeMetadata = struct {
    tag: []const u8,
    attributes: std.StringHashMap([]const u8),
};
