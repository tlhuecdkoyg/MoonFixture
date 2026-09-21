# 模型格式与错误处理

顶层对象包含 `name` 与 `entities`。实体包含 `name`、`count`、`fields`；字段包含 `name`、`generator`，以及可选的 `primary`、`unique`、`null_per_mille`。未知属性会报错。名称只允许 1–128 个 ASCII 字母、数字或下划线；名称可以以数字开头，SQLite 导出会引用标识符。

最小模型：

```json
{"name":"demo","entities":[{"name":"items","count":3,"fields":[{"name":"id","primary":true,"generator":{"kind":"sequence","start":1,"step":1}}]}]}
```

| kind | 必需属性 | 含义 |
| --- | --- | --- |
| `constant` | `value` | 单个标量，允许 null |
| `sequence` | `start`, `step` | `start + 行下标 × step`，检查 Int32 溢出 |
| `integer` | `min`, `max` | 闭区间整数抽样 |
| `boolean` | `chance` | true 概率，0–1000 千分比 |
| `choice` | `values` | 非空、非 null 标量数组 |
| `weighted_choice` | `values` | `[{"value":"low","weight":1},{"value":"high","weight":9}]`；权重为正整数，总和不超过 Int32 最大值 |
| `pattern` | `alphabet`, `length` | 从 Unicode 字符集合逐位抽样，长度 0–65536；不是正则表达式 |
| `date_offset` | `min`, `max` | 相对参考 UTC 日期的闭区间天数偏移，输出日期字符串 |
| `reference` | `entity`, `key` | 从父表的唯一、不可配置为空的键中选择值 |
| `copy` | `field` | 复制同一行字段 |
| `add`, `multiply` | `left`, `right` | 两个同一行整数运算，不允许 null |
| `concat` | `fields`, `separator` | 按字段顺序连接文本表示，null 表示为空字符串 |
| `lookup` | `field`, `entity`, `key`, `value` | 用本行 field 查父表 key，复制父表 value 字段 |

声明顺序不必等于求值顺序。实体和字段分别进行稳定拓扑排序；输出字段保持模型声明顺序，表按求值顺序输出。模型编译时复制内部数组，因此外部修改原始模型不会改变已编译计划。

默认 Limits：128 个实体，每个实体 256 个字段，总计 1,000,000 行、5,000,000 个单元格、10,000,000 个 UTF-16 文本单元，每个唯一值最多尝试 256 次。库可传入自定义 `Context`；独立校验/SQLite 适配使用默认模型规模限制。输入 JSON 额外限制 64 层嵌套。

错误结构为 `Issue { code, path, message }`。调用方应按 `code` 分支，`message` 为说明文字。常见错误：

| code | 处理建议 |
| --- | --- |
| `dependency_cycle` | 拆除循环的实体/字段依赖 |
| `missing_entity`, `missing_field`, `missing_key` | 检查引用名称 |
| `nonunique_reference` | 将父键配置为 unique 或 primary |
| `unsatisfiable_unique` | 减少行数、扩大有限域或取消唯一要求 |
| `attempt_budget` | 增大有效域或预算；此错误不证明约束一定无解 |
| `invalid_operand`, `arithmetic_overflow` | 修正派生字段类型或数值范围 |
| `date_overflow` | 调整日期偏移与参考时间 |
| `row_limit`, `cell_limit`, `text_limit` | 缩小数据规模或显式调整相应限制 |
| `input_limit`, `nesting_limit` | 缩小输入或降低 JSON 嵌套层数 |
| `foreign_key`, `derived_value`, `duplicate_key` | 外部/变异数据违反了模型约束 |

`Scenario` 是模型覆盖：改变行数、生成器或空值概率后重新编译。`Mutation` 是生成后变异：操作按顺序执行，行下标指向前一步操作后的结果。变异失败不修改原数据；成功时返回变异后的副本、操作记录和独立校验报告。一项变异可能触发多个约束错误。

`compare_datasets` 对声明了主键的表按主键匹配，其他表按行下标匹配；它比较内容而非 seed、算法或参考时间。missing 和 null 是不同变化。`check_expectations` 对最终数据检查行数、非空、整数/文本边界、大小关系、求和及父子数量，可用作集成测试的独立期望。
