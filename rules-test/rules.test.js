import { readFileSync } from "node:fs";
import test from "node:test";
import assert from "node:assert/strict";
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
  deleteField,
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

// --- invite create is now key-whitelisted and value-pinned ----------------
// The invite document is read during promotion, so anything plantable here
// reaches a privilege decision. Each test below has its allow-control in
// "a coordinator MAY create a valid invite for someone else" above.

async function asCoordinator(uid, email) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `users/${uid}`), {
      ...studentProfile(email),
      role: "coordinator",
    });
  });
  return env
    .authenticatedContext(uid, { email, email_verified: true })
    .firestore();
}

test("an invite MAY carry college and specialization", async () => {
  const coordinator = await asCoordinator("coord-inv1", "coordinv1@isufst.edu.ph");
  await assertSucceeds(
    setDoc(doc(coordinator, "facultyInvites/withcollege@isufst.edu.ph"), {
      role: "faculty",
      invitedBy: "coord-inv1",
      createdAt: serverTimestamp(),
      consumedAt: null,
      college: "CICT",
      specialization: "Software Engineering",
    })
  );
});

test("an invite may NOT carry unknown keys", async () => {
  const coordinator = await asCoordinator("coord-inv2", "coordinv2@isufst.edu.ph");
  await assertFails(
    setDoc(doc(coordinator, "facultyInvites/junk@isufst.edu.ph"), {
      role: "faculty",
      invitedBy: "coord-inv2",
      consumedAt: null,
      isDean: true,
    })
  );
});

test("an invite may NOT arrive already consumed", async () => {
  // Pre-consuming would be inert today, but `consumedAt` is what makes an
  // invite single-use — it must only ever be set by the invitee applying it.
  const coordinator = await asCoordinator("coord-inv3", "coordinv3@isufst.edu.ph");
  await assertFails(
    setDoc(doc(coordinator, "facultyInvites/preconsumed@isufst.edu.ph"), {
      role: "faculty",
      invitedBy: "coord-inv3",
      consumedAt: Timestamp.fromDate(new Date("2026-01-01")),
    })
  );
});

test("a coordinator may NOT forge invitedBy as someone else", async () => {
  // invitedBy is the only attribution the invite carries; a coordinator who
  // could name another coordinator as the issuer could hand off the paper
  // trail for an elevation they made.
  const coordinator = await asCoordinator("coord-inv4", "coordinv4@isufst.edu.ph");
  await assertFails(
    setDoc(doc(coordinator, "facultyInvites/forged@isufst.edu.ph"), {
      role: "faculty",
      invitedBy: "some-other-coordinator",
      consumedAt: null,
    })
  );
});

test("a coordinator may NOT backdate an invite", async () => {
  const coordinator = await asCoordinator("coord-inv5", "coordinv5@isufst.edu.ph");
  await assertFails(
    setDoc(doc(coordinator, "facultyInvites/backdated@isufst.edu.ph"), {
      role: "faculty",
      invitedBy: "coord-inv5",
      createdAt: Timestamp.fromDate(new Date("1999-01-01")),
      consumedAt: null,
    })
  );
});

test("a coordinator may NOT un-consume an invite to replay a promotion", async () => {
  // Without the consumedAt pin a coordinator could reopen a spent invite,
  // letting the same promotion be applied a second time.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "facultyInvites/spent@isufst.edu.ph"), {
      role: "dean",
      invitedBy: "seed",
      consumedAt: Timestamp.fromDate(new Date("2026-02-02")),
    });
  });
  const coordinator = await asCoordinator("coord-inv6", "coordinv6@isufst.edu.ph");
  await assertFails(
    updateDoc(doc(coordinator, "facultyInvites/spent@isufst.edu.ph"), {
      consumedAt: null,
    })
  );
});

test("END TO END: a coordinator invites, the invitee claims the role AND the profile fields", async () => {
  // promoteFromInvite issues THREE separate writes because the rules police
  // them under three different branches: the role (invite branch,
  // onlyChanged(['role'])), the profile fields (account-owner branch,
  // onlyChanged(['fullName','college','program','specialization'])), and the
  // consume. A single update touching role AND college satisfies neither
  // branch's onlyChanged and would be denied in production while passing
  // every fake_cloud_firestore test. This replays the real sequence.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/e2e-invitee"), {
      ...studentProfile("e2einvitee@isufst.edu.ph"),
    });
  });

  const coordinator = await asCoordinator("coord-e2e", "coorde2e@isufst.edu.ph");
  await assertSucceeds(
    setDoc(doc(coordinator, "facultyInvites/e2einvitee@isufst.edu.ph"), {
      role: "coordinator",
      invitedBy: "coord-e2e",
      createdAt: serverTimestamp(),
      consumedAt: null,
      college: "CICT",
      specialization: "Data Science",
    })
  );

  const invitee = env
    .authenticatedContext("e2e-invitee", {
      email: "e2einvitee@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  // 1. the role
  await assertSucceeds(
    updateDoc(doc(invitee, "users/e2e-invitee"), { role: "coordinator" })
  );
  // 2. the profile fields the invite carried
  await assertSucceeds(
    updateDoc(doc(invitee, "users/e2e-invitee"), {
      college: "CICT",
      specialization: "Data Science",
    })
  );
  // 3. consume the invite
  await assertSucceeds(
    updateDoc(doc(invitee, "facultyInvites/e2einvitee@isufst.edu.ph"), {
      consumedAt: serverTimestamp(),
    })
  );

  // ...and the directory write that the next sign-in performs.
  await assertSucceeds(
    setDoc(
      doc(invitee, "facultyDirectory/e2e-invitee"),
      { fullName: "Dr. E2E", role: "coordinator" },
      { merge: true }
    )
  );

  await env.withSecurityRulesDisabled(async (ctx) => {
    const u = await getDoc(doc(ctx.firestore(), "users/e2e-invitee"));
    assert.equal(u.data().role, "coordinator");
    assert.equal(u.data().college, "CICT");
    assert.equal(u.data().specialization, "Data Science");
  });
});

test("the promotion may NOT bundle role and college into one write", async () => {
  // The reason promoteFromInvite splits its writes. Bundled, this satisfies
  // neither onlyChanged branch.
  const invitee = asUser("bundle-uid", "bundle@isufst.edu.ph");

  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/bundle-uid"), {
      ...studentProfile("bundle@isufst.edu.ph"),
    });
    await setDoc(doc(db, "facultyInvites/bundle@isufst.edu.ph"), {
      role: "faculty", invitedBy: "seed", consumedAt: null, college: "CICT",
    });
  });

  await assertFails(
    updateDoc(doc(invitee, "users/bundle-uid"), {
      role: "faculty",
      college: "CICT",
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

// --- Fix wave: nominationsSubmittedAt, the letter date Form 1 prints,
// stamped by the same write that flips status to nominationPendingConforme
// (ThesisRepository.submitNominations' batch). Same request.time pin as the
// coordinator/dean timestamps above — a leader must not be able to backdate
// the date on their own submission letter.

test("a leader MAY submit nominations with a server-timestamped nominationsSubmittedAt", async () => {
  await seedThesis("t-submit-stamp-ok", "student-uid", "draft");
  await assertSucceeds(
    updateDoc(doc(student, "theses/t-submit-stamp-ok"), {
      status: "nominationPendingConforme",
      nominationsSubmittedAt: serverTimestamp(),
    })
  );
});

test("a leader may NOT backdate nominationsSubmittedAt when submitting nominations", async () => {
  await seedThesis("t-submit-stamp-bad", "student-uid", "draft");
  await assertFails(
    updateDoc(doc(student, "theses/t-submit-stamp-bad"), {
      status: "nominationPendingConforme",
      nominationsSubmittedAt: Timestamp.fromDate(new Date("1999-01-01")),
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
// Three more faculty: a full roster needs an adviser plus three panelists
// (fac-a..fac-d), and `fac-e` is the outsider the C1 scoping tests use.
await seedUser("fac-c", "faculty", "facc@isufst.edu.ph");
await seedUser("fac-d", "faculty", "facd@isufst.edu.ph");
await seedUser("fac-e", "faculty", "face@isufst.edu.ph");
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

// Seeds the exact roster `submitNominations` writes: one adviser, three
// panelists, and one ex-officio seat each for the dean and the coordinator.
// A single-nomination fixture cannot exercise `respondToNomination` honestly —
// the whole point of the sibling reads is deciding whether OTHER seats are
// still outstanding, and with one document there are none.
async function seedFullRoster(thesisId, status = "nominationPendingConforme", overrides = {}) {
  await seedThesis(thesisId, LEADER, status);
  await seedNomination(thesisId, "fac-a", {
    nomineeUid: "fac-a", position: "adviser",
    conformeStatus: overrides["fac-a"] ?? "pending",
  });
  await seedNomination(thesisId, "fac-b", {
    nomineeUid: "fac-b", position: "panelist",
    conformeStatus: overrides["fac-b"] ?? "pending",
  });
  await seedNomination(thesisId, "fac-c", {
    nomineeUid: "fac-c", position: "panelist",
    conformeStatus: overrides["fac-c"] ?? "pending",
  });
  await seedNomination(thesisId, "fac-d", {
    nomineeUid: "fac-d", position: "panelist",
    conformeStatus: overrides["fac-d"] ?? "pending",
  });
  await seedNomination(thesisId, "dean-x", {
    nomineeUid: "dean-x", position: "dean",
    exOfficio: true, conformeStatus: "exOfficio",
  });
  await seedNomination(thesisId, "coord-x", {
    nomineeUid: "coord-x", position: "coordinator",
    exOfficio: true, conformeStatus: "exOfficio",
  });
}

// `ThesisRepository.respondToNomination`, replayed call for call:
//   1. `_nominationIds()` — a plain LIST of the whole subcollection, outside
//      the transaction (Transaction.get takes no Query in cloud_firestore).
//   2. a transaction that gets the thesis, then gets EVERY sibling nomination,
//      then writes the caller's conforme and — if nothing is outstanding —
//      flips the thesis status.
async function replayRespondToNomination(db, thesisId, nomineeUid, accept = true) {
  const listed = await getDocs(collection(db, `theses/${thesisId}/nominations`));
  const ids = listed.docs.map((d) => d.id);

  return runTransaction(db, async (tx) => {
    const thesisSnap = await tx.get(doc(db, `theses/${thesisId}`));
    const noms = [];
    for (const id of ids) {
      const snap = await tx.get(doc(db, `theses/${thesisId}/nominations/${id}`));
      if (snap.exists()) noms.push({ id, ...snap.data() });
    }
    if (thesisSnap.data().status !== "nominationPendingConforme") {
      throw new Error("wrong status");
    }
    tx.update(doc(db, `theses/${thesisId}/nominations/${nomineeUid}`), {
      conformeStatus: accept ? "accepted" : "declined",
      respondedAt: serverTimestamp(),
      declineReason: null,
    });
    if (!accept) return;
    const outstanding = noms.filter(
      (n) => n.id !== nomineeUid && !n.exOfficio &&
             n.conformeStatus !== "accepted"
    );
    if (outstanding.length === 0) {
      tx.update(doc(db, `theses/${thesisId}`), {
        status: "nominationPendingCoordinator",
      });
    }
  });
}

// --- CRITICAL C1: a nominee must be able to read their co-nominees ------
//
// House rule for this block, as everywhere above: every deny is paired with an
// allow that walks the SAME path with the right user.

test("C1 allow: a nominee MAY list the whole nominations subcollection of their own thesis", async () => {
  // The exact first call `respondToNomination` makes, and the one that was
  // denied. A `list` never binds {nomineeUid}, so the own-seat arm cannot
  // carry it — only the new nominee arm can. Six documents, not one.
  await seedFullRoster("c1r-list");
  const nominee = asUser("fac-b", "facb@isufst.edu.ph");
  const snap = await assertSucceeds(
    getDocs(collection(nominee, "theses/c1r-list/nominations"))
  );
  assert.equal(snap.docs.length, 6);
});

test("C1 allow: a nominee MAY get a CO-nominee's document on their own thesis", async () => {
  // The second denied call: the per-sibling tx.get inside the transaction.
  await seedFullRoster("c1r-sibling");
  const nominee = asUser("fac-b", "facb@isufst.edu.ph");
  await assertSucceeds(
    getDoc(doc(nominee, "theses/c1r-sibling/nominations/fac-a"))
  );
});

test("C1 attack: a faculty member with NO seat on the thesis may NOT list its nominations", async () => {
  // Scoping, negative half. `fac-e` holds no nomination on this thesis; the
  // allow above proves the very same list succeeds on the very same path for
  // someone who does, so this denial is the rule and not a broken fixture.
  await seedFullRoster("c1r-outsider");
  await assertFails(
    getDocs(collection(asUser("fac-e", "face@isufst.edu.ph"),
      "theses/c1r-outsider/nominations"))
  );
});

test("C1 attack: a nominee on one thesis may NOT read the nominations of ANOTHER thesis", async () => {
  // The enumeration the new arm must not enable. `fac-b` genuinely sits on
  // c1r-mine (proved by the allow above, same user, same shape) and holds no
  // seat on c1r-theirs, whose roster is faculty they have nothing to do with.
  await seedFullRoster("c1r-mine");
  await seedThesis("c1r-theirs", "stud-b", "nominationPendingConforme");
  await seedNomination("c1r-theirs", "fac-e", { nomineeUid: "fac-e" });
  const nominee = asUser("fac-b", "facb@isufst.edu.ph");

  await assertSucceeds(
    getDocs(collection(nominee, "theses/c1r-mine/nominations"))
  );
  await assertFails(
    getDocs(collection(nominee, "theses/c1r-theirs/nominations"))
  );
  await assertFails(
    getDoc(doc(nominee, "theses/c1r-theirs/nominations/fac-e"))
  );
});

test("C1: the nominee arm does NOT reopen the unfiltered collection-group scan", async () => {
  // The cross-thesis match block is a different rule and is untouched. A
  // nominee still cannot sweep every nomination in the database, nor run the
  // inbox query for somebody else.
  await seedFullRoster("c1r-cg");
  const nominee = asUser("fac-b", "facb@isufst.edu.ph");
  await assertFails(getDocs(collectionGroup(nominee, "nominations")));
  await assertFails(
    getDocs(query(collectionGroup(nominee, "nominations"),
      where("nomineeUid", "==", "fac-a")))
  );
});

test("(a) allow: respondToNomination replayed CALL FOR CALL — list, sibling gets, accept, advance", async () => {
  // This replaces a fixture that seeded ONE nomination and read only the
  // caller's own document — a shape the client never issues, which is why it
  // passed while the real call was denied throughout.
  //
  // It also still covers why the advance rule accepts 'pending' as well as
  // 'accepted': rules evaluate every write in a transaction against the state
  // BEFORE it, so the acceptance written below is invisible to the rule
  // guarding the status flip beside it.
  //
  // Every other nominee has already accepted, so this caller is the last
  // outstanding one and the transaction takes the advance branch.
  await seedFullRoster("a-txn", "nominationPendingConforme", {
    "fac-a": "accepted", "fac-c": "accepted", "fac-d": "accepted",
  });
  const nominee = asUser("fac-b", "facb@isufst.edu.ph");

  await assertSucceeds(replayRespondToNomination(nominee, "a-txn", "fac-b"));

  // Read back through a genuinely authorized reader (the leader), not with
  // rules disabled — the effect has to be visible on the real read surface.
  const t = await getDoc(doc(leader, "theses/a-txn"));
  assert.equal(t.data().status, "nominationPendingCoordinator");
  const n = await getDoc(doc(leader, "theses/a-txn/nominations/fac-b"));
  assert.equal(n.data().conformeStatus, "accepted");
});

test("(a) allow: a NON-final nominee's response is recorded without advancing", async () => {
  // The other branch of the same call: siblings are still outstanding, so the
  // transaction writes only the conforme. Proves the sibling reads are load
  // bearing rather than incidental.
  await seedFullRoster("a-txn-partial");
  const nominee = asUser("fac-b", "facb@isufst.edu.ph");

  await assertSucceeds(
    replayRespondToNomination(nominee, "a-txn-partial", "fac-b")
  );

  const t = await getDoc(doc(leader, "theses/a-txn-partial"));
  assert.equal(t.data().status, "nominationPendingConforme");
  const n = await getDoc(doc(leader, "theses/a-txn-partial/nominations/fac-b"));
  assert.equal(n.data().conformeStatus, "accepted");
});

test("(a) attack: a nominee may NOT use their seat to write a CO-nominee's conforme", async () => {
  // The read widening must not have become a write widening. The allow above
  // proves fac-b can write their OWN seat on this same path.
  await seedFullRoster("a-txn-cross");
  await assertFails(
    updateDoc(doc(asUser("fac-b", "facb@isufst.edu.ph"),
      "theses/a-txn-cross/nominations/fac-a"), {
      conformeStatus: "accepted", respondedAt: serverTimestamp(),
      declineReason: null,
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

// `upsertOwnEntry` no longer writes `college`/`specialization` when the
// profile carries neither — which is every real faculty account, since
// nothing in the app ever fills them — and its plain `set` became a merge, so
// an administrator's Console values survive the next sign-in instead of being
// nulled. That reasoning rests on a claim about the rules that has to be
// checked rather than assumed: under `{ merge: true }`, `request.resource.data`
// is the merged RESULT, not the written subset, so `keys().hasOnly([...])` and
// the `role == myRole()` pin still govern the whole document.
test("(g) allow: a merge write of only the app-owned fields is accepted, and preserves the rest", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "facultyDirectory/fac-a"), {
      fullName: "Dr. A", role: "faculty",
      college: "CICT", specialization: "Software Engineering",
    });
  });

  await assertSucceeds(
    setDoc(
      doc(asUser("fac-a", "faca@isufst.edu.ph"), "facultyDirectory/fac-a"),
      { fullName: "Dr. A", role: "faculty" },
      { merge: true }
    )
  );

  await env.withSecurityRulesDisabled(async (ctx) => {
    const after = await getDoc(doc(ctx.firestore(), "facultyDirectory/fac-a"));
    assert.equal(after.data().college, "CICT");
    assert.equal(after.data().specialization, "Software Engineering");
  });
});

test("(g) attack: a merge write may NOT smuggle in a role the caller does not hold", async () => {
  // The merge must not become a hole: writing a subset does not exempt the
  // document from the role pin.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "facultyDirectory/fac-a"), {
      fullName: "Dr. A", role: "faculty", college: "CICT",
    });
  });

  await assertFails(
    setDoc(
      doc(asUser("fac-a", "faca@isufst.edu.ph"), "facultyDirectory/fac-a"),
      { role: "dean" },
      { merge: true }
    )
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

// =====================================================================
// END TO END — the real client sequence, replayed against the real rules.
//
// C1 got through because every layer was checked in isolation: each rule had
// a test, each repository method had a test, and no test ever issued the
// *sequence* of calls a real user's taps produce. This one does, in order,
// with the right authenticated context for each actor and with no
// `withSecurityRulesDisabled` seeding of anything the client itself writes.
//
// COVERAGE, stated plainly. This is the client's Firestore traffic replayed
// call for call — same paths, same field maps, same batch/transaction
// grouping, same ordering, same actors — under the deployed
// `firestore.rules`. What it is NOT: it does not execute the Dart in
// `ThesisRepository`, so a defect that lives purely in Dart (a wrong local
// filter, a bad `Timestamp` conversion) is out of its reach — those remain the
// Dart suite's job. What it does catch, and what nothing else in either suite
// could, is a client/rules disagreement: a call the Dart issues that the rules
// refuse. That is exactly the class C1 belonged to. The two shapes are kept in
// step by hand; the field maps below are transcribed from
// `ThesisRepository._nominationMap`/`createThesis`/`approve`.
// =====================================================================

test("END TO END: create -> submit -> four conformes -> recommend -> approve, under the real rules", async () => {
  const T = "e2e-thesis";
  const nominee = (uid) => asUser(uid, `${uid}@isufst.edu.ph`);

  // --- 1. the leader creates the thesis (createThesis) ---------------
  await assertSucceeds(
    setDoc(doc(leader, `theses/${T}`), {
      leaderUid: LEADER, workingTitle: "A Real Thesis",
      memberNames: ["Member Two"], college: "CICT", program: "BSIT",
      semester: "First", academicYear: "2026-2027", status: "draft",
      adviserUid: null, panelistUids: [],
      coordinatorRecommendedAt: null, coordinatorRecommendedBy: null,
      deanApprovedAt: null, deanApprovedBy: null,
      createdAt: serverTimestamp(),
    })
  );

  // --- 2. submitNominations' batch: 6 creates + the status flip -----
  // One adviser, three panelists, and one ex-officio seat each for the dean
  // and the coordinator — the full roster the nominate screen produces, in
  // one commit, exactly as `submitNominations` writes it.
  const nom = (uid, position, exOfficio) => ({
    nomineeUid: uid, nomineeName: `Dr. ${uid}`, position,
    exOfficio, conformeStatus: exOfficio ? "exOfficio" : "pending",
    respondedAt: null, declineReason: null,
  });
  const batch = writeBatch(leader);
  batch.set(doc(leader, `theses/${T}/nominations/fac-a`), nom("fac-a", "adviser", false));
  batch.set(doc(leader, `theses/${T}/nominations/fac-b`), nom("fac-b", "panelist", false));
  batch.set(doc(leader, `theses/${T}/nominations/fac-c`), nom("fac-c", "panelist", false));
  batch.set(doc(leader, `theses/${T}/nominations/fac-d`), nom("fac-d", "panelist", false));
  batch.set(doc(leader, `theses/${T}/nominations/dean-x`), nom("dean-x", "dean", true));
  batch.set(doc(leader, `theses/${T}/nominations/coord-x`), nom("coord-x", "coordinator", true));
  batch.update(doc(leader, `theses/${T}`), {
    status: "nominationPendingConforme",
    nominationsSubmittedAt: serverTimestamp(),
  });
  await assertSucceeds(batch.commit());

  // --- 3. each nominee's inbox query, then their respondToNomination --
  // All four, in turn — the ex-officio pair are never asked. The first three
  // must record without advancing; the fourth is the last outstanding seat
  // and must carry the thesis to the coordinator.
  for (const uid of ["fac-a", "fac-b", "fac-c", "fac-d"]) {
    const db = nominee(uid);
    // watchMyPendingNominations
    await assertSucceeds(
      getDocs(query(collectionGroup(db, "nominations"),
        where("nomineeUid", "==", uid)))
    );
    // the inbox reads the parent thesis for its title
    await assertSucceeds(getDoc(doc(db, `theses/${T}`)));
    // respondToNomination — the list, the sibling gets, the writes
    await assertSucceeds(replayRespondToNomination(db, T, uid));
  }

  const afterConforme = await getDoc(doc(leader, `theses/${T}`));
  assert.equal(afterConforme.data().status, "nominationPendingCoordinator");

  // --- 4. the coordinator recommends --------------------------------
  const coord = asUser("coord-x", "coordx@isufst.edu.ph");
  await assertSucceeds(
    getDocs(query(collection(coord, "theses"),
      where("status", "==", "nominationPendingCoordinator")))
  );
  await assertSucceeds(
    updateDoc(doc(coord, `theses/${T}`), {
      status: "nominationPendingDean",
      coordinatorRecommendedAt: serverTimestamp(),
      coordinatorRecommendedBy: "coord-x",
    })
  );

  // --- 5. the dean approves (ThesisRepository.approve) ---------------
  const dean = asUser("dean-x", "deanx@isufst.edu.ph");
  await assertSucceeds(
    getDocs(query(collection(dean, "theses"),
      where("status", "==", "nominationPendingDean")))
  );
  const listed = await getDocs(collection(dean, `theses/${T}/nominations`));
  const ids = listed.docs.map((d) => d.id);
  await assertSucceeds(
    runTransaction(dean, async (tx) => {
      await tx.get(doc(dean, `theses/${T}`));
      const all = [];
      for (const id of ids) {
        const s = await tx.get(doc(dean, `theses/${T}/nominations/${id}`));
        if (s.exists()) all.push({ id, ...s.data() });
      }
      const accepted = all.filter((n) => n.conformeStatus === "accepted");
      const adviser = accepted.filter((n) => n.position === "adviser");
      const panelists = accepted
        .filter((n) => n.position === "panelist" && !n.exOfficio)
        .map((n) => n.nomineeUid);
      assert.equal(adviser.length, 1);
      assert.equal(panelists.length, 3);
      tx.update(doc(dean, `theses/${T}`), {
        status: "nominationApproved",
        adviserUid: adviser[0].nomineeUid,
        panelistUids: panelists,
        deanApprovedAt: serverTimestamp(),
        deanApprovedBy: "dean-x",
      });
    })
  );

  // --- 6. the leader's Form 1 reads ---------------------------------
  const finalThesis = await assertSucceeds(getDoc(doc(leader, `theses/${T}`)));
  const finalNoms =
    await assertSucceeds(getDocs(collection(leader, `theses/${T}/nominations`)));

  assert.equal(finalThesis.data().status, "nominationApproved");
  assert.equal(finalThesis.data().adviserUid, "fac-a");
  assert.deepEqual([...finalThesis.data().panelistUids].sort(),
    ["fac-b", "fac-c", "fac-d"]);
  assert.equal(finalNoms.docs.length, 6);
  // The ex-officio pair are on the roster and print on Form 1, but were never
  // asked to accept and never land on panelistUids.
  const byId = Object.fromEntries(finalNoms.docs.map((d) => [d.id, d.data()]));
  for (const uid of ["dean-x", "coord-x"]) {
    assert.equal(byId[uid].conformeStatus, "exOfficio");
    assert.equal(byId[uid].exOfficio, true);
    assert.ok(!finalThesis.data().panelistUids.includes(uid));
  }
});

// --- M1b title defence ------------------------------------------------

// Memoised, unlike `asUser` above: these tests reach for the same uid more
// than once (a deny and its allow control are often two different people, and
// the same person recurs across tests). Re-deriving a Firestore instance for a
// uid that has already issued a request throws "Firestore has already been
// started and its settings can no longer be changed" — a harness error that
// would masquerade as a rules failure, and worse, would satisfy an
// `assertFails` for entirely the wrong reason.
const defenceDbs = new Map();
function asDefenceUser(uid, email) {
  if (!defenceDbs.has(uid)) {
    defenceDbs.set(
      uid,
      env.authenticatedContext(uid, { email, email_verified: true }).firestore()
    );
  }
  return defenceDbs.get(uid);
}

function defenceThesis(status, extra = {}) {
  return {
    leaderUid: "leader-uid",
    status,
    panelistUids: ["pan-uid"],
    adviserUid: "adv-uid",
    memberNames: [],
    workingTitle: "T",
    college: "CICT",
    program: "BSIT",
    semester: "First",
    academicYear: "2026-2027",
    titleRound: 1,
    ...extra,
  };
}

// Takes the Firestore handle, NOT the context. `ctx.firestore()` may only be
// called ONCE per context — a second call throws "Firestore has already been
// started", which `assertFails` would happily swallow as though it were a
// rules denial, and every deny test in this block would pass for the wrong
// reason. Observed: eight of these tests "passed their denial" that way before
// the seed was reshaped to take a single handle.
async function seedDefence(db, { status = "titlePendingDefence", decided = null } = {}) {
  await setDoc(
    doc(db, "theses/td1"),
    defenceThesis(status, decided ? { titleDecidedAt: decided } : {})
  );
  await setDoc(doc(db, "theses/td1/candidateTitles/ct1"), {
    titleText: "Candidate one", justificationPath: "p",
    justificationUrl: "u", round: 1,
  });
  await setDoc(doc(db, "theses/td1/titleComments/cm1"), {
    candidateTitleId: "ct1", authorUid: "pan-uid",
    authorName: "Dr. Panel", authorRole: "Panel Member",
    body: "Too broad.", createdAt: Timestamp.now(),
  });
  await setDoc(doc(db, "theses/td1/nominations/pan-uid"), {
    nomineeUid: "pan-uid", nomineeName: "Dr. Panel", position: "panelist",
    exOfficio: false, conformeStatus: "accepted",
  });
}

test("M1b allow: a panel member MAY read comments during the defence", async () => {
  await env.withSecurityRulesDisabled((ctx) => seedDefence(ctx.firestore()));
  const panel = asDefenceUser("pan-uid", "pan@isufst.edu.ph");
  await assertSucceeds(getDocs(collection(panel, "theses/td1/titleComments")));
});

test("M1b attack: the leader may NOT read comments before the decision", async () => {
  await env.withSecurityRulesDisabled((ctx) => seedDefence(ctx.firestore()));
  const leader = asDefenceUser("leader-uid", "leader@isufst.edu.ph");
  await assertFails(getDocs(collection(leader, "theses/td1/titleComments")));
});

test("M1b allow: the leader MAY read comments once the Dean has decided", async () => {
  // The control for the test above: same path, same user, one field changed.
  await env.withSecurityRulesDisabled((ctx) =>
    seedDefence(ctx.firestore(), { status: "titleApproved", decided: Timestamp.now() }));
  const leader = asDefenceUser("leader-uid", "leader@isufst.edu.ph");
  await assertSucceeds(getDocs(collection(leader, "theses/td1/titleComments")));
});

// Regression for the round-2 comment leak (final-branch-review C1).
//
// Nothing used to clear `titleDecidedAt` / `titleDecidedBy` /
// `titleRejectionRemark` when a rejected set was resubmitted, so
// `titleDecided()` stayed true for the rest of the thesis's life and the
// leader read the panel's round-2 remarks live, mid-defence. Reproduced on
// the emulator before the fix: LEAKED: [ 'ROUND TWO REMARK, MID-DEFENCE' ].
//
// The state under test only exists across a task seam — pending defence WITH
// a prior decision on the record — which is why no per-task test seeded it.
// The resubmission below is the real client batch, field deletes included.
async function resubmitIntoRoundTwo(leader, thesisId) {
  const batch = writeBatch(leader);
  batch.set(doc(leader, `theses/${thesisId}/candidateTitles/r2a`), {
    titleText: "Round two candidate", justificationPath: "p",
    justificationUrl: "u", round: 2, position: 0, submittedAt: serverTimestamp(),
  });
  batch.update(doc(leader, `theses/${thesisId}`), {
    status: "titlePendingDefence", titleRound: 2,
    titlesSubmittedAt: serverTimestamp(),
    presentationPath: "pp2", presentationUrl: "pu2",
    titleDecidedAt: deleteField(),
    titleDecidedBy: deleteField(),
    titleRejectionRemark: deleteField(),
  });
  return batch.commit();
}

test("M1b attack: after a resubmission the leader may NOT read the new round's comments", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "theses/tdr2"), defenceThesis("titleRejected", {
      titleDecidedAt: Timestamp.now(),
      titleDecidedBy: "dean-uid",
      titleRejectionRemark: "Too broad.",
    }));
    await setDoc(doc(db, "theses/tdr2/nominations/pan-uid"), {
      nomineeUid: "pan-uid", nomineeName: "Dr. Panel", position: "panelist",
      exOfficio: false, conformeStatus: "accepted",
    });
    await setDoc(doc(db, "users/dean-uid"), {
      ...studentProfile("dean@isufst.edu.ph"), role: "dean" });
  });

  const leader = asDefenceUser("leader-uid", "leader@isufst.edu.ph");
  await assertSucceeds(resubmitIntoRoundTwo(leader, "tdr2"));

  // The panel remarks while round 2 is under way.
  const panel = asDefenceUser("pan-uid", "pan@isufst.edu.ph");
  await assertSucceeds(setDoc(doc(panel, "theses/tdr2/titleComments/r2c"), {
    candidateTitleId: "r2a", authorUid: "pan-uid", authorName: "Dr. Panel",
    authorRole: "Panel Member", body: "ROUND TWO REMARK, MID-DEFENCE",
    createdAt: serverTimestamp(),
  }));

  // THE DENIAL: the defence is live again, so the leader is shut out again.
  await assertFails(getDocs(collection(leader, "theses/tdr2/titleComments")));

  // ALLOW CONTROL on the very same path, same user, same documents: the Dean
  // decides round 2 and the remarks open up. Without it the denial above
  // could be a broken seed rather than a working rule.
  const dean = asDefenceUser("dean-uid", "dean@isufst.edu.ph");
  await assertSucceeds(updateDoc(doc(dean, "theses/tdr2"), {
    status: "titleApproved", approvedTitleId: "r2a",
    titleDecidedBy: "dean-uid", titleDecidedAt: serverTimestamp(),
  }));
  const opened = await assertSucceeds(
    getDocs(collection(leader, "theses/tdr2/titleComments")));
  assert.deepEqual(opened.docs.map((d) => d.data().body),
    ["ROUND TWO REMARK, MID-DEFENCE"]);
});

test("M1b attack: a resubmission may NOT forge a decision instead of clearing one", async () => {
  // The other half of the fix. Widening `onlyChanged` to admit the three
  // decision fields, without pinning them to null, would hand the leader a
  // way to SET `titleDecidedAt` on their own thesis and unlock the comments
  // on a defence nobody has decided.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "theses/tdr3"),
      defenceThesis("nominationApproved", { titleRound: 0 }));
  });
  const leader = asDefenceUser("leader-uid", "leader@isufst.edu.ph");
  await assertFails(updateDoc(doc(leader, "theses/tdr3"), {
    status: "titlePendingDefence", titleRound: 1,
    titlesSubmittedAt: serverTimestamp(),
    presentationPath: "pp", presentationUrl: "pu",
    titleDecidedAt: serverTimestamp(), titleDecidedBy: "leader-uid",
  }));
  // Control: the identical write with the fields cleared instead of forged.
  await assertSucceeds(updateDoc(doc(leader, "theses/tdr3"), {
    status: "titlePendingDefence", titleRound: 1,
    titlesSubmittedAt: serverTimestamp(),
    presentationPath: "pp", presentationUrl: "pu",
    titleDecidedAt: deleteField(), titleDecidedBy: deleteField(),
    titleRejectionRemark: deleteField(),
  }));
});

test("M1b attack: the leader may NEVER read composing indicators", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await seedDefence(db, { status: "titleApproved", decided: Timestamp.now() });
    await setDoc(doc(db, "theses/td1/titleComposing/pan-uid"), {
      name: "Dr. Panel", role: "Panel Member", candidateTitleId: "ct1",
      updatedAt: Timestamp.now(),
    });
  });
  const leader = asDefenceUser("leader-uid", "leader@isufst.edu.ph");
  // Decided, so comments are readable — composing still is not.
  await assertSucceeds(getDocs(collection(leader, "theses/td1/titleComments")));
  await assertFails(getDocs(collection(leader, "theses/td1/titleComposing")));
  // Control on the very same path: the panel member reads it fine.
  const panel = asDefenceUser("pan-uid", "pan@isufst.edu.ph");
  await assertSucceeds(getDocs(collection(panel, "theses/td1/titleComposing")));
});

test("M1b attack: a comment may NOT be edited or deleted", async () => {
  await env.withSecurityRulesDisabled((ctx) => seedDefence(ctx.firestore()));
  const panel = asDefenceUser("pan-uid", "pan@isufst.edu.ph");
  await assertFails(updateDoc(doc(panel, "theses/td1/titleComments/cm1"),
    { body: "rewritten" }));
  await assertFails(deleteDoc(doc(panel, "theses/td1/titleComments/cm1")));
  // Control: the same author on the same collection MAY still append.
  await assertSucceeds(setDoc(doc(panel, "theses/td1/titleComments/appended"), {
    candidateTitleId: "ct1", authorUid: "pan-uid", authorName: "Dr. Panel",
    authorRole: "Panel Member", body: "a new remark", createdAt: serverTimestamp(),
  }));
});

test("M1b attack: a panel member may NOT author a comment as someone else", async () => {
  await env.withSecurityRulesDisabled((ctx) => seedDefence(ctx.firestore()));
  const panel = asDefenceUser("pan-uid", "pan@isufst.edu.ph");
  await assertFails(setDoc(doc(panel, "theses/td1/titleComments/forged"), {
    candidateTitleId: "ct1", authorUid: "adv-uid", authorName: "Dr. Adviser",
    authorRole: "Adviser", body: "not mine", createdAt: serverTimestamp(),
  }));
  // Control: the same write with their own uid is accepted.
  await assertSucceeds(setDoc(doc(panel, "theses/td1/titleComments/mine"), {
    candidateTitleId: "ct1", authorUid: "pan-uid", authorName: "Dr. Panel",
    authorRole: "Panel Member", body: "mine", createdAt: serverTimestamp(),
  }));
});

test("M1b attack: the leader may NOT comment on their own defence", async () => {
  await env.withSecurityRulesDisabled((ctx) => seedDefence(ctx.firestore()));
  const leader = asDefenceUser("leader-uid", "leader@isufst.edu.ph");
  await assertFails(setDoc(doc(leader, "theses/td1/titleComments/byleader"), {
    candidateTitleId: "ct1", authorUid: "leader-uid", authorName: "The Leader",
    authorRole: "Student", body: "we think it is fine", createdAt: serverTimestamp(),
  }));
  // Control: a panel member writing the same shape on the same path succeeds.
  const panel = asDefenceUser("pan-uid", "pan@isufst.edu.ph");
  await assertSucceeds(setDoc(doc(panel, "theses/td1/titleComments/bypanel"), {
    candidateTitleId: "ct1", authorUid: "pan-uid", authorName: "Dr. Panel",
    authorRole: "Panel Member", body: "we think it is fine",
    createdAt: serverTimestamp(),
  }));
});

test("M1b attack: an outsider may read NOTHING of another group's defence", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await seedDefence(db, { status: "titleApproved", decided: Timestamp.now() });
    await setDoc(doc(db, "theses/td1/titleComposing/pan-uid"), {
      name: "Dr. Panel", role: "Panel Member", candidateTitleId: "ct1",
      updatedAt: Timestamp.now(),
    });
  });
  const outsider = asDefenceUser("outsider-uid", "outsider@isufst.edu.ph");
  await assertFails(getDocs(collection(outsider, "theses/td1/candidateTitles")));
  await assertFails(getDocs(collection(outsider, "theses/td1/titleComments")));
  await assertFails(getDocs(collection(outsider, "theses/td1/titleComposing")));
  // Control: the panel member on this thesis reads all three.
  const panel = asDefenceUser("pan-uid", "pan@isufst.edu.ph");
  await assertSucceeds(getDocs(collection(panel, "theses/td1/candidateTitles")));
  await assertSucceeds(getDocs(collection(panel, "theses/td1/titleComments")));
  await assertSucceeds(getDocs(collection(panel, "theses/td1/titleComposing")));
});

test("M1b attack: a panel member may NOT plant or clear someone else's composing marker", async () => {
  await env.withSecurityRulesDisabled((ctx) => seedDefence(ctx.firestore()));
  const panel = asDefenceUser("pan-uid", "pan@isufst.edu.ph");
  await assertFails(setDoc(doc(panel, "theses/td1/titleComposing/adv-uid"), {
    name: "Dr. Adviser", role: "Adviser", candidateTitleId: "ct1",
    updatedAt: serverTimestamp(),
  }));
  // Control: their own marker, same shape, same collection.
  await assertSucceeds(setDoc(doc(panel, "theses/td1/titleComposing/pan-uid"), {
    name: "Dr. Panel", role: "Panel Member", candidateTitleId: "ct1",
    updatedAt: serverTimestamp(),
  }));
  await assertFails(deleteDoc(doc(panel, "theses/td1/titleComposing/adv-uid")));
  await assertSucceeds(deleteDoc(doc(panel, "theses/td1/titleComposing/pan-uid")));
});

// A nominee who explicitly declined to serve still had a nomination
// DOCUMENT sitting there — undeletable once the thesis left `draft` — and
// `isOnPanel()` used to grant access on mere existence via `hasNomination()`,
// never checking `conformeStatus`. That let a declined nominee keep reading
// the panel's private remarks, keep reading who was typing, and keep filing
// comments into the official record under whatever `authorRole` they chose.
// `declined-uid` is deliberately NOT in `panelistUids` (seedDefence only ever
// puts "pan-uid" there), so these assertions exercise the nomination arm of
// `isOnPanel()` in isolation — no other arm could be granting access.
test("M1b attack: a nominee who DECLINED may NOT read comments, read composing, or comment", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await seedDefence(db);
    await setDoc(doc(db, "theses/td1/nominations/declined-uid"), {
      nomineeUid: "declined-uid", nomineeName: "Dr. Declined", position: "panelist",
      exOfficio: false, conformeStatus: "declined",
    });
    await setDoc(doc(db, "theses/td1/titleComposing/pan-uid"), {
      name: "Dr. Panel", role: "Panel Member", candidateTitleId: "ct1",
      updatedAt: Timestamp.now(),
    });
  });
  const declined = asDefenceUser("declined-uid", "declined@isufst.edu.ph");
  await assertFails(getDocs(collection(declined, "theses/td1/titleComments")));
  await assertFails(getDocs(collection(declined, "theses/td1/titleComposing")));
  await assertFails(setDoc(doc(declined, "theses/td1/titleComments/byDeclined"), {
    candidateTitleId: "ct1", authorUid: "declined-uid", authorName: "Dr. Declined",
    authorRole: "Panel Member", body: "should not land", createdAt: serverTimestamp(),
  }));
});

test("M1b allow: the SAME nominee, ACCEPTED instead of declined, on the same path, can do all three", async () => {
  // The control for the test above: same thesis, same uid, same collections —
  // only `conformeStatus` changes. Proves the denial above was the
  // `conformeStatus` gate and not a wrong path or a missing prerequisite doc.
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await seedDefence(db);
    await setDoc(doc(db, "theses/td1/nominations/declined-uid"), {
      nomineeUid: "declined-uid", nomineeName: "Dr. Declined", position: "panelist",
      exOfficio: false, conformeStatus: "accepted",
    });
    await setDoc(doc(db, "theses/td1/titleComposing/pan-uid"), {
      name: "Dr. Panel", role: "Panel Member", candidateTitleId: "ct1",
      updatedAt: Timestamp.now(),
    });
  });
  const accepted = asDefenceUser("declined-uid", "declined@isufst.edu.ph");
  await assertSucceeds(getDocs(collection(accepted, "theses/td1/titleComments")));
  await assertSucceeds(getDocs(collection(accepted, "theses/td1/titleComposing")));
  await assertSucceeds(setDoc(doc(accepted, "theses/td1/titleComments/byAccepted"), {
    candidateTitleId: "ct1", authorUid: "declined-uid", authorName: "Dr. Declined",
    authorRole: "Panel Member", body: "now allowed", createdAt: serverTimestamp(),
  }));
});

// The two people who chair the defence — Coordinator and Dean — sit on
// every panel BY OFFICE and are never asked to accept, so their
// `conformeStatus` is permanently "exOfficio". This is the case the fix
// could most easily break: a gate on ['accepted'] alone would lock them out.
// `exo-uid` is, like `declined-uid` above, deliberately absent from
// `panelistUids`, so this exercises the nomination arm alone.
test("M1b allow: an EX OFFICIO nominee (Coordinator/Dean) retains panel access", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await seedDefence(db);
    await setDoc(doc(db, "theses/td1/nominations/exo-uid"), {
      nomineeUid: "exo-uid", nomineeName: "The Coordinator", position: "coordinator",
      exOfficio: true, conformeStatus: "exOfficio",
    });
  });
  const exo = asDefenceUser("exo-uid", "exo@isufst.edu.ph");
  await assertSucceeds(getDocs(collection(exo, "theses/td1/titleComments")));
  await assertSucceeds(getDocs(collection(exo, "theses/td1/titleComposing")));
  await assertSucceeds(setDoc(doc(exo, "theses/td1/titleComments/byExo"), {
    candidateTitleId: "ct1", authorUid: "exo-uid", authorName: "The Coordinator",
    authorRole: "Coordinator", body: "chairing the defence", createdAt: serverTimestamp(),
  }));
});

test("M1b attack: a candidate title may NOT be edited after submission", async () => {
  await env.withSecurityRulesDisabled((ctx) => seedDefence(ctx.firestore()));
  const leader = asDefenceUser("leader-uid", "leader@isufst.edu.ph");
  await assertFails(updateDoc(doc(leader, "theses/td1/candidateTitles/ct1"),
    { titleText: "changed after they read it" }));
  await assertFails(deleteDoc(doc(leader, "theses/td1/candidateTitles/ct1")));
  // Control: the leader may still READ it on the same path.
  await assertSucceeds(getDocs(collection(leader, "theses/td1/candidateTitles")));
});

// The submit batch: candidates + the thesis flip, committed together.
//
// This pair is the emulator probe the rule depends on. Firestore evaluates
// every write in a batch against the state BEFORE the batch, so a candidate
// `create` is judged while the thesis is still `nominationApproved` — which is
// why the create rule names the PRE-submission statuses and not
// `titlePendingDefence`. The second test is the two-sided half: the identical
// writes issued sequentially are denied, because by then the status has moved.
test("M1b allow: the leader MAY submit candidates and flip the thesis in ONE batch", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "theses/tdb1"),
      defenceThesis("nominationApproved", { titleRound: 0 }));
  });
  const leader = asDefenceUser("leader-uid", "leader@isufst.edu.ph");
  const batch = writeBatch(leader);
  for (const id of ["b1", "b2", "b3"]) {
    batch.set(doc(leader, `theses/tdb1/candidateTitles/${id}`), {
      titleText: `Candidate ${id}`, justificationPath: "p",
      justificationUrl: "u", round: 1, position: 0, submittedAt: serverTimestamp(),
    });
  }
  batch.update(doc(leader, "theses/tdb1"), {
    status: "titlePendingDefence", titleRound: 1,
    titlesSubmittedAt: serverTimestamp(),
    presentationPath: "pp", presentationUrl: "pu",
  });
  await assertSucceeds(batch.commit());
});

test("M1b probe: batched writes are evaluated against the state BEFORE the batch", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "theses/tdb2"),
      defenceThesis("nominationApproved", { titleRound: 0 }));
  });
  const leader = asDefenceUser("leader-uid", "leader@isufst.edu.ph");
  // Sequentially: the flip commits first...
  await assertSucceeds(updateDoc(doc(leader, "theses/tdb2"), {
    status: "titlePendingDefence", titleRound: 1,
    titlesSubmittedAt: serverTimestamp(),
    presentationPath: "pp", presentationUrl: "pu",
  }));
  // ...and now the very same candidate create is DENIED, because the thesis
  // has already left the submission statuses. Batched, it was allowed.
  await assertFails(setDoc(doc(leader, "theses/tdb2/candidateTitles/b1"), {
    titleText: "Candidate b1", justificationPath: "p",
    justificationUrl: "u", round: 1, position: 0, submittedAt: serverTimestamp(),
  }));
});

test("M1b attack: a stranger may NOT submit candidates to another group's thesis", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "theses/tdb3"),
      defenceThesis("nominationApproved", { titleRound: 0 }));
  });
  const outsider = asDefenceUser("outsider-uid", "outsider@isufst.edu.ph");
  await assertFails(setDoc(doc(outsider, "theses/tdb3/candidateTitles/x1"), {
    titleText: "Not mine", justificationPath: "p", justificationUrl: "u",
    round: 1, position: 0, submittedAt: serverTimestamp(),
  }));
  // Control: the real leader, same path, same payload.
  const leader = asDefenceUser("leader-uid", "leader@isufst.edu.ph");
  await assertSucceeds(setDoc(doc(leader, "theses/tdb3/candidateTitles/x1"), {
    titleText: "Not mine", justificationPath: "p", justificationUrl: "u",
    round: 1, position: 0, submittedAt: serverTimestamp(),
  }));
});

test("M1b attack: a candidate may NOT carry unknown keys or an empty title", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "theses/tdb4"),
      defenceThesis("nominationApproved", { titleRound: 0 }));
  });
  const leader = asDefenceUser("leader-uid", "leader@isufst.edu.ph");
  await assertFails(setDoc(doc(leader, "theses/tdb4/candidateTitles/junk"), {
    titleText: "Fine", justificationPath: "p", justificationUrl: "u",
    round: 1, position: 0, submittedAt: serverTimestamp(), approvedBy: "dean-uid",
  }));
  await assertFails(setDoc(doc(leader, "theses/tdb4/candidateTitles/empty"), {
    titleText: "", justificationPath: "p", justificationUrl: "u",
    round: 1, position: 0, submittedAt: serverTimestamp(),
  }));
  // A missing or nonsense position. Order is what the panel reads the set
  // in, and a candidate that carries no position -- or a forged one -- puts
  // the group's titles in front of the Dean in an order they did not choose.
  await assertFails(setDoc(doc(leader, "theses/tdb4/candidateTitles/nopos"), {
    titleText: "Fine", justificationPath: "p", justificationUrl: "u",
    round: 1, submittedAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(leader, "theses/tdb4/candidateTitles/negpos"), {
    titleText: "Fine", justificationPath: "p", justificationUrl: "u",
    round: 1, position: -1, submittedAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(leader, "theses/tdb4/candidateTitles/strpos"), {
    titleText: "Fine", justificationPath: "p", justificationUrl: "u",
    round: 1, position: "first", submittedAt: serverTimestamp(),
  }));
  // Control: the same write, whitelisted keys, non-empty title.
  await assertSucceeds(setDoc(doc(leader, "theses/tdb4/candidateTitles/ok"), {
    titleText: "Fine", justificationPath: "p", justificationUrl: "u",
    round: 1, position: 0, submittedAt: serverTimestamp(),
  }));
});

test("M1b attack: the leader may NOT edit the thesis once the defence is under way", async () => {
  await env.withSecurityRulesDisabled((ctx) => seedDefence(ctx.firestore()));
  const leader = asDefenceUser("leader-uid", "leader@isufst.edu.ph");
  // Replaying the submit would swap the presentation mid-defence.
  await assertFails(updateDoc(doc(leader, "theses/td1"), {
    status: "titlePendingDefence", titleRound: 2,
    titlesSubmittedAt: serverTimestamp(),
    presentationPath: "swapped", presentationUrl: "swapped",
  }));
  // And they certainly may not decide their own defence.
  await assertFails(updateDoc(doc(leader, "theses/td1"), {
    status: "titleApproved", approvedTitleId: "ct1",
    titleDecidedBy: "leader-uid", titleDecidedAt: serverTimestamp(),
  }));
});

test("M1b attack: the Dean may NOT approve a candidate from another thesis", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await seedDefence(db);
    await setDoc(doc(db, "users/dean-uid"), {
      ...studentProfile("dean@isufst.edu.ph"), role: "dean" });
  });
  const dean = asDefenceUser("dean-uid", "dean@isufst.edu.ph");
  await assertFails(updateDoc(doc(dean, "theses/td1"), {
    status: "titleApproved", approvedTitleId: "not-on-this-thesis",
    titleDecidedBy: "dean-uid", titleDecidedAt: serverTimestamp(),
  }));
  // Control: the real candidate is accepted.
  await assertSucceeds(updateDoc(doc(dean, "theses/td1"), {
    status: "titleApproved", approvedTitleId: "ct1",
    titleDecidedBy: "dean-uid", titleDecidedAt: serverTimestamp(),
  }));
});

test("M1b attack: a coordinator may NOT record the Dean's decision", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await seedDefence(db);
    await setDoc(doc(db, "users/coord-uid"), {
      ...studentProfile("coord@isufst.edu.ph"), role: "coordinator" });
    await setDoc(doc(db, "users/dean-uid"), {
      ...studentProfile("dean@isufst.edu.ph"), role: "dean" });
  });
  const coord = asDefenceUser("coord-uid", "coord@isufst.edu.ph");
  await assertFails(updateDoc(doc(coord, "theses/td1"), {
    status: "titleApproved", approvedTitleId: "ct1",
    titleDecidedBy: "coord-uid", titleDecidedAt: serverTimestamp(),
  }));
  // Control: the Dean, same write, same path.
  const dean = asDefenceUser("dean-uid", "dean@isufst.edu.ph");
  await assertSucceeds(updateDoc(doc(dean, "theses/td1"), {
    status: "titleApproved", approvedTitleId: "ct1",
    titleDecidedBy: "dean-uid", titleDecidedAt: serverTimestamp(),
  }));
});

test("M1b attack: the Dean may NOT record the decision under someone else's name", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await seedDefence(db);
    await setDoc(doc(db, "users/dean-uid"), {
      ...studentProfile("dean@isufst.edu.ph"), role: "dean" });
  });
  const dean = asDefenceUser("dean-uid", "dean@isufst.edu.ph");
  await assertFails(updateDoc(doc(dean, "theses/td1"), {
    status: "titleApproved", approvedTitleId: "ct1",
    titleDecidedBy: "someone-else", titleDecidedAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(doc(dean, "theses/td1"), {
    status: "titleApproved", approvedTitleId: "ct1",
    titleDecidedBy: "dean-uid", titleDecidedAt: serverTimestamp(),
  }));
});

test("M1b attack: the Dean may NOT reject without a remark", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await seedDefence(db);
    await setDoc(doc(db, "users/dean-uid"), {
      ...studentProfile("dean@isufst.edu.ph"), role: "dean" });
  });
  const dean = asDefenceUser("dean-uid", "dean@isufst.edu.ph");
  await assertFails(updateDoc(doc(dean, "theses/td1"), {
    status: "titleRejected", titleRejectionRemark: "",
    titleDecidedBy: "dean-uid", titleDecidedAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(doc(dean, "theses/td1"), {
    status: "titleRejected", titleRejectionRemark: "All three are too broad.",
    titleDecidedBy: "dean-uid", titleDecidedAt: serverTimestamp(),
  }));
});

test("M1b attack: a decision may NOT be replayed once made", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await seedDefence(db, { status: "titleApproved", decided: Timestamp.now() });
    await setDoc(doc(db, "users/dean-uid"), {
      ...studentProfile("dean@isufst.edu.ph"), role: "dean" });
  });
  const dean = asDefenceUser("dean-uid", "dean@isufst.edu.ph");
  await assertFails(updateDoc(doc(dean, "theses/td1"), {
    status: "titleRejected", titleRejectionRemark: "changed my mind",
    titleDecidedBy: "dean-uid", titleDecidedAt: serverTimestamp(),
  }));
});

test("M1b attack: the Dean may NOT skip the defence entirely", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await seedDefence(db, { status: "nominationApproved" });
    await setDoc(doc(db, "users/dean-uid"), {
      ...studentProfile("dean@isufst.edu.ph"), role: "dean" });
  });
  const dean = asDefenceUser("dean-uid", "dean@isufst.edu.ph");
  await assertFails(updateDoc(doc(dean, "theses/td1"), {
    status: "titleApproved", approvedTitleId: "ct1",
    titleDecidedBy: "dean-uid", titleDecidedAt: serverTimestamp(),
  }));
  // Control: once the thesis IS at titlePendingDefence, the same write lands.
  await env.withSecurityRulesDisabled((ctx) => seedDefence(ctx.firestore()));
  await assertSucceeds(updateDoc(doc(dean, "theses/td1"), {
    status: "titleApproved", approvedTitleId: "ct1",
    titleDecidedBy: "dean-uid", titleDecidedAt: serverTimestamp(),
  }));
});

// ---------- M2: documents, versions and feedback ----------

function docThesis(status = "titleApproved", extra = {}) {
  return {
    leaderUid: "leader-uid", adviserUid: "adviser-uid",
    panelistUids: ["pan-uid"], memberNames: [], workingTitle: "T",
    college: "CICT", program: "BSIT", semester: "First",
    academicYear: "2026-2027", status, ...extra,
  };
}

function asDocUser(uid, email) {
  return env.authenticatedContext(uid, { email, email_verified: true })
    .firestore();
}

async function seedChapters(db, thesisId = "m2") {
  await setDoc(doc(db, `theses/${thesisId}`), docThesis());
  await setDoc(doc(db, `theses/${thesisId}/documents/chapterI`), {
    type: "chapterI", currentVersion: 1, status: "submitted",
    updatedAt: Timestamp.now(),
  });
  await setDoc(doc(db, `theses/${thesisId}/documents/chapterI/versions/1`), {
    version: 1, storagePath: "p", fileUrl: "u", uploadedBy: "leader-uid",
    uploadedAt: Timestamp.now(), mimeType: "application/pdf",
    sizeBytes: 100,
  });
}

test("M2: the leader, adviser, coordinator and dean read a chapter", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await seedChapters(db);
    await setDoc(doc(db, "users/coord-uid"),
      { role: "coordinator", active: true });
    await setDoc(doc(db, "users/dean-uid"), { role: "dean", active: true });
  });
  for (const uid of ["leader-uid", "adviser-uid", "coord-uid", "dean-uid"]) {
    await assertSucceeds(
      getDoc(doc(asDocUser(uid, `${uid}@isufst.edu.ph`),
        "theses/m2/documents/chapterI")));
  }
});

test("M2: a panelist may NOT read a chapter, its versions or its feedback",
  async () => {
    // The panel meets the document at the pre-oral defence, which is M3.
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await seedChapters(db);
      await setDoc(doc(db, "theses/m2/documents/chapterI/feedback/f1"), {
        version: 1, reviewerUid: "adviser-uid", reviewerName: "Dr. A",
        reviewerRole: "Adviser", body: "Tighten it.",
        createdAt: Timestamp.now(),
      });
    });
    const pan = asDocUser("pan-uid", "pan@isufst.edu.ph");
    await assertFails(getDoc(doc(pan, "theses/m2/documents/chapterI")));
    await assertFails(
      getDoc(doc(pan, "theses/m2/documents/chapterI/versions/1")));
    await assertFails(
      getDoc(doc(pan, "theses/m2/documents/chapterI/feedback/f1")));
    // Control: the adviser, same paths.
    const adv = asDocUser("adviser-uid", "adviser@isufst.edu.ph");
    await assertSucceeds(getDoc(doc(adv, "theses/m2/documents/chapterI")));
    await assertSucceeds(
      getDoc(doc(adv, "theses/m2/documents/chapterI/versions/1")));
    await assertSucceeds(
      getDoc(doc(adv, "theses/m2/documents/chapterI/feedback/f1")));
  });

test("M2: the dean reads chapter STATUS but NOT its versions or feedback",
  async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await seedChapters(db);
      await setDoc(doc(db, "users/dean-uid"), { role: "dean", active: true });
      await setDoc(doc(db, "theses/m2/documents/chapterI/feedback/f1"), {
        version: 1, reviewerUid: "adviser-uid", reviewerName: "Dr. A",
        reviewerRole: "Adviser", body: "Tighten it.",
        createdAt: Timestamp.now(),
      });
    });
    const dean = asDocUser("dean-uid", "dean@isufst.edu.ph");
    await assertSucceeds(getDoc(doc(dean, "theses/m2/documents/chapterI")));
    await assertFails(
      getDoc(doc(dean, "theses/m2/documents/chapterI/versions/1")));
    await assertFails(
      getDoc(doc(dean, "theses/m2/documents/chapterI/feedback/f1")));
    // Control: the adviser reads the feedback the dean was denied.
    const adv = asDocUser("adviser-uid", "adviser@isufst.edu.ph");
    await assertSucceeds(
      getDoc(doc(adv, "theses/m2/documents/chapterI/feedback/f1")));
  });

test("M2: chapters may NOT be created before the title is approved",
  async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "theses/m2b"),
        docThesis("titlePendingDefence")));
    const leader = asDocUser("leader-uid", "leader@isufst.edu.ph");
    await assertFails(setDoc(doc(leader, "theses/m2b/documents/chapterI"), {
      type: "chapterI", currentVersion: 1, status: "submitted",
      updatedAt: serverTimestamp(),
    }));
    // Control: the identical write succeeds once the thesis actually is
    // titleApproved, proving the failure above is the status gate at work
    // and not a malformed path or a missing fixture.
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "theses/m2b-ctrl"), docThesis()));
    await assertSucceeds(
      setDoc(doc(leader, "theses/m2b-ctrl/documents/chapterI"), {
        type: "chapterI", currentVersion: 1, status: "submitted",
        updatedAt: serverTimestamp(),
      }));
  });

test("M2: only the five chapter ids exist", async () => {
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), "theses/m2c"), docThesis()));
  const leader = asDocUser("leader-uid", "leader@isufst.edu.ph");
  await assertFails(setDoc(doc(leader, "theses/m2c/documents/chapterVI"), {
    type: "chapterVI", currentVersion: 1, status: "submitted",
    updatedAt: serverTimestamp(),
  }));
  // Control: a real chapter id, same payload shape.
  await assertSucceeds(setDoc(doc(leader, "theses/m2c/documents/chapterV"), {
    type: "chapterV", currentVersion: 1, status: "submitted",
    updatedAt: serverTimestamp(),
  }));
});

test("M2: a student may NOT write approved, and an adviser may NOT fake a submission",
  async () => {
    await env.withSecurityRulesDisabled((ctx) => seedChapters(ctx.firestore()));
    const leader = asDocUser("leader-uid", "leader@isufst.edu.ph");
    const adv = asDocUser("adviser-uid", "adviser@isufst.edu.ph");

    // The student cannot approve their own chapter.
    await assertFails(updateDoc(doc(leader, "theses/m2/documents/chapterI"),
      { status: "approved", updatedAt: serverTimestamp() }));

    // The adviser cannot bump the version to fabricate a submission.
    await assertFails(updateDoc(doc(adv, "theses/m2/documents/chapterI"),
      { status: "submitted", currentVersion: 2,
        updatedAt: serverTimestamp() }));

    // Controls: each doing their own half.
    await assertSucceeds(updateDoc(doc(adv, "theses/m2/documents/chapterI"),
      { status: "revise", updatedAt: serverTimestamp() }));
  });

test("M2: an approved chapter is locked to the student and reopenable by the adviser",
  async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "theses/m2d"), docThesis());
      await setDoc(doc(db, "theses/m2d/documents/chapterI"), {
        type: "chapterI", currentVersion: 1, status: "approved",
        updatedAt: Timestamp.now(),
      });
    });
    const leader = asDocUser("leader-uid", "leader@isufst.edu.ph");
    const adv = asDocUser("adviser-uid", "adviser@isufst.edu.ph");

    await assertFails(updateDoc(doc(leader, "theses/m2d/documents/chapterI"),
      { currentVersion: 2, status: "submitted",
        updatedAt: serverTimestamp() }));
    // Control: the adviser reopens it, and then the student may upload.
    await assertSucceeds(updateDoc(doc(adv, "theses/m2d/documents/chapterI"),
      { status: "revise", updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(leader, "theses/m2d/documents/chapterI"),
      { currentVersion: 2, status: "submitted",
        updatedAt: serverTimestamp() }));
  });

test("M2: a chapter update may NOT smuggle in unlisted keys", async () => {
  await env.withSecurityRulesDisabled((ctx) => seedChapters(ctx.firestore()));
  const adv = asDocUser("adviser-uid", "adviser@isufst.edu.ph");
  await assertFails(updateDoc(doc(adv, "theses/m2/documents/chapterI"),
    { status: "revise", updatedAt: serverTimestamp(), grade: "A" }));
  // Control: the same update without the extra key.
  await assertSucceeds(updateDoc(doc(adv, "theses/m2/documents/chapterI"),
    { status: "revise", updatedAt: serverTimestamp() }));
});

test("M2 batch evaluation: a version and its parent bump are judged PRE-batch",
  async () => {
    // Two-sided. The batched form must be ALLOWED and the identical writes
    // issued SEQUENTIALLY must be DENIED -- by then the parent has already
    // moved and the version number no longer matches. This is a probe of
    // Firestore's behaviour, not an assumption about it.
    await env.withSecurityRulesDisabled((ctx) => seedChapters(ctx.firestore()));
    const leader = asDocUser("leader-uid", "leader@isufst.edu.ph");

    const batch = writeBatch(leader);
    batch.set(doc(leader, "theses/m2/documents/chapterI/versions/2"), {
      version: 2, storagePath: "p2", fileUrl: "u2",
      uploadedBy: "leader-uid", uploadedAt: serverTimestamp(),
      mimeType: "application/pdf", sizeBytes: 200,
    });
    batch.update(doc(leader, "theses/m2/documents/chapterI"),
      { currentVersion: 2, status: "submitted",
        updatedAt: serverTimestamp() });
    await assertSucceeds(batch.commit());

    // Sequentially: versions/2 already exists after the batch above, so
    // this second write is an UPDATE, not a create -- it is denied by
    // `allow update, delete: if false` before the create rule's version
    // logic is ever reached. This re-tests immutability (see "a version is
    // immutable once written" below), not the version-number check itself.
    await assertFails(
      setDoc(doc(leader, "theses/m2/documents/chapterI/versions/2"), {
        version: 2, storagePath: "p2", fileUrl: "u2",
        uploadedBy: "leader-uid", uploadedAt: serverTimestamp(),
        mimeType: "application/pdf", sizeBytes: 200,
      }));
  });

test("M2: a version number that is not currentVersion + 1 is refused",
  async () => {
    // A fresh document id, so this is a CREATE and the create rule's
    // version logic actually runs -- rather than being denied earlier as
    // an update to an existing version. A fresh thesis id too: "m2" has
    // already been advanced to currentVersion 2 by an earlier test in this
    // file (versions/2 already exists there), so this test seeds its own
    // fixture to guarantee the parent's currentVersion is still 1 and
    // versions/2 does not yet exist.
    await env.withSecurityRulesDisabled((ctx) => seedChapters(ctx.firestore(), "m2e"));
    const leader = asDocUser("leader-uid", "leader@isufst.edu.ph");
    await assertFails(
      setDoc(doc(leader, "theses/m2e/documents/chapterI/versions/5"), {
        version: 5, storagePath: "p", fileUrl: "u",
        uploadedBy: "leader-uid", uploadedAt: serverTimestamp(),
        mimeType: "application/pdf", sizeBytes: 100,
      }));
    // Control: the correct next number, same shape.
    await assertSucceeds(
      setDoc(doc(leader, "theses/m2e/documents/chapterI/versions/2"), {
        version: 2, storagePath: "p", fileUrl: "u",
        uploadedBy: "leader-uid", uploadedAt: serverTimestamp(),
        mimeType: "application/pdf", sizeBytes: 100,
      }));
  });

test("M2 batch: a group's FIRST upload creates the chapter and version 1 together",
  async () => {
    // The chapter does not exist before this batch, so a rule that reads
    // the parent's currentVersion unconditionally denies every group's
    // first upload -- while every Dart test still passes, because
    // fake_cloud_firestore does not enforce rules.
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "theses/m2first"), docThesis()));
    const leader = asDocUser("leader-uid", "leader@isufst.edu.ph");

    const batch = writeBatch(leader);
    batch.set(doc(leader, "theses/m2first/documents/chapterI"), {
      type: "chapterI", currentVersion: 1, status: "submitted",
      updatedAt: serverTimestamp(),
    });
    batch.set(doc(leader, "theses/m2first/documents/chapterI/versions/1"), {
      version: 1, storagePath: "p", fileUrl: "u", uploadedBy: "leader-uid",
      uploadedAt: serverTimestamp(), mimeType: "application/pdf",
      sizeBytes: 100,
    });
    await assertSucceeds(batch.commit());
  });

test("M2: a version is immutable once written", async () => {
  // A dedicated thesis id ("m2imm"), not the shared "m2" fixture other
  // tests in this file mutate -- so the control below cannot be thrown off
  // by a currentVersion some earlier test already bumped.
  await env.withSecurityRulesDisabled((ctx) =>
    seedChapters(ctx.firestore(), "m2imm"));
  const leader = asDocUser("leader-uid", "leader@isufst.edu.ph");
  await assertFails(
    updateDoc(doc(leader, "theses/m2imm/documents/chapterI/versions/1"),
      { fileUrl: "swapped" }));
  await assertFails(
    deleteDoc(doc(leader, "theses/m2imm/documents/chapterI/versions/1")));
  // Control: the same document is still readable, proving the path and
  // fixture are correct and the two failures above are the immutability
  // rule at work, not a malformed path or a missing document.
  await assertSucceeds(
    getDoc(doc(leader, "theses/m2imm/documents/chapterI/versions/1")));
});

test("M2: only the adviser writes feedback, in their own name, append-only",
  async () => {
    await env.withSecurityRulesDisabled((ctx) => seedChapters(ctx.firestore()));
    const leader = asDocUser("leader-uid", "leader@isufst.edu.ph");
    const adv = asDocUser("adviser-uid", "adviser@isufst.edu.ph");

    // A student may not write feedback at all.
    await assertFails(
      setDoc(doc(leader, "theses/m2/documents/chapterI/feedback/f1"), {
        version: 1, reviewerUid: "leader-uid", reviewerName: "Me",
        reviewerRole: "Adviser", body: "Looks great",
        createdAt: serverTimestamp(),
      }));

    // The adviser may not file feedback under someone else's uid.
    await assertFails(
      setDoc(doc(adv, "theses/m2/documents/chapterI/feedback/f2"), {
        version: 1, reviewerUid: "dean-uid", reviewerName: "Dean",
        reviewerRole: "Dean", body: "Not mine",
        createdAt: serverTimestamp(),
      }));

    // A version that does not exist yet cannot be commented on.
    await assertFails(
      setDoc(doc(adv, "theses/m2/documents/chapterI/feedback/f3"), {
        version: 9, reviewerUid: "adviser-uid", reviewerName: "Dr. A",
        reviewerRole: "Adviser", body: "On a future version",
        createdAt: serverTimestamp(),
      }));

    // Control: the adviser, own uid, an existing version.
    await assertSucceeds(
      setDoc(doc(adv, "theses/m2/documents/chapterI/feedback/f4"), {
        version: 1, reviewerUid: "adviser-uid", reviewerName: "Dr. A",
        reviewerRole: "Adviser", body: "Tighten the problem statement.",
        createdAt: serverTimestamp(),
      }));

    // Append-only.
    await assertFails(
      updateDoc(doc(adv, "theses/m2/documents/chapterI/feedback/f4"),
        { body: "Actually it is fine" }));
    await assertFails(
      deleteDoc(doc(adv, "theses/m2/documents/chapterI/feedback/f4")));
  });

test("M2: the student reads their feedback immediately", async () => {
  // Unlike M1b defence comments, this feedback exists to be acted on.
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await seedChapters(db);
    await setDoc(doc(db, "theses/m2/documents/chapterI/feedback/f1"), {
      version: 1, reviewerUid: "adviser-uid", reviewerName: "Dr. A",
      reviewerRole: "Adviser", body: "Tighten it.",
      createdAt: Timestamp.now(),
    });
  });
  const leader = asDocUser("leader-uid", "leader@isufst.edu.ph");
  await assertSucceeds(
    getDoc(doc(leader, "theses/m2/documents/chapterI/feedback/f1")));
});

test("M2: an adviser lists the theses they advise, and only those",
  async () => {
    // Until now `allow list` on theses was coordinator/dean/own-leader only,
    // which is why the faculty dashboard's "My advisees" was a placeholder.
    // M2 breaks on it: an adviser has no way to find the chapters waiting.
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "theses/adv1"), docThesis());
      await setDoc(doc(db, "theses/adv2"),
        docThesis("titleApproved", { adviserUid: "someone-else" }));
    });
    const adv = asDocUser("adviser-uid", "adviser@isufst.edu.ph");
    await assertSucceeds(getDocs(query(collection(adv, "theses"),
      where("adviserUid", "==", "adviser-uid"))));
    // Control: the same adviser may NOT list the whole collection.
    await assertFails(getDocs(collection(adv, "theses")));
  });

// ---------- M3: defence scheduling ----------

function defThesis(extra = {}) {
  return {
    leaderUid: "leader-uid", adviserUid: "adviser-uid",
    panelistUids: ["pan-uid", "pan2-uid"], memberNames: [],
    workingTitle: "T", college: "CICT", program: "BSIT",
    semester: "First", academicYear: "2026-2027",
    status: "titleApproved", ...extra,
  };
}

function defDoc(extra = {}) {
  return {
    thesisId: "dt1", type: "preOral", scheduledAt: Timestamp.now(),
    venue: "CICT AVR", panelUids: ["pan-uid", "pan2-uid"],
    adviserUid: "adviser-uid", leaderUid: "leader-uid", status: "scheduled",
    createdBy: "coord-uid",
    // `serverTimestamp()`, not `Timestamp.now()`: the `create` rule pins
    // `createdAt == request.time`, and a client-clock `Timestamp.now()`
    // is never exactly equal to the server's commit time -- the mismatch
    // is usually too small to see, which is what makes it dangerous: it
    // surfaces as an intermittent, load-dependent denial of the very
    // control case a test relies on to prove the deny arms are denying
    // for the right reason, not a coincidence.
    createdAt: serverTimestamp(), ...extra,
  };
}

// Memoised for the same reason `asDefenceUser` above is: re-deriving a
// Firestore instance for a uid that already issued a request throws
// "Firestore has already been started and its settings can no longer be
// changed" -- a harness error, not a rules denial, that `assertFails` would
// otherwise swallow as though it were one.
const m3DefDbs = new Map();
function asDefUser(uid, email) {
  if (!m3DefDbs.has(uid)) {
    m3DefDbs.set(
      uid,
      env.authenticatedContext(uid, { email, email_verified: true }).firestore()
    );
  }
  return m3DefDbs.get(uid);
}

async function seedM3Defence(db, extra = {}) {
  await setDoc(doc(db, "theses/dt1"), defThesis());
  await setDoc(doc(db, "users/coord-uid"),
    { role: "coordinator", active: true });
  await setDoc(doc(db, "users/dean-uid"), { role: "dean", active: true });
  await setDoc(doc(db, "defenses/df1"), defDoc(extra));
}

test("M3: everyone on the thesis reads the defence", async () => {
  await env.withSecurityRulesDisabled((ctx) => seedM3Defence(ctx.firestore()));
  for (const uid of ["leader-uid", "adviser-uid", "pan-uid", "coord-uid",
                     "dean-uid"]) {
    await assertSucceeds(
      getDoc(doc(asDefUser(uid, `${uid}@isufst.edu.ph`), "defenses/df1")));
  }
});

test("M3: an outsider may NOT read the defence", async () => {
  await env.withSecurityRulesDisabled((ctx) => seedM3Defence(ctx.firestore()));
  const outsider = asDefUser("outsider-uid", "out@isufst.edu.ph");
  await assertFails(getDoc(doc(outsider, "defenses/df1")));
  // Control: the adviser, same path.
  await assertSucceeds(
    getDoc(doc(asDefUser("adviser-uid", "adviser@isufst.edu.ph"),
      "defenses/df1")));
});

test("M3: only the coordinator schedules, and only as 'scheduled'",
  async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "theses/dt1"), defThesis());
      await setDoc(doc(db, "users/coord-uid"),
        { role: "coordinator", active: true });
    });
    const adv = asDefUser("adviser-uid", "adviser@isufst.edu.ph");
    const coord = asDefUser("coord-uid", "coord@isufst.edu.ph");

    await assertFails(setDoc(doc(adv, "defenses/dfA"),
      defDoc({ createdBy: "adviser-uid" })));
    // Already open at creation would skip the lifecycle entirely.
    await assertFails(setDoc(doc(coord, "defenses/dfB"),
      defDoc({ status: "inProgress" })));
    // Releasing at creation would open the log before anyone spoke.
    await assertFails(setDoc(doc(coord, "defenses/dfC"),
      defDoc({ consolidatedAt: Timestamp.now() })));
    // Control.
    await assertSucceeds(setDoc(doc(coord, "defenses/dfD"), defDoc()));
  });

test("M3: the panel snapshot must match the thesis at scheduling",
  async () => {
    // A forged snapshot would grant comment rights to someone the group
    // never nominated, and the defence record is the historical evidence
    // of who sat.
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "theses/dt1"), defThesis());
      await setDoc(doc(db, "users/coord-uid"),
        { role: "coordinator", active: true });
    });
    const coord = asDefUser("coord-uid", "coord@isufst.edu.ph");

    await assertFails(setDoc(doc(coord, "defenses/dfE"),
      defDoc({ panelUids: ["pan-uid", "smuggled-uid"] })));
    await assertFails(setDoc(doc(coord, "defenses/dfF"),
      defDoc({ adviserUid: "smuggled-uid" })));
    await assertFails(setDoc(doc(coord, "defenses/dfH"),
      defDoc({ leaderUid: "smuggled-uid" })));
    // Control: the real panel and adviser.
    await assertSucceeds(setDoc(doc(coord, "defenses/dfG"), defDoc()));
  });

test("M3: the lifecycle moves forward only, and only by the coordinator",
  async () => {
    await env.withSecurityRulesDisabled((ctx) => seedM3Defence(ctx.firestore()));
    const coord = asDefUser("coord-uid", "coord@isufst.edu.ph");
    const adv = asDefUser("adviser-uid", "adviser@isufst.edu.ph");

    // Nobody else drives it.
    await assertFails(updateDoc(doc(adv, "defenses/df1"),
      { status: "inProgress" }));
    // No skipping.
    await assertFails(updateDoc(doc(coord, "defenses/df1"),
      { status: "completed" }));
    // Control: the legal step.
    await assertSucceeds(updateDoc(doc(coord, "defenses/df1"),
      { status: "inProgress" }));
    // And no going back.
    await assertFails(updateDoc(doc(coord, "defenses/df1"),
      { status: "scheduled" }));
    await assertSucceeds(updateDoc(doc(coord, "defenses/df1"),
      { status: "completed" }));
  });

test("M3: only the adviser releases, only once, only when completed",
  async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      seedM3Defence(ctx.firestore(), { status: "inProgress" }));
    const adv = asDefUser("adviser-uid", "adviser@isufst.edu.ph");
    const coord = asDefUser("coord-uid", "coord@isufst.edu.ph");

    // Not while it is still running.
    await assertFails(updateDoc(doc(adv, "defenses/df1"),
      { consolidatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(coord, "defenses/df1"),
      { status: "completed" }));
    // Not the coordinator -- §4d makes this the adviser's act.
    await assertFails(updateDoc(doc(coord, "defenses/df1"),
      { consolidatedAt: serverTimestamp() }));
    // Control.
    await assertSucceeds(updateDoc(doc(adv, "defenses/df1"),
      { consolidatedAt: serverTimestamp() }));
    // Releasing twice would let a re-release hide comments the group read.
    await assertFails(updateDoc(doc(adv, "defenses/df1"),
      { consolidatedAt: serverTimestamp() }));
  });

test("M3: a defence may never be deleted", async () => {
  await env.withSecurityRulesDisabled((ctx) => seedM3Defence(ctx.firestore()));
  const coord = asDefUser("coord-uid", "coord@isufst.edu.ph");
  await assertFails(deleteDoc(doc(coord, "defenses/df1")));
});

test("M3: each role lists only the defences they belong to", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await seedM3Defence(db);
    await setDoc(doc(db, "theses/dt2"),
      defThesis({ leaderUid: "other-leader", adviserUid: "other-adviser",
                  panelistUids: ["other-pan"] }));
    await setDoc(doc(db, "defenses/df2"),
      defDoc({ thesisId: "dt2", adviserUid: "other-adviser",
               leaderUid: "other-leader", panelUids: ["other-pan"] }));
  });

  const adv = asDefUser("adviser-uid", "adviser@isufst.edu.ph");
  await assertSucceeds(getDocs(query(collection(adv, "defenses"),
    where("adviserUid", "==", "adviser-uid"))));
  await assertFails(getDocs(collection(adv, "defenses")));

  const pan = asDefUser("pan-uid", "pan@isufst.edu.ph");
  await assertSucceeds(getDocs(query(collection(pan, "defenses"),
    where("panelUids", "array-contains", "pan-uid"))));
  await assertFails(getDocs(collection(pan, "defenses")));

  const leader = asDefUser("leader-uid", "leader@isufst.edu.ph");
  // Filtered on `leaderUid`, the exact field the leader arm of `allow list`
  // checks -- not on `thesisId`. Firestore can only serve a `list` request
  // it can PROVE is safe from the query's own constraints; a filter on an
  // unrelated field (even one that happens to correlate 1:1 with thesisId
  // here) is not enough; probed against the emulator, where such a query
  // is denied outright regardless of the documents' actual content.
  await assertSucceeds(getDocs(query(collection(leader, "defenses"),
    where("leaderUid", "==", "leader-uid"))));

  // The coordinator and dean monitor college-wide, so an unfiltered list
  // is theirs by design.
  const coord = asDefUser("coord-uid", "coord@isufst.edu.ph");
  try {
    await assertSucceeds(getDocs(collection(coord, "defenses")));
  } catch (e) { console.log("DEBUG coord-unfiltered", e.message); throw e; }
});

// ---------- M3: defence comments ----------

test("M3: comments may be written ONLY while the defence is in progress",
  async () => {
    // This is what makes the log a record of the room rather than a
    // document anyone can append to days later.
    await env.withSecurityRulesDisabled((ctx) => seedM3Defence(ctx.firestore()));
    const pan = asDefUser("pan-uid", "pan@isufst.edu.ph");
    const coord = asDefUser("coord-uid", "coord@isufst.edu.ph");

    const remark = {
      authorUid: "pan-uid", authorName: "Dr. Panel",
      authorPosition: "Panel Member", body: "Justify the respondents.",
      createdAt: serverTimestamp(),
    };

    // scheduled -- not open yet.
    await assertFails(
      setDoc(doc(pan, "defenses/df1/comments/c1"), remark));

    await assertSucceeds(updateDoc(doc(coord, "defenses/df1"),
      { status: "inProgress" }));
    // Control: the identical write, once open.
    await assertSucceeds(
      setDoc(doc(pan, "defenses/df1/comments/c1"), remark));

    await assertSucceeds(updateDoc(doc(coord, "defenses/df1"),
      { status: "completed" }));
    // completed -- the log is frozen.
    await assertFails(
      setDoc(doc(pan, "defenses/df1/comments/c2"), remark));
  });

test("M3: the group may NOT read comments until the adviser releases them",
  async () => {
    // Guidelines §4d: the adviser consolidates and furnishes the copy. A
    // half-finished remark, or one the panel withdrew, is not the record.
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await seedM3Defence(db, { status: "completed" });
      await setDoc(doc(db, "defenses/df1/comments/c1"), {
        authorUid: "pan-uid", authorName: "Dr. Panel",
        authorPosition: "Panel Member", body: "Justify the respondents.",
        createdAt: Timestamp.now(),
      });
    });
    const leader = asDefUser("leader-uid", "leader@isufst.edu.ph");
    const adv = asDefUser("adviser-uid", "adviser@isufst.edu.ph");

    await assertFails(getDoc(doc(leader, "defenses/df1/comments/c1")));
    // Control: the adviser reads it throughout.
    await assertSucceeds(getDoc(doc(adv, "defenses/df1/comments/c1")));

    await assertSucceeds(updateDoc(doc(adv, "defenses/df1"),
      { consolidatedAt: serverTimestamp() }));
    // Released -- now the group reads it.
    await assertSucceeds(getDoc(doc(leader, "defenses/df1/comments/c1")));
  });

test("M3: a comment is filed in its author's own name, and never edited",
  async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      seedM3Defence(ctx.firestore(), { status: "inProgress" }));
    const pan = asDefUser("pan-uid", "pan@isufst.edu.ph");
    const leader = asDefUser("leader-uid", "leader@isufst.edu.ph");

    // Not under someone else's uid.
    await assertFails(setDoc(doc(pan, "defenses/df1/comments/x1"), {
      authorUid: "adviser-uid", authorName: "Dr. Adviser",
      authorPosition: "Adviser", body: "Not mine.",
      createdAt: serverTimestamp(),
    }));
    // The group presents; it does not comment on its own defence.
    await assertFails(setDoc(doc(leader, "defenses/df1/comments/x2"), {
      authorUid: "leader-uid", authorName: "Student",
      authorPosition: "Panel Member", body: "We agree.",
      createdAt: serverTimestamp(),
    }));
    // An empty remark is not a remark.
    await assertFails(setDoc(doc(pan, "defenses/df1/comments/x3"), {
      authorUid: "pan-uid", authorName: "Dr. Panel",
      authorPosition: "Panel Member", body: "",
      createdAt: serverTimestamp(),
    }));
    // Control.
    await assertSucceeds(setDoc(doc(pan, "defenses/df1/comments/x4"), {
      authorUid: "pan-uid", authorName: "Dr. Panel",
      authorPosition: "Panel Member", body: "A real remark.",
      createdAt: serverTimestamp(),
    }));
    // Append-only: the record is evidence.
    await assertFails(updateDoc(doc(pan, "defenses/df1/comments/x4"),
      { body: "Actually, never mind." }));
    await assertFails(deleteDoc(doc(pan, "defenses/df1/comments/x4")));
  });

test.after(async () => {
  await env.cleanup();
});
