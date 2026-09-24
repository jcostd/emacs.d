;;; early-init.el --- Pre-GUI boot -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jacopo Costantini

;; Author: Jacopo Costantini <jacopocostantini32@gmail.com>
;; License: GNU General Public License version 3 (or later)

;;; Commentary:
;; Runs before GUI init and before package.el.  Kills startup work,
;; prevents UI flashes, defers GC.

;;; Code:

;; package.el is driven manually from init.el.
(setq package-enable-at-startup nil)

;; Prefer .el over stale .elc.
(setq load-prefer-newer t)

;;; GC & I/O DEFERRAL
;; Both knobs matter: percentage dominates the threshold.

(defconst core--gc-threshold (* 16 1024 1024))
(defconst core--gc-percentage 0.1)
(defvar core--file-name-handler-alist file-name-handler-alist)

(setq gc-cons-threshold  most-positive-fixnum
      gc-cons-percentage 1.0
      file-name-handler-alist
      (list (rassq 'jka-compr-handler file-name-handler-alist)))

(defun core--restore-boot-state ()
  "Undo boot-time deferrals.  Named, so it can be inspected and removed."
  (setq gc-cons-threshold  core--gc-threshold
        gc-cons-percentage core--gc-percentage
        file-name-handler-alist
        (delete-dups (append file-name-handler-alist
                             core--file-name-handler-alist))))

(add-hook 'emacs-startup-hook #'core--restore-boot-state)

;;; FRAME
;; Set as frame parameters, not modes: no redisplay, no chrome flash.
;; Colours match ascetic-dark to kill the white flash before load-theme.

;; X resources become frame params and outrank theme faces.
(setq inhibit-x-resources t)

(dolist (param '((menu-bar-lines . 0)
                 (tool-bar-lines . 0)
                 (vertical-scroll-bars)
                 (horizontal-scroll-bars)))
  (push param default-frame-alist))

;; First frame only: frame params outrank theme faces, so in
;; default-frame-alist every later frame is born dark.
(setq initial-frame-alist '((background-color . "#201D17")
                            (foreground-color . "#EDE4DC")))

;; Keep the mode vars in sync so the modes never turn themselves on.
(setq menu-bar-mode   nil
      tool-bar-mode   nil
      scroll-bar-mode nil
      use-dialog-box  nil
      use-file-dialog nil)

(setq frame-inhibit-implied-resize t
      frame-resize-pixelwise       t
      window-resize-pixelwise      t)

;;; RENDERING

(setq inhibit-compacting-font-caches t)

;; No bidi paragraphs in code: skip the paren algorithm.
(setq bidi-inhibit-bpa t)
(setq-default bidi-paragraph-direction 'left-to-right)

;;; NOISE

(setq native-comp-async-report-warnings-errors 'silent)

;;; early-init.el ends here
