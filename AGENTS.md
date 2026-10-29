# Native GAL local workspace

Read docs/LOCAL_WINDOWS.md, docs/CHAPTER_ONE_PLAN.md and
docs/GAL_INTERFACE_FRAMEWORK.md before changing design or presentation.
This package contains the native browser game. Historical Godot/3D references
in the design documents describe other builds, absent from this package.

- Preserve approved watercolor manga art, proportional portraits, indigo hero,
  green Huai, and the hero's gaze toward the player.
- All UI text uses the bundled LXGW WenKai TC Medium, including buttons,
  cards, numbers and tooltips. Do not replace it with system Ming fonts.
- web/ is the active interface; chapter/{catalog,content,model,card_art}.js
  are its shared source. Preserve gameplay and independent save namespaces.
- Use python tools/dev_server.py (Windows: Start-Local.cmd), port 8091.
  CSS refreshes live; other changes offer a reload button. Keep the same origin.
- After each visual step, inspect actual browser screenshots at 1440x900 and
  960x600 and operate the affected controls. Check overlapping frames, text
  clipping, illustration boundaries and focus states. Fix defects before delivery.
- For model changes run node tests/test_ferry.cjs and node tests/test_card_art.cjs.
  Preview needs Python only; Node and Playwright are optional verification tools.
- Update the chapter plan when a milestone or design decision changes.
- Preserve existing user changes. Do not push to GitHub or publish without user
  authorization. The 2026-10-29 request authorizes the current push-to-play web
  setup on gh-pages. See docs/WEB_PREVIEW.md for deployment and verification.
- gh-pages is the active native web source and GitHub Pages publishing branch.
  Use relative URLs so the /Game-develop-rpg-wusha/ project path works.
- battle/ is the independent basic-card v1 lab. Its pure model and save namespace
  are separate from the chapter's current combat. Do not mix their save formats.
  Read docs/BASIC_BATTLE_V1.md; run node --test tests/test_basic_battle.mjs
  tests/test_basic_card_art.mjs and python tools/test_basic_battle_web.py.
- New basic cards use individual actor/technique WebP files under assets/cards/.
  Accepted full-size PNGs and QA records are under art-source/basic-v1/.
  Do not regenerate atlases or borrow one actor's face for another actor.
