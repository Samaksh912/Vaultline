import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

enum Step { idle, working, ok, fail, skipped }

/// Face check handled by the phone's own unlock (face / fingerprint / PIN).
Future<bool> deviceFaceCheck(String reason) async {
  try {
    return await LocalAuthentication().authenticate(
      localizedReason: reason,
      authMessages: const [
        AndroidAuthMessages(
          signInTitle: 'Vaultline',
          biometricHint: 'Look at the screen to verify',
          cancelButton: 'Cancel',
        ),
      ],
      // Set biometricOnly: true to forbid the PIN fallback (needs strong biometrics on the phone).
      options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
    );
  } catch (_) {
    return false;
  }
}

/// Captures a face photo and a short voice sample, then returns a filesystem path
/// for the file that should be uploaded to the backend for enrolment or verification.
class Capture {
  final _rec = AudioRecorder();
  final _picker = ImagePicker();
  final _player = AudioPlayer();
  String? _voicePath;

  Future<String> face({ImageSource source = ImageSource.camera}) async {
    final image = await _picker.pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 1280,
      imageQuality: 90,
    );
    if (image == null) throw Exception('No face image was captured.');
    return image.path;
  }

  Future<void> startVoiceCapture() async {
    if (!await _rec.hasPermission()) throw Exception('Microphone access is required.');
    final dir = await getTemporaryDirectory();
    _voicePath = '${dir.path}/v_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _rec.start(const RecordConfig(encoder: AudioEncoder.wav), path: _voicePath!);
  }

  Future<String> stopVoiceCapture() async {
    final recordedPath = (await _rec.stop()) ?? _voicePath;
    _voicePath = null;
    if (recordedPath == null || recordedPath.trim().isEmpty) {
      throw Exception('No voice sample was recorded.');
    }
    try {
      await _player.stop();
      await _player.play(DeviceFileSource(recordedPath));
    } catch (_) {}
    return recordedPath;
  }

  Future<String> voice({int seconds = 3}) async {
    if (!await _rec.hasPermission()) throw Exception('Microphone access is required.');
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/v_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _rec.start(const RecordConfig(encoder: AudioEncoder.wav), path: path);
    await Future.delayed(Duration(seconds: seconds));
    final recordedPath = (await _rec.stop()) ?? path;
    try {
      await _player.stop();
      await _player.play(DeviceFileSource(recordedPath));
    } catch (_) {}
    return recordedPath;
  }

  Future<void> replay(String path) async {
    if (path.trim().isEmpty) return;
    try {
      await _player.stop();
      await _player.play(DeviceFileSource(path));
    } catch (_) {}
  }

  void dispose() {
    _player.stop();
    _rec.dispose();
  }
}

class SafeImagePreview extends StatelessWidget {
  const SafeImagePreview({
    super.key,
    required this.path,
    this.height = 180,
    this.width = double.infinity,
    this.fit = BoxFit.cover,
    this.placeholderText = 'Preview unavailable',
  });

  final String? path;
  final double height;
  final double width;
  final BoxFit fit;
  final String placeholderText;

  @override
  Widget build(BuildContext context) {
    if (path == null || path!.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final file = File(path!);
    if (!file.existsSync()) {
      return Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Center(
          child: Text(
            placeholderText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Image.file(
        file,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Center(child: Icon(Icons.broken_image_outlined, size: 36, color: Colors.white54)),
        ),
      ),
    );
  }
}

class FaceBadge extends StatelessWidget {
  const FaceBadge(this.step, {super.key});
  final Step step;
  @override
  Widget build(BuildContext context) {
    final color = switch (step) {
      Step.ok => Colors.greenAccent,
      Step.fail => Colors.redAccent,
      Step.working => Colors.amber,
      _ => Theme.of(context).colorScheme.primary,
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color, width: 3),
      ),
      child: Icon(Icons.face_retouching_natural, size: 80, color: color),
    );
  }
}

class StatusTile extends StatelessWidget {
  const StatusTile(this.icon, this.label, this.step, {super.key});
  final IconData icon;
  final String label;
  final Step step;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (step) {
      Step.idle => ('Ready', Colors.white54),
      Step.working => ('Checking…', Colors.amber),
      Step.ok => ('Confirmed', Colors.greenAccent),
      Step.fail => ('Not recognised', Colors.redAccent),
      Step.skipped => ('Not set up', Colors.white38),
    };
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label),
        subtitle: Text(text, style: TextStyle(color: color)),
        trailing: step == Step.working
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : null,
      ),
    );
  }
}
