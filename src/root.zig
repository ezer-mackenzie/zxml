//! XML parser for the documented subset, with a stable public API in the 1.x series.

const core = @import("core.zig");

pub const Parser = @import("parser.zig").Parser;
pub const json = @import("json.zig");
pub const Json = json.Json;
pub const Document = core.Document;
pub const DocumentContent = core.DocumentContent;
pub const Node = core.Node;
pub const NodeContent = core.NodeContent;
pub const Metadata = core.Metadata;
pub const Prologue = core.Prologue;
pub const Token = core.Token;
pub const TokenType = core.TokenType;

test "public API parses a document" {
    const allocator = @import("std").testing.allocator;
    var parser = try Parser.initFromSource(allocator, "<root/>", false);
    defer parser.deinit();

    try parser.parse();
    try @import("std").testing.expect(parser.document.root != null);
}
