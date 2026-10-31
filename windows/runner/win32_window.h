#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// A class abstraction for a high DPI-aware Win32 Window. Intended to be
// inherited from by classes that wish to specialize with custom
// rendering and input handling
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // Creates a win32 window with |title| that is positioned and sized using
  // |origin| and |size|. New windows are created on the default monitor. Window
  // sizes are specified to the OS in physical pixels, hence to ensure a
  // consistent size this function will scale the inputted width and height as
  // as appropriate for the default monitor. The window is invisible until
  // |Show| is called. Returns true if the window was created successfully.
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // Show the current window. Returns true if the window was successfully shown.
  // Uses the remembered state: maximized when the window was last maximized.
  bool Show();

  // Absorb Plus window management (fork-owned).
  // Smallest window, in logical pixels; clamped to the monitor's work area.
  static constexpr int kMinWidth = 400;
  static constexpr int kMinHeight = 600;

  // Registry key (under HKCU) for the window state and shell settings. The
  // probe target uses its own key so it never touches the app's settings.
  static void SetStateRegistryKey(const std::wstring& key);
  static const std::wstring& StateRegistryKey();

  // Window property value that lets a second launch find this instance.
  static void SetInstanceTag(ULONG_PTR tag);
  static const wchar_t* InstanceProperty();
  static const wchar_t* WindowClassName();

  // Borderless full screen on the window's monitor; leaving restores the
  // previous size, position and maximized state.
  void SetFullScreen(bool full_screen);
  bool IsFullScreen() const { return full_screen_; }

  void SetAlwaysOnTop(bool always_on_top);
  bool IsAlwaysOnTop() const;

  // Writes the current (or pre-full-screen) placement to the registry.
  void SaveWindowPlacementNow();

  // First show, minimized without taking focus; restoring returns to the
  // remembered (possibly maximized) state.
  bool ShowMinimized();

  // Whether the window has been shown at least once.
  bool HasBeenShown() const { return has_been_shown_; }

  // Release OS resources associated with window.
  void Destroy();

  // Inserts |content| into the window tree.
  void SetChildContent(HWND content);

  // Returns the backing Window handle to enable clients to set icon and other
  // window properties. Returns nullptr if the window has been destroyed.
  HWND GetHandle();

  // If true, closing this window will quit the application.
  void SetQuitOnClose(bool quit_on_close);

  // Return a RECT representing the bounds of the current client area.
  RECT GetClientArea();

 protected:
  // Processes and route salient window messages for mouse handling,
  // size change and DPI. Delegates handling of these to member overloads that
  // inheriting classes can handle.
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // Called when CreateAndShow is called, allowing subclass window-related
  // setup. Subclasses should return false if setup fails.
  virtual bool OnCreate();

  // Called when Destroy is called.
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  // OS callback called by message pump. Handles the WM_NCCREATE message which
  // is passed when the non-client area is being created and enables automatic
  // non-client DPI scaling so that the non-client area automatically
  // responds to changes in DPI. All other messages are handled by
  // MessageHandler.
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // Retrieves a class instance pointer for |window|
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // Update the window frame's theme to match the system theme.
  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;

  // Show command for the first Show(): maximized when it was last maximized.
  int show_command_ = SW_SHOWNORMAL;
  bool has_been_shown_ = false;

  // State saved while in full screen.
  bool full_screen_ = false;
  LONG_PTR saved_style_ = 0;
  WINDOWPLACEMENT saved_placement_ = {sizeof(WINDOWPLACEMENT)};

  // window handle for top level window.
  HWND window_handle_ = nullptr;

  // window handle for hosted content.
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
