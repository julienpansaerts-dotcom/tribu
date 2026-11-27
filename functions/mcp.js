// Serveur MCP de Tribu : permet à un assistant (Grok, Claude, ChatGPT…) de lire et modifier
// les données de la tribu via des « outils ». Chaque bot a sa propre clé, créée dans l'app.
//
// Adresse : https://europe-west1-<projet>.cloudfunctions.net/mcp/<clé>

const crypto = require("crypto");
const { McpServer } = require("@modelcontextprotocol/sdk/server/mcp.js");
const { z } = require("zod");

const TZ = "Europe/Brussels";
const DAY = 24 * 3600 * 1000;

// ---------------------------------------------------------------- Dates (heure de Bruxelles)

/** Décalage (en ms) entre l'heure de Bruxelles et UTC à un instant donné. */
function tzOffset(date) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: TZ, hour12: false, year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
  }).formatToParts(date).reduce((acc, p) => ({ ...acc, [p.type]: p.value }), {});
  const asUTC = Date.UTC(+parts.year, +parts.month - 1, +parts.day, +parts.hour % 24, +parts.minute, +parts.second);
  return asUTC - date.getTime();
}

/** « 2026-11-27T09:00 » (heure de Bruxelles) → Date. Accepte aussi une date ISO complète ou « 2026-11-27 ». */
function parseLocal(text) {
  if (!text) return null;
  const value = String(text).trim();
  if (/[zZ]$|[+-]\d{2}:?\d{2}$/.test(value)) {
    const d = new Date(value);
    return isNaN(d) ? null : d;
  }
  const m = value.match(/^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{1,2}):(\d{2}))?/);
  if (!m) return null;
  const guess = Date.UTC(+m[1], +m[2] - 1, +m[3], m[4] ? +m[4] : 9, m[5] ? +m[5] : 0);
  const first = guess - tzOffset(new Date(guess));
  return new Date(guess - tzOffset(new Date(first)));
}

function dayKey(date) {
  return new Intl.DateTimeFormat("fr-CA", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit" }).format(date);
}

function startOfDay(date) {
  return parseLocal(dayKey(date) + "T00:00");
}

function hm(date) {
  return new Intl.DateTimeFormat("fr-BE", { timeZone: TZ, hour: "2-digit", minute: "2-digit" }).format(date);
}

function dayLabel(date) {
  return new Intl.DateTimeFormat("fr-BE", { timeZone: TZ, weekday: "long", day: "numeric", month: "long" }).format(date);
}

function normalize(text) {
  return String(text || "").toLowerCase().replace(/œ/g, "oe").replace(/æ/g, "ae").normalize("NFD").replace(/[̀-ͯ]/g, "").trim();
}

function recurrenceStep(date, recurrence) {
  const d = new Date(date.getTime());
  if (recurrence === "daily") d.setUTCDate(d.getUTCDate() + 1);
  else if (recurrence === "weekly") d.setUTCDate(d.getUTCDate() + 7);
  else if (recurrence === "monthly") d.setUTCMonth(d.getUTCMonth() + 1);
  else if (recurrence === "yearly") d.setUTCFullYear(d.getUTCFullYear() + 1);
  else return null;
  return d;
}

/** Occurrences d'un événement (éventuellement récurrent) entre deux dates. */
function occurrences(event, from, to) {
  const duration = Math.max(event.end - event.start, 0);
  const result = [];
  let start = event.start;
  for (let i = 0; i < 2000 && start < to; i++) {
    if (start.getTime() + Math.max(duration, 1) > from.getTime()) result.push({ ...event, start, end: new Date(start.getTime() + duration) });
    const next = recurrenceStep(start, event.recurrence);
    if (!next) break;
    start = next;
  }
  return result;
}

// ---------------------------------------------------------------- Outils

/**
 * Construit le serveur MCP pour une clé donnée.
 * @param {object} ctx  { repo, key: { name, scopes, personId, ownerName, ownerUid } }
 */
function buildServer(ctx) {
  const { repo, key } = ctx;
  const canWrite = (key.scopes || []).includes("write");
  const canFamily = (key.scopes || []).includes("family");
  const botName = key.name || "Bot";

  const server = new McpServer(
    { name: "tribu", version: "1.0.0" },
    {
      instructions:
        "Tribu est l'application de pilotage d'une famille belge (courses, menu, agenda, rappels, tâches). " +
        `Tu parles au nom de ${key.ownerName || "un membre de la famille"} : « moi » désigne cette personne. ` +
        "Les heures sont à l'heure de Bruxelles ; donne les dates au format AAAA-MM-JJTHH:MM. " +
        "Appelle « membres » si tu dois savoir qui fait partie de la famille.",
    },
  );

  const text = (value) => ({ content: [{ type: "text", text: value }] });
  const denied = () => text("Cette clé n'a pas le droit de modifier Tribu. Active « Peut modifier » dans l'app (Plus → Bots et IA).");

  /** Résout « Camille », « moi », « tous » en identifiants de personnes. */
  async function resolvePeople(names) {
    const people = await repo.people();
    if (!names || names.length === 0) return { ids: key.personId ? [key.personId] : [], unknown: [] };
    const ids = new Set();
    const unknown = [];
    for (const raw of names) {
      const n = normalize(raw);
      if (["moi", "me", "je"].includes(n) && key.personId) { ids.add(key.personId); continue; }
      if (["tous", "toute la famille", "tout le monde", "famille"].includes(n)) { people.forEach((p) => ids.add(p.id)); continue; }
      const match = people.find((p) => normalize(p.firstName) === n) || people.find((p) => normalize(p.firstName).startsWith(n));
      if (match) ids.add(match.id); else unknown.push(raw);
    }
    return { ids: [...ids], unknown };
  }

  async function namesOf(ids) {
    const people = await repo.people();
    return ids.map((id) => people.find((p) => p.id === id)?.firstName).filter(Boolean).join(", ");
  }

  // --- Lecture

  server.tool("membres", "Liste les membres de la famille (prénoms, âges) et indique qui est « moi ».", {}, async () => {
    const people = await repo.people();
    if (!people.length) return text("Aucun membre enregistré.");
    const lines = people.map((p) => {
      const age = p.birthDate ? Math.floor((Date.now() - p.birthDate.getTime()) / (365.25 * DAY)) : null;
      return `- ${p.firstName}${age != null ? ` (${age} ans)` : ""}${p.id === key.personId ? " ← moi" : ""}`;
    });
    return text(`Famille « ${await repo.householdName()} » :\n${lines.join("\n")}`);
  });

  server.tool(
    "programme_du_jour",
    "Rendez-vous, rappels et repas prévus un jour donné (aujourd'hui par défaut).",
    { date: z.string().optional().describe("Jour au format AAAA-MM-JJ ; aujourd'hui si absent") },
    async ({ date }) => {
      const day = startOfDay(parseLocal(date) || new Date());
      const end = new Date(day.getTime() + DAY);
      const lines = [];
      for (const event of await repo.events()) {
        for (const o of occurrences(event, day, end)) {
          lines.push({ at: o.start, line: `${o.allDay ? "Journée" : hm(o.start)} · ${o.title}${o.personIds.length ? ` (${await namesOf(o.personIds)})` : ""}${o.location ? ` — ${o.location}` : ""}` });
        }
      }
      for (const r of await repo.reminders()) {
        if (r.dueAt >= day && r.dueAt < end) {
          lines.push({ at: r.dueAt, line: `${hm(r.dueAt)} · Rappel : ${r.title} pour ${await namesOf(r.assigneeIds)}${r.doneAt ? " (fait)" : ""}` });
        }
      }
      const meal = await repo.meal(dayKey(day));
      if (meal) lines.push({ at: new Date(day.getTime() + 19 * 3600 * 1000), line: `Soir · Repas : ${meal.title}` });
      lines.sort((a, b) => a.at - b.at);
      return text(lines.length ? `${dayLabel(day)} :\n${lines.map((l) => "- " + l.line).join("\n")}` : `Rien de prévu ${dayLabel(day)}.`);
    },
  );

  server.tool("liste_de_courses", "Articles qui restent à acheter sur la liste de courses partagée.", {}, async () => {
    const items = (await repo.shopping()).filter((i) => !i.checked);
    if (!items.length) return text("La liste de courses est vide.");
    return text(`${items.length} article(s) à acheter :\n${items.map((i) => `- ${i.name}${i.quantity ? ` (${i.quantity})` : ""}`).join("\n")}`);
  });

  server.tool(
    "menu",
    "Repas prévus au menu pour les prochains jours.",
    { jours: z.number().int().min(1).max(14).optional().describe("Nombre de jours à partir d'aujourd'hui (7 par défaut)") },
    async ({ jours }) => {
      const count = jours || 7;
      const today = startOfDay(new Date());
      const lines = [];
      for (let i = 0; i < count; i++) {
        const day = new Date(today.getTime() + i * DAY + 12 * 3600 * 1000);
        const meal = await repo.meal(dayKey(day));
        lines.push(`- ${dayLabel(day)} : ${meal ? meal.title : "rien de prévu"}`);
      }
      return text(lines.join("\n"));
    },
  );

  server.tool(
    "taches",
    "Liste les tâches en cours. Par défaut, celles de « moi ».",
    {
      personne: z.string().optional().describe("Prénom, « moi » ou « tous »"),
      inclure_terminees: z.boolean().optional(),
    },
    async ({ personne, inclure_terminees }) => {
      const tasks = (await repo.tasks()).filter((t) => t.kind !== "idea" && (inclure_terminees || t.status !== "done"));
      let filtered = tasks;
      if (normalize(personne) !== "tous") {
        const { ids, unknown } = await resolvePeople(personne ? [personne] : []);
        if (unknown.length) return text(`Je ne connais pas « ${unknown.join(", ")} ». Appelle « membres » pour voir la famille.`);
        filtered = tasks.filter((t) => t.assigneeIds.some((id) => ids.includes(id)));
      }
      if (!filtered.length) return text("Aucune tâche en cours.");
      const status = { todo: "à faire", doing: "en cours", done: "fait" };
      const lines = [];
      for (const t of filtered) {
        lines.push(`- ${t.title} [${status[t.status] || t.status}]${t.assigneeIds.length ? ` — ${await namesOf(t.assigneeIds)}` : ""}${t.dueDate ? `, pour le ${dayLabel(t.dueDate)}` : ""}`);
      }
      return text(lines.join("\n"));
    },
  );

  server.tool(
    "rappels",
    "Rappels pas encore faits. Par défaut, ceux de « moi ».",
    { personne: z.string().optional().describe("Prénom, « moi » ou « tous »") },
    async ({ personne }) => {
      let list = (await repo.reminders()).filter((r) => !r.doneAt);
      if (normalize(personne) !== "tous") {
        const { ids } = await resolvePeople(personne ? [personne] : []);
        list = list.filter((r) => r.assigneeIds.some((id) => ids.includes(id)));
      }
      list.sort((a, b) => a.dueAt - b.dueAt);
      if (!list.length) return text("Aucun rappel en attente.");
      return text(list.map((r) => `- ${dayLabel(r.dueAt)} à ${hm(r.dueAt)} : ${r.title} (de ${r.createdByName})`).join("\n"));
    },
  );

  if (canFamily) {
    server.tool(
      "tailles",
      "Tailles et pointures d'un membre de la famille (vêtements, chaussures…).",
      { personne: z.string().describe("Prénom") },
      async ({ personne }) => {
        const people = await repo.people();
        const p = people.find((x) => normalize(x.firstName) === normalize(personne));
        if (!p) return text(`Je ne connais pas « ${personne} ».`);
        const sizes = Object.values(p.sizes || {});
        if (!sizes.length) return text(`Aucune taille notée pour ${p.firstName}.`);
        return text(`${p.firstName} :\n${sizes.map((s) => `- ${s.label} : ${s.value}${s.detail ? ` (${s.detail})` : ""}`).join("\n")}`);
      },
    );
  }

  // --- Écriture

  server.tool(
    "ajouter_courses",
    "Ajoute un ou plusieurs articles à la liste de courses partagée.",
    {
      articles: z.array(z.string()).min(1).describe("Articles à ajouter, par ex. [\"lait\", \"œufs\"]"),
    },
    async ({ articles }) => {
      if (!canWrite) return denied();
      const names = articles.map((a) => a.trim()).filter(Boolean).map((a) => a.charAt(0).toUpperCase() + a.slice(1));
      const existing = new Set((await repo.shopping()).filter((i) => !i.checked).map((i) => normalize(i.name)));
      const added = names.filter((n) => !existing.has(normalize(n)));
      for (const name of added) await repo.addShopping(name, `Ajouté par ${botName}`);
      if (added.length) await repo.feed(`a ajouté ${added.join(", ").toLowerCase()} aux courses`, botName, "basket");
      const skipped = names.filter((n) => !added.includes(n));
      return text(`${added.length ? `Ajouté : ${added.join(", ")}.` : ""}${skipped.length ? ` Déjà sur la liste : ${skipped.join(", ")}.` : ""}`.trim());
    },
  );

  server.tool(
    "cocher_courses",
    "Coche (marque comme acheté) des articles de la liste de courses.",
    { articles: z.array(z.string()).min(1) },
    async ({ articles }) => {
      if (!canWrite) return denied();
      const items = (await repo.shopping()).filter((i) => !i.checked);
      const done = [];
      for (const a of articles) {
        const item = items.find((i) => normalize(i.name) === normalize(a)) || items.find((i) => normalize(i.name).includes(normalize(a)));
        if (item) { await repo.checkShopping(item.id, botName); done.push(item.name); }
      }
      return text(done.length ? `Coché : ${done.join(", ")}.` : "Aucun de ces articles n'est sur la liste.");
    },
  );

  server.tool(
    "creer_tache",
    "Crée une tâche et la confie à une ou plusieurs personnes.",
    {
      titre: z.string().min(1),
      pour: z.array(z.string()).optional().describe("Prénoms (ou « moi ») ; « moi » par défaut"),
      echeance: z.string().optional().describe("Date limite AAAA-MM-JJ"),
      notes: z.string().optional(),
    },
    async ({ titre, pour, echeance, notes }) => {
      if (!canWrite) return denied();
      const { ids, unknown } = await resolvePeople(pour);
      if (unknown.length) return text(`Je ne connais pas « ${unknown.join(", ")} ». Appelle « membres » pour voir la famille.`);
      const due = parseLocal(echeance);
      await repo.addTask({ title: titre.trim(), notes: notes || "", assigneeIds: ids, dueDate: due, author: `${key.ownerName || botName} (via ${botName})`, ownerUid: key.ownerUid });
      await repo.feed(`a créé la tâche « ${titre.trim()} » pour ${await namesOf(ids)}`, botName, "checklist");
      return text(`Tâche « ${titre.trim()} » créée pour ${await namesOf(ids) || "personne"}${due ? `, à faire pour le ${dayLabel(due)}` : ""}.`);
    },
  );

  server.tool(
    "creer_rappel",
    "Crée un rappel avec notification sur le téléphone des personnes concernées.",
    {
      titre: z.string().min(1).describe("Ce qu'il faut faire, par ex. « Acheter du pain »"),
      quand: z.string().describe("Date et heure AAAA-MM-JJTHH:MM (heure de Bruxelles)"),
      pour: z.array(z.string()).optional().describe("Prénoms (ou « moi ») ; « moi » par défaut"),
      alertes_minutes_avant: z.array(z.number().int().min(0).max(10080)).optional().describe("Par ex. [30, 0] : 30 min avant et à l'heure"),
    },
    async ({ titre, quand, pour, alertes_minutes_avant }) => {
      if (!canWrite) return denied();
      const due = parseLocal(quand);
      if (!due) return text("Je n'ai pas compris la date. Utilise le format AAAA-MM-JJTHH:MM.");
      const { ids, unknown } = await resolvePeople(pour);
      if (unknown.length) return text(`Je ne connais pas « ${unknown.join(", ")} ».`);
      const offsets = (alertes_minutes_avant && alertes_minutes_avant.length ? alertes_minutes_avant : [0]).sort((a, b) => b - a);
      await repo.addReminder({ title: titre.trim(), dueAt: due, offsets, assigneeIds: ids, createdById: key.personId || "", createdByName: key.ownerName || botName });
      await repo.feed(`a programmé le rappel « ${titre.trim()} » pour ${await namesOf(ids)}`, botName, "bell");
      return text(`Rappel « ${titre.trim()} » pour ${await namesOf(ids)} le ${dayLabel(due)} à ${hm(due)}, notifications : ${offsets.map((o) => (o === 0 ? "à l'heure" : `${o} min avant`)).join(", ")}.`);
    },
  );

  server.tool(
    "ajouter_evenement",
    "Ajoute un événement à l'agenda partagé de la famille.",
    {
      titre: z.string().min(1),
      debut: z.string().describe("AAAA-MM-JJTHH:MM, ou AAAA-MM-JJ pour toute la journée"),
      fin: z.string().optional(),
      pour: z.array(z.string()).optional(),
      lieu: z.string().optional(),
    },
    async ({ titre, debut, fin, pour, lieu }) => {
      if (!canWrite) return denied();
      const allDay = /^\d{4}-\d{2}-\d{2}$/.test(String(debut).trim());
      const start = allDay ? parseLocal(debut + "T00:00") : parseLocal(debut);
      if (!start) return text("Je n'ai pas compris la date de début.");
      const end = parseLocal(fin) || new Date(start.getTime() + (allDay ? DAY : 3600 * 1000));
      const { ids, unknown } = pour && pour.length ? await resolvePeople(pour) : { ids: [], unknown: [] };
      if (unknown.length) return text(`Je ne connais pas « ${unknown.join(", ")} ».`);
      await repo.addEvent({ title: titre.trim(), start, end, allDay, personIds: ids, location: lieu || "", createdByName: `${key.ownerName || botName} (via ${botName})` });
      await repo.feed(`a ajouté « ${titre.trim()} » à l'agenda`, botName, "calendar");
      return text(`« ${titre.trim()} » ajouté à l'agenda le ${dayLabel(start)}${allDay ? "" : ` à ${hm(start)}`}.`);
    },
  );

  return server;
}

// ---------------------------------------------------------------- Accès Firestore

function firestoreRepo(db, householdId) {
  const { Timestamp, FieldValue } = require("firebase-admin/firestore");
  const h = db.collection("households").doc(householdId);
  const date = (v) => (v && v.toDate ? v.toDate() : null);
  let peopleCache = null;

  return {
    async householdName() {
      return (await h.get()).data()?.name || "La tribu";
    },
    async people() {
      if (!peopleCache) {
        const snap = await h.collection("people").get();
        peopleCache = snap.docs.map((d) => ({ id: d.id, ...d.data(), birthDate: date(d.data().birthDate) }));
      }
      return peopleCache;
    },
    async events() {
      const snap = await h.collection("events").get();
      return snap.docs.map((d) => {
        const e = d.data();
        return { id: d.id, title: e.title, start: date(e.start), end: date(e.end) || date(e.start), allDay: !!e.allDay,
          personIds: e.personIds || [], location: e.location || "", recurrence: e.recurrence || "none" };
      }).filter((e) => e.start);
    },
    async reminders() {
      const snap = await h.collection("reminders").get();
      return snap.docs.map((d) => {
        const r = d.data();
        return { id: d.id, title: r.title, dueAt: date(r.dueAt), doneAt: date(r.doneAt), assigneeIds: r.assigneeIds || [], createdByName: r.createdByName || "" };
      }).filter((r) => r.dueAt);
    },
    async meal(key) {
      const doc = await h.collection("meals").doc(key).get();
      return doc.exists ? doc.data() : null;
    },
    async shopping() {
      const snap = await h.collection("lists").doc("courses").collection("items").get();
      return snap.docs.map((d) => ({ id: d.id, name: d.data().name, quantity: d.data().quantity, checked: !!d.data().checked }));
    },
    async tasks() {
      const snap = await h.collection("tasks").get();
      return snap.docs.map((d) => {
        const t = d.data();
        return { id: d.id, title: t.title, kind: t.kind, status: t.status, assigneeIds: t.assigneeIds || [], dueDate: date(t.dueDate) };
      });
    },
    async addShopping(name, origin) {
      await h.collection("lists").doc("courses").collection("items").add({
        name, checked: false, addedBy: origin.replace("Ajouté par ", ""), origin, createdAt: FieldValue.serverTimestamp(),
      });
    },
    async checkShopping(id, by) {
      await h.collection("lists").doc("courses").collection("items").doc(id).update({ checked: true, checkedBy: by });
    },
    async addTask({ title, notes, assigneeIds, dueDate, author, ownerUid }) {
      const now = Timestamp.now();
      await h.collection("tasks").add({
        title, notes, kind: "task", status: "todo", assigneeIds, dueDate: dueDate ? Timestamp.fromDate(dueDate) : null,
        estimatedCost: null, actualCost: null, links: [], checklist: [], comments: [], voterIds: [],
        followerUids: ownerUid ? [ownerUid] : [], createdByName: author, createdAt: now, updatedAt: now,
        lastEditedByUid: "bot", lastEditedByName: author, lastChange: "a créé la tâche",
      });
    },
    async addReminder({ title, dueAt, offsets, assigneeIds, createdById, createdByName }) {
      await h.collection("reminders").add({
        title, note: "", dueAt: Timestamp.fromDate(dueAt), offsets, recurrence: "none", assigneeIds,
        createdById, createdByName, doneAt: null, doneByName: null, seenByIds: [], createdAt: Timestamp.now(),
      });
    },
    async addEvent({ title, start, end, allDay, personIds, location, createdByName }) {
      await h.collection("events").add({
        title, start: Timestamp.fromDate(start), end: Timestamp.fromDate(end), allDay, personIds, location,
        notes: "", recurrence: "none", alertMinutes: allDay ? null : 60, createdByName,
      });
    },
    async feed(text, actorName, icon) {
      await h.collection("feed").add({ text, actorName, icon, createdAt: Timestamp.now() });
    },
  };
}

/** Clé reçue dans l'adresse → fiche de la clé (ou null). Les clés sont stockées sous forme d'empreinte SHA-256. */
async function authenticate(db, rawKey) {
  if (!rawKey || rawKey.length < 24) return null;
  const hash = crypto.createHash("sha256").update(rawKey).digest("hex");
  const ref = db.collection("apiKeys").doc(hash);
  const doc = await ref.get();
  if (!doc.exists || doc.data().revoked) return null;
  const { FieldValue } = require("firebase-admin/firestore");
  ref.update({ lastUsedAt: FieldValue.serverTimestamp(), calls: FieldValue.increment(1) }).catch(() => {});
  return doc.data();
}

/** Point d'entrée HTTP (transport « Streamable HTTP » sans session). */
async function handleHttp(db, req, res) {
  const { StreamableHTTPServerTransport } = require("@modelcontextprotocol/sdk/server/streamableHttp.js");
  const rawKey = (req.path || "").split("/").filter(Boolean).pop() || (req.headers.authorization || "").replace(/^Bearer\s+/i, "");
  const key = await authenticate(db, rawKey);
  if (!key) {
    res.status(401).json({ jsonrpc: "2.0", error: { code: -32001, message: "Clé Tribu invalide ou révoquée." }, id: null });
    return;
  }
  if (req.method !== "POST") {
    res.status(405).set("Allow", "POST").json({ jsonrpc: "2.0", error: { code: -32000, message: "Méthode non prise en charge." }, id: null });
    return;
  }
  const server = buildServer({ repo: firestoreRepo(db, key.householdId), key });
  const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
  res.on("close", () => {
    transport.close();
    server.close();
  });
  await server.connect(transport);
  await transport.handleRequest(req, res, req.body);
}

module.exports = { buildServer, handleHttp, parseLocal, dayKey, occurrences };
