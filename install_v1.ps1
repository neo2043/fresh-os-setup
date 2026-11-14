Install-Module -Name 'PSParseHTML' -Scope CurrentUser
$current_directory = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

Set-Location -Path $current_directory

$winget_list = get-content -path ".\winget_install.txt"

$zigup_url = "https://github.com/marler8997/zigup/releases/latest/download/zigup-x86_64-windows.zip"
$zigup_local_path = "C:/Users/AUTO/Downloads/zigup-x86_64-windows.zip"
$zigup_unzipped_path = $env:USERPROFILE + "/terminal/zigup-x86_64-windows"

$rust_url = "https://win.rustup.rs/"
$rust_local_path = "C:/Users/AUTO/Downloads/rustup-init.exe"

$lanxchange_url = "https://github.com/tfg13/LanXchange/raw/master/releases/stable/lxc.zip"
$lanxchange_local_path = "C:/Users/AUTO/Downloads/lxc.zip"
$lanxchange_unzipped_path = "C:/LanXchange/"

$rufus_html = ConvertFrom-HTML -URL "https://rufus.ie/en/" -Engine AngleSharp
$rufus_url = $rufus_html.QuerySelector("#download > table:nth-child(3) > tbody > tr:nth-child(2) > td:nth-child(1) > a").Attributes["href"].NodeValue
$rufus_path_temp = $rufus_url.split("/")
$rufus_local_path = "$env:USERPROFILE/terminal/rufus/" + $rufus_path_temp[-1]

$virtualbox_html = ConvertFrom-HTML -URL "https://www.virtualbox.org/wiki/Downloads" -Engine AngleSharp
$virtualbox_url = $virtualbox_html.QuerySelector("#pkg-holder > ul > li:nth-child(1) > a").Attributes["href"].NodeValue
$virtualbox_path_temp = $virtualbox_url.split("/")
$virtualbox_local_path = "$env:USERPROFILE\Downloads\" + $virtualbox_path_temp[-1]
$virtualbox_extension_url = $virtualbox_html.QuerySelector("#button-container > a").Attributes["href"].NodeValue
$virtualbox_extension_path_temp = $virtualbox_extension_url.split("/")
$virtualbox_extension_local_path = "$env:USERPROFILE/Downloads/" + $virtualbox_extension_path_temp[-1]

$all_releases = Invoke-RestMethod -Uri "https://api.github.com/repos/clangd/clangd/releases"
$clangd_latest_release = $all_releases | Sort-Object -Property published_at -Descending | Select-Object -First 1
$tag = $clangd_latest_release.tag_name
$clangd_latest_url = "https://github.com/clangd/clangd/releases/download/$tag/clangd-windows-$tag.zip"
$clangd_local_path = "C:/Users/AUTO/Downloads/$tag.zip"
$clangd_unzipped_path = $env:USERPROFILE + "/terminal"

$response = curl.exe -sL "https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads" | Out-String
$arm_toolchain_html = ConvertFrom-HTML -Content $response -Engine AngleSharp
$arm_toolchain_url = $arm_toolchain_html.QuerySelector("#panel1a > div:nth-child(1) > div:nth-child(1) > div:nth-child(2) > ul:nth-child(19) > li:nth-child(1) > nobr:nth-child(1) > a:nth-child(1)").Attributes["href"].NodeValue
$arm_toolchain_local_path_temp = $arm_toolchain_url.split("/")
$arm_toolchain_local_path = "$env:USERPROFILE/Downloads/" + $arm_toolchain_local_path_temp[-1]
$arm_toolchain_local_unzipped_path = "$env:USERPROFILE/terminal/" + [System.IO.Path]::GetFileNameWithoutExtension($arm_toolchain_local_path)

# $esp_idf_url = "https://dl.espressif.com/dl/idf-installer/esp-idf-tools-setup-espressif-ide-3.0.0-with-esp-idf-5.2.2.exe"
# $esp_idf_local_path = "C:/Users/AUTO/Downloads/esp-idf-tools-setup-espressif-ide-3.0.0-with-esp-idf-5.2.2.exe"

# $arduino_ide_url = "https://downloads.arduino.cc/arduino-1.8.19-windows.exe"
# $arduino_ide_local_path = "C:/Users/AUTO/Downloads/arduino-1.8.19-windows.exe"

# $cisco_packet_tracer_url = "https://archive.org/download/cisco-packet-tracer-821-ubuntu-64bit/CiscoPacketTracer_821_Windows_64bit.exe"
# $cisco_packet_tracer_local_path = "C:/Users/AUTO/Downloads/CiscoPacketTracer_821_Windows_64bit.exe"

Write-Host "winget process started"
   foreach ($listitem in $winget_list) {
      Write-Host "installing $listitem ....."
      winget install --id $listitem --source winget
      if ($LASTEXITCODE -eq 0) {
         Write-Host "$listitem installed successfully."
      }
      else {
         Write-Host "Failed to install $listitem. Exit code: $LASTEXITCODE"
      }
   }
# winget install $winget_list --source winget
Write-Host "All winget apps installed."

Write-Host "Installing VS"
Start-Process powershell -ArgumentList "-NoExit", "winget install --id Microsoft.VisualStudio.Community --interactive --force --source winget" -Wait
Write-Host "Installed VS"

$webClient = New-Object System.Net.WebClient

Write-Host "Installing ZigUp"
$webClient.DownloadFile($zigup_url, $zigup_local_path)
New-Item -Path $env:USERPROFILE -Name "terminal" -ItemType "directory"
Expand-Archive -Force -Path $zigup_local_path -DestinationPath $zigup_unzipped_path
$user_path = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($user_path -notlike $zigup_unzipped_path) {
   if ($user_path[-1] -eq ";") {
      $user_path += "$zigup_unzipped_path"
   } else {
      $user_path += ";$zigup_unzipped_path"
   }
   [System.Environment]::SetEnvironmentVariable("PATH", $user_path, [System.EnvironmentVariableTarget]::User)
   Write-Host "Added '$zigup_unzipped_path' to the PATH environment variable. Changes will take effect in new sessions."
}
else {
   Write-Host "'$zigup_unzipped_path' is already in the PATH."
}
Remove-Item $zigup_local_path
Write-Host "Installed ZigUp"

Write-Host "Installing clangd"
$webClient.DownloadFile($clangd_latest_url, $clangd_local_path)
Expand-Archive -Force -Path $clangd_local_path -DestinationPath $clangd_unzipped_path
$clangd_path = "$($clangd_unzipped_path)/clangd_$tag/bin"
$user_path = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($user_path -notlike $clangd_path) {
   if ($user_path[-1] -eq ";") {
      $user_path += "$clangd_path"
   } else {
      $user_path += ";$clangd_path"
   }
   [System.Environment]::SetEnvironmentVariable("PATH", $user_path, [System.EnvironmentVariableTarget]::User)
   Write-Host "Added '$($clangd_path)' to the PATH environment variable. Changes will take effect in new sessions."
}
else {
   Write-Host "'$($clangd_path)' is already in the PATH."
}
Remove-Item $clangd_local_path
Write-Host "Installed clangd"

Write-Host "Installing Rust"
$webClient.DownloadFile($rust_url, $rust_local_path)
Start-Process -FilePath $rust_local_path -Wait
Remove-Item $rust_local_path
Write-Host "Installed Rust"

Write-Host "Installing lanxchange"
$webClient.DownloadFile($lanxchange_url, $lanxchange_local_path)
if (-not (Test-Path -Path $lanxchange_unzipped_path -PathType Container)) {
   New-Item -Path $lanxchange_unzipped_path -ItemType Directory
}
Expand-Archive -Path $lanxchange_local_path -DestinationPath $lanxchange_unzipped_path
Remove-Item $lanxchange_local_path
$WshShell = New-Object -COMObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\LanXChange.lnk")
$Shortcut.TargetPath = "C:\LanXchange\lxc.exe"
$Shortcut.Save()
Write-Host "Installed lanxchange"

Write-Host "Installing rufus"
New-Item -Path "$env:USERPROFILE\terminal\" -Name "Rufus" -ItemType Directory
$webClient.DownloadFile($rufus_url, $rufus_local_path)
$WshShell = New-Object -COMObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Rufus.lnk")
$Shortcut.TargetPath = $rufus_local_path
$Shortcut.Save()
Write-Host "Installed rufus"

Write-Host "Installing virtual box"
$webClient.DownloadFile($virtualbox_url, $virtualbox_local_path)
Start-Process -FilePath $virtualbox_local_path -Wait
Remove-Item $virtualbox_local_path
Write-Host "Installed virtual box"

Write-Host "Installing virtual box extension"
$webClient.DownloadFile($virtualbox_extension_url, $virtualbox_extension_local_path)
Start-Process -FilePath $virtualbox_extension_local_path -Wait
Remove-Item $virtualbox_extension_local_path
Write-Host "Installed virtual box extension"

# Write-Host "Installing VScode extensions"
# Start-Process powershell -ArgumentList "-NoExit","python $current_directory\install.py" -Wait
# Write-Host "Installed VScode extensions"

Write-Host "Installing nur"
& "$env:USERPROFILE\.cargo\bin\cargo" install nur
Write-Host "Installed nur"

Write-Host "Installing ARM Toolchain"
$webClient.DownloadFile($arm_toolchain_url, $arm_toolchain_local_path)
New-Item -Path $env:USERPROFILE -Name "terminal" -ItemType "directory"
[System.IO.Directory]::CreateDirectory("$env:USERPROFILE\terminal")
Expand-Archive -Force -Path $arm_toolchain_local_path -DestinationPath $arm_toolchain_local_unzipped_path
$user_path = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($user_path -notlike $arm_toolchain_local_unzipped_path) {
   if ($user_path[-1] -eq ";") {
      $user_path += "$arm_toolchain_local_unzipped_path/bin"
   } else {
      $user_path += ";$arm_toolchain_local_unzipped_path/bin"
   }
   [System.Environment]::SetEnvironmentVariable("PATH", $user_path, [System.EnvironmentVariableTarget]::User)
   Write-Host "Added '$arm_toolchain_local_unzipped_path/bin' to the PATH environment variable. Changes will take effect in new sessions."
}
else {
   Write-Host "'$arm_toolchain_local_unzipped_path/bin' is already in the PATH."
}
Remove-Item $arm_toolchain_local_path
Write-Host "Installed ARM Toolchain"

# Write-Host "Installing ESP IDF"
# $webClient.DownloadFile($esp_idf_url, $esp_idf_local_path)
# Start-Process -FilePath $esp_idf_local_path -Wait
# Remove-Item $esp_idf_local_path
# Write-Host "Installed ESP IDF"

# Write-Host "Installing Arduino"
# $webClient.DownloadFile($arduino_ide_url, $arduino_ide_local_path)
# Start-Process -FilePath $arduino_ide_local_path -Wait
# Remove-Item $arduino_ide_local_path
# Write-Host "Installed Arduino"

# Write-Host "Installing cisco packet tracer"
# $webClient.DownloadFile($cisco_packet_tracer_url, $cisco_packet_tracer_local_path)
# Start-Process -FilePath $cisco_packet_tracer_local_path -Wait
# Remove-Item $cisco_packet_tracer_local_path
# Write-Host "Installed cisco packet tracer"
