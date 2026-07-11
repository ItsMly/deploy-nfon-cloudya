<#
.SYNOPSIS
This script tries to install the newest version of Cloudya Desktop by NFON (or the rebranded O2 Digital Phone Desktop) from the official website.
.DESCRIPTION
This script tries to install the newest version of Cloudya Desktop by NFON (or the rebranded O2 Digital Phone Desktop) from the official website.
.PARAMETER Action
The action to perform. Possible values are "Install", "Uninstall", "Update" or "Detect".
.PARAMETER Product
The product to manage. Possible values are "Cloudya" (default) and "DigitalPhone" (O2 Digital Phone, a rebranding of Cloudya).
.PARAMETER Autostart
Creates a shortcut in the autostart folder.
.PARAMETER DisableUpdateCheck
Disables the update check.
.PARAMETER EnableCRM
Enables the CRM integration.
.PARAMETER Version
Installs a specific version (format #.#.#) instead of the latest one.
.PARAMETER Help
Shows this help.
.INPUTS
None
.OUTPUTS
Just output on screen
.NOTES
Version:        2.1
Author:         ItsMly (samily.it)
Original Author: info@singleton-factory.de
Creation Date:  2026-07-11
Purpose/Change: Digital Phone support, bugfixes, robustness

.EXAMPLE
.\Deploy-NFONCloudya.ps1 -Action Install -Autostart -EnableCRM -DisableUpdateCheck
.EXAMPLE
.\Deploy-NFONCloudya.ps1 -Action Install -Product DigitalPhone -Autostart
#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#----------------------------------------------------------[Declarations]----------------------------------------------------------
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("Install", "Uninstall", "Update", "Detect")]
    [string]$Action,
    [ValidateSet("Cloudya", "DigitalPhone")]
    [string]$Product = "Cloudya",
    [switch]$Autostart = $false,
    [switch]$EnableCRM = $false,
    [switch]$Help = $false,
    [switch]$DisableUpdateCheck = $false,
    [ValidatePattern('^$|^\d+\.\d+\.\d+$')]
    [string]$Version
)

# Version of this script
$ScriptVersion = "2.1"

# Configuration per product. Digital Phone (O2) is a rebranding of Cloudya and
# is delivered from the same CDN with a different file name prefix.
$ProductConfigs = @{
    Cloudya      = @{
        ProductName      = "Cloudya Desktop"
        DownloadPage     = "https://www.nfon.com/de/service/downloads"
        CdnPrefix        = "cloudya"
        DisplayNameMatch = "*Cloudya*"
        ExeName          = "Cloudya.exe"
        ProcessName      = "cloudya"
        ShortcutName     = "Cloudya"
        SettingsFileName = "Cloudya-local-settings.json"
    }
    DigitalPhone = @{
        ProductName      = "Digital Phone Desktop"
        DownloadPage     = "https://my.digitalphone.o2business.de/de/service/downloads"
        CdnPrefix        = "digital_phone"
        DisplayNameMatch = "*Digital Phone*"
        ExeName          = "Digital Phone.exe"
        ProcessName      = "Digital Phone"
        ShortcutName     = "Digital Phone"
        SettingsFileName = "Digital_Phone-local-settings.json"
    }
}
$Config = $ProductConfigs[$Product]

# msiexec exit codes that count as success (0 = ok, 3010/1641 = ok but reboot)
$MsiSuccessCodes = @(0, 1641, 3010)
#-----------------------------------------------------------[Functions]------------------------------------------------------------
function GetDownloadURL {
    param(
        [string]$Version = $script:Version,
        [string]$Product = $script:Product
    )
    $cfg = $ProductConfigs[$Product]
    # Check if Version is #.#.# format
    if ($Version -match "^\d+\.\d+\.\d+$") {
        Log -Severity "Info" "You specified version $Version"
        Log -Severity "Info" "This will be used instead of the latest version."
        return [PSCustomObject]@{
            URLDefault     = "https://cdn.cloudya.com/$($cfg.CdnPrefix)-$Version-win-msi.zip"
            URLCRM         = "https://cdn.cloudya.com/$($cfg.CdnPrefix)-$Version-crm-win-msi.zip"
            versionDefault = $Version
            versionCRM     = $Version
        }
    }
    else {
        Log -Severity "Info" "Getting download URL from $($cfg.DownloadPage) ..."
        # Send a request to the website and get the response
        try {
            $response = Invoke-WebRequest $cfg.DownloadPage -UseBasicParsing
        }
        catch {
            throw "Failed to reach the download page $($cfg.DownloadPage): $($_.Exception.Message)"
        }

        # Define the regex patterns to extract the download URLs and version numbers
        $regexDefault = "https:\/\/cdn\.cloudya\.com\/$($cfg.CdnPrefix)-(\d+\.\d+\.\d+)-win-msi\.zip"
        $regexCRM = "https:\/\/cdn\.cloudya\.com\/$($cfg.CdnPrefix)-(\d+\.\d+\.\d+)-crm-win-msi\.zip"

        # Search for the pattern in the response (without CRM)
        if ([regex]::IsMatch($response.Content, $regexDefault)) {
            $matchDefault = [regex]::Match($response.Content, $regexDefault)
            $urlDefault = $matchDefault.Value
            $versionDefault = $matchDefault.Groups[1].Value
        }
        else {
            throw "Failed to extract $($cfg.ProductName) download URL or version number."
        }

        # Search for the pattern in the response (with CRM)
        if ([regex]::IsMatch($response.Content, $regexCRM)) {
            $matchCRM = [regex]::Match($response.Content, $regexCRM)
            $urlCRM = $matchCRM.Value
            $versionCRM = $matchCRM.Groups[1].Value
        }
        else {
            throw "Failed to extract $($cfg.ProductName) CRM download URL or version number."
        }

        # Create a PSCustomObject with the extracted information
        return [PSCustomObject]@{
            URLDefault     = $urlDefault
            URLCRM         = $urlCRM
            versionDefault = $versionDefault
            versionCRM     = $versionCRM
        }
    }
}


# Get a temporary file name
function GetTempFileName {
    $tempFile = [System.IO.Path]::GetTempFileName()
    return $tempFile
}

# Download the setup file
function DownloadSetupFile {
    param([bool]$EnableCRM)
    # Get the download URL
    $url = GetDownloadURL
    if ($EnableCRM) {
        $url = $url.URLCRM
    }
    else {
        $url = $url.URLDefault
    }
    # Get the setup file name
    $setupFile = $tempFile

    # Download the setup file
    Log -Severity "Info" "Downloading setup file from $url ..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $setupFile -Method Get -UseBasicParsing
    }
    catch {
        Log -Severity "Error" "Download failed: $($_.Exception.Message)"
        Cleanup
        exit 1
    }
    Log -Severity "Info" "Download was saved to $setupFile"
}

function Cleanup {
    # Remove the temporary files
    if ($tempBase -and (Test-Path $tempBase)) {
        Remove-Item $tempBase
    }

    if ($tempFile -and (Test-Path $tempFile)) {
        Remove-Item $tempFile
    }

    if ($tempExtractFolder -and (Test-Path $tempExtractFolder)) {
        Remove-Item $tempExtractFolder -Recurse
    }
}

function CheckZipFile ($path) {
    # Check if there is a file to check
    if (-not (Test-Path $path)) {
        return $false
    }
    # Check if the file is a zip file by reading the first four bytes (zip header)
    $stream = [System.IO.File]::OpenRead($path)
    try {
        $bytes = New-Object byte[] 4
        $bytesRead = $stream.Read($bytes, 0, 4)
    }
    finally {
        $stream.Dispose()
    }
    if ($bytesRead -lt 4) {
        return $false
    }

    # Check if the first four bytes match the zip file header
    return ($bytes[0] -eq 0x50 -and $bytes[1] -eq 0x4B -and $bytes[2] -eq 0x03 -and $bytes[3] -eq 0x04)
}

# Run msiexec and check the exit code
function InvokeMsiexec {
    param(
        [string[]]$ArgumentList,
        [string]$Activity
    )
    $process = Start-Process -FilePath msiexec.exe -ArgumentList $ArgumentList -Wait -PassThru
    if ($MsiSuccessCodes -contains $process.ExitCode) {
        return $true
    }
    Log -Severity "Error" "$Activity failed with msiexec exit code $($process.ExitCode)."
    return $false
}

function CheckIfInstalled {
    # Check if the program is installed
    $uninstallKeys = @(
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $installed = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $Config.DisplayNameMatch } | Select-Object -First 1

    $displayName = $installed.DisplayName
    $installLocation = $installed.InstallLocation
    $displayVersion = $installed.DisplayVersion
    $guid = $installed.PSChildName
    $installedCRM = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*CRM Connect*" } | Select-Object -First 1
    $installedCRMdisplayVersion = ($installedCRM.DisplayVersion -split "\s+")[0]
    $installedCRMAddins = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*CRM Connect Addins*" } | Select-Object -First 1
    $installedCRMAddinsDisplayVersion = $installedCRMAddins.displayVersion
    $installedCRMPlusAddins = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*CRM Connect Plus Addins*" } | Select-Object -First 1
    $installedCRMPlusAddinsDisplayVersion = $installedCRMPlusAddins.displayVersion
    $installedCRMQuietUninstallString = $installedCRM.QuietUninstallString
    $installedCRMAddinsGUID = $installedCRMAddins.PSChildName
    $installedCRMPlusAddinsGUID = $installedCRMPlusAddins.PSChildName
    # If CRM is installed, set the variable to true
    if ($installedCRM) {
        $installedCRMFound = $true
    }
    else {
        $installedCRMFound = $false
    }
    # Return the result
    return [PSCustomObject]@{
        DisplayName                 = $displayName
        InstallLocation             = $installLocation
        displayVersion              = $displayVersion
        GUID                        = $guid
        CRMdisplayVersion           = $installedCRMDisplayVersion
        CRMAddinsdisplayVersion     = $installedCRMAddinsDisplayVersion
        CRMPlusAddinsdisplayVersion = $installedCRMPlusAddinsDisplayVersion
        CRM                         = $installedCRMFound
        CRMQuietUninstallString     = $installedCRMQuietUninstallString
        CRMAddinsGUID               = $installedCRMAddinsGUID
        CRMPlusAddinsGUID           = $installedCRMPlusAddinsGUID
    }
}

# Get the full path of the local settings file (used for the update check),
# which the app reads from the directory containing its exe.
function GetLocalSettingsFilePath {
    $installed = CheckIfInstalled
    if (-not $installed.InstallLocation) {
        return $null
    }
    $exe = Get-ChildItem -Path $installed.InstallLocation -Recurse -Filter $Config.ExeName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exe) {
        return $null
    }
    return Join-Path $exe.DirectoryName $Config.SettingsFileName
}

function Install {
    param([bool]$EnableCRM)
    # Check if the program is already installed
    $installed = CheckIfInstalled
    if ($installed.DisplayName) {
        Log -Severity "Info" "$($Config.ProductName) is already installed."
        return
    }
    else {
        # Download the setup file
        DownloadSetupFile -EnableCRM $EnableCRM

        # Check if the downloaded file is a zip file and extract it
        if ((CheckZipFile $tempFile) -eq $true) {
            Expand-Archive -Path $tempFile -DestinationPath $tempExtractFolder
            Log -Severity "Info" "Extracted to: $tempExtractFolder."
        }
        else {
            Log -Severity "Error" "Downloaded file is not a zip file. Maybe the URL returns 404? Program will exit."
            Log -Severity "Error" "Please check if the detected URL is correct."
            Cleanup
            exit 1
        }

        # Get the setup file name
        $setupFile = Get-ChildItem -Path $tempExtractFolder -Filter "*.msi" -Recurse | Select-Object -First 1 -ExpandProperty FullName
        Log -Severity "Info" "Found setup file: $setupFile"
        if ($setupFile) {
            # Install the setup file
            Log -Severity "Info" "Starting installation process ..."
            if (-not (InvokeMsiexec -ArgumentList @("/i", "`"$setupFile`"", "/qn", "/norestart", "REBOOT=ReallySuppress") -Activity "Installation of $($Config.ProductName)")) {
                Cleanup
                exit 1
            }
            # Wait until crm.exe is not running
            Log -Severity "Info" "Waiting for crm.exe to finish ..."
            while ($null -ne (Get-Process -Name crm -ErrorAction SilentlyContinue)) {
                Start-Sleep 2
            }
            Log -Severity "Info" "Installation done."
        }
        else {
            Log -Severity "Error" "Setup file not found. Program will exit."
            Cleanup
            exit 1
        }
        Log -Severity "Info" "Checking if installation was successful ..."
        $installedApp = CheckIfInstalled
        if ($installedApp.DisplayName) {
            Log -Severity "Info" "Installation was successful."
        }
        else {
            Log -Severity "Error" "Installation failed."
            Cleanup
            exit 1
        }
    }
}

function Uninstall {
    param($App)
    $displayName = $App.DisplayName
    $displayVersion = $App.DisplayVersion
    $GUID = $App.GUID
    $CRMQuietUninstallString = $App.CRMQuietUninstallString
    $CRMAddinsGUID = $App.CRMAddinsGUID
    $CRMPlusAddinsGUID = $App.CRMPlusAddinsGUID
    $installLocation = $App.InstallLocation

    # Check if any apps were found
    if (-not $displayName -and -not $displayVersion -and -not $GUID -and -not $CRMQuietUninstallString -and -not $CRMAddinsGUID -and -not $CRMPlusAddinsGUID) {
        Log -Severity "Info" "No apps found to uninstall."
        return $true
    }

    $success = $true

    # Remove local settings file (update check control)
    $settingsFile = GetLocalSettingsFilePath
    if ($settingsFile -and (Test-Path $settingsFile)) {
        Remove-Item -Path $settingsFile -Force -ErrorAction SilentlyContinue
        Log -Severity "Info" "Update control disabled."
    }

    # Remove legacy update control script (created by script versions <= 2.0)
    if ($installLocation -and (Test-Path -Path "$installLocation\control-cloudya-update.ps1")) {
        Remove-Item -Path "$installLocation\control-cloudya-update.ps1" -Force -ErrorAction SilentlyContinue
    }

    # Remove legacy update control script autostart (created by script versions <= 2.0)
    if (Test-Path -Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\Cloudya Update Control.lnk") {
        Remove-Item -Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\Cloudya Update Control.lnk" -Force -ErrorAction SilentlyContinue
    }

    # Uninstall the setup msi file
    if ($GUID) {
        # Disable autostart
        Autostart $false
        Log -Severity "Info" "Uninstalling $displayName $displayVersion ..."
        # Stop the app process
        Stop-Process -Name $Config.ProcessName -Force -ErrorAction SilentlyContinue
        if (-not (InvokeMsiexec -ArgumentList @("/x", $GUID, "/qn", "/norestart", "REBOOT=ReallySuppress") -Activity "Uninstallation of $displayName")) {
            $success = $false
        }
    }

    # Uninstall CRM Connect
    if ($CRMQuietUninstallString) {
        Log -Severity "Info" "Uninstalling CRM Connect ..."
        # Stop Process crm.exe
        Stop-Process -Name "crm" -Force -ErrorAction SilentlyContinue
        $process = Start-Process -FilePath cmd.exe -ArgumentList "/c $CRMQuietUninstallString /norestart REBOOT=ReallySuppress" -Wait -PassThru
        if ($MsiSuccessCodes -notcontains $process.ExitCode) {
            Log -Severity "Error" "Uninstallation of CRM Connect failed with exit code $($process.ExitCode)."
            $success = $false
        }
    }

    # Uninstall CRM Connect Addins
    if ($CRMAddinsGUID) {
        Log -Severity "Info" "Uninstalling CRM Connect Addins ..."
        if (-not (InvokeMsiexec -ArgumentList @("/x", $CRMAddinsGUID, "/qn", "/norestart", "REBOOT=ReallySuppress") -Activity "Uninstallation of CRM Connect Addins")) {
            $success = $false
        }
    }

    # Uninstall CRM Connect Plus Addins
    if ($CRMPlusAddinsGUID) {
        Log -Severity "Info" "Uninstalling CRM Connect Plus Addins ..."
        if (-not (InvokeMsiexec -ArgumentList @("/x", $CRMPlusAddinsGUID, "/qn", "/norestart", "REBOOT=ReallySuppress") -Activity "Uninstallation of CRM Connect Plus Addins")) {
            $success = $false
        }
    }

    # Waiting until crm.exe is not running
    Log -Severity "Info" "Waiting for crm.exe to finish ..."
    while ($null -ne (Get-Process -Name crm -ErrorAction SilentlyContinue)) {
        Start-Sleep 2
    }
    return $success
}

function Detect {
    # Check if the program is already installed
    $installed = CheckIfInstalled
    if ($installed.DisplayName) {
        Log -Severity "Info" "$($Config.ProductName): $($installed.DisplayVersion)"
    }
    else {
        Log -Severity "Warn" "$($Config.ProductName): Not installed."
    }

    if ($installed.CRMdisplayVersion) {
        Log -Severity "Info" "CRM Connect: $($installed.CRMdisplayVersion)"
    }
    else {
        Log -Severity "Warn" "CRM Connect: Not installed."
    }

    if ($installed.CRMAddinsdisplayVersion) {
        Log -Severity "Info" "CRM Connect Addins: $($installed.CRMAddinsdisplayVersion)"
    }
    else {
        Log -Severity "Warn" "CRM Connect Addins: Not installed."
    }

    if ($installed.CRMPlusAddinsdisplayVersion) {
        Log -Severity "Info" "CRM Connect Plus Addins: $($installed.CRMPlusAddinsdisplayVersion)"
    }
    else {
        Log -Severity "Warn" "CRM Connect Plus Addins: Not installed."
    }
}

function ShowHelp {
    Log -Severity "Info" "This script will download and install $($Config.ProductName)."
    Log -Severity "Info" "Parameters:"
    Log -Severity "Info" "  -Action Install    Install the software."
    Log -Severity "Info" "  -Action Uninstall  Remove the software."
    Log -Severity "Info" "  -Action Update     Install the latest version if a newer one is available."
    Log -Severity "Info" "  -Action Detect     Display the currently installed version (exit code 0 = installed, 1 = not installed)."
    Log -Severity "Info" "  -Product           Choose the product: Cloudya (default) or DigitalPhone (O2 Digital Phone)."
    Log -Severity "Info" "  -EnableCRM         Install CRM Connect alongside the app."
    Log -Severity "Info" "  -Autostart         Add the app to the autostart for all users (disable with -Autostart:`$false)."
    Log -Severity "Info" "  -DisableUpdateCheck  Disable the built-in update check (enable again with -DisableUpdateCheck:`$false)."
    Log -Severity "Info" "  -Version #.#.#     Install a specific version instead of the latest one."
    Log -Severity "Info" "You can combine the parameters."
    Log -Severity "Info" "Example: .\Deploy-NFONCloudya.ps1 -Action Install -Autostart -EnableCRM -DisableUpdateCheck"
    Log -Severity "Info" "Example: .\Deploy-NFONCloudya.ps1 -Action Install -Product DigitalPhone"
}
function Update {
    # Check if the program is already installed
    $installed = CheckIfInstalled

    # When the app is not installed, exit
    if ($null -eq $installed.DisplayName) {
        Log -Severity "Error" "$($Config.ProductName) is not installed."
        Log -Severity "Error" "Please install $($Config.ProductName) first."
        Log -Severity "Error" "You can do this by running this script with the '-Action Install' parameter."
        exit 1
    }

    # Get current version from website
    $currentVersion = GetDownloadURL

    # Print detected version
    Log -Severity "Info" "Installed version: $($installed.DisplayVersion)"
    Log -Severity "Info" "Current version: $($currentVersion.versionDefault)"

    # Compare versions
    if ([Version]$installed.DisplayVersion -lt [Version]$currentVersion.versionDefault) {
        Log -Severity "Info" "$($Config.ProductName) is not up to date."
        Log -Severity "Info" "Updating $($Config.ProductName) ..."

        # Detect if CRM Connect is installed
        if ($installed.CRMdisplayVersion) {
            Log -Severity "Info" "CRM Connect is installed."
            $EnableCRM = $true
        }
        else {
            Log -Severity "Info" "CRM Connect is not installed."
            $EnableCRM = $false
        }

        # Remember settings that are lost during uninstall so they can be restored
        $autostartShortcutPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\$($Config.ShortcutName).lnk"
        $hadAutostart = Test-Path $autostartShortcutPath
        $settingsFile = GetLocalSettingsFilePath
        $hadUpdateCheckDisabled = ($settingsFile -and (Test-Path $settingsFile))

        # Uninstall the setup msi file
        $uninstalled = Uninstall -App $installed
        if ($uninstalled) {
            Log -Severity "Info" "Uninstallation was successful."

            # Install the setup file
            Install -EnableCRM $EnableCRM

            # Restore settings
            if ($hadAutostart) {
                Autostart $true
            }
            if ($hadUpdateCheckDisabled) {
                DisableUpdateCheck $false
            }
        }
        else {
            Log -Severity "Error" "Uninstallation failed. Update aborted."
            Cleanup
            exit 1
        }
    }
    elseif ([Version]$installed.DisplayVersion -eq [Version]$currentVersion.versionDefault) {
        Log -Severity "Info" "$($Config.ProductName) is already up to date."
        return
    }
    else {
        Log -Severity "Info" "Local version is higher than the current version."
        return
    }
}

function Autostart([bool]$trueOrFalse) {
    if ($trueOrFalse -eq $false) {
        Log -Severity "Info" "Disabling autostart ..."
        # Find shortcut in startup folder
        $shortcut = Get-ChildItem -Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\" -Filter "$($Config.ShortcutName).lnk"
        if ($shortcut) {
            try {
                Remove-Item -Path $shortcut.FullName
                Log -Severity "Info" "Autostart disabled."
            }
            catch {
                Log -Severity "Error" "Could not disable autostart. $($_.Exception.Message)"
            }
        }
        else {
            Log -Severity "Warn" "Autostart was already disabled."
        }
    }
    elseif ($trueOrFalse -eq $true) {
        Log -Severity "Info" "Enabling autostart ..."
        # Get Install location
        $installed = CheckIfInstalled
        if ($installed.DisplayName) {
            $installLocation = $installed.InstallLocation

            # Search for the app exe in all subfolders
            $desktopExe = Get-ChildItem -Path $installLocation -Recurse -Filter $Config.ExeName | Select-Object -First 1
            if ($desktopExe) {
                $desktopExe = $desktopExe.FullName

                # Create shortcut
                try {
                    $WshShell = New-Object -ComObject "WScript.Shell"
                    $Shortcut = $WshShell.CreateShortcut("$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\$($Config.ShortcutName).lnk")
                    $Shortcut.TargetPath = "$desktopExe"
                    $Shortcut.Save()
                    Log -Severity "Info" "Autostart enabled."
                }
                # If access is denied, log error
                catch {
                    if ($_.Exception.GetType().FullName -eq "System.UnauthorizedAccessException") {
                        Log -Severity "Error" "Failed to create startup shortcut: Access to the global startup folder was denied."
                    }
                    else {
                        Log -Severity "Error" "Failed to create startup shortcut: $($_.Exception.Message)"
                    }
                }
            }
            # If the exe was not found, log error
            else {
                Log -Severity "Error" "$($Config.ExeName) was not found in the installation folder."
            }
        }
        else {
            Log -Severity "Error" "$($Config.ProductName) is not installed."
            Log -Severity "Error" "Please install $($Config.ProductName) first."
            Log -Severity "Error" "You can do this by running this script with the '-Action Install' parameter."

        }

    }
}

function DisableUpdateCheck([bool]$UpdatesEnabled) {
    # The app reads its configuration from a local settings file next to its exe
    # (e.g. C:\Program Files\Cloudya\win-unpacked\Cloudya-local-settings.json).
    # "handle-updates": "IGNORE" disables the built-in update check.
    $settingsFile = GetLocalSettingsFilePath
    if ($null -eq $settingsFile) {
        Log -Severity "Error" "$($Config.ProductName) is not installed."
        Log -Severity "Error" "Please install $($Config.ProductName) first."
        Log -Severity "Error" "You can do this by running this script with the '-Action Install' parameter."
        return
    }

    # Remove legacy update control mechanism (created by script versions <= 2.0);
    # newer app versions no longer read the settings file from %APPDATA%.
    $installLocation = (CheckIfInstalled).InstallLocation
    if (Test-Path -Path "$installLocation\control-cloudya-update.ps1") {
        Remove-Item -Path "$installLocation\control-cloudya-update.ps1" -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\Cloudya Update Control.lnk") {
        Remove-Item -Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\Cloudya Update Control.lnk" -Force -ErrorAction SilentlyContinue
    }

    try {
        if ($UpdatesEnabled) {
            if (Test-Path $settingsFile) {
                Remove-Item -Path $settingsFile -Force
            }
            Log -Severity "Info" "Updates are now enabled."
        }
        else {
            Set-Content -Path $settingsFile -Value '{ "handle-updates": "IGNORE" }' -Force
            Log -Severity "Info" "Updates are now disabled."
        }
    }
    catch {
        Log -Severity "Error" "Failed to write update control settings: $($_.Exception.Message)"
        throw
    }
}

function Log {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Severity,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $date = Get-Date -Format "yyyy-MM-dd"
    $time = Get-Date -Format "HH:mm:ss"

    switch ($Severity) {
        "INFO" {
            $color = "Green"
        }
        "WARN" {
            $color = "Yellow"
        }
        "ERROR" {
            $color = "Red"
        }
    }
    $severityText = "[$Severity]".ToUpper()
    $dateTimeText = "$date $time"
    $messageText = $Message

    $maxSeverityLength = 7
    $maxDateTimeLength = 19

    $formattedSeverity = $severityText.PadRight($maxSeverityLength)
    $formattedDateTime = $dateTimeText.PadRight($maxDateTimeLength)
    $formattedMessage = $messageText

    $logMessage = "$formattedSeverity $formattedDateTime $formattedMessage"
    Write-Host $logMessage -ForegroundColor $color
}

function Header {
    Log -Severity "Info" "Cloudya All-in-One Desktop Manager by ItsMly (samily.it). Original script by Aaron Viehl (Singleton Factory GmbH)."
    Log -Severity "Info" "Your toolkit for a better NFON Cloudya / O2 Digital Phone experience."
    Log -Severity "Info" "Version: $ScriptVersion"
    Log -Severity "Info" "Selected product: $($Config.ProductName)"
    Log -Severity "Info" "======================="
}
#-----------------------------------------------------------[Main Code]------------------------------------------------------------#
# Show header
Header

# Show help and stop when requested or when no action/parameter was given
if ($Help -or (-not $Action -and -not $PSBoundParameters.ContainsKey('Autostart') -and -not $PSBoundParameters.ContainsKey('DisableUpdateCheck'))) {
    ShowHelp
    return
}

# Get temporary file names
$tempBase = GetTempFileName
$tempFile = $tempBase + ".zip"
$tempExtractFolder = $tempFile + ".extract"

switch ($Action) {
    "Install" {
        # Install the program
        if ($EnableCRM) {
            Log -Severity "Info" "Installing $($Config.ProductName) + CRM Connect..."
        }
        else {
            Log -Severity "Info" "Installing $($Config.ProductName) ..."
        }
        Install -EnableCRM $EnableCRM
        Detect
    }
    "Uninstall" {
        $installedApp = CheckIfInstalled
        # Check if the program is installed
        $uninstalled = Uninstall -App $installedApp
        Detect
        if (-not $uninstalled) {
            Cleanup
            exit 1
        }
    }
    "Update" {
        Log -Severity "Info" "Checking for updates ..."
        Update
    }
    "Detect" {
        Detect
    }
}

# Check if autostart parameter is set
if ($PSBoundParameters.ContainsKey('Autostart') -and $Autostart) {
    Autostart $true
}
elseif ($PSBoundParameters.ContainsKey('Autostart') -and !$Autostart) {
    Autostart $false
}

# Check if update check parameter is set
if ($PSBoundParameters.ContainsKey('DisableUpdateCheck') -and $DisableUpdateCheck) {
    DisableUpdateCheck $false
}
elseif ($PSBoundParameters.ContainsKey('DisableUpdateCheck') -and !$DisableUpdateCheck) {
    DisableUpdateCheck $true
}

# Cleanup all temporary files
Cleanup

# For the Detect action the exit code signals the install state (usable e.g. as Intune detection script)
if ($Action -eq "Detect") {
    if ((CheckIfInstalled).DisplayName) {
        exit 0
    }
    exit 1
}
