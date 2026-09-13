# M3E Todo

用 Flutter 编写的 **Material 3 Expressive** 待办应用，界面遵循 [Material 3 Expressive](https://m3.material.io/) 设计语言。支持 **Android** 与 **Windows** 两个正式目标，另带 **web** 目标用于快速预览。

- Flutter 3.47.3 (stable) / Dart 3.13.3
- 第三方依赖仅 `flutter_riverpod` 与 `web`（后者只在 web 目标下被引用）；
  `flutter_localizations` 是 SDK 自带包，用来中文化日期选择器这类由 Material 绘制的
  平台界面，它会传递引入 `intl`——这是本项目唯一一个来自 pub 托管的依赖
- 静态分析零告警，164 个测试全部通过
- 已在真机（Android 13 / API 33，720×1612）上运行验证，见「真机验证结果」
- 三个平台共用同一套 `domain` / `presentation` 代码，差异全部收敛在存储与原生外壳

---

## 快速开始

```powershell
flutter pub get
flutter run -d <device>     # Android 设备或模拟器
flutter run -d windows      # Windows 桌面，需要 Visual Studio
flutter run -d edge         # 浏览器预览，不需要 Visual Studio
flutter test                # 不需要任何平台工具链
flutter analyze
```

### 构建 Windows 版的前置条件

`flutter build windows` / `flutter run -d windows` 需要 **Visual Studio 2022**，并勾选
「使用 C++ 的桌面开发」工作负载（含 MSVC v143、Windows 10/11 SDK、CMake 与 Ninja）。
Flutter 通过 `vswhere` 查找该工具链，缺失时会直接报：

```
Unable to find suitable Visual Studio toolchain.
```

这是环境依赖，不是项目问题：`flutter analyze` 与 `flutter test` 均可在没有 Visual Studio 的机器上完整运行。

**没有 Visual Studio 时**，可以用 web 目标预览界面（`flutter run -d edge`，或 `-d chrome`）。
web 与 Windows 共享同一套 `domain` / `presentation` 代码，只有存储实现不同（见
[数据存储](#数据存储)），所以预览能真实反映 Windows 上的界面与交互，而不是另做一个 demo。
web 目标下按 `F5` 或点浏览器的刷新即可，dev server 由 `flutter run` 提供。

> 本项目**刻意不引入任何原生插件**（包括 `shared_preferences`、`path_provider`）。
> 插件会让 Flutter 在 `windows/flutter/ephemeral/.plugin_symlinks` 创建符号链接，
> 而这在 Windows 上需要开启「开发者模式」或管理员权限。存储改用纯 `dart:io`、
> Android 的目录改用自带 MethodChannel 后，只需安装 Visual Studio 这一项前置条件即可构建。

---

## 运行到 Android

### 前置条件

| 需要 | 说明 |
| --- | --- |
| Android SDK | 有 `platform-tools` + `build-tools` 即可起步 |
| JDK 17+ | Android Studio 自带的 JBR 即可；命令行构建需设 `JAVA_HOME` |
| 设备或模拟器 | `flutter devices` 确认可见 |

AGP 会**按需自动补装**缺失的 SDK 组件。实测本机原先只有 `build-tools 36.0.0` 和
`platform android-37.0`，构建时 AGP 自行下载并安装了 **NDK 28.2.13676358**、
**Android SDK Platform 36** 与 **CMake 3.22.1**。

但 **`cmdline-tools` 是必需的，前提是你要构建 release AAB**。原因在
`flutter_tools` 的 `android/gradle.dart`：

```kotlin
final String? sdkManagerPath = androidSdk.sdkManagerPath;
if (sdkManagerPath != null &&
    androidSdk.cmdlineToolsAvailable &&      // ← 缺 cmdline-tools 时为 false
    androidSdk.licensesAvailable) {
  properties.add('-P$_kSdkManagerPathProperty=$sdkManagerPath');
}
```

`-Pflutter.sdkManagerPath` 传不下去，Gradle 就无法剥离原生库的调试符号，
Flutter 在 `_isAabStrippedOfDebugSymbols` 检查失败后直接 `throwToolExit`：

```
Release app bundle failed to strip debug symbols from native libraries.
Please run flutter doctor and ensure that the Android toolchain does not report any issues.
```

实测后果：`flutter build apk --release` **正常成功**（它不做这项检查），
`flutter build appbundle --release` **退出码 1**，尽管 AAB 文件仍然会生成——只是带着调试符号。

安装方式：Android Studio → `Settings → Languages & Frameworks → Android SDK → SDK Tools` →
勾选 **Android SDK Command-line Tools**。

> GitHub Actions 的 runner 镜像自带 `cmdline-tools`，所以 CI 上不受影响；
> 工作流仍然对 AAB 这一步加了 `continue-on-error`，避免它在某些镜像上失败时把可用的
> APK 一起拖掉。

### 需要的环境变量

命令行构建需要两个变量（本机已持久化到**用户级**变量，见下）：

```powershell
$env:ANDROID_HOME = "C:\Users\<你>\AppData\Local\Android\Sdk"
$env:JAVA_HOME    = "<Android Studio 安装目录>\jbr"
```

> 这里用 Android Studio 自带的 JBR 作 `JAVA_HOME`，好处是不用另装 JDK，代价是
> Android Studio 若被移动、重装或升级，这个路径会失效。真要长期稳定，建议单独装一个
> JDK 21 LTS 并指向它。
>
> 另外，**Android Studio 内部构建用的是它自己的 Gradle JDK 设置**
> （`Settings → Build, Execution, Deployment → Build Tools → Gradle → Gradle JDK`），
> 与 `JAVA_HOME` 相互独立——IDE 里能构建不代表命令行也能，反之亦然。

若 `flutter doctor` 报 `Unable to locate Android SDK`，但 SDK 确实存在，通常只是环境变量没设：

```powershell
flutter config --android-sdk "C:\Users\<你>\AppData\Local\Android\Sdk"
```

### 依赖仓库走镜像（本项目已配置，且在本机是必需的）

`android/settings.gradle.kts` 与 `android/build.gradle.kts` 里的仓库顺序是
**阿里云镜像在前、官方源在后**：

```kotlin
maven { url = uri("https://maven.aliyun.com/repository/google") }
maven { url = uri("https://maven.aliyun.com/repository/public") }
maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
google()
mavenCentral()
gradlePluginPortal()
```

这**不是性能优化**。本机实测 Google 的 Maven 仓库根本无法提供构件：

```
https://dl.google.com/dl/android/maven2/com/android/tools/build/gradle/9.1.0/gradle-9.1.0.pom
  → 4.0s，0 字节，连接失败
https://maven.aliyun.com/repository/google/...（同一构件）
  → 0.2s，200，9034 字节 ✓
```

而 Android Gradle Plugin **只发布在 Google 仓库**，所以没有镜像时依赖解析根本无法开始。
官方源保留在镜像之后作为回退，因此这套配置并非「中国专用」——换个网络环境依然能构建。

`android/gradle/wrapper/gradle-wrapper.properties` 同理把 `distributionUrl` 指向了
`mirrors.cloud.tencent.com`（官方源在本机只有 262 KB/s，且 Gradle 自带下载器一度完全停滞，
45 秒零字节；腾讯镜像 1.2 MB/s），并把 `-all` 换成 `-bin` 分发包以省掉一半体积——
`-all` 多出来的只是 Gradle 自身的源码与文档。想换回官方源，文件里注释了原始 URL。

> **为什么会出现这种情况**：本机在 IE/系统设置里配置了本地代理 `127.0.0.1:7890`
> （`ProxyEnable = 1`），但 `curl`、以及默认配置下的 Gradle（JVM 的
> `java.net.useSystemProxies` 为 `false`）都不会自动使用它，于是走直连——
> 而直连访问 `dl.google.com` 的构件路径会返回 0 字节。
> 如果哪天其他命令行工具也遇到 Google 域名下载失败，给它们设上
> `HTTPS_PROXY=http://127.0.0.1:7890` 即可；Gradle 也可以改用
> `~/.gradle/gradle.properties` 里的 `systemProp.https.proxyHost` / `proxyPort`。
> 不过既然镜像已经稳定可用，通常不必这么做。

### 本机两个环境变量写错了：缺 `https://`

本机（不是在项目里）把两个 Flutter 环境变量设成了**没有协议头**的值：

```
FLUTTER_STORAGE_BASE_URL = storage.flutter-io.cn     ← 机器级，HKLM
PUB_HOSTED_URL           = pub.flutter-io.cn         ← 机器级，HKLM
```

后果不一样，这也是它容易被误判成项目问题的原因：

| 变量 | 行为 | 现象 |
| --- | --- | --- |
| `FLUTTER_STORAGE_BASE_URL` | Flutter **工具**会自己补 `https://`，Gradle 插件不会 | `flutter pub get`、引擎产物下载一切正常，只有 Android 构建挂掉 |
| `PUB_HOSTED_URL` | pub 直接拒绝 | `Invalid PUB_HOSTED_URL="pub.flutter-io.cn": url scheme must be https:// or http://` |

Gradle 插件的原话是 `"$hostedRepository/${engineRealm}download.flutter.io"`（见
`packages/flutter_tools/gradle/.../FlutterPlugin.kt`），于是这个「相对 URL」被当成项目内
路径解析，报出的是这样一条**看起来完全不像环境问题**的错误：

```
Could not find io.flutter:arm64_v8a_debug:1.0.0-<engine hash>.
  Searched in the following locations:
    ...
    file:/D:/360/work/m3e_todo/android/app/storage.flutter-io.cn/download.flutter.io/...
```

**项目的处理**：`android/build.gradle.kts` 检测到该变量不是以 `http` 开头时，自己补上
`https://` 并把正确的仓库加进去，同时打印一条 `logger.warn` 说明原因。变量正常时这段代码
什么都不做（CI 上未设置该变量，也不受影响）。可以用一个 init script 验证仓库确实被加上了：

```
PROBE :app maven3 https://storage.flutter-io.cn/download.flutter.io      ← 补上的
PROBE :app maven4 file:/D:/360/work/m3e_todo/android/app/storage.flutter-io.cn/download.flutter.io   ← 插件算错的
```

**`PUB_HOSTED_URL` 项目无法代劳**（pub 是命令行工具，不认识项目内的任何配置）。**已修**：这两个变量在
机器级（HKLM）里都缺协议头，而当前会话没有管理员权限改不了 HKLM，因此改写**用户级**（HKCU）——
用户级会覆盖机器级，新开的进程都会拿到正确值：

```powershell
setx PUB_HOSTED_URL "https://pub.flutter-io.cn"
setx FLUTTER_STORAGE_BASE_URL "https://storage.flutter-io.cn"
```

验证方式是用 `Start-Process -UseNewEnvironment` 起一个只继承注册表环境的进程，读到的确是
`https://pub.flutter-io.cn` / `https://storage.flutter-io.cn`；而**当前这个已经运行的会话仍持有旧值**
（进程环境在启动时就固定了），所以本仓库的构建说明里仍然示范临时覆盖的写法。
要连 HKLM 一起修，用管理员权限执行 `setx ... /M`。

### 构建

```powershell
flutter build apk --debug          # 产物 build\app\outputs\flutter-apk\app-debug.apk
flutter build apk --release        # 需先在 android/app/build.gradle.kts 配置签名
```

### 已做的 Android 适配

**1. 存储目录必须问宿主要。** Android 给每个应用一个私有目录，其路径**无法**从环境变量推导。
`dart:io` 在 Android 上看到的 `Platform.environment` 只有寥寥几个系统变量，既没有 `APPDATA`
也没有 `HOME`，原逻辑会一路回落到 `Directory.current`——那是文件系统根目录，不可写。
因此 `MainActivity.kt` 里加了一个 MethodChannel：

```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.m3e.m3e_todo/storage")
    .setMethodCallHandler { call, result ->
        when (call.method) {
            "getDataDirectory" -> result.success(filesDir.absolutePath)
            else -> result.notImplemented()
        }
    }
```

Dart 侧由 `prepareDocumentStoreFactory()` 在首帧之前 `await` 它，结果注入 provider。
用自带 channel 而不是 `path_provider`，是为了保住「零插件、Windows 上不需要开发者模式」这条约束——
channel 写在应用自己的 shell 里，约二十行，不引入任何依赖。取不到时（纯 Dart VM、单元测试）
会回落到环境变量路径而不是崩溃。

**2. 启动画面与主题同色。** `values/colors.xml` 与 `values-night/colors.xml` 里的颜色取自
Flutter 主题的实际计算结果（`AppColorSchemes.*(AppColorSeed.violet).surface`），
空色种子为浅色 `#FFF7FD` / 深色 `#161219`。`LaunchTheme` 与 `NormalTheme` 都用它作为
`windowBackground`，所以从点击图标到首帧之间不会闪白或闪黑，面板是直接以正确底色出现的。
深色模式由 Android 自动选用 `values-night`，因此应用可以保持 `ThemeMode.system`。

> 同时**删掉了模板自带的 `res/drawable-v21/launch_background.xml`**。它用的是
> `?android:colorBackground`（平台默认色），而 `drawable-v21` 的优先级高于 `drawable`，
> 在本项目 `minSdk = 24` 的前提下它会永远生效，导致上面的改动完全看不到效果。

**3. 清单与外观。** `AndroidManifest.xml` 的 `android:label` 改为 `M3E Todo`。
`MainActivity` 继承 `FlutterActivity`，未改动返回键行为——Flutter 3.47 已默认处理 edge-to-edge，
页面留白由 `Scaffold` 依据 `MediaQuery` 内边距自动处理。

**4. 提醒、选择器与录音都在同一个 channel 里。** `dev.m3e.m3e_todo/platform` 覆盖了
Dart 无法自己回答的事情（清单见 `AppPlatform`）：通知权限、精确闹钟授权、排期/取消闹钟、
铃声设置与试听、系统文件选择器、系统铃声选择器、麦克风录音、把附件交给别的应用打开。
全部是框架 API，唯一新增的 Gradle 依赖是 `androidx.core`（`FileProvider` 需要）。

| 组件 | 作用 | 为什么必须存在 |
| --- | --- | --- |
| `DueAlarmReceiver` | 闹钟触发时弹通知 | 到期时应用进程通常已经死了，只有 manifest 里声明的接收器能醒过来 |
| `BootReceiver` + `AlarmStore` | 重启后恢复未到期的闹钟 | `AlarmManager` 的排期不跨重启；`SharedPreferences` 里存的那份是唯一记录 |
| `PlatformHost` | 通知渠道 + 铃声版本 | 渠道一旦创建，**铃声不可修改**；换铃声只能提升版本号、换新的渠道 id |
| `FileProvider` | 把私有目录里的附件交给相册/播放器 | 不暴露存储权限，也不把附件目录变成公开目录 |

**5. 通知的小图标是单色矢量。** `res/drawable/ic_notification.xml`：状态栏会把小图标按
alpha 通道裁成单色再上色，用启动图标（彩色位图）会得到一坨纯白。

**6. 中文平台界面。** `AppStrings` 只管本应用自己的文案，日期选择器这类由 Material 绘制的
界面要靠 `flutter_localizations`。加之前实测：编辑器里点「选择日期」弹出的是
`Select date / Sun, Sep 13 / Cancel / OK`，而且是**周日开头**的一周——中文应用里出现英文日期
选择器，且周起始日和应用自己的月视图（周一起始）不一致。加 `GlobalMaterialLocalizations`
与 `locale: zh` 之后实测变为 `选择日期 / 2026年9月13日星期日 / 取消 / 确定`，并且**周一开头**，
与日历页的网格一致。

### 验证结果

| 项目 | 结果 |
| --- | --- |
| `flutter analyze` | No issues found |
| `flutter test` | 164 个测试全部通过 |
| `flutter build apk --debug` | 成功，产物 183.98 MB |
| `flutter build apk --release` | 成功，产物 52.11 MB |
| `flutter build apk --profile --dart-define=M3E_FRAME_LOG=true` | 成功，用于性能测量（见「性能」一节） |
| `flutter build web --debug` | 成功——这同时证明条件导入在 web 上仍正确选中 `localStorage` 实现，若选错会因引用 `dart:io` 而编译失败 |

APK 经 `aapt2 dump badging` 核实：

```
package: name='dev.m3e.m3e_todo' versionCode='1' versionName='0.1.0'
compileSdkVersion='36'  targetSdkVersion:'36'
application-label:'M3E Todo'          ← 含 zh-CN 在内的全部语言
launchable-activity: name='dev.m3e.m3e_todo.MainActivity'
native-code: 'arm64-v8a' 'armeabi-v7a' 'x86_64'
```

资源表同样核实过：`color/m3_surface` 与 `drawable/launch_background` 均在包内，
`LaunchTheme` 的 `windowBackground` 指向 `@drawable/launch_background`、
`NormalTheme` 指向 `@color/m3_surface`——即启动画面配色确实生效，而非停在模板默认值。

### 真机验证结果

设备：realme PHJ110，**Android 13 / API 33**，720×1612，USB 调试。
下面每一条都是在设备上真实观察到的事实，不是「编译通过」的推论。
（界面文字取自 `uiautomator dump` 的无障碍语义树——本项目的语义标签是完整的，
因此可以逐屏核对文案，而不必依赖截图。）

| 验证项 | 观察到的事实 |
| --- | --- |
| 冷启动 | 启动画面直接以主题底色出现，无闪白；首屏为待办列表 |
| 导航 | 四个目的地 `全部 / 进行中 / 已完成 / 日历`（`第 1 个标签，共 4 个`） |
| 日历页 | 标题切为「日历回顾」；月视图 `2026年9月`，含上个月/下个月/今天/跳转到指定日期；点某一天只列出那一天的待办；搜索命中后带日期标签，点击跳回该日 |
| **月视图对齐** | `2026-09-01`（周二）落在「二」列，`2026-09-13`（周日，今天）落在「日」列——见下方「一个只有真机+断言才能抓到的 bug」 |
| 设置面板 | 一个面板内含「到期提醒」（提醒方式、铃声、试听、选择铃声、发送测试通知）、「外观」（主题模式、6 种主题色）、「使用说明」 |
| 通知权限 | Android 13 首次启动弹出授权对话框，文案为中文；授权后设置页不再显示授权提示条 |
| 到期提醒链路 | 在编辑器里设了 `2026-09-20` 的到期日并创建后，`dumpsys alarm` 出现 `origWhen=2026-09-20 09:00:00.000` 的 `RTC_WAKEUP`，接收器为 `dev.m3e.m3e_todo/.DueAlarmReceiver` |
| **提醒跨重启恢复（应用侧）** | 用 `run-as` 直接写入一条 `2026-09-25` 到期的待办（不动 UI），冷启动后 `dumpsys alarm` 立刻出现 `origWhen=2026-09-25 09:00:00.000` 的排期 |
| 测试通知 | 点「发送测试通知」后 5 秒，`dumpsys notification` 出现 `pkg=dev.m3e.m3e_todo id=999001 channel=due_ring_v2`、标题「发送测试通知」、图标为 `RESOURCE id=0x7f060006`（即 `ic_notification`） |
| **铃声在启动时恢复** | 把 `settings.json` 的 `ringtoneUri` 写成 `content://settings/system/alarm_alert` 后冷启动：渠道变为 `due_ring_v3`，`mSound=content://settings/system/alarm_alert` |
| **渠道不再每次启动重建** | 紧接着再冷启动一次：仍是 `due_ring_v3`，没有出现 `v4`（修复前每次启动都会重建，见下） |
| 通知渠道 | `due_silent`（importance 3、无声、不震动）与 `due_ring_v*`（importance 4、有铃声、震动）同时存在 |
| **麦克风录音** | 清空授权后点「开始录音」→ 弹出系统麦克风授权对话框（`允许"M3E Todo"使用麦克风?`）→ 授权后自动重试并开始录音（`正在录音… 00:05`）→「完成」后 `files/attachments/` 出现 `voice-<uuid>.m4a`，95467 字节，文件头为 `ftyp`/`mp42`（真实可播放的 M4A），编辑器出现该语音附件 |
| **文件选择器返回值** | 「图片」→ 系统 `documentsui` 只列出图片 → 选中 `m3e_pick_test.png` 后：原生把内容流式复制进 `files/attachments/<uuid>.png`（46993 字节，与源文件一致），Dart 收到 `path`/`name`/`mime`，落盘为 `{"type":"image","name":"m3e_pick_test.png","mime":"image/png","path":"/data/user/0/.../attachments/<uuid>.png"}` |
| **铃声选择器返回值** | 「选择铃声」→ 系统 `RingtoneSettingsActivity` → 选「涟漪」→ 返回 `content://media/internal/audio/media/260?title=notification_005&canonical=1`，写入 `settings.json` 的 `ringtoneUri`，渠道随之变为 `due_ring_v5` 且 `mSound` 正是该 URI（v4 被标记删除） |
| **应用背景：选择 + 裁剪 + 落盘** | 设置 →「应用背景」→ 选择背景图 → 系统选择器（只列图片）→ 裁剪页（比例：原图/屏幕/1:1/4:3/16:9/9:16）→ 选 1:1 后完成：`settings.json` 变为 `{"version":3,…,"backgroundImage":"…/image-ca199ad5….png","backgroundDim":0.9}` |
| **裁剪结果逐像素正确** | 用一张**四色分区**的 1600×900 测试图（左上红/右上绿/左下蓝/右下黄）裁成 1:1，导出 900×900，四角采样分别为 `255,0,0` / `0,255,0` / `0,0,255` / `255,255,0`——取的区域与朝向都对。900 未超过 1440 上限，故不放大 |
| **应用背景真的画出来了** | 截图后按区域统计平均色：左下 `R=89 G=86 B=253`、右下 `R=255 G=252 B=89`——正是四分图下半部的蓝/黄，叠加 35% 主题色遮罩后的数值（蓝 255 + 35% 近白 = 89） |
| **遮罩浓度可调** | 同一区域在遮罩 35% 时左右色差为 164/166，拉到 90% 后降到 24/27（图片几乎褪进主题色），且值已写入 `backgroundDim` |
| **卡片背景：选择 + 裁剪** | 编辑器 →「背景图片」→ 选择图片 → 裁剪页（默认 16:9）→ 选 1:1 完成 → 编辑器出现预览与「裁剪 / 移除背景图」按钮 → 保存后 `todos.json` 的 `backgroundImage` 指向裁剪产物 |
| **卡片背景真的画出来了** | 截图按卡片左右两侧取平均色：左 `R=220 G=180 B=210`（偏红）、右 `R=218 G=248 B=189`（偏绿），对应裁剪图的红/绿两块，并按要求淡化 |
| **重新裁剪已有背景** | 「裁剪」→ 改选 4:3 → 完成：输出 900×675（比例 1.333，与公式一致），`backgroundImage` 指向新文件，**旧文件被自动删除**（附件目录里旧的那张已不在） |
| 数据落盘 | `files/M3ETodo/todos.json` 内容为 `{"version": 2, ...}`，`settings.json` 为 `{"version": 3, ...}` |
| 日志 | 上述全部操作期间 logcat 无 `FATAL` / `AndroidRuntime` / `E/flutter`（修复前附件选择会抛异常，见下） |
| 冷启动耗时 | profile 版实测 `am start -W` TotalTime **697–787ms**（预热后，45 条待办、45 条排期）。分阶段：进程起到 Dart `main()` 约 420ms（引擎初始化），`main()` 到 `runApp` 约 151ms（其中存储通道 137ms、读设置 13ms），其余为首帧构建——也就是说 **700ms 里有 420ms 是引擎，应用自己约占 150ms** |
| 内存 | 60 条各带独立背景图的待办、滚动到底之后：PSS **197MB**、图形内存 **68MB**（改动前用 Flutter 默认图片缓存是 297MB / 167MB，见「性能」一节） |

#### 真机上抓到、单靠截图抓不到的三个问题

**1. 月视图整体错位一列。** 第一版 `_MonthGrid` 把单元格下标当成「已经是第几天」传给
`_cell()`（缺一个 `+ 1`），于是每个日期都画在真实星期的右边一列。这个 bug 在截图里
完全看不出来——数字本身是对的，只是列错了；点日期后显示的待办也是对的，因为标签与
数据始终一致。它是在 `uiautomator` dump 里对比「日期单元格的 x 坐标」与「星期表头的 x 坐标」
时暴露的，随后被两条断言固定下来（2026 年 3 月是周日开头、9 月是周二开头）：

```dart
expect(tester.getCenter(find.text('1')).dx, tester.getCenter(find.text('二')).dx);
```

**2. 附件选择在 Dart 侧从未成功过。** `AppPlatform.pickAttachment` 写的是

```dart
final Map<Object, Object?>? result = await _invoke<Map<Object, Object?>>('pickAttachment', kind);
```

而 `MethodChannel.invokeMethod<T>` 会把解码结果 `as T`。标准编解码器解出来的 map 类型是
`Map<Object?, Object?>`，`Object?` 比 `Object` **更宽**，所以这是一次**向下转型**，每次都在
Dart 侧抛出：

```
Uncaught error: type '_Map<Object?, Object?>' is not a subtype of type 'Map<Object, Object?>?' in type cast
#2  AppPlatform.pickAttachment (package:m3e_todo/core/platform/app_platform.dart:128)
#3  pickAndCreateAttachment (…/attachment_actions.dart:32)
```

原生侧完全正常：复制文件、返回 `path`/`name`/`mime` 都没问题——报错发生在 Dart 解包那一刻，
于是「文件副本留在 `files/attachments/` 里、编辑器里却始终没有附件」。这个 bug 对用户表现为
「点图片没反应」，靠读代码几乎不可能看出来，只有把真机的异常日志抓出来才会现形
（TypeError 不是 `PlatformException`，`_invoke` 的 catch 拦不住它，所以它以「未捕获异步错误」
的形式出现）。修法是把类型参数写成编解码器真正的类型 `Map<Object?, Object?>`。

**3. 每次启动都会重建响铃渠道。** 原生侧原本在 `configureFlutterEngine` 里调用
`ensureChannels(this, null)`——传入「系统默认铃声」。而在启动流程稍后，Dart 会再用
`settings.json` 里保存的铃声调一次 `setRingtone`。于是每次启动都是「默认 → 自定义」两次变更，
每次都要删掉旧渠道再建新渠道；渠道在 Android 上承载着用户自己的设置（重要性、震动、
锁屏可见性），重建就等于把这些设置重置。真机上留下的 `due_ring_v1`/`v2`/`v3` 里前两个
都带 `mDeleted=true`，正是这样被删掉的；改成「渠道一律按已保存的铃声创建、只在铃声**真的**
变化时才提升版本」之后，连续两次启动只留下一个未删除的 `v3`。

#### 顺带修掉的一个资源泄漏（以及我第一版修错了）

上面第 2 条的排查过程中，我在设备的 `files/attachments/` 里数出了 4 个孤儿文件——
它们正是那几次「复制成功但 Dart 抛异常」留下的。把那个 bug 修掉之后，孤儿文件的来源只剩一个：
**选好附件后又取消编辑器**。附件在「选中的那一刻」就被原生复制进私有目录了，而取消编辑
不会有任何东西引用它，于是它会一直留在那里。

处理方式是让编辑器记住「本次会话新建了哪些文件」，`dispose()` 时若没保存就删掉；
在编辑器里点「删除」的附件也立刻删（那是本次新建的、且已无人引用）。

> 第一版写错了，而且**真机验证把错误抓了出来**：当时为了保护「原本就存在」的文件，
> 我构造了一个 keep 集合，而它恰好包含了用户刚加进编辑器的那张图——于是取消后一个文件都没删
> （实测：选择后 1 个文件，取消后仍是 1 个）。`_newFiles` 本来就只装本次新建的文件，
> 根本不需要 keep 集合。改成直接删之后复测：取消 → 文件数回落，保存 → 文件保留且被
> `todos.json` 引用。

> 已知边界：**编辑已有待办时移除原有的附件再保存**，那个文件不会被删除。
> 它只影响从旧待办里摘下来的附件，不影响新选的文件。

#### 背景图功能引出的同类泄漏：选择器的原图副本

同一个模式在背景图上又出现了一次，而且是**真机像素校验时顺手发现的**：选择器会把用户选中的
原图复制进私有目录，裁剪器再写出一份裁剪产物——应用只引用后者，于是那份原图（实测 10 KB 的
1600×900）就一直留着。修法是 `pickAndCropImage` 无论裁剪成功还是取消，都删掉选择器那份副本；
随后真机复测确认附件目录里只剩裁剪产物。

> 顺带说明为什么这类问题集中在这一块：**「复制文件」发生在用户点选的那一刻，而「引用这个文件」
> 发生在保存的那一刻**，两者之间隔着取消、替换、重裁等一堆出口。每个出口都要么删除文件、
> 要么把它登记为「保存后再删」（`_obsoleteFiles`），这一点已经写进对应代码的注释里。

### 重启恢复（BootReceiver）在本机遇到的是 ROM 限制，不是代码问题

真机实测：重启前 `dumpsys alarm` 有 80 条我们的排期，重启后 **0 条**。查启动日志可以看到，
系统**确实**把广播投递到了我们应用，却被 ColorOS 的自启动管控拦下：

```
OplusAppStartupManager: *Do not want to launch app dev.m3e.m3e_todo/10268
  for broadcast Intent { act=android.intent.action.BOOT_COMPLETED } callUid:1000 callPid:1627
```

`callUid:1000` 是系统自己，说明清单里的接收器被发现、被选中了；被拒的是「为广播启动这个进程」。
可核实的三件事都成立：`dumpsys package` 里 `dev.m3e.m3e_todo/.BootReceiver` 带着
`Action: "android.intent.action.BOOT_COMPLETED"` 被正确注册；`shared_prefs/due_alarms.xml`
里有 **93 条**待恢复记录（每条含标题与触发毫秒，如 `任务 147 → 2026-09-21 09:00`）；
`AlarmStore.rescheduleAll()` 就是遍历它并重新 `schedule()` 的那段代码。

`BOOT_COMPLETED` 是**受保护广播**，shell（uid 2000）无法伪造，所以没法用手动投递绕过：

```
java.lang.SecurityException: Permission Denial: not allowed to send broadcast
  android.intent.action.BOOT_COMPLETED from pid=…, uid=2000
```

ROM 也没把自启动白名单暴露成可写入的设置项（`settings list secure|system` 里没有对应键），
因此这一条**在本机无法端到端确认**，只能确认到「系统已投递、被 ROM 拒绝启动」。
在没有这类自启动管控的 AOSP/原生系统上，同一份代码会照常执行。

对用户的实际影响是可控的：**打开应用本身就会重新推导并排期所有提醒**（应用启动时的
`ReminderCoordinator.sync()`，上表已用 `run-as` 落盘 + 冷启动验证过），所以即使
BootReceiver 被 ROM 拦住，用户下次打开应用后提醒也会恢复。真要让它开机即恢复，
需要在系统「自启动/后台运行」里允许本应用——这是 ROM 侧设置，应用代码无法代劳。

> 另外提醒：**不要**用 `dumpsys alarm` 里的 window 字段判断 `canScheduleExactAlarms()`
> 的结果——实测即便应用自己报告已获得该授权，这条精确闹钟仍显示 `window=+1h0m0s0ms`，
> 两个分支在日志里无法区分。设置页显示的是那个 API 的真实返回值。

---

## 目录结构

按 **feature-first + 三层架构** 组织：`core` 放跨功能基础设施，`features` 下每个功能自带
`domain / data / presentation` 三层。

```
lib/
├── main.dart                     # 仅调用 bootstrap()
├── app/
│   ├── bootstrap.dart            # 组合根：平台 I/O + Provider 覆盖 + 全局错误处理
│   ├── app.dart                  # MaterialApp，装配主题、ThemeMode 与中文本地化
│   └── app_shell.dart            # 应用外壳：导航（含日历）、AppBar、快捷键、FAB、提醒接线
├── core/
│   ├── theme/                    # M3E 设计系统（见下）
│   ├── storage/                  # DocumentStore 存储接缝（原生 JSON 文件 / web localStorage）
│   ├── diagnostics/frame_log.dart# 编译期开关的帧日志，用来量卡顿（见「性能」）
│   ├── platform/app_platform.dart# 原生 MethodChannel 的类型化封装（提醒/选择器/录音/铃声）
│   ├── constants/app_strings.dart# 全部用户可见文案集中于此
│   └── utils/                    # 日历、日期格式化、Clock、ID 生成
└── features/
    ├── todos/
    │   ├── domain/               # 纯 Dart，无 Flutter 依赖
    │   │   ├── entities/         # Todo、TodoSubtask、TodoAttachment、TodoFilter、TodoStats …
    │   │   ├── repositories/     # TodoRepository 抽象接口
    │   │   └── usecases/         # 每个用户意图一个用例
    │   ├── data/                 # JSON 映射、数据源、仓储实现
    │   └── presentation/         # provider / controller / page / widgets
    ├── calendar/presentation/    # 日历回顾页（月网格 + 某日详情 + 历史搜索）
    ├── media/                    # 图片裁剪：domain 放纯几何，presentation 放裁剪页
    ├── notifications/            # 提醒协调器与纯函数排期规则
    └── settings/                 # 同一分层，负责主题、主题色、提醒方式、铃声与应用背景
```

### 分层要点

| 层 | 职责 | 关键约束 |
| --- | --- | --- |
| `domain` | 实体与业务规则 | **不 import Flutter**，可作纯 Dart 单测 |
| `data` | 序列化与持久化 | 只实现 `domain` 定义的接口 |
| `presentation` | 状态与 UI | 不直接碰文件系统 |

几条贯穿全局的设计决定：

- **`domain` 保持 Flutter-free。** `Todo`、`TodoFilter` 等不引用任何 Flutter 类型，
  因此领域测试不启动 widget binding，跑得极快。
- **组合根只有一处。** `bootstrap()` 在第一帧之前完成目录解析与设置读取，
  再通过 `ProviderScope` 覆盖注入。结果是：widget 树里没有任何文件系统调用，
  首帧主题就是正确的（不会闪一下默认配色），而测试只需覆盖两个 provider
  就能把整个应用指向临时目录与固定时钟。
- **不可变 + 值相等。** `Todo`、`TodoFilter`、`AppSettings` 都实现了
  `==` / `hashCode`，Riverpod 借此判断是否真的需要重建。
- **意图命名的方法取代泛型 `copyWith`。** `Todo` 提供 `completeAt` / `reopen` /
  `edit` 等方法。可空字段配 `copyWith` 无法区分「保持不变」与「置为 null」，
  显式方法从根上消除这个歧义。
  > 这条规则被违反过一次，代价是一个真 bug：`reopen()` 走的私有 `_copy()` 里写的是
  > `completedAt ?? this.completedAt`，于是「重新打开」永远清不掉完成时间——`null`
  > 在这里表示「不修改」。现在换成两个只做一件事的私有构造（`_withCompletion` /
  > `_withSubtasks`），每个字段无条件赋值，由 `todo_test.dart` 断言固定住。
- **和平台耦合的逻辑，把纯的那一半切出来。** `ReminderCoordinator` 本身依赖
  Android 通道，在测试里观察不到；但它的**排期规则**（`desiredReminders()`）是纯函数，
  于是唯一值得测的逻辑可以在没有设备的情况下被测透。切分点选在「能不能观察到」，
  而不是按层次大小切。
- **派生状态不存储。** 可见列表由 `visibleTodosProvider` 从「集合 + 过滤条件」实时算出，
  统计值由 `todoStatsProvider` 算出，不存在会与事实脱节的第二份副本。
  日历的每日计数同理：每次 build 从集合现算一次（`_DayCounts.from`），
  42 个格子只读预计算好的 map，不会各自重扫一遍列表。

---

## M3E 设计语言的落地方式

Flutter 3.47.3 的 Material 库**并未包含** Expressive 新增的组件类
（`ButtonGroup`、`FloatingToolbar`、`SplitButton`、`MotionScheme`、`ShapeStyle` 均不存在）。
因此本项目不是「调用现成的 M3E 组件」，而是用现有基元 + 自建令牌把 Expressive
的**颜色、形状、动效、字体**四套规范实现出来。

### 1. 颜色：真正的 Expressive 变体

```dart
ColorScheme.fromSeed(
  seedColor: seed,
  dynamicSchemeVariant: DynamicSchemeVariant.expressive,
)
```

这是 SDK 里唯一原生的 M3E 能力。`SchemeExpressive` 会把主色调相旋转 240°
（默认的 `tonalSpot` 保持种子色相不变），从而得到 Expressive 更具对比与活力的配色。
`test/core/theme/app_theme_test.dart` 专门断言了这一点，防止有人误删该参数。
色板生成开销较大，`AppColorSchemes` 内做了 `(seed, brightness)` 记忆化。

### 2. 动效：物理弹簧，而非贝塞尔曲线

Expressive 用**弹簧参数**（刚度 + 阻尼比）描述动效。`core/theme/spring_curve.dart`
实现了 `SpringCurve`，直接驱动 `SpringSimulation` 得到阻尼谐振子的阶跃响应：

- **spatial**（位移）族阻尼比 0.9，略微欠阻尼，落位时有轻微回弹；
- **effects**（颜色/透明度/进度）族阻尼比 1.0，临界阻尼，**绝不超调**——
  这正是 `FadeTransition`、`Opacity`、`LinearProgressIndicator` 能安全使用它的原因
  （它们都断言取值必须落在 `[0, 1]`）。

由于弹簧是渐近收敛的，曲线把响应压缩进由 `settlingTime` 推导出的固定窗口，
保证 `transform(0) == 0`、`transform(1) == 1`。每个令牌的时长因此是**算出来的**
而非硬编码，动画恰好在弹簧静止时结束。`app_page_transitions.dart` 用它实现了页面转场。

### 3. 形状与字体

`AppShapes` 给出完整 M3E 圆角阶（含 Expressive 新增的 `largeIncreased` /
`extraLargeIncreased` 中间档）；`AppTypography` 只调整**字重与字距**——标题族加重，
正文与标签保持常规，形成 Expressive 的排版层级感，字号仍沿用平台排版以兼容缩放。

### 4. 组件主题

`app_component_themes.dart` 集中覆盖 24 类组件主题（卡片、对话框、底部面板、
SnackBar、输入框、分段按钮、各类按钮、导航栏/导航轨、菜单、滚动条……）。
全部从 `ColorScheme` 派生，**改一个种子色即可整站换肤**，无需改动任何其他文件。

---

## 功能

新建 / 编辑待办（标题、备注、优先级、截止日期）· **子备忘录**（可勾选的清单步骤）·
**附件**（图片 / 视频 / 文档 / 语音备忘）· **每条待办自己的色块与背景图** ·
勾选完成 · 删除并支持**撤销**（恢复到原位置）· 搜索（标题 + 备注）· 状态筛选 ·
四种排序（手动 / 最近创建 / 最快到期 / 优先级）· 长按拖动排序 · 一键清除已完成（带确认）·
进度统计头 · **日历回顾页**（月视图 + 按日查看 + 跨全部历史搜索 + 跳转到指定日期）·
**到期提醒**（响铃 / 仅消息、自定义铃声、试听、测试通知）· **应用级背景图**（可换、可移除、
遮罩浓度可调）· **内置裁剪器**（缩放 / 拖动 / 六种比例，卡片背景与应用背景共用）·
整合设置面板（提醒 / 外观 / 背景 / 使用说明）· 浅色/深色/跟随系统 · 6 种主题色 ·
响应式外壳（宽窗导航轨 / 窄窗导航栏）· 桌面快捷键 `Ctrl+N` 新建、`Ctrl+F` 聚焦搜索 ·
编辑器适配软键盘（`viewInsets` 顶起底部面板）。

### 背景图与裁剪

两处背景，同一套机制：**应用背景**（设置面板，铺满整个窗口）与**卡片背景**（编辑器里每条待办
自己的那张图）。两者都是「选择 → 裁剪 → 落到私有目录」，都可在之后重新裁剪或移除。

裁剪器是自己写的（`lib/features/media/`），没有引入 `image_cropper` 之类的插件——本项目的
硬约束就是零插件（见上文「零插件」的由来），而插件还会带来新的原生构建要求。

```
features/media/
├── domain/crop_geometry.dart      # 纯数学：cover 适配、平移夹取、可见源矩形、输出尺寸
└── presentation/image_crop_page.dart  # 手势 + 遮罩 + 比例选择 + 编码落盘
```

三个刻意的决定：

- **不用 `InteractiveViewer`。** 裁剪必须知道「当前窗口对应源图的哪一块」，而
  `InteractiveViewer` 的变换语义（子节点居中、边界夹取规则）是实现细节，把它当成几何来源
  意味着公式里混进一层猜不透的偏移。改为自己处理 `onScaleUpdate`：`scale` 与 `offset`
  就是全部状态，公式只有三行，且能脱离 widget 单测。
- **几何与 UI 分离。** 缩放系数差一点点，裁出来的图只是「构图略微不对」——截图评审绝对看不出来。
  所以最容易错的那部分被切成纯函数：`test/features/media/domain/crop_geometry_test.dart`
  用 12 条断言钉住 cover 适配、居中、夹取、缩放与窗口换形。
- **只解码一次，预览与结果同源。** 图片经 `ImageDescriptor` 读头部拿到尺寸（不解像素），
  再按上限 2048 解码一次；遮罩里画的就是这张 `ui.Image`，导出时也从它裁——
  预览与结果不可能不一致。输出最长边上限 1440，且**只缩不放**（源矩形小于上限时保持原尺寸，
  避免把 900px 的裁剪放大成 1440px 的假细节）。

应用背景的渲染在 `lib/app/app_background.dart`，三层：主题底色（打底，保证首帧与图片丢失时
都不会透出窗口）、照片（`cover`）、用户可调的遮罩。有了背景图时，`Scaffold` 的背景改为
`Colors.transparent`，AppBar 与导航栏变为 0.86 不透明的表面色——完全透明会让栏上的文字在
任意照片上不可读。

### 到期提醒是怎么工作的

`ReminderCoordinator` 在待办集合变化时，把「应该存在的提醒」和「上次已排期的提醒」
做差集，只对变化的部分调用原生：新增的排期、改过的替换、完成或删除的取消。
通知 id 由待办 id 推导，因此重启后仍然能覆盖同一条通知而不是堆积第二份。

**排期规则**抽成了一个纯函数 `desiredReminders()`：

| 规则 | 原因 |
| --- | --- |
| 到期日当天 **09:00** 触发 | 截止日期只到天，提醒需要一个人为约定的小时 |
| 已完成、无到期日的待办不排期 | 没有可提醒的东西 |
| 触发时刻已过则不排期 | 立刻补发一条通知比沉默更糟；列表本身已经标出「已逾期」 |

抽成纯函数不是为了好看：`ReminderCoordinator` 的其余部分依赖 Android 通道，
在测试里无法观察；而这段「谁该被提醒、什么时候提醒」的规则是唯一值得测的逻辑，
纯函数让它能在没有设备的情况下被完整覆盖（`test/features/notifications/`）。

原生的部分做三件事：`AlarmManager` 排期、`DueAlarmReceiver` 在进程已死时照样弹出通知、
`AlarmStore` 把待排期写进 `SharedPreferences` 让 `BootReceiver` 在重启后恢复。
**通知渠道的铃声不可修改**，所以选择铃声时会提升一个版本号、换一个新的渠道 id——
这是 Android 上唯一可行的做法，代价是渠道会被重建。

## 性能：先量，再改（以及那些量完发现不用改的）

### 用什么东西量

`dumpsys gfxinfo` 对 Flutter 应用**完全无效**：Flutter 在自己的 raster 线程上往 SurfaceView 里画，
Android 的每应用图形统计因此报告 `Total frames rendered: 0`（真机实测）。
`dumpsys SurfaceFlinger --latency` 能看到帧真的上屏了没有，但说不清时间花在 Dart 构建还是光栅化。

所以项目自带一个编译期开关的帧日志（`lib/core/diagnostics/frame_log.dart`）：

```powershell
flutter build apk --profile --dart-define=M3E_FRAME_LOG=true
adb install -r build\app\outputs\flutter-apk\app-profile.apk
adb logcat -c; # 然后操作应用
adb logcat -d | Select-String M3E_FRAME
```

它用 `FrameTiming` 报告每帧的 `build` / `raster` / `vsync` 拆分，并每隔一段给出
`p50/p90/p99/max`。开关是 `const bool.fromEnvironment`，**默认关闭时整段代码会被编译器折叠掉**，
正常构建里不存在这个回调。

### 量出来的结论

真机（Android 13，720×1612）用 **400 条**待办（含备注、子任务、到期日、背景图、图片附件）压测：

| 场景 | 结果 |
| --- | --- |
| 列表滚动（6 次长滑） | **0 掉帧**，p50 5.9–6.2ms，p90 8.5ms |
| 勾选完成 | 0 掉帧，p50 10.5ms |
| 日历页打开 + 连点 4 次「下个月」 | 优化前 1 帧掉帧（build 17.8ms、总 33.6ms）；**优化后 0 掉帧**（max 28.5ms） |
| 搜索框输入 8 个字符 | 第 1 次按键 3 帧掉帧（build 25ms / raster 39ms），**第 2、3 次连续输入 0 掉帧** |

两个关键判断都是量出来的，不是猜的：

1. **重复输入就正常了**：同一会话里连做三轮输入，只有第一轮掉帧。所以那不是「每次按键都慢」，
   而是一次性的预热（首次建立文本输入连接、首次字形/着色器预热）。
2. **一次按键的真实成本约 1.5ms**：在 provider 与卡片构建处加临时探针后测得，
   400 条待办的筛选+排序 **634µs**，一次按键只重建 **5 张**可见卡片、每张 71–398µs。
   所以 25ms 的尖峰不是我的代码在做 O(n) 的工作——**据此否掉了「都怪列表太大」这条思路，
   也否掉了给搜索加防抖的方案**（防抖能减少重建次数，但重建本来就不贵，加了只是增加复杂度）。

同理，冷启动的 1.5s 也拆开量过：进程起到 Dart `main()` 约 420ms（引擎初始化），
`main()` 到 `runApp` 约 151ms。第一次看到的「存储通道 923ms」是**装完包首次启动**的一次性开销，
第二次起只有 137ms —— 如果当时就照着第一个数字去改架构（比如不等存储就先 `runApp`），
改的是一个不存在的问题。

### 应用背景图引入的滚动掉帧（已修）

加了全屏背景图之后复测，滚动掉了 2 帧，而帧日志把责任分得很清楚：

```
janky #1/2  build=271us  raster=17738us  total=44260us
janky #2/3  build=261us  raster=6342us   vsync=2089us
```

**构建只用了 0.27ms，光栅却用了 17.7ms** —— 这个比例就是判据：问题不在 Dart，而在「每帧都在重新
光栅化一张全屏图片」。原因是背景图与列表共处同一图层，列表一动，滤镜缩放的整屏图片就得重画。

两处修改（`lib/app/app_background.dart`）：

- 给背景与遮罩套一层 `RepaintBoundary`，让这块底图只光栅化一次，滚动时只是合成；
- 背景按**实际显示尺寸**解码（`cacheWidth = 逻辑宽度 × 设备像素比`，上限 2048），
  而不是把裁剪出来的 1440px 原样塞进纹理。

复测：**0 掉帧**，p50 5.6ms、p90 9.0ms、max 从 44.3ms 降到 28.8ms。

### 新页面的第一次上屏：量清、但**没有**为此加机制

设置面板的第一次打开会掉一帧。我原本的归因是错的，这里如实记下来：

| 假设 | 实测 | 结论 |
| --- | --- | --- |
| 六个主题色预览里有五个首次生成调色板，累计 ~40ms | 每个调色板只花 **~0.9ms**；十二个全部生成共 12ms | **假设被推翻** |
| 我新加的「应用背景」分区（缩略图 + 滑块）太贵 | 去掉整个背景分区后，首开仍是 **28.6ms 构建** | 只值 ~2ms，不是原因 |
| 那就是这个页面自己的问题 | 日历页首开 25ms、编辑器首开 28ms、设置面板首开 29–39ms | **是「任何从未绘制过的整屏子树第一次上屏」的系统性成本** |

同一进程里第二次打开设置面板：**0 掉帧**（p50 11.1ms、max 15.7ms）。所以它是**一次性的**，
不是每次交互都付。

我为此写过一版「空闲时分帧预热调色板」的机制，并且**把它删掉了**——前提已被数据推翻，
留着就是没有实测收益的维护成本（`AppColorSchemes.buildAll()` 保留为诊断入口，
对应的假设由 `app_theme_test.dart` 里那条「第二次生成是免费的」断言守住）。

剩下的这 39ms 属于引擎侧首次使用成本（字形/着色器/布局路径）。要真正消掉它只有两条路，
都需要新的实测才能决定，所以这一轮没有动手：

1. **启动时把各页面离屏预渲染一遍**：把首次成本从「用户点击之后」挪到「启动之后用户还在看列表」。
   代价是启动阶段多一次约 30ms×N 的开销，本质是**搬运**而不是消除。
2. **接受它**：它是每个进程仅一次、约两帧的抖动，且发生在一个本身就带 250ms 入场动画的
   面板上，通常淹没在动画里。

### 内存：把图片缓存的上限收回来（实测省下约 100MB）

Flutter 的图片缓存默认是 **1000 项 / 100MB**，那是按「相册类应用」定的。这个应用同时在屏的
图片最多几张（应用背景、卡片背景、附件缩略图），但在「每条待办各有一张背景图」的列表里滚到底
之后，缓存会把所有滚过去的图都留着。真机 A/B（60 条各带独立 1440×1440 背景图，滚动到底后
`dumpsys meminfo`）：

| 图片缓存上限 | TOTAL PSS | TOTAL RSS | GL mtrack（图形） |
| --- | --- | --- | --- |
| Flutter 默认（1000 项 / 100MB） | 297.0MB | 431.5MB | 166.6MB |
| 本项目（120 项 / 32MB） | **197.4MB** | **329.4MB** | **67.9MB** |

**少占约 100MB**，其中绝大部分是早已滚出屏幕的行所占的纹理。上限是「天花板」而不是预分配：
图片少时根本碰不到它，代价只可能是回滚时重新解码一张。

### 开启速度：量错了两次才量对

**先说结论**：冷启动 **697–787ms**（`am start -W`，预热后）。700ms 里 420ms 是引擎初始化，
应用自己约占 150ms（存储通道 137ms + 读设置 13ms）。

**再说过程**，因为这里连错两次，值得写下来：

1. 先把「启动时要为每条提醒做一次通道调用」改成**批量一次调用**（45 条排期 45 次 IPC → 1 次），
   测出来 1443ms → 711ms，看起来是巨大的胜利。
2. 但把旧实现改回去再测，**又是 1467ms**；把新实现换回来，**也是 1526ms**。
   于是做了公平对照：两个版本各自 `install` 后先预热几次再测——**680–721ms vs 697–787ms，
   两者没有差别**。
3. 真正的原因是 **`adb install` 会重置 ART 的编译画像**：刚装完的包前几次启动约 1.5s，
   几次之后稳定在 0.7s。我先前那次「1443–1530ms」的冷启动结论，其实就是装包后的假象。

所以：**批量调用保留**（45 次平台通道往返降到 1 次，是实实在在更少的活，只是它并不改变这个
指标），但**不声称它加速了启动**。同时也说明为什么每次 A/B 都必须先预热——这是本轮踩到的第二个
「不预热就下结论」的坑（第一个是设置面板掉帧的归因）。

### 点击反馈

- 勾选待办、勾选子选项触发 `HapticFeedback.selectionClick()`：复选框是个很小的目标，
  震动是「这一下点到了」的确认。真机上用 `dumpsys vibrator_manager` 核实过，确实是
  `Prebaked{effect=TEXTURE_TICK, strength=MEDIUM}`、`Usage=TOUCH`、`opPkg=dev.m3e.m3e_todo`。
- 删除走 `HapticFeedback.mediumImpact()`：这是唯一不可撤销的操作，给更重的一下。
- 长按拖动排序时的抬起反馈加强：缩放从 2% 提到 3%，并加了一层随进度增长的阴影，
  让「被拎起来」这件事在没有拖动把手的情况下看得出来。

### 实际改了什么

- **图片缓存上限**（见上，实测约 100MB）。
- **应用背景图**：`RepaintBoundary` + 按显示尺寸解码（实测 2 帧掉帧 → 0）。
- **提醒排期批量下发**：新增 `scheduleAlarms` / `cancelAlarms` 两个通道方法，
  45 次 IPC 合并成 1 次（不改变启动耗时，见上）。
- **日历月网格**：把每天的决定（是否真实日期、是否今天、是否选中、当天有几条）一次性算成
  `List<_Cell?>`，而不是在 42 个格子里各自 `Theme.of` 两次、各自构造 2–3 个 `DateTime`；
  每日计数改用整数键 `20260913`（原来用 `DateTime` 当键，建表时每条待办要分配对象、每次查表也是）。
  某日详情从「两趟扫描」改为「一趟、按整数键比较」。
- **卡片背景图不再用 `Opacity`**：不透明度分组会为每张卡片申请离屏图层再合成（`saveLayer`），
  列表每次移动都要重来；换成一层半透明色的 `ColoredBox` 遮罩，视觉效果相同，
  但只是多一次普通绘制，没有图层。
- **新增的两处图片预览都限制了 `cacheWidth`**（设置面板 56dp 缩略图按 160px 解码、
  编辑器 96dp 预览按 320px 解码），不再为小图解码 1440px。
- **删掉历史遗留的死代码**：`AppMotion` 里那套已被弹簧实现取代的经典曲线与时长常量、
  9 个没人引用的 `AppStrings`、`AppDateFormatter.numeric`。
  > **没有**删的是 `AppShapes` 的完整圆角阶（`largeIncreased` / `extraLargeIncreased` 等）
  > 与 `AppMotion` 的六个弹簧令牌：它们之所以「未被引用」是因为那是**设计规范的完整刻度**，
  > 中间档的意义正是让嵌套表面可以逐级过渡。未使用 ≠ 冗余，删了反而会让刻度和文档对不上。
- **没有改**的地方也列在这里：列表的 `RepaintBoundary`、卡片图片的 `cacheWidth`、
  编辑器 `viewInsets` 已在更早一轮完成，本轮测量确认它们有效（滚动 0 掉帧）。

## 持续集成与发布

`.github/workflows/release.yml` 在**推送 `v*` 标签**或**手动触发**时，自动构建三个平台并
创建 GitHub Release。

```
prepare（推导版本）
   ├── android（ubuntu-latest）→ APK + AAB
   ├── windows（windows-latest）→ zip
   └── web    （ubuntu-latest）→ zip
        └── release：汇总产物 + SHA256SUMS.txt，创建或更新 Release
```

产物命名统一为 `m3e-todo-<版本>-<平台>.<扩展名>`，例如 `m3e-todo-0.1.0-android.apk`。

### 版本号从哪来

`versionName` 取自标签（`v0.1.0` → `0.1.0`），`versionCode` 取 `github.run_number`。
用运行序号而不是写死数字，是为了让版本号每次发布都**单调递增**——Play 会拒绝版本号不增的包。
工作流在构建前把结果写回 `pubspec.yaml`，这个改动只存在于 CI 工作区，不会提交。

### 签名

release 密钥库通过仓库 secrets 提供，缺省时自动降级：

| Secret | 用途 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 密钥库文件的 base64（`base64 -w0 release.jks`） |
| `ANDROID_STORE_PASSWORD` | 密钥库口令 |
| `ANDROID_KEY_ALIAS` | 密钥别名 |
| `ANDROID_KEY_PASSWORD` | 密钥口令 |

**没有配置任何 secret 也能跑通**：`android/app/build.gradle.kts` 检测到 `android/key.properties`
不存在时退回 debug 签名，产出的 APK 可正常安装，只是不能上架 Play。这样 fork 和 PR
不会因为拿不到密钥而红。

GitHub 不允许在 `if` 条件里直接引用 secrets，所以它们先经过 job 级 `env` 中转，再用
`if: env.ANDROID_KEYSTORE_BASE64 != ''` 判断。

### 本地与 CI 的差异

两处刻意的分歧，都写在对应文件里：

1. **依赖仓库**。`android/settings.gradle.kts` 与 `build.gradle.kts` 默认把阿里云镜像放在官方源
   之前（本机直连 Google Maven 取不到构件，见上文）。CI 设置 `M3E_USE_MIRRORS=false` 跳过镜像，
   因为 GitHub 的 runner 直连官方仓库更快。开关走环境变量而非 Gradle 属性，是因为
   `pluginManagement` 块在脚本其余部分之前求值，顶层声明的变量在那个作用域里不可见。
2. **Gradle 分发源**。`gradle-wrapper.properties` 指向腾讯镜像以适配国内网络，
   工作流在装 `setup-gradle` **之前**把它改回官方源——顺序很重要，`setup-gradle`
   会按 wrapper 里的 URL 计算缓存键。

此外 `build.gradle.kts` 里还有一段**只在本机环境变量写错时才生效**的补丁
（见上文「本机两个环境变量写错了」）。它判断条件用的是变量自身的值，因此 CI 上未设置该变量时
完全不进入分支，不需要额外开关。

### 需要注意

- **Flutter 版本钉在 `3.47.3`**（工作流顶部的 `FLUTTER_VERSION`），与本地保持一致。
  如果这个版本在 GitHub 上取不到，改成 `stable` 或某个已发布的具体版本即可，这是唯一要改的地方。
- Windows 构建在 `windows-latest` 上完成——runner 预装了带 C++ 桌面工作负载的
  Visual Studio，正好补上本地缺的那一环。
- **工作流已经真正跑通过一次**：`v0.1.0` 标签（指向初始提交）触发了 run #1，
  结论 `success`，产出的 Release 里挂着 5 个文件——`m3e-todo-0.1.0-android.apk`（49.37MB）、
  `-android.aab`（48.25MB）、`-windows-x64.zip`（11.59MB）、`-web.zip`（13.39MB）
  与 `SHA256SUMS.txt`。
  > 这条更正过一次：本来写的是「工作流尚未真正跑过」，依据是只查了**分支**没查**标签**——
  > 而 `v0.1.0` 早就推上去并触发过发布了。顺带说明，**本机无法验证的 Windows 目标，
  > CI 已经证明能构建**（windows zip 就在产物里）。

---

## 数据存储

存储被抽象成 `DocumentStore` 接口（只有 `read` / `write` / `delete` 三个粗粒度方法，
因为本应用中所有调用方都是整体替换文档，而不是局部打补丁——这正是实现原子替换的前提）。
具体实现由**条件导入**在编译期选定：

| 目标 | 实现 | 落点 |
| --- | --- | --- |
| Android / iOS | `JsonFileStore` | 应用私有 `filesDir`，经 MethodChannel 取得 |
| Windows / 其他桌面 | `JsonFileStore` | `%APPDATA%\M3ETodo\*.json` |
| Web | `LocalStorageDocumentStore` | 浏览器 `localStorage`（带 `m3e_todo.` 前缀） |

因此 `dart:io` 在 web 上不会被引用，`package:web` 在原生上也不会。
仓储、数据源、用例与 UI 全都只认 `DocumentStore`，不知道自己在哪个平台上跑。
两个实现遵循同一份契约：**内容损坏时不抛异常**，而是丢弃并返回 `null`。

具体落点由 `prepareDocumentStoreFactory()` 在首帧之前解析一次并注入 provider。
它必须是异步的：Android 的目录得问宿主要，而这件事只可能发生在启动阶段。

原生的文件实现采用**原子替换**：写入先落到 `.tmp` 再 rename——rename 在 NTFS 与 POSIX
上都是原子的，因此崩溃或断电绝不会留下半截文件。

写入还被**串行化**（内部 future 链）。所有写入共用同一个 `.tmp` 路径，若允许并发，
在 Windows 上后一个 rename 会撞上共享冲突（`errno 32`）或临时文件已被移走的
`PathNotFoundException`，最终文件甚至可能停留在**旧值**上。由于设置写入是
fire-and-forget，并发是常态而非边界情况，所以这里由 `JsonFileStore` 统一保证
「先入先出、后写胜出」；单次写入失败也不会污染后续写入。

- 位置：`%APPDATA%\M3ETodo\`（`todos.json`、`settings.json`）
- 兜底顺序：`APPDATA` → `LOCALAPPDATA` → `XDG_DATA_HOME` → `HOME` → `USERPROFILE` → 当前目录
- 文档带 `version` 字段（`todos.json` 为 `{ "version": 2, "todos": [...] }`；`settings.json` 为 3，
  因为应用背景是第 3 版加的），便于将来迁移；真机上落盘的两个文件都已核对过版本号
- 枚举按**名字**而不是序号存（`"reminderMode": "ring"`），因此重排枚举声明不会悄悄改变
  既有文件的含义
- **单条记录损坏不会拖垮整个列表**：解析失败的记录被跳过，其余正常加载；
  整个文件损坏则重命名为 `*.corrupt-<时间戳>` 隔离，应用从空列表启动而非每次崩溃
- 附件由原生侧复制进 `filesDir/attachments/`，`todos.json` 里存的是绝对路径——
  因此**附件不会随备份/换机迁移**，这是当前实现的已知边界

## 测试

```
test/
├── core/
│   ├── theme/           # 弹簧曲线物理性质、主题装配（含 Expressive 变体断言）
│   └── storage/         # 原子写、并发写串行化、失败恢复、按需建目录
├── features/
│   ├── todos/
│   │   ├── domain/      # 实体规则、过滤排序、全部用例（含 off-by-one 与空写断言）
│   │   ├── data/        # JSON 往返、容错、真实临时文件读写
│   │   └── presentation/# widget 测试：空态、渲染、勾选、搜索、筛选、新建、删除+撤销
│   ├── calendar/
│   │   └── presentation/# 月网格、某日详情、跨月导航、搜索跳转、日期选择器，
│   │                     # 以及「1 号必须落在它真实的星期列下」的对齐断言
│   ├── media/
│   │   └── domain/      # 裁剪几何：cover 适配、平移夹取、可见源矩形、输出尺寸与上限
│   ├── notifications/   # 纯函数排期规则（哪天该响、响不响、过期不补发）
│   └── settings/
│       └── presentation/# 整合面板的分区与提示条、外观/背景交互、设置持久化与旧版兼容
└── support/             # FakeTodoRepository、样例数据、测试用 app 构造器
```

共 164 个用例。测试覆盖不到的接线（原生通道、真实闹钟、真机权限、系统选择器、裁剪的实际像素）
由「真机验证结果」一节列出的实测事实承担——两侧刻意不重叠：测试保证逻辑，真机保证接线与像素。
这一轮的真机验证正好抓到三个测试抓不到的问题（月网格错位、附件选择转型失败、
麦克风权限没有申请入口），其中**附件选择那个是靠真机日志才现形的**；后来背景图又复现了同一类
「复制了却没引用」的泄漏，也是靠真机的文件列表抓到的。

> **注意 `testWidgets` 的一个陷阱**：widget 测试体运行在计时器被伪造的 zone 里，
> 在那里发起的 `dart:io` 操作其完成回调永远不会被投递，`await` 它会直接卡死测试
> （`runAsync` 也救不了，因为 future 是在伪造 zone 中创建的）。
> 因此凡是涉及真实文件读写的用例都写成普通 `test()` + `ProviderContainer`，
> 见 `settings_controller_test.dart`；widget 测试只验证 UI 表现。

> **另一个陷阱（真机验证时踩到）**：`tester.tap` 只按坐标点击，而底部面板在软键盘收起
> 前后位置会变；测试里因此用 `tester.ensureVisible` + `pumpAndSettle` 再点
> （见 `appearance_sheet_test.dart` 的 `tapInSheet`），不要直接用固定坐标。

## 后续扩展

- **换存储后端**：实现 `TodoRepository` 并覆盖 `todoRepositoryProvider` 即可，用例与 UI 无需改动。
- **换状态管理**：`domain` 不依赖 Riverpod，用例可独立复用。
- **本地化**：本应用自己的文案已全部集中在 `AppStrings`；平台界面（日期选择器等）
  走 `flutter_localizations`。真正要多语言时，把 `AppStrings` 换成生成的
  `AppLocalizations` 即可，`MaterialApp.locale` 也从常量改为 `MediaQuery` 的系统语言。
- **应用图标**：`windows/runner/resources/app_icon.ico` 目前仍是 Flutter 默认图标；
  通知的小图标已经是自绘的 `ic_notification.xml`。
