# MediaFinder

[English](README_EN.md) | 简体中文

基于 Everything 高速索引的本地媒体素材管理工具。双击即用：自动拉起内置 Everything、自动索引、自动打开网页控制台，毫秒级搜索、实时更新。

## 功能

- 毫秒级全文搜索（Everything 实时索引，文件新增秒级可见）
- 类型筛选（视频/图片/音频）+ 时间筛选
- 游戏/软件素材自动分类（原神、鸣潮、Steam、剪映等 30+ 分类）
- 视频封面自动生成
- 深色/浅色主题
- 无 Everything 环境自动回退传统磁盘扫描模式

## 一键使用

双击 `MediaFinder.exe` 即可，无需安装：

1. 自动解压运行所需文件到 `%LOCALAPPDATA%\MediaFinder`
2. 自动启动内置 Everything（无则自动拉起，已有则复用）
3. 自动启动网页控制台（端口 8765）并打开浏览器
4. 桌面自动生成快捷方式

首次运行 Everything 会建立全盘索引（约 1~3 分钟），之后秒级就绪。

## 从源码构建

需要 Windows + .NET Framework 4.x（系统自带）：

```
powershell -ExecutionPolicy Bypass -File source\MediaFinder-build.ps1
```

产物 `MediaFinder.exe` 为单文件：内嵌全部脚本、前端和 Everything 二进制，可直接分发。

## 运行原理

```
MediaFinder (网页界面)  ←HTTP→  本地服务器(端口8765)  ←IPC→  Everything(实时索引)
```

搜索走 Everything 高速索引（Everything64.dll 进程内 IPC）；没有 Everything 时自动回退传统磁盘扫描。

## 目录结构

```
├── MediaFinder.exe          # 分发用单文件程序（构建产物）
├── source/
│   ├── MediaFinder-build.ps1      # 构建脚本
│   ├── MediaFinder-launcher.cs    # 启动器（自解压 + 拉起服务器）
│   ├── MediaFinder.ps1            # 主入口
│   ├── MediaFinderServer.ps1      # HTTP 服务器（端口 8765）
│   ├── MediaFinder.Core.ps1       # 核心逻辑 + Everything 提供层
│   ├── MediaFinder-thumb.ps1      # 视频封面取帧工作进程
│   ├── web/                       # 网页控制台前端
│   └── Everything.exe / Everything64.dll  # 内嵌组件（见下）
```

## 第三方组件声明

本程序内嵌并分发以下第三方组件（详见 `THIRD-PARTY.txt`）：

| 组件 | 许可 | 说明 |
|---|---|---|
| Everything (Everything.exe / Everything64.dll) | [MIT](https://www.voidtools.com/License.txt) | Copyright (C) 2018 David Carpenter (voidtools)，允许再分发，分发须保留版权声明 |
| PCRE（Everything 内嵌正则库） | BSD-3-Clause | Copyright (c) 1997-2012 University of Cambridge |

Everything 官方许可与来源：<https://www.voidtools.com/>（官方论坛确认 MIT 许可，允许捆绑分发）。

## License

MediaFinder 本体：MIT License（见 LICENSE）。Everything 部分版权归 voidtools。
