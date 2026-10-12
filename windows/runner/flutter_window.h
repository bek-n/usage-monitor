#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// Held while the app runs, so that a second copy can tell it is not the first.
inline constexpr wchar_t kSingleInstanceMutex[] = L"UsageMonitor.SingleInstance";

// Posted by a second copy of the app so that the running one opens its panel.
inline constexpr wchar_t kReopenMessage[] = L"UsageMonitor.Reopen";

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Tells Dart to open the panel when the app is started again.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> app_channel_;
  UINT reopen_message_ = ::RegisterWindowMessageW(kReopenMessage);
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
