#include "flutter_window.h"

#include <optional>
#include <shobjidl.h>
#include <shellapi.h>
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

  file_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "accessible_retrieval/files",
      &flutter::StandardMethodCodec::GetInstance());
  file_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "openFile") { result->NotImplemented(); return; }
    const auto* path = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
    if (!path || path->empty() || path->find('\0') != std::string::npos) {
      result->Error("invalid_path", "A complete local source path is required.");
      return;
    }
    const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
        path->data(), static_cast<int>(path->size()), nullptr, 0);
    if (length <= 0) { result->Error("invalid_path", "Source path is not valid UTF-8."); return; }
    std::wstring wide(static_cast<size_t>(length), L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path->data(),
        static_cast<int>(path->size()), wide.data(), length);
    const DWORD attributes = GetFileAttributesW(wide.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES) {
      const DWORD error = GetLastError();
      result->Error(error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND
          ? "source_missing" : "open_failed", "Source is missing or inaccessible.");
      return;
    }
    if (attributes & FILE_ATTRIBUTE_DIRECTORY) {
      result->Error("source_missing", "Source path refers to a directory.");
      return;
    }
    // lpParameters is null: filenames are never interpreted as shell command
    // text. This reports OS acceptance, not viewer navigation to a page/span.
    const auto status = reinterpret_cast<INT_PTR>(ShellExecuteW(GetHandle(), L"open",
        wide.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
    if (status <= 32) {
      result->Error("open_failed", "Windows could not open the file (code " + std::to_string(status) + ").");
      return;
    }
    result->Success();
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
  file_channel_.reset();
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
