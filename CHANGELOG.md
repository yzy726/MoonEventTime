# Changelog

## 0.1.1 — 2026-11-09

- 修复新版 MoonBit 将 Json / ToJson 移至 core/json 后，快照和 JSONL 输出调用 `.to_json()` 导致的 E4015；改用显式的 `@json.ToJson::to_json`。
- 通过官方格式化工具迁移 derive、Int32 和默认参数语法；窗口语义、v1 快照及 JSONL 格式保持兼容。
- 工具链与标准库固定为 v0.10.20+65efd5b93；统一验证新增本地源码和打包源码的文档生成门禁。
- Mooncakes 源码包显式排除本地项目申报书，并在消费者验证中检查。
- 已发布至 [Mooncakes](https://mooncakes.io/docs/Ag108/MoonEventTime@0.1.1)，线上文档生成成功。

## 0.1.0

- 单输入按键滚动窗、负时间、原点与受检 Int64 精确统计。
- 排他水位线、迟到侧输出、终止刷新与原子预算拒绝。
- v1 快照、严格恢复校验、流式 native JSONL CLI 和稳定退出码。
- 五个合成示例、独立参考模型、黄金输出和真实进程测试。
- 核心面向 native/JavaScript/wasm-gc。
