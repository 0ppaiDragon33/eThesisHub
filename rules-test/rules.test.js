import { readFileSync } from "node:fs";
import test from "node:test";
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from "@firebase/rules-unit-testing";
import {
  doc,
  getDoc,
  getDocs,
  collection,
  collectionGroup,
  query,
  where,
  setDoc,
  updateDoc,
  deleteDoc,
  serverTimestamp,
  writeBatch,
  runTransaction,
  Timestamp,
} from "firebase/firestore";

const env = await initializeTestEnvironment({
  projectId: "ethesishub-rules-test",
  firestore: {
    rules: readFileSync("../firestore.rules", "utf8"),
    host: "127.0.0.1",
    port: 8080,
  },
});

const student = env
  .authenticatedContext("student-uid", {
    email: "student@isufst.edu.ph",
    email_verified: true,
  })
  .firestore();

// The exact document shape UserRepository.createStudentProfile writes.
function studentProfile(email) {
  return {
    fullName: "A Student",
    email,
    role: "student",
    college: null,
    program: null,
    specialization: null,
    active: true,
    createdAt: serverTimestamp(),
    createdBy: null,
  };
}

test("a new account may only be created with the student role", async () => {
  await assertSucceeds(
    setDoc(doc(student, "users/student-uid"), studentProfile("student@isufst.edu.ph"))
  );
});

test("a new account may NOT be created with an elevated role", async () => {
  const attacker = env
    .authenticatedContext("attacker-uid", {
      email: "attacker@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertFails(
    setDoc(doc(attacker, "users/attacker-uid"), {
      ...studentProfile("attacker@isufst.edu.ph"),
      role: "dean",
    })
  );
});

test("a student may NOT promote themselves without an invite", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(
      doc(ctx.firestore(), "users/no-invite-uid"),
      studentProfile("no-invite@isufst.edu.ph")
    );
  });

  const noInvite = env
    .authenticatedContext("no-invite-uid", {
      email: "no-invite@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertFails(updateDoc(doc(noInvite, "users/no-invite-uid"), { role: "dean" }));
});

test("a student MAY promote themselves when a matching invite exists", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "facultyInvites/invited@isufst.edu.ph"), {
      role: "faculty",
      invitedBy: "seed",
      consumedAt: null,
    });
    await setDoc(doc(db, "users/invited-uid"), studentProfile("invited@isufst.edu.ph"));
  });

  const invited = env
    .authenticatedContext("invited-uid", {
      email: "invited@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertSucceeds(
    updateDoc(doc(invited, "users/invited-uid"), { role: "faculty" })
  );
});

test("an invited user may NOT claim a role higher than their invite", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "facultyInvites/greedy@isufst.edu.ph"), {
      role: "faculty",
      invitedBy: "seed",
      consumedAt: null,
    });
    await setDoc(doc(db, "users/greedy-uid"), studentProfile("greedy@isufst.edu.ph"));
  });

  const greedy = env
    .authenticatedContext("greedy-uid", {
      email: "greedy@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertFails(
    updateDoc(doc(greedy, "users/greedy-uid"), { role: "dean" })
  );
});

test("a user may not read an invite belonging to someone else", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "facultyInvites/other@isufst.edu.ph"), {
      role: "dean",
      invitedBy: "seed",
      consumedAt: null,
    });
  });

  await assertFails(
    getDoc(doc(student, "facultyInvites/other@isufst.edu.ph"))
  );
});

test("audit logs may be created but never deleted", async () => {
  await assertSucceeds(
    setDoc(doc(student, "auditLogs/log-1"), {
      actorUid: "student-uid",
      action: "login",
      targetType: "session",
      targetId: "student-uid",
      metadata: {},
      timestamp: serverTimestamp(),
    })
  );
  await assertFails(deleteDoc(doc(student, "auditLogs/log-1")));
});

test("unauthenticated access is denied", async () => {
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anon, "users/student-uid")));
});

// --- Added for review round 1: coordinator self-elevation lockdown ---

test("a coordinator may NOT change their own role to dean", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/coord-uid"), {
      ...studentProfile("coord@isufst.edu.ph"),
      role: "coordinator",
    });
  });

  const coordinator = env
    .authenticatedContext("coord-uid", {
      email: "coord@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertFails(
    updateDoc(doc(coordinator, "users/coord-uid"), { role: "dean" })
  );
});

test("a coordinator may NOT change another user's role", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/coord2-uid"), {
      ...studentProfile("coord2@isufst.edu.ph"),
      role: "coordinator",
    });
    await setDoc(doc(db, "users/target-uid"), studentProfile("target@isufst.edu.ph"));
  });

  const coordinator = env
    .authenticatedContext("coord2-uid", {
      email: "coord2@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertFails(
    updateDoc(doc(coordinator, "users/target-uid"), { role: "faculty" })
  );
});

test("a coordinator MAY update another user's active field", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/coord3-uid"), {
      ...studentProfile("coord3@isufst.edu.ph"),
      role: "coordinator",
    });
    await setDoc(doc(db, "users/target2-uid"), studentProfile("target2@isufst.edu.ph"));
  });

  const coordinator = env
    .authenticatedContext("coord3-uid", {
      email: "coord3@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertSucceeds(
    updateDoc(doc(coordinator, "users/target2-uid"), { active: false })
  );
});

test("a mixed-case token email can create its profile and consume an invite stored under the lowercased id", async () => {
  const mixedCaseEmail = "Karl.Vargas@isufst.edu.ph";
  const lowercasedEmail = "karl.vargas@isufst.edu.ph";

  const mixed = env
    .authenticatedContext("mixed-case-uid", {
      email: mixedCaseEmail,
      email_verified: true,
    })
    .firestore();

  await assertSucceeds(
    setDoc(doc(mixed, "users/mixed-case-uid"), studentProfile(lowercasedEmail))
  );

  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `facultyInvites/${lowercasedEmail}`), {
      role: "faculty",
      invitedBy: "seed",
      consumedAt: null,
    });
  });

  await assertSucceeds(
    updateDoc(doc(mixed, "users/mixed-case-uid"), { role: "faculty" })
  );
});

test("a student may NOT enumerate facultyInvites", async () => {
  await assertFails(getDocs(collection(student, "facultyInvites")));
});

test("an unverified caller may NOT read an invite for their own address", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "facultyInvites/unverified@isufst.edu.ph"), {
      role: "faculty",
      invitedBy: "seed",
      consumedAt: null,
    });
  });

  const unverified = env
    .authenticatedContext("unverified-uid", {
      email: "unverified@isufst.edu.ph",
      email_verified: false,
    })
    .firestore();

  await assertFails(
    getDoc(doc(unverified, "facultyInvites/unverified@isufst.edu.ph"))
  );
});

test("an audit log may NOT be created with a foreign actorUid", async () => {
  await assertFails(
    setDoc(doc(student, "auditLogs/log-forged"), {
      actorUid: "someone-else-uid",
      action: "login",
      targetType: "session",
      targetId: "student-uid",
      metadata: {},
      timestamp: serverTimestamp(),
    })
  );
});

test("an audit log may NOT be overwritten via setDoc on an existing id", async () => {
  await assertSucceeds(
    setDoc(doc(student, "auditLogs/log-overwrite"), {
      actorUid: "student-uid",
      action: "login",
      targetType: "session",
      targetId: "student-uid",
      metadata: {},
      timestamp: serverTimestamp(),
    })
  );

  await assertFails(
    setDoc(doc(student, "auditLogs/log-overwrite"), {
      actorUid: "student-uid",
      action: "logout",
      targetType: "session",
      targetId: "student-uid",
      metadata: {},
      timestamp: serverTimestamp(),
    })
  );
});

// --- Added for review round 2: self-invite / consumed-invite lockdown ---

test("a coordinator may NOT create an invite for their own address", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/coord4-uid"), {
      ...studentProfile("coord4@isufst.edu.ph"),
      role: "coordinator",
    });
  });

  const coordinator = env
    .authenticatedContext("coord4-uid", {
      email: "coord4@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertFails(
    setDoc(doc(coordinator, "facultyInvites/coord4@isufst.edu.ph"), {
      role: "dean",
      invitedBy: "coord4-uid",
      consumedAt: null,
    })
  );
});

test("a coordinator may NOT create an invite with a role outside the allowed set", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/coord5-uid"), {
      ...studentProfile("coord5@isufst.edu.ph"),
      role: "coordinator",
    });
  });

  const coordinator = env
    .authenticatedContext("coord5-uid", {
      email: "coord5@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertFails(
    setDoc(doc(coordinator, "facultyInvites/newhire@isufst.edu.ph"), {
      role: "student",
      invitedBy: "coord5-uid",
      consumedAt: null,
    })
  );
});

test("an invitee may NOT delete their own invite", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "facultyInvites/nodel@isufst.edu.ph"), {
      role: "faculty",
      invitedBy: "seed",
      consumedAt: null,
    });
  });

  const invitee = env
    .authenticatedContext("nodel-uid", {
      email: "nodel@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertFails(
    deleteDoc(doc(invitee, "facultyInvites/nodel@isufst.edu.ph"))
  );
});

test("an invitee MAY mark their own invite consumed", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "facultyInvites/consume@isufst.edu.ph"), {
      role: "faculty",
      invitedBy: "seed",
      consumedAt: null,
    });
  });

  const invitee = env
    .authenticatedContext("consume-uid", {
      email: "consume@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertSucceeds(
    updateDoc(doc(invitee, "facultyInvites/consume@isufst.edu.ph"), {
      consumedAt: serverTimestamp(),
    })
  );
});

test("a consumed invite may NOT be used to promote again", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "facultyInvites/replay@isufst.edu.ph"), {
      role: "faculty",
      invitedBy: "seed",
      consumedAt: serverTimestamp(),
    });
    await setDoc(doc(db, "users/replay-uid"), studentProfile("replay@isufst.edu.ph"));
  });

  const replay = env
    .authenticatedContext("replay-uid", {
      email: "replay@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertFails(
    updateDoc(doc(replay, "users/replay-uid"), { role: "faculty" })
  );
});

test("a coordinator may NOT update their OWN account via the coordinator branch", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/coord6-uid"), {
      ...studentProfile("coord6@isufst.edu.ph"),
      role: "coordinator",
    });
  });

  const coordinator = env
    .authenticatedContext("coord6-uid", {
      email: "coord6@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertFails(
    updateDoc(doc(coordinator, "users/coord6-uid"), { active: false })
  );
});

// --- Added for final fix wave: inviteUnconsumed() missing-field tolerance,
// and a positive control on invite creation ---

test("a coordinator MAY create a valid invite for someone else", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/coord7-uid"), {
      ...studentProfile("coord7@isufst.edu.ph"),
      role: "coordinator",
    });
  });

  const coordinator = env
    .authenticatedContext("coord7-uid", {
      email: "coord7@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertSucceeds(
    setDoc(doc(coordinator, "facultyInvites/newfaculty@isufst.edu.ph"), {
      role: "faculty",
      invitedBy: "coord7-uid",
      consumedAt: null,
    })
  );
});

test("promotion succeeds against an invite with no consumedAt field at all", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    // Simulates a console-created invite where the admin omitted
    // `consumedAt: null` entirely, rather than setting it explicitly.
    await setDoc(doc(db, "facultyInvites/noconsumedat@isufst.edu.ph"), {
      role: "faculty",
      invitedBy: "seed",
    });
    await setDoc(
      doc(db, "users/noconsumedat-uid"),
      studentProfile("noconsumedat@isufst.edu.ph")
    );
  });

  const invited = env
    .authenticatedContext("noconsumedat-uid", {
      email: "noconsumedat@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertSucceeds(
    updateDoc(doc(invited, "users/noconsumedat-uid"), { role: "faculty" })
  );
});

// --- Task 7: theses, nominations, faculty directory ---

async function seedThesis(id, leaderUid, status, extra = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "theses", id), {
      leaderUid, status, panelistUids: [], adviserUid: null,
      memberNames: [], workingTitle: "T", college: "CICT",
      program: "BSIT", semester: "First", academicYear: "2026-2027",
      ...extra,
    });
  });
}

async function seedNomination(thesisId, uid, overrides = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `theses/${thesisId}/nominations/${uid}`), {
      nomineeName: "Dr. X", position: "panelist", exOfficio: false,
      conformeStatus: "pending", respondedAt: null, declineReason: null,
      ...overrides,
    });
  });
}

test("a student may create their own thesis as draft", async () => {
  await assertSucceeds(
    setDoc(doc(student, "theses/t-new"), {
      leaderUid: "student-uid", status: "draft", panelistUids: [],
      adviserUid: null, memberNames: [], workingTitle: "T",
      college: "CICT", program: "BSIT", semester: "First",
      academicYear: "2026-2027",
    })
  );
});

test("a student may NOT create a thesis owned by someone else", async () => {
  await assertFails(
    setDoc(doc(student, "theses/t-other"), {
      leaderUid: "someone-else", status: "draft", panelistUids: [],
      adviserUid: null, memberNames: [], workingTitle: "T",
      college: "CICT", program: "BSIT", semester: "First",
      academicYear: "2026-2027",
    })
  );
});

test("a student may NOT create a thesis already approved", async () => {
  await assertFails(
    setDoc(doc(student, "theses/t-cheat"), {
      leaderUid: "student-uid", status: "nominationApproved",
      panelistUids: [], adviserUid: null, memberNames: [],
      workingTitle: "T", college: "CICT", program: "BSIT",
      semester: "First", academicYear: "2026-2027",
    })
  );
});

test("a student may NOT read another student's thesis", async () => {
  await seedThesis("t-private", "other-uid", "draft");
  await assertFails(getDoc(doc(student, "theses/t-private")));
});

test("a student may NOT set the approval fields", async () => {
  await seedThesis("t-mine", "student-uid", "nominationPendingDean");
  await assertFails(
    updateDoc(doc(student, "theses/t-mine"), {
      status: "nominationApproved", adviserUid: "a1",
      panelistUids: ["p1", "p2", "p3"],
    })
  );
});

test("only the nominee may write their own conforme", async () => {
  await seedThesis("t-conf", "student-uid", "nominationPendingConforme");
  await seedNomination("t-conf", "invited-uid", { nomineeName: "Dr. X" });

  await assertFails(
    updateDoc(doc(student, "theses/t-conf/nominations/invited-uid"), {
      conformeStatus: "accepted",
    })
  );

  const nominee = env
    .authenticatedContext("invited-uid", {
      email: "invited@isufst.edu.ph", email_verified: true,
    })
    .firestore();

  await assertSucceeds(
    updateDoc(doc(nominee, "theses/t-conf/nominations/invited-uid"), {
      conformeStatus: "accepted",
    })
  );
});

test("a student may NOT forge an ex officio acceptance", async () => {
  await seedThesis("t-forge", "student-uid", "draft");
  await assertFails(
    setDoc(doc(student, "theses/t-forge/nominations/fake-uid"), {
      nomineeName: "Dr. Fake", position: "panelist", exOfficio: true,
      conformeStatus: "accepted", respondedAt: null, declineReason: null,
    })
  );
});

test("anyone verified may read the faculty directory", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "facultyDirectory/f1"), {
      fullName: "Dr. Armada", role: "faculty",
      college: "CICT", specialization: "SE",
    });
  });
  await assertSucceeds(getDoc(doc(student, "facultyDirectory/f1")));
});

test("a student may NOT write a faculty directory entry", async () => {
  await assertFails(
    setDoc(doc(student, "facultyDirectory/student-uid"), {
      fullName: "A Student", role: "faculty",
      college: "CICT", specialization: null,
    })
  );
});

// --- Ruling 2: nominee status-advance must be scoped to a real nominee on
// THIS thesis, moving only from nominationPendingConforme. The plan's
// original rule (verified() + onlyChanged(['status']) + target status only)
// let any verified stranger flip any thesis forward. First prove the allow
// path actually works for a real nominee on the right prior status — a
// falsifiability control for the deny tests that follow — then prove a
// stranger with no nomination doc is denied, and prove a nominee cannot
// replay the same transition from a later stage to walk the thesis
// backwards.

test("a nominee on the thesis MAY advance it from nominationPendingConforme", async () => {
  await seedThesis("t-advance-ok", "leader-uid", "nominationPendingConforme");
  await seedNomination("t-advance-ok", "nominee-uid");

  const nominee = env
    .authenticatedContext("nominee-uid", {
      email: "nominee@isufst.edu.ph", email_verified: true,
    })
    .firestore();

  await assertSucceeds(
    updateDoc(doc(nominee, "theses/t-advance-ok"), {
      status: "nominationPendingCoordinator",
    })
  );
});

test("a stranger with no nomination on the thesis may NOT advance it", async () => {
  await seedThesis("t-advance-stranger", "leader-uid", "nominationPendingConforme");
  // student-uid has no nominations/{uid} doc under this thesis at all.

  await assertFails(
    updateDoc(doc(student, "theses/t-advance-stranger"), {
      status: "nominationPendingCoordinator",
    })
  );
});

test("a nominee may NOT advance a thesis that is already nominationApproved", async () => {
  await seedThesis("t-advance-backwards", "leader-uid", "nominationApproved");
  await seedNomination("t-advance-backwards", "nominee2-uid");

  const nominee = env
    .authenticatedContext("nominee2-uid", {
      email: "nominee2@isufst.edu.ph", email_verified: true,
    })
    .firestore();

  await assertFails(
    updateDoc(doc(nominee, "theses/t-advance-backwards"), {
      status: "nominationPendingCoordinator",
    })
  );
});

// --- Self-review follow-up: the plan's coordinator/dean branches and the
// leader's own status-editing branch had no prior-status guard either — the
// same class of hole Ruling 2 flagged for the nominee branch. Prove the
// legitimate forward transition still works (falsifiability control), then
// prove the skip/backward path is denied.

test("a leader MAY move their own thesis from draft to nominationPendingConforme", async () => {
  await seedThesis("t-leader-forward", "student-uid", "draft");
  await assertSucceeds(
    updateDoc(doc(student, "theses/t-leader-forward"), {
      status: "nominationPendingConforme",
    })
  );
});

test("a leader may NOT revert their own already-approved thesis back to draft", async () => {
  await seedThesis("t-leader-revert", "student-uid", "nominationApproved");
  await assertFails(
    updateDoc(doc(student, "theses/t-leader-revert"), { status: "draft" })
  );
});

test("a coordinator MAY recommend a thesis that is pending coordinator review", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/coord-thesis-uid"), {
      fullName: "Coord", email: "coordthesis@isufst.edu.ph", role: "coordinator",
      college: null, program: null, specialization: null, active: true,
      createdAt: serverTimestamp(), createdBy: null,
    });
  });
  await seedThesis("t-coord-ok", "leader-uid", "nominationPendingCoordinator");

  const coordinator = env
    .authenticatedContext("coord-thesis-uid", {
      email: "coordthesis@isufst.edu.ph", email_verified: true,
    })
    .firestore();

  await assertSucceeds(
    updateDoc(doc(coordinator, "theses/t-coord-ok"), {
      status: "nominationPendingDean",
      coordinatorRecommendedAt: serverTimestamp(),
      coordinatorRecommendedBy: "coord-thesis-uid",
    })
  );
});

test("a coordinator may NOT recommend a thesis that is still a draft (stage skip)", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/coord-skip-uid"), {
      fullName: "Coord", email: "coordskip@isufst.edu.ph", role: "coordinator",
      college: null, program: null, specialization: null, active: true,
      createdAt: serverTimestamp(), createdBy: null,
    });
  });
  await seedThesis("t-coord-skip", "leader-uid", "draft");

  const coordinator = env
    .authenticatedContext("coord-skip-uid", {
      email: "coordskip@isufst.edu.ph", email_verified: true,
    })
    .firestore();

  await assertFails(
    updateDoc(doc(coordinator, "theses/t-coord-skip"), {
      status: "nominationPendingDean",
      coordinatorRecommendedAt: serverTimestamp(),
      coordinatorRecommendedBy: "coord-skip-uid",
    })
  );
});

test("a dean MAY approve a thesis that is pending dean review", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/dean-ok-uid"), {
      fullName: "Dean", email: "deanok@isufst.edu.ph", role: "dean",
      college: null, program: null, specialization: null, active: true,
      createdAt: serverTimestamp(), createdBy: null,
    });
  });
  await seedThesis("t-dean-ok", "leader-uid", "nominationPendingDean");
  // Fixture updated for the adviser-acceptance check added in fix wave 1:
  // the dean's approval now verifies that the nomination named by
  // `adviserUid` actually reads `accepted`. The assertion is unchanged — this
  // only supplies the prerequisite document a real approval always has, which
  // the original fixture omitted because nothing checked it.
  await seedNomination("t-dean-ok", "adv-1", {
    position: "adviser",
    conformeStatus: "accepted",
  });

  const dean = env
    .authenticatedContext("dean-ok-uid", {
      email: "deanok@isufst.edu.ph", email_verified: true,
    })
    .firestore();

  await assertSucceeds(
    updateDoc(doc(dean, "theses/t-dean-ok"), {
      status: "nominationApproved",
      deanApprovedAt: serverTimestamp(),
      deanApprovedBy: "dean-ok-uid",
      adviserUid: "adv-1",
      panelistUids: ["p1", "p2", "p3"],
    })
  );
});

test("a dean may NOT approve a thesis directly from draft (stage skip)", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/dean-skip-uid"), {
      fullName: "Dean", email: "deanskip@isufst.edu.ph", role: "dean",
      college: null, program: null, specialization: null, active: true,
      createdAt: serverTimestamp(), createdBy: null,
    });
  });
  await seedThesis("t-dean-skip", "leader-uid", "draft");

  const dean = env
    .authenticatedContext("dean-skip-uid", {
      email: "deanskip@isufst.edu.ph", email_verified: true,
    })
    .firestore();

  await assertFails(
    updateDoc(doc(dean, "theses/t-dean-skip"), {
      status: "nominationApproved",
      deanApprovedAt: serverTimestamp(),
      deanApprovedBy: "dean-skip-uid",
      adviserUid: "adv-1",
      panelistUids: ["p1", "p2", "p3"],
    })
  );
});

// =====================================================================
// Task 7, fix wave 1 — the emulator-driven security review.
//
// House rule for this block: every deny test is paired with an allow test
// that walks the SAME path with the right user, because a deny can pass for
// the wrong reason (a typo'd path, a missing prerequisite document) and look
// exactly like a rule doing its job.
// =====================================================================

async function seedUser(uid, role, email) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users", uid), {
      fullName: "U", email, role, college: null, program: null,
      specialization: null, active: true,
      createdAt: serverTimestamp(), createdBy: null,
    });
  });
}

function asUser(uid, email) {
  return env
    .authenticatedContext(uid, { email, email_verified: true })
    .firestore();
}

// The nomination document `submitNominations` writes, including the
// `nomineeUid` field the rules now pin to the document id.
function nominationDoc(uid, overrides = {}) {
  return {
    nomineeUid: uid, nomineeName: "Dr. X", position: "panelist",
    exOfficio: false, conformeStatus: "pending",
    respondedAt: null, declineReason: null,
    ...overrides,
  };
}

// A leader with a users doc, used by the nomination tests below.
const LEADER = "lead-uid";
const LEADER_EMAIL = "lead@isufst.edu.ph";
await seedUser(LEADER, "student", LEADER_EMAIL);
await seedUser("fac-a", "faculty", "faca@isufst.edu.ph");
await seedUser("fac-b", "faculty", "facb@isufst.edu.ph");
await seedUser("dean-x", "dean", "deanx@isufst.edu.ph");
await seedUser("coord-x", "coordinator", "coordx@isufst.edu.ph");
await seedUser("stud-b", "student", "studb@isufst.edu.ph");
const leader = asUser(LEADER, LEADER_EMAIL);

// --- CRITICAL 1: exOfficio was student-controlled ---------------------

test("C1 allow: a leader MAY nominate a real dean as an ex officio seat", async () => {
  await seedThesis("c1-ok", LEADER, "draft");
  await assertSucceeds(
    setDoc(doc(leader, "theses/c1-ok/nominations/dean-x"),
      nominationDoc("dean-x", {
        position: "dean", exOfficio: true, conformeStatus: "exOfficio",
      }))
  );
});

test("C1 allow: a leader MAY nominate a real coordinator as an ex officio seat", async () => {
  await seedThesis("c1-ok2", LEADER, "draft");
  await assertSucceeds(
    setDoc(doc(leader, "theses/c1-ok2/nominations/coord-x"),
      nominationDoc("coord-x", {
        position: "coordinator", exOfficio: true, conformeStatus: "exOfficio",
      }))
  );
});

test("C1 attack: a leader may NOT mark an ordinary faculty adviser ex officio", async () => {
  // The reproduction from the review, verbatim: this write SUCCEEDED before
  // the fix, and that adviser was then never asked and never blocked.
  await seedThesis("c1-attack", LEADER, "draft");
  await assertFails(
    setDoc(doc(leader, "theses/c1-attack/nominations/fac-a"),
      nominationDoc("fac-a", {
        position: "adviser", exOfficio: true, conformeStatus: "exOfficio",
      }))
  );
});

test("C1 allow: a dean nominated AS ADVISER still carries exOfficio false and must accept", async () => {
  // The one-directional constraint: office holder does not imply ex officio.
  await seedThesis("c1-dean-adviser", LEADER, "draft");
  await assertSucceeds(
    setDoc(doc(leader, "theses/c1-dean-adviser/nominations/dean-x"),
      nominationDoc("dean-x", {
        position: "adviser", exOfficio: false, conformeStatus: "pending",
      }))
  );
});

// --- CRITICAL 2: leader self-nomination -> self-advance ----------------

test("C2 attack step 1: a leader may NOT nominate themselves", async () => {
  await seedThesis("c2-self", LEADER, "draft");
  await assertFails(
    setDoc(doc(leader, `theses/c2-self/nominations/${LEADER}`),
      nominationDoc(LEADER, { exOfficio: true, conformeStatus: "exOfficio" }))
  );
});

// `theses` create only requires a verified account, so a faculty account can
// hold a thesis too. That is the case where `nomineeUid != leaderUid` does
// the work on its own: for a STUDENT leader the "nominee must not be a
// student" clause already covers self-nomination, so a student-only test
// cannot tell whether the self-check exists at all (verified: deleting the
// self-check failed no test until these two were added).
test("C2 allow: a faculty leader MAY nominate a DIFFERENT faculty member", async () => {
  await seedThesis("c2-fac-ok", "fac-a", "draft");
  await assertSucceeds(
    setDoc(doc(asUser("fac-a", "faca@isufst.edu.ph"),
      "theses/c2-fac-ok/nominations/fac-b"), nominationDoc("fac-b"))
  );
});

test("C2 attack: a faculty leader may NOT nominate THEMSELVES", async () => {
  await seedThesis("c2-fac-self", "fac-a", "draft");
  await assertFails(
    setDoc(doc(asUser("fac-a", "faca@isufst.edu.ph"),
      "theses/c2-fac-self/nominations/fac-a"), nominationDoc("fac-a"))
  );
});

test("C2: a leader may NOT nominate another student either", async () => {
  await seedThesis("c2-student", LEADER, "draft");
  await assertFails(
    setDoc(doc(leader, "theses/c2-student/nominations/stud-b"),
      nominationDoc("stud-b"))
  );
});

test("C2: a leader may NOT nominate a uid with no account at all", async () => {
  await seedThesis("c2-ghost", LEADER, "draft");
  await assertFails(
    setDoc(doc(leader, "theses/c2-ghost/nominations/ghost-uid"),
      nominationDoc("ghost-uid"))
  );
});

test("C2: the nomineeUid field may NOT disagree with the document id", async () => {
  await seedThesis("c2-mismatch", LEADER, "draft");
  await assertFails(
    setDoc(doc(leader, "theses/c2-mismatch/nominations/fac-a"),
      nominationDoc("fac-b"))
  );
});

test("C2 attack step 2: even a planted self-nomination cannot advance the thesis", async () => {
  // Defence in depth. Suppose the nomination doc existed anyway (seeded here
  // with rules disabled, standing in for the pre-fix create): the advance
  // rule now also demands a seat that was genuinely asked, and an ex officio
  // seat was not. The full chain the review proved is broken twice over.
  await seedThesis("c2-advance", LEADER, "nominationPendingConforme");
  await seedNomination("c2-advance", LEADER, {
    exOfficio: true, conformeStatus: "exOfficio",
  });
  await assertFails(
    updateDoc(doc(leader, "theses/c2-advance"), {
      status: "nominationPendingCoordinator",
    })
  );
});

// --- CRITICAL 3: decline laundering ------------------------------------

test("C3 allow: a leader MAY delete a declined nomination while the thesis is still draft", async () => {
  // Falsifiability control for the deny below: the delete path itself works
  // for this user on this path when the thesis is draft.
  await seedThesis("c3-draft", LEADER, "draft");
  await seedNomination("c3-draft", "fac-a", { conformeStatus: "declined" });
  await assertSucceeds(
    deleteDoc(doc(leader, "theses/c3-draft/nominations/fac-a"))
  );
});

test("C3 attack: a leader may NOT delete a decline once nominations have gone out", async () => {
  await seedThesis("c3-launder", LEADER, "nominationPendingConforme");
  await seedNomination("c3-launder", "fac-a", { conformeStatus: "declined" });
  await assertFails(
    deleteDoc(doc(leader, "theses/c3-launder/nominations/fac-a"))
  );
});

test("C3 attack: a leader may NOT re-create a nomination after nominations have gone out", async () => {
  // The other half of the laundering move — and the same rule stops a leader
  // from resetting a `pending` seat that is taking too long to answer.
  await seedThesis("c3-recreate", LEADER, "nominationPendingConforme");
  await assertFails(
    setDoc(doc(leader, "theses/c3-recreate/nominations/dean-x"),
      nominationDoc("dean-x", {
        exOfficio: true, conformeStatus: "exOfficio", position: "dean",
      }))
  );
});

test("C3: submitNominations' BATCH still passes — creates plus the status flip in one commit", async () => {
  // The `draft` pin would be fatal if a batched write were evaluated against
  // the state its own siblings produce. It is not: every write in a batch is
  // evaluated against the pre-batch committed state, where the thesis is
  // still draft. Asserted against the emulator rather than reasoned about.
  await seedThesis("c3-batch", LEADER, "draft");
  const batch = writeBatch(leader);
  batch.set(doc(leader, "theses/c3-batch/nominations/fac-a"),
    nominationDoc("fac-a", { position: "adviser" }));
  batch.set(doc(leader, "theses/c3-batch/nominations/fac-b"),
    nominationDoc("fac-b"));
  batch.set(doc(leader, "theses/c3-batch/nominations/dean-x"),
    nominationDoc("dean-x", {
      position: "dean", exOfficio: true, conformeStatus: "exOfficio",
    }));
  batch.update(doc(leader, "theses/c3-batch"), {
    status: "nominationPendingConforme",
  });
  await assertSucceeds(batch.commit());
});

// --- IMPORTANT (a): advancing requires a seat that was asked ------------

test("(a) allow: a nominee who has ACCEPTED may advance the thesis", async () => {
  await seedThesis("a-accepted", LEADER, "nominationPendingConforme");
  await seedNomination("a-accepted", "fac-a", { conformeStatus: "accepted" });
  await assertSucceeds(
    updateDoc(doc(asUser("fac-a", "faca@isufst.edu.ph"), "theses/a-accepted"), {
      status: "nominationPendingCoordinator",
    })
  );
});

test("(a) attack: a nominee who DECLINED may not advance the thesis", async () => {
  await seedThesis("a-declined", LEADER, "nominationPendingConforme");
  await seedNomination("a-declined", "fac-a", { conformeStatus: "declined" });
  await assertFails(
    updateDoc(doc(asUser("fac-a", "faca@isufst.edu.ph"), "theses/a-declined"), {
      status: "nominationPendingCoordinator",
    })
  );
});

test("(a) attack: an ex officio coordinator may not advance a thesis they were never asked about", async () => {
  // A coordinator sits ex officio on EVERY thesis, so before the fix every
  // coordinator could advance every thesis awaiting Conforme.
  await seedThesis("a-exofficio", LEADER, "nominationPendingConforme");
  await seedNomination("a-exofficio", "coord-x", {
    exOfficio: true, conformeStatus: "exOfficio", position: "coordinator",
  });
  await assertFails(
    updateDoc(doc(asUser("coord-x", "coordx@isufst.edu.ph"), "theses/a-exofficio"), {
      status: "nominationPendingCoordinator",
    })
  );
});

test("(a) allow: respondToNomination's atomic accept+advance TRANSACTION still passes", async () => {
  // This is why the rule accepts 'pending' as well as 'accepted' — see the
  // LIMITATION note in firestore.rules. Rules evaluate every write in a
  // transaction against the state BEFORE it, so the acceptance written on the
  // line above is invisible to the rule guarding the line below.
  await seedThesis("a-txn", LEADER, "nominationPendingConforme");
  await seedNomination("a-txn", "fac-a", { conformeStatus: "pending" });
  const nominee = asUser("fac-a", "faca@isufst.edu.ph");

  await assertSucceeds(
    runTransaction(nominee, async (tx) => {
      await tx.get(doc(nominee, "theses/a-txn"));
      await tx.get(doc(nominee, "theses/a-txn/nominations/fac-a"));
      tx.update(doc(nominee, "theses/a-txn/nominations/fac-a"), {
        conformeStatus: "accepted", respondedAt: serverTimestamp(),
        declineReason: null,
      });
      tx.update(doc(nominee, "theses/a-txn"), {
        status: "nominationPendingCoordinator",
      });
    })
  );
});

// --- IMPORTANT (b): the leader could not read their own thesis ---------

test("(b) allow: a leader MAY run watchThesisForLeader's query on their own thesis", async () => {
  await seedThesis("b-mine", LEADER, "draft");
  await assertSucceeds(
    getDocs(query(collection(leader, "theses"),
      where("leaderUid", "==", LEADER)))
  );
});

test("(b) a leader may NOT list theses that are not theirs", async () => {
  await seedThesis("b-other", "someone-else", "draft");
  await assertFails(
    getDocs(query(collection(leader, "theses"),
      where("leaderUid", "==", "someone-else")))
  );
});

test("(b) a leader may NOT list the whole theses collection unfiltered", async () => {
  await assertFails(getDocs(collection(leader, "theses")));
});

// --- IMPORTANT (c), rules side: the faculty inbox's real query ----------

test("(c) allow: the faculty inbox's collection-group query on nomineeUid is permitted", async () => {
  await seedThesis("c-inbox", LEADER, "nominationPendingConforme");
  await seedNomination("c-inbox", "fac-a", { nomineeUid: "fac-a" });
  await assertSucceeds(
    getDocs(query(collectionGroup(asUser("fac-a", "faca@isufst.edu.ph"),
      "nominations"), where("nomineeUid", "==", "fac-a")))
  );
});

test("(c) the inbox query may NOT be turned into an unfiltered scan of every nomination", async () => {
  await assertFails(
    getDocs(collectionGroup(asUser("fac-a", "faca@isufst.edu.ph"), "nominations"))
  );
});

test("(c) one faculty member may NOT run the inbox query for another", async () => {
  await assertFails(
    getDocs(query(collectionGroup(asUser("fac-b", "facb@isufst.edu.ph"),
      "nominations"), where("nomineeUid", "==", "fac-a")))
  );
});

// --- IMPORTANT (d): unbounded thesis create -----------------------------

const draftThesis = (extra = {}) => ({
  leaderUid: LEADER, status: "draft", panelistUids: [], adviserUid: null,
  memberNames: [], workingTitle: "T", college: "CICT", program: "BSIT",
  semester: "First", academicYear: "2026-2027", ...extra,
});

test("(d) allow: a leader MAY create the full document createThesis writes", async () => {
  await assertSucceeds(
    setDoc(doc(leader, "theses/d-full"), draftThesis({
      coordinatorRecommendedAt: null, coordinatorRecommendedBy: null,
      deanApprovedAt: null, deanApprovedBy: null,
      createdAt: serverTimestamp(),
    }))
  );
});

test("(d) a leader may NOT plant deanApprovedBy at creation", async () => {
  await assertFails(
    setDoc(doc(leader, "theses/d-approved"),
      draftThesis({ deanApprovedBy: "dean-x" }))
  );
});

test("(d) a leader may NOT backdate createdAt at creation", async () => {
  await assertFails(
    setDoc(doc(leader, "theses/d-backdated"),
      draftThesis({ createdAt: Timestamp.fromDate(new Date("1999-01-01")) }))
  );
});

test("(d) a leader may NOT smuggle an unknown field into a thesis", async () => {
  await assertFails(
    setDoc(doc(leader, "theses/d-junk"), draftThesis({ isAwesome: true }))
  );
});

// --- IMPORTANT (e): approved theses stayed mutable ----------------------

test("(e) allow: a leader MAY still edit their thesis while it is a draft", async () => {
  await seedThesis("e-draft", LEADER, "draft");
  await assertSucceeds(
    updateDoc(doc(leader, "theses/e-draft"), { workingTitle: "New title" })
  );
});

test("(e) a leader may NOT edit an approved thesis", async () => {
  await seedThesis("e-approved", LEADER, "nominationApproved");
  await assertFails(
    updateDoc(doc(leader, "theses/e-approved"), {
      workingTitle: "Rewritten after approval",
      memberNames: ["someone new"],
    })
  );
});

test("(e) a leader may NOT edit a thesis that is out for Conforme", async () => {
  await seedThesis("e-conforme", LEADER, "nominationPendingConforme");
  await assertFails(
    updateDoc(doc(leader, "theses/e-conforme"), { workingTitle: "Changed" })
  );
});

// --- IMPORTANT (f): timestamps were not pinned --------------------------

const BACKDATED = Timestamp.fromDate(new Date("1999-01-01"));

test("(f) a dean may NOT backdate deanApprovedAt", async () => {
  await seedUser("dean-f", "dean", "deanf@isufst.edu.ph");
  await seedThesis("f-dean", LEADER, "nominationPendingDean");
  await seedNomination("f-dean", "fac-a", {
    position: "adviser", conformeStatus: "accepted",
  });
  await assertFails(
    updateDoc(doc(asUser("dean-f", "deanf@isufst.edu.ph"), "theses/f-dean"), {
      status: "nominationApproved", deanApprovedAt: BACKDATED,
      deanApprovedBy: "dean-f", adviserUid: "fac-a",
      panelistUids: ["p1", "p2", "p3"],
    })
  );
});

test("(f) a coordinator may NOT backdate coordinatorRecommendedAt", async () => {
  await seedUser("coord-f", "coordinator", "coordf@isufst.edu.ph");
  await seedThesis("f-coord", LEADER, "nominationPendingCoordinator");
  await assertFails(
    updateDoc(doc(asUser("coord-f", "coordf@isufst.edu.ph"), "theses/f-coord"), {
      status: "nominationPendingDean", coordinatorRecommendedAt: BACKDATED,
      coordinatorRecommendedBy: "coord-f",
    })
  );
});

test("(f) allow: a nominee MAY record a response with a server timestamp", async () => {
  await seedThesis("f-resp-ok", LEADER, "nominationPendingConforme");
  await seedNomination("f-resp-ok", "fac-a");
  await assertSucceeds(
    updateDoc(doc(asUser("fac-a", "faca@isufst.edu.ph"),
      "theses/f-resp-ok/nominations/fac-a"), {
      conformeStatus: "accepted", respondedAt: serverTimestamp(),
    })
  );
});

test("(f) a nominee may NOT backdate respondedAt", async () => {
  await seedThesis("f-resp-bad", LEADER, "nominationPendingConforme");
  await seedNomination("f-resp-bad", "fac-a");
  await assertFails(
    updateDoc(doc(asUser("fac-a", "faca@isufst.edu.ph"),
      "theses/f-resp-bad/nominations/fac-a"), {
      conformeStatus: "accepted", respondedAt: BACKDATED,
    })
  );
});

// --- The accepted limitation, partly mitigated: adviserUid --------------

test("adviser: a dean may NOT approve with an adviserUid that never accepted", async () => {
  await seedUser("dean-adv", "dean", "deanadv@isufst.edu.ph");
  await seedThesis("adv-never", LEADER, "nominationPendingDean");
  await seedNomination("adv-never", "fac-a", {
    position: "adviser", conformeStatus: "pending",
  });
  await assertFails(
    updateDoc(doc(asUser("dean-adv", "deanadv@isufst.edu.ph"), "theses/adv-never"), {
      status: "nominationApproved", deanApprovedAt: serverTimestamp(),
      deanApprovedBy: "dean-adv", adviserUid: "fac-a",
      panelistUids: ["p1", "p2", "p3"],
    })
  );
});

test("adviser: a dean may NOT approve with an adviserUid that was never nominated", async () => {
  await seedUser("dean-adv2", "dean", "deanadv2@isufst.edu.ph");
  await seedThesis("adv-ghost", LEADER, "nominationPendingDean");
  await assertFails(
    updateDoc(doc(asUser("dean-adv2", "deanadv2@isufst.edu.ph"), "theses/adv-ghost"), {
      status: "nominationApproved", deanApprovedAt: serverTimestamp(),
      deanApprovedBy: "dean-adv2", adviserUid: "never-accepted-uid",
      panelistUids: ["p1", "p2", "p3"],
    })
  );
});

// --- MINOR (g): directory self-declaration ------------------------------

test("(g) allow: a faculty member MAY write their own directory entry with their real role", async () => {
  await assertSucceeds(
    setDoc(doc(asUser("fac-a", "faca@isufst.edu.ph"), "facultyDirectory/fac-a"), {
      fullName: "Dr. A", role: "faculty", college: "CICT", specialization: "SE",
    })
  );
});

test("(g) attack: a faculty member may NOT self-declare the dean role", async () => {
  await assertFails(
    setDoc(doc(asUser("fac-a", "faca@isufst.edu.ph"), "facultyDirectory/fac-a"), {
      fullName: "Dr. A", role: "dean", college: "CICT", specialization: "SE",
    })
  );
});

test("(g) a directory entry may NOT carry unknown keys", async () => {
  await assertFails(
    setDoc(doc(asUser("fac-a", "faca@isufst.edu.ph"), "facultyDirectory/fac-a"), {
      fullName: "Dr. A", role: "faculty", college: "CICT",
      specialization: "SE", isDean: true,
    })
  );
});

test("(g) a directory entry may NOT be deleted", async () => {
  await assertFails(
    deleteDoc(doc(asUser("fac-a", "faca@isufst.edu.ph"), "facultyDirectory/fac-a"))
  );
});

// --- MINOR (h): a pending nominee could not read the parent thesis ------

test("(h) allow: a pending nominee MAY read the thesis they were nominated to", async () => {
  await seedThesis("h-nominee", LEADER, "nominationPendingConforme");
  await seedNomination("h-nominee", "fac-a");
  await assertSucceeds(
    getDoc(doc(asUser("fac-a", "faca@isufst.edu.ph"), "theses/h-nominee"))
  );
});

test("(h) a faculty member with no nomination on the thesis still may NOT read it", async () => {
  await seedThesis("h-stranger", LEADER, "nominationPendingConforme");
  await seedNomination("h-stranger", "fac-a");
  await assertFails(
    getDoc(doc(asUser("fac-b", "facb@isufst.edu.ph"), "theses/h-stranger"))
  );
});

test.after(async () => {
  await env.cleanup();
});
