/// 图片项数据模型.
library;

import 'dart:io';

class ImageItem {
  final String path;
  final int originalSize;
  int? compressedSize;
  String? compressedPath;
  bool isCompressing;
  bool showCompressed;

  ImageItem({
    required this.path,
    required this.originalSize,
    this.compressedSize,
    this.compressedPath,
    this.isCompressing = false,
    this.showCompressed = false,
  });

  static Future<ImageItem> fromPath(String path) async {
    final size = await File(path).length();
    return ImageItem(path: path, originalSize: size);
  }

  /// 是否已压缩.
  bool get isCompressed => compressedPath != null;

  /// 压缩比, 压缩后/压缩前.
  double? get ratio => compressedSize != null ? compressedSize! / originalSize : null;

  /// 文件名 (不含路径).
  String get filename => path.split('/').last;
}
