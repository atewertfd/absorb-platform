#ifndef RUNNER_WINDOWS_SHELL_H_
#define RUNNER_WINDOWS_SHELL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <shobjidl.h>
#include <windows.h>
#include <wrl/client.h>

#include <memory>
#include <optional>
#include <string>

#include "win32_window.h"

// How this process was started (absorb-plus fork).
struct LaunchOptions {
  // --minimized: start in the tray (close to tray on) or minimized.
  bool minimized = false;
  // --probe: test target; separate registry key, Run value and instance.
  bool probe = false;
};

// Windows desktop integration for Absorb Plus (fork-owned): clean quit that
// saves progress first, close to tray, start with Windows, always on top,
// keep awake, taskbar thumbnail buttons and progress, and full screen. Dart
// side: lib/services/windows_shell.dart over the "absorb/windows_shell"
// channel; "com.absorb.screen_wake" is handled here too.
class WindowsShell {
 public:
  WindowsShell(Win32Window* window, flutter::BinaryMessenger* messenger,
               const LaunchOptions& launch);
  ~WindowsShell();
  WindowsShell(const WindowsShell&) = delete;
  WindowsShell& operator=(const WindowsShell&) = delete;

  // Runs before Flutter sees the message. A value means it was handled.
  std::optional<LRESULT> HandleMessage(HWND hwnd, UINT message, WPARAM wparam,
                                       LPARAM lparam);

  // Called once the first frame is ready: show normally, minimized, or stay
  // in the tray.
  void ShowAtStartup();

  // Ends the process without running native plugin teardown. See
  // FinishExit in windows_shell.cpp for why.
  [[noreturn]] void ExitNow(UINT exit_code);

 private:
  using Channel = flutter::MethodChannel<flutter::EncodableValue>;
  enum class ExitState { kRunning, kFlushing, kDone };
  enum class Playback { kNone, kPlaying, kPaused };

  void HandleShellCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                       std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  flutter::EncodableValue StateMap() const;

  // Quit flow: hide, let Dart save progress (bounded), then exit.
  void RequestQuit();
  void BeginExit(bool wait_here);
  void FinishExit();

  void ShowFromBackground();
  void HideToTray();

  void SetCloseToTray(bool enabled);
  void AddTrayIcon();
  void RemoveTrayIcon();
  void ShowTrayMenu(POINT anchor);

  bool SetStartWithWindows(bool enabled);
  std::wstring RunCommand() const;
  std::wstring RegisteredRunCommand() const;
  bool StartupDisabledBySystem() const;

  void UpdateExecutionState();

  void OnTaskbarButtonCreated();
  void UpdateThumbButtons();
  void UpdateTaskbarProgress();
  void CreateThumbIcons();
  void DestroyThumbIcons();

  void SendAction(const char* action);

  Win32Window* window_;
  LaunchOptions launch_;
  std::unique_ptr<Channel> shell_channel_;
  std::unique_ptr<Channel> screen_wake_channel_;

  UINT taskbar_created_message_ = 0;
  UINT taskbar_button_created_message_ = 0;
  UINT quit_request_message_ = 0;

  // Settings (registry under Win32Window::StateRegistryKey()).
  bool close_to_tray_ = false;
  bool start_minimized_ = false;
  bool always_on_top_ = false;
  bool keep_awake_ = true;

  // Holds: display (Keep screen on) and system (playing or downloading).
  bool display_hold_ = false;
  bool busy_hold_ = false;
  EXECUTION_STATE execution_state_ = ES_CONTINUOUS;

  bool tray_added_ = false;
  // The Dart side has talked to the shell channel, so it will answer
  // prepareToExit (messages to a channel without a Dart handler are buffered
  // and never answered).
  bool dart_ready_ = false;
  bool quit_requested_ = false;
  ExitState exit_state_ = ExitState::kRunning;
  UINT exit_code_ = 0;

  Playback playback_ = Playback::kNone;
  double progress_ = 0;
  Microsoft::WRL::ComPtr<ITaskbarList3> taskbar_;
  bool thumb_buttons_added_ = false;
  HRESULT last_taskbar_result_ = S_OK;
  HICON icon_rewind_ = nullptr;
  HICON icon_play_ = nullptr;
  HICON icon_pause_ = nullptr;
  HICON icon_forward_ = nullptr;
  HICON tray_icon_ = nullptr;

  // Labels; Dart replaces them with translated text.
  std::wstring label_show_ = L"Show Absorb Plus";
  std::wstring label_play_ = L"Play";
  std::wstring label_pause_ = L"Pause";
  std::wstring label_quit_ = L"Quit Absorb Plus";
  std::wstring label_rewind_ = L"Rewind";
  std::wstring label_forward_ = L"Fast-forward";
  std::wstring label_tooltip_ = L"Absorb Plus";
};

#endif  // RUNNER_WINDOWS_SHELL_H_
