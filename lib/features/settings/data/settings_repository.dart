import '../../../../core/storage/document_store.dart';
import '../domain/app_settings.dart';
import 'app_settings_codec.dart';

/// Persists [AppSettings] as a JSON document.
class SettingsRepository {
  SettingsRepository(this._store);

  final DocumentStore _store;

  Future<AppSettings> load() async {
    return AppSettingsCodec.fromJson(await _store.read());
  }

  Future<void> save(AppSettings settings) {
    return _store.write(AppSettingsCodec.toJson(settings));
  }
}
