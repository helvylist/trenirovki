# Тренировки 3/3: иконка в трее, уведомления по расписанию, автозапуск.
param([switch]$Push, [string]$ResultFile)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$target = Join-Path $env:LOCALAPPDATA 'Trenirovki'
$self = Join-Path $target 'trenirovki-tray.ps1'
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Trenirovki.lnk'
$repoFile = Join-Path $target 'repo.txt'

# Папка git-репозитория: из repo.txt или Desktop\dad
function Get-Repo {
    if (Test-Path -LiteralPath $repoFile) {
        $p = Get-Content -LiteralPath $repoFile -Encoding UTF8 -TotalCount 1
        if ($p) { return ([string]$p).Trim() }
    }
    return (Join-Path $env:USERPROFILE 'Desktop\dad')
}

function Get-Downloads {
    $p = $null
    try { $p = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path } catch { }
    if (-not $p) { $p = Join-Path $env:USERPROFILE 'Downloads' }
    return $p
}

# Забирает свежие файлы проекта из «Загрузок», делает commit и push. Возвращает 'OK|текст' или 'ERR|текст'.
function Invoke-GitPush([string]$repo, [string]$dl) {
    try {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return 'ERR|Git не найден. Установи Git for Windows.' }
        if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) { return ('ERR|Нет git-репозитория: ' + $repo) }
        $env:GIT_TERMINAL_PROMPT = '0'
        $copied = 0
        foreach ($n in 'trenirovki.html', 'trenirovki-tray.ps1', 'ustanovit-tray.bat', 'push-github.bat', 'zapusk.bat', 'raspisanie.docx', 'manifest.webmanifest', 'sw.js', 'icon-192.png', 'icon-512.png') {
            $b = [regex]::Escape([IO.Path]::GetFileNameWithoutExtension($n))
            $x = [regex]::Escape([IO.Path]::GetExtension($n))
            $c = Get-ChildItem -LiteralPath $dl -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $n -or $_.Name -match ('^' + $b + ' \(\d+\)' + $x + '$') } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($c) {
                $dst = Join-Path $repo $n
                if (-not (Test-Path -LiteralPath $dst) -or $c.LastWriteTime -gt (Get-Item -LiteralPath $dst).LastWriteTime) {
                    Copy-Item -LiteralPath $c.FullName -Destination $dst -Force
                    $copied++
                }
            }
        }
        Push-Location -LiteralPath $repo
        try {
            & git add -A 2>&1 | Out-Null
            $st = (& git status --porcelain 2>&1 | Out-String).Trim()
            if (-not $st) { return 'OK|Нечего отправлять: изменений нет.' }
            $o = (& git commit -m ('Update ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')) 2>&1 | Out-String).Trim()
            if ($LASTEXITCODE -ne 0) { return ('ERR|Коммит не удался: ' + $o) }
            $o = (& git push 2>&1 | Out-String).Trim()
            if ($LASTEXITCODE -ne 0) { return ('ERR|Push не удался: ' + $o) }
            return ('OK|Отправлено на GitHub. Файлов из «Загрузок»: ' + $copied + '. Сайт обновится через минуту.')
        } finally { Pop-Location }
    } catch { return ('ERR|' + $_.Exception.Message) }
}

# Режим -Push: без трея, один раз (его вызывает и меню трея, и push-github.bat)
if ($Push) {
    $res = Invoke-GitPush (Get-Repo) (Get-Downloads)
    if ($ResultFile) { Set-Content -LiteralPath $ResultFile -Value $res -Encoding UTF8 } else { Write-Host $res }
    exit
}

function Set-Autostart([bool]$on) {
    if ($on) {
        $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
        $s.TargetPath = 'powershell.exe'
        $s.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $self + '"'
        $s.WindowStyle = 7
        $s.Save()
    } else {
        Remove-Item $lnk -Force -ErrorAction SilentlyContinue
    }
}

# Установка: скрипт запущен не из рабочей папки
if ($PSScriptRoot -ne $target) {
    try {
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        # Закрываем старую копию трея: она держит мьютекс, и новая версия иначе не запустится
        try {
            Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*trenirovki-tray.ps1*' -and $_.CommandLine -notlike '*-Push*' } |
                ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        } catch { }
        Start-Sleep -Milliseconds 600
        Copy-Item -Path $PSCommandPath -Destination $self -Force -ErrorAction Stop
        Set-Autostart $true
        Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $self + '"')
        [System.Windows.Forms.MessageBox]::Show('Готово. Иконка появится в трее у часов (возможно, за стрелкой). Автозапуск включён.', 'Тренировки 3/3') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show('Не получилось: ' + $_.Exception.Message, 'Тренировки 3/3') | Out-Null
    }
    exit
}

$ErrorActionPreference = 'SilentlyContinue'
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\TrenirovkiTray', [ref]$created)
if (-not $created) { exit }

$default = @'
{
 "v": 3,
 "url": "https://helvylist.github.io/trenirovki/trenirovki.html",
 "start": "2026-10-08",
 "days": [
  [
   {
    "t": "07:30",
    "n": "Завтрак",
    "m": 30
   },
   {
    "t": "11:30",
    "n": "Готовка на 3 дня: обед и ужин",
    "m": 90
   },
   {
    "t": "13:30",
    "n": "Обед",
    "m": 30
   },
   {
    "t": "17:30",
    "n": "Тренировка · День 1 · Толкай",
    "m": 52
   },
   {
    "t": "18:32",
    "n": "Коктейль",
    "m": 10
   },
   {
    "t": "20:00",
    "n": "Ужин",
    "m": 30
   }
  ],
  [
   {
    "t": "07:30",
    "n": "Завтрак",
    "m": 30
   },
   {
    "t": "13:30",
    "n": "Обед",
    "m": 30
   },
   {
    "t": "17:30",
    "n": "Тренировка · День 2 · Тяни",
    "m": 51
   },
   {
    "t": "18:31",
    "n": "Коктейль",
    "m": 10
   },
   {
    "t": "20:00",
    "n": "Ужин",
    "m": 30
   }
  ],
  [
   {
    "t": "07:30",
    "n": "Завтрак",
    "m": 30
   },
   {
    "t": "13:30",
    "n": "Обед",
    "m": 30
   },
   {
    "t": "17:30",
    "n": "Тренировка · День 3 · Ноги и пресс",
    "m": 51
   },
   {
    "t": "18:31",
    "n": "Коктейль",
    "m": 10
   },
   {
    "t": "20:00",
    "n": "Ужин",
    "m": 30
   }
  ],
  [
   {
    "t": "07:00",
    "n": "Блок осанки",
    "m": 9
   },
   {
    "t": "07:19",
    "n": "Завтрак",
    "m": 30
   },
   {
    "t": "07:59",
    "n": "Дорога на работу",
    "m": 60
   },
   {
    "t": "20:59",
    "n": "Дорога домой",
    "m": 60
   },
   {
    "t": "22:09",
    "n": "Коктейль",
    "m": 10
   }
  ],
  [
   {
    "t": "07:00",
    "n": "Блок осанки",
    "m": 9
   },
   {
    "t": "07:19",
    "n": "Завтрак",
    "m": 30
   },
   {
    "t": "07:59",
    "n": "Дорога на работу",
    "m": 60
   },
   {
    "t": "20:59",
    "n": "Дорога домой",
    "m": 60
   },
   {
    "t": "22:09",
    "n": "Коктейль",
    "m": 10
   }
  ],
  [
   {
    "t": "07:00",
    "n": "Блок осанки",
    "m": 9
   },
   {
    "t": "07:19",
    "n": "Завтрак",
    "m": 30
   },
   {
    "t": "07:59",
    "n": "Дорога на работу",
    "m": 60
   },
   {
    "t": "20:59",
    "n": "Дорога домой",
    "m": 60
   },
   {
    "t": "22:09",
    "n": "Коктейль",
    "m": 10
   }
  ]
 ]
}
'@ | ConvertFrom-Json

$dl = $null
try { $dl = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path } catch { }
if (-not $dl) { $dl = Join-Path $env:USERPROFILE 'Downloads' }
# Настройки: самый свежий tray-config*.json из рабочей папки или из «Загрузок»
function Get-Cfg {
    $files = Get-ChildItem -Path (Join-Path $target 'tray-config*.json'), (Join-Path $dl 'tray-config*.json') | Sort-Object LastWriteTime -Descending
    foreach ($f in $files) {
        try { $c = Get-Content -Path $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json; if ($c.days -and ([int]$c.v -ge [int]$default.v)) { return $c } } catch { }
    }
    return $default
}

function Get-Plan([datetime]$day) {
    $start = [datetime]::ParseExact($script:cfg.start, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    $n = ($day.Date - $start).Days
    if ($n -lt 0) { return @() }
    $out = foreach ($a in @($script:cfg.days[$n % 6])) {
        $hm = $a.t -split ':'
        [pscustomobject]@{ Key = $a.n; Start = $day.Date.AddHours([int]$hm[0]).AddMinutes([int]$hm[1]); Title = $a.n }
    }
    return @($out | Sort-Object Start)
}

# Открывает локальный trenirovki.html из папки репозитория (те же данные, что и у zapusk.bat).
# Если файла нет, открывает версию на GitHub Pages.
function Open-App {
    $u = $null
    try {
        $f = Join-Path (Get-Repo) 'trenirovki.html'
        if (Test-Path -LiteralPath $f) { $u = ([System.Uri]$f).AbsoluteUri }
    } catch { }
    if (-not $u) { $u = [string]$script:cfg.url }
    try { Start-Process 'msedge.exe' -ArgumentList ('--app="' + $u + '"') -ErrorAction Stop }
    catch { Start-Process $u }
}

$script:cfg = Get-Cfg
$script:done = @{}

# Иконка рисуется кодом: гантель на зелёном фоне
$bmp = New-Object System.Drawing.Bitmap 32, 32
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::FromArgb(11, 122, 110))
foreach ($r in @(@(8, 15, 16, 3), @(5, 10, 3, 13), @(24, 10, 3, 13), @(8, 12, 3, 9), @(21, 12, 3, 9))) {
    $g.FillRectangle([System.Drawing.Brushes]::White, $r[0], $r[1], $r[2], $r[3])
}
$g.Dispose()

$ni = New-Object System.Windows.Forms.NotifyIcon
$ni.Icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
$ni.Text = 'Тренировки 3/3'
$ni.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miOpen = $menu.Items.Add('Открыть приложение')
$miOpen.Add_Click({ Open-App })
$miNext = $menu.Items.Add('Дальше: —')
$miNext.Enabled = $false
$menu.Items.Add('-') | Out-Null
$miAuto = New-Object System.Windows.Forms.ToolStripMenuItem('Запускать при входе в Windows')
$miAuto.CheckOnClick = $true
$miAuto.Checked = (Test-Path $lnk)
$miAuto.Add_Click({ Set-Autostart $miAuto.Checked })
$menu.Items.Add($miAuto) | Out-Null
$menu.Items.Add('-') | Out-Null

function Say([string]$title, [string]$text, [string]$icon = 'Info') {
    if ($text.Length -gt 250) { $text = $text.Substring(0, 250) }
    $ni.ShowBalloonTip(8000, $title, $text, [System.Windows.Forms.ToolTipIcon]::$icon)
}

$script:pushProc = $null
$script:pushOut = Join-Path $env:TEMP 'trenirovki-push.txt'
$script:pushTimer = New-Object System.Windows.Forms.Timer
$script:pushTimer.Interval = 1000
$script:pushTimer.Add_Tick({
    if ($script:pushProc -and $script:pushProc.HasExited) {
        $script:pushTimer.Stop()
        $r = ''
        if (Test-Path -LiteralPath $script:pushOut) { $r = ([string](Get-Content -LiteralPath $script:pushOut -Raw -Encoding UTF8)).Trim() }
        $script:pushProc = $null
        if ($r -like 'OK|*') { Say 'GitHub' $r.Substring(3) 'Info' }
        elseif ($r -like 'ERR|*') { Say 'GitHub' $r.Substring(4) 'Error' }
        else { Say 'GitHub' 'Нет результата. Запусти push-github.bat и посмотри сообщение.' 'Warning' }
    }
})

$miPush = $menu.Items.Add('Отправить на GitHub (git push)')
$miPush.Add_Click({
    if ($script:pushProc -and -not $script:pushProc.HasExited) { Say 'GitHub' 'Отправка уже идёт.'; return }
    $repo = Get-Repo
    if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) { Say 'GitHub' ('Нет git-репозитория: ' + $repo + '. Выбери папку в меню.') 'Warning'; return }
    Remove-Item -LiteralPath $script:pushOut -Force -ErrorAction SilentlyContinue
    $script:pushProc = Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $self + '" -Push -ResultFile "' + $script:pushOut + '"') -WindowStyle Hidden -PassThru
    Say 'GitHub' 'Отправляю изменения…'
    $script:pushTimer.Start()
})
$miRepo = $menu.Items.Add('Папка репозитория…')
$miRepo.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = 'Папка с git-репозиторием приложения'
    $d.SelectedPath = Get-Repo
    if ($d.ShowDialog() -eq 'OK') {
        Set-Content -LiteralPath $repoFile -Value $d.SelectedPath -Encoding UTF8
        Say 'GitHub' ('Папка репозитория: ' + $d.SelectedPath)
    }
})
$menu.Items.Add('-') | Out-Null
$miExit = $menu.Items.Add('Выход')
$miExit.Add_Click({ $ni.Visible = $false; [System.Windows.Forms.Application]::Exit() })
$ni.ContextMenuStrip = $menu
$ni.Add_MouseClick({ if ($args[1].Button -eq [System.Windows.Forms.MouseButtons]::Left) { Open-App } })
$ni.Add_BalloonTipClicked({ Open-App })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1500
$timer.Add_Tick({
    try {
        $timer.Interval = 20000
        $now = Get-Date
        $script:cfg = Get-Cfg
        $today = @(Get-Plan $now)
        foreach ($a in $today) {
            $age = ($now - $a.Start).TotalMinutes
            $id = $a.Start.ToString('yyyy-MM-dd') + '|' + $a.Key
            if ($age -ge 0 -and $age -lt 10 -and -not $script:done.ContainsKey($id)) {
                $script:done[$id] = 1
                $ni.ShowBalloonTip(8000, $a.Start.ToString('HH:mm') + ' ' + $a.Title, 'Начало по расписанию. Нажми, чтобы открыть приложение.', [System.Windows.Forms.ToolTipIcon]::Info)
            }
        }
        $next = (@($today) + @(Get-Plan ($now.Date.AddDays(1)))) | Where-Object { $_.Start -gt $now } | Select-Object -First 1
        if ($next) {
            $label = 'Дальше: ' + $next.Start.ToString('dd.MM HH:mm') + ' ' + $next.Title
            $miNext.Text = $label
            $ni.Text = $label.Substring(0, [Math]::Min(63, $label.Length))
        } else {
            $miNext.Text = 'Дальше: —'
        }
    } catch { }
})
$timer.Start()
$ni.ShowBalloonTip(5000, 'Тренировки 3/3', 'Трей запущен. Клик по иконке открывает приложение.', [System.Windows.Forms.ToolTipIcon]::Info)
[System.Windows.Forms.Application]::Run()
$timer.Stop()
$ni.Dispose()
$mutex.ReleaseMutex()
