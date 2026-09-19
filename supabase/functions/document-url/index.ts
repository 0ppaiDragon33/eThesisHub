// Mints a short-lived signed URL for one thesis document, for one caller who
// is authorized to read it.
//
// WHY THIS EXISTS
//
// EThesisHub authenticates with Firebase Auth. The Supabase client is
// initialised with the publishable key and no Supabase session, so every
// request the app makes to Supabase Storage arrives as the same anonymous
// principal. No RLS policy can tell one reader from another, which means a
// private bucket is all-or-nothing and a signed URL minted in the client is
// worthless — any client could sign any path.
//
// This function is the one place that holds the service-role key and the one
// place that can answer "is THIS reader allowed THIS file". It verifies the
// caller's Firebase ID token, asks Firestore what the thesis says, applies
// the same access rule `firestore.rules` applies, and only then signs.
//
// The bucket must be PRIVATE for any of this to mean anything. With a public
// bucket the object is fetchable without a signature and this function is
// decorative. See supabase/README.md.
//
// SECRETS (set with `supabase secrets set`, never committed):
//   SUPABASE_URL                 - the project URL
//   SUPABASE_SERVICE_ROLE_KEY    - service role; signs URLs. Never leaves here.
//   FIREBASE_PROJECT_ID          - e.g. ethesishub-43a04
//   GCP_SERVICE_ACCOUNT_JSON     - a service account with Firestore read access

import { createClient } from "jsr:@supabase/supabase-js@2";
import { create, getNumericDate, verify } from "jsr:@zaubrik/djwt@3";
import {
  CallerFacts,
  mayReadDocument,
  SIGNED_URL_TTL_SECONDS,
  ThesisFacts,
  thesisIdForPath,
} from "./authorize.ts";
import { json, preflightResponse } from "./cors.ts";

const DOCUMENTS_BUCKET = "thesis-documents";

const env = (name: string): string => {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`missing secret: ${name}`);
  return v;
};

// ---------------------------------------------------------------------------
// Firebase ID token verification
// ---------------------------------------------------------------------------

/// Google's public keys for Firebase ID tokens, cached until they expire.
///
/// Fetching these on every request would add a round trip to every document
/// open; never refreshing them would break the function the next time Google
/// rotates. `Cache-Control: max-age` on the response says when to look again.
let keyCache: { keys: Record<string, CryptoKey>; expiresAt: number } | null =
  null;

async function googleKeys(): Promise<Record<string, CryptoKey>> {
  if (keyCache && Date.now() < keyCache.expiresAt) return keyCache.keys;

  const res = await fetch(
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
  );
  if (!res.ok) throw new Error("could not fetch Google signing keys");

  const body = await res.json() as { keys: Array<JsonWebKey & { kid: string }> };
  const keys: Record<string, CryptoKey> = {};
  for (const jwk of body.keys) {
    keys[jwk.kid] = await crypto.subtle.importKey(
      "jwk",
      jwk,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"],
    );
  }

  const maxAge = Number(
    /max-age=(\d+)/.exec(res.headers.get("cache-control") ?? "")?.[1] ?? 3600,
  );
  keyCache = { keys, expiresAt: Date.now() + maxAge * 1000 };
  return keys;
}

interface FirebaseClaims {
  uid: string;
  emailVerified: boolean;
}

/// Verifies a Firebase ID token and returns its claims.
///
/// Every check here is load-bearing. Skipping the audience check would accept
/// a token minted for a different Firebase project; skipping `auth_time`
/// would accept a token whose subject is empty. Returns null rather than
/// throwing, so the caller answers 401 without distinguishing "malformed"
/// from "expired" — that distinction only helps someone probing.
async function verifyFirebaseToken(
  token: string,
  projectId: string,
): Promise<FirebaseClaims | null> {
  try {
    const [rawHeader] = token.split(".");
    const header = JSON.parse(atob(rawHeader.replace(/-/g, "+").replace(/_/g, "/")));
    const key = (await googleKeys())[header.kid];
    if (!key) return null;

    // djwt checks the signature and `exp`/`nbf` for us.
    const payload = await verify(token, key) as Record<string, unknown>;

    const issuer = `https://securetoken.google.com/${projectId}`;
    if (payload.aud !== projectId) return null;
    if (payload.iss !== issuer) return null;

    const sub = payload.sub;
    if (typeof sub !== "string" || sub.length === 0) return null;

    // A token issued in the future is not one we minted a moment ago.
    const authTime = payload.auth_time;
    if (typeof authTime !== "number" || authTime > Date.now() / 1000 + 60) {
      return null;
    }

    return { uid: sub, emailVerified: payload.email_verified === true };
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Firestore reads
// ---------------------------------------------------------------------------

/// A Google OAuth access token for the Firestore REST API, cached until it
/// is close to expiring.
let tokenCache: { token: string; expiresAt: number } | null = null;

async function firestoreAccessToken(): Promise<string> {
  if (tokenCache && Date.now() < tokenCache.expiresAt - 60_000) {
    return tokenCache.token;
  }

  const sa = JSON.parse(env("GCP_SERVICE_ACCOUNT_JSON")) as {
    client_email: string;
    private_key: string;
  };

  // The PEM arrives with literal \n in the JSON; PKCS8 import needs the raw
  // DER between the armour lines.
  const pem = sa.private_key.replace(/\\n/g, "\n");
  const der = Uint8Array.from(
    atob(pem.replace(/-----[^-]+-----/g, "").replace(/\s/g, "")),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const assertion = await create(
    { alg: "RS256", typ: "JWT" },
    {
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/datastore",
      aud: "https://oauth2.googleapis.com/token",
      exp: getNumericDate(3600),
      iat: getNumericDate(0),
    },
    key,
  );

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!res.ok) throw new Error("could not mint a Firestore access token");

  const body = await res.json() as { access_token: string; expires_in: number };
  tokenCache = {
    token: body.access_token,
    expiresAt: Date.now() + body.expires_in * 1000,
  };
  return body.access_token;
}

/// Unwraps one Firestore REST value into a plain JS value.
// deno-lint-ignore no-explicit-any
function unwrap(field: any): unknown {
  if (field === undefined || field === null) return null;
  if ("stringValue" in field) return field.stringValue;
  if ("booleanValue" in field) return field.booleanValue;
  if ("integerValue" in field) return Number(field.integerValue);
  if ("nullValue" in field) return null;
  if ("arrayValue" in field) {
    return (field.arrayValue.values ?? []).map(unwrap);
  }
  return null;
}

async function getDoc(
  projectId: string,
  path: string,
): Promise<Record<string, unknown> | null> {
  const token = await firestoreAccessToken();
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${path}`,
    { headers: { authorization: `Bearer ${token}` } },
  );
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`Firestore read failed: ${res.status}`);

  const body = await res.json() as { fields?: Record<string, unknown> };
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(body.fields ?? {})) out[k] = unwrap(v);
  return out;
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (req) => {
  // Before anything else: the browser will not send the real request until
  // this preflight is answered, so an authorization check here would never
  // run. See cors.ts.
  const preflight = preflightResponse(req);
  if (preflight) return preflight;

  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const auth = req.headers.get("authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json(401, { error: "unauthenticated" });

  let path: string;
  try {
    const body = await req.json() as { path?: unknown };
    if (typeof body.path !== "string") return json(400, { error: "bad_request" });
    path = body.path;
  } catch {
    return json(400, { error: "bad_request" });
  }

  // Shape first: an unparseable path is refused before it costs a token
  // verification, a Firestore read, or a signature.
  const thesisId = thesisIdForPath(path);
  if (thesisId === null) return json(400, { error: "bad_path" });
  const documentId = path.split("/")[2];

  const projectId = env("FIREBASE_PROJECT_ID");
  const claims = await verifyFirebaseToken(auth.slice(7), projectId);
  if (!claims) return json(401, { error: "unauthenticated" });
  if (!claims.emailVerified) return json(403, { error: "unverified" });

  // The archive read is only worth paying for on a manuscript: a chapter
  // draft is never made public by archiving, so its authorization never
  // depends on the archive document.
  const wantsManuscript = documentId === "manuscript";

  const [thesisDoc, userDoc, nomination, archiveDoc] = await Promise.all([
    getDoc(projectId, `theses/${thesisId}`),
    getDoc(projectId, `users/${claims.uid}`),
    getDoc(projectId, `theses/${thesisId}/nominations/${claims.uid}`),
    wantsManuscript
      ? getDoc(projectId, `archive/${thesisId}`)
      : Promise.resolve(null),
  ]);

  if (thesisDoc === null || userDoc === null) {
    // Deliberately the same answer as an unauthorized read: whether a given
    // thesis id exists is not something an outsider should be able to probe.
    return json(403, { error: "forbidden" });
  }

  const thesis: ThesisFacts = {
    leaderUid: (thesisDoc.leaderUid as string | null) ?? null,
    adviserUid: (thesisDoc.adviserUid as string | null) ?? null,
    panelistUids: ((thesisDoc.panelistUids as unknown[]) ?? []).filter(
      (u): u is string => typeof u === "string",
    ),
  };
  const caller: CallerFacts = {
    uid: claims.uid,
    role: (userDoc.role as string | null) ?? null,
    active: userDoc.active === true,
    hasNomination: nomination !== null,
  };

  if (
    !mayReadDocument(caller, thesis, documentId, {
      isArchived: archiveDoc !== null,
    })
  ) {
    return json(403, { error: "forbidden" });
  }

  const supabase = createClient(
    env("SUPABASE_URL"),
    env("SUPABASE_SERVICE_ROLE_KEY"),
  );
  const { data, error } = await supabase.storage
    .from(DOCUMENTS_BUCKET)
    .createSignedUrl(path, SIGNED_URL_TTL_SECONDS);

  if (error || !data) return json(502, { error: "sign_failed" });

  return json(200, { url: data.signedUrl, expiresIn: SIGNED_URL_TTL_SECONDS });
});
