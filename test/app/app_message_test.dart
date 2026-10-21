import 'package:dclash_flutter/app/widgets/app_message.dart';
import 'package:dclash_flutter/app/widgets/app_icon.dart';
import 'package:dclash_flutter/configs/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _messageHarness(VoidCallback callback, {ThemeData? theme}) =>
    MaterialApp(
      theme: theme ?? AppTheme.resolve(Brightness.light, 'blue'),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => callback(),
              child: const Text('show message'),
            ),
          ),
        ),
      ),
    );

void main() {
  test('formatError removes technical exception prefixes', () {
    expect(
      AppMessage.formatError(Exception('network unavailable')),
      'network unavailable',
    );
    expect(
      AppMessage.formatError(StateError('invalid state')),
      'invalid state',
    );
    expect(AppMessage.formatError('plain message'), 'plain message');
  });

  testWidgets('shows a compact top message with a tone icon', (tester) async {
    await tester.pumpWidget(
      _messageHarness(() => AppMessage.success(_context(tester), 'Saved')),
    );
    await tester.tap(find.text('show message'));
    await tester.pump();

    final message = find.byType(AppMessage);
    expect(message, findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.icon == AppIcons.checkCircle,
      ),
      findsOneWidget,
    );
    expect(tester.getRect(message).top, lessThan(100));
    expect(tester.getRect(message).width, lessThan(300));
    expect(
      Theme.of(_context(tester)).snackBarTheme.behavior,
      SnackBarBehavior.floating,
    );
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('uses a warning icon for warning messages', (tester) async {
    await tester.pumpWidget(
      _messageHarness(() => AppMessage.warning(_context(tester), 'Check this')),
    );
    await tester.tap(find.text('show message'));
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.icon == AppIcons.warning,
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('replaces the currently visible message', (tester) async {
    await tester.pumpWidget(
      _messageHarness(() {
        final context = _context(tester);
        AppMessage.info(context, 'First');
        AppMessage.info(context, 'Second');
      }),
    );
    await tester.tap(find.text('show message'));
    await tester.pump();

    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('error messages keep the cleaned user-facing text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _messageHarness(() {
        AppMessage.error(_context(tester), StateError('Could not connect'));
      }),
    );
    await tester.tap(find.text('show message'));
    await tester.pump();

    expect(find.text('Could not connect'), findsOneWidget);
    expect(find.text('StateError: Could not connect'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  test('application themes configure codexc-style floating messages', () {
    for (final brightness in Brightness.values) {
      final theme = AppTheme.resolve(brightness, 'blue');
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(theme.snackBarTheme.elevation, 0);
      expect(theme.snackBarTheme.shape, isNotNull);
    }
  });
}

BuildContext _context(WidgetTester tester) =>
    tester.element(find.byType(Scaffold));
