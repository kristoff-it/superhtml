import * as path from 'path';
import { workspace, ExtensionContext, window, languages } from 'vscode';
import { SuperFormatProvider } from './formatter';

import {
    LanguageClient,
    LanguageClientOptions,
    ServerOptions
} from 'vscode-languageclient/node';
import { getSuperPath } from './util';

let client: LanguageClient;

const logChannel = window.createOutputChannel("Super");

export function activate(context: ExtensionContext) {

    // If the extension is launched in debug mode then the debug server options are used
    // Otherwise the run options are used
    const serverOptions: ServerOptions = {
        command: getSuperPath(),
        args: ["lsp"],
    };

    // Options to control the language client
    const clientOptions: LanguageClientOptions = {
        // Register the server for plain text documents
        documentSelector: [
            { scheme: "file", language: 'html' },
            { scheme: "file", language: 'super' },
        ],
        outputChannel: logChannel,
        // synchronize: {
        // 	// Notify the server about file changes to '.clientrc files contained in the workspace
        // 	fileEvents: workspace.createFileSystemWatcher('**/.zgy')
        // }
    };

    // Create the language client and start the client.
    const client = new LanguageClient(
        "super",
        "SuperHTML Language Server",
        serverOptions,
        clientOptions
    );

    client.start().catch(reason => {
        window.showWarningMessage(`Failed to run SuperHTML Language Server: ${reason}`);
    });

    context.subscriptions.push(
        languages.registerDocumentFormattingEditProvider(
            [{ scheme: "file", language: "html" }],
            new SuperFormatProvider(client),
        ),
        languages.registerDocumentRangeFormattingEditProvider(
            [{ scheme: "file", language: "html" }],
            new SuperFormatProvider(client),
        ),
    );
}

export function deactivate(): Thenable<void> | undefined {
    if (!client) {
        return undefined;
    }
    return client.stop();
}
