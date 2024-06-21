# SuperHTML

A HTML templating language.

**Super is pre-alpha stage, using it now requires participating to its development**.

## Contributing to the HTML pasers & LSP
Contributing to the HTML parser and LSP doesn't require you to be familiar with the templating language, basically limiting the scope of what you have to worry about to:

- `src/cli.zig`
- `src/cli/`
- `src/html/`

In particular, you will care about `src/html/Tokenizer.zig` and `src/html/Ast.zig`.

You can run `zig test src/html/Ast.zig` to run parser unit tests without needing to worry the rest of the project.

Running `zig build` will compile the Super CLI tool, allowing you to also then test the LSP behavior directly from your favorite editor.
