import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Kamera görüntüsü dik yönde okunur.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Store.instance.load();
  runApp(const BelgeTaraApp());
}

class BelgeTaraApp extends StatelessWidget {
  const BelgeTaraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Belgetara',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const _Splash(),
    );
  }
}

class _Splash extends StatefulWidget {
  const _Splash();
  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, a, __) => FadeTransition(opacity: a, child: const HomeScreen()),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, v, c) => Opacity(opacity: v, child: Transform.scale(scale: 0.85 + 0.15 * v, child: c)),
          child: Image.asset('assets/logo.png', width: 210),
        ),
      ),
    );
  }
}
