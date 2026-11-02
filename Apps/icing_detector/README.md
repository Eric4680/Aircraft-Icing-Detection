# Aircraft Icing Detection Studio

Windows 原生桌面应用，Python + PySide6 / Qt Quick / QML。使用本机 YOLO26 Small 权重检测照片中的 **Icing 矩形区域**，不需要浏览器、账号、Roboflow API 或联网推理。

## 现在就用

完整解压项目后，双击本目录的 **`START.cmd`**。首次使用会打开安装向导：点击“开始安装”，自动准备 Python、运行库和依赖，实际加载权重验证成功后打开 App。已有可用环境会直接启动。

无需预先安装 Python，也无需手动创建 `.venv`。首次安装需要联网；安装和修复也可以单独双击 **`INSTALL.cmd`**。向导支持查看真实安装输出、打开日志、失败重试和取消。网络受限时，可填写代理地址；计算模式可选择自动、CPU 或 NVIDIA GPU。

1. 点击「导入图片」，也可以拖入图片，或按 **Ctrl+V** 粘贴图片/图片文件。
2. 点击左侧缩略图自动检测；「批量检测」处理列表中尚未完成当前参数检测的图片。
3. 在右侧调整置信度、不透明度和标签。模型输出、图像坐标和导出均使用当前有效结果。
4. 滚轮缩放、拖动平移、双击适应窗口。底部的适应和 1:1 按钮可恢复视图。
5. 点击右侧结果条目高亮对应框；再次点击图片背景取消高亮。
6. 顶部「导出」提供检测图、原图副本、JSON 和批量导出。右侧下方也有同样入口，可滚动查看。

软件只识别覆冰区域。它不输出飞机型号、飞机部件类别或像素级分割。

## 模型与真正生效的参数

模型位置由 `config.json` 读取，默认指向：

```text
../../Models/aircraft-ice-detection-1-yolo26s-t1/weights.pt
```

路径相对于本应用目录解析，与启动时所在目录无关。启动在后台校验 SHA-256、检查 `task=detect` 和单类 `Icing`，随后只创建一次 YOLO 模型实例。CPU/GPU 切换移动同一个实例并重新建立推理后端，不重新从磁盘加载权重。

这个权重保存于 **Ultralytics 8.4.55**，应用固定使用同版本。实际检查表明它启用端到端 **NMS-free** 检测。较新的 8.4.190 曾将这个旧权重解释为不同的检测头状态，因此本应用会拒绝不匹配的 SDK 版本。

| 控件 | 实际行为 |
|---|---|
| 置信度，默认 25% | 0%～100%，即时筛选本张图片的预测缓存，不重新推理 |
| IoU，显示 50% | 这个权重不使用传统 NMS，控件禁用；标题旁问号解释原因，JSON 中为 `null` |
| 不透明度，默认 75% | 0% 完全透明、100% 完全不透明，只更新框与标签的可视化 |
| 标签 | 类别+置信度、仅类别、仅置信度、隐藏标签、隐藏全部框 |
| 原图 / 检测结果 | 切换可视化，不改变模型输出；导出图片遵循当前显示设置 |
| 计算设备 | 仅列出实际可用的 CPU / CUDA GPU，空闲时可切换；异常时尝试回退 CPU 并显示原因 |

缓存保存 `conf=0` 返回的候选结果，**最多 300 个框**。0% 显示的是模型返回的候选集合，不是网络中所有原始位置；降低阈值会出现低置信度误报。对于将来经过适配的传统 NMS 权重，修改 IoU 会使旧缓存失效并重新检测；这不代表当前已经支持任意多类模型。

默认推理尺寸 640；Ultralytics 按比例 letterbox，应用读取其恢复到原图像素空间的 `xyxy`，不会先把原图拉伸为正方形。EXIF 方向在预览、推理和导出中一致纠正。

## 界面与快捷键

界面实际使用了外部 `C:/Users/Administrator/.agents/skills/apple-design/SKILL.md`：系统字体层次、三栏稳定布局、克制的材料与分隔、即时按压反馈、1:1 图像拖动和滑块反馈。保留 Windows 原生窗口操作，没有复制外部 `.agents` 目录。

浅色/深色按钮在右上角；右侧底部可勾选「减少动效」。这两项会记住；检测参数每次启动恢复默认。首开尺寸按当前屏幕可用区域调整，支持 Qt 自动高 DPI，最小内容窗口 960×640。

置信度和 IoU 标题旁的圆圈问号提供简短用途说明，鼠标悬停或键盘聚焦时显示。GPU 名称由本机 CUDA 设备读取，以 `GPU (实际型号)` 显示；名称过长时保留首尾，悬停可查看完整名称。

| 快捷键 | 功能 |
|---|---|
| Ctrl+O | 导入多张图片 |
| Ctrl+V | 粘贴图片或图片文件 |
| Ctrl+0 | 适应窗口 |
| Ctrl+1 | 实际像素大小；考虑显示器 DPR |
| Ctrl+Enter | 重新检测当前图片 |
| Ctrl+S | 导出当前检测图片 |

原始图片不会被移动、修改或删除。「移除」「清空」只操作本次会话的图片列表。高分辨率预览只常驻当前一张原图，列表使用小缩略图；超过 8000 万像素的输入会被拒绝，避免无界内存占用。

## 导出约定

- 检测图片：PNG / JPG，按原图分辨率重新绘制框，采用当前置信度、不透明度和标签模式。临时的选择高亮不写入导出。
- 原图副本：无框的像素副本，已纠正 EXIF 方向；PNG 保留解码后的像素，JPG 有正常有损压缩。不承诺原文件字节或元数据完全保留。
- JSON：图片名称、尺寸和哈希；模型名称、权重哈希和类别；设备、耗时、参数、显示设置；每个目标的类别、置信度、`xyxy` 与 `xywh`。
- 坐标基准：**纠正方向后的原始图像像素**；`xywh` 是左上角 x/y 和宽高，不是 YOLO 训练标签的归一化中心坐标。
- 批量导出：所选目录下建立独立的 `Icing_日期时间_标识` 子目录，每张图片有原图 PNG、检测 PNG、JSON。尚未完成全部检测时会提示先检测，不偷偷导出旧结果。
- 导出开始时冻结参数快照。后续在界面修改参数不影响正在写入的那一批。原文件变化会提示重新导入检测，避免使用过期框；同路径覆盖导入原图会被阻止。

## 依赖与当前机器的运行环境

当前实测：Python 3.12.10、PySide6 6.12.0、Ultralytics 8.4.55、PyTorch 2.14.0+cu132、torchvision 0.29.0+cu132、RTX 4060 Laptop GPU。

**当前机器只读复用了已存在的共享 CUDA 运行库：**

```text
E:/CodexWorkspace/.venvs/aircraft-icing-yolo-cuda/Lib/site-packages
```

应用自己的 `.venv/Lib/site-packages/icing_shared_cuda.pth` 将这个位置追加到包搜索路径。Qt、Ultralytics 8.4.55 等应用依赖仍优先取本模块自己的环境；没有修改共享环境。若这个共享目录被删除或移动，当前启动环境的 Torch 将不可用，请运行安装脚本建立可用的独立 Torch 环境。不要把 `.venv` 直接复制到另一台电脑。

安装向导由 Windows 自带的 PowerShell / Windows Forms 运行，支持 Windows x64。先检查权重与哈希，再检测本机 Python 3.12；没有时下载经过 SHA-256 校验的 uv 0.13.6，再由 uv 准备 CPython 3.12，保存在本 App 的 `.runtime/python`。它使用 [Astral 的独立 CPython 发行版](https://docs.astral.sh/uv/guides/install-python/)，不修改系统 PATH 或注册其他项目的 Python。

已匹配依赖的环境直接复用。全新环境安装 PyTorch 2.14.1 / torchvision 0.29.1；自动模式检测到 NVIDIA 时尝试官方 CUDA 12.6 运行库，下载失败后改用 CPU；也可以在向导中直接选择 CPU。旧脚本中的 Torch 2.9.1 在本轮全新 Python 环境的后台推理测试中出现原生崩溃，已提高依赖最低版本并用 2.14.1 完成回归。命令行也可指定向导选项：

```powershell
.\INSTALL.cmd -Device cpu
.\INSTALL.cmd -Device cuda
```

安装需要网络；正常使用无需网络。可选代理格式为 `http://地址:端口`，仅用于本次安装，不接受内嵌账号密码。日志为 `.runtime/install-output.log`、`.runtime/install-error.log`，状态文件为 `.runtime/install-status.json`。再次安装会覆盖这几个安装日志，已有环境可离线复用验证。

本轮已在隔离目录中忽略系统 Python，真实下载 CPython 3.12.16、建立全新 CPU 环境，并通过真实照片、GUI、坐标、导出及离线回归；原有共享 CUDA 环境也已验证复用。隔离目录测试不等同于另一台实体电脑：全新 CUDA 12.6 下载链路和各类驱动仍需在对应电脑验证。

安装脚本不要求管理员权限，不复制虚拟环境，不更改系统设置。当前开发工具需要额外权限加载原生库，是工具执行环境的限制，不是应用要求提权。

## 文件结构与维护

```text
Apps/icing_detector/
├─ START.cmd / INSTALL.cmd       # 启动与图形安装入口
├─ install.ps1                  # 无需 Python 的原生安装向导
├─ app.py                       # 原生桌面入口、日志、资源路径
├─ config.json                  # 模型路径、名称、哈希和推理约定
├─ requirements.txt / setup.ps1
├─ studio/
│  ├─ inference.py              # YOLO 实例、设备、真实推理
│  ├─ environment.py            # 启动前依赖检查
│  ├─ imaging.py                # 方向纠正与原图分辨率渲染
│  ├─ domain.py                 # 结果契约、筛选、JSON
│  ├─ workers.py                # 推理、文件与预览三个后台所有者
│  ├─ controller.py             # 界面状态、排队、缓存与导出协调
│  └─ library.py                # 缩略图列表模型
├─ qml/                         # 主题、可复用控件、工作区与图像视图
├─ assets/                      # 代码绘制的 SVG 图标
├─ tests/verify_app.py           # 使用真实权重的集成验证
├─ packaging/build_exe.ps1       # 后续 onedir 打包入口
├─ README.md / QA.md
├─ .venv/                       # 本应用依赖；不跟踪
└─ .runtime/                    # 日志、偏好、剪贴板缓存和检查产物；不跟踪
```

主要业务通过普通字典传递结构化结果，Qt 线程通过队列信号交接。模型、图像读写、图形界面分层；未来模块应增加自己的模型适配与结果契约，不把其他模型猜测成 Icing 检测输出。

日志在 `.runtime/studio.log`，自动轮转。剪贴板图片会保存成本地 `.runtime/clipboard/` PNG，供当前会话检测与导出；没有上传。关闭应用后可手动清理这些缓存，应用不在后台自动删除用户数据。

开发时在编辑器中选择本目录的 `.venv/Scripts/python.exe`。安装器测试入口为 `powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify_installer.ps1 -ManagedPython`；有需要可附加 `-Proxy http://地址:端口`。首次测试会在 `.runtime/installer-verification` 中下载并创建独立 CPU 环境，已有测试环境则用于复用和修复检查。

## 测试与打包

### 流彩背景与玻璃材质

背景由提供的 `liquid-pigment-ice.html` 移植为 Qt 原生着色器，不嵌入浏览器。保留噪声流场、周期环流、颜料混色、薄膜纹理及鼠标水纹；照片、检测框和导出内容不经过背景处理。工具栏和侧栏采样同一张背景纹理，进行磨砂模糊和材质叠色。

背景采用用户确认的固定参数，App 中不提供调节面板：流动周期 72 秒、环流周期 600 秒、环流柔度 76%、流动幅度 67%、色彩交融 55%、纹理细节 60%、薄膜光泽 33%、色彩浓度 100%；鼠标扰动 85%、扰动范围 60%、酝酿时长 2.5 秒、轨迹留存 6 秒。轨迹留存后另有原算法的 5 秒自然衰减。

勾选“减少动效”会卸载整个背景、玻璃着色器及水纹计时器，恢复原有静态界面；浅色模式恢复白色面板和灰色画布，深色模式恢复原有深色面板。取消勾选会重新启用背景。窗口最小化时暂停计算，不支持着色器的软件渲染环境自动使用静态外观。

相关代码为 `qml/LiquidBackground.qml`、`qml/GlassSurface.qml`、`qml/shaders/` 和 `studio/ambient.py`。着色器 `.qsb` 已随代码提供，直接启动无需编译；修改 `.frag` 后运行 `packaging/build_shaders.ps1` 更新。现有打包脚本已包含整个 `qml` 目录，因此会携带着色器文件。

实现依据：[Qt ShaderEffect](https://doc.qt.io/qt-6/qml-qtquick-shadereffect.html)、[ShaderEffectSource](https://doc.qt.io/qt-6/qml-qtquick-shadereffectsource.html) 和 [QSB](https://doc.qt.io/qt-6/qtshadertools-qsb.html)。专用背景验证为 `.venv\Scripts\python.exe tests\verify_background.py --image "真实照片.jpg"`；加 `--software` 检查静态回退。

见 **`QA.md`** 和 `.runtime/verification/native/report.json`。可用任意自己选择的真实图片重新执行：

```powershell
.\.venv\Scripts\python.exe -X utf8 tests\verify_app.py --native --image "真实照片1.jpg" --extra "真实非正方形照片2.jpg"
```

测试的首张照片需在默认阈值下有模型输出；测试会故意导入损坏图片、触发一次 GPU 异常并验证真实 CPU 回退。它不是训练脚本，也不向外发送图片。无桌面检查可省略 `--native`，使用 Qt 离屏渲染；设置 `QT_SCALE_FACTOR=1.5` 可检查高 DPI。测试截图来自实际 QML 和真实模型结果。

`packaging/build_exe.ps1` 预留 PyInstaller **onedir** 打包流程，模型保持外置，配置在 exe 旁，构建目录限制在本应用内。该脚本已检查语法，**本轮没有构建或验收 `.exe`**；后续还需核对 Qt 插件、CUDA 依赖、冷启动和分发许可。生成的配置引用当前模型绝对位置，换电脑部署需修改路径并重新核对哈希。
