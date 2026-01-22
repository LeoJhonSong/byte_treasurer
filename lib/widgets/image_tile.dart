/// 单图预览组件, 支持选中、右键菜单、压缩信息显示.
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/image_item.dart';

class ImageTile extends StatelessWidget {
  final ImageItem item;
  final double width;
  final double maxHeight;
  final bool isSelected;
  final void Function(bool isCtrl, bool isShift) onTap;
  final VoidCallback onCompress;
  final VoidCallback? onRevert;

  const ImageTile({
    super.key,
    required this.item,
    required this.width,
    required this.maxHeight,
    required this.isSelected,
    required this.onTap,
    required this.onCompress,
    this.onRevert,
  });

  @override
  Widget build(BuildContext context) {
    // 根据showCompressed决定显示哪张图
    final displayPath = item.showCompressed && item.compressedPath != null ? item.compressedPath! : item.path;

    return GestureDetector(
      onTap: () {
        final isCtrl = HardwareKeyboard.instance.isControlPressed;
        final isShift = HardwareKeyboard.instance.isShiftPressed;
        onTap(isCtrl, isShift);
      },
      onSecondaryTap: _handleRightClick,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 图片容器
          Container(
            width: width,
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: BoxDecoration(
              border: Border.all(color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Stack(
                children: [
                  // 图片
                  Image.file(
                    File(displayPath),
                    width: width - 6,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => SizedBox(
                      width: width - 6,
                      height: maxHeight - 6,
                      child: const Center(child: Icon(Icons.broken_image)),
                    ),
                  ),

                  // 压缩中遮罩
                  if (item.isCompressing)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black54,
                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    ),

                  // 压缩信息条 (显示压缩后版本时)
                  if (item.showCompressed && item.isCompressed)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        color: Colors.black54,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_formatSize(item.originalSize)}→${_formatSize(item.compressedSize!)}',
                              style: const TextStyle(color: Colors.white, fontSize: 10),
                            ),
                            Text(
                              '-${((1 - item.ratio!) * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 显示原图大小 (未压缩 或 已压缩但显示原图)
                  if (!item.isCompressing && (!item.isCompressed || !item.showCompressed))
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        color: Colors.black54,
                        child: Text(_formatSize(item.originalSize), style: const TextStyle(color: Colors.white, fontSize: 10)),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 文件名
          const SizedBox(height: 4),
          SizedBox(
            width: width,
            child: Text(
              item.filename,
              style: const TextStyle(fontSize: 11),
              textAlign: TextAlign.start,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _handleRightClick() {
    if (item.isCompressing) return;
    if (item.isCompressed) {
      onRevert?.call();
    } else {
      onCompress();
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
