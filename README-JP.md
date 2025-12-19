# SSP - Symbolic Spreadsheet for Lisp Learning

**SSPはノートブックではありません。**  
**セルがスクリプトではなく「式」である、Lispネイティブな評価空間です。**

![Version](https://img.shields.io/badge/version-0.6-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Lisp](https://img.shields.io/badge/Common%20Lisp-SBCL-red.svg)
![GUI](https://img.shields.io/badge/GUI-LTK%2FTk-orange.svg)

[English README](README.md)

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
- 文字列: `"Hello, World!"`
- ネスト構造: `((a 1) (b 2))`

---

## スクリーンショット

```
╔═════════════════════════════════════════════════════════════════════╗
║ [File] [Edit]                            SSP v0.6 [14×26]           ║
╠═════════════════════════════════════════════════════════════════════╣
║ =(mapcar #'1+ (range A1 A5))                                        ║
╠════╤════════════╤════════════════════════╤══════════╤═══════════════╣
║    │     A      │           B            │    C     │      D        ║
╠════╪════════════╪════════════════════════╪══════════╪═══════════════╣
║  1 │          1 │ (2 3 4 5 6)            │          │               ║
║  2 │          2 │                        │          │               ║
║  3 │          3 │ FIBONACCI              │          │               ║
║  4 │          4 │ "文字列"               │          │               ║
║  5 │          5 │                        │          │               ║
╚════╧════════════╧════════════════════════╧══════════╧═══════════════╝
       ↑ 数値           ↑ リストが値として表示
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

### データ型
- 数値は右揃え、テキストは左揃え
- リストはインライン表示: `(1 2 3)`
- シンボルは大文字: `HELLO`
- Nilは空セルとして表示

### ユーザーインターフェース
- 列幅・行高さのリサイズ（境界をドラッグ）
- ヘッダーのコンテキストメニュー（右クリック）
- ダイレクト入力モード（入力開始で編集）
- シンタックスハイライト付き複数行入力
- S式オートフォーマッター (Ctrl+Shift+F)

### データ管理
- Undo/Redo (Ctrl+Z / Ctrl+Y) 最大100操作
- ネイティブ `.ssp` ファイル形式
- CSVインポート/エクスポート
- システムクリップボード（TSV形式）
- 範囲選択（ドラッグまたはShift+矢印）

---

## 必要条件

| コンポーネント | バージョン |
|----------------|------------|
| SBCL | 2.0以上推奨 |
| Quicklisp | 最新版 |
| Tcl/Tk | 8.5以上 |

---

## インストール

### 1. SBCLとTkのインストール

```bash
# Ubuntu/Debian
sudo apt install sbcl tk

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
├── package.lisp     ; パッケージ、定数、構造体、アクセサ
├── formula.lisp     ; 許可関数、評価エンジン
├── core.lisp        ; セル操作、依存関係、Undo/Redo、ファイルI/O
├── ui.lisp          ; 描画、入力、シンタックスハイライト
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
|------|------|
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
 :metadata (:created "2025-12-20T10:30:00"
            :modified "2025-12-20T11:45:00"
            :app-version "0.6")
 :grid (:rows 26 :cols 14)
 :cells (("A1" 100)
         ("A2" 200 (+ A1 100))
         ("B1" "Hello")))
```

### API

```lisp
(ssp:save "mydata.ssp")
(ssp:load-file "mydata.ssp")
(ssp:new-sheet)
(ssp:export-csv "data.csv")
(ssp:import-csv "data.csv")
```

---

## アーキテクチャ (v0.6)

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

---

## バージョン履歴

| バージョン | 日付 | 変更点 |
|------------|------|--------|
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
