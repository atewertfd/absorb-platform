#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "single_instance.h"
#include "utils.h"
#include "windows_shell.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  LaunchOptions launch;
  for (const std::string& argument : command_line_arguments) {
    if (argument == "--minimized") launch.minimized = true;
    if (argument == "--probe") launch.probe = true;
  }
  if (launch.probe) {
    // The probe target never reads or writes the app's own settings.
    Win32Window::SetStateRegistryKey(L"Software\\Absorb Plus\\Probe");
  }

  // A second launch of this absorb.exe brings the running window forward.
  SingleInstance single_instance;
  if (!single_instance.Acquire(launch.probe, command_line)) {
    return EXIT_SUCCESS;
  }
  Win32Window::SetInstanceTag(single_instance.tag());

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, launch);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Absorb Plus", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // A Dart-requested exit (WM_QUIT): end the process like a normal quit,
  // without native plugin teardown (see WindowsShell::ExitNow).
  window.ExitAfterMessageLoop(static_cast<UINT>(msg.wParam));

  // Only reached when the window was destroyed directly. Clear the controller
  // before its child HWND emits teardown messages, and release COM-backed
  // plugins while the apartment is still initialized.
  window.Destroy();
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
