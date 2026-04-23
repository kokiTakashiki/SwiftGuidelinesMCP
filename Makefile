.PHONY: help setup upgrade build format

# デフォルトターゲット - ヘルプの表示
help:
	@echo "利用可能なコマンド:"
	@echo "  make setup      - 開発環境をセットアップします（SwiftFormat）"
	@echo "  make build      - リリースビルドします（swift build -c release）"
	@echo "  make format     - SwiftFormatでコードをフォーマットします"
	@echo "  make upgrade    - 開発環境ツールをアップグレードします"
	@echo "  make help       - このヘルプを表示します"

# 開発環境のセットアップ（SwiftFormat）
setup:
	@echo "開発環境をセットアップしています..."
	@which brew > /dev/null || (echo "Homebrewがインストールされていません。https://brew.sh を参照してください。" && exit 1)
	@if ! which swiftformat > /dev/null 2>&1; then \
		echo "SwiftFormatをインストール中..."; \
		brew install swiftformat; \
	else \
		echo "SwiftFormatは既にインストール済み"; \
	fi
	@echo "セットアップが完了しました！"

# リリースビルド（実行ファイルは .build/release/SwiftGuidelinesMCP）
build:
	swift build -c release

# SwiftFormatの実行
format:
	@if ! which swiftformat > /dev/null 2>&1; then \
		echo "SwiftFormatがインストールされていません。'make setup' を実行してください。"; \
		exit 1; \
	fi
	swiftformat Sources/

# 開発環境ツールのアップグレード
upgrade:
	@echo "開発環境ツールをアップグレードしています..."
	@which brew > /dev/null 2>&1 || (echo "Homebrewがインストールされていません。" && exit 1)
	@if which swiftformat > /dev/null 2>&1; then \
		echo "SwiftFormatをアップグレード中..."; \
		brew upgrade swiftformat || true; \
	else \
		echo "SwiftFormatがインストールされていません。'make setup' を実行してください。"; \
	fi
	@echo "アップグレードが完了しました！"
