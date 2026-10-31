# 第一版执行自检记录

执行者：Sol。更新日期：2026-10-31（北京时间）。本记录是当前软件执行自检，不代替 Astra 的独立验收或模型质量评测。

## 实际资源

- 新应用：`E:/CodexWorkspace/飞行器覆冰识别-新/Apps/icing_detector`。
- 用户权重：`Models/aircraft-ice-detection-1-yolo26s-t1/weights.pt`，20,343,685 字节。
- SHA-256：`15a0083a9cda998a52515e63c7f78d93735fa2201d467818d9aefb1f54c84e60`。
- 实际任务 `detect`，类别 `{0: Icing}`，结构配置 `yolo26s.yaml`，640 输入，保存版本 Ultralytics 8.4.55。
- 8.4.55 实际 `end2end=True`。8.4.190 曾将该旧检查点解释为 `False`，已固定训练时版本并在运行时校验。
- 外部 apple-design、animate、emil-design-eng Skill 已读取并应用；没有移动或复制 `.agents`。

## 已通过的真实检查

| 检查 | 实际证据 |
|---|---|
| 原生 Windows 应用与完整 QML 加载 | `native/report.json`，程序退出码 0，无 QML 警告 |
| GPU 与 CPU | RTX 4060 / CPU 均实际推理；手动切换后模型加载计数仍为 1 |
| 显卡显示 | 使用本机 `torch.cuda.get_device_name`，显示 `GPU (NVIDIA GeForce RTX 4060 Laptop GPU)`，没有写死型号 |
| 参数说明 | 置信度和 IoU 问号的悬停显示/移出隐藏、禁用IoU项保留说明已在Qt离屏及150% DPI下验证；不透明度按用户要求不显示问号 |
| GPU 失败回退 | 测试只注入一次 GPU 异常，随后的检测结果来自真实 CPU，界面显示 warning |
| 真正的控件操作 | 原生窗口中点击置信度滑块改变可见结果；打开标签下拉框并选项生效 |
| 置信度缓存 | 0%、25%、100% 筛选与可视化操作不增加模型推理计数 |
| IoU 适用性 | 免 NMS 权重禁用 IoU；JSON 为 null；调用也不会制造虚假变化 |
| 坐标与宽高比 | 真实方图 640×640、非方图 941×706；全部预测框在原图边界内；实际叠加层位置在窗口缩放后仍匹配原像素坐标 |
| 输入交互 | 滚轮真实 Qt 输入缩放；鼠标拖动 45 DIP，图像相应平移 45 DIP |
| 实际像素 / 适应窗口 | 原生窗口按钮操作通过；150% DPI 的实际像素比例和快捷键通过 |
| EXIF | 在真实非方图的派生副本写入方向 6，元信息与推理均使用纠正后的尺寸 |
| 图片管理 | 导入、多图切换、缓存返回、剪贴板、QUrl 拖入路径、重复跳过、移除/清空保留原文件 |
| 导出 | 单张 JPG、无框 PNG、JSON；批量原图 PNG + 检测 PNG + JSON 实际写出 |
| 显示与导出一致 | 当前置信度筛选；0% 不透明度导出像素不变；原图 PNG 副本与解码后原图像素一致 |
| 异常输入 | 损坏 PNG 被拒绝，另外两张有效照片继续工作 |
| 离线 | 应用测试流程将 Python 外连 socket 设为不可用，记录外连尝试 0 次，整个推理与导出通过 |
| 流彩与玻璃 | 原生着色器产生变化像素；面板共享背景纹理并磨砂处理，照片和检测框保持原图显示 |
| 固定参数 | 使用用户确认的 12 项数值，界面没有背景参数面板；主流场 72 秒、环流 600 秒 |
| 鼠标扰动 | 实际 Qt 鼠标事件触达背景；停留积累水纹，移开后继续衰减，最终释放轨迹 |
| 减少动效 | 实际勾选控件卸载背景和玻璃着色器、纹理与水纹计时器；画布恢复原色 `#e7ebf0`；取消勾选后像素继续变化 |
| 渲染回退 | 软件渲染环境不创建背景，使用静态外观，真实照片仍能推理 |
| 最小化 | 背景时钟与水纹计算均暂停，恢复窗口后继续 |
| 事件循环 | 后台模型/文件工作时主界面计时器持续运行；本次流彩原生完整回归最大观测间隔约 178 ms |
| 构建基础 | Python 编译检查、PowerShell 安装/打包脚本语法检查、pip 依赖检查通过 |

最终默认渲染原生窗口记录：`.runtime/verification/native/report.json`。150% DPI 记录：`.runtime/verification/hidpi/report.json`。普通离屏记录：`.runtime/verification/report.json`。

典型功能输入来自旧工作区，只读使用：

1. `Airfraft icing.v1i.coco/test/09r-218_019_jpg.rf.e6277648793142c5a12ad4d2f3c0b96b.jpg`：640×640，默认阈值输出 1 个框，置信度约 83.7%。
2. `data/Originals/batch_06_new_sites_icing_20261027/images/01_清晰原图/02_TC_机翼前缘积冰.jpg`：941×706，默认阈值输出 1 个框。

当前原生检查中首次 GPU 调用约 372 ms，第二张约 19 ms。受 GPU 其他负载、首次初始化和输入影响，这些数字仅是执行记录，不是性能承诺。耗时包含推理准备与后处理，不含前面的图片解码和文件哈希。

## 视觉证据

截图由真实 Qt 窗口的 `grabWindow()` 产生，不是静态设计稿。已查看浅色、深色、紧凑布局及非方图的实际画面。Windows 桌面截图辅助工具曾连续超时，因此改用 Qt 自身窗口截图和 QtTest 窗口输入完成验证。

流彩专用测试报告位于 `.runtime/verification/background/report.json`，软件回退报告为同目录的 `software_report.json`。已完成原生及 150% DPI 检查，着色器无运行警告；水纹固定为 288×208 网格，背景渲染纹理宽度最多 1000 像素。专用测试逐步计算水纹平均约 1 ms；这不包含 GPU 着色器帧时，未声称对所有电脑都达到固定帧率。

- `.runtime/verification/background/liquid_light.png`
- `.runtime/verification/background/liquid_dark.png`
- `.runtime/verification/background/liquid_detection.png`
- `.runtime/verification/background/static_light.png`

- `.runtime/verification/native/empty_light.png`
- `.runtime/verification/native/detection_light.png`
- `.runtime/verification/native/detection_dark.png`
- `.runtime/verification/native/compact_light.png`
- `.runtime/verification/native/wide_image.png`
- `.runtime/verification/hidpi/parameter_help.png`

界面按用户意见原位更新，代码及同名截图直接覆盖，没有另存旧版源码或增加浏览器/动画依赖；推理与导出逻辑未改变。改动前 Git 检查点为 `74abf39`。参数问号的悬停断言沿用此前离屏验证，原生窗口继续验证实际布局、输入、背景悬停和真实推理。

## 限制和边界

- 当前只支持单类 `Icing` 检测，不是通用任意模型加载器；未做批量人工标注核查，没有召回率、mAP 或实际应用质量通过结论。
- 当前机复用外部共享 Torch CUDA 环境，应用自己的 Qt/Ultralytics 等依赖在模块内；删除共享环境后需要重新安装 Torch。`README.md` 有完整路径与恢复方式。
- 没有构建 `.exe`；打包入口预留，尚未验证打包产物与分发环境。
- 独立安装脚本已检查语法，未在另一台干净 Windows 机器上重建环境。
- 测试覆盖两个真实来源样例、一个 EXIF 派生样例及一个损坏输入，不代表覆盖所有图片格式、8000 万像素边界、大规模队列或多显示器切换。
- 不透明度同时作用于框与标签：0%完全透明，100%完全不透明；高亮仅用于当前查看，不写入导出。模型最多保留 300 个候选。
- 全部代码、环境、日志、剪贴板与测试派生输出均在 Apps/icing_detector；没有在根目录新建文件夹。用户模型未移动，旧代码/数据/权重未改动。

当前结论：**Sol 执行自检 PASS，可启动交由用户和 Astra 检查；尚未收到 Astra 独立验收。**
