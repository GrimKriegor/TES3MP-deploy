# TES3MP-deploy

### A script to simplify the installation and upgrade of TES3MP

<grimkriegor@krutt.org>

When placed in an empty folder this script creates a folder hierarchy, installs the system dependencies based on your distro, downloads the code for TES3MP, OSG, Bullet, RakNet and Terra, compiles everything and is also able to upgrade it from the latest git changes whenever necessary.

Config files and plugins are kept in a separate folder, avoiding their deletion during upgrades and rebuilds.

**Usage information:**

    ./tes3mp-deploy.sh --help

**Currently supported systems:** Arch Linux, Parabola GNU/Linux-libre, Manjaro, Debian, Devuan, Ubuntu, Linux Mint and Fedora.

Big thanks to Testman and the TES3MP community for their intense testing, debugging and suggestions.
