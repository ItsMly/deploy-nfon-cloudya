# Deploy-NFONCloudya.ps1

*Version: 2.0*

![Download URL Test Status](https://github.com/ItsMly/deploy-nfon-cloudya/actions/workflows/get_download_url_test.yml/badge.svg)

This script attempts to install the latest version of Cloudya Desktop by NFON from the official website. It also provides some advanced configuration options for deployment within corporate networks, as the native NFON installer does not offer these.

## Notice

Please note that the use of this PowerShell script is at your own risk. The script is still in development and may contain bugs. Please review and test the script carefully before using it in a production environment.

The author assumes no responsibility for any damage or loss that may result from using the script.

## Installation

1. Download the script and save it to any directory on your computer.
2. Run it in an administrative PowerShell session with the required parameters.

## Usage

```powershell
.\Deploy-NFONCloudya.ps1 -Action {Install, Detect, Update, Uninstall} [-EnableCRM] [-Autostart] [-DisableUpdateCheck] [-Version #.#.#]
```

## Parameters

| Parameter                                     | Description                                                  |
| --------------------------------------------- | ------------------------------------------------------------ |
| `Action {Install, Detect, Update, Uninstall}` | Tells the script which action to perform:<br />Install → Install the software<br />Detect → Display the currently installed version<br />Update → Install the latest version if available<br />Uninstall → Remove the software |
| `EnableCRM`                                   | Automatically installs CRM Connect alongside Cloudya         |
| `Autostart`                                   | Enables Cloudya in the Windows autostart for all users. Can also be used to disable autostart via `-Autostart:$false` |
| `DisableUpdateCheck`                          | Disables the automatic update check in Cloudya. By default the check is enabled, but updates require admin privileges. In corporate networks the update check should therefore be disabled. |
| `Version #.#.#`                               | Specifies a version to install. The latest version will not be determined automatically. This solves the issue of NFON not providing the same versions everywhere. |

## How It Works

1. The script scrapes the website `https://www.nfon.com/de/service/downloads` for the latest MSI installer download links.
2. The files are downloaded.
3. The installation is started and monitored.
4. Any necessary adjustments (autostart, update check, CRM installation) are applied.

### Disabling the Update Check

By specifying the `-DisableUpdateCheck` parameter, the internal Cloudya function for checking for new updates is disabled. This prevents users from being prompted to update their Cloudya installation. This is particularly useful in corporate environments, as updates require local administrator privileges.

The update check is disabled via a workaround, since there is [no direct configuration option](https://partnercommunity.nfon.com/t/release-teaser-cloudya-app-1-6/2618/33):

1. The file `control-cloudya-update.ps1` is created in the Cloudya installation directory.
2. A startup shortcut is created for all users that runs `control-cloudya-update.ps1` at each login.
3. The script creates or deletes the file `%appdata%\cloudya-desktop\Cloudya-local-settings.json`
   1. When the file is created, its content is `{"handle-updates": "IGNORE" }`, which disables the update.
   2. When the file is deleted, the updater works as normal again.

*Note: If special security policies regarding the use of PowerShell scripts are active, this option may fail. In that case an alternative approach must be found.*

## Examples

To install the latest version of Cloudya with CRM Connect, autostart, and disabled update check:

```powershell
.\Deploy-NFONCloudya.ps1 -Action Install -EnableCRM -Autostart -DisableUpdateCheck
```

To completely uninstall Cloudya:

```powershell
.\Deploy-NFONCloudya.ps1 -Action Uninstall
```

To detect the currently installed version:

```powershell
.\Deploy-NFONCloudya.ps1 -Action Detect
```

To perform an update:

```powershell
.\Deploy-NFONCloudya.ps1 -Action Update
```

To enable autostart after installation:

```powershell
.\Deploy-NFONCloudya.ps1 -Autostart
```

To disable autostart after installation:

```powershell
.\Deploy-NFONCloudya.ps1 -Autostart:$false
```

To install a specific version:

```powershell
.\Deploy-NFONCloudya.ps1 -Action Install -Version 1.7.0
```

All parameters can be combined with each other.
