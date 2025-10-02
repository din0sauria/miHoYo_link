[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

Add-Type -AssemblyName System.Web

$ProgressPreference = 'SilentlyContinue'

$game_path = ""

Write-Host "Gacha link acquisition program by dinosaur" -ForegroundColor DarkYellow
Write-Host "抽卡链接为白色字体，若没有显示，请打开游戏查看抽卡记录重试" -ForegroundColor DarkYellow
# 自动寻找版本号最大的文件夹的函数
function Get-LatestVersionFolder {
    param(
        [string]$Path
    )
    
    if (Test-Path $Path) {
        $versionFolders = Get-ChildItem -Path $Path -Directory | Where-Object {
            $_.Name -match '^\d+\.\d+\.\d+\.\d+$'
        } | ForEach-Object {
            $version = $_.Name -split '\.'
            [PSCustomObject]@{
                Folder = $_
                Major = [int]$version[0]
                Minor = [int]$version[1]
                Build = [int]$version[2]
                Revision = [int]$version[3]
            }
        }
        
        if ($versionFolders) {
            $latest = $versionFolders | Sort-Object Major, Minor, Build, Revision -Descending | Select-Object -First 1
            return $latest.Folder.FullName
        }
    }
    return $null
}

if ($args.Length -eq 0) {
    $app_data = [Environment]::GetFolderPath('ApplicationData')
    $locallow_path = "$app_data\..\LocalLow\miHoYo\$([char]0x5d29)$([char]0x574f)$([char]0xff1a)$([char]0x661f)$([char]0x7a79)$([char]0x94c1)$([char]0x9053)\"

    $log_path = "$locallow_path\Player.log"

    if (-Not [IO.File]::Exists($log_path)) {
        Write-Output "Failed to locate log file!"
        Write-Output "Try using the Global client script?"
        return
    }

    $log_line = Get-Content $log_path -Raw

    if ([string]::IsNullOrEmpty($log_line)) {
        $log_path = "$locallow_path\Player-prev.log"

        if (-Not [IO.File]::Exists($log_path)) {
            Write-Output "Failed to locate log file!"
            Write-Output "Try using the Global client script?"
            return
        }

        $log_line = Get-Content $log_path -First 1
    }

    if ([string]::IsNullOrEmpty($log_line)) {
        Write-Output "Failed to locate game path! (1)"
    }

    $game_path = $log_line.Substring($log_line.IndexOf("Loading player data from ") + 25, 300)
    Write-Host "unity3d_path:$game_path"  -ForegroundColor DarkCyan
    $game_path = $game_path.Substring(0, $game_path.IndexOf("/Game/StarRail_Data/data.unity3d") + 39).replace("data.unity3d", "")
    Write-Host "game_path:$game_path" -ForegroundColor DarkCyan
} else {
    $game_path = $args[0]
}

if ([string]::IsNullOrEmpty($game_path)) {
    Write-Output "Failed to locate game path! (2)"
}

$copy_path = [IO.Path]::GetTempFileName()

# 自动获取最新版本的webCaches路径
$webCachesPath = "$game_path/Star Rail Game/StarRail_Data/webCaches"
$latestVersionPath = Get-LatestVersionFolder -Path $webCachesPath

if ($latestVersionPath) {
    $data_path = "$latestVersionPath/Cache/Cache_Data/data_2"
} else {
    # 如果找不到版本文件夹，使用默认路径
    $data_path = "$webCachesPath/2.37.1.0/Cache/Cache_Data/data_2"
    Write-Warning "未能找到最新的版本文件夹，使用默认路径"
}

# 同样处理硬编码的路径
$defaultWebCachesPath = "D:\Program Files\miHoYo Launcher\games\Star Rail Game\StarRail_Data\webCaches"
$latestDefaultVersionPath = Get-LatestVersionFolder -Path $defaultWebCachesPath

if ($latestDefaultVersionPath) {
    $default_data_path = "$latestDefaultVersionPath/Cache/Cache_Data/data_2"
} else {
    $default_data_path = "D:\Program Files\miHoYo Launcher\games\Star Rail Game\StarRail_Data\webCaches\2.43.1.0\Cache\Cache_Data\data_2"
    Write-Warning "未能找到默认路径下的最新版本文件夹，使用默认版本路径"
}

# 使用自动检测到的路径
if (Test-Path $default_data_path) {
    $data_path = $default_data_path
}

Copy-Item -Path $data_path -Destination $copy_path
Write-Host "data:$data_path" -ForegroundColor DarkGreen
Write-Host "copy:$copy_path" -ForegroundColor DarkGreen

$cache_data = Get-Content -Encoding UTF8 -Raw $copy_path
Remove-Item -Path $copy_path

$cache_data_split = $cache_data -split '1/0/'

for ($i = $cache_data_split.Length - 1; $i -ge 0; $i--) {
    $line = $cache_data_split[$i]

    if ($line.StartsWith('http') -and $line.Contains("getGachaLog")) {
        $url = ($line -split "\0")[0]

        $res = Invoke-WebRequest -Uri $url -ContentType "application/json" -UseBasicParsing | ConvertFrom-Json

        if ($res.retcode -eq 0) {
            $uri = [Uri]$url
            $query = [Web.HttpUtility]::ParseQueryString($uri.Query)

            $keys = $query.AllKeys
            foreach ($key in $keys) {
                # Retain required params
                if ($key -eq "authkey") { continue }
                if ($key -eq "authkey_ver") { continue }
                if ($key -eq "sign_type") { continue }
                if ($key -eq "game_biz") { continue }
                if ($key -eq "lang") { continue }
                if ($key -eq "auth_appid") { continue }
                if ($key -eq "size") { continue }

                $query.Remove($key)
            }

            $latest_url = $uri.Scheme + "://" + $uri.Host + $uri.AbsolutePath + "?" + $query.ToString()

            Write-Output $latest_url
            Set-Clipboard -Value $latest_url
			Start-Sleep -Seconds 5
            return;
        }
    }
}