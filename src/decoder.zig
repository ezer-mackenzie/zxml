const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const mem = std.mem;

const XmlValidator = @import("validator.zig").XmlValidator;

pub const XmlDecoder = struct {
    pub fn normalizeLineEndings(allocator: Allocator, source: []const u8) ![]u8 {
        var normalized = try allocator.alloc(u8, source.len);
        errdefer allocator.free(normalized);

        var source_index: usize = 0;
        var target_index: usize = 0;
        while (source_index < source.len) {
            if (source[source_index] == '\r') {
                normalized[target_index] = '\n';
                target_index += 1;
                source_index += 1;
                if (source_index < source.len and source[source_index] == '\n') source_index += 1;
            } else {
                normalized[target_index] = source[source_index];
                target_index += 1;
                source_index += 1;
            }
        }

        return try allocator.realloc(normalized, target_index);
    }

    pub fn decodeEntities(allocator: Allocator, text: []const u8, normalize_attribute_whitespace: bool) ![]const u8 {
        if (mem.indexOfScalar(u8, text, '&') == null and !normalize_attribute_whitespace) return text;

        var decoded: ArrayList(u8) = .empty;
        errdefer decoded.deinit(allocator);
        var index: usize = 0;
        while (index < text.len) {
            if (text[index] != '&') {
                const char = text[index];
                try decoded.append(
                    allocator,
                    if (normalize_attribute_whitespace and (char == '\t' or char == '\n' or char == '\r')) ' ' else char,
                );
                index += 1;
                continue;
            }

            const entity_start = index + 1;
            const relative_end = mem.indexOfScalar(u8, text[entity_start..], ';') orelse {
                return error.UnterminatedEntityReference;
            };
            const entity = text[entity_start .. entity_start + relative_end];
            if (entity.len == 0) return error.InvalidCharacterReference;

            if (entity[0] == '#') {
                const is_hex = entity.len > 1 and (entity[1] == 'x' or entity[1] == 'X');
                const digits = entity[if (is_hex) 2 else 1..];
                if (digits.len == 0) return error.InvalidCharacterReference;

                const codepoint = std.fmt.parseInt(u21, digits, if (is_hex) 16 else 10) catch {
                    return error.InvalidCharacterReference;
                };
                if (!XmlValidator.isValidXmlCharacter(codepoint)) return error.InvalidCharacterReference;

                var encoded: [4]u8 = undefined;
                const encoded_len = std.unicode.utf8Encode(codepoint, &encoded) catch {
                    return error.InvalidCharacterReference;
                };
                try decoded.appendSlice(allocator, encoded[0..encoded_len]);
            } else {
                const replacement: u8 = if (mem.eql(u8, entity, "amp"))
                    '&'
                else if (mem.eql(u8, entity, "lt"))
                    '<'
                else if (mem.eql(u8, entity, "gt"))
                    '>'
                else if (mem.eql(u8, entity, "apos"))
                    '\''
                else if (mem.eql(u8, entity, "quot"))
                    '"'
                else
                    return error.UndeclaredEntity;

                try decoded.append(allocator, replacement);
            }
            index = entity_start + relative_end + 1;
        }

        return try decoded.toOwnedSlice(allocator);
    }
};
