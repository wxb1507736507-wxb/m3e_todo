# M3E Todo

用 Flutter 编写的 **Material 3 Expressive** 待办应用，界面遵循 [Material 3 Expressive](https://m3.material.io/) 设计语言。支持 **Android** 与 **Windows** 两个正式目标，另带 **web** 目标用于快速预览。

- Flutter 3.47.3 (stable) / Dart 3.13.3
- 第三方依赖仅 `flutter_riverpod` 与 `web`（后者只在 web 目标下被引用）
- 静态分析零告警，111 个测试全部通过
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

### 验证结果

| 项目 | 结果 |
| --- | --- |
| `flutter analyze` | No issues found |
| `flutter test` | 111 个测试全部通过 |
| `flutter build apk --debug` | 成功。首次 909 秒（含下载），增量重建 7.4 秒，产物 145.75 MB |
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

> **尚未在真机或模拟器上运行过。** 本机没有已连接的设备，也没有可直接启动的 AVD，
> 因此界面在 Android 上的实际观感、以及 MethodChannel 取目录这条路径的运行时行为，
> 目前只是静态验证（编译通过 + 资源进包），未经实机确认。首次真机运行建议重点确认：
> 启动画面到首帧是否无闪烁、以及新建的待办在重启应用后是否还在。

---

## 目录结构

按 **feature-first + 三层架构** 组织：`core` 放跨功能基础设施，`features` 下每个功能自带
`domain / data / presentation` 三层。

```
lib/
├── main.dart                     # 仅调用 bootstrap()
├── app/
│   ├── bootstrap.dart            # 组合根：平台 I/O + Provider 覆盖 + 全局错误处理
│   ├── app.dart                  # MaterialApp，装配主题与 ThemeMode
│   └── app_shell.dart            # 应用外壳：导航、AppBar、快捷键、FAB
├── core/
│   ├── theme/                    # M3E 设计系统（见下）
│   ├── storage/                  # DocumentStore 存储接缝（原生 JSON 文件 / web localStorage）
│   ├── constants/app_strings.dart# 全部用户可见文案集中于此
│   └── utils/                    # 日历、日期格式化、Clock、ID 生成
└── features/
    ├── todos/
    │   ├── domain/               # 纯 Dart，无 Flutter 依赖
    │   │   ├── entities/         # Todo、TodoFilter、TodoStats …
    │   │   ├── repositories/     # TodoRepository 抽象接口
    │   │   └── usecases/         # 每个用户意图一个用例
    │   ├── data/                 # JSON 映射、数据源、仓储实现
    │   └── presentation/         # provider / controller / page / widgets
    └── settings/                 # 同一分层，负责主题模式与主题色
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
- **派生状态不存储。** 可见列表由 `visibleTodosProvider` 从「集合 + 过滤条件」实时算出，
  统计值由 `todoStatsProvider` 算出，不存在会与事实脱节的第二份副本。

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

新建 / 编辑待办（标题、备注、优先级、截止日期）· 勾选完成 · 删除并支持**撤销**
（恢复到原位置）· 搜索（标题 + 备注）· 状态筛选 · 四种排序（手动 / 最近创建 /
最快到期 / 优先级）· 拖拽排序 · 一键清除已完成（带确认）· 进度统计头 ·
浅色/深色/跟随系统 · 6 种主题色 · 响应式外壳（宽窗导航轨 / 窄窗导航栏）·
桌面快捷键 `Ctrl+N` 新建、`Ctrl+F` 聚焦搜索。

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

### 需要注意

- **Flutter 版本钉在 `3.47.3`**（工作流顶部的 `FLUTTER_VERSION`），与本地保持一致。
  如果这个版本在 GitHub 上取不到，改成 `stable` 或某个已发布的具体版本即可，这是唯一要改的地方。
- Windows 构建在 `windows-latest` 上完成——runner 预装了带 C++ 桌面工作负载的
  Visual Studio，正好补上本地缺的那一环。
- 工作流未在真实 GitHub 上运行过（本仓库尚未推送到 GitHub）。YAML 语法、
  `sed` 转义、三条版本推导逻辑都在本地实测过，但各 action 在 runner 上的实际行为
  只能等首次运行验证。

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
- 文档带 `version` 字段（`todos.json` 为 `{ "version": 1, "todos": [...] }`），便于将来迁移
- **单条记录损坏不会拖垮整个列表**：解析失败的记录被跳过，其余正常加载；
  整个文件损坏则重命名为 `*.corrupt-<时间戳>` 隔离，应用从空列表启动而非每次崩溃

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
│   └── settings/
│       └── presentation/# 外观面板交互 + 设置持久化（后者用纯 test()，见下）
└── support/             # FakeTodoRepository、样例数据、测试用 app 构造器
```

> **注意 `testWidgets` 的一个陷阱**：widget 测试体运行在计时器被伪造的 zone 里，
> 在那里发起的 `dart:io` 操作其完成回调永远不会被投递，`await` 它会直接卡死测试
> （`runAsync` 也救不了，因为 future 是在伪造 zone 中创建的）。
> 因此凡是涉及真实文件读写的用例都写成普通 `test()` + `ProviderContainer`，
> 见 `settings_controller_test.dart`；widget 测试只验证 UI 表现。

## 后续扩展

- **换存储后端**：实现 `TodoRepository` 并覆盖 `todoRepositoryProvider` 即可，用例与 UI 无需改动。
- **换状态管理**：`domain` 不依赖 Riverpod，用例可独立复用。
- **本地化**：文案已全部集中在 `AppStrings`，替换为生成的 `AppLocalizations` 即可。
- **应用图标**：`windows/runner/resources/app_icon.ico` 目前仍是 Flutter 默认图标。
