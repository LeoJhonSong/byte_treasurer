/// 图片网格组件, Wrap布局自适应排列.
library;

import 'package:flutter/material.dart';
import '../models/image_item.dart';
import 'image_tile.dart';

class ImageGrid extends StatelessWidget {
  final List<ImageItem> items;
  final Set<String> selectedPaths;
  final double tileWidth;
  final void Function(String path, {bool isCtrl, bool isShift}) onTap;
  final void Function(String path) onCompress;
  final void Function(String path)? onRevert;

  const ImageGrid({
    super.key,
    required this.items,
    required this.selectedPaths,
    this.tileWidth = 150,
    required this.onTap,
    required this.onCompress,
    this.onRevert,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_upload_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('拖放JPG文件到此处', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: items.map((item) {
          return ImageTile(
            item: item,
            width: tileWidth,
            maxHeight: tileWidth,
            isSelected: selectedPaths.contains(item.path),
            onTap: (isCtrl, isShift) => onTap(item.path, isCtrl: isCtrl, isShift: isShift),
            onCompress: () => onCompress(item.path),
            onRevert: item.isCompressed ? () => onRevert?.call(item.path) : null,
          );
        }).toList(),
      ),
    );
  }
}
