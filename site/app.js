const STORAGE_KEY = "site-todos";

const form = document.querySelector("#todo-form");
const input = document.querySelector("#todo-input");
const list = document.querySelector("#todo-list");
const empty = document.querySelector("#empty");
const count = document.querySelector("#count");
const clearDone = document.querySelector("#clear-done");
const filters = document.querySelectorAll(".filter");

let todos = load();
let filter = "all";

form.addEventListener("submit", (event) => {
  event.preventDefault();
  const text = input.value.trim();
  if (!text) return;
  todos.push({ id: crypto.randomUUID(), text, done: false });
  input.value = "";
  save();
  render();
});

list.addEventListener("change", (event) => {
  const item = event.target.closest(".item");
  if (!item || event.target.type !== "checkbox") return;
  const todo = todos.find((entry) => entry.id === item.dataset.id);
  if (!todo) return;
  todo.done = event.target.checked;
  save();
  render();
});

list.addEventListener("click", (event) => {
  const button = event.target.closest(".delete");
  if (!button) return;
  const id = button.closest(".item").dataset.id;
  todos = todos.filter((entry) => entry.id !== id);
  save();
  render();
});

filters.forEach((button) => {
  button.addEventListener("click", () => {
    filter = button.dataset.filter;
    filters.forEach((entry) => entry.classList.toggle("is-active", entry === button));
    render();
  });
});

clearDone.addEventListener("click", () => {
  todos = todos.filter((entry) => !entry.done);
  save();
  render();
});

function load() {
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY));
    return Array.isArray(saved) ? saved : [];
  } catch {
    return [];
  }
}

function save() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(todos));
}

function visibleTodos() {
  if (filter === "active") return todos.filter((entry) => !entry.done);
  if (filter === "done") return todos.filter((entry) => entry.done);
  return todos;
}

function render() {
  const shown = visibleTodos();
  list.replaceChildren(
    ...shown.map((todo) => {
      const item = document.createElement("li");
      item.className = todo.done ? "item is-done" : "item";
      item.dataset.id = todo.id;

      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.checked = todo.done;
      checkbox.setAttribute("aria-label", `Mark "${todo.text}" done`);

      const label = document.createElement("span");
      label.textContent = todo.text;

      const remove = document.createElement("button");
      remove.type = "button";
      remove.className = "delete";
      remove.textContent = "Delete";
      remove.setAttribute("aria-label", `Delete ${todo.text}`);

      item.append(checkbox, label, remove);
      return item;
    })
  );

  const remaining = todos.filter((entry) => !entry.done).length;
  count.textContent = `${remaining} left`;
  empty.hidden = shown.length > 0;
  empty.textContent =
    filter === "done" ? "No finished tasks." : filter === "active" ? "No active tasks." : "Nothing here yet.";
  clearDone.hidden = !todos.some((entry) => entry.done);
}

render();
