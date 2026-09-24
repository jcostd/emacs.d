;;; init.el --- Core configuration (Emacs 30.2) -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jacopo Costantini

;; Author: Jacopo Costantini <jacopocostantini32@gmail.com>
;; License: GNU General Public License version 3 (or later)

;;; Commentary:
;; Acme philosophy: text is text.  Built-in over external.
;; Structure via regexp font-lock; no tree-sitter by design.
;; Sections follow boot order.  Modes are switched on last.

;;; Code:

(setq user-full-name "Jacopo Costantini")
(setq user-mail-address "jacopocostantini32@gmail.com")

;;; ENGINE

(prefer-coding-system 'utf-8)

;; LSP throughput.  Both knobs, or neither.
(setq read-process-output-max (* 4 1024 1024)
      process-adaptive-read-buffering nil)

(setq redisplay-skip-fontification-on-input t  ; no font-lock mid-keystroke
      ;; abbreviated: trusted-content-p compares against ~/..., not /Users/...
      trusted-content
      (list (abbreviate-file-name
             (file-name-as-directory (file-truename user-emacs-directory)))))

;;; PACKAGES
;; Activate light, select last: custom.el loads in between and
;; must not have the last word on package-selected-packages.

(require 'package)
(package-activate-all)

;; lisp/ must precede load-theme: the themes require ascetic-theme.
(add-to-list 'load-path (locate-user-emacs-file "lisp"))
(add-to-list 'custom-theme-load-path (locate-user-emacs-file "themes"))

(setq custom-file (locate-user-emacs-file "custom.el"))
(dolist (f '("local" "custom"))
  (load (locate-user-emacs-file f) t t))

(setq package-selected-packages '(go-mode yaml-mode web-mode))
(unless (seq-every-p #'package-installed-p package-selected-packages)
  (package-initialize)
  (package-install-selected-packages t))

;;; THEME
;; Light is registered but not enabled: toggle-theme needs both
;; variants known, and exactly one active.

(load-theme 'ascetic-light t t)
(load-theme 'ascetic-dark t)

(defun core-toggle-theme ()
  "Swap ascetic variants.  Ours: no confirmation."
  (interactive)
  (theme-choose-variant t))
(keymap-global-set "<f5>" #'core-toggle-theme)

(setq mode-line-compact t
      inhibit-startup-screen t
      initial-scratch-message ";; Happy Hacking!\n\n"
      use-short-answers t
      ring-bell-function #'ignore
      highlight-nonselected-windows nil)

(setq-default cursor-in-non-selected-windows nil)

;;; EDITING POLICY
;; Chords on letters and on unshifted punctuation only: everything
;; else costs a Shift on the IT layout.

(require 'ascetic-edit)

;; 29: duplicate-dwim already knows region, rectangle and line.
;; 30: land on the copy, same column, ready to edit in place.
(setq duplicate-line-final-position   -1
      duplicate-region-final-position 1)

(keymap-global-set "M-i"      ascetic-edit-inner-map)
(keymap-global-set "M-e"      #'ascetic-edit-expand)
(keymap-global-set "C-a"      #'ascetic-edit-home)
(keymap-global-set "C-o"      #'ascetic-edit-open-below)
(keymap-global-set "M-o"      #'ascetic-edit-open-above)
(keymap-global-set "M-<up>"   #'ascetic-edit-move-up)
(keymap-global-set "M-<down>" #'ascetic-edit-move-down)

;; C-c LETTER is the user's by convention.  Keep it that way.
(keymap-global-set "C-c d" #'duplicate-dwim)
(keymap-global-set "C-c D" #'ascetic-edit-duplicate-and-comment)
(keymap-global-set "C-c k" #'ascetic-edit-delete)
(keymap-global-set "C-c s" #'ascetic-edit-surround)
(keymap-global-set "C-c c" #'ascetic-edit-resurround)
(keymap-global-set "C-c u" #'ascetic-edit-unsurround)
(keymap-global-set "C-c a" #'ascetic-edit-number-increase)
(keymap-global-set "C-c x" #'ascetic-edit-number-decrease)

;; C-/ and C-_ need Shift on the IT layout; C-. and C-, are not ASCII,
;; so they die in a TTY, and org-mode claims C-, anyway.  C-z only
;; iconifies a frame here -- C-x C-z still suspends.
(keymap-global-set "C-z"   #'undo)
(keymap-global-set "C-M-z" #'undo-redo)

(setq save-interprogram-paste-before-kill t
      kill-do-not-save-duplicates t
      require-final-newline t
      scroll-conservatively 101          ; no vscroll jumps
      auto-window-vscroll nil
      repeat-exit-timeout 3
      repeat-exit-key (kbd "RET")
      undo-limit        (* 13 160000)
      undo-strong-limit (* 13 240000)
      undo-outer-limit  (* 13 24000000))

(setq-default fill-column 80)
(add-hook 'text-mode-hook #'auto-fill-mode)

;;; DIAGNOSTICS
;; Eglot brings flymake with it; elisp has checkers of its own and
;; nothing was switching them on.  No fringe: the wave is the signal.

(setq flymake-no-changes-timeout 0.5
      flymake-indicator-type nil)

;; Byte-compile checking runs the buffer's own macros: it needs a
;; file, and a trusted one.  *scratch* is neither.
(defun core--elisp-flymake ()
  (when buffer-file-name (flymake-mode 1)))
(add-hook 'emacs-lisp-mode-hook #'core--elisp-flymake)

(keymap-global-set "C-c n" #'flymake-goto-next-error)
(keymap-global-set "C-c p" #'flymake-goto-prev-error)

;;; SHELL
;; The plumber pipes into processes.  These are that side of the pipe.

(setq shell-command-prompt-show-cwd t
      async-shell-command-display-buffer nil   ; output lands when it lands
      shell-kill-buffer-on-exit t
      comint-prompt-read-only t
      comint-input-ignoredups t
      comint-scroll-to-bottom-on-input 'this)

;; Trim only files born clean: other people's diffs stay clean.
;; Show trailing whitespace either way.
(defun core--prog-whitespace ()
  (setq show-trailing-whitespace t)
  (unless (save-excursion
            (goto-char (point-min))
            (re-search-forward "[ \t]+$" nil t))
    (add-hook 'before-save-hook #'delete-trailing-whitespace nil t)))
(add-hook 'prog-mode-hook #'core--prog-whitespace)

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
      save-place-limit 500
      recentf-max-saved-items 100
      recentf-keep '(file-remote-p file-readable-p)
      auto-revert-verbose nil
      global-auto-revert-non-file-buffers t
      uniquify-buffer-name-style 'forward
      uniquify-ignore-buffers-re "^\\*")

(setq tramp-default-method "ssh")
(with-eval-after-load 'tramp
  (setq vc-ignore-dir-regexp
        (format "\\(%s\\)\\|\\(%s\\)" vc-ignore-dir-regexp tramp-file-name-regexp)))

(keymap-global-set "C-c r" #'rename-visited-file)

;;; COMPLETION

(setq completion-styles '(basic partial-completion substring)
      completion-auto-help nil
      completion-category-defaults nil
      completion-ignore-case t
      read-buffer-completion-ignore-case t
      read-file-name-completion-ignore-case t
      read-extended-command-predicate #'command-completion-default-include-p
      enable-recursive-minibuffers t
      completion-preview-minimum-symbol-length 2
      completion-preview-idle-delay 0.15)

;; Shield the prompt from the cursor.
(setq minibuffer-prompt-properties
      '(read-only t cursor-intangible t face minibuffer-prompt))
(add-hook 'minibuffer-setup-hook #'cursor-intangible-mode)

(require 'ascetic-read)
(require 'ascetic-plumber)

(with-eval-after-load 'completion-preview
  ;; M-i is ours: text objects
  (keymap-unset completion-preview-active-mode-map "M-i" t)
  (keymap-set completion-preview-active-mode-map "M-n" #'completion-preview-next-candidate)
  (keymap-set completion-preview-active-mode-map "M-p" #'completion-preview-prev-candidate)
  (keymap-set completion-preview-active-mode-map "M-TAB" #'completion-preview-complete))

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
      `((,(rx "*" (or "Help" "Apropos" "info" "Messages" "Warnings"
                      "Compile-Log" "compilation" "grep" "xref"
                      (seq (or "Man " "Plumber") (* nonl)))
              "*")
         (display-buffer-reuse-window display-buffer-at-bottom)
         (window-height . 0.3)
         (reusable-frames . visible))))

(keymap-global-set "C-x C-b" #'ibuffer)

;;; TOOLS

(setq Man-notify-method 'aggressive)
(keymap-global-set "C-c m" #'man)

(keymap-global-set "C-c b" #'recompile)   ; the one you press fifty times
(keymap-global-set "C-c B" #'compile)     ; the one that asks

(setq display-line-numbers-width 3
      display-line-numbers-grow-only t
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

(setq wdired-allow-to-change-permissions t)

;; The layout is immutable, echo area included.
(setq eldoc-echo-area-use-multiline-p nil
      eldoc-idle-delay 0.2)

;; 29: show the opener without splitting anything.
(setq show-paren-context-when-offscreen 'overlay)

(setq savehist-additional-variables '(kill-ring search-ring regexp-search-ring))

;;; LSP

(setq eglot-autoshutdown t
      eglot-sync-connect 0
      eglot-extend-to-xref t
      eglot-report-progress nil
      eglot-send-changes-idle-time 0.1
      eglot-ignored-server-capabilities '(:documentOnTypeFormattingProvider)
      eglot-events-buffer-config '(:size 0 :format full))

(with-eval-after-load 'eglot
  (add-to-list 'eglot-stay-out-of 'font-lock)

  (defun core--eglot-format ()
    ;; gofmt is law; elsewhere only where the project says how
    (when (and (eglot-managed-p)
               (or (derived-mode-p 'go-mode)
                   (locate-dominating-file default-directory ".clang-format")))
      (with-demoted-errors "eglot-format: %S" (eglot-format-buffer))))

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

;; Go: hardware tabs are the default; gofmt does the rest.
;; C gets "linux", which is already K&R with 8-wide tabs.
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
                editorconfig-mode
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
