# Security policy

mib-statuscheck runs unsandboxed inside the Omarchy shell and fetches content
from third-party servers, so security reports are taken seriously.

## Reporting a vulnerability

Please report privately through
[GitHub's private vulnerability reporting](https://github.com/mindows/mib-statuscheck/security/advisories/new),
not in a public issue.

Include what you found, how to reproduce it, and the commit you tested
(`git -C ~/.config/omarchy/plugins/io.github.mindows.mib-statuscheck rev-parse --short HEAD`).

Examples of what counts:

- a settings value, pasted URL or feed payload that ends up executed as a
  command
- the plugin writing outside its own entry in `~/.config/omarchy/shell.json`
- requests going anywhere other than the status pages the user added

## Supported versions

Only the current `main` branch is supported. `omarchy plugin update` always
installs the latest `main`, and that is where fixes land.
