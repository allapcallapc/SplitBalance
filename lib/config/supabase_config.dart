/// Supabase project connection details.
///
/// Both values are safe to embed client-side: access to data is enforced
/// by row-level security policies in the database, not by keeping these
/// secret. Find them in the Supabase dashboard under
/// Project Settings > API.
///
/// Defaults to the production project. The main-branch and PR preview
/// deploy workflows override these via --dart-define to point at a
/// separate staging project instead, so previews never touch prod data.
///
/// The URL must be the bare project root with no path or trailing slash
/// (e.g. https://xxxx.supabase.co) - this client appends /auth/v1,
/// /rest/v1, etc. itself, so a URL copied from a dashboard field that
/// already includes one of those suffixes produces malformed doubled
/// paths (.../rest/v1//auth/v1/signup) and every request 404s.
class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://mzmefjrykettcyttbwjp.supabase.co',
  );
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_Mo36d1snz6IuyDHjsVMXtA__jBWfH0M',
  );
}
