import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/store/store_view.dart';
import 'package:fl_clash/store/xboard_models.dart';
import 'package:fl_clash/store/xboard_session.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

/// The three account forms are one sheet, so these tests drive it the way a
/// user does and assert what each face offers. Texts come from the generated
/// localizations rather than literals, so a translation change cannot make a
/// passing screen look broken.
void main() {
  late XboardSession session;
  late AppLocalizations l;

  setUp(() {
    session = XboardSession(null);
    l = loadAppLocalizations(const Locale('zh'));
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      TestApp(locale: const Locale('zh'), child: StoreAuthSheet(session: session)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('signing in asks for the email and the password alone', (
    tester,
  ) async {
    await pumpSheet(tester);

    expect(find.text(l.storeEmail), findsOneWidget);
    expect(find.text(l.storePassword), findsOneWidget);
    expect(find.text(l.storeEmailCode), findsNothing);
    expect(find.text(l.storeInviteCode), findsNothing);
    expect(find.text(l.storeForgotPassword), findsOneWidget);
  });

  testWidgets('registration adds the mailed code and the invite code', (
    tester,
  ) async {
    await pumpSheet(tester);

    await tester.tap(find.text(l.storeNoAccount));
    await tester.pumpAndSettle();

    expect(find.text(l.storeEmailCode), findsOneWidget);
    expect(find.text(l.storeInviteCode), findsOneWidget);
    expect(find.text(l.storeForgotPassword), findsNothing);
  });

  testWidgets('the reset form asks for the code and returns to sign in', (
    tester,
  ) async {
    await pumpSheet(tester);

    await tester.tap(find.text(l.storeForgotPassword));
    await tester.pumpAndSettle();

    expect(find.text(l.storeEmailCode), findsOneWidget);
    expect(find.text(l.storeResetPassword), findsOneWidget);
    expect(find.text(l.storeNoAccount), findsNothing);

    await tester.tap(find.text(l.storeBackToSignIn));
    await tester.pumpAndSettle();

    expect(find.text(l.storeEmailCode), findsNothing);
    expect(find.text(l.storeForgotPassword), findsOneWidget);
  });

  testWidgets('a panel that checks for a human does not block signing in', (
    tester,
  ) async {
    session.useSiteConfig(
      const XboardSiteConfig(
        captchaEnabled: true,
        captchaType: 'turnstile',
        turnstileSiteKey: 'site-key',
      ),
    );
    await pumpSheet(tester);

    await tester.enterText(find.byType(EditableText).first, 'a@b.com');
    await tester.enterText(find.byType(EditableText).last, 'password123');
    await tester.tap(find.text(l.storeSignIn));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text(l.storeFillCaptcha), findsNothing);
  });
}
