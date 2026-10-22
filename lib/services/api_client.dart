import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class AttendanceApi {
  AttendanceApi._();

  static String get baseUrl {
    String? configured;
    try {
      configured = dotenv.env['API_BASE_URL'];
    } catch (_) {
      // Widget tests can build screens without loading the .env asset first.
    }
    return (configured ?? 'http://10.0.2.2:5000/api').replaceAll(
      RegExp(r'/$'),
      '',
    );
  }

  static String? _token;

  static Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    _token = preferences.getString('accessToken');
  }

  static Future<void> saveSession(Map<String, dynamic> session) async {
    final preferences = await SharedPreferences.getInstance();
    _token = session['accessToken'] as String?;
    if (_token != null) await preferences.setString('accessToken', _token!);
    await preferences.setString(
      'role',
      session['role'] as String? ?? 'Employee',
    );
    await preferences.setString(
      'userName',
      session['userName'] as String? ?? '',
    );
    final employeeId = (session['employeeId'] as num?)?.toInt();
    if (employeeId != null) {
      await preferences.setInt('employeeId', employeeId);
    } else {
      await preferences.remove('employeeId');
    }
  }

  static Future<void> clearSession() async {
    _token = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('accessToken');
    await preferences.remove('role');
    await preferences.remove('userName');
    await preferences.remove('employeeId');
  }

  static Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _request('GET', path, query: query);

  static Future<dynamic> post(String path, [Object? body]) =>
      _request('POST', path, body: body);

  static Future<dynamic> put(String path, [Object? body]) =>
      _request('PUT', path, body: body);

  static Future<dynamic> delete(String path) => _request('DELETE', path);

  static Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$baseUrl/$path').replace(queryParameters: query);
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (_token != null) headers['Authorization'] = 'Bearer $_token';
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await request.send().timeout(
        const Duration(seconds: 20),
      );
      final response = await http.Response.fromStream(streamed);
      final text = utf8.decode(response.bodyBytes);
      dynamic data;
      if (text.isNotEmpty) {
        try {
          data = jsonDecode(text);
        } catch (_) {
          data = text;
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = data is Map
            ? _errorMessage(data, response.statusCode)
            : (text.isEmpty
                  ? 'Yêu cầu thất bại (${response.statusCode})'
                  : text);
        throw ApiException(message, statusCode: response.statusCode);
      }
      return data;
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException(
        'Không kết nối được API tại $baseUrl. Kiểm tra API đang chạy và cấu hình .env. ($error)',
      );
    }
  }

  static String _errorMessage(Map data, int statusCode) {
    final parts = <String>[];
    final message = data['message'] ?? data['detail'];
    if (message is String && message.isNotEmpty) parts.add(message);

    // ASP.NET Core returns validation details in ProblemDetails.errors.
    // Include them instead of showing only the generic title in the UI.
    final errors = data['errors'];
    if (errors is Map) {
      for (final entry in errors.entries) {
        final value = entry.value;
        final details = value is List
            ? value.map((item) => item.toString()).join(', ')
            : value.toString();
        parts.add('${entry.key}: $details');
      }
    }

    if (parts.isEmpty) {
      final title = data['title'] ?? data['code'];
      if (title is String && title.isNotEmpty) parts.add(title);
    }
    if (parts.isEmpty) parts.add('Yêu cầu thất bại');
    parts.add('HTTP $statusCode');
    return parts.join('\n');
  }
}
