import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';

class DropZone extends StatefulWidget {
  final Function(String filePath) onFileDropped;

  const DropZone({super.key, required this.onFileDropped});

  @override
  State<DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<DropZone> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (details) {
        setState(() {
          _isDragging = true;
        });
      },
      onDragExited: (details) {
        setState(() {
          _isDragging = false;
        });
      },
      onDragDone: (details) {
        setState(() {
          _isDragging = false;
        });

        // 处理拖入的文件
        for (var file in details.files) {
          final ext = file.path.toLowerCase().split('.').last;
          if (ext == 'jpg' || ext == 'jpeg') {
            widget.onFileDropped(file.path);
          }
        }
      },
      child: Container(
        width: double.infinity,
        height: 300,
        decoration: BoxDecoration(
          color: _isDragging ? Theme.of(context).colorScheme.primary.withAlpha(25) : Colors.grey.withAlpha(25),
          border: Border.all(color: _isDragging ? Theme.of(context).colorScheme.primary : Colors.grey, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_upload_outlined, size: 64, color: _isDragging ? Theme.of(context).colorScheme.primary : Colors.grey),
              const SizedBox(height: 16),
              Text(
                _isDragging ? '松开以添加文件' : '拖放文件到此处',
                style: TextStyle(
                  fontSize: 18,
                  color: _isDragging ? Theme.of(context).colorScheme.primary : Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
