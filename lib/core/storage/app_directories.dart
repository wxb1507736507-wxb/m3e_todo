import 'dart:io';

/// Resolves the per-user directory that holds this app's data files.
///
/// The app deliberately does **not** use `path_provider`: that is a plugin, and
/// plugins require Windows Developer Mode (or an elevated prompt) to create the
/// symlinks Flutter uses for native plugin registration. Resolving the folder
/// from the environment keeps the app plugin-free, which means the only
/// prerequisite for a Windows build is the Visual Studio C++ workload.
///
/// Native only. On web, `DocumentStore` is backed by `localStorage` instead and
/// this class is never reached.
abstract final class AppDirectories {
  /// Folder name created inside the platform's per-user data root.
  static const String appFolderName = 'M3ETodo';

  /// Keys probed, in order, to find the per-user data root.
  static const List<String> _rootKeys = <String>[
    'APPDATA',
    'LOCALAPPDATA',
    'XDG_DATA_HOME',
    'HOME',
    'USERPROFILE',
  ];

  /// Absolute path of the app's data directory.
  ///
  /// On Windows this is `%APPDATA%\M3ETodo`, the roaming profile location
  /// Microsoft recommends for user settings. The remaining keys are fallbacks so
  /// the app still starts where `APPDATA` is unset; if none are present the
  /// current working directory is used as a last resort.
  ///
  /// This is pure path computation with no I/O. The directory is created on
  /// demand by `JsonFileStore` the first time it writes, so merely asking for a
  /// store &mdash; which `bootstrap()` does before the first frame &mdash; costs
  /// nothing.
  static String dataDirectoryPath() =>
      '${_dataRoot()}${Platform.pathSeparator}$appFolderName';

  static String _dataRoot() {
    final Map<String, String> environment = Platform.environment;
    for (final String key in _rootKeys) {
      final String? value = environment[key];
      if (value != null && value.trim().isNotEmpty) {
        return value;
      }
    }
    return Directory.current.path;
  }
}

/// Builds child paths without pulling in `package:path` for two call sites.
extension DirectoryPathX on Directory {
  /// A file named [name] directly inside this directory.
  File childFile(String name) => File('$path${Platform.pathSeparator}$name');
}
