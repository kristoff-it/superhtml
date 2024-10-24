# Adding SuperHTML to Emacs via Eglot

With `eglot` being included with the core Emacs distribution since
version 29, you can add various language servers, including SuperHTML,
to Emacs fairly simply. Just ensure that `superhtml` is somewhere in
your `$PATH` and you should be able to use one of the forms below with
minimal modification.

## With `use-package`

```elisp
(use-package eglot
  :defer t
  :hook ((web-mode . eglot-ensure)
         ;; Add more modes as needed
		 )
  :config
  ;; ...
  (add-to-list 'eglot-server-programs '((web-mode :language-id "html") . ("superhtml" "lsp"))))
```

## Without `use-package`

```elisp
(require 'eglot)
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               `((web-mode :language-id "html") . ("superhtml" "lsp"))))
```

You can modify the `superhtml` path here as well. If you're not using
`web-mode` then you'll also want to substitute your preferred
mode. The `:language-id` property ensures that HTML is the
content-type passed to the language server, as `eglot` will send the
mode name (minus `-mode`) by default.
