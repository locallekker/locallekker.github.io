// Pre-release configuration check for the bundled `.env` file.
//
// Usage:
//   dart run tool/check_release_config.dart            # checks .env for a release build
//   dart run tool/check_release_config.dart --dev      # relaxes live-mode checks
//   dart run tool/check_release_config.dart path/.env  # check a different file
//
// Only key names and problems are printed, never values. Exits with code 1
// when any error is found so it can gate build scripts and CI.
import 'dart:io';

enum ConfigSeverity { error, warning }

class ConfigIssue {
  final ConfigSeverity severity;
  final String key;
  final String message;

  const ConfigIssue(this.severity, this.key, this.message);

  @override
  String toString() =>
      '${severity == ConfigSeverity.error ? 'ERROR' : 'WARN '}  $key: $message';
}

/// Parses simple `KEY=VALUE` lines, ignoring comments and blank lines and
/// stripping matching surrounding quotes.
Map<String, String> parseEnv(String contents) {
  final result = <String, String>{};
  for (final rawLine in contents.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    final key = line.substring(0, eq).trim();
    var value = line.substring(eq + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    result[key] = value;
  }
  return result;
}

List<ConfigIssue> validateReleaseConfig(
  Map<String, String> env, {
  bool release = true,
}) {
  final issues = <ConfigIssue>[];
  String value(String key) => (env[key] ?? '').trim();
  bool isTrue(String key) => value(key).toLowerCase() == 'true';
  void error(String key, String msg) =>
      issues.add(ConfigIssue(ConfigSeverity.error, key, msg));
  void warn(String key, String msg) =>
      issues.add(ConfigIssue(ConfigSeverity.warning, key, msg));

  for (final key in const ['SUPABASE_URL', 'SUPABASE_ANON_KEY']) {
    if (value(key).isEmpty) error(key, 'is required but missing or empty.');
  }

  final supabaseUrl = value('SUPABASE_URL');
  if (supabaseUrl.isNotEmpty) {
    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      error('SUPABASE_URL', 'is not a valid URL.');
    } else if (release &&
        (uri.scheme != 'https' ||
            uri.host == 'localhost' ||
            uri.host == '127.0.0.1' ||
            uri.host == '10.0.2.2')) {
      error('SUPABASE_URL', 'must be a public https URL for release builds.');
    }
  }

  if (env.containsKey('PAYSTACK_SECRET_KEY')) {
    error(
      'PAYSTACK_SECRET_KEY',
      'must not be in the app .env (it would ship inside the APK). '
          'Set it as a Supabase Edge Function secret instead.',
    );
  }

  if (release && isTrue('PAYSTACK_DEVELOPMENT_MODE')) {
    error(
      'PAYSTACK_DEVELOPMENT_MODE',
      'is true; real Paystack payments would be skipped in a release build.',
    );
  }

  final publicKey = value('PAYSTACK_PUBLIC_KEY');
  if (publicKey.isEmpty) {
    warn('PAYSTACK_PUBLIC_KEY', 'is missing or empty.');
  } else if (!publicKey.startsWith('pk_')) {
    error('PAYSTACK_PUBLIC_KEY', 'does not look like a Paystack public key.');
  } else if (release && publicKey.startsWith('pk_test_')) {
    warn('PAYSTACK_PUBLIC_KEY', 'is a TEST key in a release build.');
  }

  if (release && isTrue('PAYSTACK_SANDBOX')) {
    warn('PAYSTACK_SANDBOX', 'is true in a release build.');
  }

  final callbackUrl = value('PAYSTACK_CALLBACK_URL');
  if (callbackUrl.isNotEmpty) {
    final uri = Uri.tryParse(callbackUrl);
    if (uri == null || !uri.hasScheme) {
      error('PAYSTACK_CALLBACK_URL', 'is not a valid URL.');
    } else if (uri.scheme == 'http') {
      warn('PAYSTACK_CALLBACK_URL', 'uses http; Paystack requires https or an app deep link.');
    }
  }

  final googlePay = value('PAYSTACK_GOOGLE_PAY_ENABLED').toLowerCase();
  if (googlePay.isNotEmpty && googlePay != 'true' && googlePay != 'false') {
    warn('PAYSTACK_GOOGLE_PAY_ENABLED', "should be 'true' or 'false'; any other value disables it.");
  }

  return issues;
}

void main(List<String> args) {
  final release = !args.contains('--dev');
  final path = args.firstWhere((a) => !a.startsWith('--'), orElse: () => '.env');
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('ERROR  $path not found.');
    exitCode = 1;
    return;
  }

  final env = parseEnv(file.readAsStringSync());
  final issues = validateReleaseConfig(env, release: release);

  stdout.writeln('Checking $path (${release ? 'release' : 'dev'} mode, ${env.length} keys)');
  if (env['PAYSTACK_GOOGLE_PAY_ENABLED']?.trim().toLowerCase() == 'true') {
    stdout.writeln(
      'INFO   PAYSTACK_GOOGLE_PAY_ENABLED is on: confirm Google Pay AND Card are '
      'active under Paystack > Settings > Payments.',
    );
  }
  for (final issue in issues) {
    stdout.writeln(issue);
  }

  final errors = issues.where((i) => i.severity == ConfigSeverity.error).length;
  stdout.writeln(errors == 0
      ? 'OK: no blocking problems (${issues.length} warning(s)).'
      : 'FAILED: $errors error(s), ${issues.length - errors} warning(s).');
  if (errors > 0) exitCode = 1;
}
