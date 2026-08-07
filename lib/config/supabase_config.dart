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
