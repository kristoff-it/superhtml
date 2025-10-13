# Change Log

All notable changes to the "super" extension will be documented in this file.

## [v0.6.2]
- The "boolean attributes cannot have a value" error now puts squigglies under the attribute name instead of the value.
- Improved validation for `<link>` `[crossorigin]`, it previously used its own implementation of CORS validation, while now it uses one central implementation shared by all other similar attributes.
- `[lang]` (and similar attributes) now accept the empty string as value, used to signify that the language is unknown.
- Fixed a condition that would cause the language server to attempt to detect html elements inside of svg elements.

## [v0.6.1]
Fixes two bugs:

- `fmt` now properly leaves `<pre>` tags untouched, this regressed in the recent changes to formatting code, sorry!
- `--syntax-only` (and relative switch in VSCode) now silences also "invalid element name" errors, making it viable to use superhtml with some kinds of templated html

## [v0.6.0]
- All major Language Server features implemented: completions, clear diagnostics, descriptions, etc.
- New diagnostics cover element nesting errors and attribute validation, including complex interactions between different attributes and elements.
- Duplicate ID diagnostics that are `<template>` aware.
- Rename symbol on a tag name will rename both start and end tags at once.
- Find references can be used on class names to find other elements that have the same class.
- New improved autoformatting that keeps the first attribute on the same line as the element:
   - Uses tabs for indentation and spaces for alignment (experimental, might be reverted)
   - Respects empty lines that delineate separate blocks.
   - Doesn't format vertically elements in between text nodes anymore.
   - Basic CSS and JS autoformatting.
- Introduced a "Syntax Only Mode" setting to disable advanced validation for compatibility with templated HTML files.

This is a huge jump forward bug reports (with repro instructions!) are appreciated.
If you believe a diagnostic produced by SuperHTML to be wrong you are welcome to open an issue but
you will be asked to reference the HTML spec to dissuade poorly researched, drive-by issues.

## [v0.5.3]
- Fixes remaining bug when formatting void elements vertically.
 
## [v0.5.2]
- Starting from this release, a WASM-WASI build of SuperHTML is available on GitHub (in the Releases section) in case editors other than VSCode might watnt to bundle a wasm build of SuperHTML.
 
- Fixed indentation bug when formatting void elements.

## [v0.5.1]
- This is now a web extension that can be used with vscode.dev, etc.

## [v0.5.0]
- Updated list of obsolete tags, it previously was based on an outdated HTML spec version.
- The minor version of this extension is now aliged with the internal language server implementation version.

## [v0.3.0]
Now the LSP server is bundled in the extension, no need for a separate download anymore.

## [v0.2.0]
Introduced correct syntax highlighting grammar.

## [v0.1.3]
Add 'path' setting for this extension to allow specifying location of the Super CLI executable manually.

## [v0.1.2]
Override VSCode default autoformatting.

## [v0.1.1]
Readme fixes

## [v0.1.0]
- Initial release
