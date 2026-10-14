import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Api {
  Api._();
  static final instance = Api._();
  static const baseUrl = 'https://afakdeco-park-bot.onrender.com';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // Migrate existing sessions from SharedPreferences without forcing users
  // to sign in again. JWTs are kept in secure storage after this one-time move.
  Future<String?> _token() async {
    final secureToken = await _secureStorage.read(key: 'jwt');
    if (secureToken != null && secureToken.isNotEmpty) return secureToken;

    final prefs = await SharedPreferences.getInstance();
    final legacyToken = prefs.getString('jwt');
    if (legacyToken == null || legacyToken.isEmpty) return null;

    await _secureStorage.write(key: 'jwt', value: legacyToken);
    for (final key in const ['role', 'display_name', 'user_id']) {
      final value = prefs.getString(key);
      if (value != null) {
        await _secureStorage.write(key: key, value: value);
      }
      await prefs.remove(key);
    }
    await prefs.remove('jwt');
    return legacyToken;
  }

  Future<bool> hasToken() async {
    final token = await _token();
    if (token == null || token.isEmpty) return false;

    try {
      await request('GET', '/api/auth/session');
      return true;
    } catch (_) {
      // Preserve a session if the server is temporarily unreachable. A 401
      // clears the token in request(), so it will return false below.
      final remainingToken = await _token();
      return remainingToken != null && remainingToken.isNotEmpty;
    }
  }

  Future<void> saveAuth(Map<String, dynamic> data) async {
    await _secureStorage.write(key: 'jwt', value: data['token'].toString());
    await _secureStorage.write(key: 'role', value: '${data['role'] ?? ''}');
    await _secureStorage.write(
      key: 'display_name',
      value: '${data['display_name'] ?? ''}',
    );
    await _secureStorage.write(key: 'user_id', value: '${data['user_id'] ?? ''}');
    // Remove any legacy copies after successful secure storage.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt');
    await prefs.remove('role');
    await prefs.remove('display_name');
    await prefs.remove('user_id');
  }

  Future<void> logout() async {
    for (final key in const ['jwt', 'role', 'display_name', 'user_id']) {
      await _secureStorage.delete(key: key);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt');
    await prefs.remove('role');
    await prefs.remove('display_name');
    await prefs.remove('user_id');
  }

  // Cache GET responses for offline/read-only fallback. Fresh network data always wins.
  Future<dynamic> _getWithCache(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'api_cache:$path';
    try {
      final fresh = await request('GET', path);
      await prefs.setString(key, jsonEncode({
        'cached_at': DateTime.now().millisecondsSinceEpoch,
        'value': fresh,
      }));
      return fresh;
    } catch (_) {
      // Never use cached data after the server explicitly invalidates the session.
      if (await _token() == null) rethrow;
      final raw = prefs.getString(key);
      if (raw == null) rethrow;
      try {
        final entry = Map<String, dynamic>.from(jsonDecode(raw));
        final cachedAt = int.tryParse('${entry['cached_at']}') ?? 0;
        final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
        if (age < const Duration(hours: 24).inMilliseconds) {
          return entry['value'];
        }
      } catch (_) {
        await prefs.remove(key);
      }
      rethrow;
    }
  }

  Future<void> clearApiCache() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where((k) => k.startsWith('api_cache:')).toList()) {
      await prefs.remove(key);
    }
  }

  Future<String> downloadExport(String path, String filename) async {
    final response = await http.get(Uri.parse(baseUrl + path), headers: await _headers());
    if (response.statusCode == 401) {
      await logout();
      throw Exception('انتهت جلسة الدخول، سجّل الدخول مجدداً');
    }
    if (response.statusCode >= 400) {
      String message = 'تعذر تنزيل ملف Excel';
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['error'] != null) message = data['error'].toString();
      } catch (_) {}
      throw Exception(message);
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file.path;
  }

  Future<Map<String, String>> mediaHeaders() => _headers();

  String mediaUrl(int problemId, int mediaId) =>
      '$baseUrl/api/problems/$problemId/media/$mediaId';

  Future<Map<String, String>> _headers() async {
    final token = await _token();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse(baseUrl + path);
    final headers = await _headers();
    late http.Response response;
    if (method == 'GET') {
      response = await http.get(uri, headers: headers);
    } else if (method == 'POST') {
      response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(body ?? {}),
      );
    } else {
      response = await http.delete(uri, headers: headers);
    }

    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      data = {'ok': false, 'error': response.body};
    }
    if (response.statusCode == 401) {
      await logout();
      throw Exception('انتهت جلسة الدخول، سجّل الدخول مجدداً');
    }
    if (response.statusCode >= 400 || (data is Map && data['ok'] == false)) {
      throw Exception(data is Map ? (data['error'] ?? 'حدث خطأ') : 'حدث خطأ');
    }
    if (method != 'GET') await clearApiCache();
    return data;
  }

  Future<void> login(String uid, String code) async {
    final data = await request('POST', '/api/auth/verify', body: {
      'telegram_user_id': int.tryParse(uid),
      'code': code.trim(),
    });
    await saveAuth(Map<String, dynamic>.from(data['data']));
  }

  Future<List<dynamic>> dashboard() async =>
      List<dynamic>.from((await _getWithCache('/api/dashboard'))['data'] ?? []);

  Future<List<dynamic>> drivers() async =>
      List<dynamic>.from((await _getWithCache('/api/drivers'))['data'] ?? []);

  Future<List<dynamic>> problems({
    String? type,
    String? date,
    String? search,
  }) async {
    final query = <String, String>{};
    if (type != null && type != 'all') query['type'] = type;
    if (date != null) query['date'] = date;
    if (search != null && search.isNotEmpty) query['search'] = search;
    final path = Uri(path: '/api/problems', queryParameters: query).toString();
    return List<dynamic>.from((await _getWithCache(path))['data'] ?? []);
  }

  Future<Map<String, dynamic>> vehicleHistory(String vehicle) async =>
      Map<String, dynamic>.from(
        (await _getWithCache(
          '/api/vehicles/${Uri.encodeComponent(vehicle)}/history',
        ))['data'],
      );

  Future<Map<String, dynamic>> driverHistory(String id) async =>
      Map<String, dynamic>.from(
        (await _getWithCache('/api/drivers/$id'))['data'],
      );

  Future<void> fixProblem(int id) async =>
      request('POST', '/api/problems/$id/fix');

  Future<void> commentProblem(int id, String comment) async =>
      request('POST', '/api/problems/$id/comment', body: {'text': comment});

  Future<void> convertAccident(int id) async =>
      request('POST', '/api/problems/$id/accident');

  Future<List<dynamic>> vehicles() async =>
      List<dynamic>.from((await _getWithCache('/api/vehicles'))['data'] ?? []);

  Future<List<dynamic>> vidange() async =>
      List<dynamic>.from((await _getWithCache('/api/vidange'))['data'] ?? []);

  Future<Map<String, dynamic>> profile() async =>
      Map<String, dynamic>.from((await request('GET', '/api/auth/session'))['data'] ?? {});

  Future<void> addVehicle(String code) async =>
      request('POST', '/api/vehicles', body: {'code': code});

  Future<void> removeVehicle(String code) async =>
      request('DELETE', '/api/vehicles/${Uri.encodeComponent(code)}');

  Future<Map<String, dynamic>> fixLatestKm(String vehicle, int km) async {
    final response = await request(
      'POST',
      '/api/vehicles/${Uri.encodeComponent(vehicle)}/fix-km',
      body: {'km': km},
    );
    return Map<String, dynamic>.from(response['data'] ?? {});
  }

  Future<List<dynamic>> admins() async =>
      List<dynamic>.from((await request('GET', '/api/admins'))['data'] ?? []);

  Future<void> addAdmin(String userId) async =>
      request('POST', '/api/admins', body: {'telegram_user_id': int.tryParse(userId)});

  Future<void> removeAdmin(String userId) async =>
      request('DELETE', '/api/admins/${Uri.encodeComponent(userId)}');

  Future<void> approveDriver(String userId) async =>
      request('POST', '/api/drivers/${Uri.encodeComponent(userId)}/approve');

  Future<void> rejectDriver(String userId) async =>
      request('POST', '/api/drivers/${Uri.encodeComponent(userId)}/reject');

  Future<void> removeDriver(String userId) async =>
      request('DELETE', '/api/drivers/${Uri.encodeComponent(userId)}');

  Future<Map<String, dynamic>> setVidange(String vehicle, int km) async {
    final response = await request(
      'POST',
      '/api/vidange/${Uri.encodeComponent(vehicle)}/set',
      body: {'km': km},
    );
    return Map<String, dynamic>.from(response['data'] ?? {});
  }
}
