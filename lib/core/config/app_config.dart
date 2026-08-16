class AppConfig {
  /// Whether self-registration is restricted to the institution's domain.
  ///
  /// TEMPORARILY OFF so the five roles can be exercised end to end from a
  /// handful of ordinary mail accounts — there are not enough institutional
  /// addresses on hand to sign in as a student, an adviser, a panel member,
  /// a coordinator and the dean at once.
  ///
  /// SET THIS BACK TO `true` BEFORE THE DEFENCE. While it is false anyone
  /// with any address can register as a student. That is contained — it is
  /// this project's own Firebase instance, not a public deployment, and
  /// faculty roles are still unreachable without an invite a coordinator
  /// issues — but it is not what the manuscript describes.
  ///
  /// This is a client-side check only. `firestore.rules` never inspected the
  /// domain, so flipping this changes nothing about the deployed
  /// authorization boundary and needs no redeploy. What it does change is
  /// who may create an account.
  ///
  /// While it is false, [InstitutionalDomainNotice] shows on the register
  /// screen, so the relaxation announces itself rather than being discovered
  /// during a demo.
  static const bool enforceInstitutionalDomain = true;
  static const String institutionalDomain = 'isufst.edu.ph';

  static const String supabaseUrl = 'https://wevvsskextznmstjfmfo.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_p18CxHivLd7G6FPuYG4Czw_3oXHnvq1';
  static const String documentsBucket = 'thesis-documents';
}