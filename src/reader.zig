const std = @import("std");

const mem = std.mem;
const testing = std.testing;

const Io = std.Io;
const Dir = std.Io.Dir;
const Writer = Io.Writer;
const Allocator = mem.Allocator;

const ZXMLErrors = @import("core.zig").ZXMLErrors;

pub const Reader = struct {
    const MAX_FILE_SIZE = 10 * 1024 * 1024;
    allocator: Allocator,
    content: []const u8,

    pub fn init(allocator: Allocator, io: *const Io, path: []const u8) !Reader {
        const content = try Dir.readFileAlloc(Dir.cwd(), io.*, path, allocator, Io.Limit.limited64(MAX_FILE_SIZE));

        return .{
            .allocator = allocator,
            .content = content,
        };
    }

    /// Checks for a plausible document start; the parser validates XML structure.
    pub fn read(self: *Reader) ZXMLErrors![]const u8 {
        var index: usize = 0;
        while (index < self.content.len and mem.indexOfScalar(u8, " \t\n\r", self.content[index]) != null) : (index += 1) {}

        if (index < self.content.len and self.content[index] == '<') return self.content;

        return error.NotAnXmlDocument;
    }

    pub fn takeContent(self: *Reader) []const u8 {
        const content = self.content;
        self.content = &.{};
        return content;
    }

    pub fn deinit(self: *Reader) void {
        self.allocator.free(self.content);
        self.content = &.{};
    }

    pub fn format(self: Reader, writer: *Writer) Writer.Error!void {
        try writer.print("Reader {{ content_len: {d} }}", .{self.content.len});
    }
};

test "reader accepts markup after leading XML whitespace" {
    const content = try testing.allocator.dupe(u8, " \t\n<root/>");
    var reader = Reader{
        .allocator = testing.allocator,
        .content = content,
    };
    defer reader.deinit();

    try testing.expectEqualStrings(reader.content, try reader.read());
}

test "reader rejects input without an initial markup character" {
    const content = try testing.allocator.dupe(u8, "not XML");
    var reader = Reader{
        .allocator = testing.allocator,
        .content = content,
    };
    defer reader.deinit();

    try testing.expectError(error.NotAnXmlDocument, reader.read());
}

test "reader transfers ownership of its content" {
    const content = try testing.allocator.dupe(u8, "<root/>");
    var reader = Reader{
        .allocator = testing.allocator,
        .content = content,
    };
    const transferred = reader.takeContent();
    defer testing.allocator.free(transferred);
    defer reader.deinit();

    try testing.expectEqualStrings("<root/>", transferred);
}
