#include "flutter_window.h"

#include <optional>
#include <shobjidl.h>
#include <flutter/standard_method_codec.h>
#include <flutter/method_result_functions.h>

#include "utils.h"

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

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
  lifecycle_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "accessible_retrieval/lifecycle",
      &flutter::StandardMethodCodec::GetInstance());

  directory_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "accessible_retrieval/directories",
      &flutter::StandardMethodCodec::GetInstance());
  directory_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "chooseDirectory") {
          result->NotImplemented();
          return;
        }
        IFileOpenDialog* dialog = nullptr;
        HRESULT status = CoCreateInstance(CLSID_FileOpenDialog, nullptr,
            CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog));
        if (SUCCEEDED(status)) {
          FILEOPENDIALOGOPTIONS options;
          status = dialog->GetOptions(&options);
          if (SUCCEEDED(status)) {
            status = dialog->SetOptions(options | FOS_PICKFOLDERS |
                FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR);
          }
          if (SUCCEEDED(status)) status = dialog->Show(GetHandle());
          if (status == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
            dialog->Release();
            result->Success();
            return;
          }
          IShellItem* folder = nullptr;
          if (SUCCEEDED(status)) status = dialog->GetResult(&folder);
          PWSTR path = nullptr;
          if (SUCCEEDED(status)) status = folder->GetDisplayName(SIGDN_FILESYSPATH, &path);
          if (SUCCEEDED(status)) {
            const auto utf8 = Utf8FromUtf16(path);
            CoTaskMemFree(path);
            folder->Release();
            dialog->Release();
            result->Success(flutter::EncodableValue(utf8));
            return;
          }
          if (path) CoTaskMemFree(path);
          if (folder) folder->Release();
          dialog->Release();
        }
        result->Error("directory_picker_failed",
            "Windows folder selection failed (HRESULT " +
            std::to_string(static_cast<long>(status)) + "). Enter an absolute path instead.");
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  lifecycle_channel_.reset();
  directory_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_CLOSE && lifecycle_channel_ && !allow_close_) {
    if (!close_requested_) {
      close_requested_ = true;
      auto finish = [this, hwnd]() {
        allow_close_ = true;
        PostMessage(hwnd, WM_CLOSE, 0, 0);
      };
      lifecycle_channel_->InvokeMethod("requestClose", nullptr,
          std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
              [finish](const flutter::EncodableValue*) { finish(); },
              [finish](const std::string&, const std::string&,
                       const flutter::EncodableValue*) { finish(); },
              finish));
    }
    return 0;
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
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
