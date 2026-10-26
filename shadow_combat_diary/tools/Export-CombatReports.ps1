param(
    [string]$LogPath = "$env:USERPROFILE\Documents\Klei\DoNotStarveTogether\client_log.txt",
    [string]$OutputDirectory = "$env:USERPROFILE\Desktop\战斗反馈"
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) { throw "找不到客户端日志：$LogPath" }
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$reports = @{}
$events = New-Object 'System.Collections.Generic.List[string]'
$bad = 0
$chunks = @{}
# Read one local log; export only this mod's structured records, not other mods/chat/account logs.
foreach ($line in [IO.File]::ReadLines((Resolve-Path -LiteralPath $LogPath).Path)) {
    $offset = $line.IndexOf('[SCD] ')
    if ($offset -lt 0) { continue }
    $payload = $line.Substring($offset + 6).Trim()
    try { $entry = $payload | ConvertFrom-Json } catch { $bad++; continue }
    if ($entry.schema -ne 1) { continue }
    if ($entry.kind -eq 'record_chunk') {
        try {
            $index=[int]$entry.chunk_index; $count=[int]$entry.chunk_count
            $hex=[string]$entry.data; $key="$($entry.session):$($entry.seq)"
            if ($entry.encoding -ne 'hex-adler32-v1' -or $index -lt 1 -or $index -gt $count -or $count -gt 8389 -or $hex.Length -gt 2000 -or $hex.Length % 2 -ne 0 -or $hex -notmatch '^[0-9a-f]*$') { throw 'bad chunk' }
            if (-not $chunks.ContainsKey($key)) {
                if ($chunks.Count -ge 32) { $chunks.Remove(@($chunks.Keys)[0]); $bad++ }
                $chunks[$key]=@{count=$count; checksum=[string]$entry.checksum; parts=@{}}
            }
            $group=$chunks[$key]
            if ($group.count -ne $count -or $group.checksum -ne $entry.checksum -or ($group.parts.ContainsKey($index) -and $group.parts[$index] -ne $hex)) { $chunks.Remove($key); throw 'conflicting chunk' }
            $group.parts[$index]=$hex
            if ($group.parts.Count -ne $count) { continue }
            $chunks.Remove($key)
            $joined=(@(for($j=1;$j -le $count;$j++) {$group.parts[$j]}) -join '')
            if ($joined.Length -gt 16777216) { throw 'too large' }
            $bytes=New-Object byte[] ($joined.Length/2)
            [long]$a=1; [long]$b=0
            for($j=0;$j -lt $bytes.Length;$j++) {
                $bytes[$j]=[Convert]::ToByte($joined.Substring($j*2,2),16)
                $a=($a+$bytes[$j]) % 65521; $b=($b+$a) % 65521
            }
            if (('{0:x8}' -f ($b*65536+$a)) -ne $group.checksum) { throw 'checksum mismatch' }
            $session=$entry.session; $seq=$entry.seq
            $payload=[Text.Encoding]::UTF8.GetString($bytes)
            $entry=$payload | ConvertFrom-Json
            if ($entry.schema -ne 1 -or $entry.session -ne $session -or $entry.seq -ne $seq -or $entry.kind -eq 'record_chunk') { throw 'identity mismatch' }
        } catch { $bad++; continue }
    }
    $events.Add($payload)
    if ($entry.kind -eq 'death_report' -and $entry.report.id) { $reports[[string]$entry.report.id] = $entry.report }
}
$encoding = New-Object Text.UTF8Encoding($true)
$allEvents = Join-Path $OutputDirectory 'combat-events.jsonl'
[IO.File]::WriteAllLines($allEvents, $events, $encoding)
$summary = @('# 战斗反馈汇总', '', "死亡报告数：$($reports.Count)", "跳过损坏/截断记录：$bad", "未收齐分段记录：$($chunks.Count)", '')
foreach ($id in ($reports.Keys | Sort-Object)) {
    $report = $reports[$id]
    $safeId = $id -replace '[^a-zA-Z0-9_.-]', '_'
    $jsonPath = Join-Path $OutputDirectory "$safeId.json"
    $textPath = Join-Path $OutputDirectory "$safeId.md"
    [IO.File]::WriteAllText($jsonPath, ($report | ConvertTo-Json -Depth 50), $encoding)
    [IO.File]::WriteAllText($textPath, [string]$report.summary_text, $encoding)
    $summary += @([string]$report.summary_text, '', '---', '')
}
if ($reports.Count -eq 0) { $summary += '这份日志中尚无死亡报告。请启用模组完成一次对战后再次导出。原版重启会轮换日志；也可用 -LogPath 指定旧日志。' }
[IO.File]::WriteAllText((Join-Path $OutputDirectory '反馈汇总.md'), ($summary -join [Environment]::NewLine), $encoding)
Write-Output "已导出 $($reports.Count) 份死亡反馈，$($events.Count) 条事件到：$OutputDirectory"
if ($bad -gt 0) { Write-Output "有 $bad 条记录损坏或截断，已跳过；其余报告正常保留。" }
