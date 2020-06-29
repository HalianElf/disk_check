#Requires -Version 5.0
# HalianElf
using namespace System.Management.Automation
[CmdletBinding()]
param(
	[parameter (
		   Mandatory=$false
		 , position=0
		 , HelpMessage="Enable debug output"
		)
	]
	[Switch]$DebugOn = $false
)

# Define variables
$InformationPreference = 'Continue'
$Host.UI.RawUI.BackgroundColor = 'Black'
# https://en.wikipedia.org/wiki/S.M.A.R.T.#Known_ATA_S.M.A.R.T._attributes
$ERROR_ATTRIBUTES = @{
    "5"="Reallocated_Sector_Ct"
    "10"="Spin_Retry_Count"
    "184"="End-to-End_Error"
    "187"="Reported_Uncorrect"
    "188"="Command_Timeout"
    "196"="Reallocated_Event_Count"
    "197"="Current_Pending_Sector"
    "198"="Offline_Uncorrectable"
}

$WARN_ATTRIBUTES = @{
    "9"="Power_On_Hours"
    "194"="Temperature"
}

# Temp Directory for smart output
$tmpDir = "$env:programdata\disk_check\"
if (-Not (Test-Path $tmpDir -PathType Container)) {
    New-Item -ItemType "directory" -Path $tmpDir | Out-Null
}

# Set Debug Preference to Continue if flag is set so there is output to console
if ($DebugOn) {
	$DebugPreference = 'Continue'
}

# Function to change the color output of text
# https://blog.kieranties.com/2018/03/26/write-information-with-colours
function Write-ColorOutput() {
	[CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Object]$MessageData,
        [ConsoleColor]$ForegroundColor = $Host.UI.RawUI.ForegroundColor, # Make sure we use the current colours by default
        [ConsoleColor]$BackgroundColor = $Host.UI.RawUI.BackgroundColor,
        [Switch]$NoNewline
    )

    $msg = [HostInformationMessage]@{
        Message         = $MessageData
        ForegroundColor = $ForegroundColor
        BackgroundColor = $BackgroundColor
        NoNewline       = $NoNewline.IsPresent
    }

    Write-Information $msg
}

function notice($msg) {
    $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-ColorOutput -nonewline -ForegroundColor gray -MessageData $date
    Write-ColorOutput -nonewline -ForegroundColor green -MessageData " [NOTICE]   "
    Write-ColorOutput -ForegroundColor gray -MessageData $msg
}

function info($msg) {
    $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-ColorOutput -nonewline -ForegroundColor gray -MessageData $date
    Write-ColorOutput -nonewline -ForegroundColor blue -MessageData " [INFO  ]   "
    Write-ColorOutput -ForegroundColor gray -MessageData $msg
}

function error($msg) {
    $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-ColorOutput -nonewline -ForegroundColor gray -MessageData $date
    Write-ColorOutput -nonewline -ForegroundColor red -MessageData " [ERROR ]   "
    Write-ColorOutput -ForegroundColor gray -MessageData $msg
}

function warn($msg) {
    $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-ColorOutput -nonewline -ForegroundColor gray -MessageData $date
    Write-ColorOutput -nonewline -ForegroundColor yellow -MessageData " [WARN  ]   "
    Write-ColorOutput -ForegroundColor gray -MessageData $msg
}

function main() {
    $disks = Get-WMIObject Win32_LogicalDisk
    foreach($disk in $disks.DeviceID) {
        smartctl -a $disk > $tmpDir/smart.txt

        $smartCap = cat $tmpDir/smart.txt | Select-String -Pattern '^SMART support is.*$'
        if(-Not($smartCap -like 'SMART support is: Available - device has SMART capability.')) {
            error "Drive $disk SMART information is not available."
            Write-Information ""
            Write-Information ""
            Continue
        }

        notice "Drive $disk"
        $healthVal = cat $tmpDir/smart.txt | Select-String -Pattern '^SMART overall-health self-assessment test result:\s+(.*)$'
        if($healthVal.matches.groups[1] -like "PASSED") {
            notice "Health:`t$($healthVal.matches.groups[1])"
        } else {
            error "Health:`t$(healthVal.matches.groups[1])"
        }

        foreach($line in (Get-Content $tmpDir/smart.txt | Select-String -Pattern "(Pre-fail|Old_age)\s+(Always|Offline)")) {
            $line = [String]$line
            $trim = $line.Trim()
            $formattedLine = $($trim -replace '\s+', ",")
            $ID_VAL = $formattedLine | %{ $_.Split(",")[0]; }
            $ATTRIBUTE_NAME_VAL = $formattedLine | %{ $_.Split(",")[1]; }
            $FLAG_VAL = $formattedLine | %{ $_.Split(",")[2]; }
            $VALUE_VAL = $formattedLine | %{ $_.Split(",")[3]; }
            $WORST_VAL = $formattedLine | %{ $_.Split(",")[4]; }
            $THRESH_VAL = $formattedLine | %{ $_.Split(",")[5]; }
            $TYPE_VAL = $formattedLine | %{ $_.Split(",")[6]; }
            $UPDATED_VAL = $formattedLine | %{ $_.Split(",")[7]; }
            $WHEN_FAILED_VAL = $formattedLine | %{ $_.Split(",")[8]; }
            $RAW_VALUE_VAL = $formattedLine | %{ $_.Split(",")[9]; }

            if ($TYPE_VAL -like "Pre-fail") {
                if (($RAW_VALUE_VAL -gt 0) -Or ($RAW_VALUE_VAL -gt $THRESH_VAL)) {
                    $err = $false
                    foreach($i in $ERROR_ATTRIBUTES) {
                        if(($i -eq $ID_VAL) -And ($ERROR_ATTRIBUTES[$i] -eq $ATTRIBUTE_NAME_VAL)) {
                            $err = $true
                        }
                    }
                    if($err) {
                        error "${ATTRIBUTE_NAME_VAL}:`t${RAW_VALUE_VAL}"
                    } else {
                        warn "${ATTRIBUTE_NAME_VAL}:`t${RAW_VALUE_VAL}"
                    }
                } else {
                    info "${ATTRIBUTE_NAME_VAL}:`t${RAW_VALUE_VAL}"
                }
            } elseif($TYPE_VAL -like "Old_age") {
                if($RAW_VALUE_VAL -gt $THRESH_VAL) {
                    $notice = $false
                    foreach($i in $WARN_ATTRIBUTES) {
                        if(($i -eq $ID_VAL) -And ($WARN_ATTRIBUTES[$i] -like $ATTRIBUTE_NAME_VAL)) {
                            $notice = $true
                        }
                    }
                    if($notice){
                        notice "${ATTRIBUTE_NAME_VAL}:`t${RAW_VALUE_VAL}"
                    } else {
                        info "${ATTRIBUTE_NAME_VAL}:`t${RAW_VALUE_VAL}"
                    }
                } else {
                    info "${ATTRIBUTE_NAME_VAL}:`t${RAW_VALUE_VAL}"
                }
            }
        }
        Write-Information ""
        Write-Information ""
    }
}

main