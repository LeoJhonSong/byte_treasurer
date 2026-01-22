/// 快捷键 Intent 定义.
library;

import 'package:flutter/widgets.dart';

// 选择相关
class SelectAllIntent extends Intent {
  const SelectAllIntent();
}

class ClearSelectionIntent extends Intent {
  const ClearSelectionIntent();
}

// 缩放相关
class ZoomIntent extends Intent {
  final bool zoomIn;
  const ZoomIntent.zoomIn() : zoomIn = true;
  const ZoomIntent.zoomOut() : zoomIn = false;
}
