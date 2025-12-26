;;;; ui.lisp
;;;; SSP v0.8.0 - 描画、入力処理、シンタックスハイライト
;;;; v0.7: 日本語・Unicode対応（フォント設定、文字幅計算）
;;;; v0.7.3: バッチ描画によるパフォーマンス改善
;;;; v0.7.4: 大規模シート対応（最大10000行）
;;;; v0.7.5: スクロール位置追跡の改善
;;;; v0.7.6: 表示範囲計算の実装
;;;; v0.7.7: 仮想スクロール描画（表示範囲のみ描画）
;;;; v0.8.0: 差分更新（変更セルのみ再描画）

(in-package :ssexp)

;;;; =========================
;;;; スクロール位置同期 (v0.7.5)
;;;; =========================

(defun sync-scroll-position ()
  "Tkキャンバスのスクロール位置を *scroll-x* *scroll-y* に同期
   スクロールバー/ホイール操作後の位置ずれを防止"
  (when *main-canvas*
    (let* ((cells-w (- (total-width) +header-w+))
           (cells-h (- (total-height) +header-h+)))
      ;; 水平位置を取得
      (format-wish "senddatastrings [~a xview]" (widget-path *main-canvas*))
      (let ((xview (ltk::read-data)))
        (when (and xview (first xview))
          (let ((x-fraction (ignore-errors (read-from-string (first xview)))))
            (when (numberp x-fraction)
              (setf *scroll-x* (round (* x-fraction cells-w)))))))
      ;; 垂直位置を取得
      (format-wish "senddatastrings [~a yview]" (widget-path *main-canvas*))
      (let ((yview (ltk::read-data)))
        (when (and yview (first yview))
          (let ((y-fraction (ignore-errors (read-from-string (first yview)))))
            (when (numberp y-fraction)
              (setf *scroll-y* (round (* y-fraction cells-h))))))))))

(defun scroll-info ()
  "現在のスクロール位置情報を返す（デバッグ用）"
  (sync-scroll-position)
  (let* ((cells-w (- (total-width) +header-w+))
         (cells-h (- (total-height) +header-h+))
         (visible-w (- (visible-width) +header-w+))
         (visible-h (- (visible-height) +header-h+)))
    (format t "~%=== Scroll Info (v0.7.5) ===~%")
    (format t "scroll-x: ~d / ~d px~%" *scroll-x* cells-w)
    (format t "scroll-y: ~d / ~d px~%" *scroll-y* cells-h)
    (format t "visible: ~d x ~d px~%" visible-w visible-h)
    (format t "cursor: (~d, ~d) = ~a~%" 
            (cursor-x) (cursor-y) (cell-name (cursor-x) (cursor-y)))
    (values *scroll-x* *scroll-y*)))

;;;; =========================
;;;; 描画（Canvas操作）
;;;; =========================

(defun draw-cell-background (canvas x y val selected in-selection)
  "セルの背景のみを描画"
  (let* ((px (col-left x))
         (py (row-top y))
         (w (col-width x))
         (h (row-height y))
         (px2 (+ px w))
         (py2 (+ py h))
         ;; 値の型によって背景色を変える
         (bg (cond
               (selected "#cce5ff")                    ; カーソル位置
               (in-selection "#d0e8ff")                ; 選択範囲
               ((null val) "white")                    ; 空
               ((listp val) "#f0fff0")                 ; リストは薄緑
               ((and val (symbolp val)) "#fff0f0")    ; シンボルは薄赤
               ((stringp val) "#fffff0")              ; 文字列は薄黄
               (t "white")))
         (path (widget-path canvas)))
    (format-wish "~a create rectangle ~a ~a ~a ~a -fill {~a} -outline gray"
                 path px py px2 py2 bg)))

(defun count-overflow-cells (x y)
  "右側の空セルの数をカウント（はみ出し用）"
  (loop for i from (1+ x) below (sheet-cols)
        while (null (cell-value (get-cell (cell-name i y))))
        count t))

(defun draw-cell-text (canvas x y val)
  "セルのテキストのみを描画（数値は右寄せ、それ以外は左寄せ）
   v0.7: 日本語フォント対応、文字幅を考慮した切り詰め"
  (when val
    (let* ((px (col-left x))
           (py (row-top y))
           (w (col-width x))
           (h (row-height y))
           (raw-text (format-value val))
           ;; 全角文字を考慮して保守的に計算（全角=14px, 半角=7px として表示幅2=14px）
           (available-width (- w 12))  ; 左右マージン6pxずつ
           (char-pixel-width 7)        ; 半角文字の幅（表示幅1=7px）
           (available-chars (floor available-width char-pixel-width))
           ;; 表示幅が利用可能幅を超える場合は切り詰め
           (display-text (if (> (string-display-width raw-text) available-chars)
                             (truncate-to-display-width raw-text (max 1 (- available-chars 1)))
                             raw-text))
           (path (widget-path canvas))
           ;; 数値かどうか
           (is-number (numberp val))
           ;; フォント設定
           (font-spec (format nil "{~a} ~a" *font-family* *font-size*)))
      ;; 数値は右寄せ、それ以外は左寄せ
      (if is-number
          ;; 右寄せ（anchor: e）
          (format-wish "~a create text ~a ~a -anchor e -text {~a} -font {~a}"
                       path (+ px w -6) (+ py (floor h 2)) display-text font-spec)
          ;; 左寄せ（anchor: w）
          (format-wish "~a create text ~a ~a -anchor w -text {~a} -font {~a}"
                       path (+ px 6) (+ py (floor h 2)) display-text font-spec)))))

(defun draw-corner (canvas)
  "左上コーナーを描画（固定）"
  (let ((path (widget-path canvas)))
    (format-wish "~a delete all" path)
    (format-wish "~a create rectangle 0 0 ~a ~a -fill {#e0e0e0} -outline gray"
                 path +header-w+ +header-h+)))

;;;; =========================
;;;; バッチ描画ユーティリティ (v0.7.3 パフォーマンス改善)
;;;; =========================

(defparameter *batch-size* 500
  "1回のformat-wishで送信するコマンド数の上限")

(defun send-batch-commands (commands)
  "コマンドリストをバッチで送信（v0.7.3）"
  (when commands
    (let ((cmd-list (nreverse commands)))
      ;; *batch-size*ごとに分割送信
      (loop while cmd-list do
        (let ((batch (loop repeat *batch-size*
                          while cmd-list
                          collect (pop cmd-list))))
          (when batch
            (format-wish "~{~a~^; ~}" batch)))))))

(defun cell-bg-color (val selected in-selection)
  "セルの背景色を決定"
  (cond
    (selected "#cce5ff")
    (in-selection "#d0e8ff")
    ((null val) "white")
    ((listp val) "#f0fff0")
    ((and val (symbolp val)) "#fff0f0")
    ((stringp val) "#fffff0")
    (t "white")))

;;;; =========================
;;;; 表示範囲計算 (v0.7.6 改良)
;;;; =========================

(defun find-start-col (scroll-x)
  "スクロール位置から開始列を探す"
  (let ((accum 0))
    (dotimes (x (sheet-cols))
      (let ((w (col-width x)))
        (when (>= (+ accum w) scroll-x)
          (return-from find-start-col x))
        (incf accum w)))
    (1- (sheet-cols))))

(defun find-end-col (scroll-x visible-w)
  "スクロール位置と表示幅から終了列を探す"
  (let ((accum 0)
        (target (+ scroll-x visible-w)))
    (dotimes (x (sheet-cols))
      (incf accum (col-width x))
      (when (>= accum target)
        (return-from find-end-col x)))
    (1- (sheet-cols))))

(defun find-start-row (scroll-y)
  "スクロール位置から開始行を探す"
  (let ((accum 0))
    (dotimes (y (sheet-rows))
      (let ((h (row-height y)))
        (when (>= (+ accum h) scroll-y)
          (return-from find-start-row y))
        (incf accum h)))
    (1- (sheet-rows))))

(defun find-end-row (scroll-y visible-h)
  "スクロール位置と表示高さから終了行を探す"
  (let ((accum 0)
        (target (+ scroll-y visible-h)))
    (dotimes (y (sheet-rows))
      (incf accum (row-height y))
      (when (>= accum target)
        (return-from find-end-row y)))
    (1- (sheet-rows))))

(defun visible-cell-range ()
  "表示されているセル範囲を返す (values start-col start-row end-col end-row)
   スクロール位置と表示サイズから正確に計算 (v0.7.6)"
  (let* ((scroll-x (max 0 *scroll-x*))
         (scroll-y (max 0 *scroll-y*))
         (visible-w (- (visible-width) +header-w+))
         (visible-h (- (visible-height) +header-h+))
         ;; 開始位置を探す
         (start-col (find-start-col scroll-x))
         (start-row (find-start-row scroll-y))
         ;; 終了位置を探す
         (end-col (find-end-col scroll-x visible-w))
         (end-row (find-end-row scroll-y visible-h)))
    ;; マージンを追加（境界のちらつき防止）
    (values (max 0 (1- start-col))
            (max 0 (1- start-row))
            (min (1+ end-col) (1- (sheet-cols)))
            (min (1+ end-row) (1- (sheet-rows))))))

(defun visible-range-info ()
  "表示範囲の情報を返す（デバッグ用）"
  (sync-scroll-position)
  (multiple-value-bind (start-col start-row end-col end-row)
      (visible-cell-range)
    (let ((col-count (1+ (- end-col start-col)))
          (row-count (1+ (- end-row start-row)))
          (total-cells (* (sheet-cols) (sheet-rows))))
      (format t "~%=== Visible Range (v0.7.6) ===~%")
      (format t "Range: ~a~d to ~a~d~%"
              (string (code-char (+ (char-code #\A) start-col))) (1+ start-row)
              (string (code-char (+ (char-code #\A) end-col))) (1+ end-row))
      (format t "Columns: ~d-~d (~d cols)~%" start-col end-col col-count)
      (format t "Rows: ~d-~d (~d rows)~%" start-row end-row row-count)
      (format t "Visible cells: ~d / ~d (~,1f%)~%"
              (* col-count row-count) total-cells
              (* 100.0 (/ (* col-count row-count) total-cells)))
      (values start-col start-row end-col end-row))))

(defun draw-col-headers (canvas)
  "列名ヘッダー(A,B,C...)を描画（表示範囲のみ v0.7.7）"
  (sync-scroll-position)
  (let ((path (widget-path canvas))
        (header-font (format nil "{~a} ~a bold" *font-family* *font-size*))
        (commands nil))
    (format-wish "~a delete all" path)
    (multiple-value-bind (start-col start-row end-col end-row)
        (visible-cell-range)
      (declare (ignore start-row end-row))
      (loop for x from start-col to end-col do
        (let* ((px (- (col-left x) +header-w+))
               (w (col-width x))
               (px2 (+ px w))
               (col-name (string (code-char (+ (char-code #\A) x)))))
          (push (format nil "~a create rectangle ~a 0 ~a ~a -fill {#e0e0e0} -outline gray"
                        path px px2 +header-h+)
                commands)
          (push (format nil "~a create text ~a ~a -anchor center -text {~a} -font {~a}"
                        path (+ px (floor w 2)) (floor +header-h+ 2) col-name header-font)
                commands))))
    (send-batch-commands commands)))

(defun draw-row-headers (canvas)
  "行番号ヘッダー(1,2,3...)を描画（表示範囲のみ v0.7.7）"
  (sync-scroll-position)
  (let ((path (widget-path canvas))
        (header-font (format nil "{~a} ~a bold" *font-family* *font-size*))
        (commands nil))
    (format-wish "~a delete all" path)
    (multiple-value-bind (start-col start-row end-col end-row)
        (visible-cell-range)
      (declare (ignore start-col end-col))
      (loop for y from start-row to end-row do
        (let* ((py (- (row-top y) +header-h+))
               (h (row-height y))
               (py2 (+ py h))
               (row-num (1+ y)))
          (push (format nil "~a create rectangle 0 ~a ~a ~a -fill {#e0e0e0} -outline gray"
                        path py +header-w+ py2)
                commands)
          (push (format nil "~a create text ~a ~a -anchor center -text {~a} -font {~a}"
                        path (floor +header-w+ 2) (+ py (floor h 2)) row-num header-font)
                commands))))
    (send-batch-commands commands)))

(defun draw-headers (canvas)
  "列名(A,B,C...)と行番号(1,2,3...)のヘッダーを描画（後方互換用・バッチ処理 v0.7.3）"
  (let ((path (widget-path canvas))
        (header-font (format nil "{~a} ~a bold" *font-family* *font-size*))
        (commands nil))
    ;; 左上隅の空白セル
    (push (format nil "~a create rectangle 0 0 ~a ~a -fill {#e0e0e0} -outline gray"
                  path +header-w+ +header-h+)
          commands)
    ;; 列名ヘッダー
    (dotimes (x (sheet-cols))
      (let* ((px (col-left x))
             (w (col-width x))
             (px2 (+ px w))
             (col-name (string (code-char (+ (char-code #\A) x)))))
        (push (format nil "~a create rectangle ~a 0 ~a ~a -fill {#e0e0e0} -outline gray"
                      path px px2 +header-h+)
              commands)
        (push (format nil "~a create text ~a ~a -anchor center -text {~a} -font {~a}"
                      path (+ px (floor w 2)) (floor +header-h+ 2) col-name header-font)
              commands)))
    ;; 行番号ヘッダー
    (dotimes (y (sheet-rows))
      (let* ((py (row-top y))
             (h (row-height y))
             (py2 (+ py h))
             (row-num (1+ y)))
        (push (format nil "~a create rectangle 0 ~a ~a ~a -fill {#e0e0e0} -outline gray"
                      path py +header-w+ py2)
              commands)
        (push (format nil "~a create text ~a ~a -anchor center -text {~a} -font {~a}"
                      path (floor +header-w+ 2) (+ py (floor h 2)) row-num header-font)
              commands)))
    (send-batch-commands commands)))

(defun update-scroll-region (canvas)
  "スクロール領域を更新（4キャンバス対応 v0.7.2）"
  (let ((cells-w (- (total-width) +header-w+))
        (cells-h (- (total-height) +header-h+)))
    (if (and *col-header-canvas* *row-header-canvas* *main-canvas*)
        (progn
          (format-wish "~a configure -scrollregion {0 0 ~d ~d}"
                       (widget-path *col-header-canvas*) cells-w +header-h+)
          (format-wish "~a configure -scrollregion {0 0 ~d ~d}"
                       (widget-path *row-header-canvas*) +header-w+ cells-h)
          (format-wish "~a configure -scrollregion {0 0 ~d ~d}"
                       (widget-path *main-canvas*) cells-w cells-h))
        ;; 後方互換
        (format-wish "~a configure -scrollregion {0 0 ~d ~d}"
                     (widget-path canvas) (total-width) (total-height)))))

(defun scroll-to-cursor (canvas)
  "カーソルが表示枠外にある場合のみスクロール（v0.8.0改良）
   スクロールが発生した場合は全体再描画を行う"
  ;; まずTkの実際のスクロール位置と同期
  (sync-scroll-position)
  (let* ((main-canvas (or *main-canvas* canvas))
         ;; セル領域のサイズ
         (cells-w (- (total-width) +header-w+))
         (cells-h (- (total-height) +header-h+))
         ;; 表示領域のサイズ
         (visible-w (- (visible-width) +header-w+))
         (visible-h (- (visible-height) +header-h+))
         ;; カーソルセルの位置（セル領域内座標）
         (cursor-left (- (col-left (cursor-x)) +header-w+))
         (cursor-right (+ cursor-left (col-width (cursor-x))))
         (cursor-top (- (row-top (cursor-y)) +header-h+))
         (cursor-bottom (+ cursor-top (row-height (cursor-y))))
         ;; 現在のスクロール位置（ピクセル）
         (scroll-left *scroll-x*)
         (scroll-top *scroll-y*)
         (scroll-right (+ scroll-left visible-w))
         (scroll-bottom (+ scroll-top visible-h))
         ;; スクロールが発生したかどうか
         (scrolled nil))
    ;; 水平方向チェック
    (when (> cells-w visible-w)
      (cond
        ;; カーソルが左にはみ出し
        ((< cursor-left scroll-left)
         (let ((xpos (/ (float cursor-left) cells-w)))
           (format-wish "~a xview moveto ~f" (widget-path main-canvas) xpos)
           (when *col-header-canvas*
             (format-wish "~a xview moveto ~f" (widget-path *col-header-canvas*) xpos))
           (setf *scroll-x* cursor-left)
           (setf scrolled t)))
        ;; カーソルが右にはみ出し
        ((> cursor-right scroll-right)
         (let* ((new-left (- cursor-right visible-w))
                (xpos (/ (float new-left) cells-w)))
           (format-wish "~a xview moveto ~f" (widget-path main-canvas) xpos)
           (when *col-header-canvas*
             (format-wish "~a xview moveto ~f" (widget-path *col-header-canvas*) xpos))
           (setf *scroll-x* new-left)
           (setf scrolled t)))))
    ;; 垂直方向チェック
    (when (> cells-h visible-h)
      (cond
        ;; カーソルが上にはみ出し
        ((< cursor-top scroll-top)
         (let ((ypos (/ (float cursor-top) cells-h)))
           (format-wish "~a yview moveto ~f" (widget-path main-canvas) ypos)
           (when *row-header-canvas*
             (format-wish "~a yview moveto ~f" (widget-path *row-header-canvas*) ypos))
           (setf *scroll-y* cursor-top)
           (setf scrolled t)))
        ;; カーソルが下にはみ出し
        ((> cursor-bottom scroll-bottom)
         (let* ((new-top (- cursor-bottom visible-h))
                (ypos (/ (float new-top) cells-h)))
           (format-wish "~a yview moveto ~f" (widget-path main-canvas) ypos)
           (when *row-header-canvas*
             (format-wish "~a yview moveto ~f" (widget-path *row-header-canvas*) ypos))
           (setf *scroll-y* new-top)
           (setf scrolled t)))))
    ;; スクロールが発生した場合は全体再描画
    (when scrolled
      (redraw canvas))))

;;; ============================
;;; 複数キャンバス対応描画関数 (v0.7.2)
;;; バッチ処理対応 (v0.7.3)
;;; ============================

(defun draw-cell-background-offset (canvas x y val selected in-selection offset-x offset-y)
  "セルの背景のみを描画（オフセット指定版）- 非バッチ用"
  (let* ((px (- (col-left x) offset-x))
         (py (- (row-top y) offset-y))
         (w (col-width x))
         (h (row-height y))
         (px2 (+ px w))
         (py2 (+ py h))
         (bg (cell-bg-color val selected in-selection))
         (path (widget-path canvas)))
    (format-wish "~a create rectangle ~a ~a ~a ~a -fill {~a} -outline gray"
                 path px py px2 py2 bg)))

(defun draw-cell-text-offset (canvas x y val offset-x offset-y)
  "セルのテキストのみを描画（オフセット指定版）- 非バッチ用"
  (when val
    (let* ((px (- (col-left x) offset-x))
           (py (- (row-top y) offset-y))
           (w (col-width x))
           (h (row-height y))
           (raw-text (format-value val))
           ;; 全角文字を考慮して保守的に計算（全角=14px, 半角=7px として表示幅2=14px）
           (available-width (- w 12))  ; 左右マージン6pxずつ
           (char-pixel-width 7)        ; 半角文字の幅（表示幅1=7px）
           (available-chars (floor available-width char-pixel-width))
           (display-text (if (> (string-display-width raw-text) available-chars)
                            (truncate-to-display-width raw-text (max 1 (- available-chars 1)))
                            raw-text))
           (path (widget-path canvas))
           (is-number (numberp val))
           (font-spec (format nil "{~a} ~a" *font-family* *font-size*)))
      (if is-number
          (format-wish "~a create text ~a ~a -anchor e -text {~a} -font {~a}"
                       path (+ px w -6) (+ py (floor h 2)) display-text font-spec)
          (format-wish "~a create text ~a ~a -anchor w -text {~a} -font {~a}"
                       path (+ px 6) (+ py (floor h 2)) display-text font-spec)))))

(defun make-cell-bg-command (path x y val selected in-selection offset-x offset-y)
  "セル背景描画コマンドを生成（バッチ用 v0.7.3）"
  (let* ((px (- (col-left x) offset-x))
         (py (- (row-top y) offset-y))
         (w (col-width x))
         (h (row-height y))
         (px2 (+ px w))
         (py2 (+ py h))
         (bg (cell-bg-color val selected in-selection)))
    (format nil "~a create rectangle ~a ~a ~a ~a -fill {~a} -outline gray"
            path px py px2 py2 bg)))

(defun make-cell-bg-command-tagged (path x y val selected in-selection offset-x offset-y)
  "セル背景描画コマンドを生成（タグ付き v0.8.0）"
  (let* ((px (- (col-left x) offset-x))
         (py (- (row-top y) offset-y))
         (w (col-width x))
         (h (row-height y))
         (px2 (+ px w))
         (py2 (+ py h))
         (bg (cell-bg-color val selected in-selection))
         (tag (format nil "cell_~d_~d" x y)))
    (format nil "~a create rectangle ~a ~a ~a ~a -fill {~a} -outline gray -tags ~a"
            path px py px2 py2 bg tag)))

(defun make-cell-text-command (path x y val offset-x offset-y)
  "セルテキスト描画コマンドを生成（バッチ用 v0.7.3）"
  (when val
    (let* ((px (- (col-left x) offset-x))
           (py (- (row-top y) offset-y))
           (w (col-width x))
           (h (row-height y))
           (raw-text (format-value val))
           (available-width (- w 12))
           (char-pixel-width 7)
           (available-chars (floor available-width char-pixel-width))
           (display-text (if (> (string-display-width raw-text) available-chars)
                            (truncate-to-display-width raw-text (max 1 (- available-chars 1)))
                            raw-text))
           (is-number (numberp val))
           (font-spec (format nil "{~a} ~a" *font-family* *font-size*))
           ;; テキスト内の特殊文字をエスケープ
           (safe-text (escape-tcl-string display-text)))
      (if is-number
          (format nil "~a create text ~a ~a -anchor e -text {~a} -font {~a}"
                  path (+ px w -6) (+ py (floor h 2)) safe-text font-spec)
          (format nil "~a create text ~a ~a -anchor w -text {~a} -font {~a}"
                  path (+ px 6) (+ py (floor h 2)) safe-text font-spec)))))

(defun make-cell-text-command-tagged (path x y val offset-x offset-y)
  "セルテキスト描画コマンドを生成（タグ付き v0.8.0）"
  (when val
    (let* ((px (- (col-left x) offset-x))
           (py (- (row-top y) offset-y))
           (w (col-width x))
           (h (row-height y))
           (raw-text (format-value val))
           (available-width (- w 12))
           (char-pixel-width 7)
           (available-chars (floor available-width char-pixel-width))
           (display-text (if (> (string-display-width raw-text) available-chars)
                            (truncate-to-display-width raw-text (max 1 (- available-chars 1)))
                            raw-text))
           (is-number (numberp val))
           (font-spec (format nil "{~a} ~a" *font-family* *font-size*))
           (safe-text (escape-tcl-string display-text))
           (tag (format nil "cell_~d_~d" x y)))
      (if is-number
          (format nil "~a create text ~a ~a -anchor e -text {~a} -font {~a} -tags ~a"
                  path (+ px w -6) (+ py (floor h 2)) safe-text font-spec tag)
          (format nil "~a create text ~a ~a -anchor w -text {~a} -font {~a} -tags ~a"
                  path (+ px 6) (+ py (floor h 2)) safe-text font-spec tag)))))

;;;; =========================
;;;; 単一セル更新 (v0.8.0 差分更新)
;;;; =========================

(defun redraw-single-cell (canvas x y)
  "単一セルを再描画（差分更新 v0.8.0）"
  (when (and *main-canvas* (>= x 0) (>= y 0)
             (< x (sheet-cols)) (< y (sheet-rows)))
    (let* ((path (widget-path (or canvas *main-canvas*)))
           (cell (get-cell (cell-name x y)))
           (val (cell-value cell))
           (selected (and (= x (cursor-x)) (= y (cursor-y))))
           (in-selection (cell-in-selection-p x y))
           (tag (format nil "cell_~d_~d" x y)))
      ;; 古い描画を削除
      (format-wish "~a delete ~a" path tag)
      ;; 背景を描画
      (format-wish "~a" (make-cell-bg-command-tagged path x y val selected in-selection
                                                     +header-w+ +header-h+))
      ;; テキストを描画
      (let ((text-cmd (make-cell-text-command-tagged path x y val +header-w+ +header-h+)))
        (when text-cmd
          (format-wish "~a" text-cmd))))))

(defun escape-tcl-string (str)
  "Tcl文字列内の特殊文字をエスケープ（v0.7.3）"
  (if (or (find #\{ str) (find #\} str) (find #\\ str) (find #\; str))
      ;; 特殊文字がある場合はダブルクォートで囲む
      (with-output-to-string (out)
        (loop for c across str do
          (case c
            (#\\ (write-string "\\\\" out))
            (#\" (write-string "\\\"" out))
            (#\[ (write-string "\\[" out))
            (#\] (write-string "\\]" out))
            (#\$ (write-string "\\$" out))
            (t (write-char c out)))))
      str))

(defun draw-cells-only (canvas)
  "セル部分のみを描画（表示範囲のみ、タグ付き v0.8.0）"
  (sync-scroll-position)
  (let ((path (widget-path canvas))
        (commands nil))
    (format-wish "~a delete all" path)
    (multiple-value-bind (start-col start-row end-col end-row)
        (visible-cell-range)
      ;; パス1: 表示範囲のセルの背景コマンドを収集（タグ付き）
      (loop for y from start-row to end-row do
        (loop for x from start-col to end-col do
          (let ((cell (get-cell (cell-name x y))))
            (push (make-cell-bg-command-tagged path x y
                                        (cell-value cell)
                                        (and (= x (cursor-x)) (= y (cursor-y)))
                                        (cell-in-selection-p x y)
                                        +header-w+ +header-h+)
                  commands))))
      ;; パス2: 表示範囲のセルのテキストコマンドを収集（タグ付き）
      (loop for y from start-row to end-row do
        (loop for x from start-col to end-col do
          (let* ((cell (get-cell (cell-name x y)))
                 (text-cmd (make-cell-text-command-tagged path x y (cell-value cell)
                                                   +header-w+ +header-h+)))
            (when text-cmd
              (push text-cmd commands))))))
    ;; バッチ送信
    (send-batch-commands commands)))

(defun redraw-all (corner-canvas col-header-canvas row-header-canvas main-canvas)
  "4つのキャンバスすべてを再描画（ヘッダー固定対応）"
  (draw-corner corner-canvas)
  (draw-col-headers col-header-canvas)
  (draw-row-headers row-header-canvas)
  (draw-cells-only main-canvas))

(defun redraw (canvas)
  "画面全体を再描画（4キャンバス対応 v0.7.2、バッチ処理 v0.7.3）"
  ;; グローバルキャンバス参照がある場合は4キャンバス描画
  (if (and *corner-canvas* *col-header-canvas* *row-header-canvas* *main-canvas*)
      (progn
        (draw-corner *corner-canvas*)
        (draw-col-headers *col-header-canvas*)
        (draw-row-headers *row-header-canvas*)
        (draw-cells-only *main-canvas*))
      ;; 後方互換：単一キャンバスモード（バッチ処理 v0.7.3）
      (let ((path (widget-path canvas))
            (commands nil))
        (format-wish "~a delete all" path)
        (draw-headers canvas)
        ;; パス1: 全セルの背景コマンドを収集
        (dotimes (y (sheet-rows))
          (dotimes (x (sheet-cols))
            (let* ((cell (get-cell (cell-name x y)))
                   (val (cell-value cell))
                   (selected (and (= x (cursor-x)) (= y (cursor-y))))
                   (in-sel (cell-in-selection-p x y))
                   (px (col-left x))
                   (py (row-top y))
                   (w (col-width x))
                   (h (row-height y))
                   (bg (cell-bg-color val selected in-sel)))
              (push (format nil "~a create rectangle ~a ~a ~a ~a -fill {~a} -outline gray"
                            path px py (+ px w) (+ py h) bg)
                    commands))))
        ;; パス2: 全セルのテキストコマンドを収集
        (let ((font-spec (format nil "{~a} ~a" *font-family* *font-size*)))
          (dotimes (y (sheet-rows))
            (dotimes (x (sheet-cols))
              (let ((val (cell-value (get-cell (cell-name x y)))))
                (when val
                  (let* ((px (col-left x))
                         (py (row-top y))
                         (w (col-width x))
                         (h (row-height y))
                         (raw-text (format-value val))
                         (available-width (- w 12))
                         (available-chars (floor available-width 7))
                         (display-text (if (> (string-display-width raw-text) available-chars)
                                          (truncate-to-display-width raw-text (max 1 (- available-chars 1)))
                                          raw-text))
                         (safe-text (escape-tcl-string display-text)))
                    (if (numberp val)
                        (push (format nil "~a create text ~a ~a -anchor e -text {~a} -font {~a}"
                                      path (+ px w -6) (+ py (floor h 2)) safe-text font-spec)
                              commands)
                        (push (format nil "~a create text ~a ~a -anchor w -text {~a} -font {~a}"
                                      path (+ px 6) (+ py (floor h 2)) safe-text font-spec)
                              commands))))))))
        ;; バッチ送信
        (send-batch-commands commands))))

;;;; =========================
;;;; 入力欄（Text）の操作
;;;; =========================

(defun get-text-content (text-widget)
  "Textウィジェットの内容を取得"
  (let ((content (text text-widget)))
    ;; 末尾の改行を除去
    (string-right-trim '(#\Newline #\Return) content)))

(defun set-text-content (text-widget s)
  "Textウィジェットに文字列を設定"
  (setf (text text-widget) (if s (princ-to-string s) "")))

;;;; =========================
;;;; Syntax Highlighting
;;;; =========================

(defparameter *rainbow-colors*
  '("#E00000"    ; 深さ0: 赤
    "#0000FF"    ; 深さ1: 青
    "#008800"    ; 深さ2: 緑
    "#DD6600"    ; 深さ3: オレンジ
    "#AA00AA"    ; 深さ4: 紫
    "#007777")   ; 深さ5: シアン
  "Rainbow括弧の色リスト（深さに応じて循環）")

(defparameter *syntax-colors*
  '((:string    . "#B8860B")    ; 文字列: ダークゴールデンロッド
    (:number    . "#008888")    ; 数値: ティール
    (:keyword   . "#9932CC")    ; キーワード: ダークオーキッド
    (:cell-ref  . "#228B22")    ; セル参照: フォレストグリーン
    (:function  . "#0000CD")    ; 関数名: ミディアムブルー
    (:special   . "#DC143C")    ; 特殊シンボル: クリムゾン
    (:rel-ref   . "#006400"))   ; 相対参照: ダークグリーン
  "シンタックスハイライトの色定義")

(defparameter *known-functions*
  '("+" "-" "*" "/" "=" "/=" "<" ">" "<=" ">=" 
    "if" "cond" "and" "or" "not"
    "sum" "avg" "count" "cell-count" "max" "min"
    "mapcar" "mapc" "maplist" "mapcan" "mapcon" "reduce"
    "remove-if" "remove-if-not" "remove-duplicates"
    "count-if" "count-if-not" "find" "find-if" "position" "position-if"
    "substitute" "substitute-if" "substitute-if-not"
    "every" "some" "notevery" "notany"
    "intersection" "union" "set-difference" "set-exclusive-or" "subsetp"
    "search" "mismatch"
    "assoc" "assoc-if" "rassoc" "rassoc-if" "pairlis" "acons" "getf"
    "apply" "funcall" "lambda" "function" "let" "let*" "setf"
    "list" "cons" "car" "cdr" "first" "rest" "nth" "length" "elt"
    "append" "reverse" "sort" "stable-sort" "concatenate" "member" "subseq"
    "copy-list" "copy-seq" "copy-tree" "copy-alist"
    "abs" "sqrt" "expt" "exp" "log" "sin" "cos" "tan"
    "floor" "ceiling" "round" "truncate" "mod" "rem"
    "random" "logand" "logior" "logxor" "lognot" "ash"
    "string" "string-upcase" "string-downcase" "char"
    "char=" "char-equal" "digit-char"
    "format" "parse-integer" "type-of" "typep" "coerce"
    "range" "iota" "this-row" "this-col" "this-col-name" "this-cell-name" "cell-at"
    "quote")
  "ハイライト対象の関数名リスト")

(defparameter *special-symbols*
  '("t" "nil")
  "特殊シンボルリスト")

(defparameter *rel-symbols*
  '("rel" "rel-range")
  "相対参照シンボルリスト")

(defun setup-syntax-tags (text-widget)
  "Textウィジェットにシンタックスハイライト用タグを設定"
  ;; Rainbow括弧のタグ
  (loop for color in *rainbow-colors*
        for i from 0
        do (format-wish "~a tag configure paren~d -foreground {~a}"
                        (widget-path text-widget) i color))
  ;; 不一致括弧用のタグ（赤背景）
  (format-wish "~a tag configure paren-error -foreground white -background red"
               (widget-path text-widget))
  ;; シンタックス要素のタグ
  (format-wish "~a tag configure syn-string -foreground {~a}"
               (widget-path text-widget) (cdr (assoc :string *syntax-colors*)))
  (format-wish "~a tag configure syn-number -foreground {~a}"
               (widget-path text-widget) (cdr (assoc :number *syntax-colors*)))
  (format-wish "~a tag configure syn-keyword -foreground {~a}"
               (widget-path text-widget) (cdr (assoc :keyword *syntax-colors*)))
  (format-wish "~a tag configure syn-cell-ref -foreground {~a}"
               (widget-path text-widget) (cdr (assoc :cell-ref *syntax-colors*)))
  (format-wish "~a tag configure syn-function -foreground {~a}"
               (widget-path text-widget) (cdr (assoc :function *syntax-colors*)))
  (format-wish "~a tag configure syn-special -foreground {~a}"
               (widget-path text-widget) (cdr (assoc :special *syntax-colors*)))
  (format-wish "~a tag configure syn-rel-ref -foreground {~a}"
               (widget-path text-widget) (cdr (assoc :rel-ref *syntax-colors*))))

(defun pos-to-tk-index (content pos)
  "文字位置をTkのline.col形式に変換"
  (let* ((before (subseq content 0 pos))
         (line (1+ (count #\Newline before)))
         (last-nl (position #\Newline before :from-end t))
         (col (if last-nl (- pos last-nl 1) pos)))
    (format nil "~d.~d" line col)))

(defun add-syntax-tag (text-widget content tag start end)
  "指定範囲にシンタックスタグを適用"
  (let ((tk-start (pos-to-tk-index content start))
        (tk-end (pos-to-tk-index content end)))
    (format-wish "~a tag add ~a ~a ~a"
                 (widget-path text-widget) tag tk-start tk-end)))

(defun symbol-char-p (char)
  "シンボルを構成できる文字か判定"
  (or (alphanumericp char)
      (find char "+-*/<>=!?_")))

(defun syntax-highlight (text-widget)
  "Textウィジェット内をシンタックスハイライトする"
  (let* ((content (text text-widget))
         (len (length content))
         (num-colors (length *rainbow-colors*))
         ;; 解析用状態
         (i 0)
         (depth 0)
         (paren-positions nil)
         (tokens nil))  ; ((type start end) ...)
    
    ;; 既存のタグを削除
    (loop for j from 0 below num-colors
          do (format-wish "~a tag remove paren~d 1.0 end"
                          (widget-path text-widget) j))
    (format-wish "~a tag remove paren-error 1.0 end" (widget-path text-widget))
    (dolist (tag '("syn-string" "syn-number" "syn-keyword" 
                   "syn-cell-ref" "syn-function" "syn-special" "syn-rel-ref"))
      (format-wish "~a tag remove ~a 1.0 end" (widget-path text-widget) tag))
    
    ;; トークン解析
    (loop while (< i len) do
      (let ((char (char content i)))
        (cond
          ;; 文字列
          ((char= char #\")
           (let ((start i))
             (incf i)
             (loop while (< i len)
                   for c = (char content i)
                   do (cond
                        ((char= c #\\) (incf i 2))  ; エスケープをスキップ
                        ((char= c #\") (incf i) (return))
                        (t (incf i))))
             (push (list :string start i) tokens)))
          
          ;; キーワード
          ((char= char #\:)
           (let ((start i))
             (incf i)
             (loop while (and (< i len) (symbol-char-p (char content i)))
                   do (incf i))
             (when (> i (1+ start))
               (push (list :keyword start i) tokens))))
          
          ;; 開き括弧と関数名
          ((char= char #\()
           (push (cons i depth) paren-positions)
           (incf depth)
           (incf i)
           ;; 括弧直後のシンボルを関数名として検出
           (loop while (and (< i len) (find (char content i) " ~%	"))
                 do (incf i))
           (when (and (< i len) (symbol-char-p (char content i)))
             (let ((start i))
               (loop while (and (< i len) (symbol-char-p (char content i)))
                     do (incf i))
               (let ((sym (subseq content start i)))
                 (cond
                   ;; 相対参照
                   ((member sym *rel-symbols* :test #'string-equal)
                    (push (list :rel-ref start i) tokens))
                   ;; 既知の関数
                   ((member sym *known-functions* :test #'string-equal)
                    (push (list :function start i) tokens))
                   ;; セル参照 (関数位置でも)
                   ((and (>= (length sym) 2)
                         (<= (length sym) 4)
                         (alpha-char-p (char sym 0))
                         (every #'digit-char-p (subseq sym 1)))
                    (push (list :cell-ref start i) tokens)))))))
          
          ;; 閉じ括弧
          ((char= char #\))
           (decf depth)
           (if (< depth 0)
               (progn
                 (push (cons i -1) paren-positions)
                 (setf depth 0))
               (push (cons i depth) paren-positions))
           (incf i))
          
          ;; 数値（符号付きも対応）
          ((or (digit-char-p char)
               (and (or (char= char #\-) (char= char #\+))
                    (< (1+ i) len)
                    (digit-char-p (char content (1+ i)))))
           (let ((start i))
             (when (or (char= char #\-) (char= char #\+))
               (incf i))
             (loop while (and (< i len) 
                              (or (digit-char-p (char content i))
                                  (char= (char content i) #\.)))
                   do (incf i))
             ;; 指数表記
             (when (and (< i len) (find (char content i) "eE"))
               (incf i)
               (when (and (< i len) (find (char content i) "+-"))
                 (incf i))
               (loop while (and (< i len) (digit-char-p (char content i)))
                     do (incf i)))
             (push (list :number start i) tokens)))
          
          ;; シンボル（セル参照、特殊シンボル）
          ((alpha-char-p char)
           (let ((start i))
             (loop while (and (< i len) (symbol-char-p (char content i)))
                   do (incf i))
             (let ((sym (subseq content start i)))
               (cond
                 ;; 相対参照
                 ((member sym *rel-symbols* :test #'string-equal)
                  (push (list :rel-ref start i) tokens))
                 ;; 特殊シンボル
                 ((member sym *special-symbols* :test #'string-equal)
                  (push (list :special start i) tokens))
                 ;; セル参照 (A1-Z99, AA1-ZZ99形式)
                 ((and (>= (length sym) 2)
                       (<= (length sym) 4)
                       (alpha-char-p (char sym 0))
                       (or (and (= (length sym) 2)
                                (digit-char-p (char sym 1)))
                           (and (>= (length sym) 2)
                                (let ((first-digit-pos 
                                       (position-if #'digit-char-p sym)))
                                  (and first-digit-pos
                                       (> first-digit-pos 0)
                                       (every #'alpha-char-p (subseq sym 0 first-digit-pos))
                                       (every #'digit-char-p (subseq sym first-digit-pos)))))))
                  (push (list :cell-ref start i) tokens))))))
          
          ;; その他
          (t (incf i)))))
    
    ;; タグを適用
    ;; 括弧（Rainbow）
    (dolist (pp paren-positions)
      (let* ((pos (car pp))
             (d (cdr pp))
             (tk-start (pos-to-tk-index content pos))
             (tk-end (pos-to-tk-index content (1+ pos))))
        (if (= d -1)
            (format-wish "~a tag add paren-error ~a ~a"
                         (widget-path text-widget) tk-start tk-end)
            (format-wish "~a tag add paren~d ~a ~a"
                         (widget-path text-widget) 
                         (mod d num-colors) tk-start tk-end))))
    
    ;; その他のトークン
    (dolist (tok tokens)
      (let ((type (first tok))
            (start (second tok))
            (end (third tok)))
        (add-syntax-tag text-widget content
                        (case type
                          (:string "syn-string")
                          (:number "syn-number")
                          (:keyword "syn-keyword")
                          (:cell-ref "syn-cell-ref")
                          (:function "syn-function")
                          (:special "syn-special")
                          (:rel-ref "syn-rel-ref"))
                        start end)))))

;; 後方互換性のためのエイリアス
(defun setup-rainbow-tags (text-widget)
  (setup-syntax-tags text-widget))

(defun colorize-parentheses (text-widget)
  (syntax-highlight text-widget))

;;;; =========================
;;;; S式フォーマッター
;;;; =========================

(defun pprint-to-string (form)
  "S式を整形して文字列に変換"
  (let ((*print-pretty* t)
        (*print-right-margin* 60)
        (*print-miser-width* 40)
        (*package* (find-package :ssexp)))
    (with-output-to-string (s)
      (pprint form s))))

(defun format-sexp (text-widget)
  "入力枠のS式を整形する"
  (let* ((content (get-text-content text-widget))
         (trimmed (string-trim '(#\Space #\Tab #\Newline) content)))
    (when (and (> (length trimmed) 0)
               (char= (char trimmed 0) #\=))
      ;; =で始まる数式の場合
      (handler-case
          (let* ((*package* (find-package :ssexp))
                 (form (read-from-string (subseq trimmed 1)))
                 (formatted (string-trim '(#\Newline) (pprint-to-string form))))
            (set-text-content text-widget (format nil "=~a" formatted))
            (syntax-highlight text-widget))
        (error (e)
          ;; パースエラーの場合はメッセージ表示
          (format t "Format error: ~a~%" e))))))

(defun update-text-input (text-widget)
  "現在セルの内容をTextウィジェットに表示"
  (let ((c (current-cell))
        (*package* (find-package :ssexp)))  ; パッケージプレフィックスなしで表示
    (cond
      ;; 数式があれば =(...) 形式で表示
      ((cell-formula c)
       (set-text-content text-widget (format nil "=~S" (cell-formula c))))
      ;; 値があればそのまま表示
      ((cell-value c)
       (set-text-content text-widget (format nil "~S" (cell-value c))))
      (t
       (set-text-content text-widget ""))))
  ;; Rainbow括弧の色分けを更新
  (colorize-parentheses text-widget))

(defun format-error-message (error-type details)
  "エラーメッセージを整形"
  (case error-type
    (:syntax (format nil "#構文: ~a" details))
    (:eval   (format nil "#評価: ~a" details))
    (:ref    (format nil "#参照: ~a" details))
    (:circular (format nil "#循環: ~a" details))
    (t (format nil "#ERR: ~a" details))))

(defun commit-text-input (text-widget canvas)
  "Textウィジェットの内容をセルに確定"
  (let* ((raw (or (get-text-content text-widget) ""))
         (cell (current-cell))
         (cell-nm (cell-name (cursor-x) (cursor-y)))
         ;; Undo用に変更前の状態を保存
         (old-value (cell-value cell))
         (old-formula (cell-formula cell))
         (error-occurred nil))
    ;; 評価位置を設定
    (setf (eval-col) (cursor-x)
          (eval-row) (cursor-y))
    (if (and (> (length raw) 0)
             (char= (char raw 0) #\=))
        ;; =で始まる → 数式として解析・評価
        (let ((form nil))
          ;; 構文解析
          (handler-case
              (let ((*package* (find-package :ssexp)))
                (setf form (read-from-string (subseq raw 1))))
            (end-of-file ()
              (setf (cell-value cell) (format-error-message :syntax "式が不完全です")
                    (cell-formula cell) nil
                    error-occurred t))
            (error (e)
              (setf (cell-value cell) (format-error-message :syntax (princ-to-string e))
                    (cell-formula cell) nil
                    error-occurred t)))
          ;; 評価（構文解析が成功した場合のみ）
          (unless error-occurred
            (handler-case
                (let* ((*eval-stack* (list cell-nm))  ; 循環参照検出用
                       (value (eval-formula form))
                       (refs (extract-references form (cursor-y) (cursor-x))))
                  (setf (cell-formula cell) form
                        (cell-value cell) value)
                  ;; 依存関係を更新
                  (update-dependencies cell-nm refs))
              (error (e)
                (let ((msg (princ-to-string e)))
                  ;; 循環参照エラーを検出
                  (if (search "循環参照" msg)
                      (setf (cell-value cell) (format-error-message :circular cell-nm))
                      (setf (cell-value cell) (format-error-message :eval msg)))
                  ;; エラー時も数式を保持（再編集可能に）
                  (setf (cell-formula cell) form)
                  (update-dependencies cell-nm nil))))))
        ;; それ以外 → 通常の値として解釈
        (let ((parsed (handler-case 
                          (let ((*package* (find-package :ssexp)))
                            (read-from-string raw))
                        (end-of-file () nil)
                        (error () raw))))
          (setf (cell-formula cell) nil
                (cell-value cell) (if (string= raw "") nil (or parsed raw)))
          ;; 数式がないので依存関係をクリア
          (update-dependencies cell-nm nil)))
    ;; 変更があった場合のみUndo履歴に記録
    (unless (and (equal old-value (cell-value cell))
                 (equal old-formula (cell-formula cell)))
      (record-cell-change cell-nm old-value old-formula))
    ;; 依存元を再計算
    (recalc-dependents cell-nm)
    (redraw canvas)))

(defun commit-and-move (text-widget canvas direction)
  "入力を確定して指定方向に移動
   direction: :down, :up, :right, :left, :stay"
  (commit-text-input text-widget canvas)
  (clear-selection)
  (case direction
    (:down  (when (< (cursor-y) (1- (sheet-rows))) (incf (cursor-y))))
    (:up    (when (> (cursor-y) 0) (decf (cursor-y))))
    (:right (when (< (cursor-x) (1- (sheet-cols))) (incf (cursor-x))))
    (:left  (when (> (cursor-x) 0) (decf (cursor-x))))
    (:stay  nil))
  (setf (selection-start-x) (cursor-x)
        (selection-start-y) (cursor-y)
        (selection-end-x) (cursor-x)
        (selection-end-y) (cursor-y))
  (update-text-input text-widget)
  (redraw canvas)
  (scroll-to-cursor canvas))

;;; 後方互換性のため旧関数も残す
(defun entry-text (e) (get-text-content e))
(defun set-entry-text (e s) (set-text-content e s))
(defun update-entry (e) (update-text-input e))
(defun commit-entry (e c) (commit-text-input e c))

;;;; =========================
;;;; カーソル移動
;;;; =========================

(defun clamp (v lo hi)
  "値を範囲内に制限"
  (max lo (min hi v)))

(defun move-left (canvas text-widget)
  "左に移動（差分更新 v0.8.0）"
  (let ((old-x (cursor-x))
        (old-y (cursor-y)))
    (setf (cursor-x) (max 0 (1- (cursor-x))))
    (update-text-input text-widget)
    ;; 差分更新: 旧位置と新位置のみ再描画
    (redraw-single-cell canvas old-x old-y)
    (redraw-single-cell canvas (cursor-x) (cursor-y))
    (scroll-to-cursor canvas)))

(defun move-right (canvas text-widget)
  "右に移動（差分更新 v0.8.0）"
  (let ((old-x (cursor-x))
        (old-y (cursor-y)))
    (setf (cursor-x) (min (1- (sheet-cols)) (1+ (cursor-x))))
    (update-text-input text-widget)
    ;; 差分更新: 旧位置と新位置のみ再描画
    (redraw-single-cell canvas old-x old-y)
    (redraw-single-cell canvas (cursor-x) (cursor-y))
    (scroll-to-cursor canvas)))

(defun move-up (canvas text-widget)
  "上に移動（差分更新 v0.8.0）"
  (let ((old-x (cursor-x))
        (old-y (cursor-y)))
    (setf (cursor-y) (max 0 (1- (cursor-y))))
    (update-text-input text-widget)
    ;; 差分更新: 旧位置と新位置のみ再描画
    (redraw-single-cell canvas old-x old-y)
    (redraw-single-cell canvas (cursor-x) (cursor-y))
    (scroll-to-cursor canvas)))

(defun move-down (canvas text-widget)
  "下に移動（差分更新 v0.8.0）"
  (let ((old-x (cursor-x))
        (old-y (cursor-y)))
    (setf (cursor-y) (min (1- (sheet-rows)) (1+ (cursor-y))))
    (update-text-input text-widget)
    ;; 差分更新: 旧位置と新位置のみ再描画
    (redraw-single-cell canvas old-x old-y)
    (redraw-single-cell canvas (cursor-x) (cursor-y))
    (scroll-to-cursor canvas)))

;;;; =========================
;;;; ダイアログ
;;;; =========================

;; 入力ダイアログの結果を保持する変数
(defparameter *input-dialog-result* nil)

(defun show-size-dialog (title prompt default-value callback)
  "サイズ入力ダイアログを表示。callbackは入力値を受け取る関数"
  ;; ダイアログウィンドウを作成
  (let* ((dlg (make-instance 'toplevel))
         (lbl (make-instance 'label :master dlg :text prompt))
         (ent (make-instance 'entry :master dlg :width 15))
         (btn-frame (make-instance 'frame :master dlg))
         (ok-btn (make-instance 'button :master btn-frame :text "OK" :width 8))
         (cancel-btn (make-instance 'button :master btn-frame :text "Cancel" :width 8)))
    
    ;; ウィンドウ設定
    (wm-title dlg title)
    (format-wish "wm transient ~a ." (widget-path dlg))
    (format-wish "wm resizable ~a 0 0" (widget-path dlg))
    
    ;; 初期値を設定
    (setf (text ent) (princ-to-string default-value))
    
    ;; OKボタンの動作
    (setf (command ok-btn)
          (lambda ()
            (let* ((input (text ent))
                   (value (ignore-errors (parse-integer input))))
              (destroy dlg)
              (when (and value (> value 0))
                (funcall callback value)))))
    
    ;; キャンセルボタンの動作
    (setf (command cancel-btn)
          (lambda ()
            (destroy dlg)))
    
    ;; Enterキーでも確定
    (bind ent "<Return>"
          (lambda (evt)
            (declare (ignore evt))
            (let* ((input (text ent))
                   (value (ignore-errors (parse-integer input))))
              (destroy dlg)
              (when (and value (> value 0))
                (funcall callback value)))))
    
    ;; Escapeキーでキャンセル
    (bind dlg "<Escape>"
          (lambda (evt)
            (declare (ignore evt))
            (destroy dlg)))
    
    ;; レイアウト
    (pack lbl :padx 10 :pady 5)
    (pack ent :padx 10 :pady 5)
    (pack btn-frame :pady 10)
    (pack ok-btn :side :left :padx 5)
    (pack cancel-btn :side :left :padx 5)
    
    ;; フォーカスを入力欄に
    (focus ent)
    (format-wish "~a selection range 0 end" (widget-path ent))
    
    ;; モーダルにする
    (format-wish "grab ~a" (widget-path dlg))))

