# zxml

An experimental XML parser written in Zig. The project is at an early stage:
it has separate components for reading a file, generating tokens, and building
a node structure, but it does not yet fully implement or validate XML. It is
not recommended for production use or for processing untrusted documents.

## Requirements

- Zig **0.16.0** or later, as specified in `build.zig.zon`.

## Build and run

```powershell
zig build
zig build test
zig build run
```

In its current state, `zig build run` processes the example file
`docs/example.xml`; it does not yet accept an input path from the command line.
On Windows, the built executable is installed at `zig-out/bin/zxml.exe`.

To print a trace of file reading, tokenization, and parsing:

```powershell
zig build run -- --debug
```

Without `--debug`, the program does not print these diagnostic messages.

## Current status

- File reading with a 10 MiB size limit.
- Initial tokenization of tags and text.
- Data structures for tokens and XML nodes.
- Parser in development for building a basic tree.

The implementation is incomplete: attribute parsing, self-closing tags,
comments, entities, mixed content, and closing-tag validation still need work.
The current tests do not adequately cover these cases.

## Project structure

- `src/reader.zig`: input file reading.
- `src/tokenizer.zig`: tokenization and initial tag/attribute parsing.
- `src/parser.zig`: node tree construction.
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