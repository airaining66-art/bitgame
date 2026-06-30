# RhythmChart 调整说明

这个目录是关卡谱面的唯一入口。后面想改节奏、音乐参数、普通/极限模式，不要去改关卡脚本里的私有数组，优先改这里的 `*.chart.json`，或用 Godot 底部的 **Rhythm Editor** 面板保存。

## 文件命名

- 普通模式：`LEVEL.chart.json`，例如 `1-5.chart.json`
- 极限模式：`LEVEL_extreme.chart.json`，例如 `1-5_extreme.chart.json`
- 普通和极限必须是两个文件。没有极限文件时，选关页不会显示极限按钮，也不会偷偷回退到普通谱。

## Note 类型

底层判定只允许这四个 `judge_type`：

- `tap`：单点。例子：扇走、格挡、叉食材、表白时说对话。
- `roll`：连点条。例子：上司追问、太鼓式连打、宝宝模式连续喂奶。
- `hold`：长按条。例子：回味、翻面、房东催租。
- `none`：不需要按的迷惑项。通常放在 `lane: "decoy"`。

关卡脚本只负责把这些 note 画成自己的主题表现，不要新增第五种底层判定。

## 1-3 的 Non-node / 干扰项

第三关的判定规则比较特殊：不是“看到正确图标就一定按”，而是“判定点上有正确项、且没有错误项时才按”。所以 1-3 里：

- `lane: "node" + judge_type: "tap"`：可按的正确项。
- `lane: "decoy" + judge_type: "none" + kind: "trap"`：可见错误项，按了会罚。
- `judge_type: "none" + kind: "food_correct"/"face_correct"/"both_correct"`：可见但不该按的正确外观迷惑项。
- `kind: "empty"`：真正空格，通常不用手动新增。

Rhythm Editor 在 1-3 里会显示 `Top` / `Bottom` 控件：

- `Auto`：按 `kind` 默认映射。
- `Empty`：该轨没有图标。
- `Correct`：该轨显示正确食物/人脸。
- `Wrong`：该轨显示错误食物/人脸。

如果在 1-3 的 Non-node 轨上新增 note，当前 kind 是 `empty` 时会自动改成 `trap`，避免新增出看不见的空拍。

## 常用字段

- `beat`：note 头部到达判定点的拍号，可以是小数拍。
- `duration_beats`：`roll`/`hold` 的长度，单位是拍。`tap` 通常为 `0`。
- `kind`：关卡主题里的表现类型，比如 `bill`、`boss`、`beef`、`hold`。
- `lane`：`node` 是正常判定项，`decoy` 是迷惑项。
- `payload`：少量关卡参数。优先用编辑器工具栏里的字段改，不要手写时拼错 key。

当前编辑器支持的 payload：

- `need`：连点挑战需要点几下。
- `need_ms`：长按挑战需要按住多少毫秒。
- `warn_beats`：挑战开始前提前几拍预警。
- `strip_len`：1-5 压力条视觉长度。

## Meta / 音乐参数

每个 chart 的 `meta` 会覆盖关卡默认音乐配置：

- `start_bpm` / `end_bpm` / `bpm_curve_exp`：BPM 曲线。
- `duration_beats`：谱面总长度。不要靠最后一个 note 隐式决定关卡长度。
- `subdivisions`：编辑和展开时的细分。
- `music_path`：本关音乐脚本路径，例如 `res://rent_music.gd`。

运行时会按 `RhythmChartSequencer` 展开 `beat` 和 `duration_beats`。固定判定点的长按/连点条应理解为：条头先到判定点开始判定，之后条头被吃掉，尾巴继续向判定点移动，视觉上逐渐缩短。

## 保存前检查

在 Rhythm Editor 里点 **Validate**。如果手动改 JSON，至少确认：

- `tap`/`none` 不需要正数 `duration_beats`。
- `roll`/`hold` 必须有正数 `duration_beats`。
- `lane: "decoy"` 只能配 `judge_type: "none"`。
- `id` 不重复。
- `beat` 和 `duration_beats` 不为负数。

这些规则也会在运行时加载 chart 时校验；有错误会阻止加载，避免关卡悄悄用旧兜底谱。
