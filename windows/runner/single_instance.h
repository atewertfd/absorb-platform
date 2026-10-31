#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

#include <string>

// One running copy per executable path (absorb-plus fork). A second launch of
// the same absorb.exe hands its command line to the running window, which
// comes to the front, and then exits. Installed and portable copies in other
// folders are separate, as before.
class SingleInstance {
 public:
  // dwData of the WM_COPYDATA a second launch sends to the running window.
  // The running window replies 1 when it came forward, 0 while it is quitting.
  static constexpr ULONG_PTR kActivateMessage = 0xAB5011;

  SingleInstance() = default;
  ~SingleInstance();
  SingleInstance(const SingleInstance&) = delete;
  SingleInstance& operator=(const SingleInstance&) = delete;

  // Returns false when another instance took over this launch and this
  // process should exit. Fails open: any error lets the launch continue.
  bool Acquire(bool probe, const wchar_t* command_line);

  // Value stored as a window property so the second launch finds the window.
  ULONG_PTR tag() const { return tag_; }

 private:
  HANDLE mutex_ = nullptr;
  ULONG_PTR tag_ = 0;
};

#endif  // RUNNER_SINGLE_INSTANCE_H_
