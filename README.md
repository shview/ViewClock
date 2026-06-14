# View Clock

> 当前阶段：不含设备管理员的基础 MVP。已实现模式管理、白名单、专注倒计时、临时解锁、提前结束、历史统计、Usage Access 前台检测和本地持久化。未设置 Device Owner，未启用 Accessibility，未使用 root。

## 当前实现状态

已实现：

- 首页与今日专注概览。
- 标准番茄钟、长专注和自定义模式。
- 模式名称、时长、临时解锁次数和独立白名单编辑。
- 可启动 App 列表、搜索、图标、名称和包名展示。
- 专注倒计时、离开白名单次数、1/3/5 分钟临时解锁。
- 提前结束二次确认，失败记录与专注历史。
- 单次历史详情、历史记录删除和模式删除。
- 模式、进行中会话和历史记录本地持久化；应用重启后可恢复。
- Flutter 原生能力诊断页面和结构化日志。
- `MethodChannel` / `EventChannel`。
- 设备信息、Launcher 可启动应用元数据及按包名读取图标。
- Usage Access 状态、设置入口和前台 App 查询。
- 可见通知对应的前台监控服务。
- `Device Owner`、`Lock Task` 和 Accessibility 只读状态查询。
- Device Admin Receiver 与 Accessibility Service 骨架。

2026-06-14 基础 MVP 实机验证：

- `flutter analyze`：无问题。
- `flutter test`：全部通过。
- Debug APK 构建和同包名覆盖安装成功，原 Usage Access 保持开启。
- 首页、默认模式、模式编辑、白名单应用加载和设置页显示正常。
- 本次冒烟测试未启动专注监控，未修改系统权限。
- 调试页已切换为主力机安全模式，不提供启动 Lock Task、打开 Accessibility 或启动监控的按钮。

2026-06-14 Bug 修复与管理能力：

- 修复专注倒计时圆环横向偏移，真机中心点与屏幕中心一致。
- 修复完全退出弹窗销毁文本控制器导致的崩溃；错误确认文本不会退出，支持输入“结束”或 `END`。
- 应用图标统一缩放为 64 px，在 Android 后台线程加载，并在原生端和 Flutter 内存中缓存，降低白名单滚动卡顿。
- 增加模式删除、单次专注详情和历史记录删除。

2026-06-14 循环、统计与备份阶段：

- 模式支持独立休息时长和 1-8 轮循环。
- 专注结束后自动进入休息，休息结束后进入下一轮；最后一轮休息结束后记录完成。
- 休息期间停止前台应用监控，可主动跳过休息。
- 记录页增加本周分钟、本月分钟和完成率。
- 支持完整 JSON 导出到剪贴板，以及从剪贴板校验导入。
- 导入会替换模式和历史，并在执行前把旧数据备份到剪贴板。

2026-06-13 实机验证：

- 设备：OnePlus PLC110，Android 15 / API 35。
- 最终应用名 `View Clock`，包名 `com.shview.viewclock`。
- Debug APK 构建、安装、启动正常。
- Channel Ping、设备信息和 Device Owner=`false` 正常。
- ColorOS 的“读取应用列表”二次授权已由用户允许。
- Usage Access 已由用户在系统设置页开启，App 内状态返回 `true`。
- 前台 App 查询正确返回 `com.shview.viewclock`。
- 前台服务可识别 `com.android.settings`，并发送前台变化和违规事件；返回 App 后再次识别 `com.shview.viewclock`，验证结束后服务已停止。
- 当前无 Device/Profile Owner，未执行 `dpm set-device-owner`。
- Accessibility 未开启，root/su 未使用。

应用列表说明：

- Manifest 已声明 `QUERY_ALL_PACKAGES` 和 `MAIN/LAUNCHER` 包可见性查询。
- ColorOS 二次授权前后，`PackageManager.getInstalledApplications()` 均只返回本 App，`installedCount=1`。这表明 ROM 或设备上的应用列表隐藏层仍限制完整安装包 API，不是 Android Manifest 权限缺失。
- `LauncherApps.getActivityList()` 与 `queryIntentActivities()` 均返回 120 个可启动 App；ADB 从系统侧能看到约 122 个 Launcher Activity，结果基本一致。
- 当前白名单选择应以合并后的 120 个可启动 App 为准。三四百个总安装包包含无桌面入口的系统服务和后台组件，不适合作为普通白名单选择项。

## 1. 结论

普通 Flutter/Android App 不能可靠地“锁住其他 App”。

- 轻度锁定：使用 `UsageStatsManager` 检测前台 App，仅提醒和记录。
- 中度锁定：使用 `UsageStatsManager` 或用户主动开启的 `AccessibilityService`，检测后拉回本 App 或显示阻止页。它仍可被关闭权限、强制停止、厂商后台策略等绕过。
- 强锁定：需要把本 App 作为 Device Policy Controller，并将设备配置为 `Device Owner`，再使用 `Lock Task Mode`。这是非 root 官方路线中最接近真正 Kiosk 的方案。
- root/su：不作为产品功能，不默认实现，不在主力机上自动执行任何命令。

因此推荐先在保留数据的前提下完成轻度/中度 Demo。强锁定验证应使用模拟器、备用机，或用户明确同意清空并重新配置的设备。主力机不应直接尝试 Device Owner。

## 2. 锁定方案对比

| 方案 | 真正阻止非白名单 App | 权限/条件 | ADB | 恢复出厂/Device Owner | 厂商依赖 | 长期自用 | 主要风险 | 推荐 |
|---|---|---|---|---|---|---|---|---|
| A. 普通 App + 前台服务 + 通知 | 否 | 通知、前台服务；后台执行受系统限制 | 否 | 否 | 高 | 仅辅助 | 耗电、服务被杀、只能提醒 | 低 |
| B. `UsageStatsManager` | 否，只能事后检测 | `PACKAGE_USAGE_STATS`，用户在设置中手动授权 | 否 | 否 | 中 | 适合轻度模式 | 检测有延迟，后台可能被限制 | 高 |
| C. `AccessibilityService` | 不能绝对阻止，可较快拉回 | 用户手动开启无障碍服务 | 否 | 否 | 中到高 | 适合自用中度模式 | 高敏感权限、可被关闭、窗口事件差异 | 中 |
| D. Device Owner + Lock Task | 是，限官方允许的范围 | DPC、Device Owner、Lock Task allowlist | 设置时通常需要 ADB 或设备配置流程 | 通常要求全新/无账号设备；失败时可能只能恢复出厂 | 中 | 专用设备适合，主力机不理想 | 配置和退出成本高，策略残留风险 | 强锁定首选 |
| E. 自定义 Launcher | 不能单独阻止通知、设置、直接 Intent 等路径 | 用户设置默认桌面；强约束仍需 Device Owner | 否 | 否 | 高 | 可作为入口层 | 易切换或绕过，厂商桌面行为不同 | 中低 |
| F. root/su | 技术上可做到更强控制 | root，且高度依赖 ROM/工具链 | 常需要 | 不一定，但事故可能要求刷机/恢复 | 极高 | 不推荐 | 数据丢失、启动失败、安全边界破坏 | 仅隔离实验 |

补充说明：

- 前台服务只是提高任务存活性，不提供“禁止启动其他 App”的系统权限。
- Accessibility 路线必须显式解释用途并由用户主动开启，不能隐藏、诱导或阻止关闭。
- 未被 Device Owner allowlist 的 App 调用 `startLockTask()`，通常进入的是用户可退出的 Screen Pinning，而不是真正的 Lock Task。
- Lock Task 可隐藏 Home/Overview、限制通知并阻止非 allowlist App，但仍需为电话、紧急呼叫和必要系统能力设计安全出口。

## 3. 推荐路线

### 阶段 1：无设备状态修改

完成 Flutter 与 Kotlin 通信、应用列表、权限状态、Usage Access 引导和单次前台 App 查询。只读取状态，不启动监控服务。

### 阶段 2：轻度/中度验证

在用户手动授权后启动透明可见的前台服务：

- 轻度模式只提醒、记录违规。
- 中度模式检测非白名单 App 后返回本 App。
- Accessibility 仅作为单独的可选实验，不与默认路径绑定。

### 阶段 3：隔离环境验证强锁定

在模拟器或可清空的备用机上，将 App 设置为 Device Owner，验证：

- `DevicePolicyManager.isDeviceOwnerApp()`
- `setLockTaskPackages()`
- `isLockTaskPermitted()`
- `startLockTask()` / `stopLockTask()`
- Home、Recent、通知栏、重启后的实际表现

### 阶段 4：完整 MVP

技术验证通过后，再加入模式管理、计时、白名单、配额、统计、备份和防冲动退出流程。

## 4. MVP 功能边界

首个可用版本包含：

- Android-only Flutter UI。
- 多个专注模式与自定义时长。
- 轻度、 中度、强锁定三档能力说明与可用性检测。
- 已安装可启动 App 的名称、包名、图标和搜索。
- 每个模式独立白名单。
- 专注倒计时、临时解锁、临时允许单 App、提前结束。
- 本地历史、基础统计、JSON 导入导出。
- 权限状态、异常降级、调试日志和明确的安全退出。

首个版本不包含：

- 云账号、云同步、远程控制或商业 MDM。
- 静默 root、系统分区修改、删除系统 App。
- 保证无法绕过的中度锁定。
- 未经确认自动设置 Device Owner、默认 Launcher 或 Accessibility。
- 任何阻断紧急呼叫的策略。

数据建议使用 `Drift/SQLite`，因为记录、配额、按日周月聚合和迁移需求明显；少量 UI 偏好可使用 `SharedPreferences`。状态管理建议使用 Riverpod，便于拆分权限、计时、会话、锁定与统计状态并做测试。

## 5. 第一阶段验证 Demo

### 验证页面

每项能力有独立按钮、结果卡片和时间戳日志：

1. Flutter -> Kotlin `ping`
2. 获取设备/API 基本信息
3. 获取可启动 App 元数据列表，并按需获取图标
4. 检查 Usage Access
5. 打开 Usage Access 设置
6. 查询当前前台 App
7. 检查 Accessibility 状态
8. 打开 Accessibility 设置
9. 检查 Device Owner 状态
10. 检查 Lock Task 是否允许
11. 开始/停止 Lock Task
12. 启动/停止前台监控服务

### Channel API

```text
focus_lock/native
  ping()
  getDeviceInfo()
  getInstalledApps()
  getAppIcon(packageName)
  isUsageAccessGranted()
  openUsageAccessSettings()
  getCurrentForegroundApp()
  isDeviceOwner()
  setLockTaskPackages(packages)
  isLockTaskPermitted(packageName)
  startLockTaskMode()
  stopLockTaskMode()
  isAccessibilityEnabled()
  openAccessibilitySettings()
  startFocusMonitor(whitelist)
  stopFocusMonitor()

focus_lock/events
  permissionChanged
  foregroundAppChanged
  violationDetected
  monitorStateChanged
  lockTaskStateChanged
  nativeError
```

`setLockTaskPackages()` 必须在调用前检查 Device Owner；不满足条件时只返回结构化错误，不尝试提权或调用 su。

## 6. 计划文件结构

```text
lib/
  main.dart
  app/
    app.dart
    theme.dart
  core/
    logging/app_log.dart
    platform/native_focus_bridge.dart
    platform/native_focus_events.dart
  features/
    native_demo/
      domain/native_capability.dart
      presentation/native_demo_page.dart
      presentation/native_demo_controller.dart
    whitelist/
      domain/installed_app.dart
      presentation/app_picker_page.dart
  shared/widgets/

android/app/src/main/kotlin/com/shview/viewclock/
  MainActivity.kt
  bridge/NativeBridge.kt
  applist/AppListProvider.kt
  usage/UsageAccessHelper.kt
  foreground/FocusMonitorService.kt
  locktask/LockTaskController.kt
  deviceowner/DeviceOwnerReceiver.kt
  accessibility/AccessibilityFocusService.kt
  logging/NativeLog.kt

android/app/src/main/res/xml/
  device_admin_receiver.xml
  accessibility_service_config.xml
```

最终 Android 包名已确定为 `com.shview.viewclock`。Device Owner 建立后不能随意改包名，否则原管理组件会失配。

## 7. ADB 与 Device Owner 验证计划

### 低风险，只读

以下命令不会修改设备管理状态：

```powershell
adb devices -l
adb shell getprop ro.build.version.release
adb shell getprop ro.build.version.sdk
adb shell getprop ro.product.manufacturer
adb shell getprop ro.product.model
adb shell dpm list-owners
```

当前备用机可指定序列号运行：

```powershell
adb -s 3B6F6KE8QDS34B2G devices
flutter run -d 3B6F6KE8QDS34B2G
```

构建和覆盖安装：

```powershell
flutter build apk --debug
adb -s 3B6F6KE8QDS34B2G install -r build\app\outputs\flutter-apk\app-debug.apk
```

`flutter run` 会在手机上安装/更新 debug APK，并启动 App。它不会自动清空手机，但可能覆盖同包名的旧 debug 安装及其 App 私有数据。执行前仍需确认设备和包名。

### 中风险，必须先告知

- 安装或卸载 APK。
- 清除本 App 数据：`adb shell pm clear <package>`。
- 打开 Usage Access、Accessibility、通知等设置并授权。
- 设为默认 Launcher。
- 启动前台监控服务或中度拉回逻辑。

这些操作可能改变日常使用体验，但通常可在系统设置中关闭或撤销。

### 高风险，当前禁止执行

计划中的 Device Owner 命令形式如下，仅用于说明：

```powershell
adb shell dpm set-device-owner <package>/<receiver>
```

风险：

- 通常只能在新配置、无账号且无现有 owner 的设备上成功。
- 可能要求恢复出厂后再配置，恢复出厂会删除手机本地数据。
- 建立 Device Owner 后，App 可施加设备级策略；错误策略可能影响 Home、设置、通知、卸载与正常使用。
- 退出 Device Owner 不是所有系统都能无损完成。Android 官方把程序化清除 owner 视为测试用途，并提示部分策略可能残留；最可靠的恢复手段可能仍是恢复出厂。

因此在主力机上必须先完成备份验证、确认账号/支付/认证器迁移方式，并由用户逐条确认后才允许执行。

### root/su：禁止默认执行

不会运行 `adb root`、`adb shell su`、`pm disable-user`、删除系统包、修改 `/system`、刷写镜像、改 SELinux 或防火墙规则。若未来做 root 实验，必须使用备用机并单独给出命令影响、恢复路径和失败后的刷机方案。

## 8. 风险与回滚

| 操作 | 风险等级 | 回滚 |
|---|---|---|
| 查询设备信息、查询 owner | 低 | 无需回滚 |
| 安装 debug APK | 中低 | 卸载 APK；注意 App 私有数据随卸载删除 |
| Usage Access | 中 | 设置 -> 特殊应用权限 -> 使用情况访问权限中关闭 |
| Accessibility | 中高 | 设置 -> 无障碍中关闭服务；若拉回影响操作，先用 ADB 停止本 App |
| 默认 Launcher | 中高 | 系统设置中清除默认应用并恢复原桌面 |
| Lock Task（非 owner） | 中 | 按系统屏幕固定退出方式，或由启动它的 Activity 调用 `stopLockTask()` |
| Device Owner + Lock Task | 高 | 先由 App 停止 Lock Task、清空 allowlist 和策略；最终可能需要恢复出厂 |
| root/su 系统修改 | 极高 | 依命令而定，可能只能还原完整镜像或刷机 |

代码必须遵守 fail-open：检测、权限或服务异常时，退出锁定并提示原因，不能把设备留在没有明确恢复入口的状态。

当前备用机的恢复操作：

```powershell
# 停止前台监控服务
adb -s 3B6F6KE8QDS34B2G shell am force-stop com.shview.viewclock

# 卸载 Demo；会删除该 Demo 自己的数据，不影响其他 App
adb -s 3B6F6KE8QDS34B2G uninstall com.shview.viewclock
```

Usage Access 需在手机的“设置 -> 使用情况访问权限”中关闭。这台 ROM 会阻止普通 ADB shell 直接修改该 AppOp，因此不能依赖 `appops set` 回滚。

## 9. 需要用户提供的信息

在连接主力机前，请提供：

1. 手机品牌、具体型号。
2. Android 大版本、系统名称和系统版本号。
3. 是否必须完整保留现有数据；默认按“必须保留”处理。
4. 是否存在工作资料、企业管理、家长控制或已有 Device/Profile Owner。
5. 是否安装银行、支付、通行密钥、双因素认证器等恢复成本高的应用。
6. 是否可以正常执行 `adb devices` 并授权此电脑。
7. 是否允许安装 debug APK。
8. 是否愿意手动开启 Usage Access。
9. 是否愿意在中度验证时手动开启 Accessibility。
10. 是否有模拟器或可恢复出厂的备用机用于 Device Owner。
11. 是否允许未来把本 App 设为默认 Launcher；默认不允许。
12. 希望采用的稳定应用名和 Android 包名。

不需要提供账号密码、验证码、支付信息或个人文件。

## 10. 下一步最小代码任务

下一阶段任务：

1. 增加真正的白名单选择页面并异步加载 App 图标。
2. 增加 Android 13+ 通知权限的 Flutter 侧请求流程。
3. 验证 Screen Pinning 与可退出流程，不设置 Device Owner。
4. 在确认最终包名后，制定隔离环境 Device Owner 验证步骤。
5. 增加中度模式阻止页；默认仅提醒，不自动拉回。

## 11. 当前环境

- Flutter/Dart 约束：Dart `^3.11.4`
- Android 原生语言：Kotlin
- Java/Kotlin target：17
- 当前 application id：`com.shview.viewclock`
- 项目当前未初始化 Git 仓库

## 12. 官方参考

- [Android Lock task mode](https://developer.android.com/work/dpc/dedicated-devices/lock-task-mode)
- [Build a device policy controller](https://developer.android.com/work/dpc/build-dpc)
- [Package visibility filtering](https://developer.android.com/training/package-visibility)
- [UsageStatsManager](https://developer.android.com/reference/android/app/usage/UsageStatsManager)
- [DevicePolicyManager](https://developer.android.com/reference/android/app/admin/DevicePolicyManager)
