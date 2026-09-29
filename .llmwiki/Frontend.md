# Frontend

> Scope: the React + Vite client that lived in frontend/ — removed on 2026-09-29; what
> replaced it and where its code can still be read.
> Related: [[FrontendFlutter]] · [[Deployment]] · [[Architecture]]
> Updated: 2026-09-29

## Facts

- **Removed on 2026-09-29 (chore/remove-react-client).** frontend/, its image
  `zapzap-frontend`, its compose service `frontend`, its CI job's steps, its commit-hook gate
  and `scripts/worktree_setup.sh --no-frontend` are gone. The Flutter client is the only
  client: the Android app and the PWA under `/app/` ([[FrontendFlutter]]).
- **Its URLs still answer**: the proxy sends each one a relative 301 to its page in the PWA,
  query string kept — `/` → `/app/` (a 302), `/party/<id>` → `/app/parties/<id>`, `/create-party` →
  `/app/parties/new`, `/account/delete` → `/app/account`, any other path → `/app` + the same
  path ([[Deployment]] § The URLs of the removed React client).
- **Its code** can still be read in the parent of the commit that removed it:
  `c=$(git log -1 --format=%h -- frontend/)^`, then `git show "$c":frontend/src/App.jsx` or
  `git ls-tree -r --name-only "$c" frontend` (`055c288` holds it too).
  The Flutter pages name it "React" where a screen was ported from one of its components.
- The CI job **"Frontend — build"** stays, always skipped, only because `master`'s branch
  protection requires that check name ([[Testing]]).

## Decisions & History

- **Why it went (2026-09-29, user decision).** Every React route had its Flutter one, the
  account page with the account deletion last (#179); React cost a fourth image, vitest and
  a lint gate, and nine backlog entries of its own, for a client the PWA duplicated. Web
  players sign in once more: the PWA stores its token under `flutter.token`, not React's
  `token` (accepted). Redirects rather than a 404 or a copy of the client, because the Play
  listing and `privacy_policy.md` name `/account/delete`, and lobby links were shared.
- Its history — the rewrite from vanilla JS/EJS, Google OAuth, the token on
  `/suscribeupdate` (#94), the turn timer, the account deletion page — is in this page at
  `055c288` (`git show 055c288:.llmwiki/Frontend.md`).
