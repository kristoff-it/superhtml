# SuperHTML
Actually functional HTML Language Server (and Templating Language Library).

**NOTE: SuperHTML is still incomplete, some features are missing and looking of somebody to implement them :^)**

![](.github/vscode.png)

## HTML Language Server
The Super CLI Tool offers syntax checking and autoformatting features for HTML files.

```
$ super
Usage: super COMMAND [OPTIONS]

Commands:
  fmt          Format HTML documents
  lsp          Start the Super LSP
  help         Show this menu and exit

General Options:
  --help, -h   Print command specific usage  
```

### VSCode Support
1. Download a prebuilt version of `super` from the Releases section (or build it yourself).
2. Put `super` in your `PATH`.
3. Install the [Super HTML VSCode extension](https://marketplace.visualstudio.com/items?itemName=LorisCro.super). 


## Templating Language Library
SuperHTML is not only an LSP but also an HTML templating language. More on that soon.

## Contributing
SuperHTML tracks the latest Zig release (0.13.0 at the moment of writing). 

### Contributing to the HTML paser & LSP
Contributing to the HTML parser and LSP doesn't require you to be familiar with the templating language, basically limiting the scope of what you have to worry about to:

- `src/cli.zig`
- `src/cli/`
- `src/html/`

In particular, you will care about `src/html/Tokenizer.zig` and `src/html/Ast.zig`.

You can run `zig test src/html/Ast.zig` to run parser unit tests without needing to worry the rest of the project.

Running `zig build` will compile the Super CLI tool, allowing you to also then test the LSP behavior directly from your favorite editor.

The LSP will log in your cache directory so you can `tail -f ~/.cache/super/super.log` to see what happens with the LSP.

