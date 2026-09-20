Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

[System.Windows.Forms.Application]::EnableVisualStyles()

# ============================================================
# TV Video Converter - Multi-profile portable PowerShell GUI
# Designed for Windows PowerShell 5.1 and PS2EXE
# ============================================================

$script:AppName = "TV Video Converter"
$script:AppVersion = "1.1.0"
$script:cancelRequested = $false
$script:currentProcess = $null
$script:files = @()
$script:outputFolder = $null
$script:ffmpeg = $null
$script:ffprobe = $null
$script:downloadUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
$script:ffmpegRoot = Join-Path $env:LOCALAPPDATA "TVVideoConverter\ffmpeg"
$script:ffmpegZip = Join-Path $script:ffmpegRoot "ffmpeg-release-essentials.zip"
$script:userProfilesPath = Join-Path $env:LOCALAPPDATA "TVVideoConverter\user_profiles.json"
$script:userProfiles = [ordered]@{ }

function Load-UserProfiles {
    $script:userProfiles.Clear()
    if (Test-Path -LiteralPath $script:userProfilesPath) {
        try {
            $json = Get-Content -LiteralPath $script:userProfilesPath -Raw | ConvertFrom-Json
            if ($json) {
                foreach ($prop in $json.psobject.properties) {
                    $script:userProfiles[$prop.Name] = @{
                        Width = $prop.Value.Width
                        Height = $prop.Value.Height
                        FPS = $prop.Value.FPS
                        VideoCodec = $prop.Value.VideoCodec
                        Profile = $prop.Value.Profile
                        Level = $prop.Value.Level
                        CRF = $prop.Value.CRF
                        ScaleMode = $prop.Value.ScaleMode
                        AudioCodec = $prop.Value.AudioCodec
                        AudioBitrate = $prop.Value.AudioBitrate
                        SampleRate = $prop.Value.SampleRate
                        Channels = $prop.Value.Channels
                        StripMetadata = [bool]$prop.Value.StripMetadata
                        FastStart = [bool]$prop.Value.FastStart
                        Suffix = $prop.Value.Suffix
                        Description = $prop.Value.Description
                        IsUser = $true
                    }
                }
            }
        } catch { Log "Error cargando perfiles de usuario: $_" }
    } else {
        $script:userProfiles["Ejemplo - Mi perfil"] = @{
            Width=1920; Height=1080; FPS="60"; VideoCodec="H.264 (AVC)"; Profile="High"; Level="4.2"; CRF=18
            ScaleMode="Ajustar + barras"; AudioCodec="AAC"; AudioBitrate="256k"; SampleRate="48000"; Channels="2"
            StripMetadata=$true; FastStart=$true; Suffix="_ejemplo"
            Description="Ejemplo de perfil personalizado (Alta calidad 1080p60). Guardado localmente."
            IsUser=$true
        }
    }
}

function Save-UserProfiles {
    $dir = Split-Path $script:userProfilesPath -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    
    $obj = New-Object PSObject
    foreach ($k in $script:userProfiles.Keys) {
        $obj | Add-Member -MemberType NoteProperty -Name $k -Value $script:userProfiles[$k]
    }
    $obj | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:userProfilesPath -Encoding UTF8
}

function Get-AppDirectory {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($ScriptRoot) { return $ScriptRoot }
    return (Get-Location).Path
}

function Find-FFmpeg {
    $candidates = @(
        (Join-Path (Get-AppDirectory) "ffmpeg\bin\ffmpeg.exe"),
        (Join-Path (Get-AppDirectory) "bin\ffmpeg.exe"),
        (Join-Path (Get-AppDirectory) "ffmpeg.exe"),
        "D:\ffmpeg-2026-09-17-git-7070fe638e-essentials_build\bin\ffmpeg.exe",
        (Join-Path $script:ffmpegRoot "current\bin\ffmpeg.exe")
    )

    foreach ($path in $candidates) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }

    $cmd = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    return $null
}

function Set-FFmpegTools {
    $script:ffmpeg = Find-FFmpeg

    if ($script:ffmpeg) {
        $probeCandidate = Join-Path (Split-Path -Parent $script:ffmpeg) "ffprobe.exe"
        if (Test-Path -LiteralPath $probeCandidate) {
            $script:ffprobe = $probeCandidate
        } else {
            $script:ffprobe = $null
        }
    } else {
        $script:ffprobe = $null
    }
}

function Quote-ProcessArg([string]$Value) {
    if ($null -eq $Value) { return '""' }
    return '"' + $Value.Replace('"','\"') + '"'
}

function Join-ProcessArguments([string[]]$ArgList) {
    return (($ArgList | ForEach-Object { Quote-ProcessArg $_ }) -join " ")
}

function Log($Text) {
    if (-not $log) { return }
    $log.AppendText("[$(Get-Date -Format 'HH:mm:ss')] $Text`r`n")
    $log.SelectionStart = $log.TextLength
    $log.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Show-Info([string]$Message) {
    [System.Windows.Forms.MessageBox]::Show(
        $form, $Message, $script:AppName,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Show-Error([string]$Message) {
    [System.Windows.Forms.MessageBox]::Show(
        $form, $Message, $script:AppName,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

function Find-DownloadedFFmpeg {
    if (-not (Test-Path -LiteralPath $script:ffmpegRoot)) { return $null }
    $found = Get-ChildItem -LiteralPath $script:ffmpegRoot -Filter "ffmpeg.exe" -File -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

function Download-FFmpeg {
    New-Item -ItemType Directory -Path $script:ffmpegRoot -Force | Out-Null

    $existing = Find-DownloadedFFmpeg
    if ($existing) {
        $script:ffmpeg = $existing
        $probe = Join-Path (Split-Path -Parent $existing) "ffprobe.exe"
        if (Test-Path -LiteralPath $probe) { $script:ffprobe = $probe }
        return $true
    }

    $notice = @"
No se encontrÃ³ FFmpeg en este equipo.

Se descargarÃ¡n automÃ¡ticamente las librerÃ­as/binaries necesarios desde:
$script:downloadUrl

La descarga es necesaria para realizar las conversiones y requiere conexiÃ³n a Internet.
"@
    $result = [System.Windows.Forms.MessageBox]::Show(
        $form,
        $notice,
        "$script:AppName - FFmpeg requerido",
        [System.Windows.Forms.MessageBoxButtons]::OKCancel,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )

    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        Log "El usuario cancelÃ³ la descarga de FFmpeg."
        return $false
    }

    $btnSelect.Enabled = $false
    $btnOutput.Enabled = $false
    $btnConvert.Enabled = $false
    $btnFFmpeg.Enabled = $false
    $btnCancel.Enabled = $false
    $progress.Style = "Continuous"
    $progress.Value = 0
    $lblProgress.Text = "Descargando librerÃ­as de FFmpeg..."

    try {
        $tmpZip = $script:ffmpegZip
        if (Test-Path -LiteralPath $tmpZip) {
            Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue
        }

        Log "Descargando FFmpeg..."
        $wc = New-Object System.Net.WebClient

        $downloadEvent = {
            param($sender, $e)
            $value = [Math]::Max(0, [Math]::Min(100, $e.ProgressPercentage))
            $progress.Value = $value
            $lblProgress.Text = "Descargando librerÃ­as de FFmpeg... $value%"
            [System.Windows.Forms.Application]::DoEvents()
        }
        Register-ObjectEvent -InputObject $wc -EventName DownloadProgressChanged -SourceIdentifier "FFmpegDownloadProgress" -Action $downloadEvent | Out-Null

        $wc.DownloadFileAsync([Uri]$script:downloadUrl, $tmpZip)

        while ($wc.IsBusy) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }

        Unregister-Event -SourceIdentifier "FFmpegDownloadProgress" -ErrorAction SilentlyContinue
        Remove-Job -Name "FFmpegDownloadProgress" -Force -ErrorAction SilentlyContinue

        if (-not (Test-Path -LiteralPath $tmpZip)) {
            throw "No se obtuvo el archivo de FFmpeg."
        }

        $extractRoot = Join-Path $script:ffmpegRoot "current"
        if (Test-Path -LiteralPath $extractRoot) {
            Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null

        $lblProgress.Text = "Extrayendo librerÃ­as de FFmpeg..."
        $progress.Style = "Marquee"
        [System.Windows.Forms.Application]::DoEvents()

        Expand-Archive -LiteralPath $tmpZip -DestinationPath $extractRoot -Force

        $downloaded = Get-ChildItem -LiteralPath $extractRoot -Filter "ffmpeg.exe" -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if (-not $downloaded) {
            throw "El paquete descargado no contiene ffmpeg.exe."
        }

        $script:ffmpeg = $downloaded.FullName
        $probe = Join-Path (Split-Path -Parent $script:ffmpeg) "ffprobe.exe"
        if (Test-Path -LiteralPath $probe) {
            $script:ffprobe = $probe
        }

        try { Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue } catch {}

        $progress.Style = "Continuous"
        $progress.Value = 100
        $lblProgress.Text = "FFmpeg listo."
        Log "FFmpeg descargado y preparado en: $script:ffmpeg"
        return $true
    }
    catch {
        $progress.Style = "Continuous"
        $progress.Value = 0
        $lblProgress.Text = "No se pudo descargar FFmpeg."
        Log "Error descargando FFmpeg: $($_.Exception.Message)"
        Show-Error "No se pudo descargar FFmpeg.`r`n`r`n$($_.Exception.Message)`r`n`r`nComprueba tu conexiÃ³n a Internet e intÃ©ntalo nuevamente."
        return $false
    }
    finally {
        $btnSelect.Enabled = $true
        $btnOutput.Enabled = $true
        $btnFFmpeg.Enabled = $true
        $btnCancel.Enabled = $false
    }
}

function Get-VideoDuration([string]$InputFile) {
    if (-not $script:ffprobe -or -not (Test-Path -LiteralPath $script:ffprobe)) {
        return 0.0
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:ffprobe
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $args = @("-v","error","-show_entries","format=duration","-of","default=nw=1:nk=1",$InputFile)
    $psi.Arguments = Join-ProcessArguments $args

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    try {
        [void]$p.Start()
        $out = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()
        $seconds = 0.0
        if ([double]::TryParse($out.Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$seconds)) {
            return $seconds
        }
    } catch {}
    finally { $p.Dispose() }
    return 0.0
}

function Get-Profile([string]$Name) {
    if ($script:profiles.Contains($Name)) { return $script:profiles[$Name] }
    if ($script:userProfiles.Contains($Name)) { return $script:userProfiles[$Name] }
    return $null
}

function Get-SelectedProfile {
    $name = [string]$profileCombo.SelectedItem
    return Get-Profile $name
}

function Apply-Profile([string]$Name) {
    $p = Get-Profile $Name
    if (-not $p) { return }

    $txtWidth.Text = [string]$p.Width
    $txtHeight.Text = [string]$p.Height
    $fpsCombo.SelectedItem = [string]$p.FPS
    $codecCombo.SelectedItem = [string]$p.VideoCodec
    $videoProfileCombo.SelectedItem = [string]$p.Profile
    $levelCombo.SelectedItem = [string]$p.Level
    $crfNumeric.Value = [decimal]$p.CRF
    $scaleCombo.SelectedItem = [string]$p.ScaleMode
    $audioCombo.SelectedItem = [string]$p.AudioCodec
    $audioBitrateCombo.SelectedItem = [string]$p.AudioBitrate
    $sampleCombo.SelectedItem = [string]$p.SampleRate
    $channelsCombo.SelectedItem = [string]$p.Channels
    $metadataCheck.Checked = [bool]$p.StripMetadata
    $fastStartCheck.Checked = [bool]$p.FastStart
    $suffixText.Text = [string]$p.Suffix
    $lblProfileInfo.Text = [string]$p.Description
    if ($p.Ext) {
        if ($extCombo.Items.Contains([string]$p.Ext)) { $extCombo.SelectedItem = [string]$p.Ext }
    } else {
        $extCombo.SelectedItem = ".mp4"
    }
}

function Validate-Settings {
    $w = 0; $h = 0
    if (-not [int]::TryParse($txtWidth.Text.Trim(), [ref]$w) -or $w -lt 16) {
        Show-Error "La anchura debe ser un nÃºmero vÃ¡lido mayor o igual a 16."
        return $false
    }
    if (-not [int]::TryParse($txtHeight.Text.Trim(), [ref]$h) -or $h -lt 16) {
        Show-Error "La altura debe ser un nÃºmero vÃ¡lido mayor o igual a 16."
        return $false
    }
    if (($w % 2) -ne 0 -or ($h % 2) -ne 0) {
        Show-Error "La anchura y altura deben ser nÃºmeros pares para asegurar compatibilidad con H.264/H.265."
        return $false
    }
    return $true
}

function Get-OutputFile([string]$InputFile) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
    $folder = if ($script:outputFolder) { $script:outputFolder } else { [System.IO.Path]::GetDirectoryName($InputFile) }
    $suffix = $suffixText.Text
    $ext = ".mp4"
    if ($extCombo.SelectedItem) { $ext = [string]$extCombo.SelectedItem }
    
    $candidate = Join-Path $folder ($base + $suffix + $ext)

    if ($overwriteCheck.Checked) { return $candidate }

    if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }

    $n = 2
    do {
        $candidate = Join-Path $folder ($base + $suffix + "_" + $n + $ext)
        $n++
    } while (Test-Path -LiteralPath $candidate)

    return $candidate
}

function Build-FFmpegArguments([string]$InputFile, [string]$OutputFile) {
    $width = [int]$txtWidth.Text
    $height = [int]$txtHeight.Text
    $fps = [string]$fpsCombo.SelectedItem
    $codec = [string]$codecCombo.SelectedItem
    $vProfile = [string]$videoProfileCombo.SelectedItem
    $level = [string]$levelCombo.SelectedItem
    $crf = [int]$crfNumeric.Value
    $scaleMode = [string]$scaleCombo.SelectedItem
    $audioCodec = [string]$audioCombo.SelectedItem
    $audioBitrate = [string]$audioBitrateCombo.SelectedItem
    $sampleRate = [string]$sampleCombo.SelectedItem
    $channels = [string]$channelsCombo.SelectedItem

    $args = @("-y","-hide_banner","-i",$InputFile)
    
    if ($codec -ne "Copy" -and $codec -ne "Sin video" -and $audioCodec -ne "Copy" -and $audioCodec -ne "Sin audio") {
        $args += @("-map","0:v:0","-map","0:a?")
    } else {
        $args += @("-map","0")
    }
    
    if ($codec -ne "Sin video") {
        if ($codec -ne "Copy") {
            if ($scaleMode -eq "Original") {
                $args += @("-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2")
            }
            elseif ($scaleMode -eq "Fill / recortar") {
                $filter = ("scale={0}:{1}:force_original_aspect_ratio=increase,crop={0}:{1}" -f $width, $height)
                $args += @("-vf", $filter)
            }
            elseif ($scaleMode -eq "Estirar") {
                $filter = ("scale={0}:{1}" -f $width, $height)
                $args += @("-vf", $filter)
            }
            else {
                $filter = ("scale={0}:{1}:force_original_aspect_ratio=decrease,pad={0}:{1}:(ow-iw)/2:(oh-ih)/2" -f $width, $height)
                $args += @("-vf", $filter)
            }
        }

        switch ($codec) {
            "H.264 (AVC)" {
                $args += @("-c:v","libx264","-preset","medium","-crf",$crf.ToString(),"-pix_fmt","yuv420p")
                if ($vProfile -and $vProfile -ne "Auto") { $args += @("-profile:v",$vProfile) }
                if ($level -and $level -ne "Auto") { $args += @("-level:v",$level) }
            }
            "H.265 (HEVC)" {
                $args += @("-c:v","libx265","-preset","medium","-crf",$crf.ToString(),"-pix_fmt","yuv420p")
                if ($vProfile -eq "Main") { $args += @("-profile:v","main") }
                if ($level -and $level -ne "Auto") { $args += @("-level:v",$level) }
            }
            "MPEG-2" {
                $args += @("-c:v","mpeg2video","-b:v","5000k","-maxrate","7000k","-bufsize","1835008")
            }
            "VP9" {
                $args += @("-c:v","libvpx-vp9","-crf",$crf.ToString(),"-b:v","0")
            }
            "Xvid" {
                $args += @("-c:v","mpeg4","-vtag","XVID","-q:v","5")
            }
            "MPEG-4 Part 2" {
                $args += @("-c:v","mpeg4","-q:v",[Math]::Max(2, [Math]::Min(10, [int]([Math]::Round($crf / 5)))))
            }
            "Copy" {
                $args += @("-c:v","copy")
            }
        }
        
        if ($fps -and $fps -ne "Original" -and $codec -ne "Copy") {
            $args += @("-r",$fps)
        }
    } else {
        $args += @("-vn")
    }

    if ($audioCodec -eq "AAC") {
        $args += @("-c:a","aac","-b:a",$audioBitrate,"-ar",$sampleRate,"-ac",$channels)
    }
    elseif ($audioCodec -eq "MP3") {
        $args += @("-c:a","libmp3lame","-b:a",$audioBitrate,"-ar",$sampleRate,"-ac",$channels)
    }
    elseif ($audioCodec -eq "MP2") {
        $args += @("-c:a","mp2","-b:a",$audioBitrate,"-ar",$sampleRate,"-ac",$channels)
    }
    elseif ($audioCodec -eq "Opus") {
        $args += @("-c:a","libopus","-b:a",$audioBitrate,"-ar",$sampleRate)
    }
    elseif ($audioCodec -eq "PCM (WAV)") {
        $args += @("-c:a","pcm_s16le","-ar",$sampleRate,"-ac",$channels)
    }
    elseif ($audioCodec -eq "Copy") {
        $args += @("-c:a","copy")
    }
    else {
        $args += @("-an")
    }

    if ($metadataCheck.Checked) {
        $args += @("-map_metadata","-1","-map_chapters","-1")
    }

    if ($fastStartCheck.Checked) {
        $args += @("-movflags","+faststart")
    }

    if ($codec -ne "Copy" -and $audioCodec -ne "Copy") {
        $args += @("-sn","-dn")
    }
    
    $args += @("-progress","pipe:2","-nostats","-max_muxing_queue_size","1024",$OutputFile)
    return $args
}

function Update-ProfileStatus {
    $p = Get-SelectedProfile
    if ($null -ne $p) {
        $lblProfileInfo.Text = $p.Description
        
        $isUser = ($null -ne $p.IsUser -and $p.IsUser)
        if ($null -ne $btnDeleteProfile) {
            $btnDeleteProfile.Enabled = $isUser
        }
    }
}

function Reload-ProfileCombo {
    $current = $profileCombo.SelectedItem
    $profileCombo.Items.Clear()
    foreach ($k in $script:profiles.Keys) { [void]$profileCombo.Items.Add($k) }
    foreach ($k in $script:userProfiles.Keys) { [void]$profileCombo.Items.Add($k) }
    
    if ($current -and $profileCombo.Items.Contains($current)) {
        $profileCombo.SelectedItem = $current
    } else {
        $profileCombo.SelectedIndex = 0
    }
}

# -------------------- Profiles --------------------
$script:profiles = [ordered]@{
    "1. TV vieja (COMPATIBLE - PREDETERMINADO)" = @{
        Width=1280; Height=720; FPS="30"; VideoCodec="H.264 (AVC)"; Profile="Baseline"; Level="3.1"; CRF=22
        ScaleMode="Ajustar + barras"; AudioCodec="AAC"; AudioBitrate="128k"; SampleRate="44100"; Channels="2"
        StripMetadata=$true; FastStart=$true; Suffix="_TV"; Ext=".mp4"
        Description="Perfil de maxima compatibilidad para TVs antiguas: H.264 Baseline, AAC, 720p 30fps."
    }
    "2. Smart TV 1080p" = @{
        Width=1920; Height=1080; FPS="30"; VideoCodec="H.264 (AVC)"; Profile="High"; Level="4.1"; CRF=20
        ScaleMode="Ajustar + barras"; AudioCodec="AAC"; AudioBitrate="192k"; SampleRate="48000"; Channels="2"
        StripMetadata=$true; FastStart=$true; Suffix="_SmartTV"; Ext=".mp4"
        Description="Para Smart TVs modernas: 1080p a 30fps, alta calidad."
    }
    "3. Smart TV 1080p 60 FPS" = @{
        Width=1920; Height=1080; FPS="60"; VideoCodec="H.264 (AVC)"; Profile="High"; Level="4.2"; CRF=20
        ScaleMode="Ajustar + barras"; AudioCodec="AAC"; AudioBitrate="192k"; SampleRate="48000"; Channels="2"
        StripMetadata=$true; FastStart=$true; Suffix="_1080p60"; Ext=".mp4"
        Description="Para Smart TVs que soportan 60 FPS: 1080p a 60fps."
    }
    "4. TV muy antigua 480p" = @{
        Width=720; Height=480; FPS="30"; VideoCodec="H.264 (AVC)"; Profile="Baseline"; Level="3.0"; CRF=23
        ScaleMode="Ajustar + barras"; AudioCodec="AAC"; AudioBitrate="96k"; SampleRate="44100"; Channels="2"
        StripMetadata=$true; FastStart=$false; Suffix="_480p"; Ext=".mp4"
        Description="Resolucion SD 480p para reproductores USB muy antiguos."
    }
    "5. Android / Celular" = @{
        Width=1920; Height=1080; FPS="30"; VideoCodec="H.264 (AVC)"; Profile="High"; Level="4.1"; CRF=21
        ScaleMode="Ajustar + barras"; AudioCodec="AAC"; AudioBitrate="160k"; SampleRate="48000"; Channels="2"
        StripMetadata=$true; FastStart=$true; Suffix="_Android"; Ext=".mp4"
        Description="Reproduccion amplia en dispositivos Android."
    }
    "6. iPhone / iPad" = @{
        Width=1920; Height=1080; FPS="30"; VideoCodec="H.264 (AVC)"; Profile="High"; Level="4.1"; CRF=20
        ScaleMode="Ajustar + barras"; AudioCodec="AAC"; AudioBitrate="160k"; SampleRate="48000"; Channels="2"
        StripMetadata=$true; FastStart=$true; Suffix="_iPhone"; Ext=".mp4"
        Description="Optimizado para dispositivos Apple (iOS/iPadOS)."
    }
    "7. WhatsApp / Mensajeria" = @{
        Width=1280; Height=720; FPS="30"; VideoCodec="H.264 (AVC)"; Profile="Baseline"; Level="3.1"; CRF=23
        ScaleMode="Ajustar + barras"; AudioCodec="AAC"; AudioBitrate="96k"; SampleRate="44100"; Channels="2"
        StripMetadata=$true; FastStart=$true; Suffix="_WhatsApp"; Ext=".mp4"
        Description="Archivo ligero en 720p ideal para enviar por redes de mensajeria."
    }
    "8. Redes sociales - Vertical" = @{
        Width=1080; Height=1920; FPS="30"; VideoCodec="H.264 (AVC)"; Profile="High"; Level="4.1"; CRF=21
        ScaleMode="Ajustar + barras"; AudioCodec="AAC"; AudioBitrate="128k"; SampleRate="48000"; Channels="2"
        StripMetadata=$true; FastStart=$true; Suffix="_vertical"; Ext=".mp4"
        Description="Formato vertical 1080x1920 para TikTok, Reels, Shorts."
    }
    "9. Web / HTML5" = @{
        Width=1920; Height=1080; FPS="30"; VideoCodec="H.264 (AVC)"; Profile="High"; Level="4.1"; CRF=22
        ScaleMode="Ajustar + barras"; AudioCodec="AAC"; AudioBitrate="128k"; SampleRate="48000"; Channels="2"
        StripMetadata=$true; FastStart=$true; Suffix="_Web"; Ext=".mp4"
        Description="Video MP4 web optimizado con faststart (inicio rapido)."
    }
    "10. Consolas" = @{
        Width=1920; Height=1080; FPS="30"; VideoCodec="H.264 (AVC)"; Profile="High"; Level="4.1"; CRF=20
        ScaleMode="Ajustar + barras"; AudioCodec="AAC"; AudioBitrate="192k"; SampleRate="48000"; Channels="2"
        StripMetadata=$true; FastStart=$false; Suffix="_Consola"; Ext=".mp4"
        Description="Formato H.264 High para Xbox, PlayStation, etc."
    }
    "11. DVD / MPEG-2" = @{
        Width=720; Height=480; FPS="30"; VideoCodec="MPEG-2"; Profile="Auto"; Level="Auto"; CRF=0
        ScaleMode="Estirar"; AudioCodec="MP2"; AudioBitrate="192k"; SampleRate="48000"; Channels="2"
        StripMetadata=$true; FastStart=$false; Suffix="_DVD"; Ext=".mpg"
        Description="Video MPEG-2 compatible con reproductores de DVD antiguos."
    }
    "12. AVI / Xvid - equipos antiguos" = @{
        Width=720; Height=480; FPS="30"; VideoCodec="Xvid"; Profile="Auto"; Level="Auto"; CRF=0
        ScaleMode="Ajustar + barras"; AudioCodec="MP3"; AudioBitrate="128k"; SampleRate="44100"; Channels="2"
        StripMetadata=$true; FastStart=$false; Suffix="_XVID"; Ext=".avi"
        Description="Formato AVI Xvid para maxima retrocompatibilidad."
    }
    "13. HEVC / H.265" = @{
        Width=1920; Height=1080; FPS="30"; VideoCodec="H.265 (HEVC)"; Profile="Main"; Level="4.1"; CRF=24
        ScaleMode="Ajustar + barras"; AudioCodec="AAC"; AudioBitrate="160k"; SampleRate="48000"; Channels="2"
        StripMetadata=$true; FastStart=$true; Suffix="_HEVC"; Ext=".mp4"
        Description="Codificacion moderna H.265 para archivos muy pequenos y alta calidad."
    }
    "14. WebM / VP9" = @{
        Width=1920; Height=1080; FPS="30"; VideoCodec="VP9"; Profile="Auto"; Level="Auto"; CRF=30
        ScaleMode="Ajustar + barras"; AudioCodec="Opus"; AudioBitrate="128k"; SampleRate="48000"; Channels="2"
        StripMetadata=$true; FastStart=$false; Suffix="_WebM"; Ext=".webm"
        Description="Formato libre VP9 + Opus ideal para navegadores web."
    }
    "15. Extraer audio MP3" = @{
        Width=1920; Height=1080; FPS="Original"; VideoCodec="Sin video"; Profile="Auto"; Level="Auto"; CRF=0
        ScaleMode="Original"; AudioCodec="MP3"; AudioBitrate="192k"; SampleRate="44100"; Channels="2"
        StripMetadata=$true; FastStart=$false; Suffix=""; Ext=".mp3"
        Description="Extrae y codifica solo la pista de audio a MP3."
    }
    "16. Extraer audio M4A / AAC" = @{
        Width=1920; Height=1080; FPS="Original"; VideoCodec="Sin video"; Profile="Auto"; Level="Auto"; CRF=0
        ScaleMode="Original"; AudioCodec="AAC"; AudioBitrate="256k"; SampleRate="48000"; Channels="2"
        StripMetadata=$true; FastStart=$false; Suffix=""; Ext=".m4a"
        Description="Extrae y codifica solo la pista de audio a formato M4A (AAC de alta calidad)."
    }
    "17. Extraer audio WAV" = @{
        Width=1920; Height=1080; FPS="Original"; VideoCodec="Sin video"; Profile="Auto"; Level="Auto"; CRF=0
        ScaleMode="Original"; AudioCodec="PCM (WAV)"; AudioBitrate="320k"; SampleRate="48000"; Channels="2"
        StripMetadata=$true; FastStart=$false; Suffix=""; Ext=".wav"
        Description="Extrae el audio a formato WAV sin compresion."
    }
    "18. MOV -> MP4 sin recodificar" = @{
        Width=1920; Height=1080; FPS="Original"; VideoCodec="Copy"; Profile="Auto"; Level="Auto"; CRF=0
        ScaleMode="Original"; AudioCodec="Copy"; AudioBitrate="192k"; SampleRate="48000"; Channels="2"
        StripMetadata=$false; FastStart=$true; Suffix=""; Ext=".mp4"
        Description="Solo cambia el contenedor a MP4 copiando las pistas exactas (muy rapido)."
    }
    "19. MKV -> MP4 sin recodificar" = @{
        Width=1920; Height=1080; FPS="Original"; VideoCodec="Copy"; Profile="Auto"; Level="Auto"; CRF=0
        ScaleMode="Original"; AudioCodec="Copy"; AudioBitrate="192k"; SampleRate="48000"; Channels="2"
        StripMetadata=$false; FastStart=$true; Suffix=""; Ext=".mp4"
        Description="Remultiplexa de MKV a MP4 sin perder calidad ni tiempo."
    }
    "20. MP4 -> MKV sin recodificar" = @{
        Width=1920; Height=1080; FPS="Original"; VideoCodec="Copy"; Profile="Auto"; Level="Auto"; CRF=0
        ScaleMode="Original"; AudioCodec="Copy"; AudioBitrate="192k"; SampleRate="48000"; Channels="2"
        StripMetadata=$false; FastStart=$false; Suffix=""; Ext=".mkv"
        Description="Remultiplexa de MP4 a MKV sin perder calidad ni tiempo."
    }
}

# -------------------- GUI --------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "$script:AppName $script:AppVersion"
$form.Size = New-Object System.Drawing.Size(1000, 820)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(940, 760)
$form.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)

$title = New-Object System.Windows.Forms.Label
$title.Text = $script:AppName
$title.Font = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(24, 16)
$title.AutoSize = $true
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "Conversor portÃ¡til con perfiles para TV, mÃ³viles, web y reproductores antiguos"
$subtitle.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$subtitle.ForeColor = [System.Drawing.Color]::DimGray
$subtitle.Location = New-Object System.Drawing.Point(27, 57)
$subtitle.AutoSize = $true
$form.Controls.Add($subtitle)

$status = New-Object System.Windows.Forms.Label
$status.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$status.Location = New-Object System.Drawing.Point(28, 84)
$status.AutoSize = $true
$form.Controls.Add($status)

$btnSelect = New-Object System.Windows.Forms.Button
$btnSelect.Text = "Seleccionar videos"
$btnSelect.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnSelect.Size = New-Object System.Drawing.Size(165, 40)
$btnSelect.Location = New-Object System.Drawing.Point(24, 112)
$form.Controls.Add($btnSelect)

$btnOutput = New-Object System.Windows.Forms.Button
$btnOutput.Text = "Carpeta de salida"
$btnOutput.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$btnOutput.Size = New-Object System.Drawing.Size(155, 40)
$btnOutput.Location = New-Object System.Drawing.Point(199, 112)
$form.Controls.Add($btnOutput)

$btnConvert = New-Object System.Windows.Forms.Button
$btnConvert.Text = "CONVERTIR"
$btnConvert.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnConvert.Size = New-Object System.Drawing.Size(145, 40)
$btnConvert.Location = New-Object System.Drawing.Point(364, 112)
$btnConvert.Enabled = $false
$form.Controls.Add($btnConvert)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Cancelar"
$btnCancel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$btnCancel.Size = New-Object System.Drawing.Size(110, 40)
$btnCancel.Location = New-Object System.Drawing.Point(519, 112)
$btnCancel.Enabled = $false
$form.Controls.Add($btnCancel)

$btnFFmpeg = New-Object System.Windows.Forms.Button
$btnFFmpeg.Text = "FFmpeg"
$btnFFmpeg.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$btnFFmpeg.Size = New-Object System.Drawing.Size(110, 40)
$btnFFmpeg.Location = New-Object System.Drawing.Point(639, 112)
$form.Controls.Add($btnFFmpeg)

$lblOutput = New-Object System.Windows.Forms.Label
$lblOutput.Text = "Salida: misma carpeta que cada video"
$lblOutput.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblOutput.Location = New-Object System.Drawing.Point(27, 160)
$lblOutput.Size = New-Object System.Drawing.Size(900, 24)
$form.Controls.Add($lblOutput)

$profileGroup = New-Object System.Windows.Forms.GroupBox
$profileGroup.Text = "Perfil"
$profileGroup.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$profileGroup.Location = New-Object System.Drawing.Point(24, 190)
$profileGroup.Size = New-Object System.Drawing.Size(930, 105)
$form.Controls.Add($profileGroup)

$profileCombo = New-Object System.Windows.Forms.ComboBox
$profileCombo.DropDownStyle = "DropDownList"
$profileCombo.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$profileCombo.Location = New-Object System.Drawing.Point(18, 30)
$profileCombo.Size = New-Object System.Drawing.Size(360, 28)
$profileGroup.Controls.Add($profileCombo)

$lblProfileInfo = New-Object System.Windows.Forms.Label
$lblProfileInfo.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblProfileInfo.ForeColor = [System.Drawing.Color]::DimGray
$lblProfileInfo.Location = New-Object System.Drawing.Point(390, 27)
$lblProfileInfo.Size = New-Object System.Drawing.Size(300, 70)
$profileGroup.Controls.Add($lblProfileInfo)

$txtNewProfile = New-Object System.Windows.Forms.TextBox
$txtNewProfile.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$txtNewProfile.Location = New-Object System.Drawing.Point(700, 25)
$txtNewProfile.Size = New-Object System.Drawing.Size(210, 25)
$txtNewProfile.Text = "Mi nuevo perfil"
$profileGroup.Controls.Add($txtNewProfile)

$btnSaveProfile = New-Object System.Windows.Forms.Button
$btnSaveProfile.Text = "Guardar actual"
$btnSaveProfile.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$btnSaveProfile.Location = New-Object System.Drawing.Point(700, 55)
$btnSaveProfile.Size = New-Object System.Drawing.Size(100, 30)
$profileGroup.Controls.Add($btnSaveProfile)

$btnDeleteProfile = New-Object System.Windows.Forms.Button
$btnDeleteProfile.Text = "Eliminar"
$btnDeleteProfile.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$btnDeleteProfile.Location = New-Object System.Drawing.Point(810, 55)
$btnDeleteProfile.Size = New-Object System.Drawing.Size(100, 30)
$btnDeleteProfile.Enabled = $false
$profileGroup.Controls.Add($btnDeleteProfile)

$settingsGroup = New-Object System.Windows.Forms.GroupBox
$settingsGroup.Text = "PersonalizaciÃ³n"
$settingsGroup.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$settingsGroup.Location = New-Object System.Drawing.Point(24, 310)
$settingsGroup.Size = New-Object System.Drawing.Size(930, 190)
$form.Controls.Add($settingsGroup)

function New-SettingLabel($text,$x,$y) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x,$y)
    $l.Size = New-Object System.Drawing.Size(90,24)
    $settingsGroup.Controls.Add($l)
}
function New-Combo($x,$y,$w,$items) {
    $c = New-Object System.Windows.Forms.ComboBox
    $c.DropDownStyle = "DropDownList"
    $c.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $c.Location = New-Object System.Drawing.Point($x,$y)
    $c.Size = New-Object System.Drawing.Size($w,25)
    foreach ($i in $items) { [void]$c.Items.Add($i) }
    $settingsGroup.Controls.Add($c)
    return $c
}

New-SettingLabel "Ancho" 18 30
$txtWidth = New-Object System.Windows.Forms.TextBox
$txtWidth.Location = New-Object System.Drawing.Point(18,55)
$txtWidth.Size = New-Object System.Drawing.Size(75,25)
$settingsGroup.Controls.Add($txtWidth)

New-SettingLabel "Alto" 105 30
$txtHeight = New-Object System.Windows.Forms.TextBox
$txtHeight.Location = New-Object System.Drawing.Point(105,55)
$txtHeight.Size = New-Object System.Drawing.Size(75,25)
$settingsGroup.Controls.Add($txtHeight)

New-SettingLabel "FPS" 192 30
$fpsCombo = New-Combo 192 55 80 @("Original","24","25","30","50","60")

New-SettingLabel "Video" 285 30
$codecCombo = New-Combo 285 55 125 @("H.264 (AVC)","H.265 (HEVC)","MPEG-2","VP9","Xvid","MPEG-4 Part 2","Copy","Sin video")

New-SettingLabel "Perfil" 423 30
$videoProfileCombo = New-Combo 423 55 105 @("Auto","Baseline","Main","High")

New-SettingLabel "Level" 541 30
$levelCombo = New-Combo 541 55 75 @("Auto","3.0","3.1","4.0","4.1","4.2","5.0","5.1")

New-SettingLabel "CRF" 629 30
$crfNumeric = New-Object System.Windows.Forms.NumericUpDown
$crfNumeric.Minimum = 0
$crfNumeric.Maximum = 51
$crfNumeric.Value = 22
$crfNumeric.Location = New-Object System.Drawing.Point(629,55)
$crfNumeric.Size = New-Object System.Drawing.Size(60,25)
$settingsGroup.Controls.Add($crfNumeric)

New-SettingLabel "Escalado" 702 30
$scaleCombo = New-Combo 702 55 205 @("Ajustar + barras","Fill / recortar","Estirar","Original")

New-SettingLabel "Audio" 18 95
$audioCombo = New-Combo 18 120 90 @("AAC","MP3","MP2","Opus","PCM (WAV)","Copy","Sin audio")

New-SettingLabel "Bitrate" 120 95
$audioBitrateCombo = New-Combo 120 120 80 @("96k","128k","160k","192k","256k","320k")

New-SettingLabel "Muestra" 212 95
$sampleCombo = New-Combo 212 120 80 @("44100","48000")

New-SettingLabel "Canales" 304 95
$channelsCombo = New-Combo 304 120 60 @("1","2")

$metadataCheck = New-Object System.Windows.Forms.CheckBox
$metadataCheck.Text = "Quitar metadatos"
$metadataCheck.Location = New-Object System.Drawing.Point(385,120)
$metadataCheck.Size = New-Object System.Drawing.Size(130,25)
$metadataCheck.Checked = $true
$settingsGroup.Controls.Add($metadataCheck)

$fastStartCheck = New-Object System.Windows.Forms.CheckBox
$fastStartCheck.Text = "FastStart"
$fastStartCheck.Location = New-Object System.Drawing.Point(525,120)
$fastStartCheck.Size = New-Object System.Drawing.Size(90,25)
$fastStartCheck.Checked = $true
$settingsGroup.Controls.Add($fastStartCheck)

$overwriteCheck = New-Object System.Windows.Forms.CheckBox
$overwriteCheck.Text = "Sobrescribir"
$overwriteCheck.Location = New-Object System.Drawing.Point(625,120)
$overwriteCheck.Size = New-Object System.Drawing.Size(100,25)
$settingsGroup.Controls.Add($overwriteCheck)

$restoreBtn = New-Object System.Windows.Forms.Button
$restoreBtn.Text = "Restaurar perfil"
$restoreBtn.Location = New-Object System.Drawing.Point(735,116)
$restoreBtn.Size = New-Object System.Drawing.Size(120,30)
$settingsGroup.Controls.Add($restoreBtn)

$suffixText = New-Object System.Windows.Forms.TextBox
$suffixText.Location = New-Object System.Drawing.Point(18,155)
$suffixText.Size = New-Object System.Drawing.Size(140,25)
$settingsGroup.Controls.Add($suffixText)

$suffixLabel = New-Object System.Windows.Forms.Label
$suffixLabel.Text = "Sufijo de salida"
$suffixLabel.Location = New-Object System.Drawing.Point(165,155)
$suffixLabel.Size = New-Object System.Drawing.Size(100,24)
$settingsGroup.Controls.Add($suffixLabel)

New-SettingLabel "Formato" 275 130
$extCombo = New-Combo 275 155 80 @(".mp4",".mkv",".webm",".avi",".mpg",".mp3",".m4a",".wav")

$filesGroup = New-Object System.Windows.Forms.GroupBox
$filesGroup.Text = "Videos seleccionados"
$filesGroup.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$filesGroup.Location = New-Object System.Drawing.Point(24, 510)
$filesGroup.Size = New-Object System.Drawing.Size(600, 115)
$form.Controls.Add($filesGroup)

$list = New-Object System.Windows.Forms.ListBox
$list.Location = New-Object System.Drawing.Point(15, 28)
$list.Size = New-Object System.Drawing.Size(570, 73)
$list.HorizontalScrollbar = $true
$filesGroup.Controls.Add($list)

$userProfilesGroup = New-Object System.Windows.Forms.GroupBox
$userProfilesGroup.Text = "Mis Perfiles Guardados"
$userProfilesGroup.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$userProfilesGroup.Location = New-Object System.Drawing.Point(634, 510)
$userProfilesGroup.Size = New-Object System.Drawing.Size(320, 115)
$form.Controls.Add($userProfilesGroup)

$userProfileList = New-Object System.Windows.Forms.ListBox
$userProfileList.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$userProfileList.Location = New-Object System.Drawing.Point(15, 28)
$userProfileList.Size = New-Object System.Drawing.Size(200, 73)
$userProfilesGroup.Controls.Add($userProfileList)

$btnApplyUser = New-Object System.Windows.Forms.Button
$btnApplyUser.Text = "Cargar"
$btnApplyUser.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$btnApplyUser.Location = New-Object System.Drawing.Point(225, 28)
$btnApplyUser.Size = New-Object System.Drawing.Size(85, 30)
$userProfilesGroup.Controls.Add($btnApplyUser)

$btnDelUser = New-Object System.Windows.Forms.Button
$btnDelUser.Text = "Borrar"
$btnDelUser.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$btnDelUser.Location = New-Object System.Drawing.Point(225, 68)
$btnDelUser.Size = New-Object System.Drawing.Size(85, 30)
$userProfilesGroup.Controls.Add($btnDelUser)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(24, 640)
$progress.Size = New-Object System.Drawing.Size(930, 24)
$progress.Minimum = 0
$progress.Maximum = 100
$form.Controls.Add($progress)

$lblProgress = New-Object System.Windows.Forms.Label
$lblProgress.Text = "Esperando..."
$lblProgress.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblProgress.Location = New-Object System.Drawing.Point(27, 670)
$lblProgress.Size = New-Object System.Drawing.Size(920, 24)
$form.Controls.Add($lblProgress)

$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true
$log.ScrollBars = "Vertical"
$log.ReadOnly = $true
$log.BackColor = [System.Drawing.Color]::White
$log.Font = New-Object System.Drawing.Font("Consolas", 8)
$log.Location = New-Object System.Drawing.Point(24, 698)
$log.Size = New-Object System.Drawing.Size(930, 75)
$form.Controls.Add($log)

$script:isAdvancedVisible = $false
$btnToggleAdvanced = New-Object System.Windows.Forms.Button
$btnToggleAdvanced.Text = "â–º Mostrar opciones avanzadas"
$btnToggleAdvanced.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$btnToggleAdvanced.Location = New-Object System.Drawing.Point(24, 310)
$btnToggleAdvanced.Size = New-Object System.Drawing.Size(200, 30)
$form.Controls.Add($btnToggleAdvanced)

function Update-Layout {
    $settingsGroup.Visible = $script:isAdvancedVisible
    if ($script:isAdvancedVisible) {
        $btnToggleAdvanced.Text = "â–¼ Ocultar opciones avanzadas"
        $settingsGroup.Location = New-Object System.Drawing.Point(24, 350)
        $filesGroup.Location = New-Object System.Drawing.Point(24, 550)
        $userProfilesGroup.Location = New-Object System.Drawing.Point(634, 550)
        $progress.Location = New-Object System.Drawing.Point(24, 680)
        $lblProgress.Location = New-Object System.Drawing.Point(27, 710)
        $log.Location = New-Object System.Drawing.Point(24, 738)
        $form.MinimumSize = New-Object System.Drawing.Size(940, 800)
        $form.Size = New-Object System.Drawing.Size(1000, 860)
    } else {
        $btnToggleAdvanced.Text = "â–º Mostrar opciones avanzadas"
        $filesGroup.Location = New-Object System.Drawing.Point(24, 350)
        $userProfilesGroup.Location = New-Object System.Drawing.Point(634, 350)
        $progress.Location = New-Object System.Drawing.Point(24, 480)
        $lblProgress.Location = New-Object System.Drawing.Point(27, 510)
        $log.Location = New-Object System.Drawing.Point(24, 538)
        $form.MinimumSize = New-Object System.Drawing.Size(940, 600)
        $form.Size = New-Object System.Drawing.Size(1000, 660)
    }
}

$btnToggleAdvanced.Add_Click({
    $script:isAdvancedVisible = -not $script:isAdvancedVisible
    Update-Layout
})

function Update-Ready {
    $btnConvert.Enabled = ($script:files.Count -gt 0 -and $null -ne $script:ffmpeg)
}

function Update-FFmpegStatus {
    if ($script:ffmpeg) {
        $status.Text = "FFmpeg: OK  |  $script:ffmpeg"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(25,130,70)
    }
    else {
        $status.Text = "FFmpeg: no encontrado"
        $status.ForeColor = [System.Drawing.Color]::Red
    }
    Update-Ready
}

$profileCombo.Add_SelectedIndexChanged({
    Apply-Profile ([string]$profileCombo.SelectedItem)
    Update-ProfileStatus
})

$btnSaveProfile.Add_Click({
    $name = $txtNewProfile.Text.Trim()
    if (-not $name) {
        Show-Error "Por favor, introduce un nombre para el perfil."
        return
    }
    if ($script:profiles.Contains($name)) {
        Show-Error "No puedes sobrescribir los perfiles del sistema."
        return
    }
    
    if (-not (Validate-Settings)) { return }

        $script:profiles[$name] = @{
        Width = [int]$txtWidth.Text
        Height = [int]$txtHeight.Text
        FPS = [string]$fpsCombo.SelectedItem
        VideoCodec = [string]$codecCombo.SelectedItem
        Profile = [string]$videoProfileCombo.SelectedItem
        Level = [string]$levelCombo.SelectedItem
        CRF = [decimal]$crfNumeric.Value
        ScaleMode = [string]$scaleCombo.SelectedItem
        AudioCodec = [string]$audioCombo.SelectedItem
        AudioBitrate = [string]$audioBitrateCombo.SelectedItem
        SampleRate = [string]$sampleCombo.SelectedItem
        Channels = [string]$channelsCombo.SelectedItem
        StripMetadata = [bool]$metadataCheck.Checked
        FastStart = [bool]$fastStartCheck.Checked
        Suffix = [string]$suffixText.Text
        Ext = [string]$extCombo.SelectedItem
        Description = "Perfil personalizado guardado por el usuario."
        IsUser = $true
    }
    
    Save-UserProfiles
    Refresh-UserProfilesList
    Reload-ProfileCombo
    $profileCombo.SelectedItem = $name
    Log "Perfil guardado: $name"
})

$btnApplyUser.Add_Click({
    if ($userProfileList.SelectedItem) {
        $profileCombo.SelectedItem = $userProfileList.SelectedItem
    }
})

$btnDelUser.Add_Click({
    if ($userProfileList.SelectedItem) {
        $name = [string]$userProfileList.SelectedItem
        $res = [System.Windows.Forms.MessageBox]::Show($form, "Confirmar borrado de perfil: $name", "Borrar", [System.Windows.Forms.MessageBoxButtons]::YesNo)
        if ($res -eq "Yes") {
            $script:profiles.Remove($name)
            Save-UserProfiles
            Reload-ProfileCombo
            Refresh-UserProfilesList
        }
    }
})

function Refresh-UserProfilesList {
    $userProfileList.Items.Clear()
    foreach ($k in $script:profiles.Keys) {
        if ($script:profiles[$k].IsUser) {
            [void]$userProfileList.Items.Add($k)
        }
    }
}

$restoreBtn.Add_Click({
    Apply-Profile ([string]$profileCombo.SelectedItem)
})

$btnSelect.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Seleccionar videos"
    $dlg.Filter = "Videos (*.mov;*.mp4;*.mkv;*.avi;*.m4v)|*.mov;*.mp4;*.mkv;*.avi;*.m4v|Todos los archivos (*.*)|*.*"
    $dlg.Multiselect = $true

    if ($dlg.ShowDialog() -eq "OK") {
        $script:files = @($dlg.FileNames)
        $list.Items.Clear()
        foreach ($f in $script:files) { [void]$list.Items.Add($f) }
        Log "$($script:files.Count) video(s) seleccionado(s)."
        Update-Ready
    }
})

$btnOutput.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Selecciona la carpeta de salida"
    if ($dlg.ShowDialog() -eq "OK") {
        $script:outputFolder = $dlg.SelectedPath
        $lblOutput.Text = "Salida: $script:outputFolder"
        Log "Carpeta de salida: $script:outputFolder"
    }
})

$btnFFmpeg.Add_Click({
    Set-FFmpegTools
    if (-not $script:ffmpeg) {
        $null = Download-FFmpeg
    } else {
        $v = ""
        try {
            $v = & $script:ffmpeg -version 2>$null | Select-Object -First 1
        } catch {}
        Show-Info "FFmpeg detectado.`r`n`r`n$v"
        Log "FFmpeg detectado manualmente."
    }
    Update-FFmpegStatus
})

$btnCancel.Add_Click({
    $script:cancelRequested = $true
    if ($script:currentProcess -and -not $script:currentProcess.HasExited) {
        try { $script:currentProcess.Kill() } catch {}
    }
    Log "Cancelacion solicitada."
})

$btnConvert.Add_Click({
    if (-not $script:ffmpeg) {
        Show-Error "FFmpeg no estÃ¡ disponible."
        return
    }

    if (-not (Validate-Settings)) { return }

    $btnSelect.Enabled = $false
    $btnOutput.Enabled = $false
    $btnConvert.Enabled = $false
    $btnFFmpeg.Enabled = $false
    $btnCancel.Enabled = $true
    $script:cancelRequested = $false
    $progress.Style = "Continuous"
    $progress.Value = 0

    $total = $script:files.Count
    $completed = 0
    $successCount = 0
    $errorCount = 0

    foreach ($input in $script:files) {
        if ($script:cancelRequested) { break }

        $index = $completed + 1
        $base = [System.IO.Path]::GetFileNameWithoutExtension($input)
        $output = Get-OutputFile $input

        $duration = Get-VideoDuration $input
        if ($duration -le 0) { $duration = 1 }

        $lblProgress.Text = "Convirtiendo $index de $total : $base"
        Log "Iniciando: $input"
        Log "Salida: $output"

        $args = Build-FFmpegArguments $input $output

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $script:ffmpeg
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardOutput = $false
        $psi.Arguments = Join-ProcessArguments $args

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        $script:currentProcess = $process

        try {
            [void]$process.Start()
            $errorBuffer = @()

            while (-not $process.HasExited -or -not $process.StandardError.EndOfStream) {
                if ($process.StandardError.EndOfStream) {
                    [System.Windows.Forms.Application]::DoEvents()
                    Start-Sleep -Milliseconds 30
                    continue
                }

                $line = $process.StandardError.ReadLine()
                if ($null -eq $line) {
                    [System.Windows.Forms.Application]::DoEvents()
                    continue
                }
                
                if ($line -notmatch '^out_time_ms=' -and -not [string]::IsNullOrWhiteSpace($line) -and $line -notmatch '^frame=') {
                    if ($line -notmatch 'Use -h to get full help' -and $line -notmatch 'Conversion failed!') {
                        $errorBuffer += $line
                        if ($errorBuffer.Count -gt 3) { $errorBuffer = $errorBuffer[-3..-1] }
                    }
                }

                if ($line -match '^out_time_ms=(-?\d+)') {
                    $micro = [double]$matches[1]
                    if ($micro -ge 0) {
                        $fraction = [Math]::Min(1.0, $micro / 1000000.0 / $duration)
                        $overall = (($completed + $fraction) / $total) * 100.0
                        $progress.Value = [Math]::Max(0, [Math]::Min(100, [int]$overall))
                        $lblProgress.Text = "Convirtiendo $index de $total : $base  |  $([int]($fraction*100))%"
                    }
                }

                [System.Windows.Forms.Application]::DoEvents()

                if ($script:cancelRequested) {
                    try { $process.Kill() } catch {}
                    break
                }
            }

            $exitCode = $process.ExitCode

            if ($script:cancelRequested) {
                Log "Cancelado: $base"
                if (Test-Path -LiteralPath $output -and -not $overwriteCheck.Checked) {
                    try { Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue } catch {}
                }
                break
            }
            elseif ($exitCode -eq 0 -and (Test-Path -LiteralPath $output)) {
                $successCount++
                Log "OK: $output"
            }
            else {
                $errorCount++
                Log "ERROR: $base (codigo $exitCode)"
                if ($errorBuffer.Count -gt 0) { 
                    $detail = $errorBuffer -join " | "
                    Log "Detalle: $detail" 
                }
            }
        }
        catch {
            $errorCount++
            Log "EXCEPCION: $($_.Exception.Message)"
        }
        finally {
            try { $process.Dispose() } catch {}
            $script:currentProcess = $null
        }

        $completed++
        $progress.Value = [Math]::Min(100, [int](($completed / $total) * 100))
    }

    $btnSelect.Enabled = $true
    $btnOutput.Enabled = $true
    $btnFFmpeg.Enabled = $true
    $btnCancel.Enabled = $false
    Update-Ready

    if ($script:cancelRequested) {
        $lblProgress.Text = "Conversion cancelada."
    } else {
        $lblProgress.Text = "Terminado: $successCount correctos | $errorCount errores."
        [System.Windows.Forms.MessageBox]::Show(
            $form,
            "Proceso terminado.`r`n`r`nCorrectos: $successCount`r`nErrores: $errorCount",
            $script:AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
})

$form.Add_FormClosing({
    if ($script:currentProcess -and -not $script:currentProcess.HasExited) {
        try { $script:currentProcess.Kill() } catch {}
    }
})

# Initial setup
Load-UserProfiles
Reload-ProfileCombo
Apply-Profile ([string]$profileCombo.SelectedItem)
Update-ProfileStatus
Set-FFmpegTools

if (-not $script:ffmpeg) {
    Update-FFmpegStatus
    Log "FFmpeg no encontrado. La herramienta solicitara su descarga automatica."
    [System.Windows.Forms.Application]::DoEvents()
    $null = Download-FFmpeg
}
else {
    Update-FFmpegStatus
    Log "FFmpeg encontrado."
}

Update-FFmpegStatus
Refresh-UserProfilesList
Update-Layout
[void]$form.ShowDialog()


