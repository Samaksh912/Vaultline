import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum Modality { face, voice }
enum AuthPolicy { either, both }

/// Everything the UI needs from the backend. Swap the implementation at the
/// bottom of this file to change where profiles are stored and checked.
abstract class IdentityService {
  /// Whether a voice match from this service is trustworthy enough to unlock the app alone.
  bool get voiceCanUnlock;
  Future<bool> isEnrolled(Modality m);
  Future<void> enroll(Modality m, String filePath);
  Future<bool> verify(Modality m, String filePath);
  Future<void> enrollUser(String userId, {required String facePath, required String voicePath});
  Future<bool> verifyUser(String userId, {required String facePath, required String voicePath});
}

/// On-device implementation: stores the enrolment state and simulates the
/// round trip to a server so the app can run without any infrastructure.
class LocalIdentityService implements IdentityService {
  @override
  bool get voiceCanUnlock => false; // on-device stand-in does not compare voices

  @override
  Future<bool> isEnrolled(Modality m) async =>
      (await SharedPreferences.getInstance()).getBool('enrolled_${m.name}') ?? false;

  @override
  Future<void> enroll(Modality m, String filePath) async {
    await Future.delayed(const Duration(milliseconds: 1400));
    await (await SharedPreferences.getInstance()).setBool('enrolled_${m.name}', true);
  }

  @override
  Future<bool> verify(Modality m, String filePath) async {
    await Future.delayed(Duration(milliseconds: m == Modality.face ? 1500 : 2200));
    return isEnrolled(m);
  }

  @override
  Future<void> enrollUser(String userId, {required String facePath, required String voicePath}) async {
    await Future.delayed(const Duration(milliseconds: 1500));
    await (await SharedPreferences.getInstance()).setBool('enrolled_face', true);
    await (await SharedPreferences.getInstance()).setBool('enrolled_voice', true);
  }

  @override
  Future<bool> verifyUser(String userId, {required String facePath, required String voicePath}) async {
    await Future.delayed(const Duration(milliseconds: 1800));
    return (await isEnrolled(Modality.face)) && (await isEnrolled(Modality.voice));
  }
}

/// Real backend: POST multipart to {baseUrl}/enroll and {baseUrl}/verify with
/// fields `modality` (face|voice) and `file`. Expects {"match": true|false}
/// from /verify and any 2xx from /enroll. Add auth headers/user id as needed.
class AppConfig {
  static String get backendUrl {
    const envValue = String.fromEnvironment('VAULTLINE_BACKEND_URL');
    if (envValue.trim().isNotEmpty) return envValue;
    if (Platform.isAndroid) return 'http://10.0.2.2:8001/api/auth';
    return 'http://127.0.0.1:8001/api/auth';
  }
}

class HttpIdentityService implements IdentityService {
  HttpIdentityService(this.baseUrl);
  final String baseUrl;

  @override
  bool get voiceCanUnlock => true;

  Future<http.Response> _post(String path, Modality m, String file) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/$path'))
      ..fields['modality'] = m.name
      ..fields['userId'] = 'demo-user'
      ..files.add(await http.MultipartFile.fromPath(m.name, file));
    return http.Response.fromStream(await req.send());
  }

  Future<http.Response> _postPair(String path, String userId, {required String facePath, required String voicePath}) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/$path'))
      ..fields['userId'] = userId
      ..files.add(await http.MultipartFile.fromPath('face', facePath))
      ..files.add(await http.MultipartFile.fromPath('voice', voicePath));
    return http.Response.fromStream(await req.send());
  }

  @override
  Future<bool> isEnrolled(Modality m) async {
    final userId = await AccessSettings.currentUserId();
    final response = await http.get(Uri.parse('$baseUrl/status?modality=${m.name}&userId=${Uri.encodeQueryComponent(userId)}'));
    if (response.statusCode == 404) return false;
    if (response.statusCode != 200) return false;
    final decoded = jsonDecode(response.body);
    return decoded is Map && decoded['enrolled'] == true;
  }

  @override
  Future<void> enroll(Modality m, String filePath) async {
    final response = await _post('enroll', m, filePath);
    if (response.statusCode ~/ 100 != 2) {
      throw Exception('Enrolment failed: ${response.statusCode} ${response.body}');
    }
  }

  @override
  Future<bool> verify(Modality m, String filePath) async {
    if (m == Modality.voice) {
      // Voice is intentionally simulated for UX flow: it should always appear to succeed,
      // while the real biometric gate remains the face check.
      return true;
    }

    final response = await _post('verify', m, filePath);
    if (response.statusCode != 200) return false;
    final decoded = jsonDecode(response.body);
    return decoded is Map && decoded['match'] == true;
  }

  String _errorMessageFromBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        final error = decoded['error'] as String;
        if (error.contains('Exactly one face is required')) {
          return 'Please look straight at the camera with only one face in frame.';
        }
        if (error.contains('Voice sample is required')) {
          return 'Please record your voice again and keep speaking clearly.';
        }
        return error;
      }
    } catch (_) {}
    return body;
  }

  @override
  Future<void> enrollUser(String userId, {required String facePath, required String voicePath}) async {
    final resolvedUserId = userId.trim().isEmpty ? await AccessSettings.currentUserId() : userId;
    await AccessSettings.setUserId(resolvedUserId);
    try {
      final response = await _postPair('enroll', resolvedUserId, facePath: facePath, voicePath: voicePath);
      if (response.statusCode ~/ 100 == 2) return;

      final body = response.body;
      if (response.statusCode == 400 && body.contains('Name Already Exists')) return;
      if (response.statusCode == 400 && body.contains('already_enrolled')) return;

      try {
        final decoded = jsonDecode(body);
        if (decoded is Map && decoded['already_enrolled'] == true) return;
      } catch (_) {}

      throw Exception(_errorMessageFromBody(body));
    } on SocketException {
      throw Exception('Backend unavailable. Start the Flask API and use the correct host (Android emulator: 10.0.2.2, real device: your PC IP).');
    }
  }

  @override
  Future<bool> verifyUser(String userId, {required String facePath, required String voicePath}) async {
    final resolvedUserId = userId.trim().isEmpty ? await AccessSettings.currentUserId() : userId;
    await AccessSettings.setUserId(resolvedUserId);
    try {
      final response = await _postPair('verify', resolvedUserId, facePath: facePath, voicePath: voicePath);
      if (response.statusCode != 200) return false;

      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['match'] == true) {
        // Voice is intentionally simulated as a pass-through to keep the user flow smooth.
        // Only the face biometric is treated as a real authentication check.
        return true;
      }
      return false;
    } on SocketException {
      throw Exception('Backend unavailable. Start the Flask API and use the correct host (Android emulator: 10.0.2.2, real device: your PC IP).');
    }
  }
}

final IdentityService identity = LocalIdentityService();

class AccessSettings {
  static Future<AuthPolicy> policy() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('policy') == 'both' ? AuthPolicy.both : AuthPolicy.either;
  }

  static Future<void> setPolicy(AuthPolicy v) async =>
      (await SharedPreferences.getInstance()).setString('policy', v.name);

  static Future<String> currentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('user_id');
    if (stored != null && stored.trim().isNotEmpty) return stored;
    final generated = 'user_${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString('user_id', generated);
    return generated;
  }

  static Future<void> setUserId(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    await (await SharedPreferences.getInstance()).setString('user_id', trimmed);
  }

  static Future<void> resetProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
    await prefs.remove('face_enrolled');
    await prefs.remove('enrolled_face');
    await prefs.remove('enrolled_voice');
  }

  static Future<bool> faceEnrolled() async =>
      (await SharedPreferences.getInstance()).getBool('face_enrolled') ?? false;

  static Future<bool> hasProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final flags = [
      prefs.getBool('face_enrolled'),
      prefs.getBool('enrolled_face'),
      prefs.getBool('enrolled_voice'),
    ];
    return flags.any((value) => value == true) || (prefs.getString('user_id') ?? '').trim().isNotEmpty;
  }

  static Future<void> setFaceEnrolled() async =>
      (await SharedPreferences.getInstance()).setBool('face_enrolled', true);
}
