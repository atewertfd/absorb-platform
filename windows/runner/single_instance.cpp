#include "single_instance.h"

#include <cwchar>
#include <vector>

#include "win32_window.h"

namespace {

std::wstring LowercaseExecutablePath() {
  std::vector<wchar_t> buffer(MAX_PATH);
  for (;;) {
    const DWORD length = GetModuleFileNameW(
        nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0) return L"";
    if (length < buffer.size()) {
      std::wstring path(buffer.data(), length);
      CharLowerBuffW(path.data(), static_cast<DWORD>(path.size()));
      return path;
    }
    buffer.resize(buffer.size() * 2);
  }
}

// FNV-1a; only needs to be stable for one path on one machine.
ULONG_PTR HashPath(const std::wstring& path, bool probe) {
  unsigned long long hash = 1469598103934665603ull;
  for (wchar_t c : path) {
    hash ^= static_cast<unsigned long long>(c);
    hash *= 1099511628211ull;
  }
  if (probe) hash ^= 0x9e3779b97f4a7c15ull;
  return static_cast<ULONG_PTR>(hash | 1);
}

struct FindWindowState {
  ULONG_PTR tag;
  HWND found;
};

BOOL CALLBACK FindInstanceWindow(HWND window, LPARAM lparam) {
  auto state = reinterpret_cast<FindWindowState*>(lparam);
  wchar_t class_name[64] = {};
  if (GetClassNameW(window, class_name, 64) == 0 ||
      wcscmp(class_name, Win32Window::WindowClassName()) != 0) {
    return TRUE;
  }
  if (reinterpret_cast<ULONG_PTR>(
          GetPropW(window, Win32Window::InstanceProperty())) == state->tag) {
    state->found = window;
    return FALSE;
  }
  return TRUE;
}

bool Owned(DWORD wait_result) {
  return wait_result == WAIT_OBJECT_0 || wait_result == WAIT_ABANDONED;
}

}  // namespace

SingleInstance::~SingleInstance() {
  if (mutex_ != nullptr) CloseHandle(mutex_);
}

bool SingleInstance::Acquire(bool probe, const wchar_t* command_line) {
  const std::wstring path = LowercaseExecutablePath();
  if (path.empty()) return true;
  tag_ = HashPath(path, probe);

  wchar_t name[96];
  swprintf_s(name, L"Local\\AbsorbPlus.SingleInstance.%016llx",
             static_cast<unsigned long long>(tag_));
  mutex_ = CreateMutexW(nullptr, TRUE, name);
  if (mutex_ == nullptr) return true;
  if (GetLastError() != ERROR_ALREADY_EXISTS) return true;

  const std::wstring args = command_line != nullptr ? command_line : L"";
  // The running copy may still be creating its window: look for up to ~5 s.
  for (int attempt = 0; attempt < 50; ++attempt) {
    FindWindowState state = {tag_, nullptr};
    EnumWindows(FindInstanceWindow, reinterpret_cast<LPARAM>(&state));
    if (state.found != nullptr) {
      DWORD process_id = 0;
      GetWindowThreadProcessId(state.found, &process_id);
      // This launch came from the user, so it may hand them the foreground.
      AllowSetForegroundWindow(process_id);
      COPYDATASTRUCT data = {};
      data.dwData = kActivateMessage;
      data.cbData = static_cast<DWORD>((args.size() + 1) * sizeof(wchar_t));
      data.lpData = const_cast<wchar_t*>(args.c_str());
      DWORD_PTR reply = 0;
      if (SendMessageTimeoutW(state.found, WM_COPYDATA, 0,
                              reinterpret_cast<LPARAM>(&data),
                              SMTO_ABORTIFHUNG, 3000, &reply) != 0 &&
          reply == 1) {
        return false;
      }
      break;  // Quitting or not answering: wait for it to finish below.
    }
    if (Owned(WaitForSingleObject(mutex_, 100))) return true;
  }
  // The old copy is shutting down (it saves progress first, at most a few
  // seconds). Take over once it is gone; start anyway if it never goes.
  WaitForSingleObject(mutex_, 10000);
  return true;
}
