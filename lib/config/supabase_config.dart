/// Supabase project connection details.
///
/// Both values are safe to embed client-side: access to data is enforced
/// by row-level security policies in the database, not by keeping these
/// secret. Find them in the Supabase dashboard under
/// Project Settings > API.
///
/// No default project here on purpose - every build (local, PR/main
/// preview, and production release) must pass these explicitly via
/// --dart-define-from-file=env/staging.json or env/prod.json (see
/// .vscode/launch.json / .claude/launch.json for local runs, and the
/// deploy workflows for CI), so which project you're pointed at is always
/// a deliberate choice rather than an easy-to-miss fallback. main.dart
/// fails fast at startup if either value is missing.
///
/// The URL must be the bare project root with no path or trailing slash
/// (e.g. https://xxxx.supabase.co) - this client appends /auth/v1,
/// /rest/v1, etc. itself, so a URL copied from a dashboard field that
/// already includes one of those suffixes produces malformed doubled
/// paths (.../rest/v1//auth/v1/signup) and every request 404s.
class SupabaseConfig {
  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
}
