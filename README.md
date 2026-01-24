# byte_treasurer

JPG图片批量压缩工具, 支持拖放导入, 批量选择, 压缩/原图切换预览, 可视化参数配置.

## 关键假设

- 仅支持JPG/JPEG格式
- 压缩工具通过YAML配置文件声明, 使用Jinja2模板渲染命令行参数
- 压缩后文件存储在应用缓存目录 (`~/.cache/byte_treasurer/compressed/`), 不覆盖原文件

## 架构

```
┌──────────────────────────────────────────────────────────────┐
│                       main.dart                              │
│  ConfigSchema.load() → runApp → HomePage                     │
└──────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐   ┌─────────────────┐   ┌─────────────────────┐
│ config_schema │   │ compress_config │   │   preferences_page  │
│  .dart        │   │     .dart       │   │       .dart         │
│ ─────────────│   │ ────────────────│   │ ────────────────────│
│ YAML解析      │◄──│ 运行时配置      │◄──│ UI: 模式/工具/参数   │
│ 模板渲染      │   │ 命令生成        │   │                     │
└───────────────┘   └─────────────────┘   └─────────────────────┘
        ▲
        │ rootBundle.loadString
┌───────────────┐
│builtin_tools  │
│   .yaml       │
│ ─────────────│
│ 工具/格式声明  │
│ Jinja2模板    │
└───────────────┘
```

## 组件结构

- `HomePage` (StatefulWidget)
  - `LayoutBuilder`
    - `Shortcuts` (快捷键 → Intent映射)
      - `Actions` (Intent → 执行逻辑)
        - `Focus`
          - `GestureDetector`
            - `Column`
              - TopBar (`Container` + 收起/展开按钮)
              - `PaneTheme` > `MultiPane` (panes包, 可拖拽分割)
                - `DropTarget` > `ImageGrid` > `ImageTile` × N
                - `CompressSettingsPanel`
              - StatusBar (`Container` + `Slider`)

- `CompressSettingsPanel` (StatefulWidget)
  - `Container` (左边框)
    - `Column`
      - ModeRow × 3 (总大小/单文件/参数配置模式)
      - ParamConfigSection
        - CommandRow: `SegmentedButton`(模式) + `TextField`/命令预览
        - ToolSelector: `DropdownButtonFormField`
        - ParamsGrid: 双栏`Row` > `ListView` > ParamWidget
      - PreviewSection: `ImageTile` 压缩预览

## 快捷键 (`intents.dart`)

| 功能 | 快捷键 | Intent |
|------|--------|--------|
| 全选 | Ctrl+A | `SelectAllIntent` |
| 取消选择 | Esc | `ClearSelectionIntent` |
| 放大 | Ctrl+= / Ctrl++ / Ctrl+NumpadAdd | `ZoomIntent.zoomIn()` |
| 缩小 | Ctrl+- / Ctrl+NumpadSubtract | `ZoomIntent.zoomOut()` |
| 单选 | 左键 | - |
| 切换选中 | Ctrl+左键 | - |
| 范围选择 | Shift+左键 | - |
| 压缩/切换预览 | 右键 | - |
| 缩放 (滑条) | 滚轮 | - |

## 状态/结构体

| 类 | 维护的状态 |
|------|------|
| `_HomePageState` | `_items`图片列表, `_selectedPaths`选中集合, `_isDragging`拖放态, `_tileWidthRatio`图块宽度比, `_lastSelectedIndex`上次选中索引, `_config`压缩配置, `_showSettingsPanel`设置面板可见性, `_paneController` (panes) |
| `_CompressSettingsPanelState` | `_config`当前编辑配置, `_customCommandController`自定义命令控制器, `_totalSizeController`/`_fileSizeController`大小输入, 预览状态 |
| `ImageItem` | `path`原路径, `originalSize`, `compressedPath`, `compressedSize`, `showCompressed`, `isCompressing` |
| `CompressConfig` | `formatId`, `toolId`, `useCustomCommand`, `customCommand`, `params`参数值Map |
| `ConfigSchema` (静态) | `_tools`工具定义Map, `_formats`格式定义Map |
| `FormatDef` | `id`, `toolIds`, `params`参数定义列表, `toolArgs`工具-参数-模板映射 |
| `ParamDef` | `id`, `type`, `label`, `description`, `defaultValue`, `min`, `max`, `options` |
| `ToolDef` | `id`, `name`, `executable` |

## 异步调用

| 位置 | 调用 |
|------|------|
| `main()` | `ConfigSchema.load()` 加载YAML配置 |
| `_handleFilesDropped` | `ImageItem.fromPath` 读取文件信息 |
| `_handleCompress` | `Future.wait` 并行调用 `_compressor.compress` |
| `ImageCompressor._getCacheDir` | `getApplicationCacheDirectory` 获取系统缓存目录 |
| `ImageCompressor.compress` | `Process.run` 执行外部压缩命令 |
| `CompressSettingsPanel._runPreview` | 实时压缩预览 (防抖300ms) |

## UI交互逻辑

### HomePage

| 操作 | 行为 |
|------|------|
| 拖放JPG文件 | 添加到图片列表 |
| 左键点击图片 | 单选 (清除其他选中) |
| Ctrl+左键 | 切换当前图片选中状态 |
| Shift+左键 | 从上次选中到当前图片范围选择 |
| Ctrl+A | 全选 |
| Esc | 取消全部选择 |
| Ctrl+/-/滚轮 | 缩放图片显示大小 |
| 右键点击图片 | 若未选中则先选中; 未压缩则压缩, 已压缩则切换预览 |
| 点击TopBar收起按钮 | 隐藏/显示压缩设置面板 |
| 拖动分割线 | 调整浏览/设置面板宽度比例 |

### CompressSettingsPanel

| 操作 | 行为 |
|------|------|
| 切换"可视化"模式 | 启用参数控件, 命令栏显示生成的命令预览 |
| 切换"自定义"模式 | 禁用参数/工具选择, 命令栏可编辑 |
| 切换工具 | 保留参数值, 不支持的参数变灰+Tooltip |
| 修改参数 | 实时更新命令预览 |
| 点击复制按钮 | 复制当前命令到剪贴板 |
| 修改任何配置 | 实时回调 `onConfigChanged` 更新主页状态, 防抖触发预览 |
| 点击模式行 | 切换压缩模式 (总大小/单文件/参数配置) |

## 关键数据流

1. 启动 → `ConfigSchema.load()` 解析YAML → 填充`_tools`/`_formats`静态Map
2. 拖放文件 → `_handleFilesDropped` → 创建`ImageItem`加入`_items`
3. 快捷键 → `Shortcuts`匹配 → 触发`Intent` → `Actions`执行对应回调
4. 右键压缩 → `_handleCompress` → 根据模式选择算法 → `Process.run`
5. 设置面板配置变更 → `onConfigChanged` 回调 → `_HomePageState`即时更新`_config`

## 配置文件 (`assets/builtin_tools.yaml`)

```yaml
tools:
  toolId:
    name: 显示名称
    executable: 可执行文件名

formats:
  formatId:
    tools: [toolId1, toolId2]
    params:
      paramId:
        type: slider | switcher | picker
        label: 显示标签
        default: 默认值
        range: [min, max]          # slider专用
        options: {value: label}    # picker专用
    tool_args:
      toolId:
        _input: "{{ input }}"      # _开头为特殊键, _input最前, _output最后
        paramId: "jinja2模板"
        _output: "{{ output }}"
```

模板语法: Jinja2 (`{{ var }}`, `{% if %}`, 字典查找`dict[key]`)

## 构建与启动

```sh
flutter pub get
flutter build linux
./build/linux/x64/release/bundle/byte_treasurer
```

## 开发

### 观测点

| 变量 | 位置 | 说明 |
|------|------|------|
| `_items[i].showCompressed` | HomePage | 当前显示压缩版还是原图 |
| `_items[i].isCompressing` | HomePage | 压缩进行中标志 |
| `_selectedPaths` | HomePage | 当前选中的图片路径集合 |
| `_config.toCommandString()` | HomePage/PreferencesPage | 生成的完整命令 |
| `_config.useCustomCommand` | PreferencesPage | 可视化/自定义模式 |
| `ConfigSchema.formats` | 全局 | 已加载的格式配置 |
| 压缩缓存路径 | - | `~/.cache/byte_treasurer/compressed/` |

### 添加新压缩工具

1. 在`builtin_tools.yaml`的`tools`下添加工具定义
2. 在对应format的`tools`列表中添加toolId
3. 在`tool_args`下添加该工具的参数模板映射
4. 无需修改Dart代码
