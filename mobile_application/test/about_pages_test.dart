import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/core/theme/app_theme.dart';
import 'package:solace_mobile/features/profile/about_pages.dart';

Future<void> _pump(WidgetTester tester, Widget page, {double scale = 1}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: page,
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('about page names the developers and the department at $scale x', (tester) async {
      await _pump(tester, const AboutSolacePage(), scale: scale);
      expect(find.text('Rafsan Riasat'), findsOneWidget);
      expect(find.text('2207006'), findsOneWidget);
      expect(find.text('Dadhichi Sarker'), findsOneWidget);
      expect(find.text('2207118'), findsOneWidget);
      expect(find.textContaining('CSE · Batch 2K22'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('terms page lays out at $scale x', (tester) async {
      await _pump(tester, const TermsAndPrivacyPage(), scale: scale);
      expect(find.text('STAYS ON THIS PHONE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('faq answers open when a question is tapped', (tester) async {
    await _pump(tester, const FaqPage());
    expect(find.textContaining('reflection tool and cannot diagnose'), findsNothing);
    await tester.tap(find.text('Is Solace a replacement for therapy?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('reflection tool and cannot diagnose'), findsOneWidget);
    await tester.tap(find.text('Is Solace a replacement for therapy?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('reflection tool and cannot diagnose'), findsNothing);
  });

  testWidgets('faq lays out at 2x text', (tester) async {
    await _pump(tester, const FaqPage(), scale: 2.0);
    expect(tester.takeException(), isNull);
  });
}
