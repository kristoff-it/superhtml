# BBEdit Support for SuperHTML LSP

Adding SuperHTML support to BBEdit only requires tweaking the existing settings
for HTML language support. [Existing support uses the `vscode-html-languageserver`](https://www.barebones.com/support/bbedit/lsp-notes.html#preconfigured), which is a NodeJS project. You can easily change that to SuperHTML by doing the following:

## Accessing the HTML language settings

  * Open the BBEdit preferences by accessing the "BBEdit" menu and then choose "Settings" (or via the keyboard `⌘+,` shortcuts).
  * From the settings window navigate to the "Languages" tab.
  * In this tab, choose the “Custom Settings” tab.
  * If you already have a custom configuration, you may edit it now. However, if you don’t have an item listed for HTML, click on the “+” dropdown and choose “HTML” from the list.
  * If you already have a custom configuration, you may edit it now. However, if you don’t have an item listed for HTML, click on the “+” dropdown and choose “HTML” from the list.
  * In this new sheet window, select the “Server” tab, clearing out the existing `html-languageserver` and `—stdio` boxes and filling in `superhtml` in the “Command” text box, and “lsp” in the “Arguments” box.
  * Once you’ve entered both of those items, you should see a green checkmark indicating that the server is ready to be used.
  * Click on “OK” and your settings will be applied. You should be able to open an HTML document, or create a new one, and SuperHTML will be used as the LSP for checking for errors and warnings.