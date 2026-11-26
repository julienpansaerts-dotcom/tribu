// Fonctions serveur de Tribu : notifications programmées et regroupées.
//
// - Rappels : une notification à chaque heure choisie (outbox), action « C'est fait »,
//   et une notification à l'auteur quand le rappel est validé.
// - Tâches suivies : au plus une notification toutes les 10 minutes par tâche et par personne,
//   les modifications intermédiaires sont regroupées.
// - Agenda : alerte avant un événement.
// - Échéances : factures à payer et papiers d'identité qui expirent.

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

admin.initializeApp();
setGlobalOptions({ region: "europe-west1", maxInstances: 5 });

const db = admin.firestore();
const { FieldValue, Timestamp } = admin.firestore;
const TEN_MINUTES = 10 * 60 * 1000;
const TZ = "Europe/Brussels";

function timeLabel(date) {
  return new Intl.DateTimeFormat("fr-BE", { hour: "2-digit", minute: "2-digit", timeZone: TZ }).format(date);
}

function dayLabel(date) {
  return new Intl.DateTimeFormat("fr-BE", { weekday: "long", day: "numeric", month: "long", timeZone: TZ }).format(date);
}

/** Jetons de notification des membres visés (par fiche personne ou par uid). */
async function tokensFor(hid, { personIds = [], uids = [], excludeUid = null, parentsOnly = false }) {
  const members = await db.collection(`households/${hid}/members`).get();
  const tokens = [];
  members.forEach((m) => {
    const d = m.data();
    if (m.id === excludeUid) return;
    const targeted = parentsOnly
      ? d.role === "parent"
      : uids.includes(m.id) || (d.personId && personIds.includes(d.personId));
    if (targeted) tokens.push(...(d.fcmTokens || []));
  });
  return [...new Set(tokens)];
}

async function send(hid, tokens, title, body, data = {}, category = null) {
  if (!tokens.length) return;
  const aps = { sound: "default" };
  if (category) aps.category = category;
  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: { ...data, householdId: hid },
    apns: { payload: { aps } },
  });
  const invalid = [];
  response.responses.forEach((r, i) => {
    const code = r.error && r.error.code;
    if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token") {
      invalid.push(tokens[i]);
    }
  });
  if (invalid.length) {
    const members = await db.collection(`households/${hid}/members`).get();
    const batch = db.batch();
    members.forEach((m) => batch.update(m.ref, { fcmTokens: FieldValue.arrayRemove(...invalid) }));
    await batch.commit();
  }
}

async function clearOutbox(field, value) {
  const existing = await db.collection("outbox").where(field, "==", value).get();
  const batch = db.batch();
  existing.forEach((d) => batch.delete(d.ref));
  if (!existing.empty) await batch.commit();
}

// ---------------------------------------------------------------- Rappels

exports.onReminderWrite = onDocumentWritten("households/{hid}/reminders/{rid}", async (event) => {
  const { hid, rid } = event.params;
  const before = event.data.before.exists ? event.data.before.data() : null;
  const after = event.data.after.exists ? event.data.after.data() : null;
  const path = `households/${hid}/reminders/${rid}`;

  // Planification des notifications : on repart de zéro à chaque modification.
  const changedSchedule =
    !before || !after ||
    before.dueAt?.toMillis() !== after.dueAt?.toMillis() ||
    JSON.stringify(before.offsets) !== JSON.stringify(after.offsets) ||
    JSON.stringify(before.assigneeIds) !== JSON.stringify(after.assigneeIds) ||
    !!before.doneAt !== !!after.doneAt;

  if (changedSchedule) {
    await clearOutbox("path", path);
    if (after && !after.doneAt && after.dueAt) {
      const due = after.dueAt.toMillis();
      const batch = db.batch();
      for (const offset of after.offsets || [0]) {
        const fireAt = due - offset * 60 * 1000;
        if (fireAt > Date.now() - 60 * 1000) {
          batch.set(db.collection("outbox").doc(), {
            kind: "reminder", householdId: hid, path, offset, fireAt: Timestamp.fromMillis(fireAt),
          });
        }
      }
      await batch.commit();
    }
  }

  // Nouveau rappel : on prévient tout de suite les destinataires (sauf son auteur).
  if (!before && after) {
    const members = await db.collection(`households/${hid}/members`).get();
    const tokens = [];
    members.forEach((m) => {
      const d = m.data();
      if (d.personId === after.createdById) return;
      if ((after.assigneeIds || []).includes(d.personId)) tokens.push(...(d.fcmTokens || []));
    });
    await send(hid, [...new Set(tokens)],
      `Nouveau rappel de ${after.createdByName || "la tribu"}`,
      `${after.title} — ${dayLabel(after.dueAt.toDate())} à ${timeLabel(after.dueAt.toDate())}`,
      { reminderId: rid }, "REMINDER");
  }

  // Rappel validé : on prévient son auteur.
  if (before && after && !before.doneAt && after.doneAt) {
    const creators = await db.collection(`households/${hid}/members`).where("personId", "==", after.createdById || "").get();
    const tokens = [];
    creators.forEach((m) => tokens.push(...(m.data().fcmTokens || [])));
    await send(hid, [...new Set(tokens)], "C'est fait",
      `${after.doneByName || "Quelqu'un"} a validé « ${after.title} »`, { reminderId: rid });
  }
});

// ---------------------------------------------------------------- Agenda

exports.onEventWrite = onDocumentWritten("households/{hid}/events/{eid}", async (event) => {
  const { hid, eid } = event.params;
  const path = `households/${hid}/events/${eid}`;
  await clearOutbox("path", path);
  const after = event.data.after.exists ? event.data.after.data() : null;
  if (!after || after.alertMinutes == null || !after.start) return;
  const fireAt = after.start.toMillis() - after.alertMinutes * 60 * 1000;
  if (fireAt > Date.now()) {
    await db.collection("outbox").add({ kind: "event", householdId: hid, path, fireAt: Timestamp.fromMillis(fireAt) });
  }
});

// ---------------------------------------------------------------- Tâches suivies

exports.onTaskWrite = onDocumentWritten("households/{hid}/tasks/{tid}", async (event) => {
  const { hid, tid } = event.params;
  const before = event.data.before.exists ? event.data.before.data() : null;
  const after = event.data.after.exists ? event.data.after.data() : null;
  if (!after || !before) return;
  // Seules les vraies modifications (updatedAt change) déclenchent une notification.
  if (before.updatedAt?.toMillis() === after.updatedAt?.toMillis()) return;

  const followers = (after.followerUids || []).filter((uid) => uid !== after.lastEditedByUid);
  const now = Date.now();
  for (const uid of followers) {
    const stateRef = db.doc(`households/${hid}/taskNotify/${tid}_${uid}`);
    const sendNow = await db.runTransaction(async (tx) => {
      const state = await tx.get(stateRef);
      const last = state.exists && state.data().lastSentAt ? state.data().lastSentAt.toMillis() : 0;
      if (now - last >= TEN_MINUTES) {
        tx.set(stateRef, { lastSentAt: Timestamp.fromMillis(now), pending: 0 }, { merge: true });
        return true;
      }
      tx.set(stateRef, { pending: FieldValue.increment(1) }, { merge: true });
      tx.set(db.doc(`outbox/task_${hid}_${tid}_${uid}`), {
        kind: "task", householdId: hid, path: `households/${hid}/tasks/${tid}`, uid,
        fireAt: Timestamp.fromMillis(last + TEN_MINUTES),
      });
      return false;
    });
    if (sendNow) {
      const tokens = await tokensFor(hid, { uids: [uid] });
      await send(hid, tokens, after.title,
        `${after.lastEditedByName || "Quelqu'un"} ${after.lastChange || "a modifié la tâche"}`, { taskId: tid });
    }
  }
});

// ---------------------------------------------------------------- Envoi programmé (chaque minute)

exports.dispatchOutbox = onSchedule({ schedule: "every 1 minutes", timeZone: TZ }, async () => {
  const due = await db.collection("outbox").where("fireAt", "<=", Timestamp.now()).limit(200).get();
  for (const doc of due.docs) {
    const job = doc.data();
    try {
      const target = await db.doc(job.path).get();
      if (!target.exists) continue;
      const data = target.data();
      const hid = job.householdId;

      if (job.kind === "reminder") {
        if (data.doneAt) continue;
        const tokens = await tokensFor(hid, { personIds: data.assigneeIds || [] });
        const when = job.offset > 0 ? `dans ${job.offset >= 60 ? Math.round(job.offset / 60) + " h" : job.offset + " min"}` : "maintenant";
        await send(hid, tokens, `Rappel · ${timeLabel(data.dueAt.toDate())}`,
          `${data.title} (${when})${data.createdByName ? " — de " + data.createdByName : ""}`,
          { reminderId: target.id }, "REMINDER");

        // Rappel récurrent : quand l'heure est passée, on avance à la prochaine occurrence.
        if (job.offset === 0 && data.recurrence && data.recurrence !== "none") {
          const next = nextOccurrence(data.dueAt.toDate(), data.recurrence);
          if (next) await target.ref.update({ dueAt: Timestamp.fromDate(next), doneAt: null, doneByName: null, seenByIds: [] });
        }
      } else if (job.kind === "event") {
        const tokens = await tokensFor(hid, { personIds: data.personIds || [] });
        await send(hid, tokens.length ? tokens : await tokensFor(hid, { parentsOnly: true }),
          data.title, `${data.allDay ? "Aujourd'hui" : "À " + timeLabel(data.start.toDate())}${data.location ? " · " + data.location : ""}`,
          { eventId: target.id });
      } else if (job.kind === "task") {
        const stateRef = db.doc(`households/${hid}/taskNotify/${target.id}_${job.uid}`);
        const state = await stateRef.get();
        const pending = state.exists ? state.data().pending || 0 : 0;
        if (pending > 0) {
          const tokens = await tokensFor(hid, { uids: [job.uid] });
          await send(hid, tokens, data.title,
            `${pending} modification${pending > 1 ? "s" : ""} — dernière : ${data.lastEditedByName || ""} ${data.lastChange || ""}`.trim(),
            { taskId: target.id });
        }
        await stateRef.set({ lastSentAt: Timestamp.now(), pending: 0 }, { merge: true });
      }
    } catch (error) {
      console.error("Envoi impossible", doc.id, error);
    } finally {
      await doc.ref.delete();
    }
  }
});

function nextOccurrence(date, recurrence) {
  const next = new Date(date.getTime());
  const now = Date.now();
  let guard = 0;
  while (next.getTime() <= now && guard < 5000) {
    if (recurrence === "daily") next.setDate(next.getDate() + 1);
    else if (recurrence === "weekly") next.setDate(next.getDate() + 7);
    else if (recurrence === "monthly") next.setMonth(next.getMonth() + 1);
    else if (recurrence === "yearly") next.setFullYear(next.getFullYear() + 1);
    else return null;
    guard++;
  }
  return next;
}

// ---------------------------------------------------------------- Échéances (chaque matin)

exports.dailyDeadlines = onSchedule({ schedule: "every day 09:00", timeZone: TZ }, async () => {
  const households = await db.collection("households").get();
  const now = Date.now();
  const day = 24 * 3600 * 1000;
  for (const household of households.docs) {
    const hid = household.id;

    // Factures à payer dans 3 jours ou en retard.
    const expenses = await db.collection(`households/${hid}/expenses`).where("paidAt", "==", null).get();
    const dueSoon = expenses.docs.map((d) => d.data()).filter((e) => e.dueDate && e.dueDate.toMillis() - now <= 3 * day);
    if (dueSoon.length) {
      const total = dueSoon.reduce((sum, e) => sum + (e.amount || 0), 0);
      await send(hid, await tokensFor(hid, { parentsOnly: true }), "Factures à payer",
        `${dueSoon.map((e) => e.vendor).join(", ")} — ${total.toFixed(2).replace(".", ",")} €`, { screen: "expenses" });
    }

    // Papiers d'identité : J-60, J-30, J-7.
    const people = await db.collection(`households/${hid}/people`).get();
    for (const person of people.docs) {
      const p = person.data();
      for (const document of Object.values(p.documents || {})) {
        if (!document.expiresAt) continue;
        const daysLeft = Math.round((document.expiresAt.toMillis() - now) / day);
        if ([60, 30, 7].includes(daysLeft)) {
          await send(hid, await tokensFor(hid, { parentsOnly: true }), `${document.kind} de ${p.firstName}`,
            `Expire dans ${daysLeft} jours — pense à la renouveler.`, { personId: person.id });
        }
      }
    }
  }
});
