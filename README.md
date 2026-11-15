# accessible-multimodal-retrieval

Offline-first desktop application for searching local TXT, Markdown, PDF, DOCX, JPG, and PNG files. The Windows production path uses Flutter, ONNX Runtime CPU, Apache Tika, and the system SQLite library. Python and Chroma stay in `engine/` for development-time evaluation and are not part of the release package.

The repository license is Apache 2.0 (`LICENSE`). MobileCLIP weights use the Apple Machine Learning Research license and are not included in a public download. See `docs/architecture/adr/0003-embedding-model-and-runtime.md` and `reports/week7/开源合规报告.md`.

Maintenance steps are in `reports/week7/技术文档.md`. The user manual is `reports/week7/用户手册.md`. Installing packaged builds for macOS and Linux, the contribution guide, and the demo video are still open.
