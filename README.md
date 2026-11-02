# Aircraft Icing Detection Studio

飞行器可见覆冰区域检测项目。Windows 桌面 App 使用本地 YOLO26 Small 模型，输出 `Icing` 类别的检测框；不包含飞机型号识别、部件识别或像素级分割。

## 项目内容

| 目录 | 内容 |
| --- | --- |
| [Apps/icing_detector](Apps/icing_detector/) | PySide6 / QML 桌面 App、安装与启动脚本、验证程序 |
| [Models/aircraft-ice-detection-1-yolo26s-t1](Models/aircraft-ice-detection-1-yolo26s-t1/) | 第一版模型权重 `weights.pt` 与来源说明 |
| [Datasets/v1_annotated](Datasets/v1_annotated/) | 第一版 YOLO26 数据集 ZIP，700 张图片及标注：训练 510、验证 120、测试 70 |
| Docs | 项目文档预留位置 |

## 从源码启动

1. 安装 Windows x64 Python 3.12。安装时启用 Python Launcher。
2. 克隆或下载本仓库；首次下载应包含 `weights.pt`。
3. 进入 `Apps/icing_detector`，双击 `INSTALL.cmd`，等待安装与权重加载检查完成。
4. 双击 `START.cmd` 启动 App。

第一次安装需要网络。安装脚本会创建本机 `.venv` 并安装依赖，不需要复制其他人的环境。模型推理在本机完成；使用 App 不需要解压训练数据集。

详细操作、CPU / GPU 配置及已知限制见 [App 使用说明](Apps/icing_detector/README.md)，软件自检记录见 [QA](Apps/icing_detector/QA.md)。当前仓库提供源码，尚未提供经过异机验证的 Windows 便携发布包。

## 团队协作

- 每人从最新 `main` 创建功能分支，完成后通过 Pull Request 合并。
- 第一版模型和数据集保留为固定基线，后续版本使用新的明确版本名。
- `.venv`、`.runtime`、日志、缓存和打包产物不提交。
- 数据集来源见模型目录中的 `readme.txt` 以及 ZIP 内的 Roboflow 说明；导出配置标记为 `Private`，团队协作建议使用私有仓库。
