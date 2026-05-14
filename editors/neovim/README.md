# Silt Neovim Files

This directory contains the current lightweight Neovim integration for Silt:

- `ftdetect/silt.vim` assigns the `silt` filetype to `*.silt` and `Silt.pkg`.
- `syntax/silt.vim` highlights the current S-expression surface, core forms,
  primitive types, declarations, literals, and comments.
- `silt diagnostics --json FILE...` emits the same formatter/parser/checker
  facts as lint as `silt.diagnostics.v0` JSON for future editor/LSP adapters.

For local use, add this directory to Neovim's runtime path or copy the
`ftdetect/` and `syntax/` directories into a package directory managed by your
Neovim configuration.

This is syntax/filetype integration plus a machine-readable diagnostics seed.
It is not an LSP server, formatter adapter, or package manager plugin.
