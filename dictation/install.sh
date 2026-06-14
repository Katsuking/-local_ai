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

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}    Whisper インメモリ音声入力ツール セットアップ${NC}"
echo -e "${BLUE}==================================================${NC}"

# ==========================================
# 1. 必要なシステムパッケージのインストール
# ==========================================
echo -e "\n${YELLOW}[1/5] システムパッケージのインストールを確認しています...${NC}"

# 必要なパッケージのリスト
REQUIRED_PKGS=("python3-dev" "portaudio19-dev" "xclip" "xdotool")
MISSING_PKGS=()

for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -l | grep -qw "$pkg"; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo -e "以下の不足パッケージをインストールします: ${MISSING_PKGS[*]}"
    echo -e "インストールには sudo パスワードの入力が必要です。"
    sudo apt update
    sudo apt install -y "${MISSING_PKGS[@]}"
else
    echo -e "${GREEN}✓ すべてのシステムパッケージがインストール済みです。${NC}"
fi

# ==========================================
# 2. Python 仮想環境 (venv) の作成とパッケージインストール
# ==========================================
echo -e "\n${YELLOW}[2/5] Python 仮想環境のセットアップを行っています...${NC}"

# venv が存在しない場合は作成
if [ ! -d "venv" ]; then
    echo -e "仮想環境 (venv) を作成しています..."
    python3 -m venv venv
fi

# pipのアップグレードと依存パッケージのインストール
echo -e "依存ライブラリをインストールしています (数分かかる場合があります)..."
./venv/bin/pip install --upgrade pip
./venv/bin/pip install -r requirements.txt

echo -e "${GREEN}✓ Pythonライブラリのインストールが完了しました。${NC}"

# ==========================================
# 3. 使用する Whisper モデルの選択
# ==========================================
echo -e "\n${YELLOW}[3/5] 使用する Whisper モデルを選択してください...${NC}"
echo -e "モデルサイズによって、文字起こしの精度と必要なスペック（VRAM容量）が異なります。"
echo -e "  1) large-v3  [精度: 最大]  (RTX 3060 等の VRAM 8GB以上推奨)"
echo -e "  2) medium    [精度: 高]    (VRAM 5GB以上推奨) ※デフォルト"
echo -e "  3) small     [精度: 中]    (VRAM 2GB以上推奨)"
echo -e "  4) tiny      [精度: 低]    (GPUなし / CPUのみ動作に最適)"
read -rp "選択してください (1-4, デフォルト: 2): " model_choice

case "$model_choice" in
    1) SELECTED_MODEL="large-v3" ;;
    3) SELECTED_MODEL="small" ;;
    4) SELECTED_MODEL="tiny" ;;
    *) SELECTED_MODEL="medium" ;;
esac
echo -e "${GREEN}✓ ${SELECTED_MODEL} モデルが選択されました。${NC}"


# ==========================================
# 4. 自動起動 (.desktop) ファイルの動的生成と配置
# ==========================================
echo -e "\n${YELLOW}[4/5] 自動起動 (常駐化) 設定を行っています...${NC}"

# スクリプトを実行している現在の絶対パスを取得
PROJECT_DIR=$(pwd)
AUTOSTART_DIR="$HOME/.config/autostart"
DESKTOP_FILE="voice_input.desktop"

# 自動起動ディレクトリを作成
mkdir -p "$AUTOSTART_DIR"

# ユーザーの環境に合わせた絶対パスを Exec に埋め込んだデスクトップファイルを動的に生成
cat <<EOF > "$AUTOSTART_DIR/$DESKTOP_FILE"
[Desktop Entry]
Type=Application
Name=Voice Input Service
Comment=F8キーで音声入力を行うインメモリWhisperサービス
Exec=$PROJECT_DIR/venv/bin/python $PROJECT_DIR/voice_input.py --model $SELECTED_MODEL
Terminal=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
EOF

# 生成されたファイルに実行権限を付与
chmod +x "$AUTOSTART_DIR/$DESKTOP_FILE"

# プロジェクトルートにもバックアップをコピー
cp "$AUTOSTART_DIR/$DESKTOP_FILE" .

echo -e "${GREEN}✓ 自動起動ファイルを生成し、${AUTOSTART_DIR}/${DESKTOP_FILE} に配置しました。${NC}"

# ==========================================
# 5. セットアップ完了と初回起動
# ==========================================
echo -e "\n${YELLOW}[5/5] セットアップがすべて完了しました！${NC}"

# デスクトップ通知をテスト送信
if command -v notify-send &> /dev/null; then
    notify-send "音声入力" "インストールが完了しました！"
fi

# すでに古い音声入力プロセスが動いている場合は終了する
echo -e "既存の音声入力プロセスを確認しています..."
pkill -f "voice_input.py" || true

# 今すぐバックグラウンドで起動するかユーザーに尋ねる
read -rp "今すぐバックグラウンドで音声入力サービスを起動しますか？ (y/N): " choice
case "$choice" in
  y|Y|yes|Yes )
    echo -e "サービスをバックグラウンドで起動しています..."
    # nohupで起動し、標準出力を破棄してバックグラウンド実行
    nohup ./venv/bin/python voice_input.py --model "$SELECTED_MODEL" >/dev/null 2>&1 &
    echo -e "${GREEN}🚀 音声入力サービスが起動しました！F8キーで動作します。${NC}"
    ;;
  * )
    echo -e "${BLUE}PCを再起動するか、ログインし直したタイミングで自動的に起動します。${NC}"
    ;;
esac

echo -e "\n${GREEN}すべての工程が終了しました！${NC}"
echo -e "${BLUE}==================================================${NC}"

