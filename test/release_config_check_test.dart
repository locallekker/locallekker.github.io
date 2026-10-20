import 'package:flutter_test/flutter_test.dart';

import '../tool/check_release_config.dart';

Map<String, String> _validEnv() => {
      'SUPABASE_URL': 'https://example.supabase.co',
      'SUPABASE_ANON_KEY': 'anon',
      'PAYSTACK_PUBLIC_KEY': 'pk_live_abc',
      'PAYSTACK_SANDBOX': 'false',
      'PAYSTACK_DEVELOPMENT_MODE': 'false',
      'PAYSTACK_MONTHLY_PLAN_CODE': 'PLN_x',
      'PAYSTACK_CALLBACK_URL': 'https://locallekker.github.io/payment/callback',
      'PAYSTACK_GOOGLE_PAY_ENABLED': 'false',
    };

Iterable<String> _keysWith(List<ConfigIssue> issues, ConfigSeverity s) =>
    issues.where((i) => i.severity == s).map((i) => i.key);

void main() {
  test('parseEnv handles comments, blanks and quotes', () {
    final env = parseEnv('# c\n\nA=1\nB="two"\r\nC=\'3\'\nD=x=y\nbad\n');
    expect(env, {'A': '1', 'B': 'two', 'C': '3', 'D': 'x=y'});
  });

  test('a valid live config has no issues', () {
    expect(validateReleaseConfig(_validEnv()), isEmpty);
  });

  test('missing Supabase keys are errors', () {
    final env = _validEnv()
      ..remove('SUPABASE_URL')
      ..['SUPABASE_ANON_KEY'] = '';
    expect(
      _keysWith(validateReleaseConfig(env), ConfigSeverity.error),
      containsAll(['SUPABASE_URL', 'SUPABASE_ANON_KEY']),
    );
  });

  test('a Paystack secret key in the app env is an error', () {
    final env = _validEnv()..['PAYSTACK_SECRET_KEY'] = 'sk_live_x';
    final issues = validateReleaseConfig(env);
    expect(_keysWith(issues, ConfigSeverity.error), contains('PAYSTACK_SECRET_KEY'));
    expect(issues.join('\n'), isNot(contains('sk_live_x')));
  });

  test('development mode and localhost block release but not dev checks', () {
    final env = _validEnv()
      ..['PAYSTACK_DEVELOPMENT_MODE'] = 'true'
      ..['SUPABASE_URL'] = 'http://localhost:54321';
    expect(
      _keysWith(validateReleaseConfig(env), ConfigSeverity.error),
      containsAll(['PAYSTACK_DEVELOPMENT_MODE', 'SUPABASE_URL']),
    );
    expect(
      _keysWith(validateReleaseConfig(env, release: false), ConfigSeverity.error),
      isEmpty,
    );
  });

  test('test keys and sandbox only warn in release', () {
    final env = _validEnv()
      ..['PAYSTACK_PUBLIC_KEY'] = 'pk_test_abc'
      ..['PAYSTACK_SANDBOX'] = 'true';
    final issues = validateReleaseConfig(env);
    expect(_keysWith(issues, ConfigSeverity.error), isEmpty);
    expect(
      _keysWith(issues, ConfigSeverity.warning),
      containsAll(['PAYSTACK_PUBLIC_KEY', 'PAYSTACK_SANDBOX']),
    );
  });

  test('an unrecognised Google Pay flag warns', () {
    final env = _validEnv()..['PAYSTACK_GOOGLE_PAY_ENABLED'] = 'yes';
    expect(
      _keysWith(validateReleaseConfig(env), ConfigSeverity.warning),
      contains('PAYSTACK_GOOGLE_PAY_ENABLED'),
    );
  });
}
