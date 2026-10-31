#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             const LaunchOptions& launch)
    : project_(project), launch_(launch) {}

FlutterWindow::~FlutterWindow() {
  // Clear the member before controller destruction can re-enter MessageHandler.
  OnDestroy();
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  shell_ = std::make_unique<WindowsShell>(
      this, flutter_controller_->engine()->messenger(), launch_);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    // Normally shown; minimized or left in the tray for --minimized.
    if (shell_) {
      shell_->ShowAtStartup();
    } else {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::ExitAfterMessageLoop(UINT exit_code) {
  if (shell_) shell_->ExitNow(exit_code);
}

void FlutterWindow::OnDestroy() {
  // The shell's channels use the engine's messenger: release them first.
  shell_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Absorb Plus shell first: it owns WM_CLOSE (tray, saving before quit),
  // the tray icon, taskbar buttons and second-launch activation.
  if (shell_) {
    if (std::optional<LRESULT> handled =
            shell_->HandleMessage(hwnd, message, wparam, lparam)) {
      return *handled;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
