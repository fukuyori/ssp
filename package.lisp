;;;; package.lisp
;;;; SSP v0.7.2 - パッケージ定義、定数、構造体、アクセサ
;;;; v0.7: 日本語・Unicode対応
;;;; v0.7.1: 循環参照検出改善、パフォーマンス最適化
;;;; v0.7.2: シートサイズ上限設定（1000行×26列）

;; パッケージ再読み込み時のエラー回避
(when (find-package :ssexp)
  (delete-package :ssexp))

(defpackage :ssexp
  (:use :cl :ltk)
  (:nicknames :ssp)
  (:export 
   ;; 起動
   #:start 
   ;; バージョン情報 (v0.7)
   #:*ssp-version* #:version-info #:scroll-info #:visible-range-info
   ;; デバッグ
   #:show-dependencies #:show-cell-deps
   ;; キャッシュ・パフォーマンス (v0.7.1)
   #:clear-cache #:show-cache-stats #:*enable-cache*
   ;; 循環参照 (v0.7.1)
   #:detect-cycles #:show-cycle-path
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
   ;; サイズ制限 (v0.7.2)
   #:+max-rows+ #:+max-cols+
   #:+default-rows+ #:+default-cols+
   #:+visible-rows+ #:+visible-cols+
   ;; フォント設定 (v0.7)
   #:*font-family* #:*font-size*
   ;; 文字幅計算 (v0.7)
   #:char-display-width #:string-display-width #:truncate-to-display-width
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
;;;; バージョン情報 (v0.7.2)
;;;; =========================

(defparameter *ssp-version* "0.8.1")

(defun version-info ()
  "バージョン情報を返す"
  (format nil "SSP v~a - Symbolic Spreadsheet for Lisp Learning~%~
               Features: japanese-support, unicode-display, utf8-file-io, cjk-fonts,~%~
                         improved-cycle-detection, evaluation-cache,~%~
                         grid-size-limit (~d rows × ~d cols)"
          *ssp-version* +max-rows+ +max-cols+))

;;;; =========================
;;;; シートサイズ制限 (v0.7.2 新規)
;;;; =========================

(defconstant +max-rows+ 10000
  "最大行数（v0.7.4で拡張）")

(defconstant +max-cols+ 26
  "最大列数（A-Z、セル名形式制限）")

(defconstant +min-col-width+ 20
  "最小列幅（ピクセル）")

(defconstant +min-row-height+ 15
  "最小行高さ（ピクセル）")

(defconstant +default-rows+ 200
  "デフォルト行数")

(defconstant +default-cols+ 16
  "デフォルト列数")

(defconstant +visible-rows+ 30
  "表示行数（ウィンドウサイズ制限）")

(defconstant +visible-cols+ 16
  "表示列数（ウィンドウサイズ制限）")

(defun validate-grid-size (rows cols)
  "グリッドサイズを検証し、制限内に収める
   戻り値: (validated-rows validated-cols warnings)"
  (let ((warnings nil)
        (valid-rows rows)
        (valid-cols cols))
    ;; 行数チェック
    (when (> rows +max-rows+)
      (setf valid-rows +max-rows+)
      (push (format nil "行数を~dから~dに制限しました" rows +max-rows+) warnings))
    (when (< rows 1)
      (setf valid-rows +default-rows+)
      (push (format nil "行数を~dに設定しました" +default-rows+) warnings))
    ;; 列数チェック
    (when (> cols +max-cols+)
      (setf valid-cols +max-cols+)
      (push (format nil "列数を~dから~dに制限しました（A-Z形式制限）" cols +max-cols+) warnings))
    (when (< cols 1)
      (setf valid-cols +default-cols+)
      (push (format nil "列数を~dに設定しました" +default-cols+) warnings))
    (values valid-rows valid-cols (nreverse warnings))))

;;;; =========================
;;;; フォント設定 (v0.7)
;;;; =========================

(defparameter *font-family*
  #+darwin "Menlo"
  #+windows "MS Gothic"
  #-(or darwin windows) "Noto Sans Mono CJK JP"
  "デフォルトの等幅フォント（Unicode/CJK対応）")

(defparameter *font-family-fallback*
  '("Noto Sans Mono CJK JP"
    "Source Han Code JP"
    "IPAGothic"
    "VL Gothic"
    "DejaVu Sans Mono"
    "Consolas"
    "Courier")
  "フォールバックフォントリスト")

(defparameter *font-size* 11
  "デフォルトフォントサイズ")

;;;; =========================
;;;; 評価キャッシュ (v0.7.1 新規)
;;;; =========================

(defparameter *enable-cache* t
  "評価キャッシュを有効にするか")

(defparameter *eval-cache* (make-hash-table :test #'equal)
  "セル評価結果のキャッシュ: セル名 → (値 . 評価世代)")

(defparameter *dirty-cells* (make-hash-table :test #'equal)
  "変更されたセルのフラグ: セル名 → t")

(defparameter *eval-generation* 0
  "評価世代（キャッシュ無効化用）")

(defun clear-cache ()
  "評価キャッシュをクリア"
  (clrhash *eval-cache*)
  (clrhash *dirty-cells*)
  (incf *eval-generation*))

(defun mark-dirty (cell-name)
  "セルを変更済みとしてマーク"
  (setf (gethash cell-name *dirty-cells*) t)
  ;; キャッシュを無効化
  (remhash cell-name *eval-cache*))

(defun is-dirty-p (cell-name)
  "セルが変更済みかどうか"
  (gethash cell-name *dirty-cells*))

(defun clear-dirty (cell-name)
  "セルの変更フラグをクリア"
  (remhash cell-name *dirty-cells*))

(defun get-cached-value (cell-name)
  "キャッシュから値を取得（有効な場合）"
  (when *enable-cache*
    (let ((cached (gethash cell-name *eval-cache*)))
      (when (and cached (= (cdr cached) *eval-generation*))
        (car cached)))))

(defun set-cached-value (cell-name value)
  "値をキャッシュに保存"
  (when *enable-cache*
    (setf (gethash cell-name *eval-cache*) 
          (cons value *eval-generation*))))

(defparameter *cache-hits* 0)
(defparameter *cache-misses* 0)

(defun show-cache-stats ()
  "キャッシュ統計を表示"
  (format t "~%=== Cache Statistics ===~%")
  (format t "Enabled: ~a~%" *enable-cache*)
  (format t "Generation: ~a~%" *eval-generation*)
  (format t "Cached entries: ~a~%" (hash-table-count *eval-cache*))
  (format t "Dirty cells: ~a~%" (hash-table-count *dirty-cells*))
  (format t "Cache hits: ~a~%" *cache-hits*)
  (format t "Cache misses: ~a~%" *cache-misses*)
  (when (> (+ *cache-hits* *cache-misses*) 0)
    (format t "Hit rate: ~,1f%~%" 
            (* 100.0 (/ *cache-hits* (+ *cache-hits* *cache-misses*))))))

;;;; =========================
;;;; 循環参照検出 (v0.7.1 強化)
;;;; =========================

(defparameter *cycle-path* nil
  "検出された循環パス")

(defparameter *max-eval-depth* 100
  "最大評価深さ（無限ループ防止）")

(defun record-cycle-path (path)
  "循環パスを記録"
  (setf *cycle-path* (reverse path)))

(defun show-cycle-path ()
  "最後に検出された循環パスを表示"
  (if *cycle-path*
      (progn
        (format t "~%=== Circular Reference Detected ===~%")
        (format t "Path: ~{~a~^ → ~}~%" *cycle-path*)
        (format t "Cycle closes at: ~a~%" (car (last *cycle-path*))))
      (format t "No circular reference detected.~%")))

(defun format-cycle-error (cell-name path)
  "循環参照エラーメッセージをフォーマット"
  (let ((cycle-str (format nil "~{~a~^→~}" (reverse path))))
    (format nil "#循環: ~a (~a)" cell-name cycle-str)))

;;;; =========================
;;;; 文字幅計算 (v0.7 新規)
;;;; =========================

(defun char-display-width (char)
  "文字の表示幅を返す（半角=1, 全角=2）"
  (let ((code (char-code char)))
    (cond
      ;; ASCII printable (0x20-0x7E) -> 半角
      ((<= #x0020 code #x007E) 1)
      ;; 半角カナ (0xFF61-0xFF9F) -> 半角
      ((<= #xFF61 code #xFF9F) 1)
      ;; CJK統合漢字
      ((<= #x4E00 code #x9FFF) 2)
      ;; ひらがな
      ((<= #x3040 code #x309F) 2)
      ;; カタカナ
      ((<= #x30A0 code #x30FF) 2)
      ;; CJK記号・句読点
      ((<= #x3000 code #x303F) 2)
      ;; 全角英数
      ((<= #xFF01 code #xFF5E) 2)
      ;; 全角括弧等
      ((<= #xFF5F code #xFF60) 2)
      ;; ハングル
      ((<= #xAC00 code #xD7AF) 2)
      ;; CJK互換
      ((<= #x3300 code #x33FF) 2)
      ((<= #xFE30 code #xFE4F) 2)
      ;; 囲みCJK
      ((<= #x3200 code #x32FF) 2)
      ;; CJK拡張A
      ((<= #x3400 code #x4DBF) 2)
      ;; CJK拡張B以降（補助面）
      ((>= code #x20000) 2)
      ;; デフォルト: 半角
      (t 1))))

(defun string-display-width (str)
  "文字列の合計表示幅を計算"
  (loop for char across str
        sum (char-display-width char)))

(defun truncate-to-display-width (str max-width &optional (suffix "…"))
  "文字列を指定した表示幅に切り詰める"
  (let ((suffix-width (string-display-width suffix))
        (current-width 0)
        (result '()))
    (loop for char across str
          for char-width = (char-display-width char)
          while (<= (+ current-width char-width suffix-width) max-width)
          do (progn
               (push char result)
               (incf current-width char-width)))
    (if (= (length result) (length str))
        str  ; 切り詰め不要
        (concatenate 'string 
                     (coerce (nreverse result) 'string)
                     suffix))))

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
;;;; キャンバス参照 (v0.7.2)
;;;; =========================

(defparameter *corner-canvas* nil "左上コーナーキャンバス")
(defparameter *col-header-canvas* nil "列ヘッダーキャンバス")
(defparameter *row-header-canvas* nil "行ヘッダーキャンバス")
(defparameter *main-canvas* nil "メインセルキャンバス")

;;;; =========================
;;;; スクロール状態 (v0.7.2 改善)
;;;; =========================

(defparameter *scroll-x* 0 "水平スクロール位置（ピクセル）")
(defparameter *scroll-y* 0 "垂直スクロール位置（ピクセル）")

;;;; =========================
;;;; 実際のキャンバスサイズ (v0.7.7)
;;;; =========================

(defparameter *actual-canvas-width* nil "実際のキャンバス幅（ピクセル）、nilなら計算値を使用")
(defparameter *actual-canvas-height* nil "実際のキャンバス高さ（ピクセル）、nilなら計算値を使用")

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

