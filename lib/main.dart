import 'package:flutter/material.dart';
import 'color_schemes.dart';
import 'widgets/drop_zone.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(useMaterial3: true, colorScheme: lightColorScheme),
      darkTheme: ThemeData(useMaterial3: true, colorScheme: darkColorScheme),
      debugShowCheckedModeBanner: false,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _droppedFilePath;

  void _handleFileDropped(String filePath) {
    setState(() {
      _droppedFilePath = filePath;
    });

    // 打印文件路径(用于测试)
    print('拖入文件: $filePath');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Byte Treasurer'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 拖放区域
            DropZone(onFileDropped: _handleFileDropped),

            const SizedBox(height: 24),

            // 显示拖入的文件信息
            if (_droppedFilePath != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('拖入的文件:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(_droppedFilePath!, style: const TextStyle(fontSize: 14, fontFamily: 'monospace')),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
