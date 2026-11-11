# MoonFixture 0.1.2 本地维护记录

维护日期：2026-11-11。范围为工具链兼容性与既有功能复验，保留此前未提交的迁移；没有新增业务功能。`moon.mod`、CLI 版本输出、帮助文字、README 和变更记录同步为 `0.1.2`，随机算法标识仍为 `moonfixture-xorshift32-scalar-fnv1a-v1`。

## 工具链与依赖

| 组件 | 本次实际版本 |
| --- | --- |
| moon | `0.1.20261104 (940aa18 2026-11-04)` |
| moonc | `v0.10.20+65efd5b93 (2026-11-05)` |
| moonrun | `0.1.20261104 (940aa18 2026-11-04)` |
| Node.js | `v26.5.1` |
| Python | `3.12.13` |
| 平台 | Windows / MSVC |
| CLI 依赖 | `moonbitlang/async@0.22.7`、`moonbitlang/x@0.5.7` |

`MOON_HOME` 指向 `D:/conda/environments/moonbit/moonbit-toolchain`，各命令的 PATH 优先采用该工具链的 `bin`。CI 固定官方归档 `0.10.20+65efd5b93`；冷 registry 的初始化仍由既有 `scripts/verify.py` 在 CI 中先执行。此次本地复验逐条运行下表命令，复用已缓存依赖，没有运行 `moon update`。

## 验证结果

| 命令 | 本地结果 |
| --- | --- |
| `moon version --all` | 与上表一致 |
| `moon check --target all --deny-warn` | 通过 |
| `moon build --target all --deny-warn` | 通过，包含 native CLI |
| `moon test --target all --deny-warn` | wasm、wasm-gc、JavaScript、native 各 34/34，通过 136 次测试项执行 |
| `moon info` | 通过，已检查生成接口差异 |
| `moon fmt --check` | 通过 |
| `python scripts/count_lines.py --minimum 4000` | 生产代码 4,095 行；测试代码 816 行，未计入生产代码 |
| `python scripts/integration.py` | 四组检查全部通过，详见下文 |
| `git diff --check` | 通过 |

本机原生可执行文件为 `_build/native/debug/build/cmd/main/main.exe`。直接执行 `--version` 和 `--help` 均返回 0，显示 `MoonFixture 0.1.2` 与既有命令/选项。

既有集成脚本使用编译后的 MoonBit CLI 生成、重放和校验数据，再由独立 Python 标准库消费者验证：

- shop 模型的用户、商品、订单、明细实际写入 SQLite，启用外键并核对关联金额、非法外键拒绝和 Unicode/SQL 片段参数绑定。
- helpdesk 模型实际写入 SQLite，核对工单所属团队与坐席团队一致。
- 真实本地 HTTP 服务接受列表、详情、新增订单和非法用户引用请求，状态码及响应符合预期。
- JSON、NDJSON、CSV、重放、输入限额和输出覆盖策略通过。

## 变更和边界

既有迁移采用 `#derive`、`Int32`/`UInt32`、默认参数标记和 `Json(value)` 数值构造，生成接口相应更新；数据模型、随机算法和导出格式保持原有约定。CI 增加显式四后端构建和生成接口漂移检查。

本记录描述 Windows 本地结果；Linux/Windows 远程 CI 必须以新提交的实际运行结果另行核实。浏览器页面仍是手动示例，本轮未运行自动浏览器测试，也未新增性能、峰值内存或生产负载结论。GitHub 提交、远程 CI 和 Mooncakes 发布状态应在对应平台独立核实，不能由本地通过结果推断。
