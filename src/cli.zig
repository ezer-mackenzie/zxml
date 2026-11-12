const std = @import("std");
const mem = std.mem;

const Allocator = mem.Allocator;
const Io = std.Io;
const Clock = Io.Clock;
const Init = std.process.Init;
const zxml = @import("zxml");
const Parser = zxml.Parser;
const Json = zxml.Json;
const Metrics = @import("report/metrics.zig").Metrics;
const Report = @import("report/report.zig").Report;

const Action = enum {
    parse,
    json,
    report,
};

const Options = struct {
    action: Action = .parse,
    input_path: []const u8 = "docs/example.xml",
    output_path: ?[]const u8 = null,
    debug: bool = false,
    include_content: bool = false,
    has_input_path: bool = false,
    has_action: bool = false,
};

pub const CLI = struct {
    process: Init,

    pub fn init(process: Init) CLI {
        return .{ .process = process };
    }

    pub fn run(self: *CLI) !void {
        const allocator = self.process.gpa;
        const args = try self.process.minimal.args.toSlice(self.process.arena.allocator());
        const options = parseArguments(args[1..]) catch |err| {
            if (err == error.HelpRequested) {
                printUsage();
                return;
            }
            printUsage();
            return err;
        };

        if (options.action == .report and options.include_content and options.output_path == null) {
            std.debug.print(
                "Warning: --include-content writes the full input document to standard output.\n",
                .{},
            );
        }

        const started = Clock.awake.now(self.process.io);
        var parser: Parser = try .init(allocator, &self.process.io, options.input_path, options.debug);
        const parser_ready = Clock.awake.now(self.process.io);
        const parse_started = Clock.awake.now(self.process.io);
        defer parser.deinit();
        try parser.parse();
        const finished = Clock.awake.now(self.process.io);
        const elapsed_ns: u64 = @intCast(started.durationTo(finished).nanoseconds);
        const load_and_tokenize_ns: u64 = @intCast(started.durationTo(parser_ready).nanoseconds);
        const parse_ns: u64 = @intCast(parse_started.durationTo(finished).nanoseconds);
        const statistics = Metrics.collect(&parser);

        switch (options.action) {
            .parse => try self.writeParseSummary(options.input_path, parser.source_size, statistics, elapsed_ns),
            .json => {
                var json: Json = .init(allocator);
                defer json.deinit();
                try json.writeDocument(parser.document);
                const output = try json.toOwnedSlice();
                defer allocator.free(output);
                try self.writeOutput(options.output_path, options.input_path, output);
            },
            .report => {
                const report = Report.init(
                    options.input_path,
                    &parser,
                    elapsed_ns,
                    load_and_tokenize_ns,
                    parse_ns,
                    options.include_content,
                );
                const output = try report.stringify(allocator);
                defer allocator.free(output);
                try self.writeOutput(options.output_path, options.input_path, output);
            },
        }
    }

    fn writeParseSummary(
        self: *CLI,
        path: []const u8,
        input_bytes: usize,
        statistics: Metrics,
        elapsed_ns: u64,
    ) !void {
        const output = try std.fmt.allocPrint(
            self.process.gpa,
            "Parsed {s}: {d} bytes, {d} elements, {d} attributes in {d}.{d:0>3} ms.\n",
            .{
                path,
                input_bytes,
                statistics.element_count,
                statistics.attribute_count,
                elapsed_ns / 1_000_000,
                (elapsed_ns / 1_000) % 1_000,
            },
        );
        defer self.process.gpa.free(output);
        try self.writeOutput(null, path, output);
    }

    fn writeOutput(
        self: *CLI,
        output_path: ?[]const u8,
        input_path: []const u8,
        content: []const u8,
    ) !void {
        if (output_path) |path| {
            try self.ensureOutputDoesNotOverwriteInput(input_path, path);
            try Io.Dir.cwd().writeFile(self.process.io, .{
                .sub_path = path,
                .data = content,
            });
            return;
        }

        var buffer: [4096]u8 = undefined;
        var stdout_writer = Io.File.stdout().writer(self.process.io, &buffer);
        try stdout_writer.interface.writeAll(content);
        if (content.len == 0 or content[content.len - 1] != '\n') {
            try stdout_writer.interface.writeAll("\n");
        }
        try stdout_writer.interface.flush();
    }

    fn ensureOutputDoesNotOverwriteInput(self: *CLI, input_path: []const u8, output_path: []const u8) !void {
        const allocator = self.process.gpa;
        const input_real_path = try Io.Dir.cwd().realPathFileAlloc(
            self.process.io,
            input_path,
            allocator,
        );
        defer allocator.free(input_real_path);

        const output_real_path = Io.Dir.cwd().realPathFileAlloc(
            self.process.io,
            output_path,
            allocator,
        ) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer allocator.free(output_real_path);

        if (mem.eql(u8, input_real_path, output_real_path) or
            std.ascii.eqlIgnoreCase(input_real_path, output_real_path))
        {
            return error.OutputWouldOverwriteInput;
        }
    }
};

fn parseArguments(arguments: []const [:0]const u8) !Options {
    var options: Options = .{};
    var index: usize = 0;
    while (index < arguments.len) : (index += 1) {
        const arg = arguments[index];
        if (mem.eql(u8, arg, "--help") or mem.eql(u8, arg, "-h")) return error.HelpRequested;
        if (mem.eql(u8, arg, "--debug")) {
            options.debug = true;
        } else if (mem.eql(u8, arg, "--include-content")) {
            options.include_content = true;
        } else if (mem.eql(u8, arg, "--output")) {
            index += 1;
            if (index >= arguments.len or options.output_path != null) return error.InvalidArgument;
            options.output_path = arguments[index];
        } else if (isAction(arg)) {
            if (options.has_action or options.has_input_path) return error.InvalidArgument;
            options.action = parseAction(arg).?;
            options.has_action = true;
        } else if (mem.startsWith(u8, arg, "-") or options.has_input_path) {
            return error.InvalidArgument;
        } else {
            options.input_path = arg;
            options.has_input_path = true;
        }
    }

    if (options.include_content and options.action != .report) return error.InvalidArgument;
    if (options.output_path != null and options.action == .parse) return error.InvalidArgument;
    return options;
}

fn isAction(value: []const u8) bool {
    return mem.eql(u8, value, "parse") or mem.eql(u8, value, "json") or mem.eql(u8, value, "report");
}

fn parseAction(value: []const u8) ?Action {
    if (mem.eql(u8, value, "parse")) return .parse;
    if (mem.eql(u8, value, "json")) return .json;
    if (mem.eql(u8, value, "report")) return .report;
    return null;
}

fn printUsage() void {
    std.debug.print(
        "Usage: zxml [parse|json|report] [file.xml] [--debug] [--output path] [--include-content]\n" ++
            "  parse    Validate the XML and print a concise summary (default).\n" ++
            "  json     Write the parsed document tree as JSON.\n" ++
            "  report   Write detailed parsing metrics as JSON.\n" ++
            "  --include-content  Include the full normalized source in a report.\n",
        .{},
    );
}

test "CLI parses action, path, output, and report-content options" {
    const options = try parseArguments(&.{
        "report",
        "input.xml",
        "--output",
        "report.json",
        "--include-content",
    });
    try std.testing.expectEqual(Action.report, options.action);
    try std.testing.expectEqualStrings("input.xml", options.input_path);
    try std.testing.expectEqualStrings("report.json", options.output_path.?);
    try std.testing.expect(options.include_content);
}

test "CLI defaults to parse and rejects invalid option combinations" {
    const defaults = try parseArguments(&.{});
    try std.testing.expectEqual(Action.parse, defaults.action);
    try std.testing.expectEqualStrings("docs/example.xml", defaults.input_path);

    try std.testing.expectError(error.InvalidArgument, parseArguments(&.{"--unknown"}));
    try std.testing.expectError(error.InvalidArgument, parseArguments(&.{ "first.xml", "second.xml" }));
    try std.testing.expectError(error.InvalidArgument, parseArguments(&.{ "parse", "json" }));
    try std.testing.expectError(error.InvalidArgument, parseArguments(&.{ "input.xml", "json" }));
    try std.testing.expectError(error.InvalidArgument, parseArguments(&.{"--include-content"}));
    try std.testing.expectError(error.InvalidArgument, parseArguments(&.{ "--output", "out.json" }));
}
