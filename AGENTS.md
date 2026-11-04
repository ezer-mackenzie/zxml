# Project Guidelines

## Project status

`zxml` is an experimental XML parser and is not yet suitable for production or
untrusted input. Check [README.md](./README.md) and [ROADMAP.md](./ROADMAP.md)
before describing supported behavior. Do not claim support for XML constructs
that are not implemented and tested.

## Code and architecture

- The project targets Zig 0.16.0 or later; verify the minimum in
  `build.zig.zon`.
- Keep changes focused and follow Zig naming and formatting conventions. Run
  `zig fmt` on Zig files you change.
- Preserve the separation between `reader.zig`, `tokenizer.zig`, `parser.zig`,
  and shared types in `core.zig` unless the task calls for an architectural
  change.
- Be explicit about allocator ownership and cleanup, especially on error paths.
- Do not leave temporary debug output in normal program behavior.
- Keep documentation accurate about current implementation limitations.

## Build and test

From the repository root, run:

```powershell
zig build
zig build test
zig fmt --check src build.zig
```

Add focused tests for parser and tokenizer changes, including malformed input
where relevant. Report any validation command that could not be run.

## Project documentation

Follow [CONTRIBUTING.md](./CONTRIBUTING.md) for contribution expectations,
[SECURITY.md](./SECURITY.md) for security reports, and
[CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) for community behavior. The project
is licensed under the MIT License; do not change licensing terms or add
source-file license headers unless the maintainer asks.
