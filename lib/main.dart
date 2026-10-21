import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/audio.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // Los sonidos se sintetizan en segundo plano mientras arranca la splash.
  GameAudio.instance.init();
  runApp(const NidrathApp());
}

class NidrathApp extends StatelessWidget {
  const NidrathApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nidrath',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: const SplashScreen(),
    );
  }
}
