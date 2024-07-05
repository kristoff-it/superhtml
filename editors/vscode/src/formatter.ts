import * as vscode from "vscode";
import { OutputChannel, TextEdit } from "vscode";
import { execCmd, getSuperPath } from "./util";

export class SuperFormatProvider implements vscode.DocumentFormattingEditProvider {
    private _channel: OutputChannel;

    constructor(logChannel: OutputChannel) {
        this._channel = logChannel;
    }

    provideDocumentFormattingEdits(
        document: vscode.TextDocument,
    ): Thenable<TextEdit[]> {
        const logger = this._channel;
        return superFormat(document)
            .then(({ stdout }) => {
                logger.clear();
                const lastLineId = document.lineCount - 1;
                const wholeDocument = new vscode.Range(
                    0,
                    0,
                    lastLineId,
                    document.lineAt(lastLineId).text.length,
                );
                return [new TextEdit(wholeDocument, stdout),];
            })
            .catch((reason) => {
                const config = vscode.workspace.getConfiguration("zig");

                logger.clear();
                logger.appendLine(reason.toString().replace("<stdin>", document.fileName));
                if (config.get<boolean>("revealOutputChannelOnFormattingError")) {
                    logger.show(true);
                }
                return null;
            });
    }
}

// Same as full document formatter for now
export class SuperRangeFormatProvider implements vscode.DocumentRangeFormattingEditProvider {
    private _channel: OutputChannel;
    constructor(logChannel: OutputChannel) {
        this._channel = logChannel;
    }

    provideDocumentRangeFormattingEdits(
        document: vscode.TextDocument,
    ): Thenable<TextEdit[]> {
        const logger = this._channel;
        return superFormat(document)
            .then(({ stdout }) => {
                logger.clear();
                const lastLineId = document.lineCount - 1;
                const wholeDocument = new vscode.Range(
                    0,
                    0,
                    lastLineId,
                    document.lineAt(lastLineId).text.length,
                );
                return [new TextEdit(wholeDocument, stdout),];
            })
            .catch((reason) => {
                const config = vscode.workspace.getConfiguration("zig");

                logger.clear();
                logger.appendLine(reason.toString().replace("<stdin>", document.fileName));
                if (config.get<boolean>("revealOutputChannelOnFormattingError")) {
                    logger.show(true);
                }
                return null;
            });
    }
}

function superFormat(document: vscode.TextDocument) {
    const superPath = getSuperPath();

    const options = {
        cmdArguments: ["fmt", "--stdin"],
        notFoundText: "Could not find super. Please add super to your PATH or specify a custom path to the super binary in your settings.",
    };
    const format = execCmd(superPath, options);

    format.stdin.write(document.getText());
    format.stdin.end();

    return format;
}
