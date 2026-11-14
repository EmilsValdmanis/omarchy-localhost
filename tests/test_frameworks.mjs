import assert from "node:assert/strict"
import test from "node:test"
import { loadQmlJs, plain } from "./support/qml_js.mjs"

const Frameworks = loadQmlJs("Frameworks.js")

test("detects common localhost frameworks", () => {
  const cases = [
    ["node node_modules/.bin/next dev", "next"],
    ["node node_modules/.bin/vue-cli-service serve", "vue"],
    ["bun run dev", "bun"],
    ["python -m uvicorn app:app", "python"],
    ["python manage.py runserver 8000", "django"],
    ["php artisan serve", "laravel"],
    ["mix phx.server", "phoenix"],
    ["./gradlew bootRun", "spring"],
    ["dotnet watch run", "dotnet"],
    ["wrangler dev", "cloudflare"],
  ]

  for (const [command, id] of cases)
    assert.equal(Frameworks.frameworkFor(command).id, id, command)
})

test("framework detection ignores incidental directory names and option values", () => {
  for (const command of [
    "node /work/next-project/server.js", "node /work/chair/index.js",
    "node app.js --cert=/tmp/next", "node app.js --directory next",
  ]) assert.equal(Frameworks.frameworkFor(command).id, "node", command)
  assert.equal(Frameworks.frameworkFor("custom daemon --port 4555").id, "server")
})

test("nearest project dependencies refine generic runtimes without overriding explicit frameworks", () => {
  const cases = [
    ["vite", ["@sveltejs/kit", "svelte", "vite"], "SvelteKit"],
    ["vite", ["react", "vite", "next"], "React"],
    ["node dist/main.js", ["@nestjs/core"], "NestJS"],
    ["bun src/index.ts", ["hono"], "Hono"],
    ["next dev", ["react", "express"], "Next.js"],
    ["python -m uvicorn app:app", ["fastapi", "uvicorn"], "FastAPI"],
    ["python -m uvicorn app:app", ["react"], "Uvicorn"],
    ["python -m http.server 8000", ["fastapi"], "Python HTTP"],
  ]
  for (const [command, dependencies, name] of cases)
    assert.equal(Frameworks.frameworkFor(command, { dependencies }).name, name, command)
})

test("recognizes the Next.js process title read as a single argv entry", () => {
  const title = "next-server (v16.0.0)"
  assert.equal(Frameworks.frameworkFor(title, {}, [title]).id, "next")
  assert.equal(Frameworks.frameworkFor("node app.js", {}, ["node", "app.js", "--label", title]).id, "node")
})

test("TanStack Start and Docusaurus dependencies take precedence over React and Vite", () => {
  for (const command of ["vite --host", "node /work/app/node_modules/vite/bin/vite.js", "bun run dev"]) {
    for (const adapter of ["@tanstack/react-start", "@tanstack/solid-start"]) {
      assert.deepEqual(plain(Frameworks.frameworkFor(command, { dependencies: ["react", "solid-js", "vite", adapter] })),
        { name: "TanStack Start", id: "tanstack" })
    }
    assert.equal(Frameworks.frameworkFor(command, { dependencies: ["react", "@docusaurus/core"] }).id, "docusaurus")
  }
  assert.equal(Frameworks.frameworkFor("vite", { dependencies: ["react", "@tanstack/react-query", "@tanstack/react-router"] }).id, "react")
  assert.equal(Frameworks.frameworkFor("next dev", { dependencies: ["react", "@tanstack/react-start"] }).id, "next")
  assert.ok(Frameworks.frameworkIcon("tanstack"))
  assert.ok(Frameworks.frameworkIcon("docusaurus"))
})

test("keeps unknown servers on the letter fallback path", () => {
  assert.deepEqual(plain(Frameworks.frameworkFor("custom-local-server --port 4567")), {
    name: "Dev server",
    id: "server",
  })
})
