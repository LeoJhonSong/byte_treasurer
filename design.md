## 1. 项目定位

**科研资产压缩工作流管理器**,针对PDF/PPTX等复合文档进行资源级优化,通过"备份-压缩-预览-确认/回滚"事务机制,解决科研人员不敢压缩原始数据的痛点.

## 2. 支持格式与处理策略

### 2.1 图片

| 格式 | 策略 | 工具 |
|:---|:---|:---|
| PNG | 检测alpha通道有效性→无有效透明转JPG | pngquant (有损256色量化) / oxipng (无损) |
| JPG | 质量参数压缩 | ImageMagick |

**PNG透明度检测**: `identify -format "%[fx:mean.a]-%[fx:standard_deviation.a]"`,均值1.0且标准差0时判定为完全不透明.

### 2.2 视频

| 格式 | 策略 | 工具 |
|:---|:---|:---|
| MP4 | 内置预设 (快速/平衡/高压缩) | FFmpeg |
| MP4 | 扩展预设 | HandBrake CLI |

### 2.3 复合文档

| 格式 | 策略 | 工具 |
|:---|:---|:---|
| PPTX | 解压ZIP→遍历`ppt/media/`→压缩资源→重新打包 | Dart `archive`包 |
| PDF | 提取XObject图像→压缩→回填流对象 | pikepdf (Python副程序) |

**PPTX注意事项**: 保持文件名一致,否则需修改`.rels`和XML索引.重新打包时确保`[Content_Types].xml`结构完整.

## 3. 核心功能

### 3.1 文件夹监控

- 监控指定目录,检测新文件
- 静默期机制: 文件创建后30秒内无size变化才处理,防止截断写入中文件
- 根据策略自动压缩,原文件移至备份目录

### 3.2 事务管理

原文件 → 移至备份 → 压缩生成新文件 → 预览确认 → 删除备份 / 回滚恢复

### 3.3 差异可视化

| 模式 | 说明 |
|:---|:---|
| Slide对比 | 滑块分割,左原图右压缩图 |
| Diff Heatmap | $$\|I_{old} - I_{new}\|$$ 差值放大10倍,应用`COLORMAP_JET`伪彩色 |
| 指标量化 | PSNR, MS-SSIM, LPIPS |

### 3.4 资源展示墙

- 针对PPTX/PDF内部资源的缩略图网格
- 排序: 解析顺序 / 文件大小
- 缩略图叠加层显示: 进度条,文件大小,压缩率
- 点击定位: PPTX跳转Slide ID,PDF跳转对应页

## 4. 技术架构

### 4.1 技术栈

| 层级 | 技术选型 |
|:---|:---|
| UI | Flutter Desktop |
| 核心逻辑 | Dart `Process.run`调用CLI |
| 图片处理 | ImageMagick, pngquant, oxipng |
| 视频处理 | FFmpeg, HandBrake CLI |
| PPTX解析 | Dart `archive`包 |
| PDF解析 | Python副程序 (pikepdf) |
| 数据存储 | SQLite (`sqflite_common_ffi`) |

5. 对标分析
软件	优势	缺失
NXPowerLite	文档压缩效果极佳	闭源收费,无监控流,无差异对比
FileOptimizer	支持格式丰富	界面过时,无预览墙,无自动化
ImageOptim	图片工作流交互优秀	仅图片,无视频/复合文档
Squoosh	滑块差异对比是标杆	仅单张图片,无批处理
差异化: 跨平台GUI + 顶级压缩引擎 + PDF/PPTX资源级可视化 + 监控工作流

