const std = @import("std");

const core = @import("core.zig");

pub const Reader = struct {
    const MAX_FILE_SIZE = 10 * 1024 * 1024;

    pub fn read(allocator: std.mem.Allocator, io: *const std.Io, path: []const u8) ![]const u8 {
        const content = try std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), io.*, path, allocator, std.Io.Limit.limited64(MAX_FILE_SIZE));
        errdefer allocator.free(content);

        const header_len = @min(content.len, 16);
        const header = content[0..header_len];

        if (std.mem.startsWith(u8, header, "<?xml") or
            std.mem.startsWith(u8, header, "<"))
        {
            return content;
        }

        return core.ZXMLErrors.NotAnXmlDocument;
    }
};
