;;;; main.lisp
;;;; SSP - メインGUI、start関数、イベントハンドラ

(in-package :ssexp)

;;;; =========================
;;;; メイン：GUIの構築と起動
;;;; =========================

(defun update-window-title ()
  "ウィンドウタイトルを更新"
  (wm-title *tk* (format nil "SSP v0.6 [~Dx~D]~a" 
                         (sheet-cols) (sheet-rows)
                         (if (current-file) 
                             (format nil " - ~a" (file-namestring (current-file)))
                             ""))))

(defun start (&key (rows 26) (cols 14) (input-lines 3))
  "スプレッドシートを起動
   :rows        行数（デフォルト26）
   :cols        列数（デフォルト14、最大26=A-Z）
   :input-lines 入力欄の行数（デフォルト3）"
  ;; パラメータ設定
  (setf (sheet-rows) rows)
  (setf (sheet-cols) (min cols 26))  ; 最大26列（A-Z）
  
  ;; 初期化
  (reset-sheet)
  (setf (cursor-x) 0 (cursor-y) 0)
  (clear-selection)
  (set-clipboard nil 0 0)
  (clear-dependencies)
  (setf (current-file) nil)
  (init-sizes)  ; 列幅・行高さを初期化
  
  (with-ltk ()
    (update-window-title)
    
    ;; 垂直分割用のPanedWindowをTclコマンドで作成
    (format-wish "ttk::panedwindow .paned -orient vertical")
    
    ;; ウィジェット作成
    (let* (;; 入力エリア用フレーム（.paned配下）
           (input-frame (make-instance 'frame))
           ;; 複数行入力用Textウィジェット（固定幅フォント）
           (input-text (make-instance 'text
                                      :master input-frame
                                      :width 80
                                      :height input-lines
                                      :font "TkFixedFont"))
           (input-scroll (make-instance 'scrollbar 
                                        :master input-frame
                                        :orientation :vertical))
           ;; スプレッドシート用フレーム
           (canvas-frame (make-instance 'frame))
           (canvas (make-instance 'canvas
                                  :master canvas-frame
                                  :width (total-width)
                                  :height (total-height)))
           ;; メニューバー
           (mb (make-menubar))
           (file-menu (make-menu mb "File"))
           (edit-menu (make-menu mb "Edit")))
      
      ;; ファイルメニュー項目
      (make-menubutton file-menu "New             Ctrl+N"
                       (lambda ()
                         (new-sheet)
                         (update-window-title)
                         (update-text-input input-text)
                         (redraw canvas)))
      
      (make-menubutton file-menu "Open...         Ctrl+O"
                       (lambda ()
                         (let ((filename (get-open-file 
                                          :filetypes '(("SSP" "*.ssp")
                                                       ("All files" "*")))))
                           (when (and filename (> (length filename) 0))
                             (handler-case
                                 (progn
                                   (load-file filename)
                                   (update-window-title)
                                   (update-text-input input-text)
                                   (redraw canvas))
                               (error (e)
                                 (do-msg (format nil "Load Error: ~a" e))))))))
      
      (make-menubutton file-menu "Save            Ctrl+S"
                       (lambda ()
                         (if (current-file)
                             (progn
                               (save (current-file))
                               (do-msg (format nil "Saved: ~a" 
                                              (file-namestring (current-file)))))
                             ;; ファイルがない場合は名前を付けて保存
                             (let ((filename (get-save-file 
                                              :filetypes '(("SSP" "*.ssp")
                                                           ("All files" "*")))))
                               (when (and filename (> (length filename) 0))
                                 ;; 拡張子がなければ追加
                                 (unless (search ".ssp" filename :test #'char-equal)
                                   (setf filename (concatenate 'string filename ".ssp")))
                                 (save filename)
                                 (update-window-title)
                                 (do-msg (format nil "Saved: ~a" 
                                                (file-namestring filename))))))))
      
      (make-menubutton file-menu "Save As..."
                       (lambda ()
                         (let ((filename (get-save-file 
                                          :filetypes '(("SSP" "*.ssp")
                                                       ("All files" "*")))))
                           (when (and filename (> (length filename) 0))
                             ;; 拡張子がなければ追加
                             (unless (search ".ssp" filename :test #'char-equal)
                               (setf filename (concatenate 'string filename ".ssp")))
                             (save filename)
                             (update-window-title)
                             (do-msg (format nil "Saved: ~a" 
                                            (file-namestring filename)))))))
      
      (add-separator file-menu)
      
      (make-menubutton file-menu "Import CSV..."
                       (lambda ()
                         (let ((filename (get-open-file 
                                          :filetypes '(("CSV files" "*.csv")
                                                       ("TSV files" "*.tsv")
                                                       ("Text files" "*.txt")
                                                       ("All files" "*")))))
                           (when (and filename (> (length filename) 0))
                             (handler-case
                                 (progn
                                   (import-csv filename)
                                   (update-window-title)
                                   (update-text-input input-text)
                                   (redraw canvas)
                                   (do-msg (format nil "Imported: ~a" 
                                                  (file-namestring filename))))
                               (error (e)
                                 (do-msg (format nil "Import Error: ~a" e))))))))
      
      (make-menubutton file-menu "Export CSV..."
                       (lambda ()
                         (let ((filename (get-save-file 
                                          :filetypes '(("CSV files" "*.csv")
                                                       ("All files" "*")))))
                           (when (and filename (> (length filename) 0))
                             ;; 拡張子がなければ追加
                             (unless (search ".csv" filename :test #'char-equal)
                               (setf filename (concatenate 'string filename ".csv")))
                             (handler-case
                                 (progn
                                   (export-csv filename)
                                   (do-msg (format nil "Exported: ~a" 
                                                  (file-namestring filename))))
                               (error (e)
                                 (do-msg (format nil "Export Error: ~a" e))))))))
      
      (add-separator file-menu)
      
      (make-menubutton file-menu "Exit"
                       (lambda ()
                         (setf *exit-mainloop* t)))
      
      ;; 編集メニュー項目
      (make-menubutton edit-menu "Undo            Ctrl+Z"
                       (lambda ()
                         (when (undo)
                           (update-text-input input-text)
                           (redraw canvas))))
      
      (make-menubutton edit-menu "Redo            Ctrl+Y"
                       (lambda ()
                         (when (redo)
                           (update-text-input input-text)
                           (redraw canvas))))
      
      (add-separator edit-menu)
      
      (make-menubutton edit-menu "Cut             Ctrl+X"
                       (lambda ()
                         (copy-to-system-clipboard)
                         (clear-selection-cells)
                         (clear-selection)
                         (redraw canvas)
                         (update-text-input input-text)))
      
      (make-menubutton edit-menu "Copy            Ctrl+C"
                       (lambda ()
                         (copy-to-system-clipboard)))
      
      (make-menubutton edit-menu "Paste           Ctrl+V"
                       (lambda ()
                         (let ((sys-clip (get-system-clipboard)))
                           (if (and sys-clip (> (length sys-clip) 0))
                               (paste-from-system-clipboard)
                               (paste-clipboard)))
                         (clear-selection)
                         (redraw canvas)
                         (update-text-input input-text)))
      
      (add-separator edit-menu)
      
      (make-menubutton edit-menu "Delete          Delete"
                       (lambda ()
                         (clear-selection-cells)
                         (clear-selection)
                         (redraw canvas)
                         (update-text-input input-text)))
      
      (add-separator edit-menu)
      
      (make-menubutton edit-menu "Insert Row"
                       (lambda ()
                         (insert-row (cursor-y))
                         (configure canvas :height (total-height))
                         (redraw canvas)))
      
      (make-menubutton edit-menu "Insert Column"
                       (lambda ()
                         (insert-col (cursor-x))
                         (configure canvas :width (total-width))
                         (redraw canvas)))
      
      (make-menubutton edit-menu "Delete Row"
                       (lambda ()
                         (delete-row (cursor-y))
                         (configure canvas :height (total-height))
                         (redraw canvas)
                         (update-text-input input-text)))
      
      (make-menubutton edit-menu "Delete Column"
                       (lambda ()
                         (delete-col (cursor-x))
                         (configure canvas :width (total-width))
                         (redraw canvas)
                         (update-text-input input-text)))
      
      ;; セパレーター
      (add-separator edit-menu)
      
      ;; Format Expression
      (make-menubutton edit-menu "Format Expression   Ctrl+Shift+F"
                       (lambda ()
                         (format-sexp input-text)))
      
      ;; キーボードショートカット (Ctrl+N, Ctrl+O, Ctrl+S)
      (bind *tk* "<Control-n>"
            (lambda (evt)
              (declare (ignore evt))
              (new-sheet)
              (update-window-title)
              (update-text-input input-text)
              (redraw canvas)))
      
      (bind *tk* "<Control-o>"
            (lambda (evt)
              (declare (ignore evt))
              (let ((filename (get-open-file 
                               :filetypes '(("SSP" "*.ssp")
                                            ("All files" "*")))))
                (when (and filename (> (length filename) 0))
                  (handler-case
                      (progn
                        (load-file filename)
                        (update-window-title)
                        (update-text-input input-text)
                        (redraw canvas))
                    (error (e)
                      (do-msg (format nil "読み込みエラー: ~a" e))))))))
      
      (bind *tk* "<Control-s>"
            (lambda (evt)
              (declare (ignore evt))
              (if (current-file)
                  (progn
                    (save (current-file))
                    (do-msg (format nil "保存しました: ~a" 
                                   (file-namestring (current-file)))))
                  ;; ファイルがない場合は名前を付けて保存
                  (let ((filename (get-save-file 
                                   :filetypes '(("SSP" "*.ssp")
                                                ("All files" "*")))))
                    (when (and filename (> (length filename) 0))
                      (unless (search ".ssp" filename :test #'char-equal)
                        (setf filename (concatenate 'string filename ".ssp")))
                      (save filename)
                      (update-window-title)
                      (do-msg (format nil "保存しました: ~a" 
                                     (file-namestring filename))))))))
      
      ;; Ctrl+Z → Undo
      (bind *tk* "<Control-z>"
            (lambda (evt)
              (declare (ignore evt))
              (when (undo)
                (update-text-input input-text)
                (redraw canvas))))
      
      ;; Ctrl+Y → Redo
      (bind *tk* "<Control-y>"
            (lambda (evt)
              (declare (ignore evt))
              (when (redo)
                (update-text-input input-text)
                (redraw canvas))))
      
      ;; Ctrl+X → 切り取り
      (bind *tk* "<Control-x>"
            (lambda (evt)
              (declare (ignore evt))
              (copy-to-system-clipboard)
              (clear-selection-cells)
              (clear-selection)
              (redraw canvas)
              (update-text-input input-text)))
      
      ;; スクロールバーとテキストを連携
      (configure input-scroll :command (format nil "~a yview" (widget-path input-text)))
      (configure input-text :yscrollcommand (format nil "~a set" (widget-path input-scroll)))
      ;; タブ幅を4文字分に設定
      (format-wish "~a configure -tabs [list [expr {[font measure TkFixedFont 0] * 4}]]" 
                   (widget-path input-text))
      
      ;; Rainbow括弧のタグをセットアップ
      (setup-rainbow-tags input-text)
      ;; キー入力時に括弧を色分け
      (bind input-text "<KeyRelease>"
            (lambda (evt)
              (declare (ignore evt))
              (colorize-parentheses input-text)))
      
      ;; レイアウト - 入力フレーム内
      (pack input-scroll :side :right :fill :y)
      (pack input-text :side :left :fill :both :expand t)
      ;; レイアウト - キャンバスフレーム内
      (pack canvas :fill :both :expand t)
      
      ;; PanedWindowにペインを追加
      (format-wish ".paned add ~a -weight 0" (widget-path input-frame))
      (format-wish ".paned add ~a -weight 1" (widget-path canvas-frame))
      ;; PanedWindowをパック
      (format-wish "pack .paned -fill both -expand true -padx 2 -pady 2")

      ;; 初期描画
      (update-text-input input-text)
      (redraw canvas)

      ;;; --- イベントバインド ---

      ;; Enter → 確定して下に移動
      (bind input-text "<Return>"
            (lambda (evt)
              (declare (ignore evt))
              (commit-and-move input-text canvas :down)
              (focus canvas)))
      
      ;; Ctrl+Enter → 確定してそのまま
      (bind input-text "<Control-Return>"
            (lambda (evt)
              (declare (ignore evt))
              (commit-and-move input-text canvas :stay)
              (focus canvas)))
      
      ;; Alt+Enter → 確定して右に移動
      (bind input-text "<Alt-Return>"
            (lambda (evt)
              (declare (ignore evt))
              (commit-and-move input-text canvas :right)
              (focus canvas)))
      
      ;; Shift+Alt+Enter → 確定して左に移動
      (bind input-text "<Shift-Alt-Return>"
            (lambda (evt)
              (declare (ignore evt))
              (commit-and-move input-text canvas :left)
              (focus canvas)))
      
      ;; Escape → 編集キャンセル（元に戻す）
      (bind input-text "<Escape>"
            (lambda (evt)
              (declare (ignore evt))
              (update-text-input input-text)
              (focus canvas)))
      
      ;; Ctrl+Shift+F → S式を整形
      (bind input-text "<Control-Shift-f>"
            (lambda (evt)
              (declare (ignore evt))
              (format-sexp input-text)))
      
      ;; Tclレベルでバインディングを調整（breakでデフォルト動作を抑制）
      (let ((path (widget-path input-text)))
        (format-wish "bind ~a <Return> \"[bind ~a <Return>]; break\"" path path)
        (format-wish "bind ~a <Control-Return> \"[bind ~a <Control-Return>]; break\"" path path)
        (format-wish "bind ~a <Alt-Return> \"[bind ~a <Alt-Return>]; break\"" path path)
        (format-wish "bind ~a <Shift-Alt-Return> \"[bind ~a <Shift-Alt-Return>]; break\"" path path)
        (format-wish "bind ~a <Escape> \"[bind ~a <Escape>]; break\"" path path)
        ;; Shift+Enter で改行
        (format-wish "bind ~a <Shift-Return> {~a insert insert \\n; break}" path path))

      ;; セルクリック → 選択開始 または リサイズ開始
      (bind canvas "<ButtonPress-1>"
            (lambda (evt)
              (let ((mx (and evt (slot-value evt 'ltk::x)))
                    (my (and evt (slot-value evt 'ltk::y))))
                (when (and mx my (numberp mx) (numberp my))
                  ;; ヘッダー領域でのリサイズチェック
                  (let ((col-border (and (< my +header-h+) 
                                         (near-col-border-p mx 4)))
                        (row-border (and (< mx +header-w+) 
                                         (near-row-border-p my 4))))
                    (cond
                      ;; 列幅リサイズ開始
                      (col-border
                       (setf (resize-mode) :col
                             (resize-index) col-border
                             (resize-start) mx))
                      ;; 行高さリサイズ開始
                      (row-border
                       (setf (resize-mode) :row
                             (resize-index) row-border
                             (resize-start) my))
                      ;; 通常のセル選択
                      ((and (> mx +header-w+) (> my +header-h+))
                       (let ((x (clamp (find-col-at mx) 0 (1- (sheet-cols))))
                             (y (clamp (find-row-at my) 0 (1- (sheet-rows)))))
                         (setf (cursor-x) x
                               (cursor-y) y
                               (selection-start-x) x
                               (selection-start-y) y
                               (selection-end-x) x
                               (selection-end-y) y
                               (selecting-p) t)
                         (update-text-input input-text)
                         (redraw canvas)))))))
              (focus canvas)))

      ;; ドラッグ → 選択範囲拡張 または リサイズ
      (bind canvas "<B1-Motion>"
            (lambda (evt)
              (let ((mx (and evt (slot-value evt 'ltk::x)))
                    (my (and evt (slot-value evt 'ltk::y))))
                (when (and mx my (numberp mx) (numberp my))
                  (cond
                    ;; 列幅リサイズ中
                    ((eq (resize-mode) :col)
                     (let* ((old-w (col-width (resize-index)))
                            (delta (- mx (resize-start)))
                            (new-w (max +min-cell-w+ (+ old-w delta))))
                       (set-col-width (resize-index) new-w)
                       (setf (resize-start) mx)
                       ;; キャンバスサイズ更新
                       (configure canvas :width (total-width))
                       (redraw canvas)))
                    ;; 行高さリサイズ中
                    ((eq (resize-mode) :row)
                     (let* ((old-h (row-height (resize-index)))
                            (delta (- my (resize-start)))
                            (new-h (max +min-cell-h+ (+ old-h delta))))
                       (set-row-height (resize-index) new-h)
                       (setf (resize-start) my)
                       ;; キャンバスサイズ更新
                       (configure canvas :height (total-height))
                       (redraw canvas)))
                    ;; 通常の選択
                    ((selecting-p)
                     (let ((x (find-col-at mx))
                           (y (find-row-at my)))
                       (when (>= x 0)
                         (setf (selection-end-x) (clamp x 0 (1- (sheet-cols)))))
                       (when (>= y 0)
                         (setf (selection-end-y) (clamp y 0 (1- (sheet-rows))))))
                     (redraw canvas)))))))

      ;; ドラッグ終了
      (bind canvas "<ButtonRelease-1>"
            (lambda (evt)
              (declare (ignore evt))
              (setf (selecting-p) nil
                    (resize-mode) nil
                    (resize-index) nil)))

      ;; 右クリック用の変数
      (let ((context-col nil)   ; 右クリックされた列
            (context-row nil))  ; 右クリックされた行
        
        ;; 列ヘッダー用コンテキストメニュー作成
        (format-wish "menu .colmenu -tearoff 0")
        (format-wish ".colmenu add command -label {Insert Column} -command {}")
        (format-wish ".colmenu add command -label {Delete Column} -command {}")
        (format-wish ".colmenu add separator")
        (format-wish ".colmenu add command -label {Column Width...} -command {}")
        
        ;; 行ヘッダー用コンテキストメニュー作成
        (format-wish "menu .rowmenu -tearoff 0")
        (format-wish ".rowmenu add command -label {Insert Row} -command {}")
        (format-wish ".rowmenu add command -label {Delete Row} -command {}")
        (format-wish ".rowmenu add separator")
        (format-wish ".rowmenu add command -label {Row Height...} -command {}")
        
        ;; 右クリック → コンテキストメニュー表示
        (bind canvas "<ButtonPress-3>"
              (lambda (evt)
                (let ((mx (and evt (slot-value evt 'ltk::x)))
                      (my (and evt (slot-value evt 'ltk::y))))
                  (when (and mx my (numberp mx) (numberp my))
                    (cond
                      ;; 列ヘッダー上で右クリック
                      ((and (< my +header-h+) (>= mx +header-w+))
                       (setf context-col (find-col-at mx))
                       (when (and context-col (>= context-col 0))
                         ;; メニューコマンドを更新
                         (format-wish ".colmenu entryconfigure 0 -command {event generate . <<ColInsert>>}")
                         (format-wish ".colmenu entryconfigure 1 -command {event generate . <<ColDelete>>}")
                         (format-wish ".colmenu entryconfigure 3 -command {event generate . <<ColWidth>>}")
                         ;; メニュー表示（画面座標を取得）
                         (format-wish "tk_popup .colmenu [expr [winfo rootx ~a] + ~a] [expr [winfo rooty ~a] + ~a]"
                                      (widget-path canvas) mx (widget-path canvas) my)))
                      
                      ;; 行ヘッダー上で右クリック
                      ((and (< mx +header-w+) (>= my +header-h+))
                       (setf context-row (find-row-at my))
                       (when (and context-row (>= context-row 0))
                         ;; メニューコマンドを更新
                         (format-wish ".rowmenu entryconfigure 0 -command {event generate . <<RowInsert>>}")
                         (format-wish ".rowmenu entryconfigure 1 -command {event generate . <<RowDelete>>}")
                         (format-wish ".rowmenu entryconfigure 3 -command {event generate . <<RowHeight>>}")
                         ;; メニュー表示
                         (format-wish "tk_popup .rowmenu [expr [winfo rootx ~a] + ~a] [expr [winfo rooty ~a] + ~a]"
                                      (widget-path canvas) mx (widget-path canvas) my))))))))
        
        ;; 列挿入イベント
        (bind *tk* "<<ColInsert>>"
              (lambda (evt)
                (declare (ignore evt))
                (when context-col
                  (insert-col context-col)
                  (configure canvas :width (total-width))
                  (redraw canvas))))
        
        ;; 列削除イベント
        (bind *tk* "<<ColDelete>>"
              (lambda (evt)
                (declare (ignore evt))
                (when context-col
                  (delete-col context-col)
                  (configure canvas :width (total-width))
                  (redraw canvas)
                  (update-text-input input-text))))
        
        ;; 列幅設定イベント
        (bind *tk* "<<ColWidth>>"
              (lambda (evt)
                (declare (ignore evt))
                (when context-col
                  (let* ((current-w (col-width context-col))
                         (col-name (string (code-char (+ (char-code #\A) context-col))))
                         (target-col context-col))
                    (show-size-dialog "Column Width" 
                                      (format nil "Width for column ~a:" col-name)
                                      current-w
                                      (lambda (w)
                                        (set-col-width target-col w)
                                        (configure canvas :width (total-width))
                                        (redraw canvas)))))))
        
        ;; 行挿入イベント
        (bind *tk* "<<RowInsert>>"
              (lambda (evt)
                (declare (ignore evt))
                (when context-row
                  (insert-row context-row)
                  (configure canvas :height (total-height))
                  (redraw canvas))))
        
        ;; 行削除イベント
        (bind *tk* "<<RowDelete>>"
              (lambda (evt)
                (declare (ignore evt))
                (when context-row
                  (delete-row context-row)
                  (configure canvas :height (total-height))
                  (redraw canvas)
                  (update-text-input input-text))))
        
        ;; 行高さ設定イベント
        (bind *tk* "<<RowHeight>>"
              (lambda (evt)
                (declare (ignore evt))
                (when context-row
                  (let* ((current-h (row-height context-row))
                         (row-num (1+ context-row))
                         (target-row context-row))
                    (show-size-dialog "Row Height"
                                      (format nil "Height for row ~a:" row-num)
                                      current-h
                                      (lambda (h)
                                        (set-row-height target-row h)
                                        (configure canvas :height (total-height))
                                        (redraw canvas))))))))

      ;; Ctrl+C → システムクリップボードにコピー
      (bind canvas "<Control-c>"
            (lambda (evt)
              (declare (ignore evt))
              (copy-to-system-clipboard)))

      ;; Ctrl+V → システムクリップボードからペースト
      (bind canvas "<Control-v>"
            (lambda (evt)
              (declare (ignore evt))
              (let ((sys-clip (get-system-clipboard)))
                (if (and sys-clip (> (length sys-clip) 0))
                    ;; システムクリップボードにデータあり
                    (paste-from-system-clipboard)
                    ;; なければ内部クリップボード
                    (paste-clipboard)))
              (clear-selection)
              (redraw canvas)
              (update-text-input input-text)))

      ;; Delete → 選択範囲をクリア
      (bind canvas "<Delete>"
            (lambda (evt)
              (declare (ignore evt))
              (clear-selection-cells)
              (clear-selection)
              (redraw canvas)
              (update-text-input input-text)))

      ;; BackSpace → 選択範囲をクリア
      (bind canvas "<BackSpace>"
            (lambda (evt)
              (declare (ignore evt))
              (clear-selection-cells)
              (clear-selection)
              (redraw canvas)
              (update-text-input input-text)))

      ;; 矢印キー（選択解除してから移動）
      (bind canvas "<Left>"
            (lambda (evt) 
              (declare (ignore evt)) 
              (clear-selection)
              (move-left canvas input-text)))
      (bind canvas "<Right>"
            (lambda (evt) 
              (declare (ignore evt)) 
              (clear-selection)
              (move-right canvas input-text)))
      (bind canvas "<Up>"
            (lambda (evt) 
              (declare (ignore evt)) 
              (clear-selection)
              (move-up canvas input-text)))
      (bind canvas "<Down>"
            (lambda (evt) 
              (declare (ignore evt)) 
              (clear-selection)
              (move-down canvas input-text)))

      ;; Shift+矢印キー（範囲選択）
      (bind canvas "<Shift-Left>"
            (lambda (evt)
              (declare (ignore evt))
              ;; 選択開始していなければ現在位置から開始
              (unless (has-selection-p)
                (setf (selection-start-x) (cursor-x)
                      (selection-start-y) (cursor-y)
                      (selection-end-x) (cursor-x)
                      (selection-end-y) (cursor-y)))
              ;; カーソルを移動し、選択終端も移動
              (when (> (cursor-x) 0)
                (decf (cursor-x))
                (setf (selection-end-x) (cursor-x)
                      (selection-end-y) (cursor-y)))
              (redraw canvas)
              (update-text-input input-text)))
      (bind canvas "<Shift-Right>"
            (lambda (evt)
              (declare (ignore evt))
              (unless (has-selection-p)
                (setf (selection-start-x) (cursor-x)
                      (selection-start-y) (cursor-y)
                      (selection-end-x) (cursor-x)
                      (selection-end-y) (cursor-y)))
              (when (< (cursor-x) (1- (sheet-cols)))
                (incf (cursor-x))
                (setf (selection-end-x) (cursor-x)
                      (selection-end-y) (cursor-y)))
              (redraw canvas)
              (update-text-input input-text)))
      (bind canvas "<Shift-Up>"
            (lambda (evt)
              (declare (ignore evt))
              (unless (has-selection-p)
                (setf (selection-start-x) (cursor-x)
                      (selection-start-y) (cursor-y)
                      (selection-end-x) (cursor-x)
                      (selection-end-y) (cursor-y)))
              (when (> (cursor-y) 0)
                (decf (cursor-y))
                (setf (selection-end-x) (cursor-x)
                      (selection-end-y) (cursor-y)))
              (redraw canvas)
              (update-text-input input-text)))
      (bind canvas "<Shift-Down>"
            (lambda (evt)
              (declare (ignore evt))
              (unless (has-selection-p)
                (setf (selection-start-x) (cursor-x)
                      (selection-start-y) (cursor-y)
                      (selection-end-x) (cursor-x)
                      (selection-end-y) (cursor-y)))
              (when (< (cursor-y) (1- (sheet-rows)))
                (incf (cursor-y))
                (setf (selection-end-x) (cursor-x)
                      (selection-end-y) (cursor-y)))
              (redraw canvas)
              (update-text-input input-text)))

      ;; Canvas上でEnter → Textにフォーカス
      (bind canvas "<Return>"
            (lambda (evt)
              (declare (ignore evt))
              (focus input-text)))
      
      ;; F2 → 編集モード（既存内容を編集）
      (bind canvas "<F2>"
            (lambda (evt)
              (declare (ignore evt))
              (focus input-text)
              ;; カーソルを末尾に移動
              (format-wish "~a mark set insert end" (widget-path input-text))))
      
      ;; Canvas上でキー入力 → 入力欄をクリアしてフォーカス移動（Tclレベルで処理）
      (let ((canvas-path (widget-path canvas))
            (text-path (widget-path input-text)))
        ;; 印刷可能文字のみを処理するTclバインディング
        (format-wish "bind ~a <Key> {
          set k %K
          set c %A
          # 特殊キーを除外
          if {$c ne {} && [string length $c] == 1 && [string is print $c]} {
            # 制御キーやファンクションキーでない場合
            if {![string match *Control* $k] && 
                ![string match *Shift* $k] && 
                ![string match *Alt* $k] && 
                ![string match *Meta* $k] &&
                ![string match *Super* $k] &&
                ![string match F?* $k] &&
                $k ne {Up} && $k ne {Down} && $k ne {Left} && $k ne {Right} &&
                $k ne {Return} && $k ne {Escape} && $k ne {Tab} &&
                $k ne {Delete} && $k ne {BackSpace} &&
                $k ne {Home} && $k ne {End} && $k ne {Prior} && $k ne {Next} &&
                $k ne {Insert} && $k ne {Caps_Lock} && $k ne {Num_Lock}} {
              # テキストをクリアして文字を挿入
              ~a delete 1.0 end
              ~a insert end $c
              focus ~a
            }
          }
        }" canvas-path text-path text-path text-path))

      (focus canvas))))

;;; ロード時メッセージ
(format t "~%╔══════════════════════════════════════════════════════════╗~%")
(format t "║  SSP v0.6 - Symbolic Spreadsheet for Lisp Learning       ║~%")
(format t "╠══════════════════════════════════════════════════════════╣~%")
(format t "║  SSP is not a notebook.                                  ║~%")
(format t "║  It is a Lisp-native evaluation space where cells are    ║~%")
(format t "║  expressions, not scripts.                               ║~%")
(format t "╚══════════════════════════════════════════════════════════╝~%")
(format t "~%Start: (ssexp:start) or (ssp:start)~%")
(format t "~%Basic Operations:~%")
(format t "  Arrow keys        : Move cursor~%")
(format t "  Shift+Arrow       : Select range~%")
(format t "  Type              : Direct input~%")
(format t "  F2                : Edit mode~%")
(format t "  Ctrl+X/C/V        : Cut/Copy/Paste~%")
(format t "  Ctrl+Z/Y          : Undo/Redo~%")
(format t "  Enter             : Confirm & move down~%")
(format t "  Ctrl+Shift+F      : Format S-expression~%")
(format t "~%Cell Input Examples:~%")
(format t "  42                : Number~%")
(format t "  =(+ A1 B1)        : Formula~%")
(format t "  =(range A1 A5)    : Cell range as list~%")
(format t "  =(sum (range A1 A5))~%")
(format t "  =(mapcar #'1+ (range A1 A5))~%")
(format t "~%")
