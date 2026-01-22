/// 压缩配置模型, 以文件格式为中心.
library;

import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';
import 'config_schema.dart';

/// 压缩配置
class CompressConfig {
  String formatId;
  String toolId;
  bool useCustomCommand;
  String customCommand;
  Map<String, dynamic> params;

  CompressConfig({
    this.formatId = 'jpg',
    String? toolId,
    this.useCustomCommand = false,
    this.customCommand = '',
    Map<String, dynamic>? params,
  }) : toolId = toolId ?? ConfigSchema.getFormat('jpg')?.defaultToolId ?? 'cjpegli',
       params = params ?? ConfigSchema.getFormat('jpg')?.getDefaultValues() ?? {};

  /// 获取当前格式定义
  FormatDef? get formatDef => ConfigSchema.getFormat(formatId);

  /// 获取当前工具定义
  ToolDef? get toolDef => ConfigSchema.getTool(toolId);

  /// 切换工具 (保留参数值)
  void switchTool(String newToolId) {
    toolId = newToolId;
  }

  /// 切换格式, 重置参数为默认值
  void switchFormat(String newFormatId) {
    formatId = newFormatId;
    final format = ConfigSchema.getFormat(newFormatId);
    if (format != null) {
      toolId = format.defaultToolId;
      params = format.getDefaultValues();
    }
  }

  /// 获取参数值, 带默认值回退
  T getParam<T>(String id, T defaultValue) {
    return (params[id] as T?) ?? defaultValue;
  }

  /// 设置参数值
  void setParam(String id, dynamic value) {
    params[id] = value;
  }

  /// 检查当前工具是否支持某参数
  bool isParamSupported(String paramId) {
    return formatDef?.isParamSupported(toolId, paramId) ?? false;
  }

  /// 生成命令行参数列表
  List<String> buildCommand(String inputPath, String outputPath) {
    final format = formatDef;
    if (format == null) return [];

    final argTemplates = format.toolArgs[toolId];
    if (argTemplates == null) return [];

    final tplParams = Map<String, dynamic>.from(params);
    tplParams['input'] = inputPath;
    tplParams['output'] = outputPath;

    return TemplateRenderer.renderArgs(argTemplates, tplParams);
  }

  /// 转为 YAML 字符串
  String toYaml() {
    final format = formatDef;
    final data = <String, dynamic>{'format': formatId, 'tool': toolId};

    if (format != null) {
      for (final p in format.params) {
        if (isParamSupported(p.id)) {
          data[p.id] = params[p.id] ?? p.defaultValue;
        }
      }
    }

    final writer = YamlWriter();
    return writer.write(data);
  }

  /// 生成预览命令字符串
  String toCommandString() {
    final tool = toolDef;
    if (tool == null) return '';
    if (useCustomCommand && customCommand.isNotEmpty) return customCommand;
    final args = buildCommand('{input}', '{output}');
    return '${tool.executable} ${args.join(' ')}';
  }

  /// 从 YAML 字符串解析
  static CompressConfig? parseFromYaml(String yamlStr) {
    try {
      final doc = loadYaml(yamlStr);
      if (doc is! Map) return null;

      final formatId = doc['format'] as String? ?? 'jpg';
      final format = ConfigSchema.getFormat(formatId);
      if (format == null) return null;

      final toolId = doc['tool'] as String? ?? format.defaultToolId;

      final params = <String, dynamic>{};
      for (final p in format.params) {
        if (doc.containsKey(p.id)) {
          params[p.id] = doc[p.id];
        } else {
          params[p.id] = p.defaultValue;
        }
      }

      return CompressConfig(formatId: formatId, toolId: toolId, params: params);
    } catch (_) {
      return null;
    }
  }

  /// 从 YAML 更新当前配置
  bool updateFromYaml(String yamlStr) {
    final parsed = parseFromYaml(yamlStr);
    if (parsed == null) return false;
    formatId = parsed.formatId;
    toolId = parsed.toolId;
    params = parsed.params;
    return true;
  }
}
