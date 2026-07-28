import 'package:flutter/material.dart';

/// Matches the HTML source's `.main{max-width:1120px;margin:0 auto;
/// padding:26px 20px}` — the centered content column every screen below
/// the nav bar uses.
class AppMain extends StatelessWidget {
  const AppMain({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: child,
        ),
      ),
    );
  }
}
