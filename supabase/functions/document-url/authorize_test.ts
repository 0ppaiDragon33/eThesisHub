// Run with: deno test supabase/functions/document-url/
//
// These cover the decisions, not the plumbing: who may read a document, and
// which paths are even addressable. The token verification and the Firestore
// reads in `index.ts` need a live project to exercise and are covered by the
// manual checklist in supabase/README.md instead.

import { assertEquals } from "jsr:@std/assert@1";
import {
  CallerFacts,
  mayReadDocument,
  mayReadThesis,
  ThesisFacts,
  thesisIdForPath,
} from "./authorize.ts";

const thesis: ThesisFacts = {
  leaderUid: "leader",
  adviserUid: "adviser",
  panelistUids: ["panelA", "panelB"],
};

const caller = (over: Partial<CallerFacts>): CallerFacts => ({
  uid: "stranger",
  role: "student",
  active: true,
  hasNomination: false,
  ...over,
});

// --- path shape -------------------------------------------------------------

Deno.test("a well-formed chapter path yields its thesis", () => {
  assertEquals(
    thesisIdForPath("theses/t1/chapterI/3f9a-b2.pdf"),
    "t1",
  );
});

Deno.test("a well-formed manuscript path yields its thesis", () => {
  assertEquals(
    thesisIdForPath("theses/t1/manuscript/3f9a-b2.pdf"),
    "t1",
  );
});

Deno.test("traversal out of the theses prefix is refused", () => {
  for (
    const path of [
      "theses/t1/../t2/x.pdf",
      "theses/../../etc/passwd",
      "/theses/t1/c/x.pdf",
      "theses/t1/c/..%2Fx.pdf",
      "theses\\t1\\c\\x.pdf",
      "other-bucket/t1/c/x.pdf",
      "theses/t1/c/x.pdf/extra",
      "theses/t1/c",
      "",
    ]
  ) {
    assertEquals(thesisIdForPath(path), null, `must refuse: ${path}`);
  }
});

Deno.test("an over-long path is refused rather than parsed", () => {
  assertEquals(thesisIdForPath("theses/t1/c/" + "a".repeat(600) + ".pdf"), null);
});

// --- who may read -----------------------------------------------------------

Deno.test("the leader, adviser and panel may read", () => {
  for (const uid of ["leader", "adviser", "panelA", "panelB"]) {
    assertEquals(mayReadThesis(caller({ uid }), thesis), true, uid);
  }
});

Deno.test("an unrelated student may not read", () => {
  assertEquals(mayReadThesis(caller({}), thesis), false);
});

Deno.test("a pending nominee may read before dean approval fills the panel", () => {
  // The nominee is not yet on panelistUids — that array is filled at dean
  // approval — but has been asked for a Conforme and needs the thesis.
  assertEquals(
    mayReadThesis(caller({ uid: "nominee", hasNomination: true }), thesis),
    true,
  );
});

Deno.test("a coordinator and a dean may read any thesis", () => {
  assertEquals(mayReadThesis(caller({ role: "coordinator" }), thesis), true);
  assertEquals(mayReadThesis(caller({ role: "dean" }), thesis), true);
});

Deno.test("a deactivated account may read nothing, whatever its role", () => {
  for (const role of ["student", "faculty", "coordinator", "dean"]) {
    assertEquals(
      mayReadThesis(caller({ uid: "leader", role, active: false }), thesis),
      false,
      role,
    );
  }
});

// --- the dean's chapter exclusion ------------------------------------------

Deno.test("the dean may read the manuscript but NOT a chapter version", () => {
  // firestore.rules excludes the dean from documents/{c}/versions/{n}: a dean
  // sees that a chapter is approved, never its files. If this function were
  // more permissive, that rule would be decorative.
  const dean = caller({ role: "dean" });
  assertEquals(mayReadDocument(dean, thesis, "manuscript"), true);
  assertEquals(mayReadDocument(dean, thesis, "chapterI"), false);
});

Deno.test("the exclusion does not leak to anyone else", () => {
  assertEquals(
    mayReadDocument(caller({ uid: "leader" }), thesis, "chapterI"),
    true,
  );
  assertEquals(
    mayReadDocument(caller({ role: "coordinator" }), thesis, "chapterI"),
    true,
  );
});

Deno.test("an unauthorized caller is refused the manuscript too", () => {
  assertEquals(mayReadDocument(caller({}), thesis, "manuscript"), false);
});

// --- the repository (archived) case ----------------------------------------

Deno.test("an archived manuscript is readable by any active stranger", () => {
  // The repository is meant to be browsed. Once published, the manuscript
  // opens for anyone with an active account, matching archive/{id}'s own
  // activeUser() read rule.
  assertEquals(
    mayReadDocument(caller({}), thesis, "manuscript", { isArchived: true }),
    true,
  );
});

Deno.test("archiving does NOT make chapter drafts public", () => {
  // Only the published manuscript becomes browsable; the working chapters
  // stay members-only even after the thesis is archived.
  assertEquals(
    mayReadDocument(caller({}), thesis, "chapterII", { isArchived: true }),
    false,
  );
});

Deno.test("a deactivated account cannot browse the archive", () => {
  assertEquals(
    mayReadDocument(caller({ active: false }), thesis, "manuscript", {
      isArchived: true,
    }),
    false,
  );
});

Deno.test("without the archive flag a stranger is still refused", () => {
  // Same caller, same manuscript, thesis not archived: the members-only
  // rule applies. This pins that the archive opening is gated on the flag,
  // not the document id.
  assertEquals(
    mayReadDocument(caller({}), thesis, "manuscript", { isArchived: false }),
    false,
  );
});

// --- cross-thesis -----------------------------------------------------------

Deno.test("being on thesis A grants nothing on thesis B", () => {
  const otherThesis: ThesisFacts = {
    leaderUid: "someoneElse",
    adviserUid: "anotherAdviser",
    panelistUids: [],
  };
  for (const uid of ["leader", "adviser", "panelA"]) {
    assertEquals(mayReadThesis(caller({ uid }), otherThesis), false, uid);
  }
});
