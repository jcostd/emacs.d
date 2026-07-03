;;; misc-scaffold.el --- Scaffold Projects -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jacopo Costantini
;;
;; Author: Jacopo Costantini <jacopocostantini32@gmail.com>
;; License: GNU General Public License version 3 (or later)

;;; Commentary:
;;
;; Project scaffolding

;;; Code:

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

(provide 'misc-scaffold)

;;; misc-scaffold.el ends here
