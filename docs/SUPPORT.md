# 0.1.0 支持范围

| 能力 | 状态 | 证据 |
|---|---|---|
| 半开滚动窗、负时间、任意原点 | 支持 | time_test.mbt |
| 精确聚合、计数与求和溢出 | 支持 | aggregate_test.mbt、aggregate_wbtest.mbt |
| 排他水位线、清理、迟到分流、finish | 支持 | engine_test.mbt |
| 活跃状态、键、输出、行、快照预算 | 支持 | 单元测试、scripts/e2e.py |
| v1 快照、严格校验、后缀恢复 | 支持 | snapshot_test.mbt、snapshot_replay_cli 示例 |
| native/JavaScript/wasm-gc 核心 | 本机通过 | 对应 check/test --deny-warn |
| Windows native 文件 CLI | 本机通过 | scripts/e2e.py |
| Linux native CLI、远程 CI | 待验证 | .github/workflows/ci.yml |
| 空消费者、本地源码包 | 本地验证脚本 | scripts/consumer.py |
| Mooncakes 0.1.0 | 尚未发布 | 无注册表安装声明 |
| 滑动窗、迟到修订、多输入、空闲源 | 未支持 | 无占位 API |
| 会话窗、去重、连接器、分布式恰好一次 | 未支持 | 属于上层或未来独立设计 |

本机工具链为 moon 0.1.20260920、moonc v0.10.14+7d59c7ec9。其他版本需重跑验证。预 1.0 API 或快照格式变化需记录在 CHANGELOG，未知快照版本始终拒绝。
