module Main where

import Prelude

import Effect (Effect)
import Site.File (ensureDirectory, writeTextFile)
import Site.Html (Node, attr, cls, el, html, link, meta, renderDocument, script, text, voidEl)

main :: Effect Unit
main = do
  ensureDirectory "../out/site"
  writeTextFile "../out/site/index.html" (renderDocument page)
  writeTextFile "../out/site/site.css" css
  writeTextFile "../out/site/robots.txt" "User-agent: *\nAllow: /\n"

page :: Node
page =
  html [ attr "lang" "en" ]
    [ el "head" []
        [ meta [ attr "charset" "utf-8" ]
        , meta [ attr "name" "viewport", attr "content" "width=device-width, initial-scale=1" ]
        , meta [ attr "name" "description", attr "content" "Silt is an experimental S-expression systems language with a small CoC-style dependent core and freestanding target evidence." ]
        , meta [ attr "property" "og:title", attr "content" "Silt" ]
        , meta [ attr "property" "og:description", attr "content" "Low-level facts, lifted into typed values." ]
        , meta [ attr "property" "og:type", attr "content" "website" ]
        , meta [ attr "name" "theme-color", attr "content" "#f4efe6" ]
        , link [ attr "rel" "stylesheet", attr "href" "site.css" ]
        , link [ attr "rel" "icon", attr "href" "favicon.svg", attr "type" "image/svg+xml" ]
        , el "title" [] [ text "Silt" ]
        ]
    , el "body" []
        [ el "header" [ cls "topbar" ]
            [ el "a" [ cls "brand", attr "href" "#" ] [ text "Silt" ]
            , el "nav" [ cls "nav", attr "aria-label" "Primary" ]
                [ navLink "Book" "book/"
                , navLink "Status" "#status"
                , navLink "Verification" "#verification"
                , navLink "GitHub" "https://github.com/M-simplifier/silt"
                ]
            ]
        , el "main" []
            [ hero
            , section "status" "Current Boundary"
                [ el "p" [ cls "section-lede" ]
                    [ text "Silt is public as a research compiler with executable evidence. The long-term direction is large; the public contract is smaller and sharper." ]
                , el "div" [ cls "boundary-grid" ]
                    [ fact "Checks" "S-expressions, Pi types, quantities, effect states, layout values, static objects."
                    , fact "Emits" "Freestanding C for the supported first-order low-level subset."
                    , fact "Links" "x86_64 ELF and Limine artifacts through checked target and boot contracts."
                    , fact "Observes" "QEMU smoke markers for serial paths, panic paths, boot facts, and allocator handoff."
                    ]
                ]
            , section "program" "One Program, Several Truths"
                [ el "div" [ cls "split" ]
                    [ el "div" [ cls "prose" ]
                        [ el "p" []
                            [ text "A Silt low-level program is not only an expression. It is also a representation promise, a generated artifact, and an executable observation. The language is designed so those layers can be read together." ]
                        , el "p" []
                            [ text "The allocator handoff example does not pretend to be a general allocator. It records boot facts, frame candidates, reservation state, a free-list seed, alloc/free traces, API-shaped results, a semantics witness, a lease, and a final handoff value." ]
                        ]
                    , codeBlock allocatorSnippet
                    ]
                ]
            , section "book" "Learn Silt"
                [ el "div" [ cls "learn-band" ]
                    [ el "div" [ cls "prose" ]
                        [ el "p" []
                            [ text "The Silt Book is written as a first reading path, not as a project diary. It starts with ordinary declarations, then moves through dependent functions, quantities, memory layout, freestanding targets, Limine, and the allocator handoff case study." ]
                        , el "a" [ cls "button primary", attr "href" "book/" ] [ text "Open the Book" ]
                        ]
                    , el "ol" [ cls "reading-path" ]
                        [ pathItem "Surface" "S-expressions, declarations, normalization"
                        , pathItem "Core" "Pi, quantities, data, effect states"
                        , pathItem "Machine" "Pointers, layouts, static storage, ABI"
                        , pathItem "Boot" "Limine, serial output, typed boot facts"
                        , pathItem "Handoff" "Frame seed, alloc/free trace, final witness"
                        ]
                    ]
                ]
            , section "verification" "Evidence Trail"
                [ el "p" [ cls "section-lede" ]
                    [ text "Silt's claims are tied to commands. Each command exercises a different boundary: checker, normalizer, backend, linker, boot protocol, or verifier-observed QEMU smoke output." ]
                , codeBlock verificationSnippet
                ]
            , section "limits" "Not Yet"
                [ el "ul" [ cls "limit-list" ]
                    [ limit "not a production compiler"
                    , limit "not self-hosted"
                    , limit "no macro system yet"
                    , limit "no module system yet"
                    , limit "no general allocator or kernel"
                    , limit "no full formal proof of the compiler"
                    ]
                , el "p" [ cls "small-note" ]
                    [ text "The point is not to make the vision smaller. The point is to make every visible claim earn its place." ]
                ]
            ]
        , el "footer" [ cls "footer" ]
            [ el "span" [] [ text "MIT Licensed" ]
            , el "a" [ attr "href" "https://github.com/M-simplifier/silt/blob/main/CONTRIBUTING.md" ] [ text "Contribution policy" ]
            , el "a" [ attr "href" "https://github.com/M-simplifier/silt/blob/main/STATUS.md" ] [ text "Status" ]
            ]
        , script [ attr "type" "application/ld+json" ]
            [ text "{\"@context\":\"https://schema.org\",\"@type\":\"SoftwareSourceCode\",\"name\":\"Silt\",\"codeRepository\":\"https://github.com/M-simplifier/silt\",\"programmingLanguage\":\"Haskell\",\"license\":\"https://opensource.org/license/mit\"}" ]
        ]
    ]

hero :: Node
hero =
  el "section" [ cls "hero" ]
    [ el "div" [ cls "hero-copy" ]
        [ el "p" [ cls "eyebrow" ] [ text "Experimental systems language" ]
        , el "h1" [] [ text "Silt" ]
        , el "p" [ cls "statement" ] [ text "Low-level facts, lifted into typed values." ]
        , el "p" [ cls "hero-text" ]
            [ text "A stage0 S-expression language with a small CoC-style dependent core, conservative quantities, explicit effects, and freestanding target evidence." ]
        , el "div" [ cls "actions" ]
            [ el "a" [ cls "button primary", attr "href" "book/" ] [ text "Read the Book" ]
            , el "a" [ cls "button", attr "href" "https://github.com/M-simplifier/silt" ] [ text "View Source" ]
            ]
        , el "p" [ cls "status-line" ]
            [ text "Stage0 today: checker, NbE equality, quantities, layout/memory/ABI seeds, freestanding C/ELF/Limine smoke paths." ]
        ]
    , el "div" [ cls "hero-panel", attr "aria-label" "Silt verification example" ]
        [ codeBlock heroSnippet
        , el "div" [ cls "terminal" ]
            [ el "span" [ cls "prompt" ] [ text "$" ]
            , text " cabal run silt -- norm examples/limine.silt kernel-allocator-handoff-sample-ready"
            , voidEl "br" []
            , el "span" [ cls "ok" ] [ text "=> true" ]
            ]
        ]
    ]

navLink :: String -> String -> Node
navLink label href =
  el "a" [ attr "href" href ] [ text label ]

section :: String -> String -> Array Node -> Node
section sectionId heading children =
  el "section" [ cls "section", attr "id" sectionId ]
    ([ el "h2" [] [ text heading ] ] <> children)

fact :: String -> String -> Node
fact title body =
  el "article" [ cls "fact" ]
    [ el "h3" [] [ text title ]
    , el "p" [] [ text body ]
    ]

pathItem :: String -> String -> Node
pathItem title body =
  el "li" []
    [ el "strong" [] [ text title ]
    , el "span" [] [ text body ]
    ]

limit :: String -> Node
limit value =
  el "li" [] [ text value ]

codeBlock :: String -> Node
codeBlock source =
  el "pre" [ cls "code" ] [ el "code" [] [ text source ] ]

heroSnippet :: String
heroSnippet =
  """(claim kernel-allocator-handoff-sample-ready
  Bool)
(def kernel-allocator-handoff-sample-ready
  (kernel-allocator-handoff-ready
    kernel-allocator-handoff-sample))"""

allocatorSnippet :: String
allocatorSnippet =
  """(layout KernelAllocatorHandoff 96 8
  ((state-ready U64 0)
   (semantics-ready U64 8)
   (lease-ready U64 16)
   (allocated-base U64 24)
   (released-base U64 32)
   ...
   (handoff-ready U64 88)))"""

verificationSnippet :: String
verificationSnippet =
  """cabal test all
cabal run silt -- check examples/limine.silt
cabal run silt -- norm examples/limine.silt kernel-allocator-handoff-sample-ready
scripts/verify-stage0-backend.sh
scripts/verify-freestanding-backend.sh
scripts/verify-x86_64-elf-backend.sh
scripts/verify-limine-bridge.sh
scripts/verify-limine-qemu-nix.sh"""

css :: String
css =
  """
:root {
  color-scheme: light;
  --paper: #f4efe6;
  --ink: #171612;
  --muted: #5f6258;
  --line: #d7d0c2;
  --panel: #fffaf1;
  --panel-strong: #101315;
  --accent: #b73d2f;
  --accent-dark: #87291f;
  --green: #426f5a;
  --blue: #2d5f88;
  --code: #111315;
  --code-text: #f3eadf;
}

* {
  box-sizing: border-box;
}

body {
  width: 100%;
  max-width: 100%;
  margin: 0;
  background: var(--paper);
  color: var(--ink);
  font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  line-height: 1.55;
  overflow-x: hidden;
}

a {
  color: inherit;
}

.topbar {
  position: sticky;
  top: 0;
  z-index: 10;
  display: flex;
  align-items: center;
  justify-content: space-between;
  min-height: 64px;
  padding: 0 40px;
  background: rgba(244, 239, 230, 0.92);
  border-bottom: 1px solid var(--line);
  backdrop-filter: blur(10px);
}

.brand {
  font-weight: 800;
  text-decoration: none;
  letter-spacing: 0;
}

.nav {
  display: flex;
  gap: 24px;
  font-size: 14px;
  color: var(--muted);
}

.nav a {
  text-decoration: none;
}

.nav a:hover {
  color: var(--ink);
}

.hero {
  width: 100%;
  min-width: 0;
  min-height: calc(100vh - 64px);
  display: grid;
  grid-template-columns: minmax(0, 0.95fr) minmax(360px, 0.8fr);
  gap: 48px;
  align-items: center;
  max-width: 1180px;
  margin: 0 auto;
  padding: 64px 40px 44px;
}

.hero > * {
  min-width: 0;
}

.hero-copy {
  max-width: 760px;
  min-width: 0;
}

.eyebrow {
  margin: 0 0 18px;
  color: var(--accent);
  font-size: 13px;
  font-weight: 800;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

h1 {
  margin: 0;
  font-size: clamp(72px, 14vw, 170px);
  line-height: 0.85;
  letter-spacing: 0;
}

.statement {
  margin: 22px 0 0;
  max-width: 780px;
  font-size: clamp(30px, 4.6vw, 64px);
  line-height: 1;
  font-weight: 760;
  letter-spacing: 0;
  overflow-wrap: break-word;
}

.hero-text {
  max-width: 690px;
  margin: 28px 0 0;
  color: #343733;
  font-size: 20px;
  overflow-wrap: break-word;
}

.actions {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  margin-top: 32px;
}

.button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-height: 44px;
  padding: 0 18px;
  border: 1px solid var(--line);
  border-radius: 6px;
  background: var(--panel);
  color: var(--ink);
  font-weight: 760;
  text-decoration: none;
}

.button.primary {
  border-color: var(--accent);
  background: var(--accent);
  color: white;
}

.button:hover {
  transform: translateY(-1px);
}

.status-line {
  max-width: 720px;
  margin: 22px 0 0;
  color: var(--muted);
  font-size: 14px;
}

.hero-panel {
  min-width: 0;
  width: 100%;
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 8px;
  background: #e9dfcf;
  padding: 14px;
  box-shadow: 0 24px 70px rgba(54, 42, 26, 0.16);
}

.code {
  max-width: 100%;
  margin: 0;
  overflow: auto;
  border-radius: 6px;
  background: var(--code);
  color: var(--code-text);
  padding: 22px;
  font: 14px/1.55 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
}

.terminal {
  max-width: 100%;
  margin-top: 12px;
  border-radius: 6px;
  background: #202323;
  color: #efe7dc;
  padding: 16px;
  font: 13px/1.55 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
}

.prompt {
  color: #e0a33d;
}

.ok {
  color: #a7d0a9;
}

.section {
  max-width: 1180px;
  margin: 0 auto;
  padding: 72px 40px;
  border-top: 1px solid var(--line);
}

.section h2 {
  margin: 0 0 20px;
  font-size: clamp(32px, 5vw, 56px);
  line-height: 1;
  letter-spacing: 0;
}

.section-lede {
  max-width: 760px;
  margin: 0 0 28px;
  color: #373936;
  font-size: 20px;
}

.boundary-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 12px;
}

.fact {
  min-height: 180px;
  border: 1px solid var(--line);
  border-radius: 8px;
  background: var(--panel);
  padding: 22px;
}

.fact h3 {
  margin: 0 0 10px;
  font-size: 18px;
}

.fact p {
  margin: 0;
  color: var(--muted);
}

.split,
.learn-band {
  display: grid;
  grid-template-columns: minmax(0, 0.85fr) minmax(360px, 1fr);
  gap: 32px;
  align-items: start;
}

.split > *,
.learn-band > * {
  min-width: 0;
}

.prose p {
  margin: 0 0 18px;
  color: #373936;
  font-size: 19px;
}

.reading-path {
  display: grid;
  gap: 10px;
  margin: 0;
  padding: 0;
  list-style: none;
}

.reading-path li {
  display: grid;
  grid-template-columns: 110px minmax(0, 1fr);
  gap: 18px;
  border-bottom: 1px solid var(--line);
  padding: 14px 0;
}

.reading-path span {
  color: var(--muted);
}

.limit-list {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 10px;
  margin: 28px 0 0;
  padding: 0;
  list-style: none;
}

.limit-list li {
  min-height: 58px;
  display: flex;
  align-items: center;
  border: 1px solid var(--line);
  border-radius: 8px;
  background: var(--panel);
  padding: 12px 16px;
  color: #353833;
}

.small-note {
  max-width: 720px;
  margin: 24px 0 0;
  color: var(--muted);
}

.footer {
  display: flex;
  flex-wrap: wrap;
  gap: 18px;
  justify-content: center;
  border-top: 1px solid var(--line);
  padding: 28px 40px;
  color: var(--muted);
  font-size: 14px;
}

.footer a {
  text-decoration: none;
}

@media (max-width: 900px) {
  .topbar {
    padding: 0 20px;
  }

  .nav {
    gap: 14px;
  }

  .hero {
    min-height: auto;
    grid-template-columns: 1fr;
    padding: 44px 20px 32px;
  }

  .section {
    padding: 52px 20px;
  }

  .boundary-grid,
  .split,
  .learn-band,
  .limit-list {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 540px) {
  .topbar {
    overflow: hidden;
  }

  .nav {
    font-size: 13px;
    gap: 10px;
    max-width: 92px;
    overflow: hidden;
  }

  .nav a:not(:first-child) {
    display: none;
  }

  .hero {
    display: block;
    width: 100vw;
    max-width: 100vw;
    padding-left: 20px;
    padding-right: 20px;
    overflow: hidden;
  }

  .hero-copy,
  .hero-panel {
    width: min(350px, calc(100vw - 40px));
    max-width: min(350px, calc(100vw - 40px));
  }

  .statement,
  .hero-text,
  .status-line {
    width: 100%;
    max-width: 100%;
  }

  .hero-panel .code,
  .hero-panel .terminal {
    overflow-x: hidden;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }

  .reading-path li {
    grid-template-columns: 1fr;
    gap: 4px;
  }

  .code,
  .terminal {
    font-size: 12px;
  }
}
"""
