# 动次打次 / Bit Reaction Rhythm 🥭🎵

一个用 **Godot 4.6.3** 做的反应节奏小游戏。玩法核心:上下两排图标滑/滚向中央判定区,**相同就在节拍上按、不同就别按**;部分音符是**长按(回味)**。带连击、Fever、段位评分、极限模式。

> 这份 README 是给接手项目的人看的——读完应该能跑起来、看懂结构、知道怎么加新关卡。有 🟡 标记的是容易踩的坑。

---

## 0. 快速上手

1. 装 **Godot 4.6.3 (stable)**(无 .NET 版即可):https://godotengine.org/download
2. 打开本仓库的 **`godot/`** 目录作为 Godot 项目(`godot/project.godot`)。
3. **F5** 运行(主场景是 `title.tscn`)。
4. 操作:**空格** = 按(长按音符要按住再松)、**R** = 重开本关、**Esc** = 返回选关、鼠标点「PRESS/咬一口」按钮也行。

> 🟡 **项目在 `godot/` 子目录里**,不是仓库根。仓库根目录还放着早期的网页原型(`game.js`/`index.html`/`style.css`/`server.cjs`),那是移植前的参照物,**不参与 Godot 工程**。

---

## 1. 技术栈 & 平台

- **引擎**:Godot 4.6.3,GDScript,Forward+ 渲染。
- **目标平台**:Windows 桌面,基准分辨率 **1280×720**(`canvas_items` + `expand` 自适应缩放)。
- **无外部依赖、无第三方插件**。音效/音乐全部**运行时程序化合成**(`AudioStreamWAV`),不是音频文件。

> 🟡 **中文字体**:Godot 自带字体不含 CJK。`app.gd` 在运行时从 **Windows 系统字体**(`C:/Windows/Fonts/msyh.ttc` 等)加载微软雅黑,设为全局 `theme.default_font`。**在非 Windows 上中文会变方块**——要跨平台得把一个 CJK `.ttf/.otf` 放进 `assets/` 并改 `app._build_theme()` / `main._apply_cjk_font()`。

---

## 2. 怎么导出 exe(发给别人玩)

1. Godot 顶部菜单 **Editor → Manage Export Templates → Download and Install**(一次性,几百 MB)。
2. **Project → Export…** → 已有 **Windows Desktop** 预设(`export_presets.cfg`,单文件 `embed_pck`)→ **Export Project** → 输出 `godot/bitgame.exe`。
3. 命令行也行:`Godot_..._console.exe --headless --path godot --export-release "Windows Desktop" bitgame.exe`

> 🟡 **`bitgame.exe`(~97MB)被 `.gitignore` 排除了**(超 GitHub 单文件限制、也不该进 git)。给朋友发 exe 用 **GitHub Releases** 附件或网盘。

---

## 3. 目录结构(`godot/`)

```
godot/
  project.godot          # 主场景 = title.tscn;autoload: App = app.gd
  export_presets.cfg     # Windows / iOS 导出预设

  app.gd                 # 【autoload "App"】全局单例:主题(CJK字体)、关卡表、
                         #   场景跳转、存档(三星/最高分/极限)、cfg 缩放
  title.gd / .tscn       # 标题页(动次打次 + 菜单 + 手绘红按钮)
  level_select.gd/.tscn  # 选关地图(6 个节点、循环芒果动画、极限按钮、二进制终端)

  main.gd / .tscn        # 关卡 1-1「生存之战」(二进制 0/1 反应,滑入式)
  mango.gd / .tscn       # 关卡 1-2「芒果奇缘」(芒果/水滴 + 长按,连续滚动式)

  conductor.gd           # 【class_name Conductor】节拍/速度的唯一来源(核心)
  chiptune.gd            # 【class_name Chiptune】1-1 的 8bit 音乐
  lofi.gd                # 【class_name Music】1-2 的东南亚迷幻音乐 ⚠️见下
  binary_stream.gd       # 【class_name BinaryStream】1-1 背景的二进制流

  assets/
    mangohand.png        # 手持芒果主图(单张,透明)
    mango.png            # 芒果图标,750×150 = 5 帧"被吃掉"动画(第1帧=完整)
    drop.png             # 水滴图标,750×150 = 5 帧"炸开"动画(第1帧=完整)
    *.png.import         # Godot 导入元数据(要提交)
```

> 🟡 **`lofi.gd` 里的类名是 `Music`**(不是 LoFi)。文件名是历史遗留,内容早已不是 lo-fi 而是"东南亚迷幻摇滚"。`mango.gd` 里用 `var lofi: Music`。
> 🟡 **`*.gd.uid` 文件要提交**(Godot 4.4+ 的脚本 UID)。**`.godot/` 缓存目录已 gitignore**,打开工程会自动重建。

---

## 4. 架构 & 核心系统

### 场景流
`title.tscn` → `level_select.tscn` → `main.tscn` / `mango.tscn`,全部由 **`App`**(autoload)用 `change_scene_to_file` 切换:`App.goto_title()` / `goto_levels()` / `play_level(index, extreme)`。

### Conductor(`conductor.gd`)—— 一切节奏的源头
所有"该跟着节拍动"的东西都从它取值,保持解耦、可复用。
- 时间/速度:`time_ms()`、`beat_phase()`(0..1)、`bpm()`,BPM 用关卡 cfg 的 `bpm_curve_exp` 做缓入,**踩点时刻 = 每拍 75%(`JUDGE_OFFSET=0.75`)= 鼓点落点**。
- 信号:`beat(cycle)` / `downbeat(cycle)` / `subdivision(cycle, sub)` / `level_finished`。
- `pulse(sharpness)`:每个下拍冲到 1、随后衰减的包络——**呼吸灯/UI 跟拍闪动/缩放都读它,别自己写计时器**。
- 关卡通过 `setup(cfg)` 注入配置。

### 音乐(`chiptune.gd` / `lofi.gd`)
跟着 `Conductor.subdivision` 走,所以**天然踩点、随加速变快**。各自有 `finale` 标记:接近结尾时收束声部,让人**听得出要结束了**;关卡 `play_outro()` 收个尾和弦。

### 关卡(`main.gd` / `mango.gd`)
两关是**各自独立的场景**,目前**各写各的判定循环**(有重复)。共用的是 Conductor、音乐模块、资源加载、Fever/段位逻辑(分别在两边实现了一份)。
- **1-1 滑入式**:音符滑到中央停一拍再判定(经典反应)。
- **1-2 连续滚动式(太鼓达人风)**:音符匀速横向滚过固定判定区。长按是"头到中央停住 + 尾部滚进来 + 框收缩"。

### 判定
- 普通:`Perfect / Good` 窗口(ms,随 BPM 收紧);该按没按 = Miss,不该按却按 = 错。
- **长按(仅 1-2)**:按**按住状态**判定——头部那拍只要在按住就起判(容忍提前按),中段持续不松就连续加分,**尾部到中央前松手才算断**(容忍延迟松开)。

### Fever + 段位 + 极限(两关都有)
- **Fever**:`fever_gauge` 命中积累,满了进 6 秒 Fever(**得分 ×2** + 全屏暖色跟拍闪 + "FEVER!!"),Miss/断长按立刻退出。
- **段位**:结算按命中率给 **S(≥97%)/A/B/C/D**,显示命中率 + **个人最高分**(破纪录有 ★)。
- **极限模式**:某关 **0 掉血三星通关** → 选关页该关出现「极限 1.5×」按钮 → `App.play_level(i, true)`,`App.active_cfg()` 把 BPM×1.5、时长÷1.5。

### 存档
`App` 把三星记录和最高分写到 **`user://progress.cfg`**(Windows 上在 `%APPDATA%\Godot\app_userdata\…`)。普通/极限的最高分分开存(key 是 `index` 和 `index_ex`)。

---

## 5. 关卡是怎么"成谱"的

- **1-2** 用**固定有限谱面** `const CHART`(token:`m`=芒果该按 / `w`=水滴该按 / `-`=不该按 / `H`=3拍长按 / `E`=结束标记)。打一遍就结束,**最后一个音符后不再出新的**,到 `E` 自动收尾。
- **1-1** 是**带连段封顶的随机生成**(`press_ratio` + `max_skip_run`/`max_press_run`),结尾段(progress>0.9)自动安静下来。

关卡 cfg(在 `app.gd` 的 `_cfg(duration_ms, start_bpm, end_bpm)`)字段:`duration_ms / start_bpm / end_bpm / bpm_curve_exp / subdivisions / press_ratio / max_skip_run / max_press_run`。

---

## 6. 怎么加一个新关卡(下一步路线就是做 1-3 起)

1. 在 `app.gd` 的 `_build_levels()` 里把对应关卡 `unlocked=true`、填上 `scene`(如 `res://schrodinger.tscn`)和 `cfg`。
2. 新建场景 + 脚本。**最省事**是参考 `mango.gd` 复制一份:它已经把 Conductor、音乐、判定、Fever、段位、结算都接好了;换主题美术、换音乐模块、改 `CHART` 即可。
3. 想加**新机制**(连打 / 双轨 / 躲避音符 / 变速等)就在新关里扩;Conductor/Fever/段位这些通用件继续复用。

> 🟡 **重构提示**:`main.gd` 和 `mango.gd` 的判定/HUD/结算目前是**两份重复代码**。要做 1-3~1-6,建议先把"判定循环 + Fever + 段位 + 结算"抽成一个共享基类/组件,再让各关只配置主题、谱面、机制。现在没抽是因为前两关玩法差异大、边做边调。

---

## 7. 资源约定 & 美术

- **图标是 5 帧精灵表**(`mango.png` / `drop.png`,750×150,每帧 150×150):**第 0 帧 = 静态图标**,命中时播放 0→4 帧的"被吃/炸开"消失动画。新图标按这个格式做。
- 加载走 `_load_tex(...)`:**先 `ResourceLoader`(导入资源),再 `Image.load`(松散 PNG)兜底**——所以丢张同名 PNG 进 `assets/` 重跑就生效,不必手动导入。
- 大量手绘/像素效果是**代码 `_draw()` 画的**(瓷砖墙、判定光环、长按胶囊、手绘红按钮、地图虚线路径等),风格统一、无需素材。

---

## 8. 开发 & 调试小贴士

- **无头校验**(不开窗口跑几帧抓报错):
  ```bash
  Godot_v4.6.3-stable_win64_console.exe --headless --path godot --import
  Godot_v4.6.3-stable_win64_console.exe --path godot res://mango.tscn --quit-after 90
  ```
- **跑满全程**测结尾/结算:`--path godot res://mango.tscn`(关卡到点会自动收尾→结算)。
- 🟡 **F5(编辑器)会报、导出 exe 不报的错**:Debug 构建会打印脚本错误,Release 会**静默忽略**。之前就有个"结算时数组越界"只在 F5 暴露(已修)。**接手后请以 F5 的 Debugger 输出为准排查**。
- 🟡 改了 `class_name` 或新加脚本后,Godot 要重建全局类缓存——**先 `--import` 一次**再 `--headless` 跑,否则可能报 "Could not find type"。

---

## 9. 现状 & 路线图

**已完成**:标题/选关/两个可玩关卡(1-1 生存之战、1-2 芒果奇缘)、连击、Fever、S~D 段位+最高分、极限模式、干净的关卡结尾、Windows 导出。

**约定的后续顺序**(和原作者商量过):
1. ✅ Fever + 段位评分(已做)
2. **新机制**(给 1-3 起的关卡用:连打 / 双手两轨 / 躲避音符 / 中途变速等)
3. **铺关卡 1-3 ~ 1-6**(地图上已命名:薛定谔告白 / 野摊之王 / 超绝仰卧起 / 我有一个PLAN),每关一个新花样 + 主题 + 音乐
4. **打工人剧情线**(串起"组长/试用期"的梗,关卡间插小对话)

**已知技术债**:① 两关判定逻辑重复,做更多关前建议抽共享基类;② CJK 字体依赖 Windows 系统字体,跨平台需内置字体。

---

玩得开心,接手顺利 🌹
