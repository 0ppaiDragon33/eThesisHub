// CORS for a function a browser calls directly.
//
// The Flutter app runs on localhost in development and on the hosting
// domain in production; this function runs on *.supabase.co. Every call is
// therefore cross-origin, and because supabase-js sends `authorization` and
// `content-type` — neither of which is a CORS "simple" header — the browser
// sends an OPTIONS preflight first and refuses to make the real request
// unless that preflight comes back 2xx with the right allow-lists.
//
// Supabase does not add any of this for you. A function that only handles
// POST answers the preflight 405, and the browser reports "Response to
// preflight request doesn't pass access control check: It does not have
// HTTP ok status" — which says nothing about the function being otherwise
// correct.
//
// `*` for the origin is safe here and is the documented Supabase default.
// CORS is not this function's access control: it authenticates from an
// explicit `Authorization: Bearer <Firebase ID token>` header, which a
// browser never attaches to a cross-origin request on its own. There are no
// cookies and no `Access-Control-Allow-Credentials`, so a wildcard origin
// grants a hostile page nothing it could not already do from a server.

export const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  // supabase-js attaches apikey and x-client-info alongside the two obvious
  // ones. A header missing from this list fails the preflight even when the
  // status is 200.
  "access-control-allow-headers":
    "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  // Lets the browser skip the preflight on repeat opens within the day.
  "access-control-max-age": "86400",
};

/// Answers a CORS preflight, or returns null when this is a real request.
///
/// 204 rather than 200: there is no body to send, and the browser only reads
/// the status and the headers.
export function preflightResponse(req: Request): Response | null {
  if (req.method !== "OPTIONS") return null;
  return new Response(null, { status: 204, headers: CORS_HEADERS });
}

/// The function's only response builder.
///
/// It lives here, rather than in `index.ts`, so that returning a response
/// without the allow-origin header is not something a later edit can do by
/// accident: answering the preflight is only half the job, and a POST whose
/// own response lacks this header is discarded by the browser after it has
/// already been fetched.
export const json = (status: number, body: unknown): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "content-type": "application/json" },
  });
