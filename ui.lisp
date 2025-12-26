;;;; ui.lisp
;;;; SSP v0.7.2 - 描画、入力処理、シンタックスハイライト
;;;; v0.7: 日本語・Unicode対応（フォント設定、文字幅計算）

(in-package :ssexp)

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
;;;; 表示範囲計算 (v0.7.2 パフォーマンス改善)
;;;; =========================

(defun visible-cell-range ()
  "表示されているセル範囲を返す (values start-col start-row end-col end-row)
   注: Tkキャンバスが自動的にクリッピングするため、全範囲を返す"
  ;; シンプルに全範囲を返す（Tkがクリッピング処理）
  (values 0 0 (1- (sheet-cols)) (1- (sheet-rows))))

(defun draw-col-headers (canvas)
  "列名ヘッダー(A,B,C...)を描画"
  (let ((path (widget-path canvas))
        (header-font (format nil "{~a} ~a bold" *font-family* *font-size*)))
    (format-wish "~a delete all" path)
    (dotimes (x (sheet-cols))
      (let* ((px (- (col-left x) +header-w+))
             (w (col-width x))
             (px2 (+ px w))
             (col-name (string (code-char (+ (char-code #\A) x)))))
        (format-wish "~a create rectangle ~a 0 ~a ~a -fill {#e0e0e0} -outline gray"
                     path px px2 +header-h+)
        (format-wish "~a create text ~a ~a -anchor center -text {~a} -font {~a}"
                     path (+ px (floor w 2)) (floor +header-h+ 2) col-name header-font)))))

(defun draw-row-headers (canvas)
  "行番号ヘッダー(1,2,3...)を描画"
  (let ((path (widget-path canvas))
        (header-font (format nil "{~a} ~a bold" *font-family* *font-size*)))
    (format-wish "~a delete all" path)
    (dotimes (y (sheet-rows))
      (let* ((py (- (row-top y) +header-h+))
             (h (row-height y))
             (py2 (+ py h))
             (row-num (1+ y)))
        (format-wish "~a create rectangle 0 ~a ~a ~a -fill {#e0e0e0} -outline gray"
                     path py +header-w+ py2)
        (format-wish "~a create text ~a ~a -anchor center -text {~a} -font {~a}"
                     path (floor +header-w+ 2) (+ py (floor h 2)) row-num header-font)))))

(defun draw-headers (canvas)
  "列名(A,B,C...)と行番号(1,2,3...)のヘッダーを描画（後方互換用）"
  (let ((path (widget-path canvas))
        (header-font (format nil "{~a} ~a bold" *font-family* *font-size*)))
    ;; 左上隅の空白セル
    (format-wish "~a create rectangle 0 0 ~a ~a -fill {#e0e0e0} -outline gray"
                 path +header-w+ +header-h+)
    ;; 列名ヘッダー
    (dotimes (x (sheet-cols))
      (let* ((px (col-left x))
             (w (col-width x))
             (px2 (+ px w))
             (col-name (string (code-char (+ (char-code #\A) x)))))
        (format-wish "~a create rectangle ~a 0 ~a ~a -fill {#e0e0e0} -outline gray"
                     path px px2 +header-h+)
        (format-wish "~a create text ~a ~a -anchor center -text {~a} -font {~a}"
                     path (+ px (floor w 2)) (floor +header-h+ 2) col-name header-font)))
    ;; 行番号ヘッダー
    (dotimes (y (sheet-rows))
      (let* ((py (row-top y))
             (h (row-height y))
             (py2 (+ py h))
             (row-num (1+ y)))
        (format-wish "~a create rectangle 0 ~a ~a ~a -fill {#e0e0e0} -outline gray"
                     path py +header-w+ py2)
        (format-wish "~a create text ~a ~a -anchor center -text {~a} -font {~a}"
                     path (floor +header-w+ 2) (+ py (floor h 2)) row-num header-font)))))

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
  "カーソル位置が表示されるようにスクロール（4キャンバス対応 v0.7.2）"
  (let* ((cursor-left (- (col-left (cursor-x)) +header-w+))
         (cursor-right (+ cursor-left (col-width (cursor-x))))
         (cursor-top (- (row-top (cursor-y)) +header-h+))
         (cursor-bottom (+ cursor-top (row-height (cursor-y))))
         (cells-w (- (total-width) +header-w+))
         (cells-h (- (total-height) +header-h+))
         (visible-w (- (visible-width) +header-w+))
         (visible-h (- (visible-height) +header-h+))
         (main-canvas (or *main-canvas* canvas)))
    ;; 水平スクロール
    (when (> cells-w visible-w)
      (let ((xpos (max 0.0 (min (/ (float cursor-left) cells-w)
                                (- 1.0 (/ (float visible-w) cells-w))))))
        (format-wish "~a xview moveto ~f" (widget-path main-canvas) xpos)
        (when *col-header-canvas*
          (format-wish "~a xview moveto ~f" (widget-path *col-header-canvas*) xpos))))
    ;; 垂直スクロール
    (when (> cells-h visible-h)
      (let ((ypos (max 0.0 (min (/ (float cursor-top) cells-h)
                                (- 1.0 (/ (float visible-h) cells-h))))))
        (format-wish "~a yview moveto ~f" (widget-path main-canvas) ypos)
        (when *row-header-canvas*
          (format-wish "~a yview moveto ~f" (widget-path *row-header-canvas*) ypos))))))

;;; ============================
;;; 複数キャンバス対応描画関数 (v0.7.2)
;;; ============================

(defun draw-cell-background-offset (canvas x y val selected in-selection offset-x offset-y)
  "セルの背景のみを描画（オフセット指定版）"
  (let* ((px (- (col-left x) offset-x))
         (py (- (row-top y) offset-y))
         (w (col-width x))
         (h (row-height y))
         (px2 (+ px w))
         (py2 (+ py h))
         (bg (cond
               (selected "#cce5ff")
               (in-selection "#d0e8ff")
               ((null val) "white")
               ((listp val) "#f0fff0")
               ((and val (symbolp val)) "#fff0f0")
               ((stringp val) "#fffff0")
               (t "white")))
         (path (widget-path canvas)))
    (format-wish "~a create rectangle ~a ~a ~a ~a -fill {~a} -outline gray"
                 path px py px2 py2 bg)))

(defun draw-cell-text-offset (canvas x y val offset-x offset-y)
  "セルのテキストのみを描画（オフセット指定版）"
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

(defun draw-cells-only (canvas)
  "セル部分のみを描画（ヘッダーなし、オフセット適用）"
  (format-wish "~a delete all" (widget-path canvas))
  ;; パス1: 全セルの背景を描画
  (dotimes (y (sheet-rows))
    (dotimes (x (sheet-cols))
      (let ((cell (get-cell (cell-name x y))))
        (draw-cell-background-offset canvas x y
                                     (cell-value cell)
                                     (and (= x (cursor-x)) (= y (cursor-y)))
                                     (cell-in-selection-p x y)
                                     +header-w+ +header-h+))))
  ;; パス2: 全セルのテキストを描画
  (dotimes (y (sheet-rows))
    (dotimes (x (sheet-cols))
      (let ((cell (get-cell (cell-name x y))))
        (draw-cell-text-offset canvas x y (cell-value cell) +header-w+ +header-h+)))))

(defun redraw-all (corner-canvas col-header-canvas row-header-canvas main-canvas)
  "4つのキャンバスすべてを再描画（ヘッダー固定対応）"
  (draw-corner corner-canvas)
  (draw-col-headers col-header-canvas)
  (draw-row-headers row-header-canvas)
  (draw-cells-only main-canvas))

(defun redraw (canvas)
  "画面全体を再描画（4キャンバス対応 v0.7.2）"
  ;; グローバルキャンバス参照がある場合は4キャンバス描画
  (if (and *corner-canvas* *col-header-canvas* *row-header-canvas* *main-canvas*)
      (progn
        (draw-corner *corner-canvas*)
        (draw-col-headers *col-header-canvas*)
        (draw-row-headers *row-header-canvas*)
        (draw-cells-only *main-canvas*))
      ;; 後方互換：単一キャンバスモード
      (progn
        (format-wish "~a delete all" (widget-path canvas))
        (draw-headers canvas)
        ;; パス1: 全セルの背景を描画
        (dotimes (y (sheet-rows))
          (dotimes (x (sheet-cols))
            (let ((cell (get-cell (cell-name x y))))
              (draw-cell-background canvas x y
                                    (cell-value cell)
                                    (and (= x (cursor-x)) (= y (cursor-y)))
                                    (cell-in-selection-p x y)))))
        ;; パス2: 全セルのテキストを描画（背景の上に重ねる）
        (dotimes (y (sheet-rows))
          (dotimes (x (sheet-cols))
            (let ((cell (get-cell (cell-name x y))))
              (draw-cell-text canvas x y (cell-value cell))))))))

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
  (redraw canvas))

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
  (setf (cursor-x) (max 0 (1- (cursor-x))))
  (update-text-input text-widget)
  (redraw canvas))

(defun move-right (canvas text-widget)
  (setf (cursor-x) (min (1- (sheet-cols)) (1+ (cursor-x))))
  (update-text-input text-widget)
  (redraw canvas))

(defun move-up (canvas text-widget)
  (setf (cursor-y) (max 0 (1- (cursor-y))))
  (update-text-input text-widget)
  (redraw canvas))

(defun move-down (canvas text-widget)
  (setf (cursor-y) (min (1- (sheet-rows)) (1+ (cursor-y))))
  (update-text-input text-widget)
  (redraw canvas))

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

