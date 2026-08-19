import argparse
import json
import re
from pathlib import Path


def stamp(seconds: float) -> str:
    minutes = int(seconds // 60)
    remain = seconds - minutes * 60
    return f"{minutes:02d}:{remain:05.2f}"


def safe_name(value: str) -> str:
    return re.sub(r'[<>:"/\\|?*]', "_", value)


def main() -> None:
    parser = argparse.ArgumentParser(description="导出Whisper转写阅读稿")
    parser.add_argument("--输入文件", required=True)
    parser.add_argument("--输出目录", required=True)
    args = parser.parse_args()
    input_path = Path(args.输入文件).resolve()
    output_dir = Path(args.输出目录).resolve()
    if not input_path.exists():
        raise SystemExit(f"输入JSON不存在：{input_path}")
    records = json.loads(input_path.read_text(encoding="utf-8"))
    if not isinstance(records, list):
        raise SystemExit("输入JSON必须是数组")
    output_dir.mkdir(parents=True, exist_ok=True)
    summary = [
        "# Whisper转写阅读稿汇总",
        "",
        f"- 来源JSON：`{input_path}`",
        f"- 样本数量：{len(records)}",
        "- 说明：以下为原始音频转写，保留口语、重复和疑似识别词，不等同于校订文案。",
        "",
    ]
    for record in records:
        title = record["id"]
        lines = [
            f"# {title}",
            "",
            f"- 原始媒体：`{record.get('audio', '')}`",
            f"- 模型：`{record.get('model', '')}`",
            f"- 语言：`{record.get('language', '')}`",
            f"- 分段数量：{len(record.get('segments', []))}",
            "",
            "## 连续口播文本",
            "",
            record.get("text", "").strip(),
            "",
            "## 时间轴",
            "",
        ]
        for segment in record.get("segments", []):
            lines.append(f"- `{stamp(segment['start'])}—{stamp(segment['end'])}` {segment['text'].strip()}")
        (output_dir / f"{safe_name(title)}_转写阅读稿.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
        summary.extend([f"## {title}", "", record.get("text", "").strip(), ""])
    (output_dir / "转写阅读稿_汇总.md").write_text("\n".join(summary) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
