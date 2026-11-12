const std = @import("std");

const Allocator = std.mem.Allocator;
const Parser = @import("zxml").Parser;
const Metrics = @import("metrics.zig").Metrics;

pub const Report = struct {
    command: []const u8 = "report",
    file: []const u8,
    elapsed_ns: u64,
    elapsed_ms: f64,
    load_and_tokenize_ns: u64,
    parse_ns: u64,
    input_bytes: usize,
    parsed_bytes: usize,
    token_count: usize,
    source_lines: usize,
    root_element: ?[]const u8,
    element_count: usize,
    maximum_depth: usize,
    attribute_count: usize,
    text_node_count: usize,
    text_bytes: usize,
    comment_count: usize,
    comment_bytes: usize,
    content: ?[]const u8,

    pub fn init(
        file: []const u8,
        parser: *const Parser,
        elapsed_ns: u64,
        load_and_tokenize_ns: u64,
        parse_ns: u64,
        include_content: bool,
    ) Report {
        const metrics = Metrics.collect(parser);
        return .{
            .file = file,
            .elapsed_ns = elapsed_ns,
            .elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0,
            .load_and_tokenize_ns = load_and_tokenize_ns,
            .parse_ns = parse_ns,
            .input_bytes = parser.source_size,
            .parsed_bytes = parser.source.len,
            .token_count = parser.tokens.items.len,
            .source_lines = countLines(parser.source),
            .root_element = if (parser.document.root) |root| root.metadata.tag else null,
            .element_count = metrics.element_count,
            .maximum_depth = metrics.maximum_depth,
            .attribute_count = metrics.attribute_count,
            .text_node_count = metrics.text_node_count,
            .text_bytes = metrics.text_bytes,
            .comment_count = metrics.comment_count,
            .comment_bytes = metrics.comment_bytes,
            .content = if (include_content) parser.source else null,
        };
    }

    pub fn stringify(self: Report, allocator: Allocator) ![]u8 {
        return std.json.Stringify.valueAlloc(allocator, self, .{});
    }
};

fn countLines(source: []const u8) usize {
    var lines: usize = 1;
    for (source) |byte| {
        if (byte == '\n') lines += 1;
    }
    return lines;
}

test "report serializes detailed metrics and optional normalized content" {
    const allocator = std.testing.allocator;
    var parser: Parser = try .initFromSource(
        allocator,
        "<root a=\"1\">x&amp;y<child><!--c--></child></root>",
        false,
    );
    defer parser.deinit();
    try parser.parse();

    const report = Report.init("input.xml", &parser, 1_234_567, 1_000_000, 234_567, true);
    try std.testing.expectEqual(report.elapsed_ns, report.load_and_tokenize_ns + report.parse_ns);
    try std.testing.expectEqual(parser.source_size, report.input_bytes);
    try std.testing.expectEqualStrings(parser.source, report.content.?);
    try std.testing.expectEqualStrings("root", report.root_element.?);
    try std.testing.expectEqual(@as(usize, parser.tokens.items.len), report.token_count);

    const json = try report.stringify(allocator);
    defer allocator.free(json);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
}

test "report omits source content unless explicitly requested" {
    const allocator = std.testing.allocator;
    var parser: Parser = try .initFromSource(allocator, "<root/>", false);
    defer parser.deinit();
    try parser.parse();

    const report = Report.init("input.xml", &parser, 0, 0, 0, false);
    try std.testing.expect(report.content == null);
}
