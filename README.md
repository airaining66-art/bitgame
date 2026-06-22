# 动次打次 / Bit Reaction Rhythm 🥭🎵

一个用 **Godot 4.6.3** 做的反应节奏小游戏。核心玩法:图标滑/滚向中央判定区,
**该按时在节拍上按、不该按时别按**;部分音符是**长按**、**連打**;答错/漏按扣血。
带连击、Fever(×2 分)、S~D 段位评分、极限模式、暂停。

> 这是给**接手项目的人**(或新开对话的 AI)看的交接文档:读完应能跑起来、看懂
> 结构、知道怎么加新关卡。🟡 = 容易踩的坑。**最重要的一节是 [§2 架构](#2-架构总览
> levelbase--子类)** —— 三关现在都是同一个基类的薄子类。

---

## 0. 快速上手

1. 装 **Godot 4.6.3 (stable)**(无 .NET 版即可)。本机已装在 `D:\godot\Godot_v4.6.3-stable_win64.exe`(带 `_console` 的是命令行版,跑无头校验用它)。
2. 用 Godot 打开本仓库的 **`godot/`** 子目录(`godot/project.godot`)。⚠️ 不是仓库根。
3. **F5** 运行(主场景 `title.tscn` → 选关 → 关卡)。
4. 操作:**空格**=按(长按要按住再松、連打狂点)、**R**=重开、**Esc**=暂停(运行中)/返回(其它),也可点屏幕按钮。左上有 **暂停** 按钮。

---

## 1. 当前状态(2026-06)

**可玩关卡(3 个,都做完了):**
| 关 | 文件 | 主题 / 机制 |
|---|---|---|
| 1-1 生存之战 | `main.gd` | 二进制 0/1,上下相同就按;滑入-停顿式判定;首次进有**新手引导**(组长/试用期梗)+ 金色粒子。8-bit 音乐。 |
| 1-2 芒果奇缘 | `mango.gd` | 浴室瓷砖 + 手持芒果;芒果/水珠连续横向滚动(太鼓达人式);**长按"回味"**;咬芒果会放大+清水珠。东南亚迷幻音乐。 |
| 1-3 薛定谔告白 | `schrodinger.gd` | 像素风烛光晚餐表白;**上下两条独立**(上=食物八分网格 / 下=人脸四分);只在"有对的、没有错的"时按;**双击 / 連打框 / 长按(双条)**;头顶对话气泡;日系 J-pop。**极限版=宝宝模式**(3 段爆发:下面变宝宝、上面变奶瓶、提速 1.5×、四周压暗)。 |

1-4 野摊之王 / 1-5 超绝仰卧起 / 1-6 我有一个PLAN 在选关地图上有名字,**还没做**。

**通用系统(都在基类里):** Fever(命中攒满→6 秒 ×2 分)、S/A/B/C/D 段位(按命中率)、
极限模式(某关 0 掉血三星通关后解锁,选关页出「极限」按钮)、暂停(继续/再来一次/返回关卡)、
存档(三星 + 最高分,写到 `user://progress.cfg`)。

**最近一次大改:把三关重构成 `LevelBase` 基类 + 薄子类**(见 §2),并加了暂停系统。

**仓库:** https://github.com/airaining66-art/bitgame (`main` 分支)。`bitgame.exe`(~97MB)和 `builds/`(安卓/macOS 导出)都已 gitignore,发版走 Releases。

---

## 2. 架构总览(LevelBase + 子类)

整个游戏没有外部依赖、无第三方插件;音效/音乐**全部运行时程序化合成**(`AudioStreamWAV`),不是音频文件。

### 关卡基类 `level_base.gd`(`class_name LevelBase extends Control`)
**所有关卡共用的框架都在这**,改一次三关都生效:
- Conductor 生命周期 + 信号分发;SFX 池 + `tone()` 合成器;`_load_tex()`
- HUD 骨架、Fever 系统、倒计时、**结算页 + S~D 评级 + 分数/最高分记录**
- 暂停接线、计分/扣血/Fever 记账(`_add_score`/`apply_penalty`/`_fever_hit`)
- 判定时间分类 `classify(误差ms)→perfect/good/miss`
- `_input` / `_process` 主循环骨架

**每关 = `extends LevelBase` 的薄子类**,只重写**钩子**:
| 钩子 | 作用 |
|---|---|
| `make_cfg()` | 无 App 时的兜底配置(时长/BPM/曲线) |
| `_conf()` | **主题字典**:颜色、分数标题、Fever/结算/HUD 的色板与文案、`grade_cols`、`score_fmt`、`again_label` 等 |
| `_make_music()` | 返回本关的音乐模块节点 |
| `_make_heart()` | 返回一颗血量图标(各关样式不同) |
| `_build_level()` | 搭本关场景(背景/轨道/按钮/谱面/关卡专属 HUD) |
| `_build_sfx()` | 用 `tone(...)` 造本关音效 |
| `_reset_level()` | 每次重开的关卡状态复位 |
| `_enter_start()` | 默认进倒计时;1-1 重写成新手引导、1-2/1-3 重写成 intro 卡 |
| `_begin_play()` | `conductor.start()` 后的关卡专属准备 |
| `_on_space(pressed)` / `_extra_input(e)→bool` | 空格按下/松开;鼠标/引导等额外输入(返回 true=已消费) |
| `_advance(delta)` | 每帧玩法:布局滚动 + 漏判扫描 + BPM 标签 |
| `_juice(delta)` | 每帧视觉果汁(缩放/呼吸灯/气泡…) |
| `_verdict(掉血数, won)→{rank, eval, color?}` | 结束语(基类负责评级/记录/显示) |
| `_outro_fx()` / `perfect_window()`/`good_window()` / `_countdown_tick(last)` | 收尾特效 / 各关判定窗口 / 倒计时音 |

> 🟡 **判定的拆分原则**:命中/失误的**结果**(加分/连击/Fever、扣血/断连)和**时间分类**
> 在基类;但**"哪个音符到判定线了"这个音符模型**(1-1 滑停 / 1-2 连续滚 / 1-3 八分双轨)
> 留在各关,各自有可单独调的判定窗口。别试图把三种音符模型塞进一个统一引擎。

### Conductor `conductor.gd`(`class_name Conductor`)
节拍/速度的**唯一来源**。所有"该跟拍动"的东西都从它读值。
- `pulse()` 包络驱动一切跟拍视觉;`beat/downbeat/subdivision/level_finished` 信号。
- BPM 用关卡 cfg 的 `bpm_curve_exp` 缓入;按下时刻=每拍 0.75(`JUDGE_OFFSET`)=鼓点。
- `pause()/resume()`:**冻结节拍时钟**(暂停时 `time_ms()` 不走,恢复时平移起点,无缝接上)。
- `tempo_scale`:运行时变速(1-3 宝宝爆发设 1.5)。
- `auto_finish`:`true` 时到时长自动结束;**1-3 设 `false`**,改由谱面跑完(`pass_g>=n_ticks`)来结束。

### 音乐模块(各关一个,已解耦)
| 文件 | class_name | 用于 | 风格 |
|---|---|---|---|
| `chiptune.gd` | `Chiptune` | 1-1 | 8-bit 方波 |
| `lofi.gd` | **`Music`** 🟡(类名不是 LoFi,文件名是历史遗留) | 1-2 | 东南亚迷幻摇滚 |
| `romance.gd` | `Romance` | 1-3 | 日系 J-pop chiptune |

都跟着 `conductor.subdivision` 走(天然踩点、随提速变快),有 `finale` 标记(收尾渐弱)和 `play_outro()`。

### 其它
- `pause_menu.gd`(`PauseMenu`):暂停按钮 + 遮罩面板(继续/再来一次/返回关卡),发信号给关卡接线。
- `app.gd`(autoload **`App`**):全局主题(CJK 字体)、6 关表、场景跳转、存档、`active_cfg()`(极限缩放 / 给 1-3 极限加 `extreme_baby_mode`)、`style_button()`。
- `binary_stream.gd`(`BinaryStream`):1-1 背景二进制流。
- `title.gd` / `level_select.gd`:标题页 / 选关地图(虚线路径、循环芒果动画、极限按钮)。

> 🟡 取 App 单例用**无类型** `var app = get_node_or_null("/root/App")`;写成 `:=` 会推断成
> `Node`、访问自定义成员就编译报错。

---

## 3. 目录结构(`godot/`)

```
project.godot          主场景=title.tscn;autoload App=app.gd
app.gd                 App 单例:主题/关卡表/跳转/存档/active_cfg/style_button
level_base.gd          ★ LevelBase 关卡基类(公共框架)
conductor.gd           Conductor 节拍时钟(pause/tempo_scale/auto_finish)
pause_menu.gd          PauseMenu 暂停菜单
title.gd / .tscn       标题页
level_select.gd/.tscn  选关地图

main.gd / .tscn        1-1 生存之战(extends LevelBase)
mango.gd / .tscn       1-2 芒果奇缘(extends LevelBase)
schrodinger.gd/.tscn   1-3 薛定谔告白(extends LevelBase)

chiptune.gd            Chiptune  — 1-1 音乐
lofi.gd                Music     — 1-2 音乐(类名≠文件名)
romance.gd             Romance   — 1-3 音乐
binary_stream.gd       BinaryStream — 1-1 背景

assets/
  girlsphoto.png       2×2 像素表:上排 梓涵/如烟(脸),下排 烤鸡/沙拉(食物)
  emoji.png            竖排 3 帧:❤ / 😐❓(无语) / 🙂(笑)
  baby.png             1×2:宝宝 / 奶瓶
  mango.png drop.png   5 帧精灵表(被吃/水花)
  mangohand.png        手持芒果主图
  *.png.import         Godot 导入元数据(要提交)
```

> 🟡 `*.gd.uid` 要提交;`.godot/` 缓存目录已 gitignore(打开工程自动重建)。

---

## 4. 怎么加一个新关卡(下一步就是做 1-4 起)

1. 在 `app.gd` 的 `_build_levels()` 把对应关 `unlocked=true`、填 `scene`(如 `res://stall.tscn`)和 `cfg`(用 `_cfg(时长ms, 起始bpm, 结束bpm)`)。
2. **复制一份现成关卡当模板**(玩法最像哪个就抄哪个:1-2 滚动+长按、1-3 双轨+連打+宝宝)。把脚本 `extends LevelBase`,删掉与基类重复的部分,重写 §2 列的钩子:`_conf`(换配色/文案)、`_make_music`、`_build_level`(换美术/谱面)、`_advance/_juice`、`_verdict`、`_build_sfx`,以及本关独有的判定/布局/特效内部类。
3. 新建 `.tscn`:一个根 `Control` 节点挂上脚本即可(看任意一关的 `.tscn`,就 6 行)。
4. 美术特效(`_World`/`_Dinner`/`_Rings`/`_Caps`…)和音效都写在**子类文件里**,不进基类。

---

## 5. 资源约定

- **5 帧精灵表**(`mango.png`/`drop.png`,750×150,每帧 150):第 0 帧=静态图标,命中播 0→4 帧消失动画。
- **`girlsphoto.png` 2×2 / `baby.png` 1×2 / `emoji.png` 竖排 3 帧**:按象限/等分切区域,用 `texture_filter=NEAREST` 保持像素硬边。
- 加载走基类 `_load_tex(...)`:先 `ResourceLoader`(导入资源),再 `Image.load`(松散 PNG)兜底——丢张同名 PNG 进 `assets/` 重跑就生效。
- 大量手绘/像素效果是代码 `_draw()` 画的(瓷砖墙、烛光、像素呼吸灯、长按胶囊、对话气泡、地图虚线…),无需素材。

---

## 6. 导出(发给别人玩)

1. Godot 顶部 **Editor → Manage Export Templates → Download and Install**(一次性)。
2. **Project → Export…** → 已有 **Windows Desktop** 预设(`export_presets.cfg`,单文件 `embed_pck`)→ 输出 `godot/bitgame.exe`。也有 iOS / 安卓 / macOS 预设。
3. 🟡 `bitgame.exe`(~97MB)和 `builds/` 已 gitignore——别进 git,发版用 **GitHub Releases**。

---

## 7. 开发 & 调试贴士

- 命令行版 `Godot_v4.6.3-stable_win64_console.exe`。
- **改了 `class_name` / 加了新脚本后,先 `--import` 重建全局类缓存**,否则无头跑可能报 "Could not find type":
  ```
  Godot_..._console.exe --headless --path godot --import
  ```
- 无头解析校验:`--headless --path godot res://<关卡>.tscn --quit-after 60`,看有没有 `SCRIPT ERROR`。
- 跑全程/手感测试:写个一次性 `_smoke.tscn` 驱动器(`instantiate` 关卡→`begin_run()`→把 `health` 钉高→定时按键),跑完打印 `phase/score`,**用完即删**。截图用真机窗口跑(非 `--headless`)+ `get_viewport().get_texture().get_image().save_png(...)`。
- 🟡 **F5(编辑器)会报、导出 exe 静默忽略的错**:Debug 构建打印脚本错误,Release 忽略。排查以 F5 的 Debugger 为准。
- 🟡 **CJK 字体**:Godot 自带字体不含中文,`app.gd` 运行时从 Windows 系统字体(`msyh.ttc`)加载设为全局 `theme.default_font`。**非 Windows 上中文会变方块**——跨平台需把 CJK `.ttf` 放进 `assets/` 改加载逻辑。

---

## 8. 路线图 & 已知技术债

**约定的后续顺序:**
1. ✅ Fever + 段位评分
2. ✅ 新机制(1-3 双轨 / 連打 / 长按 / 宝宝模式)
3. **铺关卡 1-4 ~ 1-6**(野摊之王 / 超绝仰卧起 / 我有一个PLAN)——每关一个新花样 + 主题 + 音乐
4. **打工人剧情线**(串起组长/试用期的梗,关卡间插小对话)

**已知技术债 / 注意:**
- `lofi.gd` 类名是 `Music`(文件名历史遗留),别被名字误导。
- CJK 字体依赖 Windows 系统字体,跨平台要内置字体。
- 1-3 极限版(宝宝模式)的谱面较长,曾因时长被掐断,现已用 `auto_finish=false` 改成谱面驱动结束。

---

玩得开心,接手顺利 🌹
