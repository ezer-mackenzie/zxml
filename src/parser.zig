const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const heap = std.heap;

const Io = std.Io;
const Writer = std.Io.Writer;
const Allocator = mem.Allocator;
const ArenaAllocator = heap.ArenaAllocator;

const ArrayList = std.ArrayList;

const core = @import("core.zig");

const Node = core.Node;
const Token = core.Token;
const Metadata = core.Metadata;
const Document = core.Document;
const validateXmlName = core.Metadata.validateXmlName;

const Tokenizer = @import("tokenizer.zig").Tokenizer;
const XmlDecoder = @import("decoder.zig").XmlDecoder;
const XmlValidator = @import("validator.zig").XmlValidator;

pub const Parser = struct {
    pub const MAX_INPUT_SIZE = 10 * 1024 * 1024;
    pub const MAX_NESTING_DEPTH = 256;
    pub const MAX_NODE_COUNT = 16_384;

    allocator: Allocator,
    index: usize,
    document: Document,
    source: []const u8,
    source_size: usize,
    decoded_content: ArenaAllocator,
    node_count: usize = 0,
    debug: bool = false,
    tokens: ArrayList(Token) = .empty,

    pub fn init(allocator: Allocator, io: *const Io, path: []const u8, debug: bool) !Parser {
        const tokenizer: Tokenizer = try .init(allocator, io, path);
        return initWithOwnedSource(allocator, tokenizer.source, debug);
    }

    /// Copies the source so the caller may release its buffer after initialization.
    pub fn initFromSource(allocator: Allocator, source: []const u8, debug: bool) !Parser {
        if (source.len > MAX_INPUT_SIZE) return error.InputTooLarge;
        const owned_source = try allocator.dupe(u8, source);
        return initWithOwnedSource(allocator, owned_source, debug);
    }

    fn initWithOwnedSource(allocator: Allocator, source: []const u8, debug: bool) !Parser {
        var owned_source = source;
        const source_size = owned_source.len;
        errdefer allocator.free(owned_source);
        if (mem.indexOfScalar(u8, owned_source, '\r') != null) {
            const normalized = try XmlDecoder.normalizeLineEndings(allocator, owned_source);
            allocator.free(owned_source);
            owned_source = normalized;
        }
        try XmlValidator.validateXmlCharacters(owned_source);

        var tokens: ArrayList(Token) = .empty;
        errdefer tokens.deinit(allocator);

        if (debug) std.debug.print("[parser] Starting document tokenization.\n", .{});

        var tokenizer = Tokenizer.initFromSource(owned_source);
        while (try tokenizer.next()) |token| {
            try tokens.append(allocator, token);
            if (debug)
                std.debug.print(
                    "[tokenizer] Token #{d}: type={s}, self_closing={}, content=\"{s}\"\n",
                    .{
                        tokens.items.len,
                        @tagName(token.type),
                        token.self_closing,
                        token.content,
                    },
                );
        }

        if (debug) {
            std.debug.print("[parser] Tokenization complete: {d} tokens.\n", .{tokens.items.len});
            std.debug.print("[parser] Initializing document state.\n", .{});
        }

        return .{
            .allocator = allocator,
            .index = 0,
            .document = .init(.init(
                null,
                null,
                null,
            ), null),
            .tokens = tokens,
            .source = tokenizer.source,
            .source_size = source_size,
            .decoded_content = .init(allocator),
            .debug = debug,
        };
    }

    pub fn deinit(self: *Parser) void {
        const allocator = self.allocator;
        self.document.deinit(allocator);
        self.tokens.deinit(allocator);
        allocator.free(self.source);
        self.decoded_content.deinit();
    }

    fn peek(self: *const Parser) ?Token {
        if (self.index >= self.tokens.items.len) return null;
        return self.tokens.items[self.index];
    }

    fn advance(self: *Parser) ?Token {
        const token = self.peek();
        if (token != null) {
            self.index += 1;
        }
        return token;
    }

    pub fn parse(self: *Parser) !void {
        if (self.index != 0 or self.document.root != null) return error.AlreadyParsed;

        const allocator = self.allocator;
        var stack: ArrayList(*Node) = .empty;
        defer stack.deinit(allocator);

        // The stack tracks open elements; the document root is an actual XML element.
        errdefer {
            if (self.document.root) |*root| root.deinit(allocator);
            self.document.root = null;
            self.index = 0;
            self.node_count = 0;
            self.document.comments.items.len = 0;
            self.document.content.items.len = 0;
            self.document.prologue = .init(null, null, null);
            self.decoded_content.deinit();
            self.decoded_content = .init(allocator);
        }

        if (self.debug) std.debug.print("[parser] Initialized the open-element stack.\n", .{});

        while (self.peek()) |token| {
            switch (token.type) {
                .StartTag => {
                    if (mem.startsWith(u8, token.content, "?")) {
                        try self.parseXmlDeclaration(token);
                        _ = self.advance();
                    } else {
                        try self.addElement(&stack, token, false);

                        _ = self.advance();
                    }
                },
                .EndTag => {
                    if (stack.items.len == 0) return error.UnexpectedClosingTag;
                    try validateXmlName(token.content);

                    const open_node = stack.getLast();
                    if (!mem.eql(u8, open_node.metadata.tag, token.content)) {
                        return error.MismatchedClosingTag;
                    }

                    _ = stack.pop();
                    _ = self.advance();
                },
                .SelfClosingTag => {
                    try self.addElement(&stack, token, true);
                    _ = self.advance();
                },
                .Text => {
                    if (mem.indexOf(u8, token.content, "]]>") != null) {
                        return error.ForbiddenCDataTerminator;
                    }
                    const trimmed_text = mem.trim(u8, token.content, " \t\n\r");
                    if (stack.items.len == 0) {
                        if (trimmed_text.len > 0) return error.UnexpectedText;
                    } else {
                        const decoded_text = try XmlDecoder.decodeEntities(self.decoded_content.allocator(), token.content, false);
                        try stack.getLast().content.append(allocator, .{ .text = decoded_text });
                    }
                    _ = self.advance();
                },
                .Comment => {
                    if (stack.items.len == 0) {
                        try self.document.comments.append(allocator, token.content);
                        try self.document.content.append(allocator, .{ .comment = token.content });
                    } else {
                        try stack.getLast().content.append(allocator, .{ .comment = token.content });
                    }
                    _ = self.advance();
                },
            }
        }

        if (stack.items.len > 0) return error.UnclosedTag;
        if (self.document.root == null) return error.MissingRootElement;

        if (self.debug) std.debug.print("[parser] Parsing completed successfully.\n", .{});
    }

    fn parseXmlDeclaration(self: *Parser, token: Token) !void {
        const allocator = self.allocator;
        if (!mem.endsWith(u8, token.content, "?")) return error.MalformedXmlDeclaration;
        if (self.index != 0) return error.MisplacedXmlDeclaration;
        if (!mem.startsWith(u8, token.content, "?xml")) return error.UnsupportedProcessingInstruction;
        const declaration_end = token.content.len - 1;
        if (declaration_end > 4 and mem.indexOfScalar(u8, " \t\n\r", token.content[4]) == null) {
            return error.UnsupportedProcessingInstruction;
        }

        const declaration = token.content[1..declaration_end];
        const attributes_start = mem.trimStart(u8, token.content[4..declaration_end], " \t\n\r");
        if (attributes_start.len == 0) return error.MissingXmlVersion;
        const first_attribute_end = mem.indexOfAny(u8, attributes_start, " \t\n\r=") orelse attributes_start.len;
        if (!mem.eql(u8, attributes_start[0..first_attribute_end], "version")) {
            return error.XmlVersionMustBeFirst;
        }

        var metadata: Metadata = try .init(allocator, declaration);
        defer metadata.deinit();
        try XmlValidator.validateXmlDeclarationOrder(attributes_start);

        const version = metadata.attributes.get("version") orelse return error.MissingXmlVersion;
        if (!mem.eql(u8, version, "1.0")) return error.UnsupportedXmlVersion;
        if (metadata.attributes.count() > 3) return error.InvalidXmlDeclarationAttribute;

        var attributes = metadata.attributes.iterator();
        while (attributes.next()) |entry| {
            if (!mem.eql(u8, entry.key_ptr.*, "version") and
                !mem.eql(u8, entry.key_ptr.*, "encoding") and
                !mem.eql(u8, entry.key_ptr.*, "standalone"))
            {
                return error.InvalidXmlDeclarationAttribute;
            }
        }

        if (metadata.attributes.get("encoding")) |encoding| {
            if (!std.ascii.eqlIgnoreCase(encoding, "UTF-8")) return error.UnsupportedEncoding;
            self.document.prologue.encoding = encoding;
        }

        if (metadata.attributes.get("standalone")) |standalone| {
            if (mem.eql(u8, standalone, "yes")) {
                self.document.prologue.standalone = true;
            } else if (mem.eql(u8, standalone, "no")) {
                self.document.prologue.standalone = false;
            } else {
                return error.InvalidStandaloneValue;
            }
        }

        self.document.prologue.version = version;
    }

    fn addElement(
        self: *Parser,
        stack: *ArrayList(*Node),
        token: Token,
        self_closing: bool,
    ) !void {
        const allocator = self.allocator;
        if (self.node_count >= MAX_NODE_COUNT or stack.items.len >= MAX_NESTING_DEPTH) {
            return error.ResourceLimitExceeded;
        }
        if (stack.items.len == 0 and self.document.root != null) {
            return error.MultipleRootElements;
        }

        var metadata: Metadata = try .init(allocator, token.content);
        var metadata_transferred = false;
        errdefer {
            if (!metadata_transferred) metadata.deinit();
        }
        var attributes = metadata.attributes.iterator();
        while (attributes.next()) |entry| {
            entry.value_ptr.* = try XmlDecoder.decodeEntities(self.decoded_content.allocator(), entry.value_ptr.*, true);
        }

        const node: Node = .init(metadata);

        if (stack.items.len == 0) {
            self.document.root = node;
            metadata_transferred = true;
            try self.document.content.append(allocator, .root);

            if (!self_closing) try stack.append(allocator, &self.document.root.?);
            self.node_count += 1;
            return;
        }

        const parent = stack.getLast();
        try parent.content.append(allocator, .{ .element = node });
        // Once inserted, the tree owns the node's allocated attribute map.
        metadata_transferred = true;

        if (!self_closing) {
            const child_part = &parent.content.items[parent.content.items.len - 1];
            const child = &child_part.element;
            try stack.append(allocator, child);
        }
        self.node_count += 1;
    }

    pub fn format(self: Parser, writer: *Writer) Writer.Error!void {
        try writer.print("Parser {{ debug: {s}, token_count: {d} }}", .{
            if (self.debug) "yes" else "no",
            self.tokens.items.len,
        });
    }
};

fn expectParseError(source: []const u8, expected: anyerror) !void {
    var parser = try Parser.initFromSource(testing.allocator, source, false);
    defer parser.deinit();

    try testing.expectError(expected, parser.parse());
    try testing.expect(parser.document.root == null);
}

test "parser builds the real root and nested self-closing elements" {
    var parser = try Parser.initFromSource(testing.allocator, "<root><item/><next><leaf/></next></root>", false);
    defer parser.deinit();

    try parser.parse();
    try testing.expect(parser.document.root != null);

    const document_root = &parser.document.root.?;
    try testing.expectEqualStrings("root", document_root.metadata.tag);
    try testing.expectEqual(@as(usize, 2), document_root.content.items.len);
    try testing.expectEqualStrings("item", document_root.content.items[0].element.metadata.tag);
    try testing.expectEqualStrings("next", document_root.content.items[1].element.metadata.tag);
    try testing.expectEqualStrings(
        "leaf",
        document_root.content.items[1].element.content.items[0].element.metadata.tag,
    );
}

test "parser preserves text and element order in mixed content" {
    var parser = try Parser.initFromSource(
        testing.allocator,
        "<p>before<b/>between<i/>after</p>",
        false,
    );
    defer parser.deinit();

    try parser.parse();
    const parts = parser.document.root.?.content.items;

    try testing.expectEqual(@as(usize, 5), parts.len);
    try testing.expectEqualStrings("before", parts[0].text);
    try testing.expectEqualStrings("b", parts[1].element.metadata.tag);
    try testing.expectEqualStrings("between", parts[2].text);
    try testing.expectEqualStrings("i", parts[3].element.metadata.tag);
    try testing.expectEqualStrings("after", parts[4].text);
}

test "parser preserves whitespace-only text inside elements" {
    var parser = try Parser.initFromSource(testing.allocator, "<p> <b/> \n</p>", false);
    defer parser.deinit();

    try parser.parse();
    const parts = parser.document.root.?.content.items;

    try testing.expectEqual(@as(usize, 3), parts.len);
    try testing.expectEqualStrings(" ", parts[0].text);
    try testing.expectEqualStrings("b", parts[1].element.metadata.tag);
    try testing.expectEqualStrings(" \n", parts[2].text);
}

test "parser preserves comments in element content and at document level" {
    var parser = try Parser.initFromSource(
        testing.allocator,
        "<!--before--><root>left<!--inside--><child/><!--after-child-->right</root><!--after-->",
        false,
    );
    defer parser.deinit();

    try parser.parse();

    try testing.expectEqual(@as(usize, 2), parser.document.comments.items.len);
    try testing.expectEqualStrings("before", parser.document.comments.items[0]);
    try testing.expectEqualStrings("after", parser.document.comments.items[1]);
    try testing.expectEqual(@as(usize, 3), parser.document.content.items.len);
    try testing.expectEqualStrings("before", parser.document.content.items[0].comment);
    try testing.expect(parser.document.content.items[1] == .root);
    try testing.expectEqualStrings("after", parser.document.content.items[2].comment);

    const content = parser.document.root.?.content.items;
    try testing.expectEqual(@as(usize, 5), content.len);
    try testing.expectEqualStrings("left", content[0].text);
    try testing.expectEqualStrings("inside", content[1].comment);
    try testing.expectEqualStrings("child", content[2].element.metadata.tag);
    try testing.expectEqualStrings("after-child", content[3].comment);
    try testing.expectEqualStrings("right", content[4].text);
}

test "parser rejects an unexpected closing tag" {
    try expectParseError("</root>", error.UnexpectedClosingTag);
}

test "parser rejects a closing tag that does not match" {
    try expectParseError("<root><item></root>", error.MismatchedClosingTag);
}

test "parser rejects unclosed elements" {
    try expectParseError("<root><item/>", error.UnclosedTag);
}

test "parser rejects multiple root elements" {
    try expectParseError("<first/><second/>", error.MultipleRootElements);
}

test "parser rejects non-whitespace text outside the root" {
    try expectParseError("text<root/>", error.UnexpectedText);
}

test "parser rejects a document without a root element" {
    try expectParseError("", error.MissingRootElement);
}

test "parser rejects a second parse attempt" {
    var parser = try Parser.initFromSource(testing.allocator, "<root/>", false);
    defer parser.deinit();

    try parser.parse();
    try testing.expectError(error.AlreadyParsed, parser.parse());
}

test "parser reads XML declaration metadata" {
    var parser = try Parser.initFromSource(
        testing.allocator,
        "<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\"?><root/>",
        false,
    );
    defer parser.deinit();

    try parser.parse();

    try testing.expectEqualStrings("1.0", parser.document.prologue.version);
    try testing.expectEqualStrings("utf-8", parser.document.prologue.encoding);
    try testing.expect(parser.document.prologue.standalone);
}

test "parser preserves whitespace and greater-than in quoted attribute values" {
    var parser = try Parser.initFromSource(
        testing.allocator,
        "<item label=\"a value > here\" kind='primary choice'/>",
        false,
    );
    defer parser.deinit();

    try parser.parse();
    const attributes = parser.document.root.?.metadata.attributes;

    try testing.expectEqualStrings("a value > here", attributes.get("label").?);
    try testing.expectEqualStrings("primary choice", attributes.get("kind").?);
}

test "parser rejects an attribute without a quoted value" {
    try expectParseError("<item label=value/>", error.InvalidAttributeSyntax);
}

test "parser requires whitespace between attributes" {
    try expectParseError("<item first=\"one\"second=\"two\"/>", error.InvalidAttributeSyntax);
}

test "parser rejects an unterminated attribute value" {
    try expectParserInitError("<item label=\"unfinished>", error.UnterminatedAttributeValue);
}

test "parser rejects duplicate attributes" {
    try expectParseError("<item id=\"first\" id=\"second\"/>", error.DuplicateAttribute);
}

test "parser accepts valid Unicode XML names" {
    var parser = try Parser.initFromSource(
        testing.allocator,
        "<根 属性名=\"value\"><элемент/></根>",
        false,
    );
    defer parser.deinit();

    try parser.parse();
    const root = &parser.document.root.?;
    try testing.expectEqualStrings("根", root.metadata.tag);
    try testing.expectEqualStrings("value", root.metadata.attributes.get("属性名").?);
    try testing.expectEqualStrings("элемент", root.content.items[0].element.metadata.tag);
}

test "parser rejects XML names with invalid starting or continuation characters" {
    try expectParseError("<1root/>", error.InvalidXmlName);
    try expectParseError("<root bad/name=\"value\"/>", error.InvalidXmlName);
    try expectParseError("<root></1root>", error.InvalidXmlName);
}

test "parser accepts only a leading XML 1.0 declaration with UTF-8 encoding" {
    var parser = try Parser.initFromSource(
        testing.allocator,
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?><root/>",
        false,
    );
    defer parser.deinit();

    try parser.parse();
    try testing.expectEqualStrings("1.0", parser.document.prologue.version);
    try testing.expectEqualStrings("UTF-8", parser.document.prologue.encoding);
    try testing.expect(!parser.document.prologue.standalone);
}

test "parser rejects invalid XML declaration placement and values" {
    try expectParseError("<root/><?xml version=\"1.0\"?>", error.MisplacedXmlDeclaration);
    try expectParseError("<?xml?><root/>", error.MissingXmlVersion);
    try expectParseError("<?xml encoding=\"UTF-8\" version=\"1.0\"?><root/>", error.XmlVersionMustBeFirst);
    try expectParseError("<?xml version=\"1.1\"?><root/>", error.UnsupportedXmlVersion);
    try expectParseError("<?xml version=\"1.0\" encoding=\"UTF-16\"?><root/>", error.UnsupportedEncoding);
    try expectParseError("<?xml version=\"1.0\" custom=\"yes\"?><root/>", error.InvalidXmlDeclarationAttribute);
    try expectParseError("<?xml version=\"1.0\" standalone=\"no\" encoding=\"UTF-8\"?><root/>", error.InvalidXmlDeclarationOrder);
    try expectParseError("<?work item?><root/>", error.UnsupportedProcessingInstruction);
}

test "parser rejects input larger than the configured maximum" {
    const source = try testing.allocator.alloc(u8, Parser.MAX_INPUT_SIZE + 1);
    defer testing.allocator.free(source);
    @memset(source, ' ');

    try testing.expectError(
        error.InputTooLarge,
        Parser.initFromSource(testing.allocator, source, false),
    );
}

test "parser rejects nesting deeper than the configured maximum" {
    var source: ArrayList(u8) = .empty;
    defer source.deinit(testing.allocator);

    for (0..Parser.MAX_NESTING_DEPTH + 1) |_| try source.appendSlice(testing.allocator, "<n>");
    for (0..Parser.MAX_NESTING_DEPTH + 1) |_| try source.appendSlice(testing.allocator, "</n>");

    try expectParseError(source.items, error.ResourceLimitExceeded);
}

test "parser rejects more elements than the configured maximum" {
    var source: ArrayList(u8) = .empty;
    defer source.deinit(testing.allocator);

    try source.appendSlice(testing.allocator, "<root>");
    for (0..Parser.MAX_NODE_COUNT) |_| try source.appendSlice(testing.allocator, "<n/>");
    try source.appendSlice(testing.allocator, "</root>");

    try expectParseError(source.items, error.ResourceLimitExceeded);
}

test "parser decodes predefined entities and numeric references in text and attributes" {
    var parser = try Parser.initFromSource(
        testing.allocator,
        "<item value=\"&quot;&apos;&amp;&lt;&gt;&#65;&#x1F642;\">&quot;&apos;&amp;&lt;&gt;&#65;&#x1F642;</item>",
        false,
    );
    defer parser.deinit();

    try parser.parse();
    const root = &parser.document.root.?;
    try testing.expectEqualStrings("\"'&<>A🙂", root.metadata.attributes.get("value").?);
    try testing.expectEqualStrings("\"'&<>A🙂", root.content.items[0].text);
}

test "parser decodes entities once without expanding replacement text recursively" {
    var parser = try Parser.initFromSource(testing.allocator, "<root>&amp;lt;</root>", false);
    defer parser.deinit();

    try parser.parse();
    try testing.expectEqualStrings("&lt;", parser.document.root.?.content.items[0].text);
}

test "parser rejects unknown and incomplete entity references" {
    try expectParseError("<root>&custom;</root>", error.UndeclaredEntity);
    try expectParseError("<root>&amp</root>", error.UnterminatedEntityReference);
    try expectParseError("<root>&#;</root>", error.InvalidCharacterReference);
    try expectParseError("<root>&#x;</root>", error.InvalidCharacterReference);
    try expectParseError("<root>&#x110000;</root>", error.InvalidCharacterReference);
    try expectParseError("<root>&#0;</root>", error.InvalidCharacterReference);
    try expectParseError("<root>&#xD800;</root>", error.InvalidCharacterReference);
}

test "parser propagates truncated tokenizer input errors" {
    try expectParserInitError("<root", error.UnterminatedTag);
    try expectParserInitError("<root><!--unfinished", error.UnterminatedComment);
    try expectParserInitError("< root/>", error.InvalidTagSyntax);
    try expectParserInitError("</ root>", error.InvalidTagSyntax);
    try expectParserInitError("<root/ >", error.InvalidTagSyntax);
}

test "parser rejects invalid UTF-8 and XML control characters" {
    try expectParserInitError("<root>\xff</root>", error.InvalidUtf8);
    try expectParserInitError("<root>\x01</root>", error.InvalidXmlCharacter);
    try expectParserInitError("<root>\x00</root>", error.InvalidXmlCharacter);
}

test "parser normalizes CRLF and CR line endings to LF" {
    var parser = try Parser.initFromSource(
        testing.allocator,
        "<root attr=\"first\r\nsecond\rthird\">first\r\nsecond\rthird</root>",
        false,
    );
    defer parser.deinit();

    try parser.parse();
    const root = &parser.document.root.?;
    try testing.expectEqualStrings("first second third", root.metadata.attributes.get("attr").?);
    try testing.expectEqualStrings("first\nsecond\nthird", root.content.items[0].text);
}

test "parser preserves whitespace introduced by numeric references in attributes" {
    var parser = try Parser.initFromSource(testing.allocator, "<root value=\"before&#xA;after\"/>", false);
    defer parser.deinit();

    try parser.parse();
    try testing.expectEqualStrings("before\nafter", parser.document.root.?.metadata.attributes.get("value").?);
}

test "parser rejects raw less-than in attributes and the forbidden text terminator" {
    try expectParseError("<root value=\"a < b\"/>", error.InvalidAttributeValue);
    try expectParseError("<root>text ]]> invalid</root>", error.ForbiddenCDataTerminator);
}

test "parser can be retried after failure without retaining document metadata" {
    var parser = try Parser.initFromSource(
        testing.allocator,
        "<?xml version=\"1.0\" standalone=\"yes\"?><!----><root><item></root>",
        false,
    );
    defer parser.deinit();

    try testing.expectError(error.MismatchedClosingTag, parser.parse());
    try testing.expectEqual(@as(usize, 0), parser.document.comments.items.len);
    try testing.expectEqualStrings("1.0", parser.document.prologue.version);
    try testing.expect(!parser.document.prologue.standalone);
    try testing.expectError(error.MismatchedClosingTag, parser.parse());
    try testing.expectEqual(@as(usize, 0), parser.document.comments.items.len);
    try testing.expectEqualStrings("1.0", parser.document.prologue.version);
    try testing.expect(!parser.document.prologue.standalone);
}

fn expectParserInitError(source: []const u8, expected: anyerror) !void {
    try testing.expectError(expected, Parser.initFromSource(testing.allocator, source, false));
}
