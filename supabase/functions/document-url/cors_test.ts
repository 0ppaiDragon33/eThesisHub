// Run with: deno test supabase/functions/document-url/
//
// The browser talks to this function cross-origin: the app is served from
// localhost (or the hosting domain) and the function lives on
// *.supabase.co. supabase-js sends `authorization` and `content-type`, and
// both are non-simple headers, so every call is preceded by a CORS
// preflight. A function that answers the preflight with anything but a 2xx
// is unreachable from a browser no matter how correct its authorization is.
//
// That is not hypothetical: it is the bug these tests were written for.
// "Response to preflight request doesn't pass access control check: It does
// not have HTTP ok status" is what a 405 on OPTIONS looks like from the
// other side.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { CORS_HEADERS, json, preflightResponse } from "./cors.ts";

const request = (method: string) =>
  new Request("https://example.supabase.co/functions/v1/document-url", {
    method,
  });

Deno.test("a preflight is answered with an ok status, not 405", () => {
  const res = preflightResponse(request("OPTIONS"));

  assert(res !== null, "OPTIONS must be recognised as a preflight");
  // The whole bug in one assertion: the browser requires a 2xx here.
  assert(
    res.status >= 200 && res.status < 300,
    `preflight answered ${res.status}, which the browser rejects`,
  );
});

Deno.test("the preflight allows the headers supabase-js actually sends", () => {
  const res = preflightResponse(request("OPTIONS"))!;
  const allowed = (res.headers.get("access-control-allow-headers") ?? "")
    .toLowerCase();

  // Omitting any one of these fails the preflight even with a 200, because
  // the browser checks the requested headers against this list.
  for (const header of ["authorization", "content-type", "apikey"]) {
    assert(allowed.includes(header), `preflight does not allow "${header}"`);
  }
  assert(
    (res.headers.get("access-control-allow-methods") ?? "").includes("POST"),
    "preflight does not allow the POST the client is about to make",
  );
});

Deno.test("a POST is not mistaken for a preflight", () => {
  // Returning a preflight response here would short-circuit every real
  // request and the function would never sign anything.
  assertEquals(preflightResponse(request("POST")), null);
});

Deno.test("every real response carries the allow-origin header", async () => {
  // Answering the preflight is only half of it. Without this header on the
  // POST's own response the browser discards the body it just fetched, so
  // the caller still sees a CORS failure.
  const res = json(403, { error: "forbidden" });

  assertEquals(res.headers.get("access-control-allow-origin"), "*");
  assertEquals(res.status, 403);
  assertEquals(res.headers.get("content-type"), "application/json");
  assertEquals(await res.json(), { error: "forbidden" });
});

Deno.test("the allow-origin header is present in the shared set", () => {
  assertEquals(CORS_HEADERS["access-control-allow-origin"], "*");
});
