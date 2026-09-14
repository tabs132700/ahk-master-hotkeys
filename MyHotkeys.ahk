#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ============================================================
; USER CONFIGURATION
; Edit the values below to match your own setup before running.
; ============================================================

; --- AirPods / Bluetooth audio device ---

; Bluetooth MAC address of the already-paired audio device you want
; Ctrl+Shift+A / Ctrl+Shift+Alt+A to connect and disconnect.
; Find yours by running your Bluetooth utility's "discover" command
; and reading the MAC address column for the paired device.
global AirPodsMac := "XX:XX:XX:XX:XX:XX"

; Text that appears in the device's audio endpoint name. Used to verify
; the connection actually came up (see the AIRPODS - TECHNICAL NOTES
; section in README.md). "AirPods" works for any AirPods model; change
; it to match your own headphones if different.
global AirPodsNameMatch := "AirPods"

; Full path to a Bluetooth pairing command-line utility that supports
; "pair-by-mac --mac <mac> --type Bluetooth" and
; "disconnect-bluetooth-audio-device-by-mac --mac <mac> --type Bluetooth".
; This is a third-party tool, NOT included in this repo. See README.md
; for what interface is expected if you want to use a different tool.
global BluetoothUtilityPath := "C:\Apps\BluetoothDevicePairing\BluetoothDevicePairing.exe"

; --- XAMPP ---
global XamppControlPath := "C:\xampp\xampp-control.exe"

; --- phpMyAdmin ---
global PhpMyAdminUrl := "http://localhost/phpmyadmin"

; ============================================================
; END OF USER CONFIGURATION
; ============================================================


global HotkeysEnabled := true


; ============================================================
; FULLSCREEN CHECK
; ============================================================

IsFullscreen()
{
    try
    {
        hwnd := WinExist("A")

        if !hwnd
            return false

        ; Maximized windows are NOT treated as fullscreen
        if (WinGetMinMax("ahk_id " hwnd) = 1)
            return false

        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)

        Loop MonitorGetCount()
        {
            MonitorGet(A_Index, &left, &top, &right, &bottom)

            if (x <= left + 2
                && y <= top + 2
                && w >= (right - left) - 2
                && h >= (bottom - top) - 2)
            {
                return true
            }
        }
    }
    catch
    {
    }

    return false
}


HotkeysAreAllowed()
{
    global HotkeysEnabled

    return HotkeysEnabled && !IsFullscreen()
}


; ============================================================
; AIRPODS - EMBEDDED POWERSHELL HELPERS
;
; The AirPods hotkeys below need real PowerShell logic (WinRT calls to
; check/enable Bluetooth, and Core Audio calls to verify the AirPods are
; actually connected). To keep everything in this single .ahk file, that
; PowerShell source is stored as plain text here and written out to a
; temp .ps1 file at the moment a hotkey is pressed, then run and deleted.
; ============================================================

RunPowerShellScript(scriptText)
{
    tempFile := A_Temp "\MyHotkeys_" A_TickCount ".ps1"

    file := FileOpen(tempFile, "w", "UTF-8-RAW")
    file.Write(scriptText)
    file.Close()

    exitCode := RunWait(
        'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' tempFile '"',
        ,
        "Hide"
    )

    try
        FileDelete(tempFile)

    return exitCode
}

AirPodsConnectScript(mac, exePath, nameMatch)
{
    header := '$mac = "' mac '"' "`n"
    header .= '$exe = "' exePath '"' "`n"
    header .= '$nameMatch = "' nameMatch '"' "`n"

    body := "
(
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Runtime.WindowsRuntime | Out-Null

$script:AsTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object {
        $_.Name -eq 'AsTask' -and
        $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation``1'
    })[0]

function Await($WinRtTask, $ResultType) {
    $asTask = $script:AsTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
    return $netTask.Result
}

[Windows.Devices.Radios.Radio,Windows.System.Devices,ContentType=WindowsRuntime] | Out-Null
[Windows.Devices.Radios.RadioKind,Windows.System.Devices,ContentType=WindowsRuntime] | Out-Null
[Windows.Devices.Radios.RadioState,Windows.System.Devices,ContentType=WindowsRuntime] | Out-Null
[Windows.Devices.Radios.RadioAccessStatus,Windows.System.Devices,ContentType=WindowsRuntime] | Out-Null

function Get-BluetoothRadio {
    $accessOp = [Windows.Devices.Radios.Radio]::RequestAccessAsync()
    Await $accessOp ([Windows.Devices.Radios.RadioAccessStatus]) | Out-Null

    $radiosOp = [Windows.Devices.Radios.Radio]::GetRadiosAsync()
    $radios = Await $radiosOp ([System.Collections.Generic.IReadOnlyList[Windows.Devices.Radios.Radio]])

    return $radios | Where-Object { $_.Kind -eq [Windows.Devices.Radios.RadioKind]::Bluetooth } | Select-Object -First 1
}

function Enable-BluetoothRadio {
    param([int]$TimeoutSeconds = 8)

    $radio = Get-BluetoothRadio
    if (-not $radio) {
        return $false
    }

    if ($radio.State -ne [Windows.Devices.Radios.RadioState]::On) {
        $setOp = $radio.SetStateAsync([Windows.Devices.Radios.RadioState]::On)
        Await $setOp ([Windows.Devices.Radios.RadioAccessStatus]) | Out-Null
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $radio = Get-BluetoothRadio
        if ($radio -and $radio.State -eq [Windows.Devices.Radios.RadioState]::On) {
            return $true
        }
        Start-Sleep -Milliseconds 500
    }

    return $false
}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"), ClassInterface(ClassInterfaceType.None), ComImport]
public class MMDeviceEnumeratorComObj { }

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator
{
    int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
}

[Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceCollection
{
    int GetCount(out int count);
    int Item(int index, out IMMDevice device);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice
{
    int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, out IntPtr iface);
    int OpenPropertyStore(int stgmAccess, out IPropertyStore properties);
    int GetId(out IntPtr id);
    int GetState(out int state);
}

[Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPropertyStore
{
    int GetCount(out int count);
    int GetAt(int index, out PROPERTYKEY key);
    int GetValue(ref PROPERTYKEY key, out PROPVARIANT value);
    int SetValue(ref PROPERTYKEY key, ref PROPVARIANT value);
    int Commit();
}

[StructLayout(LayoutKind.Sequential)]
public struct PROPERTYKEY
{
    public Guid fmtid;
    public int pid;
}

[StructLayout(LayoutKind.Sequential)]
public struct PROPVARIANT
{
    public ushort vt;
    public ushort r1, r2, r3;
    public IntPtr p;
    public int p2;
}

public static class AirPodsAudioHelper
{
    public static string[] GetActiveEndpointNames(int dataFlow)
    {
        var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObj();
        IMMDeviceCollection collection;
        enumerator.EnumAudioEndpoints(dataFlow, 1, out collection);

        int count;
        collection.GetCount(out count);
        string[] names = new string[count];

        PROPERTYKEY PKEY_Device_FriendlyName = new PROPERTYKEY
        {
            fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"),
            pid = 14
        };

        for (int i = 0; i < count; i++)
        {
            IMMDevice device;
            collection.Item(i, out device);
            IPropertyStore props;
            device.OpenPropertyStore(0, out props);
            PROPVARIANT pv;
            props.GetValue(ref PKEY_Device_FriendlyName, out pv);
            names[i] = Marshal.PtrToStringUni(pv.p);
        }

        return names;
    }
}
"@ | Out-Null

function Test-AirPodsAudioActive {
    param([string]$NameMatch = "AirPods")

    $render = [AirPodsAudioHelper]::GetActiveEndpointNames(0)
    $capture = [AirPodsAudioHelper]::GetActiveEndpointNames(1)
    $all = @($render) + @($capture)

    return (@($all | Where-Object { $_ -and $_ -like "*$NameMatch*" })).Count -gt 0
}

if (-not (Enable-BluetoothRadio -TimeoutSeconds 8)) {
    Write-Output "BLUETOOTH_OFF"
    exit 1
}

if (-not (Test-Path $exe)) {
    Write-Output "EXE_NOT_FOUND"
    exit 3
}

try {
    & $exe pair-by-mac --mac $mac --type Bluetooth 2>&1 | Out-Null
} catch {
    Write-Output "EXE_FAILED"
    exit 3
}

$connected = $false
$deadline = (Get-Date).AddSeconds(12)
while ((Get-Date) -lt $deadline) {
    if (Test-AirPodsAudioActive -NameMatch $nameMatch) {
        $connected = $true
        break
    }
    Start-Sleep -Milliseconds 1000
}

if ($connected) {
    Write-Output "CONNECTED"
    exit 0
} else {
    Write-Output "NOT_CONNECTED"
    exit 2
}
)"

    return header . body
}

AirPodsDisconnectScript(mac, exePath, nameMatch)
{
    header := '$mac = "' mac '"' "`n"
    header .= '$exe = "' exePath '"' "`n"
    header .= '$nameMatch = "' nameMatch '"' "`n"

    body := "
(
$ErrorActionPreference = "Stop"

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"), ClassInterface(ClassInterfaceType.None), ComImport]
public class MMDeviceEnumeratorComObj { }

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator
{
    int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
}

[Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceCollection
{
    int GetCount(out int count);
    int Item(int index, out IMMDevice device);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice
{
    int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, out IntPtr iface);
    int OpenPropertyStore(int stgmAccess, out IPropertyStore properties);
    int GetId(out IntPtr id);
    int GetState(out int state);
}

[Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPropertyStore
{
    int GetCount(out int count);
    int GetAt(int index, out PROPERTYKEY key);
    int GetValue(ref PROPERTYKEY key, out PROPVARIANT value);
    int SetValue(ref PROPERTYKEY key, ref PROPVARIANT value);
    int Commit();
}

[StructLayout(LayoutKind.Sequential)]
public struct PROPERTYKEY
{
    public Guid fmtid;
    public int pid;
}

[StructLayout(LayoutKind.Sequential)]
public struct PROPVARIANT
{
    public ushort vt;
    public ushort r1, r2, r3;
    public IntPtr p;
    public int p2;
}

public static class AirPodsAudioHelper
{
    public static string[] GetActiveEndpointNames(int dataFlow)
    {
        var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObj();
        IMMDeviceCollection collection;
        enumerator.EnumAudioEndpoints(dataFlow, 1, out collection);

        int count;
        collection.GetCount(out count);
        string[] names = new string[count];

        PROPERTYKEY PKEY_Device_FriendlyName = new PROPERTYKEY
        {
            fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"),
            pid = 14
        };

        for (int i = 0; i < count; i++)
        {
            IMMDevice device;
            collection.Item(i, out device);
            IPropertyStore props;
            device.OpenPropertyStore(0, out props);
            PROPVARIANT pv;
            props.GetValue(ref PKEY_Device_FriendlyName, out pv);
            names[i] = Marshal.PtrToStringUni(pv.p);
        }

        return names;
    }
}
"@ | Out-Null

function Test-AirPodsAudioActive {
    param([string]$NameMatch = "AirPods")

    $render = [AirPodsAudioHelper]::GetActiveEndpointNames(0)
    $capture = [AirPodsAudioHelper]::GetActiveEndpointNames(1)
    $all = @($render) + @($capture)

    return (@($all | Where-Object { $_ -and $_ -like "*$NameMatch*" })).Count -gt 0
}

if (-not (Test-Path $exe)) {
    Write-Output "EXE_NOT_FOUND"
    exit 3
}

try {
    & $exe disconnect-bluetooth-audio-device-by-mac --mac $mac --type Bluetooth 2>&1 | Out-Null
} catch {
    Write-Output "EXE_FAILED"
    exit 3
}

$disconnected = $false
$deadline = (Get-Date).AddSeconds(8)
while ((Get-Date) -lt $deadline) {
    if (-not (Test-AirPodsAudioActive -NameMatch $nameMatch)) {
        $disconnected = $true
        break
    }
    Start-Sleep -Milliseconds 500
}

if ($disconnected) {
    Write-Output "DISCONNECTED"
    exit 0
} else {
    Write-Output "STILL_CONNECTED"
    exit 1
}
)"

    return header . body
}


; ============================================================
; CTRL + N
; NEW CHROME TAB
; ============================================================

#HotIf HotkeysAreAllowed()

^n::
{
    if WinExist("ahk_exe chrome.exe")
    {
        WinActivate("ahk_exe chrome.exe")
        Sleep 100
        Send "^t"
    }
    else
    {
        Run "chrome.exe"
    }
}

#HotIf


; ============================================================
; CHROME
; CTRL + SHIFT + T
; REOPEN CLOSED TAB
; ============================================================

#HotIf HotkeysAreAllowed() && WinActive("ahk_exe chrome.exe")

^+t::
{
    Send "^+t"
}

#HotIf


; ============================================================
; SPOTIFY
; CTRL + SHIFT + S
; ============================================================

#HotIf HotkeysAreAllowed()

^+s::
{
    Run "https://open.spotify.com"
}


; ============================================================
; CHATGPT APP
; CTRL + SHIFT + C
; ============================================================

^+c::
{
    shell := ComObject("Shell.Application")
    folder := shell.Namespace("shell:AppsFolder")

    if folder
    {
        for item in folder.Items
        {
            if (item.Name = "ChatGPT")
            {
                item.InvokeVerb("open")
                return
            }
        }
    }

    MsgBox "ChatGPT was not found."
}


; ============================================================
; CLAUDE APP
; CTRL + SHIFT + L
; ============================================================

^+l::
{
    shell := ComObject("Shell.Application")
    folder := shell.Namespace("shell:AppsFolder")

    if folder
    {
        for item in folder.Items
        {
            if (item.Name = "Claude")
            {
                item.InvokeVerb("open")
                return
            }
        }
    }

    MsgBox "Claude was not found."
}


; ============================================================
; DISCORD
; CTRL + SHIFT + D
; ============================================================

^+d::
{
    Run "discord://"
}


; ============================================================
; GITHUB
; CTRL + SHIFT + G
; ============================================================

^+g::
{
    Run "https://github.com"
}


; ============================================================
; YOUTUBE
; CTRL + SHIFT + Y
; ============================================================

^+y::
{
    Run "https://youtube.com"
}


; ============================================================
; WHATSAPP WEB
; CTRL + SHIFT + W
; ============================================================

^+w::
{
    Run "https://web.whatsapp.com"
}


; ============================================================
; VS CODE
; CTRL + SHIFT + V
; ============================================================

^+v::
{
    Run "code"
}


; ============================================================
; DOWNLOADS
; CTRL + SHIFT + F
; ============================================================

^+f::
{
    downloads := EnvGet("USERPROFILE") "\Downloads"

    if DirExist(downloads)
    {
        Run downloads
    }
    else
    {
        MsgBox "Downloads folder was not found:`n" downloads
    }
}


; ============================================================
; XAMPP
; CTRL + SHIFT + X
; ============================================================

^+x::
{
    global XamppControlPath

    if FileExist(XamppControlPath)
    {
        Run XamppControlPath
    }
    else
    {
        MsgBox "XAMPP was not found at:`n" XamppControlPath "`n`nEdit XamppControlPath in the CONFIG section of this script."
    }
}


; ============================================================
; PHPMYADMIN
; CTRL + SHIFT + M
; ============================================================

^+m::
{
    global PhpMyAdminUrl

    Run PhpMyAdminUrl
}


; ============================================================
; AIRPODS
; CTRL + SHIFT + A
; TURN ON BLUETOOTH (IF NEEDED) AND CONNECT AIRPODS
; ============================================================

^+a::
{
    global AirPodsMac, BluetoothUtilityPath, AirPodsNameMatch

    ToolTip "Connecting AirPods..."

    exitCode := RunPowerShellScript(AirPodsConnectScript(AirPodsMac, BluetoothUtilityPath, AirPodsNameMatch))

    ToolTip()

    switch exitCode
    {
        case 0:
            ToolTip "AirPods connected"
            SetTimer () => ToolTip(), -1500
        case 1:
            MsgBox "Bluetooth could not be turned on."
        case 2:
            MsgBox "Bluetooth is ON, but the AirPods could not be connected."
        case 3:
            MsgBox "Bluetooth utility was not found at:`n" BluetoothUtilityPath "`n`nEdit BluetoothUtilityPath in the CONFIG section of this script."
        default:
            MsgBox "AirPods connect script failed unexpectedly (exit code " exitCode ")."
    }
}


; ============================================================
; AIRPODS DISCONNECT
; CTRL + SHIFT + ALT + A
; DISCONNECT AIRPODS AUDIO ONLY (BLUETOOTH STAYS ON)
; ============================================================

^+!a::
{
    global AirPodsMac, BluetoothUtilityPath, AirPodsNameMatch

    ToolTip "Disconnecting AirPods..."

    exitCode := RunPowerShellScript(AirPodsDisconnectScript(AirPodsMac, BluetoothUtilityPath, AirPodsNameMatch))

    ToolTip()

    switch exitCode
    {
        case 0:
            SoundSetMute(1)
            ToolTip "AirPods disconnected (muted)"
            SetTimer () => ToolTip(), -1500
        case 1:
            MsgBox "The AirPods still appear connected after attempting to disconnect."
        case 3:
            MsgBox "Bluetooth utility was not found at:`n" BluetoothUtilityPath "`n`nEdit BluetoothUtilityPath in the CONFIG section of this script."
        default:
            MsgBox "AirPods disconnect script failed unexpectedly (exit code " exitCode ")."
    }
}


; ============================================================
; MANUAL
; CTRL + SHIFT + ?
; ============================================================

^+SC035::
{
    manual := A_ScriptDir "\README.md"

    if FileExist(manual)
    {
        Run manual
    }
    else
    {
        MsgBox "Manual not found:`n" manual
    }
}

#HotIf


; ============================================================
; CTRL + ALT + F4
; CLOSE ALL OPEN WINDOWS
; ============================================================

#HotIf HotkeysAreAllowed()

^!F4::
{
    windows := WinGetList()

    for hwnd in windows
    {
        try
        {
            if (WinGetMinMax("ahk_id " hwnd) != -1)
            {
                WinClose("ahk_id " hwnd)
            }
        }
    }
}

#HotIf


; ============================================================
; F12
; TOGGLE HOTKEYS ON / OFF
; ============================================================

F12::
{
    global HotkeysEnabled

    HotkeysEnabled := !HotkeysEnabled

    if HotkeysEnabled
    {
        ToolTip "Hotkeys ON"
    }
    else
    {
        ToolTip "Hotkeys OFF"
    }

    SetTimer () => ToolTip(), -1000
}
