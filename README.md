# byte_treasurer

JPG图片批量压缩工具, 支持拖放导入、批量选择、压缩/原图切换预览。

## 关键假设

- 仅支持JPG/JPEG格式
- 压缩质量固定85%
- 压缩后文件存储在应用缓存目录 (`~/.cache/byte_treasurer/compressed/`), 不覆盖原文件

## 组件结构

- `HomePage` (StatefulWidget)
  - `LayoutBuilder`
    - `Shortcuts` (快捷键 → Intent 映射)
      - `Actions` (Intent → 执行逻辑)
        - `Focus`
          - `GestureDetector`
            - `Column`
              - `DropTarget`
                - `ImageGrid` (StatelessWidget)
                  - `ImageTile` (StatelessWidget) × N
              - 状态栏 (`Container` + `Slider`)

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

## 有状态组件

| 组件 | 状态 |
|------|------|
| `_HomePageState` | `_items` (图片列表), `_selectedPaths` (选中集合), `_isDragging` (拖放状态), `_tileWidthRatio` (图块宽度比例, 0~1), `_lastSelectedIndex` (上次选中索引), `_focusNode` (焦点节点) |
| `ImageCompressor` | `_cacheDir` (缓存目录实例) |

## 异步调用

| 位置 | 调用 |
|------|------|
| `_handleFilesDropped` | `ImageItem.fromPath` (读取文件信息) |
| `_handleCompress` | `Future.wait` 并行调用 `_compressor.compressJpg` |
| `ImageCompressor._getCacheDir` | `getApplicationCacheDirectory` (获取系统缓存目录) |

## UI交互逻辑

| 操作 | 行为 |
|------|------|
| 拖放JPG文件 | 添加到图片列表 |
| 左键点击图片 | 单选 (清除其他选中) |
| Ctrl+左键 | 切换当前图片选中状态 (不影响其他) |
| Shift+左键 | 从上次选中到当前图片范围选择 |
| Ctrl+A | 全选 |
| Esc | 取消全部选择 |
| Ctrl+/- | 缩放图片显示大小 |
| 右键点击图片 | 若未选中则先选中; 根据被右键图的状态对所有选中项执行压缩或原图/压缩切换 |
| 状态栏滑条/滚轮 | 调节图片显示大小 (比例范围: minPx/窗口宽度 ~ 100%) |

## 关键数据流

1. 拖放文件 → `_handleFilesDropped` → 创建`ImageItem`加入`_items`
2. 快捷键 → `Shortcuts` 匹配 → 触发 `Intent` → `Actions` 查找并执行对应 `Action`
3. 左键 → `ImageTile.onTap` 检测 Ctrl/Shift → `_handleTap` 更新 `_selectedPaths`
4. 右键未压缩图 → `_handleCompress` → 并行压缩选中项 → 更新 `showCompressed=true`
5. 右键已压缩图 → `_handleRevert` → 遍历选中项切换 `showCompressed`
6. 缩放 → `_tileWidthRatio` 变化 → `LayoutBuilder` 计算实际像素宽度

## 开发

```sh
flutter pub get
flutter run
```

### 观测点

- `_items[i].showCompressed`: 当前显示压缩版还是原图
- `_items[i].isCompressing`: 压缩进行中标志
- `_selectedPaths`: 当前选中的图片路径集合
- `_tileWidthRatio`: 图块宽度比例 (0~1, 实际最小值由 `_minTileWidthPx/窗口宽度` 决定)
- `_lastSelectedIndex`: 上次点击选中的索引 (用于Shift范围选)
- 压缩缓存路径: `~/.cache/byte_treasurer/compressed/`
