<#
Pomo Windows Activity Tracker (prototype)

Records only:
  - foreground application executable name (not window title)
  - app changes (timeline)
  - system idle duration from GetLastInputInfo

Does NOT record key names, typed text, mouse coordinates, screenshots, or clipboard.
Designed for an explicitly started, visible user-owned session.
Compatible with Windows PowerShell 5.1+.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [ValidateRange(250, 10000)]
    [int]$PollIntervalMs = 1000,

    # 0 = run until StopFile appears or Ctrl+C is pressed.
    [ValidateRange(0, 86400)]
    [int]$DurationSeconds = 0,

    # Optional file used by Pomo to request a clean stop or pause.
    [string]$StopFile = '',

    [string]$PauseFile = '',

    [ValidateRange(1, 3600)]
    [int]$IdleThresholdSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ('PomoWindowsNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class PomoWindowsNative
{
    [StructLayout(LayoutKind.Sequential)]
    private struct LASTINPUTINFO
    {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [DllImport("kernel32.dll")]
    private static extern uint GetTickCount();

    public static uint GetForegroundProcessId()
    {
        IntPtr hwnd = GetForegroundWindow();
        uint processId = 0;
        if (hwnd != IntPtr.Zero)
            GetWindowThreadProcessId(hwnd, out processId);
        return processId;
    }

    public static long GetIdleMilliseconds()
    {
        LASTINPUTINFO info = new LASTINPUTINFO();
        info.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        if (!GetLastInputInfo(ref info))
            return -1;

        // Unsigned subtraction handles the 32-bit GetTickCount wraparound.
        uint elapsed = unchecked(GetTickCount() - info.dwTime);
        return (long)elapsed;
    }
}
'@ -Language CSharp
}


# Input hooks count only event totals. Key codes, button identities, coordinates,
# typed text, window titles, and clipboard contents are never read or persisted.
if (-not ('PomoWindowsInputNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;

public static class PomoWindowsInputNative
{
    private const int WH_KEYBOARD_LL = 13;
    private const int WH_MOUSE_LL = 14;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_LBUTTONDOWN = 0x0201;
    private const int WM_RBUTTONDOWN = 0x0204;
    private const int WM_MBUTTONDOWN = 0x0207;
    private const int WM_XBUTTONDOWN = 0x020B;
    private const int WM_QUIT = 0x0012;
    private const uint PM_NOREMOVE = 0x0000;

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int x; public int y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public UIntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public POINT pt;
        public uint lPrivate;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, HookProc callback, IntPtr module, uint threadId);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hook, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")]
    private static extern int GetMessage(out MSG message, IntPtr hwnd, uint min, uint max);
    [DllImport("user32.dll")]
    private static extern bool PeekMessage(out MSG message, IntPtr hwnd, uint min, uint max, uint remove);
    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(ref MSG message);
    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(ref MSG message);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostThreadMessage(uint threadId, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
    private static extern IntPtr GetModuleHandle(string moduleName);
    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    // Keep delegates rooted for the entire lifetime of their native hooks.
    private static HookProc keyboardCallback = KeyboardHook;
    private static HookProc mouseCallback = MouseHook;
    private static IntPtr keyboardHook = IntPtr.Zero;
    private static IntPtr mouseHook = IntPtr.Zero;
    private static long keyboardEvents = 0;
    private static long mouseClicks = 0;
    private static Thread hookThread;
    private static uint hookThreadId = 0;
    private static readonly ManualResetEvent hookReady = new ManualResetEvent(false);
    private static volatile bool installSucceeded = false;

    private static IntPtr KeyboardHook(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0)
        {
            int m = message.ToInt32();
            if (m == WM_KEYDOWN || m == WM_SYSKEYDOWN)
                Interlocked.Increment(ref keyboardEvents);
        }
        // Never inspect KBDLLHOOKSTRUCT; forward the event unchanged.
        return CallNextHookEx(IntPtr.Zero, code, message, data);
    }

    private static IntPtr MouseHook(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0)
        {
            int m = message.ToInt32();
            if (m == WM_LBUTTONDOWN || m == WM_RBUTTONDOWN ||
                m == WM_MBUTTONDOWN || m == WM_XBUTTONDOWN)
                Interlocked.Increment(ref mouseClicks);
        }
        // Never inspect MSLLHOOKSTRUCT; coordinates and button identity are discarded.
        return CallNextHookEx(IntPtr.Zero, code, message, data);
    }

    private static void UninstallNativeHooks()
    {
        if (mouseHook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(mouseHook);
            mouseHook = IntPtr.Zero;
        }
        if (keyboardHook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(keyboardHook);
            keyboardHook = IntPtr.Zero;
        }
    }

    private static void HookThreadMain()
    {
        hookThreadId = GetCurrentThreadId();
        // Create this thread's message queue before signalling readiness.
        MSG ignored;
        PeekMessage(out ignored, IntPtr.Zero, 0, 0, PM_NOREMOVE);

        try
        {
            IntPtr module = GetModuleHandle(null);
            keyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL, keyboardCallback, module, 0);
            mouseHook = SetWindowsHookEx(WH_MOUSE_LL, mouseCallback, module, 0);
            installSucceeded = keyboardHook != IntPtr.Zero && mouseHook != IntPtr.Zero;
            if (!installSucceeded)
            {
                UninstallNativeHooks();
                hookReady.Set();
                return;
            }

            hookReady.Set();
            MSG message;
            int result;
            while ((result = GetMessage(out message, IntPtr.Zero, 0, 0)) > 0)
            {
                TranslateMessage(ref message);
                DispatchMessage(ref message);
            }
        }
        catch
        {
            installSucceeded = false;
            hookReady.Set();
        }
        finally
        {
            UninstallNativeHooks();
        }
    }

    public static bool InstallHooks()
    {
        if (hookThread != null && hookThread.IsAlive)
            return installSucceeded;

        hookReady.Reset();
        installSucceeded = false;
        hookThreadId = 0;
        hookThread = new Thread(HookThreadMain);
        hookThread.IsBackground = true;
        hookThread.Name = "Pomo aggregate input counter";
        hookThread.Start();

        if (!hookReady.WaitOne(5000))
        {
            UninstallHooks();
            return false;
        }
        return installSucceeded;
    }

    public static void UninstallHooks()
    {
        Thread worker = hookThread;
        if (worker != null && worker.IsAlive && hookThreadId != 0)
        {
            PostThreadMessage(hookThreadId, WM_QUIT, IntPtr.Zero, IntPtr.Zero);
            worker.Join(2000);
        }
        if (worker == null || !worker.IsAlive)
        {
            UninstallNativeHooks();
            hookThread = null;
            hookThreadId = 0;
            installSucceeded = false;
        }
    }

    public static long TakeKeyboardEvents()
    {
        return Interlocked.Exchange(ref keyboardEvents, 0);
    }

    public static long TakeMouseClicks()
    {
        return Interlocked.Exchange(ref mouseClicks, 0);
    }
}
'@ -Language CSharp
}

$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
function Write-JsonLine {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Record)
    $json = $Record | ConvertTo-Json -Compress -Depth 5
    [System.IO.File]::AppendAllText($script:OutputPath, $json + [Environment]::NewLine, $script:utf8NoBom)
}

function Get-ForegroundApp {
    [uint32]$processId = [PomoWindowsNative]::GetForegroundProcessId()
    if ($processId -eq 0) {
        return [pscustomobject]@{ App = 'unknown' }
    }

    try {
        $process = [System.Diagnostics.Process]::GetProcessById([int]$processId)
        try {
            return [pscustomobject]@{
                App = $process.ProcessName.ToLowerInvariant()
            }
        }
        finally {
            $process.Dispose()
        }
    }
    catch {
        return [pscustomobject]@{ App = 'unknown' }
    }
}

$lastApp = ''
$wasPaused = $false
$startedUtc = [DateTime]::UtcNow
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$inputHooksAvailable = [PomoWindowsInputNative]::InstallHooks()

Write-JsonLine ([ordered]@{
    ts = $startedUtc.ToString('o')
    type = 'monitor_start'
    source = 'windows'
    poll_interval_ms = $PollIntervalMs
    input_hooks_available = [bool]$inputHooksAvailable
})

Write-Host "Pomo Windows tracker is ACTIVE."
Write-Host "Output: $OutputPath"
Write-Host 'Records app names, idle duration, and aggregate keyboard/mouse counts only.'
Write-Host 'No key names, typed text, mouse coordinates, titles, or clipboard data are stored.'
if (-not $inputHooksAvailable) { Write-Warning 'Aggregate input hooks unavailable; app tracking will continue.' }
Write-Host 'Press Ctrl+C to stop.'

try {
    while ($true) {
        if ($DurationSeconds -gt 0 -and $stopwatch.Elapsed.TotalSeconds -ge $DurationSeconds) {
            break
        }
        if ($StopFile -and (Test-Path -LiteralPath $StopFile)) {
            break
        }

        $isPaused = $PauseFile -and (Test-Path -LiteralPath $PauseFile)
        if ($isPaused) {
            if (-not $wasPaused) {
                # Drain events collected before pause, then physically remove hooks.
                [PomoWindowsInputNative]::UninstallHooks()
                $keysBeforePause = [PomoWindowsInputNative]::TakeKeyboardEvents()
                $clicksBeforePause = [PomoWindowsInputNative]::TakeMouseClicks()
                if ($keysBeforePause -gt 0 -or $clicksBeforePause -gt 0) {
                    Write-JsonLine ([ordered]@{
                        ts = [DateTime]::UtcNow.ToString('o')
                        type = 'input_sample'
                        source = 'windows'
                        keyboard_events = $keysBeforePause
                        mouse_clicks = $clicksBeforePause
                    })
                }
                Write-JsonLine ([ordered]@{
                    ts = [DateTime]::UtcNow.ToString('o')
                    type = 'monitor_pause'
                    source = 'windows'
                })
                $wasPaused = $true
            }
            Start-Sleep -Milliseconds $PollIntervalMs
            continue
        }
        elseif ($wasPaused) {
            $inputHooksAvailable = [PomoWindowsInputNative]::InstallHooks()
            Write-JsonLine ([ordered]@{
                ts = [DateTime]::UtcNow.ToString('o')
                type = 'monitor_resume'
                source = 'windows'
                input_hooks_available = [bool]$inputHooksAvailable
            })
            $wasPaused = $false
        }

        $keyboardEvents = [PomoWindowsInputNative]::TakeKeyboardEvents()
        $mouseClicks = [PomoWindowsInputNative]::TakeMouseClicks()
        $now = [DateTime]::UtcNow
        $foreground = Get-ForegroundApp
        $idleMs = [PomoWindowsNative]::GetIdleMilliseconds()
        $isIdle = ($idleMs -ge ($IdleThresholdSeconds * 1000))

        if ($foreground.App -ne $lastApp) {
            Write-JsonLine ([ordered]@{
                ts = $now.ToString('o')
                type = 'app_change'
                source = 'windows'
                app = $foreground.App
            })
            $lastApp = $foreground.App
        }

        Write-JsonLine ([ordered]@{
            ts = $now.ToString('o')
            type = 'sample'
            source = 'windows'
            app = $foreground.App
            idle_ms = $idleMs
            idle = $isIdle
            keyboard_events = $keyboardEvents
            mouse_clicks = $mouseClicks
            input_hooks_available = [bool]$inputHooksAvailable
        })

        Start-Sleep -Milliseconds $PollIntervalMs
    }
}
finally {
    try {
        if (-not $wasPaused) {
            [PomoWindowsInputNative]::UninstallHooks()
            $finalKeys = [PomoWindowsInputNative]::TakeKeyboardEvents()
            $finalClicks = [PomoWindowsInputNative]::TakeMouseClicks()
            if ($finalKeys -gt 0 -or $finalClicks -gt 0) {
                Write-JsonLine ([ordered]@{
                    ts = [DateTime]::UtcNow.ToString('o')
                    type = 'input_sample'
                    source = 'windows'
                    keyboard_events = $finalKeys
                    mouse_clicks = $finalClicks
                })
            }
        }
    }
    finally {
        [PomoWindowsInputNative]::UninstallHooks()
        Write-JsonLine ([ordered]@{
            ts = [DateTime]::UtcNow.ToString('o')
            type = 'monitor_stop'
            source = 'windows'
            elapsed_seconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
        })
        Write-Host 'Pomo Windows tracker stopped.'
    }
}
