import {
    createStdioOptions,
    startServer
} from '@vscode/wasm-wasi-lsp';
import { ProcessOptions, Wasm } from '@vscode/wasm-wasi';
import { ExtensionContext, Uri, window, workspace } from 'vscode';
import {
    LanguageClient,
    LanguageClientOptions,
    ServerOptions
} from 'vscode-languageclient/node';

export async function activate(context: ExtensionContext) {
    const wasm: Wasm = await Wasm.load();

    const channel = window.createOutputChannel('SuperHTML LSP WASM Server');
    // The server options to run the WebAssembly language server.
    const serverOptions: ServerOptions = async () => {
        const options: ProcessOptions = {
            stdio: createStdioOptions(),
            mountPoints: [{ kind: 'workspaceFolder' }]
        };

        // Load the WebAssembly code
        const filename = Uri.joinPath(
            context.extensionUri,
            'wasm',
            'server.wasm'
        );
        const bits = await workspace.fs.readFile(filename);
        const module = await WebAssembly.compile(bits);

        // Create the wasm worker that runs the LSP server
        const process = await wasm.createProcess(
            'superhtml',
            module,
            { initial: 160, maximum: 160, shared: true },
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
            { scheme: "file", language: 'super' },
        ],
        outputChannel: channel,
    };

    const client = new LanguageClient(
        "super",
        "SuperHTML Language Server",
        serverOptions,
        clientOptions

    );
    await client.start();
}