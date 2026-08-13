class AppConfig {
  // TEMPORARILY DISABLED FOR TESTING — MUST BE RESTORED TO true BEFORE DEFENSE.
  //
  // Disabled on 2026-08-13 so the invite flow could be tested end to end with
  // non-institutional addresses (e.g. Gmail + aliases) without waiting on a
  // second ISUFST account holder.
  //
  // Restoring it is a one-word change here, or: git revert <this commit>.
  // Scope and Limitations in the manuscript states that registration is
  // restricted to institutional addresses — that claim is FALSE while this
  // is false.
  static const bool enforceInstitutionalDomain = false;
  static const String institutionalDomain = 'isufst.edu.ph';

  static const String supabaseUrl = 'https://wevvsskextznmstjfmfo.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_p18CxHivLd7G6FPuYG4Czw_3oXHnvq1';
  static const String documentsBucket = 'thesis-documents';
}