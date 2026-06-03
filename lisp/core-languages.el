;;; core-languages.el --- Syntax, LSP and Grammars -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jacopo Costantini
;;
;; Author: Jacopo Costantini <jacopocostantini32@gmail.com>
;; License: GNU General Public License version 3 (or later)

;;; Commentary:
;;
;; Consolidates programming language behaviors, LSP (Eglot) settings,
;; and Tree-sitter grammar management.

;;; Code:

;;; Tree-sitter

(setq treesit-language-source-alist
      '((go         "https://github.com/tree-sitter/tree-sitter-go"         "v0.23.4")
        (ruby       "https://github.com/tree-sitter/tree-sitter-ruby"       "v0.23.1")
        (json       "https://github.com/tree-sitter/tree-sitter-json"       "v0.24.8")
        (css        "https://github.com/tree-sitter/tree-sitter-css"        "v0.23.2")
        (javascript "https://github.com/tree-sitter/tree-sitter-javascript" "v0.23.1")
        (yaml       "https://github.com/ikatyang/tree-sitter-yaml"          "v0.5.0")
        (dockerfile "https://github.com/camdencheek/tree-sitter-dockerfile" "v0.2.0")
        (c          "https://github.com/tree-sitter/tree-sitter-c"          "v0.23.6")
        (cpp        "https://github.com/tree-sitter/tree-sitter-cpp"        "v0.23.4")))

(setq major-mode-remap-alist
      '((ruby-mode	. ruby-ts-mode)
        (js-json-mode	. json-ts-mode)
        (css-mode	. css-ts-mode)
        (js-mode	. js-ts-mode)
        (c-mode		. c-ts-mode)
        (c++-mode	. c++-ts-mode)
	(c-or-c++-mode	. c-or-c++-ts-mode)))

(defun core-treesit-auto-install ()
  "Compile and install missing Tree-sitter grammars."
  (interactive)
  (dolist (lang (mapcar #'car treesit-language-source-alist))
    (unless (treesit-language-available-p lang)
      (message "Compiling grammar: %s" lang)
      (treesit-install-language-grammar lang))))

;;; LSP (Eglot)

(setq eglot-autoshutdown t
      eglot-sync-connect 0
      eglot-extend-to-xref t
      eglot-send-changes-idle-time 0.1
      eglot-ignored-server-capabilities '(:documentOnTypeFormattingProvider))

(with-eval-after-load 'eglot
  (fset #'jsonrpc--log-event #'ignore)
  (add-to-list 'eglot-stay-out-of 'font-lock)

  (defun core--eglot-format-on-save ()
    (when (eglot-managed-p)
      (ignore-errors (eglot-format-buffer))))

  (defun core--eglot-organize-imports-on-save ()
    (when (eglot-managed-p)
      (ignore-errors
        (eglot-code-action-organize-imports (point-min) (point-max)))))

  ;; C/C++
  (add-to-list 'eglot-server-programs
               '((c-ts-mode c++-ts-mode)
		 . ("clangd"
                    "--background-index"
                    "--pch-storage=memory"
                    "--clang-tidy"
                    "--header-insertion=iwyu"
                    "--completion-style=bundled"
		    "--fallback-style=LLVM")))

  ;; GO
  (add-to-list 'eglot-server-programs
               '((go-ts-mode go-mod-ts-mode go-work-ts-mode)
		 . ("gopls"
		    :initializationOptions
                    (:staticcheck t :gofumpt t))))
  ;; RUBY
  (add-to-list 'eglot-server-programs
	       '((ruby-mode ruby-ts-mode) "ruby-lsp")))

;;; Shared Styles

(defun core--apply-pike-style ()
  "Applies Rob Pike's standard: 8-width hardware tabs."
  (setq-local indent-tabs-mode t)
  (setq-local tab-width 8))

(defun core--apply-lsp-setup ()
  "Applies format and organize import on save"
  (add-hook 'before-save-hook #'core--eglot-format-on-save 10 t)
  (add-hook 'before-save-hook #'core--eglot-organize-imports-on-save nil t))

;;; Languages

;; Shell

(add-hook 'after-save-hook #'executable-make-buffer-file-executable-if-script-p)

;; Go configuration

(defun core--apply-golang-setup ()
  "Golang editor configuration."
  (eglot-ensure)
  (core--apply-pike-style)
  (core--apply-lsp-setup))

(add-to-list 'auto-mode-alist '("\\.go\\'" . go-ts-mode))
(add-to-list 'auto-mode-alist '("/go\\.mod\\'" . go-ts-mode))
(add-to-list 'auto-mode-alist '("/go\\.work\\'" . go-ts-mode))

(add-hook 'go-ts-mode-hook #'core--apply-golang-setup)

;; C/C++ configuration

(defun core--apply-c-c++-setup ()
  "C/C++ editor configuration."
  (eglot-ensure)
  (core--apply-pike-style)
  (core--apply-lsp-setup))

(setq c-ts-mode-indent-style 'k&r)
(setq c-ts-mode-indent-offset 8)

(add-hook 'c-ts-mode-hook #'core--apply-c-c++-setup)
(add-hook 'c++-ts-mode-hook #'core--apply-c-c++-setup)
(add-hook 'c-or-c++-ts-mode-hook #'core--apply-c-c++-setup)

;; Ruby configuration

(defun core--apply-ruby-setup ()
  "Ruby editor configuration."
  (eglot-ensure)
  (core--apply-lsp-setup))

(add-hook 'ruby-ts-mode-hook #'core--apply-ruby-setup)

;; Javascript configuration

(add-to-list 'auto-mode-alist '("\\.m?js\\'" . js-ts-mode))

;; YAML configuration

(add-to-list 'auto-mode-alist '("\\.ya?ml\\'" . yaml-ts-mode))

;; JSON configuration

(add-to-list 'auto-mode-alist '("\\.json\\'" . json-ts-mode))

;; Docker files configuration

(add-to-list 'auto-mode-alist '("\\(?:Dockerfile\\(?:\\..*\\)?\\|\\.[Dd]ockerfile\\)\\'" . dockerfile-ts-mode))

;; Web (Fallback)

(use-package web-mode
  :ensure t
  :mode (("\\.erb\\'"  . web-mode)
         ("\\.html?\\'" . web-mode)
         ("\\.[jt]sx\\'" . web-mode))
  :custom
  (web-mode-markup-indent-offset 2)
  (web-mode-css-indent-offset 2)
  (web-mode-code-indent-offset 2)
  (web-mode-enable-auto-pairing t)
  (web-mode-enable-current-element-highlight nil))

;;; Project scaffolding

;; C/C++ scaffold
(defun core-scaffold-c-project (dir type)
  "Scaffold new C or C++ TYPE project in DIR.
Create optimal .clangd and .clang-format files for Eglot, following Rob Pike/Go style."
  (interactive
   (list (read-directory-name "Project directory name: ")
         (completing-read "Language " '("C" "C++"))))
  (make-directory dir t)

  (with-temp-file (expand-file-name ".clangd" dir)
    (insert "CompileFlags:\n  Add: [-Wall, -Wextra, -Wpedantic]\n---\nIf:\n  PathMatch: .*\\."
            (if (string= type "C") "c\n" "(cpp|cc|cxx|hpp|h)\n")
            "CompileFlags:\n  Add: ["
            (if (string= type "C") "-std=c11" "-std=c++17")
            "]\n"))

  (let ((clang-format-content
         "BasedOnStyle: LLVM
UseTab: ForIndentation
IndentWidth: 8
TabWidth: 8
BreakBeforeBraces: Attach
AllowShortIfStatementsOnASingleLine: false
AllowShortLoopsOnASingleLine: false
AllowShortBlocksOnASingleLine: false
AllowShortFunctionsOnASingleLine: None
IndentCaseLabels: false
PointerAlignment: Right
ColumnLimit: 100\n"))
    (with-temp-file (expand-file-name ".clang-format" dir)
      (insert clang-format-content)))

  (let* ((ext (if (string= type "C") "c" "cpp"))
         (code (if (string= type "C")
                   "#include <stdio.h>\n\nint main(void) {\n\tprintf(\"Hello, World!\\n\");\n\treturn 0;\n}\n"
                 "#include <iostream>\n\nint main() {\n\tstd::cout << \"Hello, World!\\n\";\n\treturn 0;\n}\n"))
         (main-file (expand-file-name (concat "main." ext) dir)))
    (with-temp-file main-file (insert code))
    (find-file main-file)
    (message "Project %s initialized in %s!" type dir)))

;; Go scaffold
(defun core-scaffold-go-project (dir mod-name)
  "Scaffold a Go module in DIR with name MOD-NAME."
  (interactive
   (list (read-directory-name "Project directory name: ")
         (read-string "Module name (es. github.com/user/repo): ")))
  (make-directory dir t)

  (let ((default-directory dir))
    (shell-command (format "go mod init %s" (shell-quote-argument mod-name)))

    (let ((main-file (expand-file-name "main.go" dir)))
      (with-temp-file main-file
        (insert "package main\n\nimport \"fmt\"\n\nfunc main() {\n\tfmt.Println(\"Hello, World!\")\n}\n"))
      (find-file main-file)
      (message "Go module '%s' initialized in %s!" mod-name dir))))

(provide 'core-languages)
;;; core-languages.el ends here
