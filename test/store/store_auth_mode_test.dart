import 'package:fl_clash/store/store_auth_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('storeAuthMode', () {
    test('reset wins over register', () {
      expect(
        storeAuthMode(register: true, reset: true),
        StoreAuthMode.reset,
      );
    });

    test('register without reset is the register form', () {
      expect(
        storeAuthMode(register: true, reset: false),
        StoreAuthMode.register,
      );
    });

    test('neither flag is the sign-in form', () {
      expect(
        storeAuthMode(register: false, reset: false),
        StoreAuthMode.signIn,
      );
    });
  });

  group('StoreAuthModeSwitch.toggled', () {
    test('sign-in and register swap', () {
      expect(StoreAuthMode.signIn.toggled(), StoreAuthMode.register);
      expect(StoreAuthMode.register.toggled(), StoreAuthMode.signIn);
    });

    test('reset returns to sign-in, not registration', () {
      expect(StoreAuthMode.reset.toggled(), StoreAuthMode.signIn);
    });
  });

  group('StoreAuthModeSwitch fields', () {
    test('only registration offers an invite code', () {
      expect(StoreAuthMode.signIn.showsInvite, isFalse);
      expect(StoreAuthMode.register.showsInvite, isTrue);
      expect(StoreAuthMode.reset.showsInvite, isFalse);
    });

    test('the mailed code is asked for on reset and on a panel that wants it', () {
      expect(
        StoreAuthMode.signIn.showsEmailCodeFor(panelNeedsCode: false),
        isFalse,
      );
      expect(
        StoreAuthMode.register.showsEmailCodeFor(panelNeedsCode: false),
        isFalse,
      );
      expect(
        StoreAuthMode.register.showsEmailCodeFor(panelNeedsCode: true),
        isTrue,
      );
      expect(
        StoreAuthMode.reset.showsEmailCodeFor(panelNeedsCode: false),
        isTrue,
      );
    });

    test('forgot password belongs to the sign-in form alone', () {
      expect(StoreAuthMode.signIn.showsForgotPassword, isTrue);
      expect(StoreAuthMode.register.showsForgotPassword, isFalse);
      expect(StoreAuthMode.reset.showsForgotPassword, isFalse);
    });

    test('the reset form keeps the password field for the new one', () {
      expect(StoreAuthMode.signIn.showsPassword, isTrue);
      expect(StoreAuthMode.register.showsPassword, isTrue);
      expect(StoreAuthMode.reset.showsPassword, isTrue);
    });
  });
}
