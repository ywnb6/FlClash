import 'package:fl_clash/store/store_view.dart';
import 'package:fl_clash/store/xboard_models.dart';
import 'package:fl_clash/store/xboard_session.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

/// The panel's human check is drawn inside a WebView, which a widget test
/// cannot host, so the check is asserted through the modes that decide it.
/// What matters here is that the three forms show the fields they should and
/// that only registration asks for the panel's check.
void main() {
  late XboardSession session;

  setUp(() {
    session = XboardSession(null);
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      TestApp(
        child: Builder(
          builder: (context) => StoreAuthSheet(session: session),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('signing in offers neither the mailed code nor the invite code', (
    tester,
  ) async {
    await pumpSheet(tester);

    expect(find.text('邮箱'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('邮箱验证码'), findsNothing);
    expect(find.textContaining('邀请码'), findsNothing);
    expect(find.text('忘记密码'), findsOneWidget);
  });

  testWidgets('registration offers the mailed code and the invite code', (
    tester,
  ) async {
    await pumpSheet(tester);

    await tester.tap(find.text('没有账号，去注册'));
    await tester.pumpAndSettle();

    expect(find.text('邮箱验证码'), findsOneWidget);
    expect(find.textContaining('邀请码'), findsOneWidget);
    expect(find.text('忘记密码'), findsNothing);
  });

  testWidgets('the reset form keeps the code field and returns to sign in', (
    tester,
  ) async {
    await pumpSheet(tester);

    await tester.tap(find.text('忘记密码'));
    await tester.pumpAndSettle();

    expect(find.text('邮箱验证码'), findsOneWidget);
    expect(find.text('重置密码'), findsOneWidget);

    await tester.tap(find.text('返回登录'));
    await tester.pumpAndSettle();

    expect(find.text('邮箱验证码'), findsNothing);
    expect(find.text('忘记密码'), findsOneWidget);
  });

  testWidgets('signing in is not blocked by the panel human check', (
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
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();

    // The submission goes to the panel; what it must not do is stop at the
    // human check, which only registration carries.
    expect(find.text('请先完成人机验证'), findsNothing);
  });

  testWidgets('the reset form goes back to sign in, never to registration', (
    tester,
  ) async {
    await pumpSheet(tester);

    await tester.tap(find.text('忘记密码'));
    await tester.pumpAndSettle();

    expect(find.text('没有账号，去注册'), findsNothing);
    expect(find.text('返回登录'), findsOneWidget);
  });
}
