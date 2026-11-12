const std = @import("std");
const CLI = @import("cli.zig").CLI;

pub fn main(init: std.process.Init) !void {
    var cli: CLI = .init(init);
    try cli.run();
}
