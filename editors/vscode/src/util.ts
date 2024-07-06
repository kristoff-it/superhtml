import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { window, workspace } from "vscode";
import which from "which";

export const isWindows = process.platform === "win32";

export function getExePath(exePath: string | null, exeName: string, optionName: string): string {
    // Allow passing the ${workspaceFolder} predefined variable
    // See https://code.visualstudio.com/docs/editor/variables-reference#_predefined-variables
    if (exePath && exePath.includes("${workspaceFolder}")) {
        // We choose the first workspaceFolder since it is ambiguous which one to use in this context
        if (workspace.workspaceFolders && workspace.workspaceFolders.length > 0) {
            // older versions of Node (which VSCode uses) may not have String.prototype.replaceAll
            exePath = exePath.replace(/\$\{workspaceFolder\}/gm, workspace.workspaceFolders[0].uri.fsPath);
        }
    }

    if (!exePath) {
        exePath = which.sync(exeName, { nothrow: true });
    } else if (exePath.startsWith("~")) {
        exePath = path.join(os.homedir(), exePath.substring(1));
    } else if (!path.isAbsolute(exePath)) {
        exePath = which.sync(exePath, { nothrow: true });
    }

    let message;
    if (!exePath) {
        message = `Could not find ${exeName} in PATH`;
    } else if (!fs.existsSync(exePath)) {
        message = `\`${optionName}\` ${exePath} does not exist`
    } else {
        try {
            fs.accessSync(exePath, fs.constants.R_OK | fs.constants.X_OK);
            return exePath;
        } catch {
            message = `\`${optionName}\` ${exePath} is not an executable`;
        }
    }
    window.showErrorMessage(message);
    throw Error(message);
}

export function getSuperPath(): string {
    const configuration = workspace.getConfiguration("super");
    const superPath = configuration.get<string>("path");
    return getExePath(superPath, "super", "super.path");
}

