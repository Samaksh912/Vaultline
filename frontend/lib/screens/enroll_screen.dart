import 'package:flutter/material.dart' hide Step;
import '../identity_service.dart';
import '../ui.dart';
import 'auth_screen.dart';

class EnrollScreen extends StatefulWidget {
  const EnrollScreen({super.key});
  @override
  State<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends State<EnrollScreen> {
  final cap = Capture();
  Step face = Step.idle, voice = Step.idle;
  bool busy = false;
  bool completed = false;
  String? error;
  String? facePreviewPath;
  String? voicePreviewPath;

  Future<void> _finish() async {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator.pushReplacement(MaterialPageRoute(builder: (_) => const AuthScreen()));
  }

  Future<void> _start() async {
    setState(() {
      busy = true;
      completed = false;
      error = null;
      face = voice = Step.idle;
    });

    try {
      final userId = await AccessSettings.currentUserId();
      final alreadyEnrolled = await identity.isEnrolled(Modality.face) || await identity.isEnrolled(Modality.voice);
      if (alreadyEnrolled) {
        if (!mounted) return;
        setState(() {
          face = Step.ok;
          voice = Step.ok;
          busy = false;
          completed = true;
        });
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Look at your phone camera and hold still.')),
      );
      final facePath = await cap.face();
      setState(() => face = Step.working);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Now speak clearly for a few seconds.')),
      );
      final voicePath = await cap.voice();

      await identity.enrollUser(userId, facePath: facePath, voicePath: voicePath);
      await AccessSettings.setFaceEnrolled();

      if (!mounted) return;
      facePreviewPath = facePath;
      voicePreviewPath = voicePath;
      setState(() {
        face = Step.ok;
        voice = Step.ok;
        busy = false;
        completed = true;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your profile has been saved.')));
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '').trim();
      setState(() {
        busy = false;
        face = Step.fail;
        voice = Step.fail;
        error = message.isNotEmpty ? message : 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  void dispose() {
    cap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Set up access'), backgroundColor: Colors.transparent),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          const Text(
            'When prompted, look at the screen and say “my voice is my password”. '
            'Face and voice are captured together and take a few seconds.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 24),
          Center(child: FaceBadge(face)),
          const SizedBox(height: 24),
          StatusTile(Icons.face_retouching_natural, 'Face', face),
          StatusTile(Icons.graphic_eq, 'Voice', voice),
          if (error != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent))),
          if (facePreviewPath != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                children: [
                  SafeImagePreview(path: facePreviewPath),
                  const SizedBox(height: 12),
                  if (voicePreviewPath != null)
                    FilledButton.icon(
                      onPressed: () => cap.replay(voicePreviewPath!),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Listen to recorded voice'),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          if (completed)
            FilledButton.icon(
              onPressed: _finish,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continue to sign in'),
            )
          else
            FilledButton.icon(
              onPressed: busy ? null : _start,
              icon: const Icon(Icons.fiber_manual_record),
              label: Text(busy ? 'Saving…' : 'Capture and save'),
            ),
        ]),
      );
}
