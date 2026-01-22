import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'color_schemes.dart';
import 'models/image_item.dart';
import 'models/compress_config.dart';
import 'models/config_schema.dart';
import 'widgets/image_grid.dart';
import 'services/image_compressor.dart';
import 'pages/preferences_page.dart';
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
      theme: ThemeData(useMaterial3: true, colorScheme: lightColorScheme),
      darkTheme: ThemeData(useMaterial3: true, colorScheme: darkColorScheme),
      debugShowCheckedModeBanner: false,
      home: const HomePage(),
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

  static const double _minTileWidthPx = 80; // 最小像素宽度
  static const double _zoomStep = 0.03; // 缩放步进

  @override
  void dispose() {
    _focusNode.dispose();
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

  // 选择逻辑: isCtrl 切换选中, isShift 范围选, 否则单选
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
        // 单击: 单选
        _selectedPaths.clear();
        _selectedPaths.add(path);
        _lastSelectedIndex = idx;
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

    // 标记所有待压缩项为压缩中
    setState(() {
      for (final p in pathsToCompress) {
        final idx = _items.indexWhere((i) => i.path == p);
        if (idx != -1) _items[idx].isCompressing = true;
      }
    });

    // 并行压缩
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

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  Future<void> _openPreferences() async {
    final result = await Navigator.push<CompressConfig>(context, MaterialPageRoute(builder: (_) => PreferencesPage(config: _config)));
    if (result != null) {
      setState(() => _config = result);
    }
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
                      // 主内容区
                      Expanded(
                        child: DropTarget(
                          onDragEntered: (_) => setState(() => _isDragging = true),
                          onDragExited: (_) => setState(() => _isDragging = false),
                          onDragDone: (details) {
                            setState(() => _isDragging = false);
                            _handleFilesDropped(details.files.map((f) => f.path).toList());
                          },
                          child: SizedBox.expand(
                            child: Container(
                              decoration: BoxDecoration(
                                border: _isDragging ? Border.all(color: Theme.of(context).colorScheme.primary, width: 3) : null,
                              ),
                              child: ImageGrid(
                                items: _items,
                                selectedPaths: _selectedPaths,
                                tileWidth: tileWidth,
                                onTap: _handleTap,
                                onCompress: _handleCompress,
                                onRevert: _handleRevert,
                              ),
                            ),
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
            Text('原: ${_formatSize(_totalOriginalSize)}', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
            const SizedBox(width: 16),
            // 压缩后大小
            Text('压缩后: ${_formatSize(_totalCompressedSize)}', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
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
        children: [TextButton.icon(onPressed: _openPreferences, icon: const Icon(Icons.settings, size: 18), label: const Text('首选项'))],
      ),
    );
  }
}
