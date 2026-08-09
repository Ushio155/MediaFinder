# MediaFinder 更新日志 / Changelog

## v1.2.1（2026-08-09）

### 新增功能 / New Features

#### ⚡ 实时更新 / Live Updates
- **搜索结果实时刷新**：Everything 模式下页面每 5 秒自动重新搜索，复制/移动/删除文件后无需手动点击，结果自动更新
  - **Live search refresh**: in Everything mode the page re-searches every 5 seconds automatically — copied, moved or deleted files appear without clicking anything
- **Everything 提权保障**：自动检测 Everything 是否以管理员身份运行，非管理员实例自动修复重启（读取 NTFS 变更日志的前提），保证索引实时性
  - **Elevation guard**: automatically detects and fixes non-admin Everything instances (required to read the NTFS change journal), keeping the index truly real-time
- **索引守护进程**：Everything 进程异常退出时自动重启，期间暂停日志同步防止误报
  - **Watchdog**: auto-restarts Everything when it crashes; log sync is paused during downtime to prevent false alarms
- **空结果保护**：Everything 查询异常返回 0 个文件时保留原索引，不覆盖不清零
  - **Empty-result protection**: keeps the previous index when Everything returns 0 files abnormally
- **建库状态检测**：Everything 正在构建索引时状态栏显示提示，日志同步自动降级
  - **Index-building detection**: shows a status hint while Everything is building its database

#### 🌐 英文 UI / English UI
- 自动识别系统语言（中文系统显示中文，其他语言显示英文）
  - Auto-detects system language (Chinese UI for zh systems, English otherwise)
- 右上角一键切换语言（与暗色模式同栏），选择自动记忆
  - One-click language toggle in the top bar (next to the theme toggle); choice is remembered
- 100+ 界面文案双语覆盖：菜单、按钮、提示、弹窗、Toast、确认框、时间格式
  - 100+ UI strings translated: menus, buttons, hints, modals, toasts, confirm dialogs, time formats
- 文件分类名翻译（如「明日方舟终末地」→ "Arknights EndField"、"鸣潮" → "Wuthering Waves"），未收录分类原样显示
  - Category names translated (e.g. 明日方舟终末地 → "Arknights EndField", 鸣潮 → "Wuthering Waves"); unknown categories pass through unchanged
- 扫描结果消息翻译（"完成: 共 N 个媒体文件" → "Done: N media files..."）
  - Scan result messages translated ("完成: 共 N 个媒体文件" → "Done: N media files...")

#### 📜 日志功能 / Activity Logs
- 实时记录媒体文件新增 / 移动 / 消失事件（Everything 模式 30 秒粒度）
  - Records add / move / delete events in real time (30s granularity in Everything mode)
- 日志管理面板：按日期查看、导出、删除单日或全部日志
  - Log management panel: view by date, export, delete single-day or all logs
- 防假事件机制：快照为空但上次有文件时跳过同步，Everything 波动不再产生误报
  - Phantom-event guard: skips sync when the snapshot is empty but previously had files, preventing false reports from Everything fluctuation

### 修复 / Bug Fixes
- 修复 Everything 非管理员运行时索引冻结（副本文件扫不到、已删文件残留）的问题
  - Fixed frozen index when Everything ran without admin rights (copies invisible, deleted files lingering)
- 修复复制文件后搜索/扫描不更新的问题
  - Fixed search/scan not updating after copying files
- 修复 Everything 重启瞬间日志误报全部文件消失的问题
  - Fixed mass phantom "removed" events when Everything restarts
- 修复启动崩溃（缺失元素映射导致整页失效）
  - Fixed startup crash (missing element mapping breaking the whole page)

### 使用提示 / Notes
- Everything 需要管理员权限读取 NTFS 变更日志：首次启动会弹出 UAC 确认，允许后即可实时追踪
  - Everything needs admin rights to read the NTFS journal: allow the UAC prompt on first launch for real-time tracking
- 按「重新扫描」仍可随时手动全量刷新索引快照
  - The Rescan button still forces a full index snapshot refresh at any time
