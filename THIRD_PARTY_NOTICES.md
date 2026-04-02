# Third-Party Notices

This repository contains scripts that automate the installation of third-party
software into a WSL2 environment. No third-party software is bundled or
distributed by this repository. All tools listed below are downloaded from
their respective official sources at build time.

---

## Tools Installed by bootstrap/install.sh

| Tool | License | License Holder | License Link |
|------|---------|---------------|-------------|
| [opencode](https://opencode.ai) | MIT | SST, Inc. | https://github.com/sst/opencode/blob/main/LICENSE |
| [GitHub CLI (gh)](https://cli.github.com) | MIT | GitHub, Inc. | https://github.com/cli/cli/blob/trunk/LICENSE |
| [Podman](https://podman.io) | Apache-2.0 | containers project | https://github.com/containers/podman/blob/main/LICENSE |
| [podman-docker](https://github.com/containers/podman) | Apache-2.0 | containers project | https://github.com/containers/podman/blob/main/LICENSE |
| [git](https://git-scm.com) | GPL-2.0-only | Linus Torvalds et al. | https://git.kernel.org/pub/scm/git/git.git/tree/COPYING |
| [curl](https://curl.se) | curl (MIT-like) | Daniel Stenberg et al. | https://curl.se/docs/copyright.html |
| [wget](https://www.gnu.org/software/wget/) | GPL-3.0-or-later | Free Software Foundation | https://www.gnu.org/software/wget/ |
| [unzip](https://infozip.sourceforge.net) | Info-ZIP | Info-ZIP | https://infozip.sourceforge.net/license.html |
| [xdg-utils](https://www.freedesktop.org/wiki/Software/xdg-utils/) | MIT/LGPL-2.1+ | freedesktop.org | https://cgit.freedesktop.org/xdg/xdg-utils/tree/LICENSE |
| [GnuPG (gnupg)](https://gnupg.org) | GPL-3.0-or-later | Free Software Foundation | https://gnupg.org/copying.html |
| [Ubuntu 24.04 LTS WSL image](https://ubuntu.com) | Various | Canonical Ltd. | https://ubuntu.com/legal/open-source-licences |

Additional Ubuntu/Debian packages (`ca-certificates`, `lsb-release`,
`apt-transport-https`) are installed from Ubuntu repositories. Their licensing
is governed by their respective upstream projects as distributed by Ubuntu.
See https://ubuntu.com/legal/open-source-licences for details.

---

## Note on GPL-Licensed Tools

`git`, `wget`, and `gnupg` are licensed under the GNU General Public License.
These tools are installed from Ubuntu package repositories at build time;
they are not bundled with, modified by, or distributed as part of this
repository. The GPL copyleft conditions (which apply to distribution of
GPL-licensed software) do not apply to these scripts.

The notices above are provided for transparency, not legal obligation.
