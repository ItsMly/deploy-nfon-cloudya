# Deploy-NFONCloudya.ps1

*Version: 2.1*

![Download URL Test Status](https://github.com/ItsMly/deploy-nfon-cloudya/actions/workflows/get_download_url_test.yml/badge.svg)

This script attempts to install the latest version of Cloudya Desktop by NFON — or the rebranded **O2 Digital Phone Desktop** — from the official website. It also provides some advanced configuration options for deployment within corporate networks, as the native installer does not offer these.

## Notice

Please note that the use of this PowerShell script is at your own risk. The script is still in development and may contain bugs. Please review and test the script carefully before using it in a production environment.

The author assumes no responsibility for any damage or loss that may result from using the script.

## Installation

1. Download the script and save it to any directory on your computer.
2. Run it in an administrative PowerShell session with the required parameters.

## Usage

```powershell
.\Deploy-NFONCloudya.ps1 -Action {Install, Detect, Update, Uninstall} [-Product {Cloudya, DigitalPhone}] [-EnableCRM] [-Autostart] [-DisableUpdateCheck] [-Version #.#.#]
```

## Parameters

| Parameter                                     | Description                                                  |
| --------------------------------------------- | ------------------------------------------------------------ |
| `Action {Install, Detect, Update, Uninstall}` | Tells the script which action to perform:<br />Install → Install the software<br />Detect → Display the currently installed version (exit code 0 = installed, 1 = not installed, usable e.g. as Intune detection script)<br />Update → Install the latest version if available<br />Uninstall → Remove the software |
| `Product {Cloudya, DigitalPhone}`             | Selects the product to manage. `Cloudya` (default) is the NFON original, `DigitalPhone` is the O2 Digital Phone Desktop App — a rebranding of Cloudya distributed via [my.digitalphone.o2business.de](https://my.digitalphone.o2business.de/de/service/downloads). |
| `EnableCRM`                                   | Automatically installs CRM Connect alongside the app         |
| `Autostart`                                   | Enables the app in the Windows autostart for all users. Can also be used to disable autostart via `-Autostart:$false` |
| `DisableUpdateCheck`                          | Disables the automatic update check in the app. By default the check is enabled, but updates require admin privileges. In corporate networks the update check should therefore be disabled. Can be re-enabled via `-DisableUpdateCheck:$false` |
| `Version #.#.#`                               | Specifies a version to install. The latest version will not be determined automatically. This solves the issue of NFON not providing the same versions everywhere. |

## How It Works

1. The script scrapes the vendor download page for the latest MSI installer download links:
   - Cloudya: `https://www.nfon.com/de/service/downloads`
   - Digital Phone: `https://my.digitalphone.o2business.de/de/service/downloads`
2. The files are downloaded (both products are delivered from the same CDN, `cdn.cloudya.com`).
3. The installation is started and monitored (msiexec exit codes are checked).
4. Any necessary adjustments (autostart, update check, CRM installation) are applied.

### Disabling the Update Check

By specifying the `-DisableUpdateCheck` parameter, the internal function for checking for new updates is disabled. This prevents users from being prompted to update their installation. This is particularly useful in corporate environments, as updates require local administrator privileges.

The update check is disabled via a config file, since there is [no direct configuration option](https://partnercommunity.nfon.com/t/release-teaser-cloudya-app-1-6/2618/33):

1. The script writes a local settings file next to the app executable (e.g. `C:\Program Files\Cloudya\win-unpacked\Cloudya-local-settings.json`, for Digital Phone `...\win-unpacked\Digital_Phone-local-settings.json`).
2. Its content is `{ "handle-updates": "IGNORE" }`, which disables the update check.
3. When the file is deleted (`-DisableUpdateCheck:$false`), the updater works as normal again.

*Note: Current app versions (2.x) only read this settings file from the executable directory. Older versions of this script (≤ 2.0) placed the file in `%APPDATA%` via a logon script — that mechanism no longer works and its leftovers are cleaned up automatically.*

During `-Action Update` the script remembers whether autostart and the disabled update check were active and restores both after the new version has been installed.

## Examples

To install the latest version of Cloudya with CRM Connect, autostart, and disabled update check:

```powershell
.\Deploy-NFONCloudya.ps1 -Action Install -EnableCRM -Autostart -DisableUpdateCheck
```

To install the latest version of O2 Digital Phone:

```powershell
.\Deploy-NFONCloudya.ps1 -Action Install -Product DigitalPhone
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
