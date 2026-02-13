# Swift Guidelines MCP Server

Swift API Design Guidelinesを読み込めるMCP (Model Context Protocol) サーバーです。swift.orgからリアルタイムにガイドラインを取得できます。

## 機能

- **readSwiftGuidelines**: Swift API Design Guidelinesをswift.orgから読み込みます
  - オプションで特定のセクション（例: "Naming", "Clarity"）を指定して取得できます
  - セクション指定がない場合は、ガイドライン全体を返します

## 必要な環境

- macOS 13.0以降
- Swift 6.0以降（Xcode 16以降）

## ビルド方法

```bash
swift build -c release
```

実行ファイルは `.build/release/SwiftGuidelinesMCP` に生成されます。

## 使用方法

### Cursorでの設定

1. Cursorの設定を開きます（`Cmd + ,`）
2. MCPサーバーの設定セクションを開きます
3. 以下の設定を追加します：

```json
{
  "mcpServers": {
    "swift-api-guidelines": {
      "command": "/path/to/SwiftGuidelinesMCP/.build/release/SwiftGuidelinesMCP",
      "transport": "stdio"
    }
  }
}
```

**注意**: `/path/to/SwiftGuidelinesMCP` をプロジェクトの実際のパスに置き換えてください。

4. Cursorを再起動します

### 使用例

Cursorのチャットで、`@swift-guidelines` または `@swift-api-guidelines` を指定して使用できます：

```
@swift-guidelines Swiftメソッド命名のベストプラクティスは？
```

または、特定のセクションを指定：

```
@swift-guidelines Namingセクションの内容を教えてください
```

## 技術スタック

- **言語**: Swift 6.0+
- **フレームワーク**: [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)
- **通信方式**: stdio (標準入出力)

## プロジェクト構造

```
SwiftGuidelinesMCP/
├── Package.swift          # Swift Package Managerの設定
└── Sources/
    └── SwiftGuidelinesMCP/
        └── Main.swift     # メイン実装
```

## ライセンス

このプロジェクトは、Swift API Design Guidelinesの内容を取得するためのツールです。取得されるガイドラインの内容は、Swift.orgのライセンスに従います。

## 開発

### 依存関係

- `modelcontextprotocol/swift-sdk`: MCPプロトコルの実装

### 実装の詳細

- MCPサーバーは `Server` クラスを使用して実装されています
- `tools/list` と `tools/call` ハンドラーを実装しています
- swift.orgからHTMLを取得し、テキストを抽出して返します
- セクション指定がある場合は、該当セクションを検索して返します

## トラブルシューティング

### サーバーがすぐに終了する

サーバーが正常に起動しない場合は、ビルドが正しく行われているか確認してください：

```bash
swift build -c release
```

### ガイドラインが取得できない

ネットワーク接続を確認してください。サーバーは `https://swift.org/documentation/api-design-guidelines/` からコンテンツを取得します。

## 謝辞

- [Model Context Protocol](https://modelcontextprotocol.io/) の開発者コミュニティ
- [Swift.org](https://swift.org/) のSwift API Design Guidelines

