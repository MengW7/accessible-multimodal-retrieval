# TFLite native (Windows)

第 1 周：用 Python 解释器的冒烟测试作为环境验证门槛。

第 3 周没有放入 `libtensorflowlite_c-win.dll`。通过转换门槛的权重是 ONNX fp32，这只 DLL 加载不了 ONNX。W3 的推理走外部 ONNX Runtime 进程，见 ADR 0003。下面这个路径仍然是预留位置，真的改回进程内 TFLite 时再用：

`native/tflite/windows/libtensorflowlite_c-win.dll`