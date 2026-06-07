# Clean-room Policy

This project must remain legally boring.

Allowed inputs:

- Publicly documented behavior.
- User-observable UI behavior.
- Original code written for this repository.
- Permissively licensed or Apache-2.0-compatible dependencies.
- Test fixtures created by contributors or generated procedurally.

Disallowed inputs:

- Original MangaMeeya source code, if it appears later without a clear license.
- Decompiled or disassembled MangaMeeya code.
- Copied binary resources, icons, images, configuration files, or plugin files.
- Code translated from reverse-engineering notes.
- GPL or AGPL code copied into the core without an explicit licensing decision.

Compatibility notes:

- It is fine to say the project is inspired by a classic reader interaction
  model.
- It is not fine to claim this project is an official continuation.
- When implementing a feature, describe the user-facing behavior, then write a
  new implementation from scratch.

Contribution rule:

If a contributor has recently inspected decompiled code for the same feature,
they should not implement that feature directly. They can write a behavior note;
another contributor can implement from that note if it avoids code-level detail.
