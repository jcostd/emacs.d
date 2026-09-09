;;; ascetic-dark-theme.el --- Ascetic Dark -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jacopo Costantini
;; Author: Jacopo Costantini <jacopocostantini32@gmail.com>
;; License: GNU General Public License version 3 (or later)

;;; Commentary:
;; Low-ambient adaptation, not a twin.  Hue is locked to ascetic-light,
;; L* inverted, chroma capped by the sRGB gamut -- which narrows sharply
;; near white.  The signal band is therefore compressed to Lc 48-64:
;; order survives, spacing does not.  Weight and wave underlines carry
;; the rest.  Requires lisp/ on `load-path' before load.
;;
;; Deutan margins are short here: alarm/literal 3.9 L*, literal/caution
;; 4.6, caution/mute 2.4.

;;; Code:

(require 'ascetic-theme)

;;;###theme-autoload
(deftheme ascetic-dark
  "Clarity through renunciation.  Warm ground, low emission."
  :background-mode 'dark
  :kind 'color-scheme
  :family 'ascetic)

(ascetic-theme-define ascetic-dark
  ;; ladder: monotone toward ink, as in light.  rule is matched on Lc,
  ;; not L* -- reverse polarity compresses, equal steps do not carry
  ;; equal weight.
  (paper   "#201D17")   ; L* 11  C* 5  h 88
  (paper-1 "#29251F")   ; L* 15
  (paper-2 "#39342C")   ; L* 22
  (rule    "#665F50")   ; L* 40.6  Lc 18.6

  ;; signal: band compressed by gamut, order preserved
  (ink     "#EDE4DC")   ; 90
  (alarm   "#FBA59F")   ; 64  h 28   always bold
  (figure  "#94B3D8")   ; 58  h 265
  (literal "#98BA90")   ; 58  h 138
  (caution "#D09A5C")   ; 52  h 72   always bold
  (mute    "#A49D95"))  ; 48  h 75   always italic

(provide-theme 'ascetic-dark)
;;; ascetic-dark-theme.el ends here
