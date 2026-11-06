#define ORT_API_MANUAL_INIT
#include <onnxruntime_cxx_api.h>

#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <vector>

namespace {

// Keep ONNX Runtime types and ownership inside the bridge.
struct InputTensor {
  const char* name;
  void* data;
  size_t bytes;
  const int64_t* shape;
  size_t rank;
  int32_t element_type;
};

Ort::Env MakeEnvironment() {
  const auto* api = OrtGetApiBase()->GetApi(ORT_API_VERSION);
  if (!api) throw std::runtime_error("ONNX Runtime C API version is incompatible.");
  Ort::InitApi(api);
  Ort::Env environment(ORT_LOGGING_LEVEL_ERROR, "amr");
  environment.DisableTelemetryEvents();
  return environment;
}

Ort::Env& Environment() {
  static auto environment = MakeEnvironment();
  return environment;
}

void SetMessage(char* buffer, size_t size, const char* message) {
  if (size != 0) std::snprintf(buffer, size, "%s", message);
}

}  // namespace

extern "C" __declspec(dllexport) int32_t amr_onnx_probe(char* buffer, size_t size) {
  try {
    Environment();
    SetMessage(buffer, size, OrtGetApiBase()->GetVersionString());
    return 0;
  } catch (const std::exception& error) {
    SetMessage(buffer, size, error.what());
    return 1;
  }
}

extern "C" __declspec(dllexport) void* amr_onnx_open(
    const wchar_t* path, char* error, size_t error_size) {
  try {
    auto& environment = Environment();
    Ort::SessionOptions options;
    options.SetGraphOptimizationLevel(ORT_ENABLE_ALL);
    return new Ort::Session(environment, path, options);
  } catch (const std::exception& failure) {
    SetMessage(error, error_size, failure.what());
    return nullptr;
  }
}

extern "C" __declspec(dllexport) int32_t amr_onnx_run(
    void* handle, const InputTensor* inputs, size_t count, const char* output_name,
    float* output, size_t output_count, char* error, size_t error_size) {
  try {
    auto& session = *static_cast<Ort::Session*>(handle);
    auto memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    std::vector<Ort::Value> values;
    std::vector<const char*> names;
    values.reserve(count);
    names.reserve(count);
    for (size_t index = 0; index < count; ++index) {
      const auto& input = inputs[index];
      names.push_back(input.name);
      values.push_back(Ort::Value::CreateTensor(
          memory, input.data, input.bytes, input.shape, input.rank,
          static_cast<ONNXTensorElementDataType>(input.element_type)));
    }
    auto results = session.Run(Ort::RunOptions{nullptr}, names.data(),
                               values.data(), count, &output_name, 1);
    const auto info = results.front().GetTensorTypeAndShapeInfo();
    if (info.GetElementType() != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT ||
        info.GetElementCount() != output_count) {
      throw std::runtime_error("ONNX output type or element count is unexpected.");
    }
    std::memcpy(output, results.front().GetTensorData<float>(),
                output_count * sizeof(float));
    return 0;
  } catch (const std::exception& failure) {
    SetMessage(error, error_size, failure.what());
    return 1;
  }
}

extern "C" __declspec(dllexport) void amr_onnx_close(void* handle) {
  delete static_cast<Ort::Session*>(handle);
}
