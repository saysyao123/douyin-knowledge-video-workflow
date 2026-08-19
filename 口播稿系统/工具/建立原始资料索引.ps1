param(
    [string]$原始资料目录 = 'D:\整体视频流程重建\资料库\原始资料',
    [string]$索引输出 = 'D:\整体视频流程重建\资料库\资料索引\原始资料文件索引_V1.0.csv'
)

$主题规则 = [ordered]@{
    '认知与思维' = '本质|问题分析|思考|思维|认知|聪明|逻辑|判断|决策|学习|知识|行为|平庸|碌碌'
    '商业与产品' = '商业|产品|市场|竞品|用户|销售|转化|增长|定位|管理|企业|公司|创业|财务|股票|投资|收益|纳税'
    '职场与表达' = '工作|职场|领导|升职|加薪|面试|公务员|就业|沟通|表达|团队|时间管理|效率|简历|演讲'
    '财富与消费' = '财富|赚钱|收入|消费|投资|股票|收益|花呗|理财|资产'
    '故事与案例' = '历史|案件|真实|社会|战争|人物|故事|案例|教父|西游|小说'
}

function Get-主题([string]$名称) {
    $命中 = @($主题规则.Keys | Where-Object { $名称 -match $主题规则[$_] })
    if ($命中.Count -eq 0) { return '待人工归类' }
    return ($命中 -join '；')
}

$文件 = Get-ChildItem -LiteralPath $原始资料目录 -Recurse -File | Sort-Object FullName
$结果 = for ($i = 0; $i -lt $文件.Count; $i++) {
    $项 = $文件[$i]
    $状态 = if ($项.Extension -eq '.qkdownloading') { '未完成下载' } elseif ($项.Extension -eq '.pdf') { '待内容核验' } elseif ($项.Extension -eq '.md') { '说明文件' } else { '待识别' }
    [PSCustomObject]@{
        资料ID = ('MAT-{0:D4}' -f ($i + 1))
        文件名 = $项.Name
        扩展名 = $项.Extension
        文件大小字节 = $项.Length
        修改时间 = $项.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
        主题粗分类 = Get-主题 $项.BaseName
        核验状态 = $状态
        原始路径 = $项.FullName
    }
}

$父目录 = Split-Path -Parent $索引输出
New-Item -ItemType Directory -Path $父目录 -Force | Out-Null
$结果 | Export-Csv -LiteralPath $索引输出 -NoTypeInformation -Encoding UTF8
Write-Output ("已建立资料索引：{0} 条，输出：{1}" -f $结果.Count, $索引输出)
