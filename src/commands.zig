const std = @import("std");

const core = @import("core.zig");

const Reader = @import("reader.zig").Reader;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Parser = @import("parser.zig").Parser;

pub const Commands = struct {
    pub fn parse(init: std.process.Init) void {
        const allocator = init.gpa;
        const io = init.io;

        // in future versions, change the hardcoded path
        const xml = try Reader.read(allocator, &io, "./docs/example.xml");
        defer allocator.free(xml);

        var tokenizer = Tokenizer.init(xml);
        var tokens: std.ArrayList(core.Token) = .empty;
        defer tokens.deinit(allocator);

        while (tokenizer.next()) |token| {
            try tokens.append(allocator, token);
            std.debug.print("token obtenido: {s}\n", .{token.text});
        }

        var parser = Parser.init(tokens.items);
        parser.parse();
    }
};
