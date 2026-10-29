# Security Policy

## Supported versions

Only the latest release gets security fixes. Please update to the
[latest version](https://github.com/tran-minh-khoi/SATF/releases/latest) before reporting.

| Version        | Supported |
| -------------- | --------- |
| Latest release | ✅        |
| Older releases | ❌        |

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Report it privately through GitHub instead:
[Report a vulnerability](https://github.com/tran-minh-khoi/SATF/security/advisories/new)
(Security tab → "Report a vulnerability").

Helpful things to include:

- What the problem is and what an attacker could do with it
- Steps to reproduce (a sample file helps a lot)
- SATF version and OS (macOS or Windows version)

You should get a reply within 7 days. Once the issue is confirmed, a fix ships in a
new release and you'll be credited in the advisory unless you'd rather stay anonymous.

## Scope

Things that are in scope include:

- Opening or converting a crafted file that makes SATF run code, write outside the
  chosen output folder, or overwrite files it shouldn't
- Problems in how add-ons (FFmpeg, LibreOffice) are downloaded, checked, or launched
- Misuse of the Apple Events permission SATF uses to ask Office / iWork apps to export PDFs

Bugs inside third-party tools themselves (FFmpeg, LibreOffice, Microsoft Office, etc.)
should be reported to those projects.
