# MoonFixture

[![CI](https://github.com/tlhuecdkoyg/MoonFixture/actions/workflows/ci.yml/badge.svg)](https://github.com/tlhuecdkoyg/MoonFixture/actions/workflows/ci.yml)

**MoonBit 原生的可复现关联测试数据构造库。** 用一个显式模型定义实体、主外键、唯一字段和派生关系，为数据库集成测试、接口回归与前端演示生成同一套可重放数据。

Fixture 是测试运行前准备好的数据和环境；MoonFixture 聚焦其中的结构化数据。项目提供可复用库和原生 CLI，不是姓名词库，也不负责执行测试框架或求解任意业务约束。

## 已实现能力

- 确定性 UInt32 随机流；按实体、字段、行及尝试次数隔离；完整模型、种子、UTC 参考时间和算法版本重放。
- 常量、序列、整数区间、布尔概率、枚举、加权枚举、Unicode 字符串和相对日期。
- 主键、唯一字段、外键、字段依赖、父表查值、整数加法/乘法及文本组合；稳定拓扑排序与循环诊断。
- 有限唯一域无放回抽样；其他唯一约束使用明确的尝试预算；区分域耗尽与预算耗尽。
- 命名场景覆盖；在副本上定向修改、删除或复制记录，并报告实际违反的约束。
- 独立数据校验、业务期望断言、按主键比较、字段分布统计、关联查询及聚合结果构造。
- JSON、NDJSON、CSV 和参数化 SQLite 批次；支持接收端停止并恢复的分批导出。
- 输入大小/嵌套深度、实体数、字段数、总行数、单元格数、文本量和尝试次数限制。

## 工具链与验证环境

本项目开发验证使用 **2026-09-21 从 MoonBit 官方发布通道下载的工具链**。以下是实际二进制版本，不以“最新稳定版”代替版本信息：

| 组件 | 版本 |
| --- | --- |
| moon | `0.1.20260920 (914d7da 2026-09-20)` |
| moonc | `v0.10.14+7d59c7ec9 (2026-09-18)` |
| moonrun | `0.1.20260920 (914d7da 2026-09-20)` |
| CLI 依赖 | `moonbitlang/async 0.22.1`、`moonbitlang/x 0.5.5` |
| 本地验证 | Windows / MSVC；Node.js `v26.5.1` |

库支持 `wasm`、`wasm-gc`、`js`、`native`；CLI 仅支持 `native`。核心库只导入 MoonBit core；上述第三方模块供 CLI 使用。CI 在 Linux/Windows 上安装官方发布通道工具链并打印完整版本，用于发现后续兼容性变化；它不等于锁定本次验证版本。

## 作为库使用

```sh
moon add tlhuecdkoyg/MoonFixture@0.1.0
```

在调用包的 `moon.pkg` 中加入：

```moonbit
import {
  "tlhuecdkoyg/MoonFixture" @fixture,
}
```

以下完整测试可以放入调用包的测试文件：

```moonbit
test "relational fixture" {
  let model : @fixture.Model = {
    name: "shop",
    entities: [
      {
        name: "users", count: 5,
        fields: [@fixture.Field::new("id", Sequence(1, 1), primary=true)],
      },
      {
        name: "orders", count: 20,
        fields: [
          @fixture.Field::new("id", Sequence(100, 1), primary=true),
          @fixture.Field::new("user_id", Reference("users", "id")),
          @fixture.Field::new("quantity", IntegerRange(1, 5)),
          @fixture.Field::new("unit_price", Constant(Integer(200))),
          @fixture.Field::new("total", Multiply("quantity", "unit_price")),
        ],
      },
    ],
  }
  let context = @fixture.Context::new(2026U)
  let plan = @fixture.compile(model, context~).unwrap()
  let data = plan.generate().unwrap()
  assert_true(@fixture.validate_dataset(model, data).is_valid())
  assert_eq(@fixture.replay(plan.replay_json()).unwrap(), data)
}
```

可复用 API 的完整签名由 `moon info` 生成，见 [pkg.generated.mbti](pkg.generated.mbti)。模型文件格式及各生成器字段见 [模型说明](docs/MODEL.md)。

## 命令行

在仓库目录执行。`moon run` 的 `--` 后为程序参数：

```sh
moon run cmd/main --target native -- --help
moon run cmd/main --target native -- generate examples/shop.json --seed 2026 --output shop-data.json
moon run cmd/main --target native -- validate shop-data.json --model examples/shop.json
moon run cmd/main --target native -- manifest examples/shop.json --seed 2026 --output replay.json
moon run cmd/main --target native -- replay replay.json --output replayed-data.json
moon run cmd/main --target native -- generate examples/shop.json --format csv --table products
moon run cmd/main --target native -- generate examples/shop.json --format sqlite --output sqlite-batches.json
```

`plan` 只编译模型，不生成数据。`-` 可表示标准输入/输出。文件默认以新建方式写入；`--force` 允许覆盖已有输出，但仍拒绝覆盖输入和校验模型。退出码：`0` 成功，`1` 模型/数据失败，`2` 参数或 I/O 失败。CLI 默认每个输入文件最多 16 MiB；`--max-input` 可调整。

SQLite 输出是包含 DDL、`?` 占位符语句和参数数组的 JSON 包。调用方应在事务外启用 `PRAGMA foreign_keys = ON`，然后在一个事务中建表并绑定参数插入；出现错误时回滚。库本身不包含 SQLite 驱动。

## 可实际运行的使用场景

1. **数据库集成测试**：`examples/shop.json` 生成用户、商品、订单、明细。集成脚本使用 Python 标准库 SQLite 驱动实际入库，开启外键，执行联表金额汇总，与生成明细比较，并确认非法外键被数据库拒绝。
2. **接口回归测试**：相同订单数据装入一个真实本地 HTTP 示例服务。脚本通过 socket 请求列表、详情、新增订单及非法用户引用，校验响应。此服务是可运行的示范消费者，不宣称已有第三方业务系统接入。
3. **前端演示与空状态测试**：生成 JSON 后，直接打开 `examples/browser/index.html` 并选择文件，查看实体切换、分页和 Unicode 文本。把未被引用的子表 `count` 改成 `0`，即可生成空列表。页面通过 `textContent` 展示值，数据不上传到服务器。
4. **第二业务领域复用**：`examples/helpdesk.json` 构造团队、坐席和工单，包含坐席归属查值、优先级、相对日期和可空备注；无需修改引擎。集成脚本独立校验工单团队与坐席团队一致。

运行数据库和 HTTP 集成：

```sh
moon build --target native --deny-warn
python scripts/integration.py
```

Python 仅作为独立验证消费者；所有模型解析、约束规划、随机构造及数据导出均由 MoonBit 实现。浏览器示例供手动验证，未将其计作自动浏览器测试。

## 测试与代码统计

```sh
python scripts/verify.py
python scripts/count_lines.py --minimum 4000
```

验证脚本运行四后端检查与测试、格式检查、API 生成、生产代码统计、本机 CLI 构建和真实 SQLite/HTTP 集成。测试覆盖固定随机参考向量、64 组种子关联模型、唯一域耗尽、日期边界、派生溢出、循环依赖、重放、错误输入、批次恢复与副本隔离。

统计脚本只计算根库、`cli/`、`cmd/` 下手写 `.mbt` 文件的有效非空代码行；排除注释、帮助文本块、测试、示例、依赖、生成接口和构建产物。统计值可由脚本重算，详细验证记录见 [VALIDATION.md](docs/VALIDATION.md)。

## 可复现性及边界

- 可复现输入包括模型、种子、算法版本、参考时间及资源限制。日期不读取系统时钟。模型指纹是非密码学摘要，仅辅助定位；完整 manifest 才是重放依据。
- 添加无关字段不会改变已有独立随机流；修改父表规模、唯一约束或依赖可能改变关联结果。升级算法或生成语义可能改变结果，应随包版本固定重放环境。
- 值域为 `Null / Bool / Int32 / String`。金额建议用最小货币单位整数；不提供浮点金额或任意精度数值。整数随机区间最多包含 `2147483647` 个值。
- 日期采用公历 `0001-01-01` 到 `9999-12-31`，偏移单位为天。参考时间格式固定为 `YYYY-MM-DDTHH:MM:SSZ`，不支持时区偏移、分数秒和闰秒。
- 只支持单字段主键和有向无环依赖；多对多可用中间表表达。没有任意约束求解器、循环关系生成器或完整 JSON Schema 支持。
- 非空唯一整数、布尔、普通枚举、有限字符串、日期和引用域采用无放回抽样。普通枚举的重复值在唯一模式下去重；唯一布尔抽样也不再保持原始概率。加权枚举保持权重抽样，并受唯一重试预算约束。
- `null_per_mille` 是每行抽样概率，不保证精确比例。唯一字段允许多个 null；常量/复制/查值也可产生 null。主键始终禁止 null。
- 数据集整体驻留内存；主键索引、唯一集合和比较结果亦占内存。批次 API 只减少导出阶段的额外缓冲，未承诺流式生成或常量内存。
- 数据集 JSON 的 seed 使用十进制字符串；导入后字段按名称排序，校验按名称匹配。CSV 中 null、缺失字段与空字符串均导出为空单元格，因此不可无损恢复类型。JSON 重复键沿用 core JSON 解析器的覆盖语义，请勿依赖重复键表达模型。
- SQLite 适配不声明列类型亲和性，以区分字符串 `"1"` 与整数 `1`；拒绝同列混合布尔与整数，避免 SQLite 的类型折叠。对数据库驱动的测试在 Python SQLite 消费者上进行，并未声称已实现 MoonBit SQLite 驱动接入。

## 原创性与许可证

MoonFixture 为原创 MoonBit 实现，采用 Apache-2.0。确定性随机算法、拓扑排序和无放回抽样属于通用算法；不是 Faker 或其他项目的源码移植。相邻项目及定位差异见 [设计说明](docs/DESIGN.md)，依赖和复用说明见 [THIRD_PARTY.md](THIRD_PARTY.md)。
