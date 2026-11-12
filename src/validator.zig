const std = @import("std");

const mem = std.mem;

pub const XmlValidator = struct {
    pub fn validateXmlDeclarationOrder(attributes: []const u8) !void {
        var index: usize = 0;
        var previous_rank: u8 = 0;

        while (index < attributes.len) {
            while (index < attributes.len and mem.indexOfScalar(u8, " \t\n\r", attributes[index]) != null) : (index += 1) {}
            if (index == attributes.len) break;

            const name_start = index;
            while (index < attributes.len and mem.indexOfScalar(u8, " \t\n\r=", attributes[index]) == null) : (index += 1) {}
            const name = attributes[name_start..index];
            const rank: u8 = if (mem.eql(u8, name, "version"))
                1
            else if (mem.eql(u8, name, "encoding"))
                2
            else if (mem.eql(u8, name, "standalone"))
                3
            else
                return error.InvalidXmlDeclarationAttribute;

            if (rank <= previous_rank) return error.InvalidXmlDeclarationOrder;
            previous_rank = rank;

            while (index < attributes.len and mem.indexOfScalar(u8, " \t\n\r", attributes[index]) != null) : (index += 1) {}
            if (index == attributes.len or attributes[index] != '=') return error.InvalidXmlDeclarationAttribute;
            index += 1;
            while (index < attributes.len and mem.indexOfScalar(u8, " \t\n\r", attributes[index]) != null) : (index += 1) {}
            if (index == attributes.len or (attributes[index] != '"' and attributes[index] != '\'')) {
                return error.InvalidXmlDeclarationAttribute;
            }

            const quote = attributes[index];
            index += 1;
            while (index < attributes.len and attributes[index] != quote) : (index += 1) {}
            if (index == attributes.len) return error.InvalidXmlDeclarationAttribute;
            index += 1;
        }

        if (previous_rank == 0) return error.MissingXmlVersion;
    }

    pub fn isValidXmlCharacter(codepoint: u21) bool {
        return codepoint == 0x9 or codepoint == 0xA or codepoint == 0xD or
            (codepoint >= 0x20 and codepoint <= 0xD7FF) or
            (codepoint >= 0xE000 and codepoint <= 0xFFFD) or
            (codepoint >= 0x10000 and codepoint <= 0x10FFFF);
    }

    pub fn validateXmlCharacters(source: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(source)) return error.InvalidUtf8;

        var index: usize = 0;
        while (index < source.len) {
            const sequence_length = std.unicode.utf8ByteSequenceLength(source[index]) catch {
                return error.InvalidUtf8;
            };
            const end = index + sequence_length;
            const codepoint = std.unicode.utf8Decode(source[index..end]) catch {
                return error.InvalidUtf8;
            };
            if (!isValidXmlCharacter(codepoint)) return error.InvalidXmlCharacter;
            index = end;
        }
    }
};
