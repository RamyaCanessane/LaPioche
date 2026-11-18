import { API_URL } from "./config.js";
import { api } from "./api.js";

const $ = (selector, root = document) => root.querySelector(selector);

$("#docs-link").href = API_URL;

const dateFormat = new Intl.DateTimeFormat("fr-FR", { dateStyle: "long" });
const formatDate = (iso) => dateFormat.format(new Date(iso));

// Construit un élément sans jamais passer par innerHTML : les données de
// l'API (titres, noms) sont insérées comme du texte.
function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (key === "class") node.className = value;
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value);
  }
  node.append(...children);
  return node;
}

function button(label, onClick, className = "") {
  return el(
    "button",
    { type: "button", class: className, onclick: onClick },
    label,
  );
}

function toast(message, isError = false) {
  const node = el("p", { class: isError ? "toast error" : "toast" }, message);
  $("#toasts").append(node);
  setTimeout(() => node.remove(), 5000);
}

// Exécute une action déclenchée par un bouton et affiche l'erreur de l'API.
async function run(action) {
  try {
    await action();
  } catch (error) {
    toast(error.message, true);
  }
}

function showFormError(dialog, error) {
  const target = $(".form-error", dialog);
  target.textContent = error ? error.message : "";
  target.hidden = !error;
}

for (const cancel of document.querySelectorAll("[data-cancel]")) {
  cancel.addEventListener("click", () => cancel.closest("dialog").close());
}

// Branche un formulaire de boîte de dialogue sur un appel à l'API.
// L'erreur renvoyée par l'API reste affichée dans la boîte, qui ne se ferme
// qu'en cas de succès.
function bindSubmit(dialog, form, handler) {
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    showFormError(dialog, null);
    try {
      await handler(new FormData(form));
      dialog.close();
      await refresh();
    } catch (error) {
      showFormError(dialog, error);
    }
  });
}

// --- Onglets ---------------------------------------------------------------

const tabs = ["games", "members", "overdue"];

function currentTab() {
  const name = location.hash.slice(1);
  return tabs.includes(name) ? name : "games";
}

async function refresh() {
  const tab = currentTab();
  for (const name of tabs) {
    $(`#${name}`).hidden = name !== tab;
    $(`[data-tab="${name}"]`).toggleAttribute("aria-current", name === tab);
  }
  const loaders = {
    games: loadGames,
    members: loadMembers,
    overdue: loadOverdue,
  };
  if (tab !== "overdue") updateOverdueCount();
  await run(loaders[tab]);
}

window.addEventListener("hashchange", refresh);

// --- Jeux ------------------------------------------------------------------

// Critères de recherche appliqués : ils sont conservés quand la liste est
// rechargée (après un ajout, un emprunt, un retour...).
let gameFilters = {};

const filtersForm = $("#games-filters");

// Un entier strictement positif, sinon null : l'API refuserait le reste.
function positiveInteger(value) {
  const text = String(value ?? "").trim();
  const number = Number(text);
  return /^\d+$/.test(text) && Number.isSafeInteger(number) && number > 0
    ? number
    : null;
}

// Les champs vides ou invalides sont simplement ignorés.
function readGameFilters(data) {
  const filters = {};
  const q = String(data.get("q") ?? "").trim();
  if (q) filters.q = q;
  const players = positiveInteger(data.get("players"));
  if (players !== null) filters.players = players;
  const maxDuration = positiveInteger(data.get("maxDuration"));
  if (maxDuration !== null) filters.maxDuration = maxDuration;
  if (data.get("available")) filters.available = true;
  return filters;
}

filtersForm.addEventListener("submit", (event) => {
  event.preventDefault();
  gameFilters = readGameFilters(new FormData(filtersForm));
  run(loadGames);
});

filtersForm.elements.available.addEventListener("change", () => {
  gameFilters = readGameFilters(new FormData(filtersForm));
  run(loadGames);
});

$("#filters-reset").addEventListener("click", () => {
  filtersForm.reset();
  gameFilters = {};
  run(loadGames);
});

async function loadGames() {
  const games = await api.listGames(gameFilters);
  const isSearch = Object.keys(gameFilters).length > 0;
  // Ludothèque vide et recherche sans résultat : deux messages différents.
  $("#games-empty").hidden = !(games.length === 0 && !isSearch);
  $("#games-no-result").hidden = !(games.length === 0 && isSearch);
  $("#games-list").replaceChildren(...games.map(gameCard));
}

function gameCard(game) {
  const players =
    game.minPlayers === game.maxPlayers
      ? `${game.minPlayers}`
      : `${game.minPlayers} à ${game.maxPlayers}`;
  const status = game.isAvailable
    ? el("span", { class: "badge ok" }, "Disponible")
    : el("span", { class: "badge busy" }, "Emprunté");

  const actions = el("div", { class: "actions" });
  if (game.isAvailable) {
    actions.append(
      button("Emprunter", () => openBorrowDialog(game), "primary"),
    );
  } else {
    actions.append(button("Rendre", () => returnGame(game), "primary"));
  }
  actions.append(button("Modifier", () => openGameDialog(game)));
  actions.append(button("Supprimer", () => deleteGame(game), "danger"));
  return el(
    "li",
    { class: "card" },
    el("div", { class: "card-head" }, el("h3", {}, game.title), status),
    el(
      "p",
      { class: "meta" },
      `${players} joueur·ses · ${game.durationMinutes} min`,
    ),
    actions,
  );
}

async function deleteGame(game) {
  const confirmed = window.confirm(
    `Voulez-vous vraiment supprimer « ${game.title} » ?`,
  );

  if (!confirmed) return;

  await run(async () => {
    await api.deleteGame(game.id);

    toast(`« ${game.title} » a été supprimé.`);

    await loadGames();
  });
}

const gameDialog = $("#game-dialog");
const gameForm = $("#game-form");

let editedGame = null;

function openGameDialog(game = null) {
  editedGame = game;
  gameForm.reset();
  $("#game-dialog-title").textContent = game
    ? `Modifier « ${game.title} »`
    : "Ajouter un jeu";
  if (game) {
    gameForm.elements.title.value = game.title;
    gameForm.elements.minPlayers.value = game.minPlayers;
    gameForm.elements.maxPlayers.value = game.maxPlayers;
    gameForm.elements.durationMinutes.value = game.durationMinutes;
  }
  showFormError(gameDialog, null);
  gameDialog.showModal();
}

$("#add-game").addEventListener("click", () => openGameDialog());

bindSubmit(gameDialog, gameForm, (data) => {
  const game = {
    title: data.get("title").trim(),
    minPlayers: Number(data.get("minPlayers")),
    maxPlayers: Number(data.get("maxPlayers")),
    durationMinutes: Number(data.get("durationMinutes")),
  };
  return editedGame
    ? api.updateGame(editedGame.id, game)
    : api.createGame(game);
});

// --- Emprunts --------------------------------------------------------------

const borrowDialog = $("#borrow-dialog");
const borrowForm = $("#borrow-form");
let borrowedGame = null;

async function openBorrowDialog(game) {
  await run(async () => {
    const members = await api.listMembers();
    if (members.length === 0) {
      toast("Ajoutez d'abord un·e adhérent·e pour pouvoir emprunter.", true);
      return;
    }
    borrowedGame = game;
    $("#borrow-dialog-title").textContent = `Emprunter « ${game.title} »`;
    $("select", borrowForm).replaceChildren(
      ...members.map((member) =>
        el("option", { value: member.id }, `${member.name} (${member.email})`),
      ),
    );
    showFormError(borrowDialog, null);
    borrowDialog.showModal();
  });
}

async function returnGame(game) {
  await run(async () => {
    const members = await api.listMembers();
    const loansByMember = await Promise.all(
      members.map((member) => api.listMemberLoans(member.id)),
    );
    const loan = loansByMember
      .flat()
      .find((l) => l.gameID === game.id && !l.returnedAt);
    if (!loan) {
      throw new Error("Aucun emprunt en cours n'a été trouvé pour ce jeu.");
    }
    await api.returnLoan(loan.id);
    toast(`« ${game.title} » a été rendu.`);
    await loadGames();
    updateOverdueCount();
  });
}

bindSubmit(borrowDialog, borrowForm, async (data) => {
  const loan = await api.borrow(borrowedGame.id, data.get("memberID"));
  toast(
    `« ${borrowedGame.title} » emprunté, à rendre avant le ${formatDate(loan.dueAt)}.`,
  );
});

// --- Adhérent·es -----------------------------------------------------------

async function loadMembers() {
  const members = await api.listMembers();
  $("#members-empty").hidden = members.length > 0;
  $("#members-list").replaceChildren(...members.map(memberRow));
}

function memberRow(member) {
  const actions = el(
    "div",
    { class: "actions" },
    button("Emprunts", () => openLoansDialog(member), "info"),
    button("Modifier", () => openMemberDialog(member)),
    button("Supprimer", () => deleteMember(member), "danger"),
  );
  return el(
    "li",
    { class: "row" },
    el(
      "div",
      { class: "row-main" },
      el("p", {}, el("strong", {}, member.name)),
      el("p", { class: "meta" }, member.email),
    ),
    actions,
  );
}

const memberDialog = $("#member-dialog");
const memberForm = $("#member-form");

let editedMember = null;

function openMemberDialog(member = null) {
  editedMember = member;
  memberForm.reset();
  $("#member-dialog-title").textContent = member
    ? `Modifier « ${member.name} »`
    : "Ajouter un·e adhérent·e";
  if (member) {
    memberForm.elements.name.value = member.name;
    memberForm.elements.email.value = member.email;
  }
  showFormError(memberDialog, null);
  memberDialog.showModal();
}

$("#add-member").addEventListener("click", () => openMemberDialog());

bindSubmit(memberDialog, memberForm, (data) => {
  const member = {
    name: data.get("name").trim(),
    email: data.get("email").trim(),
  };
  return editedMember
    ? api.updateMember(editedMember.id, member)
    : api.createMember(member);
});

async function deleteMember(member) {
  if (confirm(`Voulez-vous vraiment supprimer « ${member.name} » ?`)) {
    await run(async () => {
      await api.deleteMember(member.id);
      toast(`« ${member.name} » a été supprimé·e.`);
      await loadMembers();
    });
  }
}

const loansDialog = $("#loans-dialog");

// Rendu si returnedAt est renseigné, en retard si la date prévue est passée.
function loanStatus(loan) {
  if (loan.returnedAt) return { label: "Rendu", className: "ok" };
  if (new Date(loan.dueAt) < new Date()) {
    return { label: "En retard", className: "late" };
  }
  return { label: "En cours", className: "busy" };
}

function loanRow(loan, titles) {
  const status = loanStatus(loan);
  return el(
    "li",
    { class: "row" },
    el(
      "div",
      { class: "row-main" },
      el("p", {}, el("strong", {}, titles.get(loan.gameID) ?? "Jeu inconnu")),
      el(
        "p",
        { class: "meta" },
        `Emprunté le ${formatDate(loan.borrowedAt)} · À rendre avant le ${formatDate(loan.dueAt)}`,
      ),
    ),
    el("span", { class: `badge ${status.className}` }, status.label),
  );
}

async function openLoansDialog(member) {
  await run(async () => {
    // L'API ne renvoie que l'identifiant du jeu : on récupère les titres.
    const [loans, games] = await Promise.all([
      api.listMemberLoans(member.id),
      api.listGames(),
    ]);
    const titles = new Map(games.map((game) => [game.id, game.title]));
    $("#loans-dialog-title").textContent = `Emprunts de ${member.name}`;
    $("#loans-empty").hidden = loans.length > 0;
    $("#loans-list").replaceChildren(
      ...loans.map((loan) => loanRow(loan, titles)),
    );
    loansDialog.showModal();
  });
}

// --- Emprunts en retard ----------------------------------------------------

function setOverdueCount(count) {
  const badge = $("#overdue-count");
  badge.textContent = count;
  badge.hidden = count === 0;
}

// L'indicateur est secondaire : s'il échoue, on n'affiche pas d'erreur.
async function updateOverdueCount() {
  try {
    setOverdueCount((await api.listOverdueLoans()).length);
  } catch {
    // on garde la valeur précédente
  }
}

function daysLate(loan) {
  const days = Math.floor((Date.now() - new Date(loan.dueAt)) / 86_400_000);
  return Math.max(1, days);
}

function overdueRow(loan, titles, names) {
  const days = daysLate(loan);
  return el(
    "li",
    { class: "row late" },
    el(
      "div",
      { class: "row-main" },
      el("p", {}, el("strong", {}, titles.get(loan.gameID) ?? "Jeu inconnu")),
      el(
        "p",
        { class: "meta" },
        `Emprunté par ${names.get(loan.memberID) ?? "adhérent·e inconnu·e"} · À rendre avant le ${formatDate(loan.dueAt)}`,
      ),
    ),
    // Le libellé texte signale le retard : la couleur ne suffit pas.
    el(
      "span",
      { class: "badge late" },
      `En retard : ${days} jour${days > 1 ? "s" : ""}`,
    ),
  );
}

async function loadOverdue() {
  const [loans, games, members] = await Promise.all([
    api.listOverdueLoans(),
    api.listGames(),
    api.listMembers(),
  ]);
  const titles = new Map(games.map((game) => [game.id, game.title]));
  const names = new Map(members.map((member) => [member.id, member.name]));
  setOverdueCount(loans.length);
  $("#overdue-empty").hidden = loans.length > 0;
  $("#overdue-list").replaceChildren(
    ...loans.map((loan) => overdueRow(loan, titles, names)),
  );
}

refresh();
