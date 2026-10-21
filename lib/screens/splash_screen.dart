import 'dart:async';
import 'package:flutter/material.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final String _credit;

  static const _credits = ['HILAL INDUSTRIES', 'MAHMOOD INDUSTRIES'];
  static const _blue = Color(0xFF2FE0FF);

  @override
  void initState() {
    super.initState();
    _credit = _credits[DateTime.now().microsecond % _credits.length];
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
    Timer(const Duration(milliseconds: 2800), _goHome);
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ScaleTransition(
                    scale: _scale,
                    child: Image.asset(
                      'assets/images/splash_logo.jpg',
                      width: MediaQuery.of(context).size.width * 0.9,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Text(
                        'EDITH',
                        style: const TextStyle(
                          fontSize: 34,
                          letterSpacing: 10,
                          color: _blue,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                'E D I T H',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 6,
                  color: _blue,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _credit,
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 5,
                  color: Colors.white54,
                ),
              ),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }
}
