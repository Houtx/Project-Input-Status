<p align="center">
  <img src="InputStatus/Resources/AppIcon-1024.png" width="112" alt="Input Status icon">
</p>

# Input Status

一个轻量的 macOS 桌面挂件，用于查看 [AI.INPUT.IM](https://status.input.im/) 的服务可用状态。它提供原生玻璃界面、菜单栏入口、约两分钟自动刷新和手动刷新，不需要安装完整 Xcode，也不需要 Apple Developer 账号。

## 功能

- 桌面挂件直接显示服务在线状态与可用率。
- macOS 26 使用原生 Liquid Glass，macOS 14/15 使用半透明材质回退。
- 支持锁定挂件位置，避免误拖动；解锁后可移动并自动保存位置。
- 约每两分钟自动刷新，右上角按钮可立即刷新。
- 菜单栏同步显示状态，并可显示或隐藏桌面挂件。
- 网络异常时保留最近一次成功数据，超过约四分钟会标记为过期。
- 安装后自动配置用户级登录启动。
- 保留 WidgetKit 扩展，可在系统允许时添加原生小组件。

## 系统要求

- macOS 14 Sonoma 或更高版本。
- Apple Silicon 或 Intel Mac。
- macOS Command Line Tools。

如果尚未安装 Command Line Tools，可运行：

```zsh
xcode-select --install
```

这不会安装完整 Xcode。

## 安装

```zsh
git clone https://github.com/Houtx/Project-Input-Status.git
cd Project-Input-Status
./scripts/install.sh
```

安装脚本会：

1. 使用当前系统 SDK 编译主程序和 Widget 扩展。
2. 使用 ad-hoc 签名生成本机可运行的应用。
3. 安装到 `/Applications/InputStatus.app`。
4. 注册 Widget 扩展并配置登录启动。
5. 启动桌面挂件和菜单栏应用。

## 使用

- 点击锁形图标切换位置锁定。默认锁定，锁定时无法拖动。
- 点击刷新图标立即请求最新状态。
- 点击“打开状态页”查看完整状态页。
- 点击菜单栏状态图标，可显示或隐藏桌面挂件。
- 挂件解锁后可以拖动，位置会在下次启动时恢复。

## WidgetKit 说明

项目包含标准 WidgetKit 扩展，可在桌面空白处右键选择“编辑小组件”，然后搜索“AI.INPUT.IM 服务状态”。

本项目使用本机 ad-hoc 签名，不同 macOS 版本可能不会在系统小组件图库中展示该扩展。应用内置的桌面挂件不受此限制，也是无 Xcode 环境下的默认实现。

## 隐私

- 不需要登录或填写 API Key。
- 不包含遥测、广告或用户追踪。
- 仅向 `https://status.input.im/api/status` 请求公开状态数据。
- 状态缓存和挂件偏好仅保存在本机应用沙箱中。

## 开发

仅构建、不安装：

```zsh
./scripts/build.sh
```

构建产物位于 `build/InputStatus.app`。

重新生成应用图标：

```zsh
./scripts/generate-icon.sh
```

工程结构：

- `InputStatus/App`：桌面挂件、菜单栏应用和周期刷新。
- `InputStatus/Widget`：WidgetKit 扩展。
- `InputStatus/Shared`：状态 API、数据模型和本地缓存。
- `InputStatus/Resources`：图标、Info.plist 和沙箱权限。
- `scripts`：无 Xcode 的构建、安装和卸载脚本。
- `InputStatus.xcodeproj`、`project.yml`：可选的 Xcode/XcodeGen 工程描述。

## 卸载

```zsh
./scripts/uninstall.sh
```

卸载会删除 `/Applications/InputStatus.app`、注销 Widget 扩展并移除登录启动项，不会删除项目源码。

## 签名说明

默认构建采用 ad-hoc 签名，仅用于当前 Mac 本地安装。面向其他用户分发时，应改用 Apple Developer ID 签名并完成公证。
