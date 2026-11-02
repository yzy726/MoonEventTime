# 来源与许可证

依据本项目排他水位线与半开窗合同独立实现，没有移植第三方流引擎代码。

概念参考：[Flink 事件时间](https://nightlies.apache.org/flink/flink-docs-master/docs/concepts/time/)、[窗口生命周期](https://nightlies.apache.org/flink/flink-docs-master/docs/dev/datastream/operators/windows/)、[Beam](https://beam.apache.org/documentation/programming-guide/)、[Dataflow Model](https://research.google.com/pubs/archive/43864.pdf)。本库不声称兼容这些系统的全部触发语义。

运行时仅依赖 MoonBit 标准库（Apache-2.0），无第三方 Mooncakes 依赖。io.c 为本项目编写的私有文件适配器；开发时查阅标准库和 FFI 签名，没有复制实验 fs 包实现。测试、黄金值与示例均为合成数据，可随 Apache-2.0 项目分发。

CI Actions 的许可属于各自上游，不构成库的运行时依赖。打包过滤参考 [MoonBit 模块文档](https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html)。完整项目许可见 LICENSE。
