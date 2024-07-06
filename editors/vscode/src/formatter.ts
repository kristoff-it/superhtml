import * as vscode from "vscode";
import { TextEdit } from "vscode";

import {
    DocumentFormattingRequest,
    DocumentRangeFormattingRequest,
    LanguageClient,
    TextDocumentIdentifier
} from 'vscode-languageclient/node';

export class SuperFormatProvider implements vscode.DocumentFormattingEditProvider, vscode.DocumentRangeFormattingEditProvider {
    private _client: LanguageClient;

    constructor(client: LanguageClient) {
        this._client = client;
    }

    provideDocumentFormattingEdits(document: vscode.TextDocument, options: vscode.FormattingOptions, token: vscode.CancellationToken): vscode.ProviderResult<vscode.TextEdit[]> {
        return this._client.sendRequest(
            DocumentFormattingRequest.type,
            { textDocument: TextDocumentIdentifier.create(document.uri.toString()), options: options },
            token,
        ) as Promise<TextEdit[] | null>;
    }

    provideDocumentRangeFormattingEdits(document: vscode.TextDocument, range: vscode.Range, options: vscode.FormattingOptions, token: vscode.CancellationToken): vscode.ProviderResult<vscode.TextEdit[]> {
        return this._client.sendRequest(
            DocumentRangeFormattingRequest.type,
            { textDocument: TextDocumentIdentifier.create(document.uri.toString()), range: range, options: options },
            token,
        ) as Promise<TextEdit[] | null>;
    }
}
