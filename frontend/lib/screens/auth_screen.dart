import 'dart:async';

import 'package:flutter/material.dart' hide Step;
import '../identity_service.dart';
import '../ui.dart';
import 'enroll_screen.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final cap = Capture();
  Step face = Step.idle, voice = Step.idle;
  bool busy = false, anyEnrolled = true, voiceRecording = false;
  String? error;
  String? facePreviewPath;
  String? voicePreviewPath;

  bool get canContinue => face == Step.ok && voice == Step.ok && !busy && !voiceRecording;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final faceEnrolled = await identity.isEnrolled(Modality.face);
      final voiceEnrolled = await identity.isEnrolled(Modality.voice);
      if (mounted) {
        setState(() => anyEnrolled = faceEnrolled || voiceEnrolled);
        if (anyEnrolled && (faceEnrolled || voiceEnrolled)) {
          unawaited(_authenticateFace(automatic: true));
        }
      }
    } catch (_) {
      if (mounted) setState(() => anyEnrolled = false);
    }
  }

  Future<void> _authenticateFace({bool automatic = false}) async {
    if (busy || voiceRecording) return;

    setState(() {
      busy = true;
      error = null;
      face = Step.working;
      if (!automatic) {
        voice = voice == Step.ok ? Step.ok : Step.idle;
      }
    });

    try {
      final facePath = await cap.face();
      final granted = await identity.verify(Modality.face, facePath);
      if (!mounted) return;

      facePreviewPath = facePath;
      setState(() {
        face = granted ? Step.ok : Step.fail;
        busy = false;
      });

      if (!granted) {
        setState(() => error = 'Face authentication failed. Please try again.');
        return;
      }

      if (automatic || !mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Face confirmed. Please speak to continue.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        busy = false;
        face = Step.fail;
        error = 'Something went wrong while checking your face. Please try again.';
      });
    }
  }

  Future<void> _startVoiceCapture() async {
    if (face != Step.ok || busy || voiceRecording) return;

    setState(() {
      voiceRecording = true;
      voice = Step.working;
      error = null;
    });

    try {
      await cap.startVoiceCapture();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recording… press pause when you are done speaking.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        voiceRecording = false;
        voice = Step.fail;
        error = 'Microphone access is required to continue.';
      });
    }
  }

  Future<void> _authenticateVoice() async {
    if (!voiceRecording) return;

    setState(() {
      voiceRecording = false;
      busy = true;
      voice = Step.working;
      error = null;
    });

    try {
      final voicePath = await cap.stopVoiceCapture();
      final granted = await identity.verify(Modality.voice, voicePath);
      if (!mounted) return;

      voicePreviewPath = voicePath;
      setState(() {
        voice = granted ? Step.ok : Step.fail;
        busy = false;
      });

      if (granted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voice confirmed.')));
      } else {
        setState(() => error = 'Voice authentication failed. Please try again.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        busy = false;
        voice = Step.fail;
        error = 'Something went wrong while checking your voice. Please try again.';
      });
    }
  }

  Future<void> _continue() async {
    if (!canContinue) return;

    setState(() => busy = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Identity confirmed.')));
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  Future<void> _setUp() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EnrollScreen()));
    _prepare();
  }

  @override
  void dispose() {
    cap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 12),
              Text('Vaultline', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              const Text('Confirm it\'s you to continue',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
              const SizedBox(height: 28),
              Center(child: FaceBadge(face)),
              const SizedBox(height: 28),
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
                          label: const Text('Replay voice sample'),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              if (anyEnrolled) ...[
                if (face == Step.fail && !busy && !voiceRecording)
                  TextButton.icon(
                    onPressed: () => _authenticateFace(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                if (face == Step.ok && !voiceRecording && voice != Step.ok)
                  FilledButton.icon(
                    onPressed: busy ? null : _startVoiceCapture,
                    icon: const Icon(Icons.mic),
                    label: const Text('Speak'),
                  ),
                if (voiceRecording)
                  FilledButton.icon(
                    onPressed: _authenticateVoice,
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                  ),
                if (voice == Step.fail && !busy && !voiceRecording)
                  TextButton.icon(
                    onPressed: _startVoiceCapture,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again voice'),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: canContinue ? _continue : null,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Continue'),
                ),
              ] else ...[
                const Text('Welcome! Set up face and voice access to get started.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: _setUp, icon: const Icon(Icons.person_add), label: const Text('Get started')),
              ],
              if (!busy && (face == Step.fail || voice == Step.fail))
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Tip: speak clearly and look at the screen when prompted.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.white38)),
                ),
            ],
          ),
        ),
      );
}
