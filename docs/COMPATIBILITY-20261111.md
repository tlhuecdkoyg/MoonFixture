# 2026 年 11 月持续可用性维护

维护目的：按组委会提醒，**完成兼容性检查和必要修复**。维护版本为 `0.1.4`，检查日期为 2026-11-11；对应邮件截止时间为 2026-11-13 09:00（北京时间，UTC+8）。

## 工具链与范围

`moon version --all` 与检查当日[官方发布元数据](https://cli.moonbitlang.com/version.json)一致：

- `moonc v0.10.20+65efd5b93 (2026-11-05)`。
- `moon` / `moonrun 0.1.20261104 (940aa18 2026-11-04)`。
- CLI 依赖 `moonbitlang/async@0.22.7`、`moonbitlang/x@0.5.7`。

核心库支持 wasm / wasm-gc / JavaScript / native；CLI 支持 native。本轮检查源码与依赖、四后端库和公开 API 样例、原生 CLI、实际 SQLite/HTTP 消费流程及 CI。检查日期与工具链构建日期分别记录，不使用未注明版本的“最新稳定版”作为验证基线。

## 必要修复与新增验证

本维护版延续 `0.1.3` 对唯一外键空父键、JSON 整数精确检查和 SQLite 名称兼容性的修复，详见[此前复查记录](RECHECK-20261111.md)。本轮新增范围未发现需新增修复的生成库缺陷，未修改随机算法、数据格式或公开 API。

新增 `compatibility_matrix_test.mbt`：组合日期边界、种子、父子关联及派生字段，验证生成结果可被独立校验、JSON 往返和完整重放保持一致、分批导出与恢复一致，以及定向破坏能被检测且不修改原数据。正式矩阵使用六个日期参考和三个种子共 18 组，随四后端测试持续执行。

额外独立探针在 native 和 JavaScript 上验证了六个日期参考乘二十个种子的 120 组模型。CLI 另检查异常参数、非法 UTF-8 及输出覆盖保护。探针通过代表该有界输入集合的结果，不代表穷尽所有模型。

## 复现命令

```text
moon version --all
moon check --target all --deny-warn
moon test --target all --deny-warn
moon build --target all --release
moon build --target native --deny-warn
python scripts/integration.py
python scripts/count_lines.py --minimum 4000
moon info
moon fmt --check
```

SQLite/HTTP 集成脚本运行真实编译的 CLI；Python 标准库充当独立消费者。CI 继续在 Ubuntu 和 Windows 上执行支持目标的严格检查、构建、测试及集成验证。

本版本同步维护说明、安装值及 CLI 版本。`0.1.2`、`0.1.3` 的原始结果保留在对应历史记录；远程 CI 及注册表发布状态应核对本版本对应提交，不能以历史绿灯替代。

本地实际结果：四后端各 **43/43** 测试通过，严格检查、release 构建、接口、格式、打包及真实 SQLite/HTTP 集成均通过。新增 18 组正式矩阵随四后端执行；公开 `.mbti` 接口无变化。生产代码仍为 **4,253 行**，不包含测试、依赖和生成接口。
