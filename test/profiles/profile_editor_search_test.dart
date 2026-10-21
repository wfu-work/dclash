import 'package:dclash_flutter/app/pages/profiles/widgets/profile_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('search selects and reveals matches and wraps in both directions', (
    tester,
  ) async {
    final content = TextEditingController(
      text:
          '${List.generate(150, (index) => 'line $index').join('\n')}\nneedle\nneedle',
    );
    addTearDown(content.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 350,
            child: ProfileCodeEditor(controller: content),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('profileEditorFind'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('profileEditorFindInput')),
      'NEEDLE',
    );
    await tester.pump(const Duration(milliseconds: 250));
    // The isolate completes in real time, while its continuation returns to
    // the test's fake async zone. Yield real time and pump that zone together.
    for (
      var attempt = 0;
      attempt < 100 &&
          content.selection.start != content.text.indexOf('needle');
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(content.selection.start, content.text.indexOf('needle'));
    final editor = tester.widget<EditableText>(find.byType(EditableText).last);
    expect(editor.scrollController!.offset, greaterThan(0));
    await tester.tap(find.byTooltip('profileEditorNext'));
    await tester.pump();
    expect(content.selection.start, content.text.lastIndexOf('needle'));
    await tester.tap(find.byTooltip('profileEditorNext'));
    await tester.pump();
    expect(content.selection.start, content.text.indexOf('needle'));
    await tester.tap(find.byTooltip('profileEditorPrevious'));
    await tester.pump();
    expect(content.selection.start, content.text.lastIndexOf('needle'));
  });
}
