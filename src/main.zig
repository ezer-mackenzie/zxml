const std = @import("std");
const Io = std.Io;

const core = @import("core.zig");

const Reader = @import("reader.zig").Reader;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Parser = @import("parser.zig").Parser;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const xml = try Reader.read(allocator, &io, "./docs/example.xml");
    defer allocator.free(xml);

    var parser = Parser.init(xml);
    defer parser.deinit(allocator);

    try parser.parse(allocator);
}
