/// 首选项页面, 参数双栏布局, 支持可视化配置或自定义命令.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/compress_config.dart';
import '../models/config_schema.dart';

class PreferencesPage extends StatefulWidget {
  final CompressConfig config;

  const PreferencesPage({super.key, required this.config});

  @override
  State<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends State<PreferencesPage> {
  late CompressConfig _config;
  late TextEditingController _customCommandController;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    _customCommandController = TextEditingController(text: _config.customCommand.isEmpty ? _config.toCommandString() : _config.customCommand);
  }

  @override
  void dispose() {
    _customCommandController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final format = _config.formatDef;
    final tool = _config.toolDef;
    if (format == null || tool == null) return const Scaffold(body: Center(child: Text('未知配置')));

    return Scaffold(
      appBar: AppBar(
        title: const Text('首选项'),
        actions: [
          TextButton(
            onPressed: () {
              if (_config.useCustomCommand) {
                _config.customCommand = _customCommandController.text;
              }
              Navigator.pop(context, _config);
            },
            child: const Text('保存'),
          ),
        ],
      ),
      body: Column(
        children: [
          // 第一行: 模式切换 + 命令预览/编辑
          _buildCommandRow(colorScheme),
          const Divider(height: 1),

          // 第二行: 工具选择
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _buildToolSelector(tool),
          ),
          const Divider(height: 1),

          // 第三行: 参数双栏
          Expanded(child: _buildParamsGrid(format, colorScheme)),
        ],
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
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      hintText: 'cjpegli {input} {output} -q 85',
                      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                    ),
                    onChanged: (v) => _config.customCommand = v,
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
          decoration: const InputDecoration(labelText: '工具', border: OutlineInputBorder(), isDense: true),
          items: format.toolIds.map((id) {
            final t = ConfigSchema.getTool(id);
            return DropdownMenuItem(value: id, child: Text(t?.name ?? id));
          }).toList(),
          onChanged: enabled ? (v) => setState(() => _config.switchTool(v!)) : null,
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
            onChanged: enabled ? (v) => setState(() => _config.setParam(param.id, v.round())) : null,
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
      onChanged: enabled ? (v) => setState(() => _config.setParam(param.id, v)) : null,
    );
  }

  Widget _buildPicker(ParamDef param, bool enabled) {
    final value = _config.getParam<String>(param.id, param.defaultValue as String);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: param.label, helperText: param.description, border: const OutlineInputBorder(), isDense: true),
        items: param.options?.map((o) => DropdownMenuItem(value: o.value, child: Text(o.label))).toList() ?? [],
        onChanged: enabled ? (v) => setState(() => _config.setParam(param.id, v!)) : null,
      ),
    );
  }
}
