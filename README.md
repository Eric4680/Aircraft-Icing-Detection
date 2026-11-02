# Aircraft Icing Detection Studio

Windows 桌面工具，使用本地 YOLO26 Small 模型检测照片中的 `Icing` 覆冰区域。

## 下载与启动

1. 在 GitHub 点击 **Code → Download ZIP**，下载后**完整解压**。
2. 打开解压后的 **`Apps/icing_detector`** 文件夹，双击 **`START.cmd`**。
3. 首次使用点击向导中的**“开始安装”**，等待完成，App 会自动打开。

**首次安装需要联网，无需手动安装 Python。以后直接双击 `START.cmd` 即可。**

请保留原有目录结构；运行 App 无需解压训练数据集。需要修复安装时，双击同目录的 `INSTALL.cmd`。

## 项目目录

| 目录 | 内容 |
| --- | --- |
| [Apps/icing_detector](Apps/icing_detector/) | App 源码、安装与启动入口、测试脚本 |
| [Models/aircraft-ice-detection-1-yolo26s-t1](Models/aircraft-ice-detection-1-yolo26s-t1/) | 第一版模型权重 `weights.pt` 与模型说明 |
| [Datasets/v1_annotated](Datasets/v1_annotated/) | 第一版数据集 ZIP，含 700 张图片及标注 |
| [Docs](Docs/) | 项目文档目录 |

## 团队协作

- **参与开发请使用 Git 克隆仓库**，地址从 GitHub 的 **Code** 菜单复制；ZIP 下载适合直接运行体验。
- 开始工作前更新本地 `main`，再创建自己的功能分支，避免多人同时直接修改 `main`。
- 完成后推送自己的分支，创建 **Pull Request（合并请求）**，说明改动和验证结果，经队友检查后合并。
- `main` 保持可启动；修改模型、依赖或配置时，验证启动与真实检测，并同步相关说明。
- 第一版模型和数据集作为固定基线保留，后续版本新增明确的版本目录。
- `.venv`、`.runtime`、缓存、日志和个人导出结果不提交。

## 详细说明

· [模型与数据来源](Models/aircraft-ice-detection-1-yolo26s-t1/README.md) 
· [App 开发说明](Apps/icing_detector/README.md) 
· [App 自检记录](Apps/icing_detector/QA.md)
