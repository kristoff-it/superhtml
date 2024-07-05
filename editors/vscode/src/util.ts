import * as cp from "child_process";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { window, workspace } from "vscode";
import which from "which";

export const isWindows = process.platform === "win32";

/** Options for execCmd */
export interface ExecCmdOptions {
    /** The project root folder for this file is used as the cwd of the process */
    fileName?: string;
    /** Any arguments */
    cmdArguments?: string[];
    /** Shows a message if an error occurs (in particular the command not being */
    /* found), instead of rejecting. If this happens, the promise never resolves */
    showMessageOnError?: boolean;
    /** Called after the process successfully starts */
    onStart?: () => void;
    /** Called when data is sent to stdout */
    onStdout?: (data: string) => void;
    /** Called when data is sent to stderr */
    onStderr?: (data: string) => void;
    /** Called after the command (successfully or unsuccessfully) exits */
    onExit?: () => void;
    /** Text to add when command is not found (maybe helping how to install) */
    notFoundText?: string;
}

/** Type returned from execCmd. Is a promise for when the command completes
 *  and also a wrapper to access ChildProcess-like methods.
 */
export interface ExecutingCmd
    extends Promise<{ stdout: string; stderr: string }> {
    /** The process's stdin */
    stdin: NodeJS.WritableStream;
    /** End the process */
    kill();
    /** Is the process running */
    isRunning: boolean; // tslint:disable-line
}

/** Executes a command. Shows an error message if the command isn't found */
export function execCmd
    (cmd: string, options: ExecCmdOptions = {}): ExecutingCmd {

    const { fileName, onStart, onStdout, onStderr, onExit } = options;
    let childProcess, firstResponse = true, wasKilledbyUs = false;

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const executingCmd: any = new Promise((resolve, reject) => {
        const cmdArguments = options ? options.cmdArguments : [];

        childProcess =
            cp.execFile(cmd, cmdArguments, { cwd: detectProjectRoot(fileName || workspace.rootPath + "/fakeFileName"), maxBuffer: 10 * 1024 * 1024 }, handleExit);


        childProcess.stdout.on("data", (data: Buffer) => {
            if (firstResponse && onStart) {
                onStart();
            }
            firstResponse = false;
            if (onStdout) {
                onStdout(data.toString());
            }
        });

        childProcess.stderr.on("data", (data: Buffer) => {
            if (firstResponse && onStart) {
                onStart();
            }
            firstResponse = false;
            if (onStderr) {
                onStderr(data.toString());
            }
        });

        function handleExit(err: Error, stdout: string, stderr: string) {
            executingCmd.isRunning = false;
            if (onExit) {
                onExit();
            }
            if (!wasKilledbyUs) {
                if (err) {
                    if (options.showMessageOnError) {
                        const cmdName = cmd.split(" ", 1)[0];
                        const cmdWasNotFound =
                            // Windows method apparently still works on non-English systems
                            (isWindows &&
                                err.message.includes(`'${cmdName}' is not recognized`)) ||
                            // eslint-disable-next-line @typescript-eslint/no-explicit-any
                            (!isWindows && (<any>err).code === 127);

                        if (cmdWasNotFound) {
                            const notFoundText = options ? options.notFoundText : "";
                            window.showErrorMessage(
                                `${cmdName} is not available in your path. ` + notFoundText,
                            );
                        } else {
                            window.showErrorMessage(err.message);
                        }
                    } else {
                        reject(err);
                    }
                } else {
                    resolve({ stdout: stdout, stderr: stderr });
                }
            }
        }
    });
    executingCmd.stdin = childProcess.stdin;
    executingCmd.kill = killProcess;
    executingCmd.isRunning = true;

    return executingCmd as ExecutingCmd;

    function killProcess() {
        wasKilledbyUs = true;
        if (isWindows) {
            cp.spawn("taskkill", ["/pid", childProcess.pid.toString(), "/f", "/t"]);
        } else {
            childProcess.kill("SIGINT");
        }
    }
}

const buildFile = "build.zig";

export function findProj(dir: string, parent: string): string {
    if (dir === "" || dir === parent) {
        return "";
    }
    if (fs.lstatSync(dir).isDirectory()) {
        const build = path.join(dir, buildFile);
        if (fs.existsSync(build)) {
            return dir;
        }
    }
    return findProj(path.dirname(dir), dir);
}

export function detectProjectRoot(fileName: string): string {
    const proj = findProj(path.dirname(fileName), "");
    if (proj !== "") {
        return proj;
    }
    return undefined;
}

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

