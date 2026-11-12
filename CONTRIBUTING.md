# Contributing Guide

Thank you for your interest in contributing to `zxml`. The 1.x public API is
stable for the documented XML subset. Small, verifiable changes accompanied by
tests are especially helpful.

## Before you start

1. Read [README.md](./README.md) and [ROADMAP.md](./ROADMAP.md) to understand
   the current status and priorities.
2. Check whether an issue or proposal about the same topic already exists.
3. For major behavioral or scope changes, open a discussion or issue first and
   agree on the approach with the maintainer.
4. The project is licensed under the MIT License. Review
   [LICENSE.md](./LICENSE.md) before contributing.

## Set up the environment

Install Zig 0.16.0 or later. From the repository root:

```powershell
zig build
zig build test
zig fmt --check src build.zig
```

To run the program on the bundled example or a chosen XML path:

```powershell
zig build run
zig build run -- parse path\to\input.xml
```

Use `--debug` to print the tokenizer and parser trace.

## Changes and tests

- Keep each change focused and consistent with the project's conventions.
- Add tests for new or fixed behavior, including invalid input where
  appropriate.
- Do not claim support for XML constructs that the parser does not yet process
  correctly.
- Avoid leaving temporary debug messages in normal output.
- Run formatting, the build, and tests before submitting a change. If a command
  cannot be run, state which one and why.
- Do not include dependencies, broad formatting changes, or generated files
  that are not needed for the proposal.

## Pull requests

Describe the problem, the solution, and any remaining limitations. Include the
commands you ran and their results. For parser changes, provide minimal XML
examples that illustrate the covered case.

## Code of conduct

All participants are expected to follow [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md).
For security reports, use the private reporting process described in
[SECURITY.md](./SECURITY.md).