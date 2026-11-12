# zxml

`zxml` is an XML parser written in Zig for the documented XML subset. It can
tokenize a document and build an element tree, but it does not implement or
validate the full XML specification. Despite the stable API, it is not
suitable for production use or untrusted input.

The package version is **0.9.0**. The public API and documented behavior are
stable throughout the 1.x series. This does not imply support for the full XML
specification or suitability for parsing untrusted input.

## Requirements

- Zig **0.16.0** or later, as specified in `build.zig.zon`.

## Build and run

```powershell
zig build
zig build test
zig build run
```

By default, `zig build run` processes `docs/example.xml`. Supply a path to
parse a different file:

```powershell
zig build run -- parse docs/example.xml
zig build run -- path\to\input.xml --debug
```

The `parse` command is optional. On Windows, the executable is installed at
`zig-out/bin/zxml.exe`.

The CLI also supports a JSON tree export and a detailed metrics report:

```powershell
zig build run -- json docs/example.xml --output tree.json
zig build run -- report docs/example.xml --output report.json
zig build run -- report docs/example.xml --include-content
```

`parse` validates the input and prints a concise summary. The JSON report
includes elapsed file-loading, tokenization, and parse time in nanoseconds and
the total in milliseconds, separated into file-loading/tokenization and tree
parsing, the input byte count before line-ending normalization, normalized
byte count, line and token counts, root name, element count, maximum depth,
attribute count, decoded text-node and byte counts, and comment counts/bytes.
Use `--include-content` to include the full normalized source in a report;
without this flag, the report contains sizes and statistics but not document
text. Treat reports with content as sensitive data.

To print a trace of file reading, tokenization, and parsing:

```powershell
zig build run -- --debug
```

Without `--debug`, the program does not print these diagnostic messages.

## Implemented behavior

- The reader loads files up to 10 MiB and performs a basic check that the first
  non-whitespace character is `<`. The parser, not the reader, validates the
  document structure.
- The tokenizer distinguishes opening tags, closing tags, self-closing tags,
  text, and comments. A `>` inside a quoted attribute value does not end a tag.
- Opening tags accept attributes with single- or double-quoted values.
  Attribute values may contain whitespace and `>`.
- The parser builds a tree with one actual root element, validates matching
  closing tags, and rejects unexpected closing tags, unclosed elements,
  multiple roots, and non-whitespace text outside the root.
- The tree stores text and child elements in source order, preserving mixed
  content such as `<p>before<b/>after</p>`.
- Whitespace-only text inside elements is preserved; whitespace outside the
  document element is ignored.
- The parser extracts `version`, `encoding`, and `standalone` from an
  XML-declaration-shaped token. `standalone` accepts `yes` and `no`.
- Malformed attribute syntax, unterminated quoted values, and duplicate
  attributes are rejected.
- Element names, closing names, and attribute names are checked against the
  XML 1.0 `Name` character ranges, including valid UTF-8 name characters.
- An optional XML declaration must be first, declare XML 1.0, and may specify
  UTF-8 encoding and `standalone="yes"` or `"no"`. Other processing
  instructions and encodings are rejected.
- The five predefined XML entities (`amp`, `lt`, `gt`, `apos`, and `quot`) are
  decoded in text and attribute values. Decimal and hexadecimal numeric
  character references are also decoded. Undeclared, unterminated, malformed,
  and XML-invalid character references are rejected.
- The parser API rejects input larger than 10 MiB, nesting deeper than 256
  elements, and documents containing more than 16,384 elements.
- The tokenizer reports unterminated tags, quoted attribute values, and
  comments, and rejects comments containing the forbidden `--` sequence.
- Whitespace before an element name, after a closing slash, or after a
  self-closing slash is rejected as malformed tag syntax.
- Input must be valid UTF-8 and contain only XML 1.0 characters. Literal `<` in
  attribute values and `]]>` in character data are rejected.
- XML line endings are normalized: CRLF and lone CR become LF before parsing.
- Comments inside elements are retained in the ordered content sequence;
  comments outside the root are retained in `Document.comments` and
  `Document.content`, which preserves their order relative to the root.
- The library can export a parsed document as compact JSON with
  `zxml.json.stringify`; the JSON format preserves document and mixed-content
  order, and sorts attribute names for deterministic output.

## JSON export

`zxml.Json` encapsulates JSON generation with `init`, `writeDocument`,
`toOwnedSlice`, and `deinit`. `zxml.json.stringify(allocator, parser.document)`
is a convenience method that returns an allocated JSON slice. The caller owns
the result and must free it with the same allocator.
The document object contains its XML prologue and an ordered `content` array.
Elements have a `name`, an `attributes` object, and an ordered `content` array;
text and comments are represented as typed objects with a `value` string.
Strings are escaped according to JSON rules, while valid non-ASCII text remains
UTF-8.

## Limitations

- This is not a complete XML parser or validator. Namespaces are not
  interpreted or validated.
- Other processing instructions, CDATA, and DTDs are not implemented as XML
  features.
- Token positions are not yet tracked, so syntax errors do not report line or
  column numbers.
- Custom DTD entity declarations are not supported.
- Element content is represented as ordered text, comment, and child-element
  parts. Document-level order is available through `Document.content`.
- The reader's initial-markup check is only a basic input check, not document
  validation.
- The parser has not been hardened for untrusted input and must not be used as
  a security boundary.

## Compatibility

The 1.x series preserves the public API and documented behavior. Additions and
bug fixes may be released as minor or patch versions, respectively; breaking
API or behavior changes require a new major version. Validation fixes may
cause malformed input that was previously accepted to be rejected.

Parsed text, tag names, and attribute strings are slices into the parser's
owned source buffer. Keep the `Parser` alive while using its parsed document.
The parser stores the allocator supplied to `Parser.init` or
`Parser.initFromSource`; call `parse()` and `deinit()` without passing it again.

The package exports `Parser`, `Json`, `Document`, `DocumentContent`, `Node`,
`NodeContent`, `Metadata`, `Prologue`, `Token`, and `TokenType` from
`src/root.zig`; the `json` namespace provides document serialization.

## Project structure

- `src/reader.zig`: input file reading.
- `src/tokenizer.zig`: tokenization and initial tag/attribute parsing.
- `src/parser.zig`: node tree construction.
- `src/decoder.zig`: XML entity decoding and line-ending normalization.
- `src/validator.zig`: XML character and declaration validation.
- `src/json.zig`: JSON serialization for parsed documents.
- `src/cli.zig`: CLI argument handling and command orchestration.
- `src/report/metrics.zig`: metrics collected from the parsed document tree.
- `src/report/report.zig`: report data and JSON serialization.
- `src/core.zig`: shared types and structures.
- `src/main.zig`: current entry point.
- `docs/example.xml`: document used by the executable.

## Contributing

Read [CONTRIBUTING.md](./CONTRIBUTING.md) before proposing changes. To report a
potential security issue, follow [SECURITY.md](./SECURITY.md). The project's
direction and scope are described in [ROADMAP.md](./ROADMAP.md).

## License

This project is licensed under the MIT License. See [LICENSE.md](./LICENSE.md)
for the full license text.