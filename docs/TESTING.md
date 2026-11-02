# 测试方法

公开 API 用黑盒测试；不可从外部构造的计数极值用白盒测试。所有事件为自行合成，核心测试不访问网络、时钟或真实等待。

| 文件 | 覆盖 |
|---|---|
| time_test.mbt | 半开窗、负时间、原点、极值、分区性质 |
| aggregate_test.mbt、aggregate_wbtest.mbt | 精确统计、双向求和与计数溢出 |
| engine_test.mbt | 水位线、迟到反例、UTF-8 顺序、预算原子性、长流清理 |
| reference_test.mbt | seed=726、300 条事件与独立列表批量模型 |
| snapshot_test.mbt | 格式、配置、统计不变量、损坏状态和恢复 |
| replay/replay_test.mbt | JSONL、整数精度、行预算、诊断 |
| scripts/e2e.py | 真实进程、文件、编码、退出码、恢复 |
| scripts/examples.py | 五个库程序与 CLI 对照手写黄金输出 |
| scripts/consumer.py | 打包源码、空消费者、README 示例 |

参考模型直接枚举小整数窗口，筛选事件列表并计算统计，不复用生产分配函数或到期索引。性质测试中的大量循环断言不机械计为独立场景。数量按命名 test 与实际进程流程报告。

运行 `python scripts/verify.py`，或分别运行格式、三个目标 check/test --deny-warn、moon info、native 构建和各脚本。脚本检查不少于 80 个命名场景、25 个 invalid/edge 场景。只报告实际执行结果；本地通过不等于远程 CI 已运行。
