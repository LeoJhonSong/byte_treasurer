/// JPG图片压缩服务, 支持 ImageMagick 和 cjpegli.
///
/// 用法:
/// ```dart
/// final compressor = ImageCompressor();
/// final result = await compressor.compress('/path/to/input.jpg', config);
/// ```
library;

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/compress_config.dart';

class CompressionResult {
  final String outputPath;
  final int originalSize;
  final int compressedSize;

  /// 压缩比, 压缩后/压缩前, 越小越好.
  final double ratio;

  CompressionResult({required this.outputPath, required this.originalSize, required this.compressedSize}) : ratio = compressedSize / originalSize;
}

class ImageCompressor {
  Directory? _cacheDir;

  /// 获取压缩文件缓存目录.
  Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final appCache = await getApplicationCacheDirectory();
    _cacheDir = Directory(p.join(appCache.path, 'compressed'));
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  /// 根据配置压缩图片.
  Future<CompressionResult> compress(String inputPath, CompressConfig config, {void Function(double progress)? onProgress}) async {
    final inputFile = File(inputPath);
    final originalSize = await inputFile.length();

    // 生成输出路径
    final cacheDir = await _getCacheDir();
    final pathHash = inputPath.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');
    final basename = p.basenameWithoutExtension(inputPath);
    final ext = p.extension(inputPath);
    final outputPath = p.join(cacheDir.path, '${pathHash}_$basename$ext');

    onProgress?.call(0.1);

    // 构建命令
    final tool = config.toolDef;
    if (tool == null) throw Exception('未知工具: ${config.toolId}');
    final executable = tool.executable;
    final args = config.buildCommand(inputPath, outputPath);

    final result = await Process.run(executable, args);

    onProgress?.call(0.9);

    if (result.exitCode != 0) {
      throw Exception('$executable 压缩失败: ${result.stderr}');
    }

    final compressedSize = await File(outputPath).length();
    onProgress?.call(1.0);

    return CompressionResult(outputPath: outputPath, originalSize: originalSize, compressedSize: compressedSize);
  }

  /// 兼容旧接口, 使用默认配置压缩.
  Future<CompressionResult> compressJpg(String inputPath, {int quality = 80, void Function(double progress)? onProgress}) {
    final config = CompressConfig();
    config.setParam('quality', quality);
    return compress(inputPath, config, onProgress: onProgress);
  }
}
