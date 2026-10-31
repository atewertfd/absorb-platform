#include "windows_shell.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cwchar>
#include <vector>

#include "resource.h"
#include "single_instance.h"
#include "utils.h"

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr UINT kTrayCallbackMessage = WM_APP + 0x3A1;
constexpr UINT kTrayIconId = 1;
constexpr UINT_PTR kExitTimerId = 0xAB51;
// Upper bound for the Dart side to save progress before the process ends.
constexpr UINT kExitTimeoutMs = 4000;
constexpr UINT kThumbRewind = 0xAB60;
constexpr UINT kThumbPlayPause = 0xAB61;
constexpr UINT kThumbForward = 0xAB62;
constexpr UINT kMenuShow = 1;
constexpr UINT kMenuPlayPause = 2;
constexpr UINT kMenuQuit = 3;

constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kStartupApprovedKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run";
constexpr wchar_t kPersonalizeKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";

const wchar_t* RunValueName(bool probe) {
  return probe ? L"Absorb Plus (probe)" : L"Absorb Plus";
}

bool ReadSetting(const wchar_t* name, bool fallback) {
  DWORD value = 0;
  DWORD size = sizeof(value);
  if (RegGetValueW(HKEY_CURRENT_USER, Win32Window::StateRegistryKey().c_str(),
                   name, RRF_RT_REG_DWORD, nullptr, &value,
                   &size) != ERROR_SUCCESS) {
    return fallback;
  }
  return value != 0;
}

void WriteSetting(const wchar_t* name, bool value) {
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER,
                      Win32Window::StateRegistryKey().c_str(), 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return;
  }
  const DWORD data = value ? 1 : 0;
  RegSetValueExW(key, name, 0, REG_DWORD, reinterpret_cast<const BYTE*>(&data),
                 sizeof(data));
  RegCloseKey(key);
}

std::wstring ExecutablePath() {
  std::vector<wchar_t> buffer(MAX_PATH);
  for (;;) {
    const DWORD length = GetModuleFileNameW(
        nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0) return L"";
    if (length < buffer.size()) return std::wstring(buffer.data(), length);
    buffer.resize(buffer.size() * 2);
  }
}

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) return L"";
  const int length =
      MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                          static_cast<int>(utf8.size()), nullptr, 0);
  if (length <= 0) return L"";
  std::wstring result(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      result.data(), length);
  return result;
}

std::string Utf8(const std::wstring& text) {
  return text.empty() ? std::string() : Utf8FromUtf16(text.c_str());
}

const EncodableValue* Arg(const EncodableValue* args, const char* key) {
  const auto* map = args != nullptr ? std::get_if<EncodableMap>(args) : nullptr;
  if (map == nullptr) return nullptr;
  auto it = map->find(EncodableValue(key));
  return it == map->end() ? nullptr : &it->second;
}

std::optional<bool> BoolArg(const EncodableValue* args, const char* key) {
  const EncodableValue* value = Arg(args, key);
  if (value == nullptr) return std::nullopt;
  if (const auto* b = std::get_if<bool>(value)) return *b;
  return std::nullopt;
}

std::optional<double> DoubleArg(const EncodableValue* args, const char* key) {
  const EncodableValue* value = Arg(args, key);
  if (value == nullptr) return std::nullopt;
  if (const auto* d = std::get_if<double>(value)) return *d;
  if (const auto* i = std::get_if<int32_t>(value)) return *i;
  if (const auto* l = std::get_if<int64_t>(value)) {
    return static_cast<double>(*l);
  }
  return std::nullopt;
}

std::optional<std::string> StringArg(const EncodableValue* args,
                                     const char* key) {
  const EncodableValue* value = Arg(args, key);
  if (value == nullptr) return std::nullopt;
  if (const auto* s = std::get_if<std::string>(value)) return *s;
  return std::nullopt;
}

// Thumbnail toolbar glyphs, drawn in code so no image assets are needed.
enum class Glyph { kRewind, kPlay, kPause, kForward };

struct Vec2 {
  double x;
  double y;
};

bool InTriangle(double x, double y, Vec2 a, Vec2 b, Vec2 c) {
  auto side = [x, y](Vec2 p, Vec2 q) {
    return (x - q.x) * (p.y - q.y) - (p.x - q.x) * (y - q.y);
  };
  const double d1 = side(a, b);
  const double d2 = side(b, c);
  const double d3 = side(c, a);
  const bool negative = d1 < 0 || d2 < 0 || d3 < 0;
  const bool positive = d1 > 0 || d2 > 0 || d3 > 0;
  return !(negative && positive);
}

bool InGlyph(Glyph glyph, double x, double y) {
  switch (glyph) {
    case Glyph::kPlay:
      return InTriangle(x, y, {0.30, 0.18}, {0.30, 0.82}, {0.82, 0.50});
    case Glyph::kPause:
      return y >= 0.20 && y <= 0.80 &&
             ((x >= 0.26 && x <= 0.43) || (x >= 0.57 && x <= 0.74));
    case Glyph::kRewind:
      return InTriangle(x, y, {0.50, 0.24}, {0.50, 0.76}, {0.10, 0.50}) ||
             InTriangle(x, y, {0.90, 0.24}, {0.90, 0.76}, {0.50, 0.50});
    case Glyph::kForward:
      return InTriangle(x, y, {0.10, 0.24}, {0.10, 0.76}, {0.50, 0.50}) ||
             InTriangle(x, y, {0.50, 0.24}, {0.50, 0.76}, {0.90, 0.50});
  }
  return false;
}

// A 32-bit icon with antialiased alpha (4x4 samples per pixel).
HICON CreateGlyphIcon(Glyph glyph, int size, uint32_t rgb) {
  if (size <= 0) return nullptr;
  BITMAPINFO info = {};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = size;
  info.bmiHeader.biHeight = -size;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  HDC screen = GetDC(nullptr);
  HBITMAP color =
      CreateDIBSection(screen, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  ReleaseDC(nullptr, screen);
  if (color == nullptr || bits == nullptr) {
    if (color != nullptr) DeleteObject(color);
    return nullptr;
  }
  auto* pixels = static_cast<uint32_t*>(bits);
  constexpr int kSamples = 4;
  for (int y = 0; y < size; ++y) {
    for (int x = 0; x < size; ++x) {
      int hits = 0;
      for (int sy = 0; sy < kSamples; ++sy) {
        for (int sx = 0; sx < kSamples; ++sx) {
          const double px = (x + (sx + 0.5) / kSamples) / size;
          const double py = (y + (sy + 0.5) / kSamples) / size;
          if (InGlyph(glyph, px, py)) ++hits;
        }
      }
      const uint32_t alpha =
          static_cast<uint32_t>(hits * 255 / (kSamples * kSamples));
      pixels[y * size + x] = alpha == 0 ? 0 : (alpha << 24) | (rgb & 0xFFFFFF);
    }
  }
  // Monochrome rows are WORD aligned; an all-zero mask defers to the alpha.
  std::vector<BYTE> mask_bits(static_cast<size_t>((size + 15) / 16 * 2 * size),
                              0);
  HBITMAP mask = CreateBitmap(size, size, 1, 1, mask_bits.data());
  ICONINFO icon_info = {TRUE, 0, 0, mask, color};
  HICON icon = mask != nullptr ? CreateIconIndirect(&icon_info) : nullptr;
  if (mask != nullptr) DeleteObject(mask);
  DeleteObject(color);
  return icon;
}

bool TaskbarUsesLightTheme() {
  DWORD value = 0;
  DWORD size = sizeof(value);
  if (RegGetValueW(HKEY_CURRENT_USER, kPersonalizeKey, L"SystemUsesLightTheme",
                   RRF_RT_REG_DWORD, nullptr, &value,
                   &size) != ERROR_SUCCESS) {
    return false;
  }
  return value != 0;
}

// Milliseconds since this process was created, for the startup timing line
// in the log (lib/services/startup_timing.dart); -1 if Windows won't say.
int64_t ProcessAgeMs() {
  FILETIME created, exited, kernel, user, now;
  if (!GetProcessTimes(GetCurrentProcess(), &created, &exited, &kernel,
                       &user)) {
    return -1;
  }
  GetSystemTimeAsFileTime(&now);
  ULARGE_INTEGER c, n;
  c.LowPart = created.dwLowDateTime;
  c.HighPart = created.dwHighDateTime;
  n.LowPart = now.dwLowDateTime;
  n.HighPart = now.dwHighDateTime;
  return static_cast<int64_t>((n.QuadPart - c.QuadPart) / 10000);
}

}  // namespace

WindowsShell::WindowsShell(Win32Window* window,
                           flutter::BinaryMessenger* messenger,
                           const LaunchOptions& launch)
    : window_(window), launch_(launch) {
  taskbar_created_message_ = RegisterWindowMessageW(L"TaskbarCreated");
  taskbar_button_created_message_ =
      RegisterWindowMessageW(L"TaskbarButtonCreated");
  quit_request_message_ = RegisterWindowMessageW(L"AbsorbPlus.QuitRequest");

  HWND hwnd = window_->GetHandle();
  // Explorer must reach these even if Absorb Plus runs elevated.
  ChangeWindowMessageFilterEx(hwnd, taskbar_button_created_message_,
                              MSGFLT_ALLOW, nullptr);
  ChangeWindowMessageFilterEx(hwnd, WM_COMMAND, MSGFLT_ALLOW, nullptr);

  close_to_tray_ = ReadSetting(L"closeToTray", false);
  start_minimized_ = ReadSetting(L"startMinimized", false);
  always_on_top_ = ReadSetting(L"alwaysOnTop", false);
  keep_awake_ = ReadSetting(L"keepAwake", true);
  if (always_on_top_) window_->SetAlwaysOnTop(true);
  if (close_to_tray_) AddTrayIcon();
  CreateThumbIcons();

  shell_channel_ = std::make_unique<Channel>(
      messenger, "absorb/windows_shell",
      &flutter::StandardMethodCodec::GetInstance());
  shell_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        HandleShellCall(call, std::move(result));
      });

  // lib/services/screen_wake.dart: "Keep screen on" (display and system).
  screen_wake_channel_ = std::make_unique<Channel>(
      messenger, "com.absorb.screen_wake",
      &flutter::StandardMethodCodec::GetInstance());
  screen_wake_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() != "set") {
          result->NotImplemented();
          return;
        }
        display_hold_ = BoolArg(call.arguments(), "on").value_or(false);
        UpdateExecutionState();
        result->Success();
      });
}

WindowsShell::~WindowsShell() {
  if (shell_channel_) shell_channel_->SetMethodCallHandler(nullptr);
  if (screen_wake_channel_) screen_wake_channel_->SetMethodCallHandler(nullptr);
  RemoveTrayIcon();
  SetThreadExecutionState(ES_CONTINUOUS);
  DestroyThumbIcons();
  if (tray_icon_ != nullptr) DestroyIcon(tray_icon_);
}

std::optional<LRESULT> WindowsShell::HandleMessage(HWND hwnd, UINT message,
                                                   WPARAM wparam,
                                                   LPARAM lparam) {
  if (message != 0 && message == taskbar_button_created_message_) {
    OnTaskbarButtonCreated();
    return std::nullopt;
  }
  if (message != 0 && message == taskbar_created_message_) {
    // Explorer restarted: the tray icon is gone and must be added again.
    tray_added_ = false;
    if (close_to_tray_ && exit_state_ == ExitState::kRunning) AddTrayIcon();
    return std::nullopt;
  }
  if (message != 0 && message == quit_request_message_) {
    // tool/dev.ps1 and other tools: quit even when hidden in the tray.
    RequestQuit();
    return 0;
  }

  switch (message) {
    case WM_CLOSE:
      if (exit_state_ != ExitState::kRunning) return 0;
      if (close_to_tray_ && !quit_requested_) {
        HideToTray();
        return 0;
      }
      BeginExit(false);
      return 0;

    case WM_QUERYENDSESSION:
      return TRUE;

    case WM_ENDSESSION:
      // Sign-out, shutdown or an installer's Restart Manager: quit for real,
      // tray or not, and save progress before Windows ends the process.
      if (wparam) BeginExit(true);
      return 0;

    case WM_TIMER:
      if (wparam == kExitTimerId) {
        FinishExit();
        return 0;
      }
      break;

    case WM_COPYDATA: {
      const auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
      if (data == nullptr || data->dwData != SingleInstance::kActivateMessage) {
        break;
      }
      // 0 tells the new launch to wait for this copy to finish quitting.
      if (exit_state_ != ExitState::kRunning) return 0;
      std::wstring args;
      if (data->lpData != nullptr && data->cbData >= sizeof(wchar_t)) {
        args.assign(static_cast<const wchar_t*>(data->lpData),
                    data->cbData / sizeof(wchar_t));
      }
      // Windows startup launching a copy that is already running changes
      // nothing; any other launch brings the window forward.
      if (args.find(L"--minimized") == std::wstring::npos) {
        ShowFromBackground();
      }
      return 1;
    }

    case WM_COMMAND:
      if (HIWORD(wparam) == THBN_CLICKED) {
        switch (LOWORD(wparam)) {
          case kThumbRewind:
            SendAction("rewind");
            return 0;
          case kThumbPlayPause:
            SendAction("playPause");
            return 0;
          case kThumbForward:
            SendAction("forward");
            return 0;
        }
      }
      break;

    case kTrayCallbackMessage:
      switch (LOWORD(lparam)) {
        case NIN_SELECT:
        case NIN_KEYSELECT:
          ShowFromBackground();
          break;
        case WM_CONTEXTMENU: {
          POINT anchor = {static_cast<short>(LOWORD(wparam)),
                          static_cast<short>(HIWORD(wparam))};
          ShowTrayMenu(anchor);
          break;
        }
      }
      return 0;

    case WM_SETTINGCHANGE:
      if (lparam != 0 &&
          wcscmp(reinterpret_cast<const wchar_t*>(lparam),
                 L"ImmersiveColorSet") == 0) {
        CreateThumbIcons();
        if (thumb_buttons_added_) UpdateThumbButtons();
      }
      break;
  }
  (void)hwnd;
  return std::nullopt;
}

void WindowsShell::ShowAtStartup() {
  if (window_->HasBeenShown() || window_->GetHandle() == nullptr) return;
  if (!launch_.minimized) {
    window_->Show();
  } else if (close_to_tray_) {
    AddTrayIcon();  // Stay hidden; the tray icon brings the window back.
  } else {
    window_->ShowMinimized();
  }
}

void WindowsShell::ShowFromBackground() {
  HWND hwnd = window_->GetHandle();
  if (hwnd == nullptr || exit_state_ != ExitState::kRunning) return;
  if (!window_->HasBeenShown()) {
    window_->Show();
  } else if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  } else {
    ShowWindow(hwnd, SW_SHOW);
  }
  SetForegroundWindow(hwnd);
}

void WindowsShell::HideToTray() {
  HWND hwnd = window_->GetHandle();
  if (hwnd == nullptr) return;
  AddTrayIcon();
  ShowWindow(hwnd, SW_HIDE);
}

void WindowsShell::RequestQuit() {
  quit_requested_ = true;
  BeginExit(false);
}

// Quitting: the window disappears at once, the Dart side saves the playback
// position (lib/services/windows_shell.dart, "prepareToExit"), and then the
// process ends. Bounded by kExitTimeoutMs so a stuck flush cannot keep the
// process alive.
void WindowsShell::BeginExit(bool wait_here) {
  if (exit_state_ == ExitState::kRunning) {
    exit_state_ = ExitState::kFlushing;
    HWND hwnd = window_->GetHandle();
    window_->SaveWindowPlacementNow();
    if (hwnd != nullptr) ShowWindow(hwnd, SW_HIDE);
    RemoveTrayIcon();
    if (taskbar_ && hwnd != nullptr) {
      taskbar_->SetProgressState(hwnd, TBPF_NOPROGRESS);
    }
    if (!dart_ready_ || hwnd == nullptr ||
        SetTimer(hwnd, kExitTimerId, kExitTimeoutMs, nullptr) == 0) {
      FinishExit();  // Nothing to save yet (e.g. still on the sign-in screen).
    }
    shell_channel_->InvokeMethod(
        "prepareToExit", nullptr,
        std::make_unique<flutter::MethodResultFunctions<EncodableValue>>(
            [this](const EncodableValue*) { FinishExit(); },
            [this](const std::string&, const std::string&,
                   const EncodableValue*) { FinishExit(); },
            [this]() { FinishExit(); }));
  }
  if (!wait_here) return;
  // WM_ENDSESSION: Windows may end the process as soon as the message
  // returns, so keep pumping (Dart runs on this thread) until saved.
  const ULONGLONG deadline = GetTickCount64() + 3000;
  while (exit_state_ != ExitState::kDone && GetTickCount64() < deadline) {
    MSG msg;
    while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
    }
    MsgWaitForMultipleObjects(0, nullptr, FALSE, 50, QS_ALLINPUT);
  }
  FinishExit();
}

void WindowsShell::FinishExit() {
  ExitNow(exit_code_);
}

// Why the process ends here instead of destroying the Flutter engine first:
// engine teardown runs every plugin's native destructor, and several of them
// crash or deadlock during teardown (connectivity_plus releases COM twice and
// its network callbacks can fire mid-teardown; libmpv keeps calling into a
// Dart isolate that no longer exists; WebView2 composition objects). Each
// crash made Windows Error Reporting hold the closed process while it wrote a
// crash dump, which is the "absorb.exe still running after closing" the owner
// saw. Everything that must survive is saved before this point: the Dart side
// awaits its progress writes in prepareToExit, the registry is written
// synchronously, and Windows releases the rest when the process ends.
[[noreturn]] void WindowsShell::ExitNow(UINT exit_code) {
  exit_state_ = ExitState::kDone;
  RemoveTrayIcon();  // A killed process would leave a stale tray icon.
  SetThreadExecutionState(ES_CONTINUOUS);
  std::fflush(stdout);
  std::fflush(stderr);
  if (TerminateProcess(GetCurrentProcess(), exit_code)) {
    for (;;) Sleep(INFINITE);
  }
  ExitProcess(exit_code);
}

void WindowsShell::SetCloseToTray(bool enabled) {
  close_to_tray_ = enabled;
  WriteSetting(L"closeToTray", enabled);
  if (enabled) {
    AddTrayIcon();
    return;
  }
  HWND hwnd = window_->GetHandle();
  if (hwnd != nullptr && !IsWindowVisible(hwnd)) ShowFromBackground();
  RemoveTrayIcon();
}

void WindowsShell::AddTrayIcon() {
  HWND hwnd = window_->GetHandle();
  if (hwnd == nullptr || tray_added_) return;
  if (tray_icon_ == nullptr) {
    const UINT dpi = GetDpiForWindow(hwnd);
    tray_icon_ = static_cast<HICON>(LoadImageW(
        GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
        GetSystemMetricsForDpi(SM_CXSMICON, dpi),
        GetSystemMetricsForDpi(SM_CYSMICON, dpi), LR_DEFAULTCOLOR));
  }
  NOTIFYICONDATAW data = {sizeof(NOTIFYICONDATAW)};
  data.hWnd = hwnd;
  data.uID = kTrayIconId;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  data.uCallbackMessage = kTrayCallbackMessage;
  data.hIcon = tray_icon_;
  wcsncpy_s(data.szTip, label_tooltip_.c_str(), _TRUNCATE);
  if (!Shell_NotifyIconW(NIM_ADD, &data)) return;
  data.uVersion = NOTIFYICON_VERSION_4;
  Shell_NotifyIconW(NIM_SETVERSION, &data);
  tray_added_ = true;
}

void WindowsShell::RemoveTrayIcon() {
  HWND hwnd = window_->GetHandle();
  if (!tray_added_ || hwnd == nullptr) return;
  NOTIFYICONDATAW data = {sizeof(NOTIFYICONDATAW)};
  data.hWnd = hwnd;
  data.uID = kTrayIconId;
  Shell_NotifyIconW(NIM_DELETE, &data);
  tray_added_ = false;
}

void WindowsShell::ShowTrayMenu(POINT anchor) {
  HWND hwnd = window_->GetHandle();
  if (hwnd == nullptr) return;
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) return;
  AppendMenuW(menu, MF_STRING, kMenuShow, label_show_.c_str());
  UINT play_flags = MF_STRING;
  if (playback_ == Playback::kNone) play_flags |= MF_GRAYED;
  AppendMenuW(menu, play_flags, kMenuPlayPause,
              (playback_ == Playback::kPlaying ? label_pause_ : label_play_)
                  .c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuQuit, label_quit_.c_str());
  SetMenuDefaultItem(menu, kMenuShow, FALSE);

  // Required for the menu to close when the user clicks elsewhere.
  SetForegroundWindow(hwnd);
  UINT flags = TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON;
  flags |= GetSystemMetrics(SM_MENUDROPALIGNMENT) ? TPM_RIGHTALIGN
                                                   : TPM_LEFTALIGN;
  const UINT command = static_cast<UINT>(
      TrackPopupMenuEx(menu, flags, anchor.x, anchor.y, hwnd, nullptr));
  PostMessageW(hwnd, WM_NULL, 0, 0);
  DestroyMenu(menu);

  switch (command) {
    case kMenuShow:
      ShowFromBackground();
      break;
    case kMenuPlayPause:
      SendAction("playPause");
      break;
    case kMenuQuit:
      RequestQuit();
      break;
  }
}

std::wstring WindowsShell::RunCommand() const {
  std::wstring command = L"\"" + ExecutablePath() + L"\"";
  if (start_minimized_) command += L" --minimized";
  if (launch_.probe) command += L" --probe";
  return command;
}

std::wstring WindowsShell::RegisteredRunCommand() const {
  const wchar_t* name = RunValueName(launch_.probe);
  DWORD size = 0;
  if (RegGetValueW(HKEY_CURRENT_USER, kRunKey, name, RRF_RT_REG_SZ, nullptr,
                   nullptr, &size) != ERROR_SUCCESS ||
      size < sizeof(wchar_t)) {
    return L"";
  }
  std::wstring value(size / sizeof(wchar_t), L'\0');
  if (RegGetValueW(HKEY_CURRENT_USER, kRunKey, name, RRF_RT_REG_SZ, nullptr,
                   value.data(), &size) != ERROR_SUCCESS) {
    return L"";
  }
  value.resize(wcsnlen(value.c_str(), value.size()));
  return value;
}

namespace {

bool CommandIsForThisCopy(const std::wstring& command) {
  const std::wstring prefix = L"\"" + ExecutablePath() + L"\"";
  return command.size() >= prefix.size() &&
         CompareStringOrdinal(command.c_str(), static_cast<int>(prefix.size()),
                              prefix.c_str(), static_cast<int>(prefix.size()),
                              TRUE) == CSTR_EQUAL;
}

}  // namespace

bool WindowsShell::SetStartWithWindows(bool enabled) {
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kRunKey, 0, nullptr, 0, KEY_SET_VALUE,
                      nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return false;
  }
  const wchar_t* name = RunValueName(launch_.probe);
  LSTATUS status;
  if (enabled) {
    const std::wstring command = RunCommand();
    status = RegSetValueExW(
        key, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(command.c_str()),
        static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  } else {
    status = RegDeleteValueW(key, name);
    if (status == ERROR_FILE_NOT_FOUND) status = ERROR_SUCCESS;
  }
  RegCloseKey(key);
  return status == ERROR_SUCCESS;
}

// Task Manager's Startup apps page can switch the entry off without removing
// it; the settings tile says so instead of claiming it will run.
bool WindowsShell::StartupDisabledBySystem() const {
  BYTE data[12] = {};
  DWORD size = sizeof(data);
  if (RegGetValueW(HKEY_CURRENT_USER, kStartupApprovedKey,
                   RunValueName(launch_.probe), RRF_RT_REG_BINARY, nullptr,
                   data, &size) != ERROR_SUCCESS ||
      size == 0) {
    return false;
  }
  return (data[0] & 1) != 0;
}

void WindowsShell::UpdateExecutionState() {
  EXECUTION_STATE flags = ES_CONTINUOUS;
  // "Keep screen on": the display and therefore the system stay on.
  if (display_hold_) flags |= ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED;
  // Playing or downloading: no sleep, but the display may still turn off.
  if (busy_hold_ && keep_awake_) flags |= ES_SYSTEM_REQUIRED;
  if (flags == execution_state_) return;
  if (SetThreadExecutionState(flags) != 0) execution_state_ = flags;
}

void WindowsShell::OnTaskbarButtonCreated() {
  if (!taskbar_) {
    Microsoft::WRL::ComPtr<ITaskbarList3> list;
    if (FAILED(CoCreateInstance(CLSID_TaskbarList, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&list))) ||
        FAILED(list->HrInit())) {
      return;
    }
    taskbar_ = list;
  }
  // A new taskbar button (first show, or shown again from the tray) has no
  // toolbar yet.
  thumb_buttons_added_ = false;
  UpdateThumbButtons();
  UpdateTaskbarProgress();
}

void WindowsShell::UpdateThumbButtons() {
  HWND hwnd = window_->GetHandle();
  if (!taskbar_ || hwnd == nullptr) return;
  const bool playing = playback_ == Playback::kPlaying;
  const UINT ids[3] = {kThumbRewind, kThumbPlayPause, kThumbForward};
  HICON icons[3] = {icon_rewind_, playing ? icon_pause_ : icon_play_,
                    icon_forward_};
  const std::wstring* tips[3] = {&label_rewind_,
                                 playing ? &label_pause_ : &label_play_,
                                 &label_forward_};
  THUMBBUTTON buttons[3] = {};
  for (int i = 0; i < 3; ++i) {
    buttons[i].dwMask =
        static_cast<THUMBBUTTONMASK>(THB_ICON | THB_TOOLTIP | THB_FLAGS);
    buttons[i].iId = ids[i];
    buttons[i].hIcon = icons[i];
    wcsncpy_s(buttons[i].szTip, tips[i]->c_str(), _TRUNCATE);
    buttons[i].dwFlags =
        playback_ == Playback::kNone ? THBF_HIDDEN : THBF_ENABLED;
  }
  if (!thumb_buttons_added_) {
    last_taskbar_result_ = taskbar_->ThumbBarAddButtons(hwnd, 3, buttons);
    thumb_buttons_added_ = SUCCEEDED(last_taskbar_result_);
  } else {
    last_taskbar_result_ = taskbar_->ThumbBarUpdateButtons(hwnd, 3, buttons);
  }
}

void WindowsShell::UpdateTaskbarProgress() {
  HWND hwnd = window_->GetHandle();
  if (!taskbar_ || hwnd == nullptr || exit_state_ != ExitState::kRunning) {
    return;
  }
  if (playback_ == Playback::kNone) {
    last_taskbar_result_ = taskbar_->SetProgressState(hwnd, TBPF_NOPROGRESS);
    return;
  }
  constexpr ULONGLONG kTotal = 10000;
  const ULONGLONG done = static_cast<ULONGLONG>(
      std::llround(std::clamp(progress_, 0.0, 1.0) * kTotal));
  taskbar_->SetProgressValue(hwnd, done, kTotal);
  last_taskbar_result_ = taskbar_->SetProgressState(
      hwnd, playback_ == Playback::kPlaying ? TBPF_NORMAL : TBPF_PAUSED);
}

void WindowsShell::CreateThumbIcons() {
  DestroyThumbIcons();
  HWND hwnd = window_->GetHandle();
  const UINT dpi = hwnd != nullptr ? GetDpiForWindow(hwnd) : 96;
  const int size = GetSystemMetricsForDpi(SM_CXSMICON, dpi);
  // Dark glyphs on the light taskbar theme, white on the dark one.
  const uint32_t rgb = TaskbarUsesLightTheme() ? 0x202020 : 0xFFFFFF;
  icon_rewind_ = CreateGlyphIcon(Glyph::kRewind, size, rgb);
  icon_play_ = CreateGlyphIcon(Glyph::kPlay, size, rgb);
  icon_pause_ = CreateGlyphIcon(Glyph::kPause, size, rgb);
  icon_forward_ = CreateGlyphIcon(Glyph::kForward, size, rgb);
}

void WindowsShell::DestroyThumbIcons() {
  for (HICON* icon : {&icon_rewind_, &icon_play_, &icon_pause_,
                      &icon_forward_}) {
    if (*icon != nullptr) DestroyIcon(*icon);
    *icon = nullptr;
  }
}

void WindowsShell::SendAction(const char* action) {
  if (exit_state_ != ExitState::kRunning) return;
  shell_channel_->InvokeMethod(
      "action", std::make_unique<EncodableValue>(std::string(action)));
}

EncodableValue WindowsShell::StateMap() const {
  const std::wstring registered = RegisteredRunCommand();
  return EncodableValue(EncodableMap{
      {EncodableValue("closeToTray"), EncodableValue(close_to_tray_)},
      {EncodableValue("startMinimized"), EncodableValue(start_minimized_)},
      {EncodableValue("startWithWindows"), EncodableValue(!registered.empty())},
      {EncodableValue("startWithWindowsThisCopy"),
       EncodableValue(CommandIsForThisCopy(registered))},
      {EncodableValue("startWithWindowsCommand"),
       EncodableValue(Utf8(registered))},
      {EncodableValue("startupDisabledBySystem"),
       EncodableValue(!registered.empty() && StartupDisabledBySystem())},
      {EncodableValue("alwaysOnTop"), EncodableValue(always_on_top_)},
      {EncodableValue("keepAwake"), EncodableValue(keep_awake_)},
      {EncodableValue("fullScreen"), EncodableValue(window_->IsFullScreen())},
      {EncodableValue("exePath"), EncodableValue(Utf8(ExecutablePath()))},
  });
}

void WindowsShell::HandleShellCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  const EncodableValue* args = call.arguments();
  // Asked during startup, before Dart can take part in the quit flow, so it
  // must not mark Dart as ready.
  if (method == "processAgeMs") {
    result->Success(EncodableValue(ProcessAgeMs()));
    return;
  }
  dart_ready_ = true;
  const bool enabled = BoolArg(args, "enabled").value_or(false);

  if (method == "getState") {
    result->Success(StateMap());
  } else if (method == "setCloseToTray") {
    SetCloseToTray(enabled);
    result->Success(StateMap());
  } else if (method == "setStartMinimized") {
    start_minimized_ = enabled;
    WriteSetting(L"startMinimized", enabled);
    // Keep the Run entry's --minimized flag in step, for this copy only.
    if (CommandIsForThisCopy(RegisteredRunCommand())) SetStartWithWindows(true);
    result->Success(StateMap());
  } else if (method == "setStartWithWindows") {
    if (!SetStartWithWindows(enabled)) {
      result->Error("registry", "Could not change the Windows startup entry.");
      return;
    }
    result->Success(StateMap());
  } else if (method == "setAlwaysOnTop") {
    always_on_top_ = enabled;
    WriteSetting(L"alwaysOnTop", enabled);
    window_->SetAlwaysOnTop(enabled);
    result->Success(StateMap());
  } else if (method == "setKeepAwake") {
    keep_awake_ = enabled;
    WriteSetting(L"keepAwake", enabled);
    UpdateExecutionState();
    result->Success(StateMap());
  } else if (method == "setBusy") {
    busy_hold_ = BoolArg(args, "busy").value_or(false);
    UpdateExecutionState();
    result->Success();
  } else if (method == "setPlayback") {
    const std::string state = StringArg(args, "state").value_or("none");
    const Playback next = state == "playing"  ? Playback::kPlaying
                          : state == "paused" ? Playback::kPaused
                                              : Playback::kNone;
    progress_ = DoubleArg(args, "progress").value_or(0);
    if (next != playback_) {
      playback_ = next;
      UpdateThumbButtons();
    }
    UpdateTaskbarProgress();
    result->Success();
  } else if (method == "setStrings") {
    auto take = [args](const char* key, std::wstring* target) {
      if (auto text = StringArg(args, key); text && !text->empty()) {
        *target = Utf16FromUtf8(*text);
      }
    };
    take("show", &label_show_);
    take("play", &label_play_);
    take("pause", &label_pause_);
    take("quit", &label_quit_);
    take("rewind", &label_rewind_);
    take("forward", &label_forward_);
    if (thumb_buttons_added_) UpdateThumbButtons();
    result->Success();
  } else if (method == "setFullScreen" || method == "toggleFullScreen") {
    window_->SetFullScreen(method == "setFullScreen" ? enabled
                                                     : !window_->IsFullScreen());
    result->Success(EncodableValue(window_->IsFullScreen()));
  } else if (method == "quit") {
    result->Success();
    RequestQuit();
  } else if (method == "probe" && launch_.probe) {
    // Test target only (tool/windows_shell_probe.dart).
    HWND hwnd = window_->GetHandle();
    if (auto width = DoubleArg(args, "resizeWidth")) {
      const int height =
          static_cast<int>(DoubleArg(args, "resizeHeight").value_or(*width));
      SetWindowPos(hwnd, nullptr, 0, 0, static_cast<int>(*width), height,
                   SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    }
    RECT window_rect = {};
    GetWindowRect(hwnd, &window_rect);
    MONITORINFO monitor = {sizeof(MONITORINFO)};
    GetMonitorInfoW(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                    &monitor);
    auto rect = [](const RECT& r) {
      return EncodableValue(flutter::EncodableList{
          EncodableValue(static_cast<int32_t>(r.left)),
          EncodableValue(static_cast<int32_t>(r.top)),
          EncodableValue(static_cast<int32_t>(r.right - r.left)),
          EncodableValue(static_cast<int32_t>(r.bottom - r.top))});
    };
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("windowRect"), rect(window_rect)},
        {EncodableValue("monitorRect"), rect(monitor.rcMonitor)},
        {EncodableValue("dpi"),
         EncodableValue(static_cast<int32_t>(GetDpiForWindow(hwnd)))},
        {EncodableValue("caption"),
         EncodableValue((GetWindowLongPtrW(hwnd, GWL_STYLE) & WS_CAPTION) ==
                        WS_CAPTION)},
        {EncodableValue("zoomed"), EncodableValue(IsZoomed(hwnd) != FALSE)},
        {EncodableValue("visible"),
         EncodableValue(IsWindowVisible(hwnd) != FALSE)},
        {EncodableValue("topmost"), EncodableValue(window_->IsAlwaysOnTop())},
        {EncodableValue("fullScreen"), EncodableValue(window_->IsFullScreen())},
        {EncodableValue("executionState"),
         EncodableValue(static_cast<int32_t>(execution_state_))},
        {EncodableValue("trayIcon"), EncodableValue(tray_added_)},
        {EncodableValue("taskbar"), EncodableValue(taskbar_ != nullptr)},
        {EncodableValue("thumbButtons"), EncodableValue(thumb_buttons_added_)},
        {EncodableValue("taskbarResult"),
         EncodableValue(static_cast<int32_t>(last_taskbar_result_))},
        {EncodableValue("runCommand"),
         EncodableValue(Utf8(RegisteredRunCommand()))},
    }));
  } else {
    result->NotImplemented();
  }
}
