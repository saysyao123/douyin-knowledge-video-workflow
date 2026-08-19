import argparse
import json
import os
import shutil
import sys
import time
from pathlib import Path


EXPECTED_PYTHON = Path(r"C:\Python314\python.exe")
MODEL_CACHE = Path(r"C:\Users\adminmailbox\.cache\whisper")
MODELS = {
    "主转写": ("large-v3-turbo", "large-v3-turbo.pt", 1_500_000_000),
    "争议复核": ("small", "small.pt", 400_000_000),
}
WORKFLOW = "douyin-whisper-only-transcription"


def fail(message: str) -> None:
    raise SystemExit(f"[STOP] {message}")


def atomic_write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_name(path.name + ".part")
    partial.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(partial, path)


def load_tasks(path: Path):
    if not path.exists():
        fail(f"任务文件不存在：{path}")
    try:
        tasks = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail(f"任务文件无法解析：{exc}")
    if not isinstance(tasks, list) or not tasks:
        fail("任务文件必须是非空JSON数组")
    ids = [item.get("id") for item in tasks]
    if any(not item for item in ids) or len(ids) != len(set(ids)):
        fail("任务ID必须存在且不能重复")
    for task in tasks:
        source = Path(task.get("audio", ""))
        if not source.is_absolute():
            source = path.parent / source
        if not source.exists():
            fail(f"输入媒体不存在：{source}")
        task["audio"] = str(source.resolve())
    return tasks


def load_checkpoint(path: Path):
    if not path.exists():
        return []
    try:
        records = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail(f"已有输出文件无法解析，拒绝覆盖：{exc}")
    if not isinstance(records, list):
        fail("已有输出文件不是JSON数组，拒绝覆盖")
    ids = [item.get("id") for item in records]
    if len(ids) != len(set(ids)):
        fail("已有输出文件包含重复ID，拒绝继续")
    return records


def main() -> None:
    parser = argparse.ArgumentParser(description="Whisper唯一转写执行器")
    parser.add_argument("--任务文件", required=True)
    parser.add_argument("--输出文件", required=True)
    parser.add_argument("--模式", choices=list(MODELS), default="主转写")
    args = parser.parse_args()

    if str(Path(sys.executable).resolve()).lower() != str(EXPECTED_PYTHON.resolve()).lower():
        fail(f"Python环境不符合唯一流程要求：{sys.executable}")
    if shutil.which("ffmpeg") is None:
        fail("找不到FFmpeg，Whisper无法读取媒体")

    try:
        import torch
        import whisper
    except Exception as exc:
        fail(f"Whisper或Torch不可导入：{exc}")
    if getattr(whisper, "__version__", "") != "20250625":
        fail(f"Whisper版本漂移：{getattr(whisper, '__version__', 'unknown')}")
    if not str(torch.__version__).startswith("2.10.0+cpu"):
        fail(f"Torch版本或CPU构建漂移：{torch.__version__}")

    model_name, model_filename, min_size = MODELS[args.模式]
    model_path = MODEL_CACHE / model_filename
    if not model_path.exists() or model_path.stat().st_size < min_size:
        fail(f"模型文件缺失或大小异常：{model_path}")

    task_path = Path(args.任务文件).resolve()
    output_path = Path(args.输出文件).resolve()
    tasks = load_tasks(task_path)
    records = load_checkpoint(output_path)
    finished = {item["id"] for item in records}

    print(f"workflow={WORKFLOW}")
    print(f"python={sys.executable}")
    print(f"whisper={whisper.__version__} torch={torch.__version__}")
    print(f"model={model_name} device=cpu")
    print(f"tasks={len(tasks)} finished={len(finished)}")

    if len(finished) == len(tasks):
        print("[OK] 所有任务已经完成，无需重复转写")
        return

    model = whisper.load_model(model_name, device="cpu", download_root=str(MODEL_CACHE))
    for task in tasks:
        if task["id"] in finished:
            print(f"skip {task['id']}", flush=True)
            continue
        print(f"transcribing {task['id']}", flush=True)
        started = time.time()
        parameters = {
            "language": "zh",
            "task": "transcribe",
            "fp16": False,
            "verbose": False,
            "word_timestamps": True,
            "condition_on_previous_text": task.get("condition_on_previous_text", True),
            "temperature": task.get("temperature", 0.0),
            "beam_size": task.get("beam_size", 5),
            "best_of": task.get("best_of", 5),
        }
        result = model.transcribe(task["audio"], **parameters)
        records.append({
            "workflow": WORKFLOW,
            "id": task["id"],
            "audio": task["audio"],
            "pass": task.get("pass", args.模式),
            "model": model_name,
            "device": "cpu",
            "python": sys.executable,
            "whisper_version": whisper.__version__,
            "torch_version": torch.__version__,
            "parameters": {key: value for key, value in parameters.items() if key not in ("verbose", "fp16")},
            "duration_seconds": time.time() - started,
            "language": result.get("language"),
            "text": result.get("text", "").strip(),
            "segments": result.get("segments", []),
        })
        atomic_write_json(output_path, records)
        print(f"done {task['id']} in {records[-1]['duration_seconds']:.1f}s", flush=True)


if __name__ == "__main__":
    main()
