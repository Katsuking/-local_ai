from faster_whisper import WhisperModel
from pynput import keyboard
import pyperclip
import sounddevice as sd
import numpy as np
import subprocess
import threading
import time
import os
import sys

# ==========================================
# CUDA 共有ライブラリの動的パス追加処理
# ==========================================
# ctranslate2 が必要とする libcublas.so.12 を、システム上の Ollama が持つ CUDA 12 パスから読み込めるようにします。
# プロセス開始後に os.environ で LD_LIBRARY_PATH を書き換えても動的リンカは認識しないため、
# パスを設定した上で os.execve() を使用して自分自身（プロセス）を再起動します。
OLLAMA_CUDA_PATH = "/usr/local/lib/ollama/cuda_v12"
if os.path.isdir(OLLAMA_CUDA_PATH):
  current_ld_path = os.environ.get("LD_LIBRARY_PATH", "")
  if OLLAMA_CUDA_PATH not in current_ld_path.split(":"):
    new_ld_path = f"{OLLAMA_CUDA_PATH}:{current_ld_path}" if current_ld_path else OLLAMA_CUDA_PATH
    os.environ["LD_LIBRARY_PATH"] = new_ld_path
    try:
      # 環境変数を更新した状態でプロセスを起動し直します
      os.execve(sys.executable, [sys.executable] + sys.argv, os.environ)
    except Exception as e:
      print(f"[音声入力] 動的リンク追加後の再起動に失敗しました: {e}")


# ==========================================
# 設定パラメータ
# ==========================================
MODEL_SIZE = "large-v3"       # RTX 3060 の VRAM 性能を最大限活かすため、最も高精度な large-v3 を使用
DEVICE = "cuda"               # GPU (CUDA) 加速を有効化
COMPUTE_TYPE = "float16"      # 半精度浮動小数点 (float16) を使用し、処理の高速化と VRAM 節約を両立
SAMPLE_RATE = 16000           # Whisperモデルが要求する標準サンプリングレート (16kHz)

# ==========================================
# グローバル状態管理
# ==========================================
is_recording = False          # 現在録音中かどうかのフラグ
audio_buffer = []             # 録音データを一時的にメモリ上に保持するリスト (一時ファイルは作成しない)
stream = None                 # sounddevice の録音ストリームオブジェクト
model = None                  # WhisperModel インスタンス
keyboard_controller = keyboard.Controller()  # キー入力をシミュレートするためのコントローラー


def send_notification(title, message):
  """
  Ubuntu のデスクトップ通知 (notify-send) を送信して、
  バックグラウンド動作時にも音声入力の状態が視覚的にわかるようにします。
  """
  try:
    subprocess.run(["notify-send", "-t", "2000", title, message])
  except Exception as e:
    print(f"通知の送信に失敗しました: {e}")


def audio_callback(indata, frames, time_info, status):
  """
  sounddevice の入力ストリームから呼び出されるコールバック関数。
  取得した音声データをそのままメモリ上のリストに追加します。
  """
  if status:
    print(f"音声入力警告: {status}")
  if is_recording:
    audio_buffer.append(indata.copy())


def start_recording():
  """
  録音処理を開始します。
  """
  global is_recording, audio_buffer, stream
  audio_buffer = []
  is_recording = True

  send_notification("音声入力", "🔴 録音中...")
  print("\n[音声入力] 録音を開始しました。")

  # 16kHz モノラル、float32 形式でマイクから入力を取得
  stream = sd.InputStream(
      samplerate=SAMPLE_RATE,
      channels=1,
      dtype='float32',
      callback=audio_callback
  )
  stream.start()


def stop_and_transcribe():
  """
  録音を停止し、非同期で文字起こしおよび入力エミュレーション処理を開始します。
  """
  global is_recording, stream
  is_recording = False

  print("[音声入力] 録音を停止しました。文字起こしを開始します。")
  send_notification("音声入力", "⏳ 認識中...")

  if stream:
    stream.stop()
    stream.close()
    stream = None

  # 文字起こしと入力処理は UI やリスナーをブロックしないよう、別スレッドで非同期実行します
  threading.Thread(target=process_audio).start()


def process_audio():
  """
  メモリ上の音声データを結合し、Whisper でテキスト化してアクティブウィンドウに貼り付けます。
  """
  global audio_buffer
  if not audio_buffer:
    print("[音声入力] 録音データが空です。")
    send_notification("音声入力", "❌ 音声データがありません")
    return

  # メモリ上の音声バッファを結合して平坦な NumPy 配列にします (ファイル書き出しなし)
  audio_data = np.concatenate(audio_buffer, axis=0).flatten()

  try:
    start_time = time.time()

    # Whisperモデルで文字起こしを実行 (日本語を指定、beam_sizeは標準の5)
    segments, info = model.transcribe(audio_data, beam_size=5, language="ja")
    text = "".join([segment.text for segment in segments])

    elapsed_time = time.time() - start_time
    print(f"[音声入力] 処理時間: {elapsed_time:.2f}秒")
    print(f"[音声入力] 認識結果: {text}")

    if text.strip():
      paste_text(text)
    else:
      send_notification("音声入力", "⚠️ 音声を認識できませんでした")

  except Exception as e:
    print(f"[音声入力] 文字起こしエラー: {e}")
    send_notification("音声入力", f"❌ エラーが発生しました: {e}")


def paste_text(text):
  """
  文字起こし結果をクリップボードにコピーし、
  Ctrl+V を送信してアクティブウィンドウに入力します。
  """
  # 元のクリップボードの値を退避して後で復元したい場合は、以下の行のコメントアウトを解除します
  # original_clipboard = pyperclip.paste()

  # 認識されたテキストをクリップボードに設定（これにより文字起こし結果がクリップボードに残ります）
  pyperclip.copy(text)

  # アプリケーションがフォーカスやクリップボード変更を検知するための短いウェイト
  time.sleep(0.1)

  # Ctrl + V キーの送信をシミュレート
  with keyboard_controller.pressed(keyboard.Key.ctrl):
    keyboard_controller.press('v')
    keyboard_controller.release('v')

  # 元のクリップボードの値を復元したい場合は、以下の行のコメントアウトを解除します
  # time.sleep(0.2)
  # pyperclip.copy(original_clipboard)

  send_notification("音声入力", f"✓ 入力完了: \"{text[:15]}...\"")


def on_press(key):
  """
  キーが押されたときに呼び出されるリスナーコールバック。
  F8キーが押された場合に、録音の開始/終了を切り替えます。
  """
  global is_recording
  # F8 キーの入力を判定
  if key == keyboard.Key.f8:
    if not is_recording:
      start_recording()
    else:
      stop_and_transcribe()


def main():
  """
  メインエントリーポイント。モデルを初期化し、グローバルキーボードリスナーを起動します。
  """
  global model
  print("[音声入力] GPU (RTX 3060) で Whisper モデル (large-v3) をロードしています...")
  send_notification("音声入力", "🚀 モデルをロード中...")

  # モデルのロード (これには初回のダウンロードやGPUロードで数十秒かかる場合があります)
  model = WhisperModel(MODEL_SIZE, device=DEVICE, compute_type=COMPUTE_TYPE)

  print("[音声入力] 準備完了! F8キーを押して音声入力を開始/停止してください。")
  send_notification("音声入力", "🟢 準備完了 (F8キーで開始/停止)")

  # キーボード入力を監視するリスナーを起動し、メインスレッドで待機します
  with keyboard.Listener(on_press=on_press) as listener:
    listener.join()


if __name__ == "__main__":
  main()
