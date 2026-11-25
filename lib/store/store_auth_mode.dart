/// Which form the shop's account sheet shows, and what the switch at its foot
/// does from there.
///
/// The sheet is one widget with three faces, so the transitions live here
/// instead of inside `setState`, where a test can reach them.
enum StoreAuthMode { signIn, register, reset }

extension StoreAuthModeSwitch on StoreAuthMode {
  /// Cycles sign-in ↔ register, and returns to sign-in from reset: an account
  /// holder who mistyped a password wants the sign-in form back, not to be
  /// offered registration.
  StoreAuthMode toggled() => switch (this) {
    StoreAuthMode.signIn => StoreAuthMode.register,
    StoreAuthMode.register => StoreAuthMode.signIn,
    StoreAuthMode.reset => StoreAuthMode.signIn,
  };

  bool get showsInvite => this == StoreAuthMode.register;

  bool get showsEmailCode => this != StoreAuthMode.signIn;

  bool get showsForgotPassword => this == StoreAuthMode.signIn;

  /// The reset form reuses the field for the new password.
  bool get showsPassword => true;

  /// The panel's human check guards registration alone, so signing in and
  /// resetting a password never draw it.
  bool showsCaptchaFor({required bool panelAsks}) =>
      panelAsks && this == StoreAuthMode.register;

  /// Registration may follow the panel; a reset always needs the mailed code.
  bool showsEmailCodeFor({required bool panelNeedsCode}) =>
      this == StoreAuthMode.reset ||
      (this == StoreAuthMode.register && panelNeedsCode);
}

StoreAuthMode storeAuthMode({required bool register, required bool reset}) {
  if (reset) return StoreAuthMode.reset;
  return register ? StoreAuthMode.register : StoreAuthMode.signIn;
}
