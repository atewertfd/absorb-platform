#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include <algorithm>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// Keep the desktop window where the user left it without adding a Flutter
// plugin or another always-running process. Values are physical screen pixels
// and are restored only when the saved monitor still exists.
std::wstring& WindowStateRegKey() {
  static std::wstring key = L"Software\\Absorb Plus\\Window";
  return key;
}

constexpr const wchar_t kInstanceProperty[] = L"AbsorbPlus.Instance";
ULONG_PTR g_instance_tag = 0;

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

bool ReadWindowStateValue(HKEY key, const wchar_t* name, DWORD* value) {
  DWORD size = sizeof(*value);
  return RegGetValueW(key, nullptr, name, RRF_RT_REG_DWORD, nullptr, value,
                     &size) == ERROR_SUCCESS;
}

// Restores the saved size and position. Returns true when the window was
// maximized last time, so the first Show() maximizes it again.
bool RestoreWindowPlacement(HWND window) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, WindowStateRegKey().c_str(), 0,
                    KEY_READ, &key) != ERROR_SUCCESS) {
    return false;
  }

  DWORD x = 0, y = 0, width = 0, height = 0, maximized = 0;
  const bool complete = ReadWindowStateValue(key, L"x", &x) &&
                        ReadWindowStateValue(key, L"y", &y) &&
                        ReadWindowStateValue(key, L"width", &width) &&
                        ReadWindowStateValue(key, L"height", &height);
  ReadWindowStateValue(key, L"maximized", &maximized);
  RegCloseKey(key);
  // Small sizes are fine: WM_GETMINMAXINFO keeps the window at least the
  // minimum size. Only reject values that cannot be a real window.
  if (!complete || width < 200 || height < 200 || width > 32767 ||
      height > 32767) {
    return false;
  }

  const LONG left = static_cast<LONG>(x);
  const LONG top = static_cast<LONG>(y);
  RECT requested = {left, top, left + static_cast<LONG>(width),
                    top + static_cast<LONG>(height)};
  HMONITOR monitor = MonitorFromRect(&requested, MONITOR_DEFAULTTONULL);
  if (monitor == nullptr) return false;

  SetWindowPos(window, nullptr, requested.left, requested.top,
               requested.right - requested.left,
               requested.bottom - requested.top,
               SWP_NOZORDER | SWP_NOACTIVATE);
  return maximized != 0;
}

// Saves the restored (not maximized) bounds plus whether the window is
// maximized, so a maximized window comes back maximized and un-maximizing it
// returns to the size the user chose.
void SaveWindowPlacement(HWND window, const WINDOWPLACEMENT* placement_override) {
  if (window == nullptr) return;

  WINDOWPLACEMENT placement = {sizeof(WINDOWPLACEMENT)};
  if (placement_override != nullptr) {
    placement = *placement_override;
  } else if (!GetWindowPlacement(window, &placement)) {
    return;
  }

  // rcNormalPosition is in workspace coordinates; the saved values are screen
  // coordinates (they differ when the taskbar is on the left or top).
  RECT bounds = placement.rcNormalPosition;
  HMONITOR monitor = MonitorFromRect(&bounds, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {sizeof(MONITORINFO)};
  if (monitor != nullptr && GetMonitorInfoW(monitor, &info)) {
    OffsetRect(&bounds, info.rcWork.left - info.rcMonitor.left,
               info.rcWork.top - info.rcMonitor.top);
  }
  if (bounds.right - bounds.left < 200 || bounds.bottom - bounds.top < 200) {
    return;
  }
  const bool maximized =
      placement.showCmd == SW_SHOWMAXIMIZED ||
      (placement_override == nullptr && IsZoomed(window)) ||
      (placement.showCmd == SW_SHOWMINIMIZED &&
       (placement.flags & WPF_RESTORETOMAXIMIZED) != 0);

  HKEY key = nullptr;
  DWORD disposition = 0;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, WindowStateRegKey().c_str(), 0,
                      nullptr, 0, KEY_WRITE, nullptr, &key,
                      &disposition) != ERROR_SUCCESS) {
    return;
  }

  const DWORD values[] = {
      static_cast<DWORD>(bounds.left),
      static_cast<DWORD>(bounds.top),
      static_cast<DWORD>(bounds.right - bounds.left),
      static_cast<DWORD>(bounds.bottom - bounds.top),
      maximized ? 1u : 0u,
  };
  const wchar_t* names[] = {L"x", L"y", L"width", L"height", L"maximized"};
  for (int i = 0; i < 5; ++i) {
    RegSetValueExW(key, names[i], 0, REG_DWORD,
                   reinterpret_cast<const BYTE*>(&values[i]), sizeof(DWORD));
  }
  RegCloseKey(key);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  if (g_instance_tag != 0) {
    SetPropW(window, kInstanceProperty,
             reinterpret_cast<HANDLE>(g_instance_tag));
  }

  if (RestoreWindowPlacement(window)) {
    show_command_ = SW_SHOWMAXIMIZED;
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  const int command = has_been_shown_ ? SW_SHOWNORMAL : show_command_;
  has_been_shown_ = true;
  return ShowWindow(window_handle_, command);
}

bool Win32Window::ShowMinimized() {
  WINDOWPLACEMENT placement = {sizeof(WINDOWPLACEMENT)};
  if (!GetWindowPlacement(window_handle_, &placement)) return false;
  placement.showCmd = SW_SHOWMINNOACTIVE;
  if (show_command_ == SW_SHOWMAXIMIZED) {
    placement.flags |= WPF_RESTORETOMAXIMIZED;
  }
  has_been_shown_ = true;
  return SetWindowPlacement(window_handle_, &placement) != FALSE;
}

// static
void Win32Window::SetStateRegistryKey(const std::wstring& key) {
  WindowStateRegKey() = key;
}

// static
const std::wstring& Win32Window::StateRegistryKey() {
  return WindowStateRegKey();
}

// static
void Win32Window::SetInstanceTag(ULONG_PTR tag) {
  g_instance_tag = tag;
}

// static
const wchar_t* Win32Window::InstanceProperty() {
  return kInstanceProperty;
}

// static
const wchar_t* Win32Window::WindowClassName() {
  return kWindowClassName;
}

void Win32Window::SetFullScreen(bool full_screen) {
  HWND window = window_handle_;
  if (window == nullptr || full_screen == full_screen_) return;

  if (full_screen) {
    saved_placement_ = {sizeof(WINDOWPLACEMENT)};
    if (!GetWindowPlacement(window, &saved_placement_)) return;
    if (IsZoomed(window)) saved_placement_.showCmd = SW_SHOWMAXIMIZED;
    saved_style_ = GetWindowLongPtrW(window, GWL_STYLE);
    MONITORINFO info = {sizeof(MONITORINFO)};
    if (!GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                         &info)) {
      return;
    }
    full_screen_ = true;
    SetWindowLongPtrW(window, GWL_STYLE,
                      saved_style_ & ~(WS_OVERLAPPEDWINDOW | WS_MAXIMIZE));
    const RECT& m = info.rcMonitor;
    SetWindowPos(window, nullptr, m.left, m.top, m.right - m.left,
                 m.bottom - m.top,
                 SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  } else {
    full_screen_ = false;
    const LONG_PTR current = GetWindowLongPtrW(window, GWL_STYLE);
    SetWindowLongPtrW(window, GWL_STYLE,
                      (saved_style_ & ~static_cast<LONG_PTR>(WS_VISIBLE)) |
                          (current & WS_VISIBLE));
    const bool visible = IsWindowVisible(window) != FALSE;
    WINDOWPLACEMENT placement = saved_placement_;
    if (!visible) placement.showCmd = SW_HIDE;
    SetWindowPlacement(window, &placement);
    SetWindowPos(window, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                     SWP_FRAMECHANGED | SWP_NOACTIVATE);
  }
}

void Win32Window::SetAlwaysOnTop(bool always_on_top) {
  if (window_handle_ == nullptr) return;
  SetWindowPos(window_handle_, always_on_top ? HWND_TOPMOST : HWND_NOTOPMOST,
               0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

bool Win32Window::IsAlwaysOnTop() const {
  return window_handle_ != nullptr &&
         (GetWindowLongPtrW(window_handle_, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;
}

void Win32Window::SaveWindowPlacementNow() {
  SaveWindowPlacement(window_handle_, full_screen_ ? &saved_placement_ : nullptr);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      SaveWindowPlacement(hwnd, full_screen_ ? &saved_placement_ : nullptr);
      RemovePropW(hwnd, kInstanceProperty);
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_GETMINMAXINFO: {
      // Keep the layout usable: at least kMinWidth x kMinHeight logical
      // pixels, but never more than the monitor's work area allows.
      auto info = reinterpret_cast<MINMAXINFO*>(lparam);
      HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
      const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
      LONG min_width = Scale(kMinWidth, scale);
      LONG min_height = Scale(kMinHeight, scale);
      MONITORINFO monitor_info = {sizeof(MONITORINFO)};
      if (GetMonitorInfoW(monitor, &monitor_info)) {
        const RECT& work = monitor_info.rcWork;
        min_width = std::min(min_width, (work.right - work.left) * 9 / 10);
        min_height = std::min(min_height, (work.bottom - work.top) * 9 / 10);
      }
      info->ptMinTrackSize.x = min_width;
      info->ptMinTrackSize.y = min_height;
      return 0;
    }

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    SaveWindowPlacementNow();
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
