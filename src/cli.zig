const std = @import("std");

pub const Cli = struct {
    pub fn run(init: std.process.Init) void {
        var args = try init.minimal.args.iterateAllocator(init.gpa);
        defer args.deinit();

        _ = args.skip();

        const command = args.next() orelse return help();

        if (std.mem.eql(u8, command, "parse")) {
            std.debug.print("parsing...", .{});
        }
    }

    pub fn help() void {
        // WIP      |
        return;
    }
};
