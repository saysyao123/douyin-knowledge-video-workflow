---
name: douyin-whisper-only-transcription
description: "使用本机已验证的 OpenAI Whisper large-v3-turbo 对中文音频或视频进行唯一主路线转写，保留分段与词级时间戳，并按项目目录逐条落盘；适用于参考视频分析、口播稿样本转写和原始音频逐字记录。"
---

# Whisper唯一转写技能

## 适用范围

当任务需要把中文音频或视频转成可复核的口播文本、参考账号样本、逐字稿或带时间轴的转写时，必须使用本技能。它只负责原始音频到转写记录，不负责润色、改写、事实核验和口播稿创作。

本技能的正式转写路线只有一条：

```text
C:\Python314\python.exe
        ↓
openai-whisper 20250625
        ↓
large-v3-turbo.pt（CPU）
        ↓
中文锁定 + 词级时间戳 + 逐条原子落盘
```

## 唯一路线硬约束

- Python固定为 `C:\Python314\python.exe`；
- Whisper固定为本机 `openai-whisper 20250625`；
- 主模型固定为 `large-v3-turbo`，模型文件位于 `C:\Users\adminmailbox\.cache\whisper\large-v3-turbo.pt`；
- 推理固定使用CPU，`fp16=False`；
- 语言固定为 `zh`，任务固定为 `transcribe`；
- 必须开启 `word_timestamps=True`；
- 默认参数为 `temperature=0.0`、`beam_size=5`、`best_of=5`、`condition_on_previous_text=True`；
- 必须逐条保存JSON检查点，保留完整分段时间戳、模型、参数、语言和运行耗时；
- 原始音频是口播文字的唯一事实来源。旧文案、平台标题、字幕、预期答案和其他AI的猜测不得纠正或覆盖ASR结果；
- `small`只能在同一Whisper路线中对争议词做辅助复核，不能替换主模型结果；
- `faster-whisper`、平台自动字幕、第三方ASR、外部AI听写结果均不得进入正式主转写流程；
- 不自动安装新模型、不自动切换Python环境、不在模型缺失时静默下载；门禁失败必须停止并报告。

## 执行方式

正式批量转写使用技能目录下的脚本：

```powershell
& 'C:\Python314\python.exe' `
  'D:\整体视频流程重建\技能库\douyin-whisper-only-transcription\scripts\执行转写.py' `
  --任务文件 'D:\整体视频流程重建\选题项目\某个选题\主模型批量转写任务.json' `
  --输出文件 'D:\整体视频流程重建\选题项目\某个选题\参考样本转写\主模型批量转写结果.json'
```

脚本会在开始前检查Python、Whisper、Torch、模型文件和FFmpeg；输出文件已存在时按ID恢复，已完成的任务跳过，新的任务逐条追加。输出JSON完成后，再调用 `scripts\导出转写阅读稿.py` 生成中文可读稿和时间轴阅读版。

详细参数、输出结构、质量门禁和争议词处理见 [references/参数与质量门禁.md](references/参数与质量门禁.md)。

## 结果处理边界

- 转写结果可以用于分析开头、句长、停顿、结构、案例进入时间和CTA；
- 转写结果不能直接作为企业、人物、数字、政策或财经事实的证据；
- 品牌、人名、数字、专有名词和疑似口误必须保留时间点，必要时用本技能的 `争议复核` 模式复听比较；
- 不为了语言通顺而擅自改字，不删除重复、口头禅或不完整句；
- 只有通过JSON完整性、时间戳和来源记录检查后，才可进入口播稿风格分析。

## 停止条件

出现以下任一情况立即停止：运行Python不是 `C:\Python314\python.exe`、Whisper/Torch版本漂移、模型文件缺失或异常、FFmpeg不可用、输入文件不存在、JSON任务ID重复、输出出现无法解析的半成品，或无法证明结果来自原始音频。
