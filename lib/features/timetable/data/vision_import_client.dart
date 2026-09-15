/// The one HTTP call network recognition makes.
///
/// OpenAI-compatible on purpose: 通义千问 (DashScope), 智谱, Kimi, SiliconFlow,
/// DeepSeek and anything self-hosted all expose `POST {base}/chat/completions`
/// with an `image_url` carrying a base64 data URI, so one small client serves
/// all of them and the user picks a provider by filling in a base URL, a model
/// and a key. Nothing here is provider-specific, and there is no plugin: the
/// request goes out through `dart:io`, which Flutter already has.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A provider that can look at a picture and answer with JSON.
class VisionProvider {
  const VisionProvider({
    required this.name,
    required this.baseUrl,
    required this.model,
    this.help,
  });

  final String name;

  /// Everything up to but not including `/chat/completions`.
  final String baseUrl;
  final String model;

  /// Where to get a key, said in the settings screen.
  final String? help;
}

/// The providers worth naming, with the endpoint each one documents.
///
/// A preset only fills in the two fields the user would otherwise have to find
/// in a console; nothing about the call changes between them, and 自定义 is there
/// for everything else — including a model running on the user's own machine.
const List<VisionProvider> visionProviders = <VisionProvider>[
  VisionProvider(
    name: '通义千问（阿里云百炼）',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    model: 'qwen-vl-max',
    help: 'bailian.console.aliyun.com 里创建 API-KEY',
  ),
  VisionProvider(
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-4v-plus',
    help: 'open.bigmodel.cn 里创建 API Key',
  ),
  VisionProvider(
    name: 'Kimi（月之暗面）',
    baseUrl: 'https://api.moonshot.cn/v1',
    model: 'moonshot-v1-8k-vision-preview',
    help: 'platform.moonshot.cn 里创建 API Key',
  ),
  VisionProvider(
    name: '硅基流动 SiliconFlow',
    baseUrl: 'https://api.siliconflow.cn/v1',
    model: 'Qwen/Qwen2.5-VL-72B-Instruct',
    help: 'cloud.siliconflow.cn 里创建 API 密钥',
  ),
  VisionProvider(
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    model: 'deepseek-chat',
    help: 'platform.deepseek.com 里创建 API key（需账号已开通视觉模型）',
  ),
  VisionProvider(
    name: '自定义（OpenAI 兼容）',
    baseUrl: '',
    model: '',
    help: '任何 OpenAI 兼容接口：填 base URL 与模型名',
  ),
];

/// What a vision call needs to know.
class VisionRequest {
  const VisionRequest({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.prompt,
    required this.imagePath,
    this.timeout = const Duration(seconds: 90),
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final String prompt;
  final String imagePath;
  final Duration timeout;
}

/// A call that could not be made, with something a user can act on.
class VisionFailure implements Exception {
  const VisionFailure(this.message, {this.detail});

  /// Written for the person holding the phone: what went wrong, and what to do.
  final String message;

  /// The provider's own words, when there are any.
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message（$detail）';
}

/// Sends one picture and one instruction, and returns what came back.
typedef VisionComplete = Future<String> Function(VisionRequest request);

/// The real client: one POST, one reply, no retries.
///
/// No retry on purpose. A recognition that failed is a recognition the user is
/// waiting on, and asking again costs them another ninety seconds of the same
/// wait for a result that is usually the same failure — a wrong key, no credit,
/// no network. The caller falls back to the on-device reader instead, which is
/// instant and offline.
Future<String> completeWithVision(VisionRequest request) async {
  final String base = request.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  if (base.isEmpty) {
    throw const VisionFailure('没有填接口地址', detail: '设置 → 识图导课');
  }
  if (request.apiKey.trim().isEmpty) {
    throw const VisionFailure('没有填 API Key', detail: '设置 → 识图导课');
  }
  if (request.model.trim().isEmpty) {
    throw const VisionFailure('没有填模型名', detail: '设置 → 识图导课');
  }

  final File file = File(request.imagePath);
  if (!await file.exists()) {
    throw const VisionFailure('图片找不到了');
  }
  // The file goes as it is. Re-encoding it to shrink it was tried on paper and
  // does not work: the only encoding Flutter can produce is PNG, and a PNG of a
  // photograph is larger than the JPEG it came from. Every provider this app
  // names takes images up to 10MB, which covers a screenshot and a phone photo
  // alike; anything past that is answered with "cut it down first".
  final String dataUri =
      'data:${_mimeOf(file.path)};base64,${base64Encode(await file.readAsBytes())}';

  final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final HttpClientRequest post = await client
        .postUrl(Uri.parse('$base/chat/completions'))
        .timeout(request.timeout);
    post.headers.contentType = ContentType.json;
    post.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${request.apiKey.trim()}');
    post.write(
      jsonEncode(<String, Object?>{
        'model': request.model.trim(),
        'messages': <Object?>[
          <String, Object?>{
            'role': 'user',
            'content': <Object?>[
              <String, Object?>{'type': 'text', 'text': request.prompt},
              <String, Object?>{
                'type': 'image_url',
                'image_url': <String, Object?>{'url': dataUri},
              },
            ],
          },
        ],
        // Asking for JSON as a *mode* where it is supported: the prompt already
        // says so, and a provider that can enforce it removes the one class of
        // answer this cannot parse.
        'response_format': <String, Object?>{'type': 'json_object'},
        'temperature': 0,
        'stream': false,
      }),
    );

    final HttpClientResponse response = await post.close().timeout(request.timeout);
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VisionFailure(
        _messageForStatus(response.statusCode),
        detail: _errorText(body),
      );
    }
    return _contentOf(body);
  } on VisionFailure {
    rethrow;
  } on SocketException catch (error) {
    throw VisionFailure('连不上服务器', detail: error.osError?.message ?? error.message);
  } on TimeoutException {
    throw const VisionFailure('识别超时了，换张清楚一点的图再试');
  } on HandshakeException catch (error) {
    throw VisionFailure('安全连接失败', detail: error.message);
  } finally {
    client.close(force: true);
  }
}

/// What went wrong, in words that suggest what to do about it.
String _messageForStatus(int status) => switch (status) {
      401 || 403 => 'API Key 不对或没有权限',
      404 => '接口地址或模型名不对',
      413 => '图片太大了',
      429 => '请求太频繁或额度用完了',
      >= 500 => '服务商这边出错了，过一会儿再试',
      _ => '识别失败（HTTP $status）',
    };

/// The provider's own explanation, which is usually the accurate one.
String? _errorText(String body) {
  try {
    final Object? decoded = jsonDecode(body);
    if (decoded is Map) {
      final Object? error = decoded['error'];
      if (error is Map && error['message'] is String) {
        return error['message']! as String;
      }
      if (decoded['message'] is String) {
        return decoded['message']! as String;
      }
    }
  } on FormatException {
    // Not JSON: keep the raw body if it is short enough to be a message.
  }
  final String trimmed = body.trim();
  return trimmed.isEmpty || trimmed.length > 300 ? null : trimmed;
}

/// The assistant's text out of an OpenAI-shaped reply.
String _contentOf(String body) {
  final Object? decoded = jsonDecode(body);
  if (decoded is! Map) {
    throw const VisionFailure('看不懂服务器的回复');
  }
  final Object? choices = decoded['choices'];
  if (choices is! List || choices.isEmpty) {
    throw VisionFailure('服务器没有给出结果', detail: _errorText(body));
  }
  final Object? first = choices.first;
  final Object? message = first is Map ? first['message'] : null;
  final Object? content = message is Map ? message['content'] : null;
  if (content is String && content.trim().isNotEmpty) {
    return content;
  }
  // Some providers answer with parts rather than a string.
  if (content is List) {
    final String joined = content
        .whereType<Map>()
        .map((Map part) => part['text'])
        .whereType<String>()
        .join();
    if (joined.trim().isNotEmpty) {
      return joined;
    }
  }
  throw const VisionFailure('服务器返回了空结果');
}

/// The type to declare, from the extension the picker gave the file.
///
/// The bytes are not sniffed: every provider accepts these three and rejects a
/// wrong label, and the app's own picker only ever produces them (plus the
/// camera's JPEG).
String _mimeOf(String path) {
  final String lower = path.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  return 'image/jpeg';
}
