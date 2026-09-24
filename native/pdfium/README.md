### PDF 渲染与解析引擎 (PDFium)
* **核心决策**：采用预编译的 PDFium 二进制文件配合 Dart FFI / Flutter 插件进行集成。
* **候选方案**：
  * `pdfium_flutter` / `pdfium_dart`：底层轻量方案，在构建时自动拉取原生库，适合纯文本提取与轻量页面光栅化。
  * `pdfrx`：高层 UI 查看器组件，底层同样基于 PDFium，开箱即用支持桌面端缩放、手势与页面导航。
* **本地依赖产物路径**：
  * Windows 动态库预留位置：`native/pdfium/windows/pdfium.dll`
  * 头文件预留位置：`native/pdfium/include/`