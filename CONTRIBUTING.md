# Contributing to Edge Core

Thanks for considering a contribution. Edge Core is maintained by
WENET VIETNAM JOINT STOCK COMPANY and developed in the open. This document
covers what you need to know before opening a pull request.

## Licensing of contributions

Edge Core ships under multiple licenses depending on the component:

| Component                   | Path            | License                    |
| --------------------------- | --------------- | -------------------------- |
| Edge Agent                  | `edge_agent/`   | Apache License 2.0         |
| Nexmaker                    | `nexmaker/`     | Apache License 2.0         |
| Edge Admin                  | `edge_admin/`   | Elastic License 2.0 (ELv2) |
| Examples, docs, deploy, bin | other top-level | Apache License 2.0         |

**By submitting a contribution, you agree that your contribution is licensed
under the same license as the component it modifies.** Apache 2.0 contributions
to the agent, nexmaker, examples, docs, and deploy. ELv2 contributions to the
admin. This applies whether you submit a pull request, a patch, a comment with
a code suggestion, or any other form of contribution.

## Developer Certificate of Origin (DCO)

Every commit must be signed off under the
[Developer Certificate of Origin (DCO) v1.1](https://developercertificate.org/).
The DCO is a developer-friendly alternative to a Contributor License Agreement
that confirms you have the right to submit the work you are contributing.

The full DCO text is reproduced at the bottom of this file. Signing off means
you are making the four statements in that text.

### How to sign off

Add a `Signed-off-by` line to every commit:

```
Signed-off-by: Your Name <your.email@example.com>
```

The easiest way is the `-s` flag:

```bash
git commit -s -m "Your commit message"
```

The name and email must match what you use in `git config user.name` and
`git config user.email`. Real name preferred; pseudonymous contributions are
accepted on a case-by-case basis.

If you forget to sign off, amend the commit:

```bash
git commit --amend -s --no-edit
git push --force-with-lease
```

For multiple commits, an interactive rebase with the `signoff` command works.

We may add automated DCO enforcement (e.g. the GitHub DCO app) later. For now
sign-offs are checked manually before merge.

## Pull request flow

Day-to-day development happens on the `develop` branch. `main` tracks released
versions and only receives merges at release time.

1. Fork the repository.
2. Create a topic branch off `develop`:
   `git checkout -b topic/short-description develop`
3. Make your changes. Sign off every commit.
4. Run the relevant quality checks before pushing — see `CLAUDE.md` and the
   per-component instructions in the example READMEs. At minimum:
   - `./bin/run cloud admin precommit` for changes touching `edge_admin/`
   - `./bin/run edge agent precommit` for changes touching `edge_agent/`
5. Open a pull request against `develop` describing what you changed and why.
6. Be ready to discuss feedback. Maintainers may request changes or push small
   fixups directly to your branch.

## What we welcome

- Bug fixes with a clear reproducer
- Documentation improvements
- Compatibility patches for new Linux distros, ARM variants, etc.
- Test coverage improvements
- Performance fixes with measurable before/after numbers

## What we are cautious about

- Large architectural changes without prior discussion. Open an issue first so
  we can agree on the shape before you spend time on it.
- Renaming public APIs, env vars, or directory layouts without strong
  justification — these break downstream users silently.
- Features that significantly overlap with our hosted commercial offering. We
  evaluate these case by case; opening an issue to discuss the idea before
  writing code is the safest path for both sides.

## Reporting security issues

Do not file security issues in public GitHub Issues. Email
**security@wenet-ec.com** with a description, reproducer, and any exploitation
details. We will acknowledge receipt within 72 hours and coordinate a fix and
disclosure timeline with you.

## Code of conduct

Be respectful, assume good faith, and keep technical discussion technical.
Maintainers reserve the right to close PRs, lock threads, or block users whose
behavior repeatedly disrupts the project.

---

## Developer Certificate of Origin

```
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.


Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```
