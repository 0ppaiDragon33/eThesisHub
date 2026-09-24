// Authorization decisions for thesis documents, as pure functions.
//
// Split out from `index.ts` so the rules that decide who may read a document
// can be tested without a network, a Firebase project, or a Supabase
// deployment. `index.ts` does the I/O; everything that decides anything
// lives here.

/// The shape of a thesis document, reduced to the fields that decide access.
export interface ThesisFacts {
  leaderUid: string | null;
  adviserUid: string | null;
  panelistUids: string[];
}

/// The caller, as Firestore knows them.
export interface CallerFacts {
  uid: string;
  role: string | null;
  active: boolean;
  /// Whether a `theses/{id}/nominations/{uid}` document exists. A nominee who
  /// has been asked for a Conforme can read the thesis before they are on
  /// `panelistUids` — that array is only filled at dean approval.
  hasNomination: boolean;
}

/// Storage paths this function will sign, and the thesis each belongs to.
///
/// Only two shapes exist, both written by `StoragePaths`:
///   theses/{thesisId}/{documentId}/{uuid}.{ext}
///   theses/{thesisId}/manuscript/{uuid}.{ext}
///
/// Anything else is refused rather than guessed at. The segment check is the
/// path-traversal defence: `..`, absolute paths, backslashes, encoded
/// separators and empty segments all fail it, so a caller cannot walk out of
/// the `theses/` prefix into another bucket key.
const SEGMENT = /^[A-Za-z0-9][A-Za-z0-9_-]*$/;
const FILENAME = /^[A-Za-z0-9][A-Za-z0-9_-]*\.[A-Za-z0-9]{1,8}$/;

export function thesisIdForPath(path: string): string | null {
  // Reject before splitting: a path containing a traversal token is never
  // repaired into a valid one, and normalising it here would only create a
  // second, subtly different notion of what the path means.
  if (path.length === 0 || path.length > 512) return null;
  if (path.includes("..") || path.includes("\\") || path.includes("%")) {
    return null;
  }
  if (path.startsWith("/")) return null;

  const parts = path.split("/");
  if (parts.length !== 4) return null;

  const [root, thesisId, documentId, filename] = parts;
  if (root !== "theses") return null;
  if (!SEGMENT.test(thesisId)) return null;
  if (!SEGMENT.test(documentId)) return null;
  if (!FILENAME.test(filename)) return null;

  return thesisId;
}

/// Whether [caller] may read documents belonging to [thesis].
///
/// This mirrors `mayReadThesis()` in `firestore.rules`, deliberately: a
/// document's audience is the thesis's audience, and two different answers to
/// "who is on this thesis" is how a file becomes readable by someone the
/// record says it is not for.
///
/// The dean is included here where the chapter-version rule excludes them.
/// That is not an oversight — see `mayReadDocument`, which applies the
/// narrower rule for chapter files.
export function mayReadThesis(
  caller: CallerFacts,
  thesis: ThesisFacts,
): boolean {
  if (!caller.active) return false;
  if (caller.role === "coordinator" || caller.role === "dean") return true;
  return (
    thesis.leaderUid === caller.uid ||
    thesis.adviserUid === caller.uid ||
    thesis.panelistUids.includes(caller.uid) ||
    caller.hasNomination
  );
}

/// Whether [caller] may read the file at [documentId] on [thesis].
///
/// `firestore.rules` draws one distinction the thesis-level check does not:
/// on `documents/{chapterId}/versions/{n}` the dean is excluded, because a
/// dean sees that a chapter is approved and never its files. The manuscript
/// is not a chapter version and carries no such exclusion.
///
/// Keeping that distinction here matters: if this function were more
/// permissive than the rules, a dean who cannot read a version's metadata
/// could still fetch the file it points at, and the rule would be decorative.
///
/// [isArchived] is the repository case. Once a thesis is published to the
/// `archive` collection its manuscript is browsable by any active reader —
/// `firestore.rules` makes `archive/{id}` itself readable by `activeUser()`,
/// and a published manuscript with no way to open it is not a repository.
/// This applies ONLY to the manuscript, and ONLY once archived: a chapter
/// draft never becomes public this way, and an in-progress manuscript stays
/// members-only. "Completed" does not make every file public — it makes the
/// one published file readable.
export function mayReadDocument(
  caller: CallerFacts,
  thesis: ThesisFacts,
  documentId: string,
  { isArchived = false }: { isArchived?: boolean } = {},
): boolean {
  if (isArchived && documentId === "manuscript" && caller.active) return true;
  if (!mayReadThesis(caller, thesis)) return false;
  if (documentId !== "manuscript" && caller.role === "dean") return false;
  return true;
}

/// How long a minted URL stays valid, in seconds.
///
/// Short enough that a leaked link is not a lasting grant, long enough to
/// survive opening a PDF on a slow connection. A viewer that needs longer
/// asks again — the client holds the path, never the URL.
export const SIGNED_URL_TTL_SECONDS = 120;

// ---------------------------------------------------------------------------
// Personal files (My files)
// ---------------------------------------------------------------------------

/// The owner of a path in someone's My files, or null for any other path.
///
/// Exactly one shape exists, written by `StoragePaths.personalFile`:
///   personal/{uid}/{fileId}/{generated}.{ext}
/// with the same traversal defence as [thesisIdForPath].
export function personalOwnerForPath(path: string): string | null {
  if (path.length === 0 || path.length > 512) return null;
  if (path.includes("..") || path.includes("\\") || path.includes("%")) {
    return null;
  }
  if (path.startsWith("/")) return null;

  const parts = path.split("/");
  if (parts.length !== 4) return null;

  const [root, uid, fileId, filename] = parts;
  if (root !== "personal") return null;
  if (!SEGMENT.test(uid)) return null;
  if (!SEGMENT.test(fileId)) return null;
  if (!FILENAME.test(filename)) return null;

  return uid;
}

/// Whether [caller] may open or delete a file in [ownerUid]'s My files.
///
/// The owner alone, while active. No role reaches another person's personal
/// files, the Dean and the Research Coordinator included: these are one
/// person's working files, not thesis records (spec E9).
export function mayUsePersonalFile(
  caller: CallerFacts,
  ownerUid: string,
): boolean {
  return caller.active && caller.uid === ownerUid;
}

export type Action = "sign" | "delete";

/// What a request is asking for, decided from its body alone.
export type Route =
  | { kind: "thesis"; thesisId: string; documentId: string }
  | { kind: "personal"; action: Action; ownerUid: string }
  | { kind: "error"; status: 400 | 403; error: string };

/// Routes a request body to the check it needs.
///
/// A thesis document can only be signed. Nothing in the app deletes one, so
/// a delete on a thesis path is refused outright rather than attempted.
export function routeRequest(path: unknown, action: unknown = "sign"): Route {
  if (typeof path !== "string") {
    return { kind: "error", status: 400, error: "bad_request" };
  }
  if (action !== "sign" && action !== "delete") {
    return { kind: "error", status: 400, error: "bad_action" };
  }

  const ownerUid = personalOwnerForPath(path);
  if (ownerUid !== null) return { kind: "personal", action, ownerUid };

  const thesisId = thesisIdForPath(path);
  if (thesisId === null) {
    return { kind: "error", status: 400, error: "bad_path" };
  }
  if (action === "delete") {
    return { kind: "error", status: 403, error: "forbidden" };
  }
  return { kind: "thesis", thesisId, documentId: path.split("/")[2] };
}
