#!/bin/bash

# エラーが発生した場合にスクリプトを終了する設定
set -e

# ==========================================
# カラー出力用の定義
# ==========================================
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${RED}==================================================${NC}"
echo -e "${RED}    Whisper 音声入力ツール アンインストール (クリーンアップ)${NC}"
echo -e "${RED}==================================================${NC}"

# ==========================================
# 1. 実行中プロセスの停止
# ==========================================
echo -e "\n${YELLOW}[1/4] 実行中の音声入力サービスを停止しています...${NC}"
if pkill -f "voice_input.py" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ 動作中のプロセスを停止しました。${NC}"
else
    echo -e "実行中のプロセスはありませんでした。"
fi

# ==========================================
# 2. 自動起動設定の削除
# ==========================================
echo -e "\n${YELLOW}[2/4] 自動起動設定を解除しています...${NC}"
AUTOSTART_FILE="$HOME/.config/autostart/voice_input.desktop"

if [ -f "$AUTOSTART_FILE" ]; then
    rm -f "$AUTOSTART_FILE"
    echo -e "${GREEN}✓ ${AUTOSTART_FILE} を削除しました。${NC}"
else
    echo -e "自動起動設定ファイルはありませんでした。"
fi

# プロジェクト内の desktop ファイルも削除
if [ -f "voice_input.desktop" ]; then
    rm -f "voice_input.desktop"
fi

# ==========================================
# 3. Python 仮想環境 (venv) の削除
# ==========================================
echo -e "\n${YELLOW}[3/4] Python 仮想環境 (venv) を削除しています...${NC}"
if [ -d "venv" ]; then
    rm -rf venv
    echo -e "${GREEN}✓ venv ディレクトリを削除しました。${NC}"
else
    echo -e "削除する venv ディレクトリはありませんでした。"
fi

# ==========================================
# 4. ダウンロード済み Whisper モデルキャッシュの削除確認
# ==========================================
echo -e "\n${YELLOW}[4/4] Whisper モデルキャッシュの確認を行っています...${NC}"
HF_CACHE_DIR="$HOME/.cache/huggingface/hub"
LARGE_V3_CACHE="$HF_CACHE_DIR/models--Systran--faster-whisper-large-v3"
TINY_CACHE="$HF_CACHE_DIR/models--Systran--faster-whisper-tiny"

# キャッシュサイズの見積もり
CACHE_EXISTS=false
if [ -d "$LARGE_V3_CACHE" ] || [ -d "$TINY_CACHE" ]; then
    CACHE_EXISTS=true
fi

if [ "$CACHE_EXISTS" = true ]; then
    echo -e "${YELLOW}Hugging Face に保存されている学習済みモデルのキャッシュ（約3.1GB）が見つかりました。${NC}"
    read -rp "ディスク容量を解放するために、ダウンロード済みの Whisper モデルを削除しますか？ (y/N): " choice
    case "$choice" in 
      y|Y|yes|Yes )
        echo -e "モデルキャッシュを削除しています..."
        rm -rf "$LARGE_V3_CACHE" "$TINY_CACHE"
        echo -e "${GREEN}✓ モデルキャッシュを削除しました。${NC}"
        ;;
      * )
        echo -e "${BLUE}モデルキャッシュを保持したままにします（再度インストールする際に高速に起動できます）。${NC}"
        ;;
    esac
else
    echo -e "削除対象のモデルキャッシュはありませんでした。"
fi

# デスクトップ通知を送信
if command -v notify-send &> /dev/null; then
    notify-send "音声入力" "アンインストールが完了しました"
fi

echo -e "\n${GREEN}すべてのクリーンアップ処理が正常に終了しました。${NC}"
echo -e "${RED}==================================================${NC}"
