const std = @import("std");
const mem = std.mem;

const Writer = std.Io.Writer;
const Allocator = mem.Allocator;

const StringHashMap = std.StringHashMap;
const ArrayList = std.ArrayList;

pub const ZXMLErrors = error{
    UnsupportedFile,
    NotAnXmlDocument,
};

pub const TokenType = enum {
    StartTag,
    EndTag,
    SelfClosingTag,
    Text,
    Comment,
};

pub const Token = struct {
    type: TokenType,
    content: []const u8,
    self_closing: bool = false,

    pub fn format(self: Token, writer: *Writer) Writer.Error!void {
        try writer.print("Token {{ type: {s}, content: {s}, self_closing: {} }}", .{
            @tagName(self.type),
            self.content,
            self.self_closing,
        });
    }
};

pub const Metadata = struct {
    tag: []const u8,
    attributes: StringHashMap([]const u8),
    debug: bool = false,

    pub fn init(
        allocator: Allocator,
        content: []const u8,
    ) !Metadata {
        var attributes: StringHashMap([]const u8) = .init(allocator);
        errdefer attributes.deinit();

        var index: usize = 0;
        skipWhitespace(content, &index);

        const tag_start = index;
        while (index < content.len and !isWhitespace(content[index])) : (index += 1) {}
        if (index == tag_start) return error.InvalidTagName;
        const tag_name = content[tag_start..index];
        try validateXmlName(tag_name);

        while (index < content.len) {
            skipWhitespace(content, &index);
            if (index == content.len) break;

            const key_start = index;
            while (index < content.len and !isWhitespace(content[index]) and content[index] != '=') : (index += 1) {}
            if (index == key_start) return error.InvalidAttributeSyntax;
            const key = content[key_start..index];
            try validateXmlName(key);

            skipWhitespace(content, &index);
            if (index == content.len or content[index] != '=') return error.InvalidAttributeSyntax;
            index += 1;
            skipWhitespace(content, &index);
            if (index == content.len or (content[index] != '"' and content[index] != '\'')) {
                return error.InvalidAttributeSyntax;
            }

            const quote = content[index];
            index += 1;
            const value_start = index;
            while (index < content.len and content[index] != quote) : (index += 1) {
                if (content[index] == '<') return error.InvalidAttributeValue;
            }
            if (index == content.len) return error.UnterminatedAttributeValue;

            const value = content[value_start..index];
            index += 1;
            if (attributes.contains(key)) return error.DuplicateAttribute;
            try attributes.put(key, value);

            if (index < content.len and !isWhitespace(content[index])) {
                return error.InvalidAttributeSyntax;
            }
        }

        return .{
            .tag = tag_name,
            .attributes = attributes,
            .debug = false,
        };
    }

    fn isWhitespace(char: u8) bool {
        return char == ' ' or char == '\t' or char == '\n' or char == '\r';
    }

    fn skipWhitespace(content: []const u8, index: *usize) void {
        while (index.* < content.len and isWhitespace(content[index.*])) : (index.* += 1) {}
    }

    pub fn validateXmlName(name: []const u8) !void {
        if (name.len == 0) return error.InvalidXmlName;

        var index: usize = 0;
        var first = true;
        while (index < name.len) {
            const sequence_length = std.unicode.utf8ByteSequenceLength(name[index]) catch {
                return error.InvalidXmlName;
            };
            const end = index + sequence_length;
            if (end > name.len) return error.InvalidXmlName;

            const codepoint = std.unicode.utf8Decode(name[index..end]) catch {
                return error.InvalidXmlName;
            };
            if (first) {
                if (!isXmlNameStartChar(codepoint)) return error.InvalidXmlName;
            } else if (!isXmlNameChar(codepoint)) {
                return error.InvalidXmlName;
            }

            first = false;
            index = end;
        }
    }

    fn isXmlNameStartChar(codepoint: u21) bool {
        return codepoint == ':' or codepoint == '_' or
            (codepoint >= 'A' and codepoint <= 'Z') or
            (codepoint >= 'a' and codepoint <= 'z') or
            (codepoint >= 0xC0 and codepoint <= 0xD6) or
            (codepoint >= 0xD8 and codepoint <= 0xF6) or
            (codepoint >= 0xF8 and codepoint <= 0x2FF) or
            (codepoint >= 0x370 and codepoint <= 0x37D) or
            (codepoint >= 0x37F and codepoint <= 0x1FFF) or
            (codepoint >= 0x200C and codepoint <= 0x200D) or
            (codepoint >= 0x2070 and codepoint <= 0x218F) or
            (codepoint >= 0x2C00 and codepoint <= 0x2FEF) or
            (codepoint >= 0x3001 and codepoint <= 0xD7FF) or
            (codepoint >= 0xF900 and codepoint <= 0xFDCF) or
            (codepoint >= 0xFDF0 and codepoint <= 0xFFFD) or
            (codepoint >= 0x10000 and codepoint <= 0xEFFFF);
    }

    fn isXmlNameChar(codepoint: u21) bool {
        return isXmlNameStartChar(codepoint) or
            codepoint == '-' or codepoint == '.' or
            (codepoint >= '0' and codepoint <= '9') or
            codepoint == 0xB7 or
            (codepoint >= 0x300 and codepoint <= 0x36F) or
            (codepoint >= 0x203F and codepoint <= 0x2040);
    }

    pub fn deinit(self: *Metadata) void {
        self.tag = undefined;
        self.attributes.deinit();
    }

    pub fn format(
        self: Metadata,
        writer: *Writer,
    ) Writer.Error!void {
        try writer.print(
            "Metadata {{ tag: \"{s}\", attributes_count: {d}",
            .{ self.tag, self.attributes.count() },
        );

        if (self.attributes.count() > 0) {
            try writer.writeAll(", attributes: [");

            var iterator = self.attributes.iterator();
            var first = true;

            while (iterator.next()) |entry| {
                if (!first) try writer.writeAll(", ");

                try writer.print(
                    "{s}=\"{s}\"",
                    .{ entry.key_ptr.*, entry.value_ptr.* },
                );

                first = false;
            }

            try writer.writeAll("]");
        }

        try writer.writeAll(" }");
    }
};

pub const NodeContent = union(enum) {
    text: []const u8,
    element: Node,
    comment: []const u8,
};

pub const Node = struct {
    metadata: Metadata,
    content: ArrayList(NodeContent),

    pub fn init(metadata: Metadata) Node {
        return .{
            .metadata = metadata,
            .content = .empty,
        };
    }

    pub fn deinit(self: *Node, allocator: mem.Allocator) void {
        for (self.content.items) |*part| {
            switch (part.*) {
                .text, .comment => {},
                .element => |*child| child.deinit(allocator),
            }
        }

        self.metadata.deinit();
        self.content.deinit(allocator);
    }

    pub fn format(
        self: Node,
        writer: *Writer,
    ) Writer.Error!void {
        try writer.print("XMLNode{{ tag: \"{s}\", content_parts: {} }}", .{
            self.metadata.tag,
            self.content.items.len,
        });
    }
};

pub const Prologue = struct {
    version: []const u8,
    encoding: []const u8,
    standalone: bool,

    pub fn init(version: ?[]const u8, encoding: ?[]const u8, standalone: ?bool) Prologue {
        return .{
            .version = version orelse "1.0",
            .encoding = encoding orelse "utf-8",
            .standalone = standalone orelse false,
        };
    }

    pub fn format(self: Prologue, writer: *Writer) Writer.Error!void {
        try writer.print(
            "Prologue {{ version: \"{s}\", encoding: \"{s}\", standalone: {} }}",
            .{ self.version, self.encoding, self.standalone },
        );
    }
};

pub const DocumentContent = union(enum) {
    root,
    comment: []const u8,
};

pub const Document = struct {
    prologue: Prologue,
    root: ?Node,
    comments: ArrayList([]const u8), // Stores comment slices without owning their source text.
    content: ArrayList(DocumentContent),

    pub fn init(
        prologue: Prologue,
        root: ?Node,
    ) Document {
        return .{
            .prologue = prologue,
            .root = root,
            .comments = .empty,
            .content = .empty,
        };
    }

    pub fn deinit(self: *Document, allocator: Allocator) void {
        if (self.root) |*r| r.deinit(allocator);
        self.comments.deinit(allocator);
        self.content.deinit(allocator);
    }

    pub fn format(self: Document, writer: *Writer) Writer.Error!void {
        try writer.writeAll("XMLDocument {\n  ");

        try writer.print("prologue: {f},\n  root: ", .{self.prologue});

        if (self.root) |root| {
            try writer.print("{f}", .{root});
        } else {
            try writer.writeAll("null");
        }

        try writer.writeAll("\n}");
    }
};
