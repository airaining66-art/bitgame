# Codex / AI 工作守则

## 判定系统不可碎片化

这个游戏的底层判定只有三类:

- 单点
- 连点
- 长按

所有关卡都必须复用这三类判定逻辑。新关卡可以换主题、素材、轨道形状、视觉反馈、界面编排和音效,但不要为了某个主题再创造新的底层判定类型。

实现前先把玩法翻译成这三类之一:

- "扇走"、"格挡"、"叉食材"通常是单点的表现。
- "上司追问"、"太鼓式连打"是连点的表现。
- "回味"、"翻面"、"房东催租"是长按的表现。

固定判定点的长按/连点条要遵守音游常识:判定点固定,条从屏幕外沿轨道进入;条头到达判定点后开始判定;之后条头被判定点吃掉,尾巴继续向判定点移动,所以条会逐渐缩短。轨道可以是直线或弯曲路径,但逻辑不能变。

## RhythmChart first

新的谱面编辑和运行时统一走:

- `godot/rhythm/rhythm_chart.gd`
- `godot/rhythm/rhythm_chart_runtime.gd`
- `godot/charts/*.chart.json`
- `godot/addons/rhythm_editor/`

所有可判定 note 必须映射为 `tap` / `roll` / `hold`; 不需要按下的迷惑项使用 `none`。关卡脚本只负责把这些 note 画成自己的主题表现,不要再新增独立的私有谱面语言。

Normal and Extreme charts must be separate files. Use `LEVEL.chart.json` for normal and `LEVEL_extreme.chart.json` for extreme, and expose both through the Rhythm Editor mode selector.

当需要做特殊关卡表现时,优先参考已有写法:

- 1-2 `mango.gd`:连续滚动和长按。
- 1-3 `schrodinger.gd`:连打、长按胶囊、宝宝模式预警。

不要重做一套孤立机制。如果发现需要新机制,先确认它确实不能归入单点/连点/长按。
# RhythmChart sequencing is global

谱面时间展开只能走统一层:

- `godot/rhythm/rhythm_chart.gd`: 数据模型
- `godot/rhythm/rhythm_chart_sequencer.gd`: 按 beat / duration / subdivision 展开事件
- `godot/rhythm/level_chart_bridge.gd`: 加载普通/极限 chart,套 meta/music,给旧关卡投影 beat slots

关卡脚本只能做表现映射,不能再各自实现私有谱面游标、私有 `round(beat)`、私有 `while cursor` 补空拍,也不能用最后一个 note 来决定流程长度。插件里能编辑到的 note,运行时必须从同一个 sequencer 读到。旧关卡暂时需要一拍一格时,使用 `LevelChartBridge.build_discrete_slots()` 兼容;之后要继续迁到连续 beat clock / subdivision 驱动。
