# 依赖与复用说明

- MoonBit core：随官方工具链提供，许可见所用工具链的 core/LICENSE。核心库使用其 JSON、集合、调试、字符串等接口。
- [moonbitlang/async 0.22.1](https://github.com/moonbitlang/async)：Apache-2.0，CLI 的异步文件与标准 I/O。
- [moonbitlang/x 0.5.5](https://github.com/moonbitlang/x)：Apache-2.0，CLI 的进程退出接口。
- `scripts/count_lines.py` 改编自同一作者的 [MoonRTF](https://github.com/tlhuecdkoyg/MoonRTF)（Apache-2.0）代码统计脚本。CLI I/O 边界处理沿用该项目的大小限制、新建输出及拒绝覆盖输入的设计；MoonFixture 业务核心独立实现。
- Python SQLite/HTTP 集成使用 Python 标准库；没有将 Python 的生成逻辑包装成 MoonBit 库。
- xorshift32、Fisher–Yates、FNV 风格名称混合、稳定拓扑排序和公历运算为通用算法的独立实现。没有复制 Faker 的实现或词库。

依赖源码不随本仓库提交，也不计入有效生产代码统计。Apache-2.0 正文见 [LICENSE](LICENSE)。
