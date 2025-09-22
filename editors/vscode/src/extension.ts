import {
    // createStdioOptions,
    startServer
} from '@vscode/wasm-wasi-lsp';
import { ProcessOptions, Stdio, Wasm } from '@vscode/wasm-wasi/v1';
import { ConfigurationTarget, ExtensionContext, Uri, window, workspace, env } from 'vscode';
import {
    LanguageClient,
    LanguageClientOptions,
    ServerOptions
} from 'vscode-languageclient/node';

let client: LanguageClient;
export async function activate(context: ExtensionContext) {
    const config = workspace.getConfiguration('superhtml');

    let builtin_extension_is_enabled = true;
    try {
        const settings = [
            'html.suggest.html5',
            'html.autoClosingTags',
            'html.hover.documentation',
            'html.hover.references'
        ];

        const cfg = workspace.getConfiguration();
        for (const s of settings) {
            await cfg.update(s, false, ConfigurationTarget.Global);
        }
    } catch {
        // the builtin extension is disabled, we're happy
        builtin_extension_is_enabled = false;
    }

    if (builtin_extension_is_enabled) {
        const ensure_html_disabled = config.get<boolean>("EnsureBuiltinHTMLExtensionIsDisabled", true);
        if (ensure_html_disabled) {
            const see_how = "See How";
            const never = "Don't Show This Again";
            const dismiss = "Dismiss";

            window.showWarningMessage(
                "To prevent wrong end tag suggestions, disable the VSCode builtin HTML extension.",
                see_how, never, dismiss,
            ).then(async (choice) => {
                if (choice == see_how) {
                    const uri = Uri.parse("https://github.com/kristoff-it/superhtml/issues/107");
                    await env.openExternal(uri);
                } else if (choice == never) {
                    await config.update("EnsureBuiltinHTMLExtensionIsDisabled", false, ConfigurationTarget.Global);
                    await window.showInformationMessage(
                        "You won't be asked to disable the VSCode HTML extension again."
                    );
                }
            });
        }
    }

    let args = [];
    const syntax_only = config.get<boolean>("SyntaxOnlyMode", false);
    if (syntax_only) {
        args.push('--syntax-only');
    }

    const wasm: Wasm = await Wasm.load();

    const channel = window.createOutputChannel('SuperHTML Language Server');
    // The server options to run the WebAssembly language server.
    const serverOptions: ServerOptions = async () => {
        const options: ProcessOptions = {
            stdio: createStdioOptions(),
            // mountPoints: [{ kind: 'workspaceFolder' }]
            args: args,
        };

        // Load the WebAssembly code
        const filename = Uri.joinPath(
            context.extensionUri,
            'wasm',
            'superhtml.wasm'
        );
        const bits = await workspace.fs.readFile(filename);
        const module = await WebAssembly.compile(bits);

        // Create the wasm worker that runs the LSP server
        const process = await wasm.createProcess(
            'superhtml',
            module,
            { initial: 160, maximum: 160, shared: false },
            options
        );

        // Hook stderr to the output channel
        const decoder = new TextDecoder('utf-8');
        process.stderr!.onData(data => {
            channel.append(decoder.decode(data));
        });

        return startServer(process);
    };

    const clientOptions: LanguageClientOptions = {
        documentSelector: [
            { scheme: "file", language: 'html' },
            { scheme: "file", language: 'superhtml' },
        ],
        outputChannel: channel,
    };

    client = new LanguageClient(
        "superhtml",
        "SuperHTML Language Server",
        serverOptions,
        clientOptions
    );

    await client.start();
}

export function deactivate(): Thenable<void> | undefined {
    if (!client) {
        return undefined;
    }
    return client.stop();
}


function createStdioOptions(): Stdio {
    return {
        in: {
            kind: 'pipeIn',
        },
        out: {
            kind: 'pipeOut'
        },
        err: {
            kind: 'pipeOut'
        }
    };
}
