const zxml = @import("zxml");
const Parser = zxml.Parser;
const Node = zxml.Node;

pub const Metrics = struct {
    element_count: usize = 0,
    maximum_depth: usize = 0,
    attribute_count: usize = 0,
    text_node_count: usize = 0,
    text_bytes: usize = 0,
    comment_count: usize = 0,
    comment_bytes: usize = 0,

    pub fn collect(parser: *const Parser) Metrics {
        var metrics: Metrics = .{};
        metrics.comment_count = parser.document.comments.items.len;
        for (parser.document.comments.items) |comment| {
            metrics.comment_bytes += comment.len;
        }
        if (parser.document.root) |root| metrics.visitNode(root, 1);
        return metrics;
    }

    fn visitNode(self: *Metrics, node: Node, depth: usize) void {
        self.element_count += 1;
        self.maximum_depth = @max(self.maximum_depth, depth);
        self.attribute_count += node.metadata.attributes.count();

        for (node.content.items) |part| {
            switch (part) {
                .text => |text| {
                    self.text_node_count += 1;
                    self.text_bytes += text.len;
                },
                .comment => |comment| {
                    self.comment_count += 1;
                    self.comment_bytes += comment.len;
                },
                .element => |child| self.visitNode(child, depth + 1),
            }
        }
    }
};

test "metrics count nested elements and decoded content" {
    const allocator = @import("std").testing.allocator;
    var parser: Parser = try .initFromSource(
        allocator,
        "<root a=\"1\">x&amp;y<child><!--c--></child></root>",
        false,
    );
    defer parser.deinit();
    try parser.parse();

    const metrics = Metrics.collect(&parser);
    try @import("std").testing.expectEqual(@as(usize, 2), metrics.element_count);
    try @import("std").testing.expectEqual(@as(usize, 2), metrics.maximum_depth);
    try @import("std").testing.expectEqual(@as(usize, 1), metrics.attribute_count);
    try @import("std").testing.expectEqual(@as(usize, 1), metrics.text_node_count);
    try @import("std").testing.expectEqual(@as(usize, 3), metrics.text_bytes);
    try @import("std").testing.expectEqual(@as(usize, 1), metrics.comment_count);
    try @import("std").testing.expectEqual(@as(usize, 1), metrics.comment_bytes);
}
