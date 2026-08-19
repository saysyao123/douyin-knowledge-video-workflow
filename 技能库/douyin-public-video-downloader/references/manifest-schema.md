# 抖音公开视频下载清单格式

清单是每次采集的可复盘入口。建议保存到项目内的中文批次目录，例如：

`D:\整体视频流程重建\下载记录\抖音公开视频\2026-08-18_对标账号采集\下载清单.json`

## 必填字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `account` | string | 页面显示的账号名 |
| `account_folder` | string | 素材输出的中文账号目录名 |
| `aweme_id` | string | 抖音作品 ID，作为去重键 |
| `title` | string | 页面可见标题；不确定时写空或 `null` |
| `source_url` | string | 具体作品页 URL，不要只保存账号主页 |
| `media_url` | string | 本次公开页面临时暴露的媒体地址，只用于即时下载 |
| `filename` | string | 目标文件名，例如 `01_作品ID.mp4` |

## 推荐字段

| 字段 | 说明 |
|---|---|
| `published_at` | 页面可见的发布时间；保留原始时区或写 `null` |
| `selection_rule` | `latest`、`hottest` 或 `specified` |
| `collected_at` | Asia/Shanghai ISO 8601 采集时间 |
| `substituted_for` | 替补时填写原候选作品 ID，否则为 `null` |
| `notes` | 公开页面证据、限制和人工判断 |

## 结果字段

下载脚本不会把临时 `media_url` 复制到最终结果索引。结果至少记录：

- `status`：`downloaded-basic-validated`、`skipped-existing-valid`、`media-url-rejected` 或 `download-failed`；
- `target_path`、`bytes`、`duration_seconds`、`width`、`height`；
- `video_codec`、`audio_codec`、`sha256`；
- `source_url`、`aweme_id`、失败 `error` 和下载时间。

基础下载成功后，仍必须运行完整校验脚本。只有 `verify-video-assets.ps1` 的 `status=ok` 才能进入分析索引。

## 来源与版权记录

公开视频可以作为内部研究样本，不代表获得再发布或商业使用许可。分析记录应区分：原视频画面、平台页面元数据、口播内容转写和分析者推断；不得将推断写成原作者事实。
