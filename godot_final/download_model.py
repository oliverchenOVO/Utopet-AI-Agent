"""
執行此腳本以下載 faster-whisper-medium 語音模型。
模型約 1.5 GB，需要網路連線。

用法：
    python download_model.py
"""

from pathlib import Path
from huggingface_hub import snapshot_download

MODEL_REPO = "Systran/faster-whisper-medium"
LOCAL_DIR  = Path(__file__).parent / "faster-whisper-medium"

def main():
    if (LOCAL_DIR / "model.bin").exists():
        print(f"模型已存在：{LOCAL_DIR}")
        return

    print(f"開始下載 {MODEL_REPO} → {LOCAL_DIR}")
    print("檔案約 1.5 GB，請耐心等待...\n")

    snapshot_download(
        repo_id=MODEL_REPO,
        repo_type="model",
        local_dir=str(LOCAL_DIR),
        ignore_patterns=["*.msgpack", "flax_model*", "tf_model*", "*.h5"],
    )
    print(f"\n下載完成：{LOCAL_DIR}")

if __name__ == "__main__":
    main()
