import * as path from 'path';
import { workspace, ExtensionContext, window, languages } from 'vscode';
import { SuperFormatProvider, SuperRangeFormatProvider } from './formatter';

import {
	LanguageClient,
	LanguageClientOptions,
	ServerOptions
} from 'vscode-languageclient/node';

let client: LanguageClient;

const logChannel = window.createOutputChannel("super");

export function activate(context: ExtensionContext) {
    // context.subscriptions.push(
    //     languages.registerDocumentFormattingEditProvider(
    //         [{ scheme: "file", language: "super"}],
    //         new SuperFormatProvider(logChannel),
    //     ),
    //   );
    //   context.subscriptions.push(
    //     languages.registerDocumentRangeFormattingEditProvider(
    //         [{ scheme: "file", language: "super"}],
    //         new SuperRangeFormatProvider(logChannel),
    //     ),
    //   );


	// If the extension is launched in debug mode then the debug server options are used
	// Otherwise the run options are used
	const serverOptions: ServerOptions = {
	 	run: { command: "super", args: ["lsp"] },
  	debug: { command: "super", args: ["lsp"] },
	};

	// Options to control the language client
	const clientOptions: LanguageClientOptions = {
		// Register the server for plain text documents
        documentSelector: [
            { scheme: "file", language: 'html' },
            { scheme: "file", language: 'super' },
        ],
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
    }).then(() => {
        client.getFeature("textDocument/formatting").clear();
    });
}

export function deactivate(): Thenable<void> | undefined {
	if (!client) {
		return undefined;
	}
	return client.stop();
}
