;;; init.el --- Core configuration (Emacs 30.2) -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jacopo Costantini

;; Author: Jacopo Costantini <jacopocostantini32@gmail.com>
;; License: GNU General Public License version 3 (or later)

;;; Commentary:
;; Acme philosophy: text is text.  Built-in over external.
;; Structure via regexp font-lock; no tree-sitter by design.
;; Sections follow boot order.  Modes are switched on last.

;;; Code:

;;; ENGINE

(prefer-coding-system 'utf-8)

;; LSP throughput.  Both knobs, or neither.
(setq read-process-output-max (* 4 1024 1024)
      process-adaptive-read-buffering nil)

(setq redisplay-skip-fontification-on-input t  ; no font-lock mid-keystroke
      ffap-machine-p-known 'reject             ; no DNS from ffap
      trusted-content (list user-emacs-directory))

;;; PACKAGES

(require 'package)
(setq package-selected-packages '(go-mode yaml-mode web-mode))
(package-initialize)
(package-install-selected-packages t)

;; lisp/ must precede load-theme: the themes require ascetic-theme.
(add-to-list 'load-path (locate-user-emacs-file "lisp"))
(add-to-list 'custom-theme-load-path (locate-user-emacs-file "themes"))

;;; LOCAL FILES
;; Custom loads here, not last: last loader wins, and
;; package-selected-packages is a defcustom.

(defun core-load-if-exists (file)
  (when (file-exists-p file) (load file nil t)))

(setq custom-file (locate-user-emacs-file "custom.el"))

(dolist (f '("local.el" "secrets.el" "custom.el"))
  (core-load-if-exists (locate-user-emacs-file f)))

;;; THEME
;; Light is registered but not enabled: toggle-theme needs both
;; variants known, and exactly one active.

(setq custom-safe-themes t)
(load-theme 'ascetic-light t t)
(load-theme 'ascetic-dark t)

(keymap-global-set "<f5>" #'toggle-theme)

(setq mode-line-compact t
      inhibit-startup-screen t
      initial-scratch-message ";; Happy Hacking!\n\n"
      use-short-answers t
      ring-bell-function #'ignore
      highlight-nonselected-windows nil)

(setq-default cursor-in-non-selected-windows nil)

;;; EDITING

(require 'ascetic-edit)

;; C-c + letter is the user's; C-c + control char belongs to major modes.
(keymap-global-set "C-c d"        #'duplicate-dwim)
(keymap-global-set "C-c D"        #'ascetic-edit-duplicate-and-comment)
(keymap-global-set "M-<up>"       #'ascetic-edit-move-up)
(keymap-global-set "M-<down>"     #'ascetic-edit-move-down)
(keymap-global-set "C-<return>"   #'ascetic-edit-open-below)
(keymap-global-set "C-S-<return>" #'ascetic-edit-open-above)
(keymap-global-set "M-k"          #'ascetic-edit-delete)
(keymap-global-set "M-'"          #'ascetic-edit-surround)
(keymap-global-set "M-i"          ascetic-edit-inner-map)
(keymap-global-set "M-J"          #'delete-indentation)
(keymap-global-set "M-z"          #'zap-up-to-char)
(keymap-global-set "C-x K"        #'kill-current-buffer)

(setq save-interprogram-paste-before-kill t
      kill-do-not-save-duplicates t
      require-final-newline t
      sentence-end-double-space nil
      scroll-conservatively 101          ; no vscroll jumps
      auto-window-vscroll nil
      repeat-exit-timeout 3
      repeat-exit-key (kbd "RET")
      undo-limit        (* 13 160000)
      undo-strong-limit (* 13 240000)
      undo-outer-limit  (* 13 24000000))

(setq-default fill-column 80)
(add-hook 'text-mode-hook #'auto-fill-mode)

;; Ours only: other people's diffs stay clean.
(defun core--trim-on-save ()
  (add-hook 'before-save-hook #'delete-trailing-whitespace nil t))
(add-hook 'prog-mode-hook #'core--trim-on-save)

(dolist (cmd '(narrow-to-region upcase-region downcase-region))
  (put cmd 'disabled nil))

;;; FILES
;; Emacs 30 already keeps places, history, bookmarks, recentf, projects
;; and tramp state under `user-emacs-directory'.  Only redirect what
;; would otherwise land next to someone else's source.

(setq create-lockfiles nil               ; .#file symlinks break web bundlers
      backup-by-copying t
      backup-directory-alist `(("." . ,(locate-user-emacs-file "backups")))
      auto-save-file-name-transforms
      `((".*" ,(locate-user-emacs-file "auto-save-list/") t))
      delete-by-moving-to-trash t
      history-length 100
      save-place-limit 500
      recentf-max-saved-items 100
      recentf-keep '(file-remote-p file-readable-p)
      auto-revert-verbose nil
      global-auto-revert-non-file-buffers t
      uniquify-buffer-name-style 'forward
      uniquify-separator "/"
      uniquify-after-kill-buffer-p t
      uniquify-ignore-buffers-re "^\\*")

(setq tramp-default-method "ssh")
(with-eval-after-load 'tramp
  (setq vc-ignore-dir-regexp
        (format "\\(%s\\)\\|\\(%s\\)" vc-ignore-dir-regexp tramp-file-name-regexp)))

(keymap-global-set "C-c r" #'rename-visited-file)

;;; COMPLETION

(setq completion-styles '(basic partial-completion substring)
      completion-auto-help nil
      completions-detailed nil
      completion-cycle-threshold nil
      completion-category-defaults nil
      completion-category-overrides nil
      completion-ignore-case t
      read-buffer-completion-ignore-case t
      read-file-name-completion-ignore-case t
      read-extended-command-predicate #'command-completion-default-include-p
      enable-recursive-minibuffers t
      completion-preview-minimum-symbol-length 2
      completion-preview-idle-delay 0.15)

;; Shield the prompt from the cursor.
(setq minibuffer-prompt-properties
      '(read-only t intangible t cursor-intangible t face minibuffer-prompt))
(add-hook 'minibuffer-setup-hook #'cursor-intangible-mode)

(require 'ascetic-read)
(require 'ascetic-plumber)

(with-eval-after-load 'completion-preview
  ;; M-i belongs to core-edit-inner-map; a minor-mode map would steal it.
  (keymap-set completion-preview-active-mode-map "M-n" #'completion-preview-next-candidate)
  (keymap-set completion-preview-active-mode-map "M-p" #'completion-preview-prev-candidate)
  (keymap-set completion-preview-active-mode-map "C-;" #'completion-preview-complete))

;;; WINDOWS

(windmove-default-keybindings)

(setq switch-to-buffer-obey-display-actions t
      window-combination-resize t
      help-window-select t
      ibuffer-expert t
      ibuffer-show-empty-filter-groups nil
      ediff-diff-options "-w"
      ediff-window-setup-function #'ediff-setup-windows-plain
      ediff-split-window-function #'split-window-horizontally
      tab-bar-show 1
      tab-bar-close-button-show nil
      tab-bar-new-button-show nil
      tab-bar-new-tab-choice "*scratch*"
      tab-bar-tab-hints t
      tab-bar-format '(tab-bar-format-tabs))

(setq display-buffer-alist
      '(("\\*\\(Help\\|Apropos\\|info\\|Messages\\|Warnings\\|Compile-Log\\)\\*"
         (display-buffer-reuse-window display-buffer-at-bottom)
         (window-height . 0.3)
         (reusable-frames . visible))
        ;; compilation, grep, xref, and the plumber's sinks
        ("\\*\\(compilation\\|grep\\|xref\\|Plumber.*\\)\\*"
         (display-buffer-reuse-window display-buffer-at-bottom)
         (window-height . 0.3)
         (reusable-frames . visible))))

(keymap-global-set "C-x C-b" #'ibuffer)

;;; TOOLS

(setq display-line-numbers-width 3
      display-line-numbers-grow-only t
      isearch-lax-whitespace t
      isearch-lazy-count t
      lazy-count-prefix-format "[%s of %s] "
      grep-use-headings t                ; 30: hits grouped under a file heading
      project-mode-line t
      compilation-scroll-output t
      compilation-always-kill t
      compilation-skip-threshold 2
      compilation-ask-about-save nil
      compilation-hidden-output '("^make\\[[0-9]+\\]: .*\n")
      vc-follow-symlinks t
      vc-git-diff-switches '("--histogram"))

(add-hook 'prog-mode-hook #'display-line-numbers-mode)
(add-hook 'compilation-filter-hook #'ansi-color-compilation-filter)
(add-hook 'emacs-lisp-mode-hook #'outline-minor-mode)  ; ;;; headers fold

(with-eval-after-load 'project
  (add-to-list 'project-vc-extra-root-markers "go.mod"))

;; 29: .c <-> .h without ff-find-other-file.
(setq find-sibling-rules '(("\\([^/]+\\)\\.c\\'" "\\1.h")
                           ("\\([^/]+\\)\\.h\\'" "\\1.c")))
(keymap-global-set "C-x M-o" #'find-sibling-file)

;; -A shows dotfiles; --group-directories-first is GNU-only.
(setq dired-listing-switches (if (eq system-type 'gnu/linux)
                                 "-AFlbhv --group-directories-first"
                               "-AFlbhv")
      dired-omit-files "\\`\\.?#\\|\\`\\.\\.?\\'\\|\\.DS_Store\\'\\|\\.class\\'"
      dired-recursive-copies 'always
      dired-recursive-deletes 'always
      dired-dwim-target t)

(with-eval-after-load 'dired (require 'dired-x))
(add-hook 'dired-mode-hook #'dired-omit-mode)

;;; LSP

(setq eglot-autoshutdown t
      eglot-sync-connect 0
      eglot-extend-to-xref t
      eglot-report-progress nil
      eglot-send-changes-idle-time 0.1
      eglot-ignored-server-capabilities '(:documentOnTypeFormattingProvider)
      ;; 30: supported API, replaces the jsonrpc--log-event fset hack.
      eglot-events-buffer-config '(:size 0 :format full))

(with-eval-after-load 'eglot
  (add-to-list 'eglot-stay-out-of 'font-lock)

  (defun core--eglot-format ()
    (when (eglot-managed-p)
      (ignore-errors (eglot-format-buffer))))

  (defun core--eglot-organize-imports ()
    (when (eglot-managed-p)
      (ignore-errors
        (eglot-code-action-organize-imports (point-min) (point-max)))))

  (defun core-eglot-setup ()
    "Imports first, then format.  Depth orders them."
    (add-hook 'before-save-hook #'core--eglot-organize-imports 0 t)
    (add-hook 'before-save-hook #'core--eglot-format 10 t))

  (add-hook 'eglot-managed-mode-hook #'core-eglot-setup)

  (add-to-list 'eglot-server-programs
               '((c-mode c++-mode)
                 . ("clangd" "--background-index" "--pch-storage=memory"
                    "--clang-tidy" "--header-insertion=iwyu"
                    "--completion-style=bundled" "--fallback-style=LLVM")))

  (add-to-list 'eglot-server-programs
               '(go-mode . ("gopls" :initializationOptions
                            (:staticcheck t :gofumpt t))))

  (add-to-list 'eglot-server-programs '(ruby-mode . ("ruby-lsp"))))

;;; LANGUAGES

;; Go: hardware tabs, gofmt does the rest.
;; C gets "linux", which is already K&R with 8-wide tabs.
(defun core--go-style ()
  (setq-local indent-tabs-mode t tab-width 8))
(add-hook 'go-mode-hook #'core--go-style)

(setq c-default-style '((c-mode    . "linux")
                        (c++-mode  . "stroustrup")
                        (java-mode . "java")
                        (awk-mode  . "awk")
                        (other     . "linux")))

(add-hook 'after-save-hook #'executable-make-buffer-file-executable-if-script-p)

(setq web-mode-markup-indent-offset 2
      web-mode-css-indent-offset 2
      web-mode-code-indent-offset 2
      web-mode-enable-auto-pairing t
      web-mode-enable-current-element-highlight nil)

(add-to-list 'auto-mode-alist '("\\.erb\\'" . web-mode))
(add-to-list 'auto-mode-alist '("\\.[jt]sx\\'" . web-mode))

(setq tex-bibtex-command "biber")
(add-hook 'latex-mode-hook #'turn-on-reftex)

;;; MODES
;; Switched on last, so every variable is already set.

(dolist (mode '(delete-selection-mode
                electric-pair-mode
                global-subword-mode
                global-so-long-mode
                kill-ring-deindent-mode         ; 30: yank without parasite indent
                global-visual-wrap-prefix-mode  ; 30: native adaptive-wrap
                repeat-mode
                savehist-mode
                recentf-mode
                save-place-mode
                global-auto-revert-mode
                minibuffer-depth-indicate-mode
                ascetic-read-mode
                global-completion-preview-mode
                winner-mode
                tab-bar-mode))
  (funcall mode 1))

;;; init.el ends here
