<#
.SYNOPSIS
    把本工程上传到 GitHub，触发云端 macOS 构建，并把产出的未签名 ipa 拉回本地。

.DESCRIPTION
    ipa 只能在 macOS 上产出（Windows 没 Xcode），因此用 GitHub Actions 的 macos runner 构建。
    本脚本负责：上传工程 → workflow_dispatch → 轮询 → 下载 artifact → 落盘到本地 build 目录。

    本机装了 git 就用 git push；**没装 git 也没关系**，会自动走 GitHub Contents API 逐文件上传。

    需要的凭据都在这里生成：https://github.com/settings/tokens
    勾选 repo（全部）与 workflow 两项权限即可。

.PARAMETER RepoUrl
    仓库 HTTPS 地址，例如 https://github.com/zhangsan/cloudphone.git
    仓库需先在网页端建好（空的私有仓库即可）。

.PARAMETER Token
    GitHub Personal Access Token。

.PARAMETER Branch
    推送分支，默认 main。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Scripts\publish_and_build.ps1 `
        -RepoUrl https://github.com/zhangsan/cloudphone.git -Token ghp_xxxxxxxxxxxx
#>
param(
    [Parameter(Mandatory = $true)][string]$RepoUrl,
    [Parameter(Mandatory = $true)][string]$Token,
    [string]$Branch = "main"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

# ---------- 解析 owner/repo ----------
if ($RepoUrl -match 'github\.com[/:](?<owner>[^/]+)/(?<repo>[^/]+?)(\.git)?/?$') {
    $owner = $Matches['owner']
    $repo  = $Matches['repo']
} else {
    throw "无法解析仓库名：$RepoUrl（应为 https://github.com/owner/repo.git）"
}

$headers = @{
    Authorization = "Bearer $Token"
    Accept        = "application/vnd.github+json"
    "User-Agent"  = "CloudPhone-Build"
}

Write-Host "==> 目标仓库：$owner/$repo（分支 $Branch）" -ForegroundColor Cyan

# ---------- 收集文件（排除构建产物） ----------
$files = Get-ChildItem -Path $root -Recurse -File | Where-Object {
    $_.FullName -notmatch '[\\/](build|\.git|_icon_backup_[^\\/]*)[\\/]' -and $_.Extension -ne '.zip'
} | Sort-Object FullName

if ($files.Count -eq 0) { throw "没有找到要上传的文件" }
Write-Host "==> 待上传 $($files.Count) 个文件" -ForegroundColor Cyan

# 覆盖已存在的文件必须带上它的 blob sha。
# ⚠️ contents 的 GET 对部分路径会返回 404（拿不到 sha → PUT 报 "sha wasn't supplied"），
#    必须改用 git trees 递归接口一次性建立 path → sha 索引。
$treeIndex = @{}
try {
    $tree = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/git/trees/$Branch`?recursive=1" -Headers $headers
    foreach ($it in $tree.tree) { if ($it.type -eq 'blob') { $treeIndex[$it.path] = $it.sha } }
    Write-Host "==> 远端已有 $($treeIndex.Count) 个文件（已建 sha 索引）" -ForegroundColor Cyan
} catch {
    Write-Warning "trees 接口失败，退回逐个探测：$($_.Exception.Message)"
}

function Push-File {
    param($FullPath)
    $rel  = $FullPath.Substring($root.Length + 1)
    $apiPath = ($rel -replace '\\', '/')
    $content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($FullPath))

    $body = @{ message = "Update $apiPath"; content = $content; branch = $Branch }

    # 已存在的文件要带上 sha 才能覆盖更新
    if ($treeIndex.ContainsKey($apiPath)) {
        $body.sha = $treeIndex[$apiPath]
    } else {
        try {
            $existing = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/contents/$apiPath?ref=$Branch" -Headers $headers
            if ($existing.sha) { $body.sha = $existing.sha }
        } catch { }
    }

    $json = $body | ConvertTo-Json -Depth 6
    $ok = $false
    for ($attempt = 1; $attempt -le 3 -and -not $ok; $attempt++) {
        try {
            Invoke-RestMethod `
                -Uri "https://api.github.com/repos/$owner/$repo/contents/$apiPath" `
                -Method Put -Headers $headers -ContentType "application/json" `
                -Body ([Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 120 | Out-Null
            $ok = $true
        } catch {
            # 500 多为瞬时故障，重试一次通常就好
            if ($attempt -eq 3) { throw }
            Write-Host "    ! 第 $attempt 次失败，重试：$apiPath" -ForegroundColor Yellow
            Start-Sleep -Seconds 3
        }
    }

    Write-Host "    ↑ $apiPath" -ForegroundColor DarkGray
}

$git = Get-Command git -ErrorAction SilentlyContinue

if ($git) {
    Write-Host "==> 检测到 git，使用 push 方式上传" -ForegroundColor Cyan
    Push-Location $root
    try {
        if (-not (Test-Path ".git")) { git init -b $Branch | Out-Null }
        git config user.email "build@localhost"
        git config user.name  "CloudPhone Build"
        git remote remove origin 2>$null
        git remote add origin "https://x-access-token:$Token@github.com/$owner/$repo.git"
        git add -A
        git commit -m "CloudPhone iOS build setup" 2>$null
        git push -u origin $Branch
    } finally { Pop-Location }
} else {
    Write-Host "==> 未检测到 git，改用 GitHub API 逐文件上传" -ForegroundColor Cyan
    foreach ($f in $files) { Push-File -FullPath $f.FullName }
}
Write-Host "==> 代码已就位" -ForegroundColor Green

# ---------- 触发构建 ----------
Write-Host "==> 触发 build workflow..." -ForegroundColor Cyan
Invoke-RestMethod `
    -Uri "https://api.github.com/repos/$owner/$repo/actions/workflows/build-unsigned-ipa.yml/dispatches" `
    -Method Post -Headers $headers -ContentType "application/json" `
    -Body ( @{ ref = $Branch } | ConvertTo-Json ) | Out-Null

# ---------- 定位 run ----------
Start-Sleep -Seconds 10
$runsUri = "https://api.github.com/repos/$owner/$repo/actions/runs?per_page=5"
$runId = $null
for ($i = 0; $i -lt 12 -and -not $runId; $i++) {
    $runs = Invoke-RestMethod -Uri $runsUri -Headers $headers
    $latest = $runs.workflow_runs | Where-Object { $_.name -eq "Build unsigned IPA" } | Select-Object -First 1
    if ($latest) { $runId = $latest.id } else { Start-Sleep -Seconds 5 }
}
if (-not $runId) { throw "没能定位 workflow run，请到 Actions 页手动 Run workflow。" }

$runHtml = "https://github.com/$owner/$repo/actions/runs/$runId"
Write-Host "==> 构建已开始：$runHtml" -ForegroundColor Cyan

# ---------- 轮询 ----------
$deadline = (Get-Date).AddMinutes(25)
$conclusion = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 15
    $run = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/actions/runs/$runId" -Headers $headers
    if ($run.status -eq "completed") { $conclusion = $run.conclusion; break }
}
if ($conclusion -ne "success") {
    throw "构建未成功（$conclusion），日志见：$runHtml"
}
Write-Host "==> 构建成功" -ForegroundColor Green

# ---------- 下载 ipa ----------
$artifacts = (Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/actions/runs/$runId/artifacts" -Headers $headers).artifacts
if (-not $artifacts) { throw "没有 artifact，请确认 workflow 的 upload-artifact 步骤执行成功" }

$tmp = Join-Path $root "build\_artifact"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$zipPath = Join-Path $tmp "artifact.zip"
Write-Host "==> 下载 $($artifacts[0].name)..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $artifacts[0].archive_download_url -Headers $headers -OutFile $zipPath

Expand-Archive -Path $zipPath -DestinationPath $tmp -Force
$ipa = Get-ChildItem -Path $tmp -Filter *.ipa -Recurse | Select-Object -First 1
if (-not $ipa) { throw "解包后没找到 .ipa" }

$dest = Join-Path $root "build\$($ipa.Name)"
Copy-Item $ipa.FullName $dest -Force

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host " ipa 已就绪：$dest" -ForegroundColor Green
Write-Host " 未签名，需你用自己的证书重签后安装（README「用你自己的证书重签」）" -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Green
explorer.exe (Split-Path -Parent $dest)
