;;; init.el --- My Core Configuration (Emacs 30.2) -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jacopo Costantini

;; Author: Jacopo Costantini <jacopocostantini32@gmail.com>
;; License: GNU General Public License version 3 (or later)

;;; Commentary:
;; Core configuration. Acme philosophy: text is text.
;; Predictability, speed, minimalism.
;; Native features > external bloatware.

;;; Code:

;;; BOOTSTRAP & ENGINE

(prefer-coding-system 'utf-8)

;; IPC/Network throughput. Critical for LSP/Eglot speed.
(setq read-process-output-max (* 4 1024 1024))

;; GC limits: allow 16MB allocations before pausing.
(add-hook 'emacs-startup-hook
          (lambda () (setq gc-cons-threshold (* 16 1024 1024))))

;; Defer major-mode hook execution on raw buffers.
(setq initial-major-mode 'fundamental-mode)

;; Anti-stutter: halt font-lock during rapid keystrokes.
(setq redisplay-skip-fontification-on-input t)

;; Network timeout avoidance.
(setq ffap-machine-p-known 'reject)

;;; PACKAGE & MODULE LOADER
(require 'package)

(setq package-selected-packages
	     '(go-mode
	       json-mode
	       yaml-mode
	       web-mode))

(package-initialize)
(package-install-selected-packages t)

;; Load external core modules & secrets
(defun core-load-if-exists (file)
  (when (file-exists-p file)
    (load file nil t)))

(core-load-if-exists
 (expand-file-name "local.el" user-emacs-directory)) ; machine local config

(core-load-if-exists
 (expand-file-name "secrets.el" user-emacs-directory)) ; user secrets

(setq custom-safe-themes t)
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))
(add-to-list 'custom-theme-load-path (expand-file-name "themes" user-emacs-directory))

(load-theme 'ascetic-light t t)
(load-theme 'ascetic-dark t)

(require 'core-editing)

;;; UI & MONOCHROME PHILOSOPHY

(setq mode-line-compact t)

(setq inhibit-startup-screen t
      inhibit-startup-message t
      initial-scratch-message ";; Happy Hacking!\n\n")

(setq use-short-answers t
      use-dialog-box nil)

(setq visible-bell nil
      ring-bell-function #'ignore)

(setq-default cursor-in-non-selected-windows nil)
(setq highlight-nonselected-windows nil)

;; highlight current line
(global-hl-line-mode 1)

;;; CORE EDITING PRIMITIVES

;; Clipboard rules
(setq save-interprogram-paste-before-kill t
      kill-do-not-save-duplicates t)

;; Formatting boundaries
(setq-default fill-column 80)
(add-hook 'text-mode-hook #'auto-fill-mode)
(add-hook 'before-save-hook #'delete-trailing-whitespace)
(setq sentence-end-double-space nil)

;; State management
(setq undo-limit (* 13 160000)
      undo-strong-limit (* 13 240000)
      undo-outer-limit (* 13 24000000))

;; Deterministic scrolling (no vscroll jumps)
(setq scroll-conservatively 101
      auto-window-vscroll nil)

;; Native minor modes
(delete-selection-mode 1)
(electric-pair-mode 1)
(global-subword-mode 1)
(global-so-long-mode 1)

;; Enable disabled native commands
(put 'narrow-to-region 'disabled nil)
(put 'upcase-region 'disabled nil)
(put 'downcase-region 'disabled nil)

;; repeat
(setq repeat-exit-timeout 3)
(setq repeat-exit-key (kbd "RET"))
(repeat-mode 1)

;;; FILESYSTEM & I/O

(defvar core-state-dir (expand-file-name "var/" user-emacs-directory))
(make-directory core-state-dir t)

(defun core-state-file (name)
  (expand-file-name name core-state-dir))

(dolist (dir '("backups"
               "auto-save-list"
               "tramp-auto-save"
	       "remember"
	       "url"
               "games/shared-score"
               "games/user-score"))
  (make-directory (expand-file-name dir core-state-dir) t))

(setq custom-file (core-state-file "custom.el")
      save-place-file (core-state-file "places")
      recentf-save-file (core-state-file "recentf")
      savehist-file (core-state-file "history")
      bookmark-default-file (core-state-file "bookmarks")
      project-list-file (core-state-file "projects")

      ;; DIARY
      diary-file (core-state-file "diary")

      ;; REMEMBER
      remember-data-directory (core-state-file "remember/")
      remember-data-file (core-state-file "notes")

      ;; EWW & URL
      eww-bookmarks-directory core-state-dir
      url-configuration-directory (core-state-file "url/")

      ;; GAMES
      shared-game-score-directory (core-state-file "games/shared-score")
      gamegrid-user-score-file-directory (core-state-file "games/user-score")

      ;; TRAMP
      tramp-persistency-file-name (core-state-file "tramp")
      tramp-auto-save-directory (core-state-file "tramp-auto-save/"))

;; Disable symlink lockfiles (.#file) - fatal for web bundlers
(setq create-lockfiles nil)

;; backups
(setq backup-by-copying t)
(setq backup-directory-alist `(("." . ,(core-state-file "backups"))))

;; autosave
(setq auto-save-list-file-prefix (core-state-file "auto-save-list/.saves-"))
(setq auto-save-file-name-transforms `((".*" ,(core-state-file "auto-save-list/") t)))

;; history tracking
(setq history-length 100)
(savehist-mode 1)

;; recent files
(setq recentf-keep '(file-remote-p file-readable-p))
(setq recentf-max-saved-items 100)
(recentf-mode 1)

;; save place
(setq save-place-limit 500)
(save-place-mode 1)

;; uniquify buffer names
(setq uniquify-buffer-name-style 'forward
      uniquify-separator "/"
      uniquify-after-kill-buffer-p t
      uniquify-ignore-buffers-re "^\\*")

(keymap-global-set "C-c r" #'rename-visited-file)

;; autorevert
(setq auto-revert-verbose nil)
(setq global-auto-revert-non-file-buffers t)
(global-auto-revert-mode 1)

;; remember
(keymap-global-set "C-x M-r" #'remember)
(with-eval-after-load 'remember
  (add-to-list 'remember-handler-functions 'remember-diary-extract-entries))

;; tramp
(setq tramp-default-method "ssh")
(with-eval-after-load 'tramp
  (setq vc-ignore-dir-regexp
	(format "\\(%s\\)\\|\\(%s\\)"
		vc-ignore-dir-regexp
		tramp-file-name-regexp)))

;;; BUFFER COMPLETION

(setq completion-styles '(basic partial-completion substring)
      completion-auto-help nil
      completions-detailed nil
      completion-cycle-threshold nil)

(setq completion-category-defaults nil
      completion-category-overrides nil)

(setq completion-ignore-case t
      read-buffer-completion-ignore-case t
      read-file-name-completion-ignore-case t
      read-extended-command-predicate #'command-completion-default-include-p)

(minibuffer-depth-indicate-mode)
(setq enable-recursive-minibuffers t)

;; Shield minibuffer prompt from cursor.
(setq minibuffer-prompt-properties '(read-only t intangible t cursor-intangible t face minibuffer-prompt))
(add-hook 'minibuffer-setup-hook #'cursor-intangible-mode)

(require 'ascetic-read)
(require 'ascetic-plumber)
(ascetic-read-mode 1)

;;; IN-BUFFER COMPLETION
(setq completion-preview-minimum-symbol-length 2)
(setq completion-preview-idle-delay 0.15)

(with-eval-after-load 'completion-preview
  (when (boundp 'completion-preview-active-mode-map)
    (keymap-set completion-preview-active-mode-map "M-n" #'completion-preview-next-candidate)
    (keymap-set completion-preview-active-mode-map "M-p" #'completion-preview-prev-candidate)
    (keymap-set completion-preview-active-mode-map "M-i" #'completion-preview-complete)))

(global-completion-preview-mode 1)

;; quick expansion
(keymap-global-set "M-/" #'hippie-expand)
(setq hippie-expand-try-functions-list
      '(try-expand-dabbrev
        try-expand-dabbrev-all-buffers
        try-expand-dabbrev-from-kill
        try-complete-file-name-partially
        try-complete-file-name))

;;; WINDOWS & WORKSPACES

;; window movements
(windmove-default-keybindings)

;; window history
(winner-mode 1)

(setq switch-to-buffer-obey-display-actions t
      window-combination-resize t
      help-window-select t)

;; window rules
(setq display-buffer-alist
 '(("\\*\\(Help\\|Apropos\\|info\\|Messages\\|Warnings\\|Compile-Log\\)\\*"
    (display-buffer-reuse-window display-buffer-at-bottom)
    (window-height . 0.3)
    (reusable-frames . visible))
   ;; Cattura *compilation*, ma anche *Plumber Stream* e *Plumber: ...*
   ("\\*\\(compilation\\|Plumber.*\\)\\*"
    (display-buffer-reuse-window display-buffer-at-bottom)
    (window-height . 0.3)
    (reusable-frames . visible))
   ("\\*Completions\\*"
    (display-buffer-reuse-window display-buffer-at-bottom)
    (window-height . 0.2))))

;; tab-bar
(keymap-global-set "M-[" #'tab-bar-history-back)
(keymap-global-set "M-]" #'tab-bar-history-forward)

(setq tab-bar-show 1
      tab-bar-close-button-show nil
      tab-bar-new-button-show nil
      tab-bar-new-tab-choice "*scratch*"
      tab-bar-tab-hints t
      tab-bar-format
      '(tab-bar-format-tabs
	tab-bar-format-align-right
	tab-bar-format-global))

(tab-bar-mode 1)
(tab-bar-history-mode 1)

;; ediff
(setq ediff-diff-options "-w"
      ediff-window-setup-function 'ediff-setup-windows-plain
      ediff-split-window-function 'split-window-horizontally)

;; ibuffer
(setq ibuffer-expert t
      ibuffer-show-empty-filter-groups nil)

(keymap-global-set "C-x C-b" #'ibuffer)

;;; DEV TOOLS & WORKFLOW

;; line number
(setq display-line-numbers-width 3)
(setq display-line-numbers-grow-only t)
(add-hook 'prog-mode-hook #'display-line-numbers-mode)

;; searching
(setq search-highlight t)
(setq isearch-lax-whitespace t)
(setq isearch-lazy-count t)
(setq lazy-count-prefix-format "[%s of %s] ")

;; dired
(setq dired-listing-switches "-AFlbhv --group-directories-first")
(setq dired-omit-files "^\\.?#\\|^\\.[a-zA-Z0-9]+\\|\\.DS_Store$\\|\\.class$")
(setq dired-recursive-copies 'always
      dired-recursive-deletes 'always
      delete-by-moving-to-trash t
      dired-dwim-target t)
(add-hook 'dired-mode-hook #'dired-omit-mode)

;; which key
(setq which-key-idle-delay 0.5)
(which-key-mode 1)

;; project.el
(setq project-mode-line t)
(with-eval-after-load 'project
  (add-to-list 'project-vc-extra-root-markers "go.mod"))

;; compilation
(setq compilation-scroll-output t
      compilation-always-kill t
      compilation-skip-threshold 2
      compilation-ask-about-save nil)

(add-hook 'compilation-filter-hook #'ansi-color-compilation-filter)

;; version control
(setq vc-follow-symlinks t
      vc-git-diff-switches '("--histogram"))

;; eglot lsp
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

  (defun core--apply-lsp-setup ()
    "Applies format and organize import on save"
    (add-hook 'before-save-hook #'core--eglot-format-on-save 10 t)
    (add-hook 'before-save-hook #'core--eglot-organize-imports-on-save nil t))

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

;;; Data/Text

;; LaTeX
(setq tex-bibtex-command "biber")

(add-hook 'latex-mode-hook 'turn-on-reftex)

(setq reftex-save-parse-info t
      reftex-use-multiple-selection-buffers t
      reftex-plug-into-AUCTeX nil
      reftex-bibliography-commands
      '("bibliography"
	"nobibliography"
	"addbibresource"))

;;; Languages

;; Shell
(add-hook 'after-save-hook #'executable-make-buffer-file-executable-if-script-p)

;; C/C++
(defun core--apply-pike-style ()
  "Applies Rob Pike's standard: 8-width hardware tabs."
  (setq-local indent-tabs-mode t)
  (setq-local tab-width 8))

(setq c-basic-offset 8)
(setq c-default-style '((c-mode		.	"k&r")
			(c++-mode	.	"stroustrup")
			(java-mode	.	"java")
			(awk-mode	.	"awk")
			(other		.	"gnu")))
(add-hook 'c-mode-hook #'core--apply-pike-style)

;; Golang
(add-hook 'go-mode-hook #'core--apply-pike-style)

;; Web
(setq web-mode-markup-indent-offset 2
      web-mode-css-indent-offset 2
      web-mode-code-indent-offset 2
      web-mode-enable-auto-pairing t
      web-mode-enable-current-element-highlight nil)
(add-to-list 'auto-mode-alist '("\\.erb\\'" . web-mode))
(add-to-list 'auto-mode-alist '("\\.[jt]sx\\'" . web-mode))

(require 'misc-scaffold)

;; Loaded last to ensure system modifications don't override manual config.
(when (file-exists-p custom-file)
  (load custom-file nil t))

;;; init.el ends here
