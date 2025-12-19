;;;; package.lisp
;;;; SSP - パッケージ定義、定数、構造体、アクセサ

;; パッケージ再読み込み時のエラー回避
(when (find-package :ssexp)
  (delete-package :ssexp))

(defpackage :ssexp
  (:use :cl :ltk)
  (:nicknames :ssp)
  (:export 
   ;; 起動
   #:start 
   ;; デバッグ
   #:show-dependencies #:show-cell-deps
   ;; ファイル操作
   #:save #:load-file #:new-sheet
   #:export-csv #:import-csv
   ;; Undo/Redo
   #:undo #:redo #:clear-history
   ;; 構造体
   #:cell #:make-cell #:cell-value #:cell-formula
   #:ss-state #:resize-state #:clipboard-data #:eval-context
   ;; グローバルインスタンス
   #:*ss* #:*resize* #:*clip* #:*eval-ctx*
   ;; 定数
   #:+default-cell-w+ #:+default-cell-h+
   #:+min-cell-w+ #:+min-cell-h+
   #:+header-h+ #:+header-w+
   #:+max-undo-history+
   ;; アクセサ - シートサイズ
   #:sheet-rows #:sheet-cols
   ;; アクセサ - カーソル
   #:cursor-x #:cursor-y #:move-cursor
   ;; アクセサ - 選択
   #:selection-start-x #:selection-start-y
   #:selection-end-x #:selection-end-y
   #:selecting-p #:set-selection
   ;; アクセサ - レイアウト
   #:get-col-width #:get-row-height
   #:set-col-width #:set-row-height
   ;; アクセサ - セル
   #:get-cell #:set-cell #:current-cell #:cell-name
   ;; アクセサ - 評価
   #:eval-row #:eval-col #:eval-stack
   ;; アクセサ - クリップボード
   #:clipboard-cells #:clipboard-rows #:clipboard-cols #:set-clipboard
   ;; アクセサ - ファイル
   #:current-file
   ;; 後方互換（段階的に廃止）
   #:*current-file* #:*rows* #:*cols*))
(in-package :ssexp)

;;;; =========================
;;;; 定数（再読み込み対応のためdefparameterを使用）
;;;; =========================

(defparameter +default-cell-w+ 100)  ; デフォルトセル幅
(defparameter +default-cell-h+ 24)   ; デフォルトセル高さ
(defparameter +min-cell-w+ 30)       ; 最小セル幅
(defparameter +min-cell-h+ 16)       ; 最小セル高さ
(defparameter +header-h+ 24)         ; 列ヘッダー高さ
(defparameter +header-w+ 40)         ; 行ヘッダー幅
(defparameter +max-undo-history+ 100) ; 最大Undo履歴数

;;;; =========================
;;;; 構造体定義
;;;; =========================

;; セル構造体
(defstruct cell
  value      ; 表示値（任意のLisp値）
  formula)   ; 数式（S式）、なければnil

;; スプレッドシート状態
(defstruct ss-state
  ;; グリッドサイズ
  (rows 26 :type fixnum)
  (cols 14 :type fixnum)
  ;; セルデータ
  (sheet (make-hash-table :test #'equal))
  (refs (make-hash-table :test #'equal))
  (dependents (make-hash-table :test #'equal))
  ;; カーソル
  (cur-x 0 :type fixnum)
  (cur-y 0 :type fixnum)
  ;; 選択範囲
  (sel-start-x 0 :type fixnum)
  (sel-start-y 0 :type fixnum)
  (sel-end-x 0 :type fixnum)
  (sel-end-y 0 :type fixnum)
  (selecting nil)
  ;; レイアウト
  (col-widths nil)
  (row-heights nil)
  ;; Undo/Redo
  (undo-stack nil)
  (redo-stack nil)
  ;; ファイル
  (current-file nil))

;; リサイズ状態
(defstruct resize-state
  (mode nil)       ; :col or :row
  (index nil)      ; リサイズ中の列/行インデックス
  (start nil))     ; ドラッグ開始位置

;; クリップボード
(defstruct clipboard-data
  (cells nil)      ; 2次元リスト ((val formula) ...)
  (rows 0 :type fixnum)
  (cols 0 :type fixnum))

;; 評価コンテキスト
(defstruct eval-context
  (row 0 :type fixnum)   ; 評価中の行
  (col 0 :type fixnum)   ; 評価中の列
  (stack nil)            ; 循環参照検出用
  (env nil))             ; lambda環境

;;;; =========================
;;;; グローバルインスタンス
;;;; =========================

(defparameter *ss* (make-ss-state))
(defparameter *resize* (make-resize-state))
(defparameter *clip* (make-clipboard-data))
(defparameter *eval-ctx* (make-eval-context))

;;;; =========================
;;;; 後方互換性のためのグローバル変数
;;;; （段階的に廃止予定）
;;;; =========================

(defparameter *rows* 26)
(defparameter *cols* 14)
(defparameter *default-cell-w* +default-cell-w+)
(defparameter *default-cell-h* +default-cell-h+)
(defparameter *min-cell-w* +min-cell-w+)
(defparameter *min-cell-h* +min-cell-h+)
(defparameter +header-h+ +header-h+)
(defparameter +header-w+ +header-w+)
(defparameter *cur-x* 0)
(defparameter *cur-y* 0)
(defparameter *col-widths* nil)
(defparameter *row-heights* nil)
(defparameter *resize-mode* nil)
(defparameter *resize-index* nil)
(defparameter *resize-start* nil)
(defparameter *sel-start-x* nil)
(defparameter *sel-start-y* nil)
(defparameter *sel-end-x* nil)
(defparameter *sel-end-y* nil)
(defparameter *selecting* nil)
(defparameter *clipboard* nil)
(defparameter *clipboard-rows* 0)
(defparameter *clipboard-cols* 0)
(defvar *eval-row* 0)
(defvar *eval-col* 0)
(defvar *eval-stack* nil)
(defparameter *refs* (make-hash-table :test 'equal))
(defparameter *dependents* (make-hash-table :test 'equal))
(defparameter *undo-stack* nil)
(defparameter *redo-stack* nil)
(defparameter *max-undo-history* +max-undo-history+)
(defparameter *current-file* nil)
(defparameter *sheet* (make-hash-table :test #'equal))

;;;; =========================
;;;; アクセサ関数
;;;; =========================

;;; --- シートサイズ ---
(defun sheet-rows () *rows*)
(defun sheet-cols () *cols*)
(defun (setf sheet-rows) (val) (setf *rows* val))
(defun (setf sheet-cols) (val) (setf *cols* val))

;;; --- カーソル ---
(defun cursor-x () *cur-x*)
(defun cursor-y () *cur-y*)
(defun (setf cursor-x) (val) (setf *cur-x* val))
(defun (setf cursor-y) (val) (setf *cur-y* val))
(defun move-cursor (x y)
  (setf *cur-x* x *cur-y* y))

;;; --- 選択範囲 ---
(defun selection-start-x () *sel-start-x*)
(defun selection-start-y () *sel-start-y*)
(defun selection-end-x () *sel-end-x*)
(defun selection-end-y () *sel-end-y*)
(defun selecting-p () *selecting*)
(defun (setf selection-start-x) (val) (setf *sel-start-x* val))
(defun (setf selection-start-y) (val) (setf *sel-start-y* val))
(defun (setf selection-end-x) (val) (setf *sel-end-x* val))
(defun (setf selection-end-y) (val) (setf *sel-end-y* val))
(defun (setf selecting-p) (val) (setf *selecting* val))
(defun set-selection (start-x start-y end-x end-y)
  (setf *sel-start-x* start-x
        *sel-start-y* start-y
        *sel-end-x* end-x
        *sel-end-y* end-y))

;;; --- 列幅・行高さ ---
;; col-width, row-height, set-col-width, set-row-height は
;; 後方の「列幅・行高さ管理」セクションで定義

;;; --- リサイズ状態 ---
(defun resize-mode () *resize-mode*)
(defun resize-index () *resize-index*)
(defun resize-start () *resize-start*)
(defun (setf resize-mode) (val) (setf *resize-mode* val))
(defun (setf resize-index) (val) (setf *resize-index* val))
(defun (setf resize-start) (val) (setf *resize-start* val))

;;; --- 評価コンテキスト ---
(defun eval-row () *eval-row*)
(defun eval-col () *eval-col*)
(defun eval-stack () *eval-stack*)
(defun (setf eval-row) (val) (setf *eval-row* val))
(defun (setf eval-col) (val) (setf *eval-col* val))
(defun (setf eval-stack) (val) (setf *eval-stack* val))
(defun push-eval-stack (name) (push name *eval-stack*))
(defun pop-eval-stack () (pop *eval-stack*))
(defun eval-stack-member (name) (member name *eval-stack* :test #'string=))

;;; --- 依存関係 ---
(defun get-refs (name) (gethash name *refs*))
(defun get-dependents (name) (gethash name *dependents*))
(defun (setf get-refs) (val name) (setf (gethash name *refs*) val))
(defun (setf get-dependents) (val name) (setf (gethash name *dependents*) val))
(defun clear-refs (name) (remhash name *refs*))
(defun clear-dependents (name) (remhash name *dependents*))
(defun clear-all-refs () (clrhash *refs*))
(defun clear-all-dependents () (clrhash *dependents*))
(defun map-refs (fn) (maphash fn *refs*))
(defun map-dependents (fn) (maphash fn *dependents*))

;;; --- Undo/Redo ---
(defun undo-stack () *undo-stack*)
(defun redo-stack () *redo-stack*)
(defun (setf undo-stack) (val) (setf *undo-stack* val))
(defun (setf redo-stack) (val) (setf *redo-stack* val))
(defun push-undo (action)
  (push action *undo-stack*)
  (when (> (length *undo-stack*) +max-undo-history+)
    (setf *undo-stack* (butlast *undo-stack*))))
(defun pop-undo () (pop *undo-stack*))
(defun push-redo (action) (push action *redo-stack*))
(defun pop-redo () (pop *redo-stack*))
(defun clear-redo () (setf *redo-stack* nil))

;;; --- クリップボード ---
(defun clipboard-cells () *clipboard*)
(defun clipboard-rows () *clipboard-rows*)
(defun clipboard-cols () *clipboard-cols*)
(defun set-clipboard (cells rows cols)
  (setf *clipboard* cells
        *clipboard-rows* rows
        *clipboard-cols* cols))

;;; --- ファイル ---
(defun current-file () *current-file*)
(defun (setf current-file) (val) (setf *current-file* val))

;;;; =========================
;;;; データモデル
;;;; =========================

;; シート本体：セル名("A1"等)をキーとするハッシュテーブル
;; *sheet* は上で定義済み

(defun get-cell (name)
  "セルを取得。存在しなければ新規作成"
  (or (gethash name *sheet*)
      (setf (gethash name *sheet*) (make-cell))))

(defun get-cell-raw (name)
  "セルを取得。存在しなければnil"
  (gethash name *sheet*))

(defun set-cell-value (name cell)
  "セルを直接設定"
  (setf (gethash name *sheet*) cell))

(defun remove-cell (name)
  "セルを削除"
  (remhash name *sheet*))

(defun clear-sheet ()
  "シート全体をクリア"
  (clrhash *sheet*))

(defun reset-sheet ()
  "シートを新規作成"
  (setf *sheet* (make-hash-table :test #'equal)))

(defun map-sheet (fn)
  "シートの全セルに関数を適用"
  (maphash fn *sheet*))

(defun cell-name (x y)
  "座標(x,y)からセル名を生成。(0,0)->\"A1\", (1,2)->\"B3\""
  (format nil "~a~d"
          (code-char (+ (char-code #\A) x))
          (1+ y)))

(defun current-cell ()
  "現在カーソル位置のセルを取得"
  (get-cell (cell-name (cursor-x) (cursor-y))))

