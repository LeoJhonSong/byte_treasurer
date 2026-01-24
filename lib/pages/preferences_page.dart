/// 压缩设置面板, 参数双栏布局, 支持可视化配置或自定义命令.
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/compress_config.dart';
import '../models/config_schema.dart';
import '../models/image_item.dart';
import '../services/image_compressor.dart';
import '../widgets/image_tile.dart';

class CompressSettingsPanel extends StatefulWidget {
  final CompressConfig config;
  final String? sampleImagePath;
  final ValueChanged<CompressConfig> onConfigChanged;

  const CompressSettingsPanel({super.key, required this.config, this.sampleImagePath, required this.onConfigChanged});

  @override
  State<CompressSettingsPanel> createState() => _CompressSettingsPanelState();
}

class _CompressSettingsPanelState extends State<CompressSettingsPanel> {
  late CompressConfig _config;
  late TextEditingController _customCommandController;
  late TextEditingController _totalSizeController;
  late TextEditingController _fileSizeController;

  // 预览相关状态
  final _compressor = ImageCompressor();
  Timer? _debounceTimer;
  bool _isPreviewing = false;
  int? _previewOriginalSize;
  int? _previewCompressedSize;
  String? _previewOutputPath;
  String? _previewError;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    _customCommandController = TextEditingController(text: _config.customCommand.isEmpty ? _config.toCommandString() : _config.customCommand);
    _totalSizeController = TextEditingController(text: _config.totalSizeLimitKB.toString());
    _fileSizeController = TextEditingController(text: _config.fileSizeLimitKB.toString());
    if (widget.sampleImagePath != null) {
      _loadOriginalSize();
      _triggerPreview();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _customCommandController.dispose();
    _totalSizeController.dispose();
    _fileSizeController.dispose();
    super.dispose();
  }

  Future<void> _loadOriginalSize() async {
    if (widget.sampleImagePath == null) return;
    final size = await File(widget.sampleImagePath!).length();
    setState(() => _previewOriginalSize = size);
  }

  void _triggerPreview() {
    if (_config.mode == CompressMode.totalSizeLimit) return; // 总大小模式不支持单张预览
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), _runPreview);
  }

  Future<void> _runPreview() async {
    if (widget.sampleImagePath == null) return;
    setState(() {
      _isPreviewing = true;
      _previewError = null;
    });
    try {
      final result = await _compressor.compress(widget.sampleImagePath!, _config);
      setState(() {
        _previewCompressedSize = result.compressedSize;
        _previewOutputPath = result.outputPath;
        _isPreviewing = false;
      });
    } catch (e) {
      setState(() {
        _previewError = e.toString();
        _isPreviewing = false;
      });
    }
  }

  /// 获取支持某参数的工具名称列表
  List<String> _getSupportingToolNames(String paramId) {
    final format = _config.formatDef;
    if (format == null) return [];
    final names = <String>[];
    for (final toolId in format.toolIds) {
      if (format.isParamSupported(toolId, paramId)) {
        final tool = ConfigSchema.getTool(toolId);
        names.add(tool?.name ?? toolId);
      }
    }
    return names;
  }

  void _notifyConfigChanged() {
    if (_config.useCustomCommand) {
      _config.customCommand = _customCommandController.text;
    }
    _config.totalSizeLimitKB = int.tryParse(_totalSizeController.text) ?? 5120;
    _config.fileSizeLimitKB = int.tryParse(_fileSizeController.text) ?? 500;
    widget.onConfigChanged(_config);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(left: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        children: [
          // 模式1: 总大小上限
          _buildModeRow(CompressMode.totalSizeLimit, '总大小上限', Icons.folder_outlined, colorScheme),
          // 模式2: 单文件上限
          _buildModeRow(CompressMode.fileSizeLimit, '单文件上限', Icons.insert_drive_file_outlined, colorScheme),
          // 模式3: 参数配置 (占据剩余空间)
          Expanded(child: _buildParamConfigMode(colorScheme)),

          // 预览区域
          const Divider(height: 1),
          _buildPreviewSection(colorScheme),
        ],
      ),
    );
  }

  Widget _buildModeRow(CompressMode mode, String label, IconData icon, ColorScheme colorScheme) {
    final isSelected = _config.mode == mode;
    final bgColor = isSelected ? colorScheme.primaryContainer : colorScheme.surface;
    final fgColor = isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: () {
        setState(() => _config.mode = mode);
        _notifyConfigChanged();
        _triggerPreview();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5)),
        ),
        child: Row(
          children: [
            Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: isSelected ? colorScheme.primary : colorScheme.outline, size: 20),
            const SizedBox(width: 12),
            Icon(icon, color: fgColor, size: 20),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: fgColor, fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal)),
            const Spacer(),
            if (mode == CompressMode.totalSizeLimit)
              _buildInlineSizeInput(_totalSizeController, isSelected, colorScheme)
            else if (mode == CompressMode.fileSizeLimit)
              _buildInlineSizeInput(_fileSizeController, isSelected, colorScheme)
            else if (mode == CompressMode.paramConfig && !isSelected)
              Text('quality=${_config.getParam<num>('quality', 85).round()}', style: TextStyle(color: fgColor, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineSizeInput(TextEditingController controller, bool enabled, ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 80,
          height: 32,
          child: TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: enabled ? colorScheme.onSurface : colorScheme.onSurfaceVariant),
            decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
            onChanged: (_) {
              if (enabled) {
                _config.fileSizeLimitKB = int.tryParse(_fileSizeController.text) ?? 500;
                _config.totalSizeLimitKB = int.tryParse(_totalSizeController.text) ?? 5120;
                _notifyConfigChanged();
                _triggerPreview();
              }
            },
          ),
        ),
        const SizedBox(width: 4),
        Text('KB', style: TextStyle(color: enabled ? colorScheme.onSurface : colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _buildParamConfigMode(ColorScheme colorScheme) {
    final isSelected = _config.mode == CompressMode.paramConfig;
    final bgColor = isSelected ? colorScheme.primaryContainer.withValues(alpha: 0.3) : colorScheme.surface;
    final fgColor = isSelected ? colorScheme.onSurface : colorScheme.onSurfaceVariant;
    final format = _config.formatDef;
    final tool = _config.toolDef;

    return GestureDetector(
      onTap: () {
        setState(() => _config.mode = CompressMode.paramConfig);
        _notifyConfigChanged();
        _triggerPreview();
      },
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant, width: 0.5)),
        ),
        child: Opacity(
          opacity: isSelected ? 1.0 : 0.5,
          child: IgnorePointer(
            ignoring: !isSelected,
            child: Column(
              children: [
                // 标题行
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: isSelected ? colorScheme.primary : colorScheme.outline, size: 20),
                      const SizedBox(width: 12),
                      Icon(Icons.tune, color: fgColor, size: 20),
                      const SizedBox(width: 8),
                      Text('参数配置', style: TextStyle(color: fgColor, fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal)),
                    ],
                  ),
                ),
                // 配置内容
                if (format != null && tool != null) ...[
                  const Divider(height: 1),
                  _buildCommandRow(colorScheme),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: _buildToolSelector(tool),
                  ),
                  const Divider(height: 1),
                  Expanded(child: _buildParamsGrid(format, colorScheme)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCommandRow(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // 左侧: 模式切换
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('可视化'), icon: Icon(Icons.tune)),
              ButtonSegment(value: true, label: Text('自定义'), icon: Icon(Icons.edit)),
            ],
            selected: {_config.useCustomCommand},
            onSelectionChanged: (v) {
              setState(() {
                _config.useCustomCommand = v.first;
                if (!_config.useCustomCommand) {
                  _customCommandController.text = _config.toCommandString();
                }
              });
              _notifyConfigChanged();
            },
          ),
          const SizedBox(width: 16),

          // 右侧: 命令预览/编辑
          Expanded(
            child: _config.useCustomCommand
                ? TextField(
                    controller: _customCommandController,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'cjpegli {input} {output} -q 85',
                      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                    ),
                    onChanged: (v) {
                      _config.customCommand = v;
                      _notifyConfigChanged();
                    },
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: colorScheme.outline.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _config.toCommandString(),
                            style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: colorScheme.onSurface),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          tooltip: '复制命令',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _config.toCommandString()));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)));
                          },
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolSelector(ToolDef tool) {
    final format = _config.formatDef!;
    final enabled = !_config.useCustomCommand;

    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: IgnorePointer(
        ignoring: !enabled,
        child: DropdownButtonFormField<String>(
          initialValue: _config.toolId,
          decoration: const InputDecoration(labelText: '工具'),
          items: format.toolIds.map((id) {
            final t = ConfigSchema.getTool(id);
            return DropdownMenuItem(value: id, child: Text(t?.name ?? id));
          }).toList(),
          onChanged: enabled
              ? (v) => setState(() {
                    _config.switchTool(v!);
                    _notifyConfigChanged();
                    _triggerPreview();
                  })
              : null,
        ),
      ),
    );
  }

  Widget _buildParamsGrid(FormatDef format, ColorScheme colorScheme) {
    final params = format.params;
    final half = (params.length + 1) ~/ 2;
    final leftParams = params.take(half).toList();
    final rightParams = params.skip(half).toList();

    return Opacity(
      opacity: _config.useCustomCommand ? 0.5 : 1.0,
      child: IgnorePointer(
        ignoring: _config.useCustomCommand,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: leftParams.map((p) => _buildParamWidget(p)).toList(),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: rightParams.map((p) => _buildParamWidget(p)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParamWidget(ParamDef param) {
    final supported = _config.isParamSupported(param.id);
    final supportingTools = _getSupportingToolNames(param.id);
    final tooltipMsg = supported ? '' : '支持: ${supportingTools.join(', ')}';

    Widget child = switch (param.type) {
      ParamType.slider => _buildSlider(param, supported),
      ParamType.switcher => _buildSwitch(param, supported),
      ParamType.picker => _buildPicker(param, supported),
    };

    if (!supported) {
      child = Tooltip(
        message: tooltipMsg,
        child: Opacity(opacity: 0.4, child: IgnorePointer(child: child)),
      );
    }

    return child;
  }

  Widget _buildSlider(ParamDef param, bool enabled) {
    final value = _config.getParam<num>(param.id, param.defaultValue as num).toDouble();
    final min = (param.min ?? 0).toDouble();
    final max = (param.max ?? 100).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(param.label)),
              Text(value.round().toString(), style: const TextStyle(fontWeight: FontWeight.w500)),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: (max - min).round(),
            onChanged: enabled
                ? (v) => setState(() {
                      _config.setParam(param.id, v.round());
                      _notifyConfigChanged();
                      _triggerPreview();
                    })
                : null,
          ),
          if (param.description != null) Text(param.description!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildSwitch(ParamDef param, bool enabled) {
    final value = _config.getParam<bool>(param.id, param.defaultValue as bool);

    return SwitchListTile(
      title: Text(param.label),
      subtitle: param.description != null ? Text(param.description!) : null,
      value: value,
      onChanged: enabled
          ? (v) => setState(() {
                _config.setParam(param.id, v);
                _notifyConfigChanged();
                _triggerPreview();
              })
          : null,
    );
  }

  Widget _buildPicker(ParamDef param, bool enabled) {
    final value = _config.getParam<String>(param.id, param.defaultValue as String);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: param.label, helperText: param.description),
        items: param.options?.map((o) => DropdownMenuItem(value: o.value, child: Text(o.label))).toList() ?? [],
        onChanged: enabled
            ? (v) => setState(() {
                  _config.setParam(param.id, v!);
                  _notifyConfigChanged();
                  _triggerPreview();
                })
            : null,
      ),
    );
  }

  Widget _buildPreviewSection(ColorScheme colorScheme) {
    // 无样本图片: 提示信息
    if (widget.sampleImagePath == null) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined, size: 20, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text('在浏览面板选中图片后可预览压缩效果', style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    // 构造预览用的 ImageItem
    final previewItem = ImageItem(
      path: widget.sampleImagePath!,
      originalSize: _previewOriginalSize ?? 0,
      compressedSize: _previewCompressedSize,
      compressedPath: _previewOutputPath,
      isCompressing: _isPreviewing,
      showCompressed: _previewOutputPath != null,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 复用 ImageTile 组件
          ImageTile(
            item: previewItem,
            width: 120,
            maxHeight: 120,
            isSelected: false,
            onTap: (_, _) {},
            onCompress: () {},
          ),
          const SizedBox(width: 16),

          // 错误信息 或 刷新按钮
          if (_previewError != null)
            Expanded(child: Text(_previewError!, style: TextStyle(color: colorScheme.error, fontSize: 12)))
          else
            const Spacer(),

          // 刷新按钮 (仅自定义命令模式)
          if (_config.useCustomCommand)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新预览',
              onPressed: _isPreviewing ? null : _triggerPreview,
            ),
        ],
      ),
    );
  }
}
