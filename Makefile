.PHONY: help setup upgrade build format

# デフォルトターゲット - ヘルプの表示
help:
	@echo "利用可能なコマンド:"
	@echo "  make setup      - 開発環境をセットアップします（SwiftFormat）"
	@echo "  make build      - リリースビルドします（swift build -c release）"
	@echo "  make format     - SwiftFormatでコードをフォーマットします"
	@echo "  make upgrade    - 開発環境ツールをアップグレードします"
	@echo "  make help       - このヘルプを表示します"

# 開発環境のセットアップ（SwiftFormat + swiftly + 最新Swift）
setup:
	@echo "開発環境をセットアップしています..."
	@which brew > /dev/null || (echo "Homebrewがインストールされていません。https://brew.sh を参照してください。" && exit 1)
	@if ! which swiftformat > /dev/null 2>&1; then \
		echo "SwiftFormatをインストール中..."; \
		brew install swiftformat; \
	else \
		echo "SwiftFormatは既にインストール済み"; \
	fi
	@if ! which swiftly > /dev/null 2>&1; then \
		echo "swiftlyをインストール中..."; \
		brew install swiftly; \
		swiftly init --quiet-shell-followup --assume-yes; \
	else \
		echo "swiftlyは既にインストール済み"; \
	fi
	@echo "最新のSwiftツールチェーンをインストール中..."
	@swiftly install --use latest
	@echo "セットアップが完了しました！"
	@echo ""
	@echo "次のステップ:"
	@echo "  1. シェルを開き直す（または 'source ~/.swiftly/env.sh' を実行）してswiftlyのPATHを反映する"
	@echo "  2. 'make build' でバイナリをビルドする"

# リリースビルド（実行ファイルは .build/release/SwiftGuidelinesMCP）
# swiftlyを使用している場合は env.sh を読み込んで PATH を通す
build:
	@. $$HOME/.swiftly/env.sh 2>/dev/null; swift build -c release

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
	@if which swiftly > /dev/null 2>&1; then \
		echo "swiftly本体をアップグレード中..."; \
		brew upgrade swiftly || true; \
		echo "Swiftツールチェーンを最新に更新中..."; \
		swiftly install --use latest; \
	else \
		echo "swiftlyがインストールされていません。'make setup' を実行してください。"; \
	fi
	@echo "アップグレードが完了しました！"
