# 发布包来源与复现

这份文档说明 Release 中的 Core 和 Full ZIP 是怎样产生的，以及第三方怎样独立重跑同一份构建配方。

## 现行发布包的身份

- Release：[`toolchain`](https://github.com/one-click-run/portable-idris2/releases/tag/toolchain)
- Core：`portable-idris2-0.8.0-windows-x86_64.zip`
- Full：`portable-idris2-full-0.8.0-windows-x86_64.zip`
- 构建仓库提交：`b30bb0b4d75589ad8f052464e73d80331038ea08`
- 成功的公开构建：[GitHub Actions run 41228257084](https://github.com/one-click-run/portable-idris2/actions/runs/41228257084)

两种包共同使用：

| 组件 | tag | 解析出的提交 |
| --- | --- | --- |
| Idris 2 | `v0.8.0` | `15a3e4e70843f7a34100f6470c04b791330788df` |
| Chez Scheme | `v10.4.1` | `e95a7efbafa2cf3bd5343ea542e6bc909a7ab2c4` |

Full 另外使用：

| 输入 | 固定值 |
| --- | --- |
| Pack | `cb842e66c7e9834fae9cdf05ba33ca64fbec949f` |
| Pack database | `69ddc094a218941bba5516828c2ee1dfdcc640f5` |
| collection | `nightly-251031` |
| LSP-lib | `ca77e80a392b8cfeee3aaeb150069957699cdb82` |
| idris2-lsp | `81344545c134c8e7105ecf1fdd7a1caae6647035` |

公开的 Windows 兼容补丁也属于构建输入：

| 补丁 | SHA-256 |
| --- | --- |
| `patches/idris2-windows-data-directories.patch` | `6d7152bf4cb6e641c2710ccd4db2705aed157ae0909bd81dbc75f2c06a6ed088` |
| `patches/pack-windows-mkdir.patch` | `355b5d90a1b32b291789544219683784b845b49b628918167c63bd2f4006f81d` |

这些值同时记录在 ZIP 内的 `SOURCE-MANIFEST.json`，也以
`*.source-manifest.json` 独立附在 Release 上。`*.spdx.json` 是 SPDX 2.3
SBOM，`*.sha256` 校验整个 ZIP。Full 内的 `MSYS2-PACKAGES.txt` 列出实际装入
压缩包的每一个 MSYS2 软件包及版本。

## Core 是怎样产生的

1. GitHub Actions 准备 MSYS2、GCC、GMP、Git、Make 等构建依赖。
2. `scripts/build-toolchain.ps1` 按 tag 克隆 Idris 2 和 Chez Scheme，并记录 tag 实际解析出的完整 commit。
3. 脚本校验并应用仓库内的 Idris 2 Windows 补丁。
4. Chez Scheme 以线程支持编译；随后用它从官方 bootstrap 源码自举 Idris 2 并安装标准库。
5. 脚本只复制运行所需的 MinGW DLL、启动器、示例、补丁、许可证、manifest 和 SBOM。
6. 未压缩目录先执行自检，然后产生 Core ZIP 和 SHA-256。

## Full 是怎样产生的

1. `scripts/build-full-toolchain.ps1` 先调用上面的 Core 构建，保证两种包的编译器来源一致。
2. 它读取固定 Pack database commit 中的固定 collection，并核对 collection 所要求的 Idris 2 commit。
3. 它按 commit 取得并编译 Pack，只取得 LSP 必需的 `LSP-lib` 和 `idris2-lsp`，不遍历整个远端包集合。
4. 两个 Windows 兼容补丁在源码树中公开应用，补丁哈希写入 manifest。
5. runner 上完整的 MSYS2/Git/GCC/GMP 开发环境被复制进 Full；缓存、临时目录和用户目录被清空，实际包清单写入 `MSYS2-PACKAGES.txt`。
6. Full 用包内 MSYS2 GCC 编译 `native/Launch-Idris2-LSP.c`。该原生代理只把 Windows Chez
   产生的 LF-only LSP 消息头规范化为协议要求的 CRLF，JSON 正文和 stdin 保持原始字节；完全相同的
   C 源码随 ZIP 放在 `sources/`，源码和 EXE 的 SHA-256 写入 manifest。
7. 工作流把环境复制到含空格的新路径，并在无效网络代理下分别用 Chez 和 RefC 编译、运行 Hello World，
   再发送 `didOpen` 和 `textDocument/hover`，必须实际得到 `main : IO ()` 才算 LSP 可用。
8. Core 和 Full 都通过本地归档离线安装测试后才上传。上传后，公开的一行安装器还会分别安装两种包并再次验收。

流程的可执行定义是
[`release-toolchain.yml`](.github/workflows/release-toolchain.yml)、
[`build-toolchain.ps1`](scripts/build-toolchain.ps1) 和
[`build-full-toolchain.ps1`](scripts/build-full-toolchain.ps1)。文档与代码冲突时，以构建提交中的代码和产物内 manifest 为准。

## 在 Windows 上复现

最接近正式发布的环境是 GitHub 的 `windows-latest` runner。手工复现需要 PowerShell、Git、完整 MSYS2 MINGW64，以及 `base-devel git make tar mingw-w64-x86_64-gcc mingw-w64-x86_64-gmp`。构建过程需要联网取得源码；生成的工具链运行时不需要联网。

在准备好依赖后执行：

```powershell
git clone https://github.com/one-click-run/portable-idris2.git
cd portable-idris2
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\reproduce-release.ps1 -Edition Full -MsysRoot C:\msys64
```

只重建 Core：

```powershell
.\scripts\reproduce-release.ps1 -Edition Core -MsysRoot C:\msys64
```

脚本固定使用上表中的版本和提交，并在构建过程中验证 collection 与 Idris 2 是否匹配。结果写入 `dist\`。

也可以不在本机准备环境，直接 fork 仓库并从 Actions 手动运行
`Publish toolchain`；工作流中的默认输入就是现行配方。不要把 fork 生成的文件误传到本项目的正式 Release。

## 怎样审计已经发布的 ZIP

下载 ZIP 及相邻的 `.sha256`，例如：

```powershell
$zip = '.\portable-idris2-full-0.8.0-windows-x86_64.zip'
$expected = ((Get-Content "$zip.sha256" -Raw) -split '\s+')[0]
$actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected) { throw "SHA-256 mismatch" }
```

解压后，将 `SOURCE-MANIFEST.json`、`SBOM.spdx.json`、`patches\` 和
`MSYS2-PACKAGES.txt`（仅 Full）与仓库及 Release 独立附件对照。manifest 的
`repositoryCommit` 能精确定位生成该包的构建脚本。

## “可复现”在这里的准确含义

本项目承诺的是：构建配方公开，源码 tag/commit 和补丁明确，构建可由第三方重跑，结果能通过相同的迁移、编译与离线测试。

目前**不承诺 ZIP 逐字节相同**，也不承诺多年后只依赖公网仍能找回全部构建输入：

- ZIP 时间戳、压缩器和 GitHub runner 镜像会影响字节结果；
- MSYS2 安装命令取得构建时镜像中的软件包。实际版本已写入 Full 的 `MSYS2-PACKAGES.txt`，但外部镜像可能清理旧包；
- 上游 Git 仓库和下载地址也可能移动或消失。

因此，Release 的 `.sha256` 用于验证“下载到的是否为我们发布的原包”，不表示任意重建都应得到同一哈希。为了保证用户以后仍能安装，正式运行所需的完整 Core/Full ZIP 和校验文件由 `one-click-run` 自己的 Release 托管；复现脚本依赖网络，只承担透明审计与重建职责，不是用户安装时的依赖。
