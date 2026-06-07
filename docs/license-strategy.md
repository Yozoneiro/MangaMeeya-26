# License Strategy

The project uses Apache-2.0.

Why:

- Simple for personal, commercial, desktop, mobile, and store distribution.
- Explicit patent grant.
- Friendly to Rust and cross-platform ecosystem reuse.
- Less friction for future Android, iOS, and embedded shells.

What this means:

- Others can use, modify, redistribute, and sell builds.
- They do not need to open-source their changes.
- They must preserve the license and notices.
- The project should rely on brand, community, and velocity rather than strong
  copyleft.

Dependency policy:

- Prefer MIT, Apache-2.0, BSD, ISC, Zlib, MPL-2.0, or similarly permissive
  dependencies.
- Avoid GPL/AGPL dependencies in core crates.
- If a GPL tool is useful, keep it outside the distributed application or behind
  a separate optional process with an explicit decision record.
