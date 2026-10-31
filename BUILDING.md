# Building and auditing a release

For the exact inputs, public build log, Chinese step-by-step explanation, audit
commands, and reproduction entry point for the current Core and Full releases,
see [`REPRODUCING.md`](REPRODUCING.md).

Core is built from pinned Idris 2 and Chez Scheme release tags by
`scripts/build-toolchain.ps1`. Full is assembled by
`scripts/build-full-toolchain.ps1` from exact Pack, collection, LSP-lib, and
idris2-lsp commits. Repository patches live under `patches/` and are applied by
the build script rather than hidden in a prebuilt binary.

Each archive contains `SOURCE-MANIFEST.json`, `SBOM.spdx.json`, third-party
notices and licenses, and `OFFLINE-GUARANTEE.md`. The manifest and SBOM are also
published as separate Release assets.

The Full build also compiles `native/Launch-Idris2-LSP.c` with the GCC included
in the bundled MSYS2 tree. Chez on Windows emits LF-only LSP headers, while VS
Code requires the protocol's CRLF framing. The native proxy launches the exact
bundled Scheme program, preserves stdin and JSON bodies byte-for-byte, and only
canonicalizes LSP headers. Its exact source is retained in the ZIP under
`sources/`; source and executable SHA-256 values are recorded in the manifest.

The normal rebuild command is:

```powershell
.\scripts\build-full-toolchain.ps1 `
  -IdrisVersion v0.8.0 -ChezVersion v10.4.1 `
  -PackCollection nightly-251031 `
  -PackCommit cb842e66c7e9834fae9cdf05ba33ca64fbec949f `
  -PackDbCommit 69ddc094a218941bba5516828c2ee1dfdcc640f5
```

The recipe is intended to be auditable and rebuildable. It deliberately does
not claim byte-for-byte reproducibility across machines. Upstream network URLs
can disappear; the exact commits, checksums, patches, and published runtime ZIP
remain sufficient to audit what an existing release contains. Preserved source
inputs can be substituted for the same commits without changing the recipe.
