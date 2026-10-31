# Offline runtime guarantee

After the release ZIP and its adjacent SHA-256 file have been obtained, every
component advertised as part of that edition works without a network connection.

Core guarantees offline Idris 2 compilation, standard libraries, the Chez
Scheme backend, and the included examples. Full additionally guarantees the
bundled language server, RefC backend, GCC, Git, Bash, Make, and Pack executable.
The launcher never invokes Pack, downloads files, checks for updates, or contacts
a package collection.

This guarantee does not include packages absent from the archive. A user-issued
`pack install` for an unbundled package is an explicit request for external
content and may use the network. It is never performed automatically.

For an air-gapped installation, download the ZIP and `.sha256` file on another
machine, copy them together, and run:

```powershell
.\init.ps1 -Archive .\portable-idris2-<edition>-<version>-windows-x86_64.zip
```

The installer verifies SHA-256 before extracting the archive.
