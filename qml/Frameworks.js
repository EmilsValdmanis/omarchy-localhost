.import "Paths.js" as Paths

function commandTokens(command) {
  var matches = String(command || "").match(/(?:[^\s"']+|"[^"\n]*"|'[^'\n]*')+/g) || []
  return matches.map(function(token) { return token.replace(/^["']|["']$/g, "") })
}

var FRAMEWORK_RULES = [
  ["docusaurus", "Docusaurus", "docusaurus"],
  ["react-email", "React Email", "react"],
  ["func start", "Azure Functions", "azure"],
  ["wrangler dev", "Cloudflare Workers", "cloudflare"],
  ["firebase emulators", "Firebase", "firebase"],
  ["supabase start", "Supabase", "supabase"],
  ["prisma studio", "Prisma Studio", "prisma"],
  ["graphql-yoga", "GraphQL Yoga", "graphql"],
  ["apollo-server", "Apollo Server", "graphql"],
  ["vue-cli-service", "Vue", "vue"],
  ["ng serve", "Angular", "angular"],
  ["solid-start", "SolidStart", "solid"],
  ["qwik", "Qwik", "qwik"],
  ["remix", "Remix", "remix"],
  ["gatsby", "Gatsby", "gatsby"],
  ["ember serve", "Ember", "ember"],
  ["eleventy", "Eleventy", "eleventy"],
  ["electron", "Electron", "electron"],
  ["tauri dev", "Tauri", "tauri"],
  ["expo start", "Expo", "expo"],
  ["webpack serve", "Webpack", "webpack"],
  ["webpack-dev-server", "Webpack", "webpack"],
  ["parcel serve", "Parcel", "parcel"],
  ["hugo server", "Hugo", "hugo"],
  ["jekyll serve", "Jekyll", "jekyll"],
  ["next", "Next.js", "next"],
  ["next-server", "Next.js", "next"],
  ["nuxt", "Nuxt", "nuxt"],
  ["svelte", "Svelte", "svelte"],
  ["astro", "Astro", "astro"],
  ["vite", "Vite", "vite", true],
  ["storybook", "Storybook", "storybook"],
  ["nest start", "NestJS", "nestjs"],
  ["nest.js", "NestJS", "nestjs"],
  ["adonis serve", "AdonisJS", "adonis"],
  ["node ace serve", "AdonisJS", "adonis"],
  ["express", "Express", "express"],
  ["bun", "Bun", "bun", true],
  ["deno", "Deno", "deno", true],
  ["streamlit run", "Streamlit", "streamlit"],
  ["jupyter lab", "Jupyter", "jupyter"],
  ["jupyter notebook", "Jupyter", "jupyter"],
  ["gradio", "Gradio", "gradio"],
  ["uvicorn", "Uvicorn", "python", true],
  ["fastapi", "FastAPI", "fastapi"],
  ["flask", "Flask", "flask"],
  ["manage.py runserver", "Django", "django"],
  ["gunicorn", "Python / Gunicorn", "python", true],
  ["hypercorn", "Python / Hypercorn", "python", true],
  ["rails server", "Rails", "rails"],
  ["rails s", "Rails", "rails"],
  ["sinatra", "Sinatra", "sinatra"],
  ["php artisan serve", "Laravel", "laravel"],
  ["symfony server", "Symfony", "symfony"],
  ["wp-env start", "WordPress", "wordpress"],
  ["php -s", "PHP", "php"],
  ["mix phx.server", "Phoenix", "phoenix"],
  ["mix run", "Elixir", "elixir"],
  ["http.server", "Python HTTP", "python"],
  ["trunk serve", "Rust / Trunk", "rust"],
  ["leptos", "Leptos", "rust"],
  ["cargo run", "Rust", "rust"],
  ["go run", "Go", "go"],
  ["air", "Go / Air", "go"],
  ["spring-boot", "Spring Boot", "spring"],
  ["bootrun", "Spring Boot", "spring"],
  ["quarkus:dev", "Quarkus", "quarkus"],
  ["quarkus dev", "Quarkus", "quarkus"],
  ["dotnet watch", ".NET", "dotnet"],
  ["dotnet run", ".NET", "dotnet"],
  ["grafana server", "Grafana", "grafana"],
  ["prometheus", "Prometheus", "prometheus"]
]

var PROJECT_FRAMEWORKS = [
  ["@tanstack/react-start", "TanStack Start", "tanstack"],
  ["@tanstack/solid-start", "TanStack Start", "tanstack"],
  ["@docusaurus/core", "Docusaurus", "docusaurus"],
  ["@sveltejs/kit", "SvelteKit", "svelte"], ["@astrojs/core", "Astro", "astro"],
  ["astro", "Astro", "astro"], ["next", "Next.js", "next"], ["nuxt", "Nuxt", "nuxt"],
  ["@nestjs/core", "NestJS", "nestjs"], ["@remix-run/react", "Remix", "remix"],
  ["@solidjs/start", "SolidStart", "solid"], ["@builder.io/qwik", "Qwik", "qwik"],
  ["@angular/core", "Angular", "angular"], ["hono", "Hono", "hono"],
  ["fastify", "Fastify", "fastify"], ["express", "Express", "express"],
  ["svelte", "Svelte", "svelte"], ["solid-js", "SolidJS", "solid"],
  ["react", "React", "react"], ["vue", "Vue", "vue"], ["vite", "Vite", "vite"],
  ["fastapi", "FastAPI", "fastapi"], ["django", "Django", "django"], ["flask", "Flask", "flask"]
]

function frameworkFor(command, project, argv) {
  var args = argv && argv.length ? argv : commandTokens(command)
  var tokens = args.map(function(arg, index) {
    // Next rewrites argv[0] through process.title, including its version suffix.
    if (index === 0 && /^next-server \(v[^\s)]+\)$/.test(arg)) return "next-server"
    var previous = String(args[index - 1] || "")
    if (/^--?[^=]+$/.test(previous) && ["-m", "--", "--watch"].indexOf(previous) === -1) return ""
    return (arg.charAt(0) === "-" ? arg : Paths.basename(arg)).toLowerCase().replace(/\.(?:m?js|cjs)$/, "")
  })
  var result = null
  var generic = true
  for (var i = 0; i < FRAMEWORK_RULES.length && !result; i++) {
    var rule = FRAMEWORK_RULES[i]
    var parts = rule[0].replace(/\.js$/, "").split(" ")
    for (var j = 0; j <= tokens.length - parts.length; j++) {
      if (parts.every(function(part, offset) { return tokens[j + offset] === part })) {
        result = { name: rule[1], id: rule[2] }
        generic = rule[3] === true
        break
      }
    }
  }
  if (generic) {
    var dependencies = project && Array.isArray(project.dependencies) ? project.dependencies : []
    var python = tokens.some(function(token) { return /^(?:python[\d.]*|uvicorn|gunicorn|hypercorn|flask|django)$/.test(token) })
    var javascript = tokens.some(function(token) { return /^(?:node|nodejs|bun|deno|vite|tsx|ts-node|npm|pnpm|yarn)$/.test(token) })
    for (var k = 0; k < PROJECT_FRAMEWORKS.length; k++) {
      var candidate = PROJECT_FRAMEWORKS[k]
      var pythonFramework = ["fastapi", "django", "flask"].indexOf(candidate[2]) !== -1
      if ((pythonFramework ? !python : !javascript) || dependencies.indexOf(candidate[0]) === -1) continue
      if (result && result.id === "vite" && ["next", "nuxt", "nestjs", "express", "fastify", "hono"].indexOf(candidate[2]) !== -1) continue
      return { name: candidate[1], id: candidate[2] }
    }
  }
  if (result) return result
  if (tokens.indexOf("node") !== -1 || tokens.indexOf("nodejs") !== -1 || tokens.indexOf("tsx") !== -1)
    return { name: "Node.js", id: "node" }
  return { name: "Dev server", id: "server" }
}

var FRAMEWORK_ICONS = {
  tanstack: "󱁕", docusaurus: "\uf15c",
  hono: "\uf06d", fastify: "\uf0e7",
  next: "", vite: "", svelte: "", astro: "", nuxt: "",
  angular: "", react: "", vue: "", solid: "", qwik: "",
  remix: "", gatsby: "", ember: "", eleventy: "", expo: "",
  electron: "", tauri: "", webpack: "", storybook: "",
  cloudflare: "", azure: "", firebase: "", supabase: "",
  graphql: "", prisma: "", bun: "", deno: "", node: "", docker: "",
  express: "", nestjs: "", adonis: "", python: "",
  django: "", fastapi: "", flask: "", streamlit: "",
  jupyter: "", ruby: "", rails: "", php: "", laravel: "",
  symfony: "", wordpress: "", elixir: "", phoenix: "",
  rust: "", go: "", java: "", spring: "", quarkus: "",
  dotnet: "", grafana: "", prometheus: ""
}

function frameworkIcon(frameworkId) {
  return FRAMEWORK_ICONS[frameworkId] || ""
}
