# SSP - Symbolic Spreadsheet for Lisp Learning

**SSPはノートブックではありません。**  
**セルがスクリプトではなく「式」である、Lispネイティブな評価空間です。**

![Version](https://img.shields.io/badge/version-0.8.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Lisp](https://img.shields.io/badge/Common%20Lisp-SBCL-red.svg)
![GUI](https://img.shields.io/badge/GUI-LTK%2FTk-orange.svg)

[English README](README.md)

---

## v0.7.2 の新機能

### シートサイズ制限

- **最大行数**: 1000行（UIパフォーマンス制限）
- **最大列数**: 26列（A-Z、セル名形式制限）
- **デフォルトグリッド**: 100行×26列
- **表示領域**: 30行×14列（スクロールバー付き）
- **起動時検証**: `(start :rows 2000)` → 自動的に1000に制限
- **インポート時検証**: 制限を超えるCSV/SSPファイルは警告付きで切り詰め

### スクロールバー

- 大きなシートをナビゲートするための縦横スクロールバー
- カーソルが表示範囲外に移動すると自動スクロール
- スクロール時に行/列ヘッダーを固定表示
- ファイル読み込み/インポート時にスクロール領域を自動更新

### スクロール操作

- **マウスホイール**: 縦スクロール
- **Shift + マウスホイール**: 横スクロール
- **Page Up/Down**: ページ単位でスクロール
- **Ctrl+Home**: 左上端へ移動
- **Ctrl+End**: 右下端へ移動

### サイズ定数

```lisp
+max-rows+      ; 1000 - 最大行数
+max-cols+      ; 26   - 最大列数 (A-Z)
+default-rows+  ; 100  - デフォルト行数
+default-cols+  ; 26   - デフォルト列数 (A-Z)
+visible-rows+  ; 30   - ウィンドウ内の表示行数
+visible-cols+  ; 14   - ウィンドウ内の表示列数
```

### CSVインポートの強化

```lisp
(import-csv "data.csv"
  :expand-grid t      ; データに合わせて自動拡張（デフォルト）
  :max-rows 500       ; カスタム行制限
  :max-cols 20)       ; カスタム列制限
```

---

## v0.7.1 の新機能

### 循環参照検出の改善

- **パス表示**: 循環参照を検出すると、完全な循環パスを表示
  - 例: `#循環: A3 (A1→A2→A3→A1)`
- **事前チェック**: `(detect-cycles)` 関数で全セルの循環をスキャン
- **深さ制限**: 最大評価深さ（100）で無限ループを防止

### パフォーマンス最適化

- **評価キャッシュ**: 結果をキャッシュして不要な再計算を回避
  - 「dirty」（変更された）セルとその依存先のみ再計算
- **キャッシュ統計**: `(show-cache-stats)` でキャッシュ効率を監視
- **トポロジカルソート**: 循環警告付きの改善された依存関係順序

### 新コマンド

```lisp
(detect-cycles)       ; 全セルの循環参照をスキャン
(show-cache-stats)    ; キャッシュヒット/ミス統計を表示
(show-cycle-path)     ; 最後に検出された循環パスを表示
(clear-cache)         ; 評価キャッシュを手動クリア
```

---

## v0.7 の新機能

### 日本語・Unicode対応

- **CJKフォント自動選択**: 日本語・中国語・韓国語文字に適切なフォントを自動選択
  - macOS: Menlo
  - Windows: MS Gothic
  - Linux: Noto Sans Mono CJK JP（フォールバック対応）
- **文字幅計算**: 全角（2）・半角（1）文字の正確な幅計算
- **テキスト切り詰め**: 文字幅を考慮した「…」サフィックス付きスマート切り詰め
- **UTF-8ファイルI/O**: `.ssp`ファイルの完全なUTF-8サポート
- **Excel互換CSV**: 正しいExcelインポートのためのBOM（バイト順マーク）プレフィックス

### 文字幅の分類

| 種類 | 幅 | 例 |
|------|----|----|
| ASCII | 1 | A, 1, + |
| 半角カナ | 1 | ｱ, ｲ, ｳ |
| ひらがな | 2 | あ, い, う |
| カタカナ | 2 | ア, イ, ウ |
| 漢字 | 2 | 日, 本, 語 |
| 全角記号 | 2 | 。, 、, 「 |

---

## 思想

SSPでは、各セルは単一の**S式**を保持します。スクリプトでもコードブロックでもありません。

```
セル A1: 10
セル A2: =(+ A1 5)        → 15
セル A3: =(range A1 A2)   → (10 15)
セル A4: =(apply #'+ A3)  → 25
```

`=(+ A1 B1)` と入力するとき、あなたは「コードを実行」しているのではなく、**シンボリックな関係性**を定義しているのです。スプレッドシートのグリッドは、セル参照を通じて依存関係が自然に流れるライブ評価環境になります。

**セルは任意のLisp値を保持できます：**
- 数値: `42`, `3.14159`
- リスト: `(1 2 3 4 5)`
- シンボル: `HELLO`, `T`, `NIL`
- 文字列: `"Hello, World!"`, `"日本語"`
- ネスト構造: `((a 1) (b 2))`

---

## スクリーンショット

```
╔═════════════════════════════════════════════════════════════════════╗
║ [File] [Edit]                            SSP v0.7 [14×26]           ║
╠═════════════════════════════════════════════════════════════════════╣
║ =(mapcar #'1+ (range A1 A5))                                        ║
╠════╤════════════╤════════════════════════╤══════════╤═══════════════╣
║    │     A      │           B            │    C     │      D        ║
╠════╪════════════╪════════════════════════╪══════════╪═══════════════╣
║  1 │          1 │ (2 3 4 5 6)            │          │               ║
║  2 │          2 │                        │          │               ║
║  3 │          3 │ 日本語テスト           │          │               ║
║  4 │          4 │ "文字列"               │          │               ║
║  5 │          5 │                        │          │               ║
╚════╧════════════╧════════════════════════╧══════════╧═══════════════╝
       ↑ 数値           ↑ 日本語テキスト対応 (v0.7)
```

---

## セルの値

Excel（数値・文字列・エラーのみ）とは異なり、SSPのセルは**任意のLisp値**を保持できます。

### 対応する値の種類

| 種類 | 入力例 | 表示 | 備考 |
|------|--------|------|------|
| 整数 | `42` | `42` | 右揃え |
| 浮動小数点 | `3.14159` | `3.142` | 右揃え、4桁精度 |
| 分数 | `1/3` | `1/3` | Lisp固有の正確な分数 |
| 文字列 | `"Hello"` | `Hello` | 左揃え |
| 文字列(日本語) | `"日本語"` | `日本語` | 全角文字対応 (v0.7) |
| シンボル | `HELLO` | `HELLO` | 大文字表示 |
| キーワード | `:keyword` | `:KEYWORD` | コロン付き |
| リスト | `(1 2 3)` | `(1 2 3)` | そのまま表示 |
| ネストリスト | `((a 1) (b 2))` | `((A 1) (B 2))` | 連想リスト、木構造等 |
| NIL | `nil` | *(空白)* | 空セルとして表示 |
| T | `t` | `T` | 真値 |

### 入力方法

```
直接入力:     42           → 数値
             "text"       → 文字列  
             hello        → シンボル HELLO
             "日本語"     → 日本語文字列 (v0.7)
             
数式入力:     =(+ 1 2)     → 3
             =(list 1 2 3) → (1 2 3)
             =(range A1 A5) → (val1 val2 val3 val4 val5)
```

### 数式の戻り値の例

```lisp
=(+ 1 2 3)                          → 6           ; 数値
=(/ 1 3)                            → 1/3         ; 分数（正確）
=(list 'a 'b 'c)                    → (A B C)     ; シンボルのリスト
=(cons 1 '(2 3))                    → (1 2 3)     ; リスト
=(if (> A1 0) '正 '負)              → 正          ; シンボル
=(format nil "~a円" A1)             → "100円"     ; 文字列
=(range A1 A5)                      → (1 2 3 4 5) ; 値のリスト
=(mapcar #'1+ (range A1 A3))        → (2 3 4)     ; 変換後リスト
='((:name "太郎") (:age 25))        → 連想リスト
```

---

## 機能

### Lispネイティブ数式システム
- **S式による数式** - 完全なLisp構文をサポート
- **150以上のホワイトリスト関数** （算術、リスト、文字列、論理）
- **ラムダ式**: `=(mapcar (lambda (x) (* x x)) (range A1 A5))`
- **高階関数**: `apply`, `funcall`, `reduce`, `mapcar`
- **条件分岐**: `if`, `cond`, `when`, `unless`, `case`

### セル参照
| 種類 | 構文 | 説明 |
|------|------|------|
| 絶対参照 | `A1`, `B2` | 固定セル参照 |
| 相対参照 | `(rel -1 0)` | 現在セルからのオフセット |
| 範囲 | `(range A1 A5)` | 値のリストを返す |
| 相対範囲 | `(rel-range -4 0 -1 0)` | オフセットによる範囲 |
| 位置 | `this-row`, `this-col` | 現在位置 |

### スマート参照 (v0.5+)
- 行・列の挿入・削除時に参照を自動更新
- 削除されたセルへの参照は `#REF!` エラー
- データ損失防止のための確認ダイアログ

### Unicode対応 (v0.7)
- 日本語・中国語・韓国語文字サポート
- 全角・半角文字の正確な幅計算
- プラットフォームごとのCJKフォント自動選択
- Excel CSV互換のUTF-8 BOM

### ユーザーインターフェース
- 列幅・行高さのリサイズ（境界をドラッグ）
- ヘッダーのコンテキストメニュー（右クリック）
- ダイレクト入力モード（入力開始で編集）
- シンタックスハイライト付き複数行入力
- S式オートフォーマッター (Ctrl+Shift+F)

### データ管理
- Undo/Redo (Ctrl+Z / Ctrl+Y) 最大100操作
- ネイティブ `.ssp` ファイル形式（UTF-8）
- CSVインポート/エクスポート（BOMオプション）
- システムクリップボード（TSV形式）
- 範囲選択（ドラッグまたはShift+矢印）

---

## 必要条件

| コンポーネント | バージョン |
|----------------|------------|
| SBCL | 2.0以上推奨 |
| Quicklisp | 最新版 |
| Tcl/Tk | 8.5以上 |

### 推奨フォント（CJKサポート用）
- **Linux**: Noto Sans Mono CJK JP, Source Han Code JP, IPAGothic
- **macOS**: 内蔵（Menloとフォールバック）
- **Windows**: MS Gothic（内蔵）

---

## インストール

### 1. SBCLとTkのインストール

```bash
# Ubuntu/Debian
sudo apt install sbcl tk fonts-noto-cjk

# macOS
brew install sbcl tcl-tk

# Windows
# SBCLは http://www.sbcl.org/ からダウンロード
# Tcl/Tkは https://www.activestate.com/products/tcl/ からインストール
```

### 2. Quicklispのインストール

```bash
curl -O https://beta.quicklisp.org/quicklisp.lisp
sbcl --load quicklisp.lisp
```

```lisp
(quicklisp-quickstart:install)
(ql:add-to-init-file)
(quit)
```

---

## 使い方

### ASDFを使用

```lisp
(push #P"/path/to/ssp/" asdf:*central-registry*)
(asdf:load-system :ssp)
(ssp:start)
```

### 簡易ローダーを使用（ASDF不要）

```lisp
(load "/path/to/ssp/load.lisp")
(ssp:start)
```

### 起動オプション

```lisp
(ssp:start)                      ; デフォルト: 26行 × 14列
(ssp:start :rows 50 :cols 10)    ; カスタムグリッドサイズ
(ssp:start :input-lines 5)       ; 数式入力エリアを大きく
```

---

## プロジェクト構成

```
ssp/
├── ssp.asd          ; ASDFシステム定義
├── load.lisp        ; 簡易ローダー（ASDF不要）
├── package.lisp     ; パッケージ、定数、構造体、アクセサ、文字幅計算 (v0.7)
├── formula.lisp     ; 許可関数、評価エンジン
├── core.lisp        ; セル操作、依存関係、Undo/Redo、ファイルI/O
├── ui.lisp          ; 描画、入力、シンタックスハイライト（Unicode対応 v0.7）
├── main.lisp        ; GUI構築、イベントハンドラ
├── README.md        ; 英語ドキュメント
└── README-JP.md     ; 日本語ドキュメント
```

---

## キーボードショートカット

### ナビゲーション

| キー | 動作 |
|------|------|
| 矢印キー | カーソル移動 |
| Shift+矢印 | 選択範囲拡張 |
| Home / End | 最初 / 最後の列 |
| Ctrl+Home | A1へ移動 |
| Page Up/Down | ページ単位スクロール |

### 編集

| キー | 動作 |
|------|------|
| 任意の文字 | 入力開始（セルを置換） |
| F2 | 編集モード（内容を保持） |
| Delete / BackSpace | セルをクリア |
| Escape | 編集キャンセル |
| Ctrl+Shift+F | S式フォーマット |

### 確定

| キー | 動作 |
|-----|------|
| Enter | 確定 → 下に移動 |
| Ctrl+Enter | 確定 → その場に留まる |
| Alt+Enter | 確定 → 右に移動 |
| Shift+Enter | 入力欄で改行 |
| Tab | 確定 → 右に移動 |

### クリップボード

| キー | 動作 |
|------|------|
| Ctrl+C | コピー |
| Ctrl+X | 切り取り |
| Ctrl+V | 貼り付け |
| Ctrl+Z | 元に戻す |
| Ctrl+Y | やり直し |

### ファイル

| キー | 動作 |
|------|------|
| Ctrl+N | 新規作成 |
| Ctrl+O | ファイルを開く |
| Ctrl+S | 保存 |
| Ctrl+Shift+S | 名前を付けて保存 |

---

## 数式の例

### 基本的な算術
```lisp
=(+ 1 2 3)              → 6
=(* A1 A2)              → A1とA2の積
=(/ (+ A1 A2) 2)        → 2セルの平均
```

### 範囲の操作
```lisp
=(range A1 A10)         → (1 2 3 4 5 6 7 8 9 10)
=(apply #'+ (range A1 A10))  → 合計
=(apply #'max (range A1 A10)) → 最大値
=(length (range A1 A10))     → 個数
```

### リスト操作
```lisp
=(mapcar #'1+ (range A1 A5))     → 各要素を+1
=(remove-if #'oddp (range A1 A10)) → 偶数のみ抽出
=(reverse (range A1 A5))         → 逆順
=(sort (range A1 A5) #'<)        → 昇順ソート
```

### ラムダ式
```lisp
=(mapcar (lambda (x) (* x x)) (range A1 A5))  → 各要素を2乗
=(reduce (lambda (a b) (+ a b)) (range A1 A5)) → 合計
```

### 条件分岐
```lisp
=(if (> A1 0) "正" "非正")
=(cond ((< A1 0) "負")
       ((= A1 0) "ゼロ")
       (t "正"))
```

### 相対参照
```lisp
=(rel -1 0)             → 上のセル
=(rel 0 -1)             → 左のセル
=(+ (rel -1 0) (rel -2 0))  → 上2セルの合計
=(apply #'+ (rel-range -4 0 -1 0))  → 上4セルの合計
```

---

## 許可関数一覧（150以上）

### 算術
`+`, `-`, `*`, `/`, `mod`, `rem`, `1+`, `1-`, `floor`, `ceiling`, `round`, `truncate`, `abs`, `max`, `min`, `sqrt`, `expt`, `log`, `exp`, `sin`, `cos`, `tan`, `gcd`, `lcm`

### 比較
`=`, `/=`, `<`, `>`, `<=`, `>=`, `equal`, `equalp`, `eq`, `eql`

### リスト操作
`car`, `cdr`, `cons`, `list`, `first`...`tenth`, `last`, `nth`, `length`, `append`, `reverse`, `member`, `assoc`, `mapcar`, `mapc`, `mapcan`, `reduce`, `remove`, `remove-if`, `remove-if-not`, `find`, `find-if`, `position`, `count`, `sort`, `subseq`, `butlast`, `nthcdr`

### 文字列操作
`string-upcase`, `string-downcase`, `string-capitalize`, `string-trim`, `concatenate`, `format`, `char`, `subseq`

### 論理
`and`, `or`, `not`, `null`, `if`, `cond`, `when`, `unless`, `case`

### 型判定
`numberp`, `stringp`, `listp`, `symbolp`, `atom`, `zerop`, `plusp`, `minusp`, `evenp`, `oddp`

### 高階関数
`apply`, `funcall`, `lambda`, `mapcar`, `mapc`, `reduce`, `remove-if`, `remove-if-not`, `find-if`, `every`, `some`, `notevery`, `notany`

---

## ファイル形式

### ネイティブ形式 (.ssp)

```lisp
(:spreadsheet
 :format-version 1
 :metadata (:created "2025-12-26T10:30:00"
            :modified "2025-12-26T11:45:00"
            :app-version "0.7")
 :grid (:rows 26 :cols 14)
 :cells (("A1" 100)
         ("A2" 200 (+ A1 100))
         ("B1" "日本語テスト")))
```

### API

```lisp
(ssp:save "mydata.ssp")
(ssp:load-file "mydata.ssp")
(ssp:new-sheet)
(ssp:export-csv "data.csv")                    ; BOM付き（Excel互換）
(ssp:export-csv "data.csv" :excel-compatible nil)  ; BOMなし
(ssp:import-csv "data.csv")
```

---

## アーキテクチャ (v0.6+)

### 構造体ベース設計

```lisp
(defstruct cell value formula)
(defstruct ss-state rows cols sheet refs dependents ...)
(defstruct eval-context row col stack env)
```

### アクセサ関数

全グローバル状態はアクセサ関数経由でアクセス:
- `(cursor-x)`, `(cursor-y)`, `(move-cursor x y)`
- `(sheet-rows)`, `(sheet-cols)`
- `(get-cell name)`, `(get-cell-raw name)`
- `(get-refs name)`, `(get-dependents name)`

### 依存関係追跡

```
A1: 10
A2: =(+ A1 5)     ; A2はA1に依存
A3: =(* A2 2)     ; A3はA2に依存

A1が変更 → A2を再計算 → A3を再計算
```

### 文字幅計算 (v0.7)

```lisp
(char-display-width #\A)      → 1  ; 半角
(char-display-width #\あ)     → 2  ; 全角
(string-display-width "Hello") → 5
(string-display-width "日本語") → 6
(truncate-to-display-width "日本語テスト" 8) → "日本語…"
```

---

## バージョン履歴

| バージョン | 日付 | 変更点 |
|------------|------|--------|
| 0.7.2 | 2025-12 | シートサイズ制限（1000×26）、スクロールバー、デフォルト100×26、表示30×14 |
| 0.7.1 | 2025-12 | 循環参照検出改善、評価キャッシュ、パフォーマンス最適化 |
| 0.7 | 2025-12 | 日本語・Unicode対応、CJKフォント、文字幅計算、CSV BOM対応 |
| 0.6 | 2025-12 | 構造体ベースアーキテクチャ、アクセサ関数、モジュール分割、SSPに改名 |
| 0.5 | 2025-12 | スマート数式参照、行・列の挿入・削除 |
| 0.4 | 2025-12 | シンタックスハイライト、S式フォーマッター |
| 0.3 | 2025-12 | Undo/Redo、ファイル保存/読み込み、CSV対応 |
| 0.2 | 2025-12 | 範囲選択、クリップボード、ラムダ対応 |
| 0.1 | 2025-12 | 初期リリース |

---

## ライセンス

MIT License

---

## コントリビュート

コントリビューション歓迎！これはスプレッドシートとLispの交差点を探求する学習プロジェクトです。

---

*SSP: すべてのセルが式であり、グリッドがREPLとなる場所。*
