#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"
#include "windows_shell.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  FlutterWindow(const flutter::DartProject& project,
                const LaunchOptions& launch);
  virtual ~FlutterWindow();

  // After the message loop ends (a Dart-requested exit or a destroyed
  // window): ends the process the same way as a normal quit. Returns only
  // when the shell was never created.
  void ExitAfterMessageLoop(UINT exit_code);

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  LaunchOptions launch_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Absorb Plus desktop integration (tray, taskbar, quit flow).
  std::unique_ptr<WindowsShell> shell_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
