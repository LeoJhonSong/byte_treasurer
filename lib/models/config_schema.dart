/// 配置 schema 定义, 以文件格式为中心.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';
import 'package:jinja/jinja.dart';

/// 参数类型
enum ParamType { slider, switcher, picker }

/// 参数定义
class ParamDef {
  final String id;
  final ParamType type;
  final String label;
  final String? description;
  final dynamic defaultValue;

  // slider 专用
  final num? min;
  final num? max;

  // picker 专用
  final List<PickerOption>? options;

  const ParamDef({
    required this.id,
    required this.type,
    required this.label,
    this.description,
    required this.defaultValue,
    this.min,
    this.max,
    this.options,
  });
}

/// picker 选项
class PickerOption {
  final String value;
  final String label;

  const PickerOption({required this.value, required this.label});
}

/// 工具定义
class ToolDef {
  final String id;
  final String name;
  final String executable;

  const ToolDef({required this.id, required this.name, required this.executable});
}

/// 格式定义
class FormatDef {
  final String id;
  final List<String> toolIds;
  final List<ParamDef> params;

  /// toolId -> paramId -> arg template
  final Map<String, Map<String, String>> toolArgs;

  const FormatDef({
    required this.id,
    required this.toolIds,
    required this.params,
    required this.toolArgs,
  });

  /// 获取参数的默认值 Map
  Map<String, dynamic> getDefaultValues() {
    return {for (final p in params) p.id: p.defaultValue};
  }

  /// 获取默认工具 ID
  String get defaultToolId => toolIds.first;

  /// 检查某工具是否支持某参数
  bool isParamSupported(String toolId, String paramId) {
    return toolArgs[toolId]?.containsKey(paramId) ?? false;
  }
}

/// 配置 schema 管理
class ConfigSchema {
  static Map<String, ToolDef>? _tools;
  static Map<String, FormatDef>? _formats;
  static bool _loading = false;

  /// 从 YAML 文件加载, 需在 app 启动时调用
  static Future<void> load() async {
    if (_tools != null || _loading) return;
    _loading = true;

    final yamlStr = await rootBundle.loadString('assets/builtin_tools.yaml');
    final doc = loadYaml(yamlStr) as YamlMap;

    // 解析 tools
    _tools = {};
    (doc['tools'] as YamlMap).forEach((id, v) {
      final map = v as YamlMap;
      _tools![id] = ToolDef(id: id, name: map['name'], executable: map['executable']);
    });

    // 解析 formats
    _formats = {};
    (doc['formats'] as YamlMap).forEach((id, v) {
      final map = v as YamlMap;
      _formats![id] = _parseFormat(id, map);
    });

    _loading = false;
  }

  static FormatDef _parseFormat(String id, YamlMap m) {
    final toolIds = List<String>.from(m['tools']);
    final params = <ParamDef>[];

    // 解析 params
    (m['params'] as YamlMap).forEach((paramId, v) {
      final map = v as YamlMap;
      final typeStr = map['type'] as String;
      final type = ParamType.values.firstWhere((t) => t.name == typeStr);

      List<PickerOption>? options;
      if (type == ParamType.picker) {
        options = [];
        (map['options'] as YamlMap).forEach((value, label) {
          options!.add(PickerOption(value: value.toString(), label: label));
        });
      }

      num? min, max;
      if (type == ParamType.slider) {
        final range = map['range'] as YamlList;
        min = range[0];
        max = range[1];
      }

      params.add(ParamDef(
        id: paramId,
        type: type,
        label: map['label'],
        description: map['description'],
        defaultValue: map['default'],
        min: min,
        max: max,
        options: options,
      ));
    });

    // 解析 tool_args: toolId -> paramId -> template
    final toolArgs = <String, Map<String, String>>{};
    (m['tool_args'] as YamlMap).forEach((toolId, argsMap) {
      final args = <String, String>{};
      (argsMap as YamlMap).forEach((paramId, tpl) {
        args[paramId as String] = tpl as String;
      });
      toolArgs[toolId as String] = args;
    });

    return FormatDef(id: id, toolIds: toolIds, params: params, toolArgs: toolArgs);
  }

  /// 获取所有工具
  static Map<String, ToolDef> get tools => _tools ?? {};

  /// 获取所有格式
  static Map<String, FormatDef> get formats => _formats ?? {};

  /// 根据 ID 获取工具
  static ToolDef? getTool(String id) => _tools?[id];

  /// 根据 ID 获取格式
  static FormatDef? getFormat(String id) => _formats?[id];

  /// 是否已加载
  static bool get isLoaded => _tools != null;
}

/// Jinja2 模板渲染器
class TemplateRenderer {
  static final _env = Environment();

  /// 渲染命令参数列表, 按字典顺序, _开头的键排序到首尾 (_input 最前, _output 最后)
  static List<String> renderArgs(Map<String, String> argTemplates, Map<String, dynamic> params) {
    final args = <String>[];

    // 排序: _input 最前, _output 最后, 其他按原顺序
    final keys = argTemplates.keys.toList();
    keys.sort((a, b) {
      if (a == '_input') return -1;
      if (b == '_input') return 1;
      if (a == '_output') return 1;
      if (b == '_output') return -1;
      return 0;
    });

    for (final key in keys) {
      final tpl = argTemplates[key]!;
      final template = _env.fromString(tpl);
      final rendered = template.render(params).trim();
      if (rendered.isNotEmpty) {
        args.addAll(rendered.split(RegExp(r'\s+')).where((s) => s.isNotEmpty));
      }
    }
    return args;
  }
}
