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

  /// 生成输出路径.
  Future<String> _getOutputPath(String inputPath, {String? suffix}) async {
    final cacheDir = await _getCacheDir();
    final pathHash = inputPath.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');
    final basename = p.basenameWithoutExtension(inputPath);
    final ext = p.extension(inputPath);
    final suffixStr = suffix != null ? '_$suffix' : '';
    return p.join(cacheDir.path, '${pathHash}_$basename$suffixStr$ext');
  }

  /// 根据配置压缩图片.
  Future<CompressionResult> compress(String inputPath, CompressConfig config, {void Function(double progress)? onProgress}) async {
    final inputFile = File(inputPath);
    final originalSize = await inputFile.length();

    onProgress?.call(0.1);

    // 根据模式选择压缩方式
    switch (config.mode) {
      case CompressMode.fileSizeLimit:
        return _compressToTargetSize(inputPath, originalSize, config.fileSizeLimitKB * 1024, config, onProgress: onProgress);
      case CompressMode.totalSizeLimit:
        // 总大小模式在批量压缩时处理, 单张压缩时使用参数配置
        return _compressWithParams(inputPath, originalSize, config, onProgress: onProgress);
      case CompressMode.paramConfig:
        return _compressWithParams(inputPath, originalSize, config, onProgress: onProgress);
    }
  }

  /// 使用参数配置压缩.
  Future<CompressionResult> _compressWithParams(String inputPath, int originalSize, CompressConfig config, {void Function(double progress)? onProgress}) async {
    final outputPath = await _getOutputPath(inputPath);

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

  /// 压缩到目标大小 (二分搜索quality).
  Future<CompressionResult> _compressToTargetSize(String inputPath, int originalSize, int targetSize, CompressConfig config, {void Function(double progress)? onProgress}) async {
    // 如果原文件已小于目标大小, 直接返回
    if (originalSize <= targetSize) {
      return CompressionResult(outputPath: inputPath, originalSize: originalSize, compressedSize: originalSize);
    }

    final tool = config.toolDef;
    if (tool == null) throw Exception('未知工具: ${config.toolId}');

    int low = 1, high = 100;
    String? bestOutputPath;
    int? bestSize;

    // 二分搜索找到满足目标大小的最高质量
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final tempConfig = CompressConfig(
        formatId: config.formatId,
        toolId: config.toolId,
        params: Map.from(config.params)..['quality'] = mid,
      );

      final outputPath = await _getOutputPath(inputPath, suffix: 'q$mid');
      final args = tempConfig.buildCommand(inputPath, outputPath);
      final result = await Process.run(tool.executable, args);

      if (result.exitCode != 0) {
        high = mid - 1;
        continue;
      }

      final compressedSize = await File(outputPath).length();
      onProgress?.call(0.1 + 0.8 * (100 - high) / 100);

      if (compressedSize <= targetSize) {
        // 满足条件, 尝试更高质量
        bestOutputPath = outputPath;
        bestSize = compressedSize;
        low = mid + 1;
      } else {
        // 超出目标, 降低质量
        high = mid - 1;
        // 删除临时文件
        await File(outputPath).delete();
      }
    }

    // 如果没有找到满足条件的质量, 使用最低质量
    if (bestOutputPath == null) {
      final tempConfig = CompressConfig(
        formatId: config.formatId,
        toolId: config.toolId,
        params: Map.from(config.params)..['quality'] = 1,
      );
      bestOutputPath = await _getOutputPath(inputPath, suffix: 'q1');
      final args = tempConfig.buildCommand(inputPath, bestOutputPath);
      await Process.run(tool.executable, args);
      bestSize = await File(bestOutputPath).length();
    }

    onProgress?.call(1.0);

    return CompressionResult(outputPath: bestOutputPath, originalSize: originalSize, compressedSize: bestSize!);
  }

  /// 批量压缩到总大小上限 (按原始大小比例分配预算).
  ///
  /// TODO: 改进为基于质量指标的迭代算法:
  /// 1. 先用统一quality压缩所有文件
  /// 2. 计算每个文件的质量指标 (PSNR/SSIM)
  /// 3. 若总大小超标, 优先降低"质量损失最小"的文件的quality
  /// 4. 迭代直到满足约束, 实现质量损失均衡分配
  Future<List<CompressionResult>> compressBatchToTotalSize(
    List<String> inputPaths,
    int totalTargetBytes,
    CompressConfig config, {
    void Function(int index, double progress)? onProgress,
  }) async {
    // 获取所有文件原始大小
    final originalSizes = <int>[];
    int totalOriginal = 0;
    for (final path in inputPaths) {
      final size = await File(path).length();
      originalSizes.add(size);
      totalOriginal += size;
    }

    // 如果原始总大小已满足约束, 直接返回原文件
    if (totalOriginal <= totalTargetBytes) {
      return [
        for (int i = 0; i < inputPaths.length; i++)
          CompressionResult(outputPath: inputPaths[i], originalSize: originalSizes[i], compressedSize: originalSizes[i])
      ];
    }

    // 按比例分配预算
    final results = <CompressionResult>[];
    for (int i = 0; i < inputPaths.length; i++) {
      final targetSize = (originalSizes[i] / totalOriginal * totalTargetBytes).round();
      onProgress?.call(i, 0.0);
      final result = await _compressToTargetSize(
        inputPaths[i],
        originalSizes[i],
        targetSize,
        config,
        onProgress: (p) => onProgress?.call(i, p),
      );
      results.add(result);
    }

    return results;
  }

  /// 兼容旧接口, 使用默认配置压缩.
  Future<CompressionResult> compressJpg(String inputPath, {int quality = 80, void Function(double progress)? onProgress}) {
    final config = CompressConfig();
    config.setParam('quality', quality);
    return compress(inputPath, config, onProgress: onProgress);
  }
}
