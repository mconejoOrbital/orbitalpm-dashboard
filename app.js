const dashboard = window.DASHBOARD_DATA;

if (!dashboard || !Array.isArray(dashboard.engineers)) {
  document.body.innerHTML = `
    <main class="empty-state" style="margin:40px">
      <h1>Datos no disponibles</h1>
      <p>Ejecuta <strong>ActualizarDatos.ps1</strong> para obtener la información desde Azure DevOps.</p>
    </main>`;
  throw new Error("No se encontró window.DASHBOARD_DATA");
}

const state = { search: "", filter: "all", taskSearch: "", taskProject: "", taskStatus: "" };
const dateFormatter = new Intl.DateTimeFormat("es-SV", { day: "numeric", month: "long", year: "numeric" });
const shortDateFormatter = new Intl.DateTimeFormat("es-SV", { day: "numeric", month: "short" });

const formatDate = (value, short = false) => {
  const date = new Date(`${value}T12:00:00`);
  return (short ? shortDateFormatter : dateFormatter).format(date);
};

const escapeHtml = (value = "") =>
  String(value).replace(/[&<>"']/g, character => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#039;"
  })[character]);

const initials = name => name
  .split(/\s+/)
  .slice(0, 2)
  .map(part => part[0])
  .join("")
  .toUpperCase();

const avatarColors = index => {
  const palettes = [
    ["#3972f6", "#74a1ff"],
    ["#7b5cf0", "#aa91ff"],
    ["#18a679", "#5cd1ad"],
    ["#ef7d45", "#f6b064"],
    ["#d95d8c", "#ed91b2"],
    ["#248da6", "#5ec3d4"]
  ];
  return palettes[index % palettes.length];
};

const statusClass = status => status.toLowerCase().replace(/\s+/g, "-");

function updateMetrics() {
  document.querySelector("#week-label").textContent =
    `${formatDate(dashboard.weekStart)} — ${formatDate(dashboard.weekEnd)}`;
  document.querySelector("#metric-engineers").textContent = dashboard.summary.engineerCount;
  document.querySelector("#metric-active-engineers").textContent = `${dashboard.summary.activeEngineerCount} con proyectos activos`;
  document.querySelector("#metric-projects").textContent = dashboard.summary.projectCount;
  document.querySelector("#metric-active-tasks").textContent =
    `${dashboard.summary.activeTaskCount} tareas vinculadas · ${dashboard.summary.completedProjectCount} completados`;
  document.querySelector("#metric-tasks").textContent = dashboard.summary.taskCount;
  document.querySelector("#metric-completed").textContent = `${dashboard.summary.completedCount} completadas`;
  document.querySelector("#metric-progress").textContent = `${dashboard.summary.progress}%`;
  document.querySelector("#metric-portfolio-progress").textContent = `${dashboard.summary.portfolioAverageProgress}%`;
  document.querySelector("#metric-portfolio-progress-detail").textContent =
    `${dashboard.summary.projectCount} proyectos vigentes · ${dashboard.summary.closedProjectCount} ocultos`;
  document.querySelector("#updated-label").textContent =
    `Actualizado ${new Intl.DateTimeFormat("es-SV", { dateStyle: "medium", timeStyle: "short" }).format(new Date(dashboard.generatedAt))}`;
}

function filteredEngineers() {
  const term = state.search.trim().toLocaleLowerCase("es");
  return dashboard.engineers.filter(engineer => {
    const projectNames = engineer.activeProjects.map(project => project.name);
    const searchable = [engineer.name, engineer.email, ...projectNames]
      .join(" ")
      .toLocaleLowerCase("es");
    const matchesSearch = !term || searchable.includes(term);
    const matchesFilter =
      state.filter === "all" ||
      (state.filter === "weekly" && engineer.taskCount > 0) ||
      (state.filter === "no-weekly" && engineer.taskCount === 0);
    return matchesSearch && matchesFilter;
  });
}

function engineerCard(engineer, index) {
  const [colorA, colorB] = avatarColors(index);
  const activeProjects = engineer.activeProjects || [];
  const projectPills = activeProjects
    .slice(0, 3)
    .map(project => `<span class="project-pill" title="${escapeHtml(project.name)} · ${project.activeTaskCount} tareas activas">${escapeHtml(project.name)}</span>`)
    .join("");
  const extra = activeProjects.length > 3
    ? `<span class="project-pill">+${activeProjects.length - 3}</span>`
    : "";

  return `
    <article class="engineer-card">
      <div class="engineer-header">
        <div class="avatar" style="--avatar-a:${colorA};--avatar-b:${colorB}">${escapeHtml(initials(engineer.name))}</div>
        <div class="engineer-name">
          <h3 title="${escapeHtml(engineer.name)}">${escapeHtml(engineer.name)}</h3>
          <p title="${escapeHtml(engineer.email)}">${escapeHtml(engineer.email)}</p>
        </div>
        <span class="progress-value">${engineer.progress}%</span>
      </div>
      <div class="progress-track" aria-label="${engineer.progress}% completado">
        <div class="progress-bar" style="width:${engineer.progress}%"></div>
      </div>
      <div class="card-stats">
        <div class="card-stat"><strong>${engineer.projectCount}</strong><span>Proyectos Loop</span></div>
        <div class="card-stat"><strong>${engineer.activeTaskCount}</strong><span>Tareas activas</span></div>
        <div class="card-stat"><strong>${engineer.taskCount}</strong><span>Tareas semana</span></div>
        <div class="card-stat"><strong>${engineer.completedCount}</strong><span>Completadas</span></div>
      </div>
      <div class="project-pills">${projectPills}${extra}</div>
      <button class="details-button" type="button" data-engineer="${escapeHtml(engineer.email)}">Ver proyectos activos y sprint semanal</button>
    </article>`;
}

function renderEngineers() {
  const engineers = filteredEngineers();
  const grid = document.querySelector("#engineer-grid");
  grid.innerHTML = engineers.map(engineerCard).join("");
  document.querySelector("#result-count").textContent = `${engineers.length} de ${dashboard.engineers.length} ingenieros`;
  document.querySelector("#empty-state").hidden = engineers.length !== 0;
  grid.hidden = engineers.length === 0;

  grid.querySelectorAll("[data-engineer]").forEach(button => {
    button.addEventListener("click", () => openEngineer(button.dataset.engineer));
  });
}

function renderProjects() {
  const table = document.querySelector("#project-table");
  table.innerHTML = dashboard.projects.map(project => `
    <tr>
      <td>
        <strong>${escapeHtml(project.client)}</strong>
        <small class="project-scope">${escapeHtml(project.scope)}</small>
      </td>
      <td><span class="portfolio-status ${statusClass(project.portfolioStatus)}">${escapeHtml(project.portfolioStatus)}</span></td>
      <td>
        <div class="portfolio-progress">
          <div class="progress-track"><div class="progress-bar" style="width:${project.portfolioProgress}%"></div></div>
          <strong>${project.portfolioProgress}%</strong>
        </div>
      </td>
      <td>${project.engineerCount}</td>
      <td>${project.activeTaskCount}</td>
      <td>${project.taskCount}</td>
      <td>${project.completedCount}</td>
      <td>
        <div class="table-progress">
          <div class="progress-track"><div class="progress-bar" style="width:${project.progress}%"></div></div>
          <strong>${project.progress}%</strong>
        </div>
      </td>
    </tr>`).join("");
}

function renderCompletedProjects() {
  const absentProjects = dashboard.completedAdoProjects || [];
  const closedProjects = dashboard.closedPortfolioProjects || [];
  const total = absentProjects.length + closedProjects.length;
  document.querySelector("#completed-project-count").textContent = `${total} proyectos ocultos`;
  document.querySelector("#closed-portfolio-list").innerHTML = closedProjects.length
    ? closedProjects.map(project => `<span>${escapeHtml(project)}</span>`).join("")
    : `<span class="completed-empty">Ninguno</span>`;
  document.querySelector("#completed-project-list").innerHTML = absentProjects.length
    ? absentProjects.map(project => `<span>${escapeHtml(project)}</span>`).join("")
    : `<span class="completed-empty">Ninguno</span>`;
}

function renderAllProjectTasks() {
  const grouped = new Map();
  dashboard.engineers.forEach(engineer => {
    engineer.projects.forEach(project => {
      if (!grouped.has(project.name)) grouped.set(project.name, []);
      project.sprints.forEach(sprint => {
        const existingSprint = grouped.get(project.name).find(item => item.name === sprint.name);
        if (existingSprint) {
          existingSprint.tasks.push(...sprint.tasks.map(task => ({ ...task, engineer: engineer.name })));
        } else {
          grouped.get(project.name).push({
            name: sprint.name,
            start: sprint.start,
            finish: sprint.finish,
            tasks: sprint.tasks.map(task => ({ ...task, engineer: engineer.name }))
          });
        }
      });
    });
  });

  const taskTerm = state.taskSearch.trim().toLocaleLowerCase("es");
  const projects = [...grouped.entries()]
    .filter(([name]) => !state.taskProject || name === state.taskProject)
    .map(([name, sprints]) => {
      const filteredSprints = sprints
      .map(sprint => ({
        ...sprint,
        tasks: sprint.tasks.filter(task => {
          const searchable = [task.title, task.engineer, name, sprint.name]
            .join(" ")
            .toLocaleLowerCase("es");
          const matchesTerm = !taskTerm || searchable.includes(taskTerm);
          const matchesStatus =
            !state.taskStatus ||
            (state.taskStatus === "done" && task.isCompleted) ||
            (state.taskStatus === "open" && !task.isCompleted);
          return matchesTerm && matchesStatus;
        })
      }))
      .filter(sprint => sprint.tasks.length > 0)
      .sort((a, b) => a.start.localeCompare(b.start) || a.name.localeCompare(b.name));

      return {
        name,
        sprints: filteredSprints,
        tasks: filteredSprints.reduce((total, sprint) => total + sprint.tasks.length, 0)
      };
    })
    .filter(project => project.tasks > 0 || project.name === state.taskProject)
    .sort((a, b) => b.tasks - a.tasks);
  if (state.taskProject && !projects.some(project => project.name === state.taskProject)) {
    projects.push({ name: state.taskProject, sprints: [], tasks: 0 });
  }

  const withoutWeeklySprint = dashboard.projectsWithoutWeeklySprint?.length || 0;
  const allWeeklyTasks = dashboard.summary.taskCount;
  const visibleTasks = projects.reduce((total, project) => total + project.tasks, 0);
  document.querySelector("#task-count-label").textContent =
    `${visibleTasks} de ${allWeeklyTasks} tareas · ${projects.length} proyectos visibles`;
  document.querySelector("#task-view-summary").innerHTML = `
    <span><strong>${visibleTasks}</strong> tareas visibles</span>
    <span><strong>${projects.length}</strong> proyectos</span>
    <span><strong>${state.taskProject ? "Proyecto seleccionado" : withoutWeeklySprint}</strong> ${state.taskProject ? " · solo se muestra la selección" : "activos sin sprint fechado"}</span>`;
  document.querySelector("#project-task-breakdown").innerHTML = projects.map((project, index) => `
    <details class="project-task-card" ${index === 0 ? "open" : ""}>
      <summary class="project-task-summary">
        <div class="project-task-name">
          <h3>${escapeHtml(project.name)}</h3>
          <p>${project.sprints.length} sprint${project.sprints.length === 1 ? "" : "s"} en el periodo</p>
        </div>
        <div class="project-task-summary-meta">
          <span class="project-task-total">${project.tasks} tareas</span>
          <span class="project-task-chevron">›</span>
        </div>
      </summary>
      ${project.sprints.length
    ? project.sprints.map(sprint => `
        <div class="sprint-block">
          <div class="sprint-heading">
            <strong>${escapeHtml(sprint.name)} · ${formatDate(sprint.start, true)}–${formatDate(sprint.finish, true)}</strong>
            <span>${sprint.tasks.length} tarea${sprint.tasks.length === 1 ? "" : "s"}</span>
          </div>
          <table class="project-task-table">
            <thead><tr><th>Tarea</th><th>Ingeniero</th><th>Estado</th></tr></thead>
            <tbody>
              ${sprint.tasks.sort((a, b) => a.title.localeCompare(b.title)).map(task => `
                <tr>
                  <td><a class="task-link" href="${escapeHtml(task.url)}" target="_blank" rel="noopener">${escapeHtml(task.title)}</a></td>
                  <td class="task-engineer">${escapeHtml(task.engineer)}</td>
                  <td><span class="task-status ${task.isCompleted ? "done" : ""}">${escapeHtml(task.state)}</span></td>
                </tr>`).join("")}
            </tbody>
          </table>
        </div>`).join("")
    : `<div class="project-no-tasks">No hay tareas que coincidan con los filtros para este proyecto en el sprint seleccionado.</div>`}
    </details>    `).join("") || `
      <div class="empty-state compact">
        <span>⌕</span>
        <h3>No hay tareas con estos filtros</h3>
        <p>Prueba con otro texto, proyecto o estado.</p>
      </div>`;

    const projectFilter = document.querySelector("#task-project-filter");
    if (!projectFilter.dataset.ready) {
      projectFilter.innerHTML += dashboard.projects
        .map(project => `<option value="${escapeHtml(project.name)}">${escapeHtml(project.name)}</option>`)
        .join("");
      projectFilter.dataset.ready = "true";
    }
    projectFilter.value = state.taskProject;
    document.querySelector("#task-status-filter").value = state.taskStatus;
}

function openEngineer(email) {
  const engineer = dashboard.engineers.find(item => item.email === email);
  if (!engineer) return;

  document.querySelector("#dialog-engineer").textContent =
    `${engineer.projectCount} proyectos activos · ${engineer.activeTaskCount} tareas activas · ${engineer.taskCount} tareas esta semana`;
  document.querySelector("#dialog-title").textContent = engineer.name;

  const activeProjectContent = engineer.activeProjects.length
    ? `<section class="project-block">
        <div class="project-title"><h3>Proyectos activos</h3><span>${engineer.activeTaskCount} tareas abiertas</span></div>
        <div class="active-project-list">
          ${engineer.activeProjects.map(project => `
            <div class="active-project-row">
              <span>
                ${escapeHtml(project.name)}
                <small>${escapeHtml(project.portfolioStatus)} · ${project.portfolioProgress}% Loop</small>
              </span>
              <strong>${project.activeTaskCount} ADO</strong>
            </div>`).join("")}
        </div>
      </section>`
    : `<div class="empty-state compact"><h3>Sin proyectos activos</h3></div>`;

  const weeklyContent = engineer.projects.length
    ? engineer.projects.map(project => `
        <section class="project-block">
          <div class="project-title">
            <h3>${escapeHtml(project.name)}</h3>
            <span>${project.completedCount}/${project.taskCount} completadas</span>
          </div>
          ${project.sprints.map(sprint => `
            <p class="sprint-label">${escapeHtml(sprint.name)} · ${formatDate(sprint.start, true)}–${formatDate(sprint.finish, true)}</p>
            <div class="task-list">
              ${sprint.tasks.map(task => `
                <div class="task-row">
                  <span class="state-dot ${task.isCompleted ? "done" : ""}"></span>
                  <a href="${escapeHtml(task.url)}" target="_blank" rel="noopener">${escapeHtml(task.title)}</a>
                  <span class="task-state">${escapeHtml(task.state)}</span>
                </div>`).join("")}
            </div>`).join("")}
        </section>`).join("")
    : `<div class="empty-state compact">
        <h3>Sin tareas en un sprint fechado esta semana</h3>
        <p>El ingeniero permanece visible porque el inventario de proyectos activos es independiente del sprint semanal.</p>
      </div>`;

  document.querySelector("#dialog-content").innerHTML =
    `${activeProjectContent}<div class="dialog-section-label">Sprint del 12 al 16 de octubre</div>${weeklyContent}`;

  document.querySelector("#task-dialog").showModal();
}

document.querySelector("#search-input").addEventListener("input", event => {
  state.search = event.target.value;
  renderEngineers();
});

document.querySelectorAll("[data-filter]").forEach(button => {
  button.addEventListener("click", () => {
    document.querySelectorAll("[data-filter]").forEach(item => item.classList.remove("active"));
    button.classList.add("active");
    state.filter = button.dataset.filter;
    renderEngineers();
  });
});

document.querySelector("#reload-button").addEventListener("click", () => window.location.reload());
document.querySelector("#dialog-close").addEventListener("click", () => document.querySelector("#task-dialog").close());
document.querySelector("#task-dialog").addEventListener("click", event => {
  if (event.target === event.currentTarget) event.currentTarget.close();
});

document.querySelector("#task-search-input").addEventListener("input", event => {
  state.taskSearch = event.target.value;
  renderAllProjectTasks();
});
document.querySelector("#task-project-filter").addEventListener("change", event => {
  state.taskProject = event.target.value;
  renderAllProjectTasks();
});
document.querySelector("#task-status-filter").addEventListener("change", event => {
  state.taskStatus = event.target.value;
  renderAllProjectTasks();
});

updateMetrics();
renderEngineers();
renderProjects();
renderAllProjectTasks();
renderCompletedProjects();

const AUTO_REFRESH_CHECK_SECONDS = 60;
const autoRefreshCheckbox = document.querySelector("#auto-refresh-checkbox");
const nextRefreshLabel = document.querySelector("#next-refresh-label");
let secondsUntilCheck = AUTO_REFRESH_CHECK_SECONDS;
let autoRefreshFailures = 0;

async function checkForDataUpdates() {
  try {
    const response = await fetch(`data.js?_=${Date.now()}`, { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const text = await response.text();
    const match = text.match(/"generatedAt"\s*:\s*"([^"]+)"/);
    autoRefreshFailures = 0;
    if (match && match[1] && match[1] !== dashboard.generatedAt) {
      window.location.reload();
    }
  } catch (error) {
    autoRefreshFailures += 1;
  }
}

function tickAutoRefresh() {
  if (!autoRefreshCheckbox.checked) {
    nextRefreshLabel.textContent = "Auto-refresco desactivado";
    return;
  }
  secondsUntilCheck -= 1;
  if (secondsUntilCheck <= 0) {
    secondsUntilCheck = AUTO_REFRESH_CHECK_SECONDS;
    checkForDataUpdates();
  }
  const statusSuffix = autoRefreshFailures > 0 ? " · sin conexión con data.js" : "";
  nextRefreshLabel.textContent = `Próxima comprobación en ${secondsUntilCheck}s${statusSuffix}`;
}

autoRefreshCheckbox.addEventListener("change", () => {
  secondsUntilCheck = AUTO_REFRESH_CHECK_SECONDS;
});

setInterval(tickAutoRefresh, 1000);
tickAutoRefresh();
