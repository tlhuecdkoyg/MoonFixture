# 发布前验证记录

验证日期：2026-09-22。命令与可复算统计见 `scripts/verify.py` 和 `scripts/count_lines.py`。这些是本地实测结果；远程 CI 状态以 GitHub Actions 当前记录为准。

| 项目 | 结果 |
| --- | --- |
| `moon check --target all --deny-warn` | 通过 |
| wasm 测试 | 34/34 通过 |
| wasm-gc 测试 | 34/34 通过 |
| JavaScript 测试 | 34/34 通过 |
| native 测试 | 34/34 通过 |
| `moon fmt --check` | 通过 |
| `moon info` | 通过，生成接口已纳入版本管理 |
| native CLI 构建 | 通过 |
| 生产 MoonBit 有效代码 | **4,073 行** |
| 测试有效代码 | 816 行，未计入生产代码 |

32/34 等测试数量不是随机样本数量：其中一项测试遍历 64 个固定种子，每组构造包含父表查值、金额计算和可空 Unicode 文本的关联模型。四个后端各执行完整测试集合，共 136 次测试项执行。

## 独立集成验证

`python scripts/integration.py` 已通过：

- 同一完整输入重复生成相同 JSON；manifest 重放输出逐字符一致。
- shop：12 用户、8 商品、40 订单、120 明细，合计 180 行；实际写入 SQLite 内存库并启用外键。
- helpdesk：4 团队、16 坐席、80 工单，合计 100 行；实际入库并核对工单团队与坐席归属。
- SQLite `foreign_key_check` 无错误；订单联表金额与生成明细总额一致；非法外键插入被数据库拒绝。
- 含引号、逗号、Unicode 及 SQL 片段的商品标签通过参数绑定插入，CSV 再解析后保持原标签。
- 真实本地 HTTP 服务接收列表、详情、创建、非法用户引用请求，返回预期 200/201/422 状态与内容。
- CLI 验证数据集、JSON/NDJSON/CSV、覆盖策略、过小输入限制和无效 JSON 的退出行为符合约定。

## 环境与限制

版本：moon `0.1.20260920 (914d7da 2026-09-20)`；moonc `v0.10.14+7d59c7ec9 (2026-09-18)`；moonrun `0.1.20260920 (914d7da 2026-09-20)`。Windows/MSVC 本地构建；Node `v26.5.1`。

MoonBit 源码检查没有警告。Windows 原生构建时，官方 async 0.22.1 的 C 文件 `internal/event_loop/fs.c` 产生一条 `EINVAL` 宏重定义警告；构建与执行通过，没有修改依赖源码掩盖该警告。

浏览器页面为手动使用示例，本记录不声称已运行自动浏览器测试。没有进行通用性能基准或大规模生产负载测试，也不宣称恒定内存。Python 在集成验证中充当独立数据库/HTTP 消费者；当前没有 MoonBit SQLite 驱动集成测试。
