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
  setDoc,
  updateDoc,
  deleteDoc,
  serverTimestamp,
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

test.after(async () => {
  await env.cleanup();
});
