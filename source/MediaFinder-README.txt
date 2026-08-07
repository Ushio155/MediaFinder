MediaFinder 使用说明
============================================

【一键使用】
双击 MediaFinder.exe 即可，无需安装任何东西：
  1. 自动解压运行所需文件到 %LOCALAPPDATA%\MediaFinder
  2. 自动启动内置的 Everything 高速索引（无则自动拉起，已有则复用）
  3. 自动启动网页控制台并打开浏览器
  4. 桌面自动生成快捷方式

【首次启动】
Everything 首次运行会建立全盘索引（约 1~3 分钟），期间搜索结果渐进更新，
完成后即可秒级搜索。之后每次启动几秒内就绪。

【运行原理】
  MediaFinder (网页界面)  ←HTTP→  本地服务器(端口8765)  ←IPC→  Everything(实时索引)
  搜索走 Everything 高速索引（毫秒级，文件新增实时可见）；
  没有 Everything 时自动回退到传统磁盘扫描模式（功能不变，稍慢）。

【开机自启】
  Everything 默认随 Windows 开机自动启动（托盘常驻，注册表 Run 项
  "MediaFinder-Everything"），这样任何时候打开网页都是秒级搜索；
  MediaFinder 网页则按需双击 exe 打开。
  想取消 Everything 开机自启: 删除注册表项
  HKCU\Software\Microsoft\Windows\CurrentVersion\Run 下的
  MediaFinder-Everything，或在配置里设 autostartEverythingOnBoot=false。

【配置文件】
  位置: %LOCALAPPDATA%\MediaFinder\MediaFinder.config.json
  常用项:
    watchPaths          监视目录列表（可在网页左侧增删）
    autoDetect          自动识别常见目录 (默认 true)
    refreshInterval     自动刷新间隔秒数 (默认 5)
    indexProvider       auto=自动选择 | everything=强制Everything | ps=强制磁盘扫描
    autoStartEverything 启动时自动拉起内置Everything (默认 true)
    stopEverythingOnExit 服务器退出时一并关闭Everything (默认 false,
                        仅关闭由MediaFinder自动拉起的实例)

【常见问题】
  - Everything 启动后搜索不到新文件? 等几秒，Everything 是实时索引，USN 日志秒级更新。
  - 想单独用 Everything 搜索? 直接运行 %LOCALAPPDATA%\MediaFinder\Everything.exe。
  - 端口被占用? 服务器启动时自动检测并提示，可用 -Port 参数指定其他端口。
  - 退出 MediaFinder: 网页左下角「退出服务器」，或运行 MediaFinder-stop.cmd。

【版权与许可】
  本程序内嵌并分发以下第三方组件：

  1. Everything (Everything.exe / Everything64.dll)
     Copyright (C) 2018 David Carpenter
     许可协议: MIT 许可（免费软件，个人与商业使用免费，允许自由复制、
     修改与分发，但分发时必须保留以下版权与许可声明）：

     Everything
       Copyright (C) 2018 David Carpenter
       Permission is hereby granted, free of charge, to any person obtaining
       a copy of this software and associated documentation files (the
       "Software"), to deal in the Software without restriction, including
       without limitation the rights to use, copy, modify, merge, publish,
       distribute, sublicense, and/or sell copies of the Software, and to
       permit persons to whom the Software is furnished to do so, subject to
       the following conditions:
       The above copyright notice and this permission notice shall be
       included in all copies or substantial portions of the Software.
       THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
       EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
       MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
       NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
       BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
       ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
       CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
       SOFTWARE.

     官方网站: https://www.voidtools.com
     Everything64.dll 来自 voidtools 官方 SDK。

  2. MediaFinder 本体由使用者自行编写，仅作为内部/个人工具使用；
     若对外分发，请自行注明出处与使用条款。

