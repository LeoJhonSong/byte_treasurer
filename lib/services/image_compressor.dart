/// JPG图片压缩服务, 使用ImageMagick进行质量参数压缩.
///
/// 用法:
/// ```dart
/// final compressor = ImageCompressor();
/// final result = await compressor.compressJpg('/path/to/input.jpg', quality: 85);
/// ```
library;

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class CompressionResult {
  final String outputPath;
  final int originalSize;
  final int compressedSize;

  /// 压缩比, 压缩后/压缩前, 越小越好.
  final double ratio;

  CompressionResult({
    required this.outputPath,
    required this.originalSize,
    required this.compressedSize,
  }) : ratio = compressedSize / originalSize;
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

  /// 压缩JPG图片.
  Future<CompressionResult> compressJpg(
    String inputPath, {
    int quality = 80,
    void Function(double progress)? onProgress,
  }) async {
    final inputFile = File(inputPath);
    final originalSize = await inputFile.length();

    // 生成输出路径: 缓存目录下, 用原路径hash + 文件名避免冲突
    final cacheDir = await _getCacheDir();
    final pathHash = inputPath.hashCode.toRadixString(16);
    final basename = p.basenameWithoutExtension(inputPath);
    final ext = p.extension(inputPath);
    final outputPath = p.join(cacheDir.path, '${pathHash}_$basename$ext');

    onProgress?.call(0.1);

    // 调用ImageMagick压缩
    final result = await Process.run('magick', [
      inputPath,
      '-quality',
      quality.toString(),
      outputPath,
    ]);

    onProgress?.call(0.9);

    if (result.exitCode != 0) {
      throw Exception('ImageMagick压缩失败: ${result.stderr}');
    }

    final compressedSize = await File(outputPath).length();
    onProgress?.call(1.0);

    return CompressionResult(
      outputPath: outputPath,
      originalSize: originalSize,
      compressedSize: compressedSize,
    );
  }
}
