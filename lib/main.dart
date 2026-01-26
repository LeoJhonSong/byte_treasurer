import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:panes/panes.dart';
import 'color_schemes.dart';
import 'models/image_item.dart';
import 'models/compress_config.dart';
import 'models/config_schema.dart';
import 'widgets/browse_panel.dart';
import 'services/image_compressor.dart';
import 'pages/preferences_page.dart';
import 'utils/format.dart';
import 'intents.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ConfigSchema.load();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: _buildTheme(lightColorScheme),
      darkTheme: _buildTheme(darkColorScheme),
      debugShowCheckedModeBanner: false,
      home: const HomePage(),
    );
  }

  ThemeData _buildTheme(ColorScheme colorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        textStyle: TextStyle(color: colorScheme.onSurface, fontSize: 12),
        textAlign: TextAlign.center,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        preferBelow: true,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.outline)),
        disabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.outlineVariant)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.primary, width: 2)),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<ImageItem> _items = [];
  final Set<String> _selectedPaths = {};
  final _compressor = ImageCompressor();
  CompressConfig _config = CompressConfig();
  bool _isDragging = false;
  double _tileWidthRatio = 0.15; // 图块宽度占窗口宽度的比例
  int? _lastSelectedIndex; // 用于 Shift 批量选择
  final FocusNode _focusNode = FocusNode();
  bool _showSettingsPanel = true; // 压缩设置面板可见性
  late final PaneController _paneController;

  static const double _minTileWidthPx = 80; // 最小像素宽度
  static const double _zoomStep = 0.03; // 缩放步进

  @override
  void initState() {
    super.initState();
    _paneController = PaneController(
      entries: [
        PaneEntry(id: 'browse', initialSize: PaneSize.fraction(1.0)),
        PaneEntry(id: 'settings', initialSize: PaneSize.pixel(320), minSize: PaneSize.pixel(280), maxSize: PaneSize.pixel(600), autoHide: true),
      ],
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _paneController.dispose();
    super.dispose();
  }

  Future<void> _handleFilesDropped(List<String> paths) async {
    for (final path in paths) {
      final ext = path.toLowerCase().split('.').last;
      if ((ext == 'jpg' || ext == 'jpeg') && !_items.any((i) => i.path == path)) {
        final item = await ImageItem.fromPath(path);
        setState(() => _items.add(item));
      }
    }
  }

  // 选择逻辑: isCtrl 切换选中, isShift 范围选, 单击已选中则取消, 否则单选
  void _handleTap(String path, {bool isCtrl = false, bool isShift = false}) {
    final idx = _items.indexWhere((i) => i.path == path);
    if (idx == -1) return;

    setState(() {
      if (isShift && _lastSelectedIndex != null) {
        // Shift: 范围选择
        final start = _lastSelectedIndex! < idx ? _lastSelectedIndex! : idx;
        final end = _lastSelectedIndex! > idx ? _lastSelectedIndex! : idx;
        for (var i = start; i <= end; i++) {
          _selectedPaths.add(_items[i].path);
        }
      } else if (isCtrl) {
        // Ctrl: 切换选中
        if (_selectedPaths.contains(path)) {
          _selectedPaths.remove(path);
        } else {
          _selectedPaths.add(path);
        }
        _lastSelectedIndex = idx;
      } else {
        // 单击: 已选中则取消, 否则单选
        if (_selectedPaths.contains(path) && _selectedPaths.length == 1) {
          _selectedPaths.clear();
          _lastSelectedIndex = null;
        } else {
          _selectedPaths.clear();
          _selectedPaths.add(path);
          _lastSelectedIndex = idx;
        }
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedPaths.clear();
      for (final item in _items) {
        _selectedPaths.add(item.path);
      }
    });
  }

  void _clearSelection() {
    setState(() => _selectedPaths.clear());
  }

  void _zoomIn() {
    setState(() => _tileWidthRatio = (_tileWidthRatio + _zoomStep).clamp(0.0, 1.0));
  }

  void _zoomOut() {
    setState(() => _tileWidthRatio = (_tileWidthRatio - _zoomStep).clamp(0.0, 1.0));
  }

  Future<void> _handleCompress(String path) async {
    // 若点击的是未选中项, 先选中它
    if (!_selectedPaths.contains(path)) {
      setState(() => _selectedPaths.add(path));
    }

    // 筛选待压缩项
    final pathsToCompress = _selectedPaths.where((p) {
      final idx = _items.indexWhere((i) => i.path == p);
      return idx != -1 && !_items[idx].isCompressed && !_items[idx].isCompressing;
    }).toList();

    if (pathsToCompress.isEmpty) return;

    // 标记所有待压缩项为压缩中
    setState(() {
      for (final p in pathsToCompress) {
        final idx = _items.indexWhere((i) => i.path == p);
        if (idx != -1) _items[idx].isCompressing = true;
      }
    });

    // 根据模式选择压缩方式
    if (_config.mode == CompressMode.totalSizeLimit && pathsToCompress.length > 1) {
      // 总大小模式: 批量压缩
      final results = await _compressor.compressBatchToTotalSize(
        pathsToCompress,
        _config.totalSizeLimitKB * 1024,
        _config,
      );
      setState(() {
        for (int i = 0; i < pathsToCompress.length; i++) {
          final idx = _items.indexWhere((item) => item.path == pathsToCompress[i]);
          if (idx != -1) {
            _items[idx].isCompressing = false;
            _items[idx].compressedSize = results[i].compressedSize;
            _items[idx].compressedPath = results[i].outputPath;
            _items[idx].showCompressed = true;
          }
        }
      });
    } else {
      // 单文件模式或参数配置模式: 并行压缩
      await Future.wait(
        pathsToCompress.map((p) async {
          final idx = _items.indexWhere((i) => i.path == p);
          final result = await _compressor.compress(p, _config);
          setState(() {
            _items[idx].isCompressing = false;
            _items[idx].compressedSize = result.compressedSize;
            _items[idx].compressedPath = result.outputPath;
            _items[idx].showCompressed = true;
          });
        }),
      );
    }
  }

  void _handleRevert(String path) {
    final idx = _items.indexWhere((i) => i.path == path);
    if (idx == -1 || !_items[idx].isCompressed) return;

    // 若点击的是未选中项, 先选中它
    if (!_selectedPaths.contains(path)) {
      setState(() => _selectedPaths.add(path));
    }

    // 根据被右键图的当前状态决定目标状态
    final targetShowCompressed = !_items[idx].showCompressed;

    // 对所有选中的已压缩图片执行相同切换
    setState(() {
      for (final p in _selectedPaths) {
        final i = _items.indexWhere((item) => item.path == p);
        if (i != -1 && _items[i].isCompressed) {
          _items[i].showCompressed = targetShowCompressed;
        }
      }
    });
  }

  // 统计信息
  int get _totalOriginalSize => _items.fold(0, (sum, i) => sum + i.originalSize);
  int get _totalCompressedSize => _items.fold(0, (sum, i) => sum + (i.compressedSize ?? i.originalSize));

  // 获取预览用样本图片路径
  String? get _sampleImagePath {
    if (_selectedPaths.isNotEmpty) return _selectedPaths.first;
    if (_items.isNotEmpty) return _items.first.path;
    return null;
  }

  void _toggleSettingsPanel() {
    _paneController.toggle('settings');
    setState(() => _showSettingsPanel = _paneController.isVisible('settings'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final windowWidth = constraints.maxWidth;
          final minRatio = _minTileWidthPx / windowWidth;
          final tileWidth = (_tileWidthRatio.clamp(minRatio, 1.0) * windowWidth).clamp(_minTileWidthPx, windowWidth);

          return Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.keyA, control: true): SelectAllIntent(),
              SingleActivator(LogicalKeyboardKey.escape): ClearSelectionIntent(),
              SingleActivator(LogicalKeyboardKey.equal, control: true): ZoomIntent.zoomIn(),
              SingleActivator(LogicalKeyboardKey.minus, control: true): ZoomIntent.zoomOut(),
              SingleActivator(LogicalKeyboardKey.add, control: true): ZoomIntent.zoomIn(),
              SingleActivator(LogicalKeyboardKey.numpadAdd, control: true): ZoomIntent.zoomIn(),
              SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true): ZoomIntent.zoomOut(),
            },
            child: Actions(
              actions: {
                SelectAllIntent: CallbackAction<SelectAllIntent>(onInvoke: (_) => _selectAll()),
                ClearSelectionIntent: CallbackAction<ClearSelectionIntent>(onInvoke: (_) => _clearSelection()),
                ZoomIntent: CallbackAction<ZoomIntent>(onInvoke: (intent) => intent.zoomIn ? _zoomIn() : _zoomOut()),
              },
              child: Focus(
                focusNode: _focusNode,
                autofocus: true,
                child: GestureDetector(
                  onTap: () => _focusNode.requestFocus(),
                  child: Column(
                    children: [
                      // Top bar
                      _buildTopBar(context),
                      // 主内容区: 图片浏览 + 压缩设置面板
                      Expanded(
                        child: PaneTheme(
                          data: PaneThemeData(
                            resizerColor: Theme.of(context).colorScheme.outlineVariant,
                            resizerHoverColor: Theme.of(context).colorScheme.primary,
                            resizerThickness: 4,
                            resizerHitTestThickness: 8,
                          ),
                          child: MultiPane(
                            direction: Axis.horizontal,
                            controller: _paneController,
                            paneBuilder: (context, id) {
                              if (id == 'browse') return _buildBrowsePanel(context, tileWidth);
                              if (id == 'settings') return CompressSettingsPanel(config: _config, sampleImagePath: _sampleImagePath, onConfigChanged: (c) => setState(() => _config = c));
                              return const SizedBox();
                            },
                          ),
                        ),
                      ),
                      // 底部状态栏
                      _buildStatusBar(context, minRatio),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context, double minRatio) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          // 文件数量
          Text('${_items.length} 张', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
          const SizedBox(width: 16),
          // 原大小
          if (_items.isNotEmpty) ...[
            Text('原: ${formatSize(_totalOriginalSize)}', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
            const SizedBox(width: 16),
            // 压缩后大小
            Text('压缩后: ${formatSize(_totalCompressedSize)}', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
          ],
          const Spacer(),
          // 缩放滑条 (支持滚轮)
          Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                if (event.scrollDelta.dy < 0) {
                  _zoomIn();
                } else {
                  _zoomOut();
                }
              }
            },
            child: Row(
              children: [
                Icon(Icons.photo_size_select_small, size: 16, color: colorScheme.onSurfaceVariant),
                SizedBox(
                  width: 120,
                  child: Slider(
                    value: _tileWidthRatio.clamp(minRatio, 1.0),
                    min: minRatio,
                    max: 1.0,
                    onChanged: (v) => setState(() => _tileWidthRatio = v),
                  ),
                ),
                Icon(Icons.photo_size_select_large, size: 16, color: colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 浏览面板 (拖放区 + 图片网格)
  Widget _buildBrowsePanel(BuildContext context, double tileWidth) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        _handleFilesDropped(details.files.map((f) => f.path).toList());
      },
      child: SizedBox.expand(
        child: Container(
          decoration: BoxDecoration(border: _isDragging ? Border.all(color: Theme.of(context).colorScheme.primary, width: 3) : null),
          child: BrowsePanel(items: _items, selectedPaths: _selectedPaths, tileWidth: tileWidth, onTap: _handleTap, onCompress: _handleCompress, onRevert: _handleRevert),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          const Spacer(),
          IconButton(
            onPressed: _toggleSettingsPanel,
            icon: Icon(_showSettingsPanel ? Icons.chevron_right : Icons.chevron_left, size: 20),
            tooltip: _showSettingsPanel ? '收起压缩设置' : '展开压缩设置',
          ),
        ],
      ),
    );
  }
}
