;;; init.el --- Core configuration (Emacs 30.2) -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jacopo Costantini

;; Author: Jacopo Costantini <jacopocostantini32@gmail.com>
;; License: GNU General Public License version 3 (or later)

;;; Commentary:
;; Acme philosophy: text is text.  Built-in over external.  Structure via regexp
;; font-lock; no tree-sitter by design.  Sections follow boot order.

;;; Code:

(setq user-full-name "Jacopo Costantini"
      user-mail-address "jacopocostantini32@gmail.com")

;;; ENGINE

(setq redisplay-skip-fontification-on-input t
      ;; abbreviated: trusted-content-p matches ~/..., not the expansion
      trusted-content
      (list (abbreviate-file-name
             (file-name-as-directory (file-truename user-emacs-directory)))))

;;; PACKAGES
;; Activate cheap, select last: custom.el must not own the package list.

(require 'package)
(package-activate-all)

;; lisp/ must precede load-theme: the themes require ascetic-theme.
(add-to-list 'load-path (locate-user-emacs-file "lisp"))
(add-to-list 'custom-theme-load-path (locate-user-emacs-file "themes"))

(setq custom-file (locate-user-emacs-file "custom.el"))
(load custom-file t t)

(setq package-selected-packages '(go-mode yaml-mode web-mode))
(unless (seq-every-p #'package-installed-p package-selected-packages)
  (package-initialize)
  (package-install-selected-packages t))

;;; UI
;; Light is registered, not enabled: theme-choose-variant needs both
;; variants known and exactly one active.

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
      ring-bell-function #'ignore)
(setq-default cursor-in-non-selected-windows nil)

;;; EDITING POLICY
;; Chords on letters, and on punctuation the IT layout gives unshifted.

(require 'ascetic-edit)

(keymap-global-set "M-i"      ascetic-edit-inner-map)
(keymap-global-set "M-e"      #'ascetic-edit-expand)
(keymap-global-set "C-o"      #'ascetic-edit-open-below)
(keymap-global-set "M-o"      #'ascetic-edit-open-above)
(keymap-global-set "M-<up>"   #'ascetic-edit-move-up)
(keymap-global-set "M-<down>" #'ascetic-edit-move-down)

;; C-c LETTER: the user's, by convention.
(keymap-global-set "C-c d" #'duplicate-dwim)
(keymap-global-set "C-c D" #'ascetic-edit-duplicate-and-comment)
(keymap-global-set "C-c k" #'ascetic-edit-delete)
(keymap-global-set "C-c s" #'ascetic-edit-surround)
(keymap-global-set "C-c c" #'ascetic-edit-resurround)
(keymap-global-set "C-c u" #'ascetic-edit-unsurround)
(keymap-global-set "C-c a" #'ascetic-edit-number-increase)
(keymap-global-set "C-c x" #'ascetic-edit-number-decrease)

;; C-/ costs a Shift on IT, C-. dies in a TTY.  C-x C-z still suspends.
(keymap-global-set "C-z"   #'undo)
(keymap-global-set "C-M-z" #'undo-redo)

(setq duplicate-line-final-position   -1         ; 30: land on the copy
      duplicate-region-final-position 1
      show-paren-context-when-offscreen 'overlay ; 29: opener, no split
      save-interprogram-paste-before-kill t
      kill-do-not-save-duplicates t
      scroll-conservatively 101                  ; never recenter
      repeat-exit-timeout 3
      repeat-exit-key "RET")

(setq-default fill-column 80)
(add-hook 'text-mode-hook #'auto-fill-mode)

;; Numbered; trimmed only if born clean: other people's diffs stay clean.
(defun core--code-buffer ()
  (display-line-numbers-mode 1)
  (setq show-trailing-whitespace t)
  (unless (save-excursion
            (goto-char (point-min))
            (re-search-forward "[ \t]+$" nil t))
    (add-hook 'before-save-hook #'delete-trailing-whitespace nil t)))
(add-hook 'prog-mode-hook #'core--code-buffer)

;; yaml-mode is a text-mode: config, not prose.
(add-hook 'yaml-mode-hook #'turn-off-auto-fill)
(add-hook 'yaml-mode-hook #'core--code-buffer)

(dolist (cmd '(narrow-to-region upcase-region downcase-region))
  (put cmd 'disabled nil))

;;; DIAGNOSTICS

;; The layout is immutable, echo area included.
(setq eldoc-echo-area-use-multiline-p nil
      eldoc-idle-delay 0.2)

;; Byte-compiling runs the buffer's macros: trusted files only.
(defun core--elisp-flymake ()
  (when (trusted-content-p) (flymake-mode 1)))
(add-hook 'emacs-lisp-mode-hook #'core--elisp-flymake)

;; flymake appends itself to eldoc: the signature wins the one line.
;; Error first.
(defun core--flymake-eldoc-first ()
  (when flymake-mode
    (remove-hook 'eldoc-documentation-functions #'flymake-eldoc-function t)
    (add-hook 'eldoc-documentation-functions #'flymake-eldoc-function -90 t)))
(add-hook 'flymake-mode-hook #'core--flymake-eldoc-first)

(keymap-global-set "C-c n" #'flymake-goto-next-error)
(keymap-global-set "C-c p" #'flymake-goto-prev-error)

;;; SHELL

(setq shell-command-prompt-show-cwd t
      async-shell-command-display-buffer nil  ; shown when output lands
      shell-kill-buffer-on-exit t
      comint-prompt-read-only t
      comint-input-ignoredups t
      comint-scroll-to-bottom-on-input 'this)

;;; FILES
;; Emacs 30 keeps its own state under `user-emacs-directory'.  Redirect
;; only what would land beside someone else's source.

(setq create-lockfiles nil               ; .#file symlinks break web bundlers
      backup-by-copying t
      backup-directory-alist `(("." . ,(locate-user-emacs-file "backups")))
      auto-save-file-name-transforms     ; 28: hashed, under NAME_MAX
      `((".*" ,(locate-user-emacs-file "auto-save-list/") sha1))
      delete-by-moving-to-trash t
      recentf-max-saved-items 100
      savehist-additional-variables '(search-ring regexp-search-ring)
      auto-revert-verbose nil
      auto-revert-avoid-polling t
      global-auto-revert-non-file-buffers t
      uniquify-buffer-name-style 'forward
      uniquify-ignore-buffers-re "^\\*"
      tramp-default-method "ssh")

;; no vc probing over TRAMP
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
      completion-preview-idle-delay 0.15
      minibuffer-prompt-properties
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
(keymap-global-set "C-x C-b" #'ibuffer)

(setq switch-to-buffer-obey-display-actions t
      window-combination-resize t
      help-window-select t
      ibuffer-expert t
      ediff-diff-options "-w"
      ediff-window-setup-function #'ediff-setup-windows-plain
      ediff-split-window-function #'split-window-horizontally
      tab-bar-show 1
      tab-bar-close-button-show nil
      tab-bar-new-tab-choice "*scratch*"
      tab-bar-format '(tab-bar-format-tabs)
      display-buffer-alist
      `((,(rx "*" (or "Help" "Apropos" "info" "Messages" "Warnings"
                      "Compile-Log" "compilation" "grep" "xref"
                      (seq (or "Man " "Plumber") (* nonl)))
              "*")
         (display-buffer-reuse-window display-buffer-at-bottom)
         (window-height . 0.3)
         (reusable-frames . visible))))

;;; TOOLS

(keymap-global-set "C-c m"   #'man)
(keymap-global-set "C-c b"   #'recompile)
(keymap-global-set "C-c B"   #'compile)
(keymap-global-set "C-x M-o" #'find-sibling-file)

(setq Man-notify-method 'aggressive
      display-line-numbers-width 3
      display-line-numbers-grow-only t
      isearch-lazy-count t
      isearch-repeat-on-direction-change t
      isearch-allow-motion t
      grep-use-headings t
      project-mode-line t
      compilation-scroll-output t
      compilation-always-kill t
      compilation-skip-threshold 2
      compilation-ask-about-save nil
      compilation-hidden-output '("^make\\[[0-9]+\\]: .*\n")
      vc-follow-symlinks t
      vc-git-diff-switches '("--histogram")
      find-sibling-rules '(("\\([^/]+\\)\\.c\\'" "\\1.h")
                           ("\\([^/]+\\)\\.h\\'" "\\1.c")))

(add-hook 'compilation-filter-hook #'ansi-color-compilation-filter)
(add-hook 'emacs-lisp-mode-hook #'outline-minor-mode)  ; headers and forms fold

(with-eval-after-load 'project
  (add-to-list 'project-vc-extra-root-markers "go.mod"))

;; GNU ls; HOST covers BSD.
(setq dired-listing-switches "-AFlbhv --group-directories-first"
      dired-recursive-copies 'always
      dired-recursive-deletes 'always
      dired-dwim-target t
      wdired-allow-to-change-permissions t)

;;; LANGUAGES
;; Go: tabs are the default, gofmt is law.  C: "linux", K&R, 8-wide tabs.

(defun core--gofmt-on-save ()
  (add-hook 'before-save-hook #'gofmt-before-save nil t))
(add-hook 'go-mode-hook #'core--gofmt-on-save)

(setq c-default-style '((c++-mode  . "stroustrup")
                        (java-mode . "java")
                        (awk-mode  . "awk")
                        (other     . "linux"))
      tex-bibtex-command "biber")

(add-hook 'after-save-hook #'executable-make-buffer-file-executable-if-script-p)
(add-hook 'latex-mode-hook #'reftex-mode)

(add-to-list 'auto-mode-alist '("\\.erb\\'" . web-mode))
(add-to-list 'auto-mode-alist '("\\.[jt]sx\\'" . web-mode))

;;; HOST

(when (eq system-type 'darwin)
  ;; BSD ls: no -v sort, no --group-directories-first.
  ;; Right Option types @ # [ ] on the IT layout; left stays Meta.
  (setq dired-listing-switches "-AFlbh"
        ns-right-alternate-modifier 'none)
  ;; A Dock launch skips the login shell: name the dirs, don't source it.
  (dolist (dir '("/opt/homebrew/bin" "/Library/TeX/texbin"))
    (when (and (file-directory-p dir) (not (member dir exec-path)))
      (push dir exec-path)
      (setenv "PATH" (concat dir path-separator (getenv "PATH"))))))

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
                tab-bar-history-mode
                tab-bar-mode))
  (funcall mode 1))

;;; init.el ends here
