import 'package:codex_notif/models/mail_rule.dart';
import 'package:codex_notif/screens/rule_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget harness({
    MailRule? initial,
    ValueChanged<RuleEditorOutcome?>? result,
  }) {
    return MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final value = await Navigator.push<RuleEditorOutcome>(
              context,
              MaterialPageRoute(
                builder: (_) => RuleEditorPage(initial: initial),
              ),
            );
            result?.call(value);
          },
          child: const Text('open'),
        ),
      ),
    );
  }

  testWidgets('editor selects exactly one alert mode', (tester) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('强提醒'));
    await tester.pump();

    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('empty pattern prevents save', (tester) async {
    RuleEditorOutcome? outcome;
    await tester.pumpWidget(harness(result: (value) => outcome = value));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('完成'));
    await tester.pump();

    expect(find.text('匹配文字不能为空'), findsOneWidget);
    expect(outcome, isNull);
  });

  testWidgets('strong mode is returned in saved rule', (tester) async {
    RuleEditorOutcome? outcome;
    await tester.pumpWidget(harness(result: (value) => outcome = value));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Codex');
    await tester.tap(find.text('强提醒'));
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(outcome?.rule?.alertMode, AlertMode.strong);
  });

  testWidgets('existing rule exposes delete with confirmation', (tester) async {
    const rule = MailRule(
      id: '1',
      type: RuleType.subject,
      pattern: 'Codex',
      sound: AlertSound.alert,
    );
    await tester.pumpWidget(harness(initial: rule));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除规则'));
    await tester.pump();

    expect(find.text('确认删除这条规则？'), findsOneWidget);
  });
}
