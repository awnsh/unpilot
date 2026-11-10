# Unpilot - https://github.com/awnsh/unpilot
# Not affiliated with Microsoft or Anthropic.
#
# The Copilot key sends Win+Shift+F23. A low-level keyboard hook swallows it and does the
# action in config.json instead: act as another key, press a shortcut, open an app or URL,
# type text, run a command, or (the default) toggle a liquid-glass Claude popup that asks
# Claude through the Claude Code CLI and streams the reply inline.

$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\UnpilotKey', [ref]$created)
if (-not $created) { exit }   # already running

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Web.Extensions
$refs = @(
    [System.Windows.Window].Assembly.Location,
    [System.Windows.Media.Brush].Assembly.Location,
    [System.Windows.Threading.Dispatcher].Assembly.Location,
    [System.Windows.Markup.XamlReader].Assembly.Location,
    [System.Xaml.XamlSchemaContext].Assembly.Location,
    [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location,
    [System.Linq.Enumerable].Assembly.Location
)

Add-Type -ReferencedAssemblies $refs -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Threading;

public static class UnpilotKey {
    const int WH_KEYBOARD_LL = 13, WM_KEYDOWN = 0x100, WM_KEYUP = 0x101, WM_SYSKEYDOWN = 0x104, WM_SYSKEYUP = 0x105;
    const uint LLKHF_INJECTED = 0x10, KEYEVENTF_KEYUP = 2;
    const int VK_F23 = 0x86, VK_LWIN = 0x5B, VK_RWIN = 0x5C, VK_LSHIFT = 0xA0, VK_RSHIFT = 0xA1, VK_MASK = 0xE8;

    [StructLayout(LayoutKind.Sequential)]
    struct KBDLLHOOKSTRUCT { public uint vkCode, scanCode, flags, time; public IntPtr extra; }
    delegate IntPtr HookProc(int n, IntPtr w, IntPtr l);

    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int id, HookProc fn, IntPtr mod, uint tid);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int n, IntPtr w, IntPtr l);
    [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string name);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

    static HookProc proc = Hook;
    static IntPtr hook;
    static bool f23Held, swallowWinUp, swallowShiftUp;
    static Dispatcher ui;
    static QuickWindow win;

    // What the Copilot key does, from config.json: claude | remap | app | url | keys | text | command
    static string action = "claude", target = "";
    static int remapVk;

    public static void Run(string act, string tgt) {
        SetProcessDPIAware();
        action = string.IsNullOrEmpty(act) ? "claude" : act.Trim().ToLowerInvariant();
        target = tgt ?? "";
        if (action == "remap") { remapVk = ParseKey(target.Trim()); if (remapVk == 0) action = "claude"; }
        ui = Dispatcher.CurrentDispatcher;
        if (action == "claude") win = new QuickWindow();
        hook = SetWindowsHookEx(WH_KEYBOARD_LL, proc, GetModuleHandle(null), 0);
        Dispatcher.Run();
    }

    static void K(int vk, bool up) { keybd_event((byte)vk, 0, up ? KEYEVENTF_KEYUP : 0, UIntPtr.Zero); }

    // ---------- Actions ----------
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint code, uint mapType);
    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [StructLayout(LayoutKind.Explicit, Size = 40)]
    struct INPUT {
        [FieldOffset(0)] public uint type;
        [FieldOffset(8)] public ushort wVk;
        [FieldOffset(10)] public ushort wScan;
        [FieldOffset(12)] public uint dwFlags;
        [FieldOffset(16)] public uint time;
        [FieldOffset(24)] public IntPtr extra;
    }

    static readonly Dictionary<string, int> Names = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase) {
        {"ctrl",0x11},{"control",0x11},{"lctrl",0xA2},{"rctrl",0xA3},{"rightctrl",0xA3},{"shift",0x10},{"lshift",0xA0},{"rshift",0xA1},
        {"alt",0x12},{"lalt",0xA4},{"ralt",0xA5},{"altgr",0xA5},{"win",0x5B},{"windows",0x5B},{"lwin",0x5B},{"rwin",0x5C},
        {"apps",0x5D},{"menu",0x5D},{"contextmenu",0x5D},{"esc",0x1B},{"escape",0x1B},{"enter",0x0D},{"return",0x0D},{"tab",0x09},
        {"space",0x20},{"backspace",0x08},{"delete",0x2E},{"del",0x2E},{"insert",0x2D},{"home",0x24},{"end",0x23},
        {"pageup",0x21},{"pgup",0x21},{"pagedown",0x22},{"pgdn",0x22},{"up",0x26},{"down",0x28},{"left",0x25},{"right",0x27},
        {"printscreen",0x2C},{"prtsc",0x2C},{"capslock",0x14},{"numlock",0x90},{"scrolllock",0x91},{"pause",0x13},
        {"mediaplaypause",0xB3},{"playpause",0xB3},{"medianext",0xB0},{"nexttrack",0xB0},{"mediaprev",0xB1},{"prevtrack",0xB1},
        {"mediastop",0xB2},{"volumemute",0xAD},{"mute",0xAD},{"volumedown",0xAE},{"volumeup",0xAF},
        {"browserback",0xA6},{"browserforward",0xA7},{"browserrefresh",0xA8},{"browserhome",0xAC},
        {".",0xBE},{"period",0xBE},{",",0xBC},{"comma",0xBC},{"/",0xBF},{";",0xBA},{"-",0xBD},{"=",0xBB},{"`",0xC0},{"[",0xDB},{"]",0xDD},{"\\",0xDC},{"'",0xDE}
    };
    static readonly HashSet<int> Extended = new HashSet<int> { 0xA3, 0xA5, 0x5B, 0x5C, 0x5D, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2D, 0x2E, 0x2C, 0x90,
        0xB0, 0xB1, 0xB2, 0xB3, 0xAD, 0xAE, 0xAF, 0xA6, 0xA7, 0xA8, 0xAC };

    static int ParseKey(string name) {
        string n = name.Replace(" ", "");
        int vk;
        if (Names.TryGetValue(n, out vk)) return vk;
        if (n.Length == 1 && char.IsLetterOrDigit(n[0])) return char.ToUpperInvariant(n[0]);
        if (n.Length >= 2 && (n[0] == 'F' || n[0] == 'f')) { int f; if (int.TryParse(n.Substring(1), out f) && f >= 1 && f <= 24) return 0x70 + f - 1; }
        return 0;
    }

    static INPUT KeyInput(int vk, bool up) {
        uint flags = up ? 2u : 0u;
        if (Extended.Contains(vk)) flags |= 1u;
        return new INPUT { type = 1, wVk = (ushort)vk, wScan = (ushort)MapVirtualKey((uint)vk, 0), dwFlags = flags };
    }

    static void Send(List<INPUT> list) { if (list.Count > 0) SendInput((uint)list.Count, list.ToArray(), Marshal.SizeOf(typeof(INPUT))); }

    static void SendKey(int vk, bool up) { Send(new List<INPUT> { KeyInput(vk, up) }); }

    // "Ctrl+Shift+Esc", "Win+Shift+S", "MediaPlayPause"
    static void SendCombo(string combo) {
        var vks = combo.Split('+').Select(s => ParseKey(s.Trim())).Where(v => v != 0).ToList();
        if (vks.Count == 0) return;
        var list = new List<INPUT>();
        foreach (var v in vks) list.Add(KeyInput(v, false));
        for (int i = vks.Count - 1; i >= 0; i--) list.Add(KeyInput(vks[i], true));
        Send(list);
    }

    static void TypeText(string text) {
        var list = new List<INPUT>();
        foreach (char c in text.Replace("\r\n", "\n")) {
            if (c == '\n') { list.Add(KeyInput(0x0D, false)); list.Add(KeyInput(0x0D, true)); continue; }
            list.Add(new INPUT { type = 1, wScan = c, dwFlags = 4 });        // KEYEVENTF_UNICODE
            list.Add(new INPUT { type = 1, wScan = c, dwFlags = 4 | 2 });
        }
        Send(list);
    }

    static void DoAction() {
        try {
            if (action == "app" || action == "url") {
                Process.Start(new ProcessStartInfo(target.Trim()) { UseShellExecute = true });
            } else if (action == "keys") {
                SendCombo(target);
            } else if (action == "text") {
                TypeText(target);
            } else if (action == "command") {
                string enc = Convert.ToBase64String(Encoding.Unicode.GetBytes(target));
                Process.Start(new ProcessStartInfo("powershell.exe", "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand " + enc) { UseShellExecute = false, CreateNoWindow = true });
            }
        } catch { }
    }

    static IntPtr Hook(int n, IntPtr w, IntPtr l) {
        if (n >= 0) {
            var k = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(l, typeof(KBDLLHOOKSTRUCT));
            if ((k.flags & LLKHF_INJECTED) == 0) {
                int msg = (int)w;
                bool down = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
                bool up = msg == WM_KEYUP || msg == WM_SYSKEYUP;
                if (k.vkCode == VK_F23) {
                    if (down && !f23Held) {
                        f23Held = true;
                        K(VK_MASK, false); K(VK_MASK, true);      // keep Start menu from opening
                        K(VK_LSHIFT, true); K(VK_LWIN, true);     // release Win+Shift
                        swallowWinUp = swallowShiftUp = true;
                        if (action == "claude") ui.BeginInvoke(new Action(delegate { win.Toggle(); }));
                        else if (action == "remap") SendKey(remapVk, false);   // hold: key goes down with the Copilot key
                        else ui.BeginInvoke(new Action(DoAction));
                    } else if (up) {
                        f23Held = false;
                        if (action == "remap") SendKey(remapVk, true);
                    }
                    return (IntPtr)1;
                }
                if (up && swallowWinUp && (k.vkCode == VK_LWIN || k.vkCode == VK_RWIN)) { swallowWinUp = false; return (IntPtr)1; }
                if (up && swallowShiftUp && (k.vkCode == VK_LSHIFT || k.vkCode == VK_RSHIFT)) { swallowShiftUp = false; return (IntPtr)1; }
            }
        }
        return CallNextHookEx(hook, n, w, l);
    }
}

public class QuickWindow : Window {
    const string Model = "sonnet";
    const string SysPrompt = "You are Claude, answering a quick question typed into a small popup on the user's Windows desktop. Be concise and direct: lead with the answer and keep it short. Use plain text only, with no markdown headings, bold, or tables; simple dashes for lists are fine.";

    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);

    // Glass: Windows acrylic blur behind the window, clipped to a pill shape.
    [StructLayout(LayoutKind.Sequential)] struct AccentPolicy { public int AccentState, AccentFlags, GradientColor, AnimationId; }
    [StructLayout(LayoutKind.Sequential)] struct WinCompAttrData { public int Attribute; public IntPtr Data; public int SizeOfData; }
    [DllImport("user32.dll")] static extern int SetWindowCompositionAttribute(IntPtr h, ref WinCompAttrData d);
    [DllImport("gdi32.dll")] static extern IntPtr CreateRoundRectRgn(int x1, int y1, int x2, int y2, int w, int h);
    [DllImport("user32.dll")] static extern int SetWindowRgn(IntPtr h, IntPtr rgn, bool redraw);

    const double Radius = 30, Shadow = 32, CardWidth = 760, Pad = 60, MaxCardHeight = 760;
    Image backdrop;

    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleBitmap(IntPtr dc, int w, int h);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool BitBlt(IntPtr dst, int x, int y, int w, int h, IntPtr src, int sx, int sy, uint rop);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
    [DllImport("gdi32.dll")] static extern int GetDeviceCaps(IntPtr dc, int index);

    // Snapshot the screen area behind the card (plus padding so the blur has no dark edges).
    void CaptureBackdrop() {
        IntPtr screen = GetDC(IntPtr.Zero);
        try {
            double s = GetDeviceCaps(screen, 88) / 96.0;   // LOGPIXELSX
            double capW = CardWidth + 2 * Pad, capH = MaxCardHeight + 2 * Pad;
            int x = (int)Math.Round((Left + Shadow - Pad) * s), y = (int)Math.Round((Top + Shadow - Pad) * s);
            int w = (int)Math.Round(capW * s), h = (int)Math.Round(capH * s);
            IntPtr mem = CreateCompatibleDC(screen);
            IntPtr bmp = CreateCompatibleBitmap(screen, w, h);
            IntPtr old = SelectObject(mem, bmp);
            BitBlt(mem, 0, 0, w, h, screen, x, y, 0x00CC0020 | 0x40000000);   // SRCCOPY | CAPTUREBLT
            SelectObject(mem, old);
            var src = Imaging.CreateBitmapSourceFromHBitmap(bmp, IntPtr.Zero, Int32Rect.Empty, System.Windows.Media.Imaging.BitmapSizeOptions.FromEmptyOptions());
            src.Freeze();
            DeleteObject(bmp); DeleteDC(mem);
            backdrop.Source = src;
            backdrop.Width = capW; backdrop.Height = capH;
            Canvas.SetLeft(backdrop, -Pad); Canvas.SetTop(backdrop, -Pad);
        } catch { backdrop.Source = null; }
        finally { ReleaseDC(IntPtr.Zero, screen); }
    }
    const int GlassTint = unchecked((int)0x26141312);   // AABBGGRR: smoky, mostly clear

    void EnableGlass() {
        var h = new WindowInteropHelper(this).Handle;
        var accent = new AccentPolicy { AccentState = 4, AccentFlags = 2, GradientColor = GlassTint };
        int size = Marshal.SizeOf(accent);
        IntPtr p = Marshal.AllocHGlobal(size);
        Marshal.StructureToPtr(accent, p, false);
        var data = new WinCompAttrData { Attribute = 19, Data = p, SizeOfData = size };
        if (SetWindowCompositionAttribute(h, ref data) == 0) {   // older Windows: plain blur
            accent.AccentState = 3; Marshal.StructureToPtr(accent, p, true);
            SetWindowCompositionAttribute(h, ref data);
        }
        Marshal.FreeHGlobal(p);
    }

    void ApplyRegion() {
        var h = new WindowInteropHelper(this).Handle;
        if (h == IntPtr.Zero || ActualWidth == 0) return;
        var src = PresentationSource.FromVisual(this);
        double s = src != null ? src.CompositionTarget.TransformToDevice.M11 : 1;
        int w = (int)Math.Round(ActualWidth * s), ht = (int)Math.Round(ActualHeight * s), r = (int)Math.Round(Radius * 2 * s);
        SetWindowRgn(h, CreateRoundRectRgn(0, 0, w + 1, ht + 1, r, r), true);
    }

    static LinearGradientBrush Vert(string top, string bottom) {
        return new LinearGradientBrush((Color)ColorConverter.ConvertFromString(top), (Color)ColorConverter.ConvertFromString(bottom), 90);
    }

    TextBox input;
    TextBlock placeholder, hint;
    StackPanel convo;
    ScrollViewer scroll;
    Border divider;
    Process proc;
    string sessionId;
    int gen;

    // A slim, rounded, translucent scrollbar instead of the default blocky one.
    static Style ThinScrollBar() {
        string xaml =
            "<Style xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml' TargetType='ScrollBar'>" +
            "<Setter Property='Width' Value='8'/><Setter Property='MinWidth' Value='8'/>" +
            "<Setter Property='Template'><Setter.Value><ControlTemplate TargetType='ScrollBar'>" +
            "<Grid Background='Transparent'><Track x:Name='PART_Track' IsDirectionReversed='True'><Track.Thumb>" +
            "<Thumb><Thumb.Template><ControlTemplate TargetType='Thumb'>" +
            "<Border x:Name='b' CornerRadius='3' Width='5' Margin='0,2' HorizontalAlignment='Center' Background='#47FFFFFF'/>" +
            "<ControlTemplate.Triggers>" +
            "<Trigger Property='IsMouseOver' Value='True'><Setter TargetName='b' Property='Background' Value='#8CFFFFFF'/></Trigger>" +
            "<Trigger Property='IsDragging' Value='True'><Setter TargetName='b' Property='Background' Value='#B3FFFFFF'/></Trigger>" +
            "</ControlTemplate.Triggers></ControlTemplate></Thumb.Template></Thumb>" +
            "</Track.Thumb></Track></Grid></ControlTemplate></Setter.Value></Setter></Style>";
        return (Style)System.Windows.Markup.XamlReader.Parse(xaml);
    }

    static Brush B(string hex) { return (Brush)new BrushConverter().ConvertFromString(hex); }

    public QuickWindow() {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        ResizeMode = ResizeMode.NoResize;
        Width = CardWidth + 2 * Shadow;
        SizeToContent = SizeToContent.Height;
        WindowStartupLocation = WindowStartupLocation.Manual;
        FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI");

        // Glass layers: sheen fill fading top->bottom, bright specular rim, soft inner glow line.
        var card = new Border {
            CornerRadius = new CornerRadius(Radius),
            Background = Vert("#1AFFFFFF", "#03FFFFFF"),
            BorderBrush = Vert("#A0FFFFFF", "#22FFFFFF"),
            BorderThickness = new Thickness(1.2)
        };
        var inner = new Border {
            CornerRadius = new CornerRadius(Radius - 1),
            BorderBrush = Vert("#30FFFFFF", "#00FFFFFF"),
            BorderThickness = new Thickness(0, 1.5, 0, 0),
            Padding = new Thickness(22, 13, 22, 14)
        };
        card.Child = inner;
        var root = new StackPanel();
        TextElement.SetForeground(root, Brushes.White);
        var textShadow = new DropShadowEffect { BlurRadius = 6, ShadowDepth = 0, Opacity = 0.55, Color = Colors.Black };
        root.Effect = textShadow;

        var row = new Grid();
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition());
        var spark = new TextBlock {
            Text = "✳", Foreground = B("#F0906C"), FontSize = 22, FontFamily = new FontFamily("Segoe UI Symbol"),
            VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 12, 0)
        };
        Grid.SetColumn(spark, 0);
        row.Children.Add(spark);

        var inputHost = new Grid();
        Grid.SetColumn(inputHost, 1);
        placeholder = new TextBlock {
            Text = "Ask Claude…", Foreground = B("#A6FFFFFF"), FontSize = 17,
            VerticalAlignment = VerticalAlignment.Center, IsHitTestVisible = false, Margin = new Thickness(2, 0, 0, 0)
        };
        input = new TextBox {
            Background = Brushes.Transparent, BorderThickness = new Thickness(0), Foreground = B("#FFFFFFFF"),
            CaretBrush = B("#FFFFFFFF"), FontSize = 17, TextWrapping = TextWrapping.Wrap, AcceptsReturn = false,
            VerticalContentAlignment = VerticalAlignment.Center, Padding = new Thickness(0, 4, 0, 4)
        };
        input.TextChanged += delegate { placeholder.Visibility = input.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed; };
        inputHost.Children.Add(placeholder);
        inputHost.Children.Add(input);
        row.Children.Add(inputHost);
        root.Children.Add(row);

        divider = new Border { Height = 1, Background = B("#38FFFFFF"), Margin = new Thickness(0, 12, 0, 4), Visibility = Visibility.Collapsed };
        root.Children.Add(divider);

        convo = new StackPanel { Margin = new Thickness(0, 0, 10, 0) };
        scroll = new ScrollViewer {
            Content = convo, MaxHeight = 480, VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Visibility = Visibility.Collapsed
        };
        scroll.Resources.Add(typeof(System.Windows.Controls.Primitives.ScrollBar), ThinScrollBar());
        root.Children.Add(scroll);

        hint = new TextBlock {
            Text = "Enter to ask a follow-up  ·  Ctrl+Enter to save in Claude  ·  Esc to close", Foreground = B("#99FFFFFF"), FontSize = 11.5,
            Margin = new Thickness(0, 10, 0, 0), HorizontalAlignment = HorizontalAlignment.Right, Visibility = Visibility.Collapsed
        };
        root.Children.Add(hint);

        inner.Child = root;

        // Layers, back to front: soft shadow, blurred snapshot of the screen behind (clipped to a
        // smooth anti-aliased pill), smoky tint, then the sheen/rim card with the content.
        var glass = new Grid { Margin = new Thickness(Shadow) };
        var shadow = new Border {
            CornerRadius = new CornerRadius(Radius), Background = B("#FF101010"),
            Effect = new DropShadowEffect { BlurRadius = 32, ShadowDepth = 8, Opacity = 0.42, Color = Colors.Black }
        };
        var backdropCanvas = new Canvas();
        backdrop = new Image { Stretch = Stretch.Fill, Effect = new BlurEffect { Radius = 30, KernelType = KernelType.Gaussian } };
        backdropCanvas.Children.Add(backdrop);
        var clipped = new Grid();
        clipped.Children.Add(backdropCanvas);
        clipped.Children.Add(new Border { Background = B("#D0121110") });   // dark tint: keeps white text readable over bright pages
        clipped.SizeChanged += delegate {
            clipped.Clip = new RectangleGeometry(new Rect(0, 0, clipped.ActualWidth, clipped.ActualHeight), Radius, Radius);
        };
        glass.Children.Add(shadow);
        glass.Children.Add(clipped);
        glass.Children.Add(card);
        Content = glass;
        PreviewKeyDown += OnKey;
        Deactivated += delegate { if (IsVisible) HideAndReset(); };
    }

    void OnKey(object s, KeyEventArgs e) {
        if (e.Key == Key.Escape) { HideAndReset(); e.Handled = true; }
        else if (e.Key == Key.Enter && input.IsKeyboardFocusWithin && (Keyboard.Modifiers & ModifierKeys.Control) != 0) { SendToClaudeApp(); e.Handled = true; }
        else if (e.Key == Key.Enter && input.IsKeyboardFocusWithin && (Keyboard.Modifiers & ModifierKeys.Shift) == 0) { Send(); e.Handled = true; }
    }

    public void Toggle() {
        if (IsVisible) { HideAndReset(); return; }
        var wa = SystemParameters.WorkArea;
        Left = wa.Left + (wa.Width - Width) / 2;
        Top = wa.Top + wa.Height * 0.2 - Shadow;
        CaptureBackdrop();   // must happen before Show so the snapshot doesn't include the popup
        Show();
        var h = new WindowInteropHelper(this).Handle;
        IntPtr fg = GetForegroundWindow();
        uint fgThread = GetWindowThreadProcessId(fg, IntPtr.Zero), me = GetCurrentThreadId();
        if (fgThread != me) AttachThreadInput(me, fgThread, true);
        SetForegroundWindow(h); BringWindowToTop(h);
        if (fgThread != me) AttachThreadInput(me, fgThread, false);
        Activate();
        input.Focus();
        Keyboard.Focus(input);
    }

    void HideAndReset() {
        gen++;
        KillProc();
        sessionId = null;
        convo.Children.Clear();
        scroll.Visibility = divider.Visibility = hint.Visibility = Visibility.Collapsed;
        input.Text = "";
        Hide();
        backdrop.Source = null;
    }

    void KillProc() {
        try { if (proc != null && !proc.HasExited) proc.Kill(); } catch { }
        proc = null;
    }

    static string ClaudeExe() {
        string home = Environment.GetEnvironmentVariable("USERPROFILE") ?? "";
        string local = Environment.GetEnvironmentVariable("LOCALAPPDATA") ?? "";
        // 1. Standalone Claude Code install (claude.ai/install)
        string own = Path.Combine(home, ".local\\bin\\claude.exe");
        if (File.Exists(own)) return own;
        // 2. claude.exe anywhere on PATH
        foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';')) {
            try { var p = Path.Combine(dir.Trim(), "claude.exe"); if (File.Exists(p)) return p; } catch { }
        }
        // 3. The copy bundled with the Claude desktop app (newest version wins)
        var roots = new List<DirectoryInfo>();
        try {
            var cd = new DirectoryInfo(Path.Combine(local, "Claude-Data"));
            if (cd.Exists) roots.AddRange(cd.GetDirectories().Select(d => new DirectoryInfo(Path.Combine(d.FullName, "claude-code"))));
        } catch { }
        try {
            var pk = new DirectoryInfo(Path.Combine(local, "Packages"));
            if (pk.Exists) roots.AddRange(pk.GetDirectories("Claude_*").Select(d => new DirectoryInfo(Path.Combine(d.FullName, "LocalCache\\Roaming\\Claude\\claude-code"))));
        } catch { }
        roots.Add(new DirectoryInfo(Path.Combine(Environment.GetEnvironmentVariable("APPDATA") ?? "", "Claude\\claude-code")));
        try {
            var best = roots.Where(d => d.Exists)
                .SelectMany(d => d.GetFiles("claude.exe", SearchOption.AllDirectories))
                .OrderByDescending(f => f.LastWriteTimeUtc)
                .FirstOrDefault();
            if (best != null) return best.FullName;
        } catch { }
        return "claude.exe";
    }

    void Send() {
        string q = input.Text.Trim();
        if (q.Length == 0 || proc != null) return;
        input.Text = "";

        var qText = new TextBlock { Text = q, Foreground = B("#C2FFFFFF"), FontSize = 13.5, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 4) };
        var answer = new TextBox {
            Text = "Thinking…", IsReadOnly = true, BorderThickness = new Thickness(0), Background = Brushes.Transparent,
            Foreground = B("#A6FFFFFF"), FontSize = 15, TextWrapping = TextWrapping.Wrap, Padding = new Thickness(0)
        };
        convo.Children.Add(qText);
        convo.Children.Add(answer);
        scroll.Visibility = divider.Visibility = hint.Visibility = Visibility.Visible;
        scroll.ScrollToEnd();

        string dir = Path.Combine(Path.GetTempPath(), "Unpilot");
        Directory.CreateDirectory(dir);
        var psi = new ProcessStartInfo(ClaudeExe()) {
            Arguments = "-p --output-format stream-json --verbose --include-partial-messages --tools \"\" --strict-mcp-config --model " + Model
                + " --system-prompt \"" + SysPrompt + "\"" + (sessionId != null ? " --resume " + sessionId : ""),
            UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = dir,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
        };
        psi.EnvironmentVariables.Remove("CLAUDECODE");

        int myGen = gen;
        var raw = new StringBuilder();
        var streamed = new StringBuilder();
        Process p;
        try { p = Process.Start(psi); }
        catch (Exception ex) { answer.Text = "Couldn't start Claude: " + ex.Message; return; }
        proc = p;
        p.ErrorDataReceived += (s2, e2) => { if (e2.Data != null) lock (raw) raw.AppendLine(e2.Data); };
        p.BeginErrorReadLine();
        var bytes = new UTF8Encoding(false).GetBytes(q);
        p.StandardInput.BaseStream.Write(bytes, 0, bytes.Length);
        p.StandardInput.Close();

        var t = new Thread(() => {
            var json = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
            string resultText = null; bool isError = false;
            try {
                string line;
                while ((line = p.StandardOutput.ReadLine()) != null) {
                    if (!line.StartsWith("{")) { lock (raw) raw.AppendLine(line); continue; }
                    Dictionary<string, object> d;
                    try { d = json.Deserialize<Dictionary<string, object>>(line); } catch { continue; }
                    object type; d.TryGetValue("type", out type);
                    object sid;
                    if (d.TryGetValue("session_id", out sid) && sid is string) {
                        string sidS = (string)sid;
                        Dispatcher.BeginInvoke(new Action(delegate { if (gen == myGen) sessionId = sidS; }));
                    }
                    if ("stream_event".Equals(type)) {
                        var ev = d["event"] as Dictionary<string, object>;
                        if (ev == null || !"content_block_delta".Equals(Get(ev, "type"))) continue;
                        var delta = Get(ev, "delta") as Dictionary<string, object>;
                        if (delta == null || !"text_delta".Equals(Get(delta, "type"))) continue;
                        string chunk = Get(delta, "text") as string;
                        if (string.IsNullOrEmpty(chunk)) continue;
                        streamed.Append(chunk);
                        string snapshot = streamed.ToString().TrimStart();
                        Dispatcher.BeginInvoke(new Action(delegate {
                            if (gen != myGen) return;
                            answer.Foreground = B("#FFFFFFFF");
                            answer.Text = snapshot;
                            scroll.ScrollToEnd();
                        }));
                    } else if ("result".Equals(type)) {
                        resultText = Get(d, "result") as string;
                        isError = true.Equals(Get(d, "is_error"));
                    }
                }
                p.WaitForExit();
            } catch { }
            string rawS; lock (raw) rawS = raw.ToString().Trim();
            string streamedS = streamed.ToString().Trim();
            Dispatcher.BeginInvoke(new Action(delegate {
                if (gen != myGen) return;
                proc = null;
                string final = streamedS;
                if (isError || final.Length == 0) final = !string.IsNullOrEmpty(resultText) ? resultText.Trim() : rawS;
                if (final.IndexOf("Not logged in", StringComparison.OrdinalIgnoreCase) >= 0)
                    final = "The Claude popup isn't signed in yet. Open PowerShell, run: claude auth login   then try again.";
                if (final.Length == 0) final = "No reply came back. Try again.";
                answer.Foreground = isError || streamedS.Length == 0 ? B("#E0A49A") : B("#FFFFFFFF");
                if (!isError && streamedS.Length > 0) answer.Foreground = B("#FFFFFFFF");
                answer.Text = final;
                scroll.ScrollToEnd();
                input.Focus();
            }));
        });
        t.IsBackground = true;
        t.Start();
    }

    // Ctrl+Enter: hand the question to the Claude desktop app's own Quick Entry so it's saved to your chat history.
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll", EntryPoint = "GetWindowThreadProcessId")] static extern uint GetWindowPid(IntPtr h, out uint pid);

    static void Key2(int vk, bool up) { keybd_event((byte)vk, 0, up ? 2u : 0u, UIntPtr.Zero); }

    static HashSet<uint> ClaudeAppPids() {
        var set = new HashSet<uint>();
        foreach (var p in Process.GetProcessesByName("claude")) {
            bool isApp = false;
            try { isApp = p.MainWindowHandle != IntPtr.Zero; } catch { }
            if (!isApp) { try { isApp = p.MainModule.FileName.IndexOf("\\WindowsApps\\", StringComparison.OrdinalIgnoreCase) >= 0; } catch { } }
            if (isApp) set.Add((uint)p.Id);
        }
        return set;
    }

    void SendToClaudeApp() {
        string q = input.Text.Trim();
        if (q.Length == 0) return;
        var pids = ClaudeAppPids();
        if (pids.Count == 0) {
            convo.Children.Add(new TextBlock { Text = "Open the Claude app first, then press Ctrl+Enter again to save this question there.",
                Foreground = B("#E0A49A"), FontSize = 13.5, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 0) });
            scroll.Visibility = divider.Visibility = Visibility.Visible;
            return;
        }
        HideAndReset();
        var t = new Thread(() => {
            // wait for Ctrl and Enter to be let go so they don't mix with the keys we send
            for (int i = 0; i < 40 && ((GetAsyncKeyState(0x11) & 0x8000) != 0 || (GetAsyncKeyState(0x0D) & 0x8000) != 0); i++) Thread.Sleep(50);
            string saved = null;
            try { if (Clipboard.ContainsText()) saved = Clipboard.GetText(); } catch { }
            bool clipOk = false;
            for (int i = 0; i < 5 && !clipOk; i++) { try { Clipboard.SetText(q); clipOk = true; } catch { Thread.Sleep(60); } }
            if (!clipOk) return;

            Key2(0x11, false); Key2(0x12, false); Key2(0x20, false); Key2(0x20, true); Key2(0x12, true); Key2(0x11, true);  // Ctrl+Alt+Space

            bool ready = false;
            for (int i = 0; i < 40 && !ready; i++) {   // up to 2s for Claude's Quick Entry to take focus
                Thread.Sleep(50);
                uint pid; GetWindowPid(GetForegroundWindow(), out pid);
                ready = pids.Contains(pid);
            }
            if (ready) {
                Thread.Sleep(250);
                Key2(0x11, false); Key2(0x56, false); Key2(0x56, true); Key2(0x11, true);   // Ctrl+V
                Thread.Sleep(200);
                Key2(0x0D, false); Key2(0x0D, true);                                        // Enter
            }
            Thread.Sleep(600);
            try { if (saved != null) Clipboard.SetText(saved); } catch { }
        });
        t.SetApartmentState(ApartmentState.STA);
        t.IsBackground = true;
        t.Start();
    }

    static object Get(Dictionary<string, object> d, string k) { object v; return d.TryGetValue(k, out v) ? v : null; }
}
'@

# config.json (next to this script) says what the key does. No config = the Claude popup.
$action = 'claude'; $target = ''
$cfgPath = Join-Path $PSScriptRoot 'config.json'
if (Test-Path $cfgPath) {
    try {
        $cfg = [IO.File]::ReadAllText($cfgPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($cfg.action) { $action = [string]$cfg.action }
        if ($cfg.target) { $target = [string]$cfg.target }
    } catch { }
}
[UnpilotKey]::Run($action, $target)
