;;; ascetic-light-theme.el --- Ascetic Light -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jacopo Costantini
;; Author: Jacopo Costantini <jacopocostantini32@gmail.com>
;; License: GNU General Public License version 3 (or later)

;;; Commentary:
;; Primary theme.  Positive polarity is faster and more accurate
;; (Buchner 2007, Piepenbrock 2013) at every ambient level.
;; Requires lisp/ on `load-path' before load.
;; Reference polarity: the dark theme locks hue to these values and
;; inverts L*, except rule, which is matched on Lc.
;; Signal urgency, top down: alarm figure literal caution mute.
;; Deutan-fragile pairs need 8 L*: literal/caution 7.9, caution/mute
;; 4.8 -- the latter rides on chroma.  figure/literal share L* and are
;; held apart by hue alone, dE2000 31.

;;; Code:

(require 'ascetic-theme)

;;;###theme-autoload
(deftheme ascetic-light
  "Clarity through renunciation.  Vellum ground, iron-gall ink."
  :background-mode 'light
  :kind 'color-scheme
  :family 'ascetic)

(ascetic-theme-define ascetic-light
  ;; ladder: monotone toward ink
  (paper   "#F5E9D1")   ; L* 92.7  C* 13  h 88
  (paper-1 "#E9DDC6")   ; L* 88.5
  (paper-2 "#D9CAAE")   ; L* 82.0
  (rule    "#BCAF97")   ; L* 72.0

  ;; signal: Lc against paper, ordered by search urgency
  (ink     "#272320")   ; 90
  (alarm   "#6F2324")   ; 82
  (figure  "#325372")   ; 75
  (literal "#395833")   ; 75  hue-separated from figure
  (caution "#875A1F")   ; 67  always bold
  (mute    "#756E67"))  ; 62  always italic

(provide-theme 'ascetic-light)
;;; ascetic-light-theme.el ends here
