# portable-idris2

在当前目录生成完整、可移动的 Windows Idris 2 开发环境。

项目同时发布 Core 和 Full 两种环境。Core 包含 Idris 2、标准库和带线程
支持的 Chez Scheme；Full 额外包含 Pack、`idris2-lsp`、Git、MSYS2、GCC/GMP
及 RefC 工具链。两者都不会永久修改系统 `PATH`，复制或改名整个目录后仍可使用。

目前仅支持 Windows x86-64。

发布包承诺的组件在下载完成后均可离线使用。启动器不会调用 Pack、检查更新或自动下载内容。

## 这个压缩包从哪里来

Core 和 Full 都不是从维护者电脑里手工复制出来的黑盒。它们由本仓库的
PowerShell 构建脚本在干净的 Windows GitHub Actions 运行器中生成：从固定的
tag 或 commit 取得 Chez Scheme、Idris 2、Pack 和 LSP 源码，应用仓库内公开补丁，
完成自举编译，再组装、测试和压缩。Full 中的 MSYS2/GCC 工具链也会列出实际
打包的软件包版本。

现行 Core/Full 发布包所用的全部提交、补丁哈希、构建提交、公开构建记录和复现
命令都列在 [`REPRODUCING.md`](REPRODUCING.md)。自动构建的可执行定义是
[`Publish toolchain` 工作流](.github/workflows/release-toolchain.yml)，没有未公开的
本地打包步骤。

## 使用

在希望创建环境的目录中打开 PowerShell，执行：

```powershell
irm "https://raw.githubusercontent.com/one-click-run/portable-idris2/main/init.ps1" | iex
```

安装完成后，双击生成的 `OCR-portable-idris2-<版本>.cmd`。
当 Release 同时存在 Core 和 Full 时，安装器会显示选择窗口或编号菜单。
Full 版还会生成相邻的 `OCR-portable-idris2-<版本>-VSCode.cmd`。双击后会用
便携工具链打开包内 Hello World 工程，并让 Idris 2 扩展通过自包含原生代理启动
包内 LSP，不需要修改系统环境变量。代理会修正 Windows Chez 输出的 LSP 换行格式，
其可复现源码位于 `native/Launch-Idris2-LSP.c`。未安装 `bamboo.idris2-lsp` 扩展时会显示提示。

完全离线的目标机器可以先从 Release 复制 ZIP 和相邻的 `.sha256` 文件，再运行：

```powershell
.\init.ps1 -Archive .\portable-idris2-0.8.0-windows-x86_64.zip
```

也可以无交互指定 Release 资产和安装名称：

```powershell
$env:ONE_CLICK_RUN_PORTABLE_IDRIS2_SELECTED_ASSET = "portable-idris2-0.8.0-windows-x86_64.zip"
$env:ONE_CLICK_RUN_PORTABLE_IDRIS2_INSTALL_NAME = "work"
irm "https://raw.githubusercontent.com/one-click-run/portable-idris2/main/init.ps1" | iex
```

安装 Full 版：

```powershell
$env:ONE_CLICK_RUN_PORTABLE_IDRIS2_SELECTED_ASSET = "portable-idris2-full-0.8.0-windows-x86_64.zip"
irm "https://raw.githubusercontent.com/one-click-run/portable-idris2/main/init.ps1" | iex
```

## 特性

- 单脚本安装，普通用户不需要预装构建工具。
- 工具链和 SHA-256 校验文件由本组织的 GitHub Release 托管。
- 安装器在解压前强制校验 SHA-256。
- `IDRIS2_PREFIX`、Chez 路径和用户数据都由启动器动态设置。
- 工具链不包含写死的安装目录；整个文件夹可以复制、改名和删除。
- GitHub Actions 依照 Idris 2 官方 Windows CI，从固定版本源码完成自举。
- 每个发布包内含精确提交来源清单 `SOURCE-MANIFEST.json`、SPDX SBOM 和离线能力说明。

## 环境内容

- Idris 2 编译器及标准库
- 带线程支持的 Chez Scheme
- Chez 后端所需的 MinGW 运行库
- `examples/hello/Main.idr` 示例

Full 版另外包含：

- Pack 及与 Idris 2 `v0.8.0` 对应的固定 package collection
- `idris2-lsp` 及其依赖和源码索引
- 可移动的 MSYS2、Git、Bash、Make、GCC 与 GMP 开发环境
- 可直接使用的 RefC 后端
- 位于便携目录内的 Pack 配置、状态、包缓存和 Git 配置

Pack 上游尚未正式维护原生 Windows 支持。本项目对固定 Pack 提交应用了一个
仓库内可审计的最小补丁，避免 `cmd.exe` 将 `mkdir -p` 误解析为不兼容的
内置命令。Idris 2 补丁则让 Windows 能识别 RefC 数据目录，并正确引用带空格的编译路径。
两份补丁均位于 `patches/`，其 SHA-256 会写入每个发布包的来源清单。

Full 中的 LSP 只从 collection 锁定的 `LSP-lib` 和 `idris2-lsp` 两个提交构建，构建过程不会让 Pack 遍历或缓存整个远端包集合。`pack install` 安装发布包以外的第三方包属于用户明确发起的联网操作，不在离线承诺范围内。完整边界见 [OFFLINE-GUARANTEE.md](OFFLINE-GUARANTEE.md)。

进入环境后可以运行：

```console
idris2 --version
idris2 examples\hello\Main.idr -o hello
build\exec\hello.cmd
```

Full 版还可以运行：

```console
pack help
idris2-lsp
idris2 --cg refc examples\hello\Main.idr -o hello-refc
build\exec\hello-refc.exe
```

## 维护者发布工具链

1. 打开仓库的 **Actions** 页面。
2. 选择 **Publish toolchain**。
3. 输入 Idris 2 与 Chez Scheme 版本，或保留默认值。
4. 运行工作流。

工作流将构建 Chez Scheme、从官方 bootstrap 源码自举 Idris 2、从锁定提交构建 Pack
及 LSP、收集 MSYS2/MinGW 工具链、执行 Chez 与 RefC 迁移测试、生成两种 ZIP
和 SHA-256，生成来源清单与 SBOM，执行本地归档离线安装测试，并上传到固定的 `toolchain` Release。发布后还会重新运行公开的
一行安装器验证 Core 与 Full。

构建原理见 [BUILDING.md](BUILDING.md)，现行版本的精确来源、复现命令和限制见 [REPRODUCING.md](REPRODUCING.md)。本项目承诺“可审计、可重建”，暂不宣称不同机器构建出的 ZIP 能逐字节一致。

## 安全与来源

在线模式下，安装器只从 `one-click-run/portable-idris2` Release 下载工具链；离线模式接受本地 ZIP。两种模式都要求相邻
的 SHA-256 文件存在且匹配。上游来源及许可证见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 许可证

本仓库中的安装、启动和构建脚本采用 MIT 许可证。打包的第三方项目继续
使用各自的上游许可证。

