#!/bin/bash

set -e

VERSION="2.21.0"

TES3MP_STABLE_VERSION="0.8.1"
TES3MP_STABLE_VERSION_FILE="0.47.0\n68954091c54d0596037c4fb54d2812313b7582a1"
TES3MP_FORGE_VERSION="2.4.0"

HELP_TEXT_HEADER="\
TES3MP-deploy ($VERSION)
Grim Kriegor <grimkriegor@krutt.org>
Licensed under the GNU GPLv3 free license
"

HELP_TEXT_BODY="\
Usage $0 MODE [OPTIONS]

Modes of operation:
  -i, --install                  Prepare and install TES3MP and its dependencies
  -u, --upgrade                  Upgrade TES3MP
  -a, --auto-upgrade             Automatically upgrade TES3MP if there are changes on the remote repository
  -r, --rebuild                  Simply rebuild TES3MP
  -y, --script-upgrade           Upgrade the TES3MP-deploy script
  -p, --make-package             Make a portable package for easy distribution
  -h, --help                     This help text

Options:
  -s, --server-only              Only build the server
  -c, --cores N                  Use N cores for building TES3MP and its dependencies
  -v, --version ID               Checkout and build a specific TES3MP commit or branch
  -V, --version-string STRING    Set the version string for compatibility
  -C, --container [ARCH]         Run inside a container, optionally specify container architecture

Peculiar options:
  --skip-pkgs                    Skip package installation
  --cmake-local                  Tell CMake to look in /usr/local/ for libraries
  --handle-corescripts           Handle CoreScripts, pulls and branch switches
  --handle-version-file          Handle version file by overwritting it with a persistent one

Please report bugs in the GitHub issue page or directly on the TES3MP Discord.
https://github.com/GrimKriegor/TES3MP-deploy
"

SCRIPT_DIR="$(dirname $(readlink -f $0))"

echo -e "$HELP_TEXT_HEADER"

# Run in container
function run_in_container() {

  # Check if Docker is installed
  if ! which docker 2>&1 >/dev/null; then
    echo -e "Please install Docker before proceeding."
    exit 1
  fi

  # Clean script arguments
  SCRIPT_ARGUMENTS=$(echo "$@" | sed 's/-C//;s/--container//')

  # Defaults
  CONTAINER_IMAGE="docker.io/grimkriegor/tes3mp-forge:$TES3MP_FORGE_VERSION"
  CONTAINER_FOLDER_NAME="container"
  CONTAINER_DEFAULT_ARGS="--skip-pkgs --cmake-local"
  CONTAINER_PLATFORM_CMD="--arch amd64"

  # Architecture specifics
  case $CONTAINER_ARCHITECTURE in
    armhf )
      CONTAINER_IS_EMULATED="true"
      CONTAINER_ARCH="arm"
      CONTAINER_VARIANT="v7"
    ;;
  esac

  # Emulated container specifics
  if [ $CONTAINER_IS_EMULATED ]; then
    CONTAINER_FOLDER_NAME="$CONTAINER_FOLDER_NAME-$CONTAINER_ARCHITECTURE"
    CONTAINER_DEFAULT_ARGS=$(echo $CONTAINER_DEFAULT_ARGS | sed 's/--cmake-local//')
    CONTAINER_PLATFORM_CMD="--arch $CONTAINER_ARCH --variant $CONTAINER_VARIANT"
    echo -e "\nEmulating $CONTAINER_ARCHITECTURE on $(uname -m)"
  fi

  # Update container image
  eval $(which docker) pull "$CONTAINER_PLATFORM_CMD" "$CONTAINER_IMAGE"

  # Run through container
  echo -e "\n[!] Now running inside the TES3MP-forge container [!]\n"
  mkdir -p "$SCRIPT_DIR/$CONTAINER_FOLDER_NAME"
  eval $(which docker) run --rm -it \
    -v "$SCRIPT_DIR/tes3mp-deploy.sh":"/deploy/tes3mp-deploy.sh" \
    -v "$SCRIPT_DIR/$CONTAINER_FOLDER_NAME":"/build" \
    $CONTAINER_PLATFORM_CMD \
    --entrypoint "/bin/bash" \
    "$CONTAINER_IMAGE" \
    /deploy/tes3mp-deploy.sh "$CONTAINER_DEFAULT_ARGS" "$SCRIPT_ARGUMENTS"
  exit 0
}

# Parse arguments
SCRIPT_ARGS="$@"
if [ $# -eq 0 ]; then
  echo -e "$HELP_TEXT_BODY"
  echo -e "No parameter specified."
  exit 1

else
  while [ $# -ne 0 ]; do
    case $1 in

    # Help text
    -h | --help )
      echo -e "$HELP_TEXT_BODY"
      exit 1
    ;;

    # Install dependencies and build TES3MP
    -i | --install )
      INSTALL=true
      REBUILD=true
    ;;

    # Check if there are updates, prompt to rebuild if so
    -u | --upgrade )
      UPGRADE=true
    ;;

    # Upgrade automatically if there are changes in the upstream code
    -a | --auto-upgrade )
      UPGRADE=true
      AUTO_UPGRADE=true
    ;;

    # Rebuild tes3mp
    -r | --rebuild )
      REBUILD=true
    ;;

    # Upgrade the script
    -y | --script-upgrade )
      SCRIPT_UPGRADE=true
    ;;

    # Make package
    -p | --make-package )
      MAKE_PACKAGE=true
    ;;

    # Define installation as server only
    -s | --server-only )
      SERVER_ONLY=true
      touch .serveronly
    ;;

    # Build specific commit
    -v | --version | --branch | --commit )
      if [[ "$2" =~ ^-.* || "$2" == "" ]]; then
        echo -e "\nYou must specify a valid commit hash or branch name"
        exit 1
      else
        BUILD_COMMIT=true
        TARGET_COMMIT="$2"
        shift
      fi
    ;;

    # Custom version string for compatibility
    -V | --version-string )
      if [[ "$2" =~ ^-.* || "$2" == "" ]]; then
        echo -e "\nYou must specify a valid version string"
        exit 1
      else
        CHANGE_VERSION_STRING=true
        TARGET_VERSION_STRING="$2"
        shift
      fi
    ;;

    # Number of CPU threads to use in compilation
    -c | --cores )
      if [[ "$2" =~ ^-.* || "$2" == "" ]]; then
        ARG_CORES=""
      else
        ARG_CORES=$2
        shift
      fi
    ;;

    # Run in container
    -C | --container )
      if [[ "$2" =~ ^-.* || "$2" =~ "" ]]; then
        CONTAINER_ARCHITECTURE="$2"
        shift
      fi
      RUN_IN_CONTAINER=true
    ;;

    # Skip package installation
    --skip-pkgs )
      SKIP_PACKAGE_INSTALL=true
    ;;

    # Tell cmake to look for dependencies on /usr/local/
    --cmake-local )
      CMAKE_LOCAL=true
    ;;

    # Handle CoreScripts
    --handle-corescripts )
      HANDLE_CORESCRIPTS=true
    ;;

    # Handle version file
    --handle-version-file )
      HANDLE_VERSION_FILE=true
    ;;

    esac
    shift
  done

fi

# Run in container
if [ $RUN_IN_CONTAINER ]; then
  run_in_container "$SCRIPT_ARGS"
fi

# Exit if no operation is specified
if [[ ! $INSTALL && ! $UPGRADE && ! $REBUILD && ! $SCRIPT_UPGRADE && ! $MAKE_PACKAGE ]]; then
  echo -e "\nNo operation specified, exiting."
  exit 1
fi

# Number of CPU cores used for compilation
if [[ "$ARG_CORES" == "" || "$ARG_CORES" == "0" ]]; then
    CORES="$(cat /proc/cpuinfo | awk '/^processor/{print $3}' | wc -l)"
else
    CORES="$ARG_CORES"
fi

# Distro identification
DISTRO="$(lsb_release -si | awk '{print tolower($0)}')"
DISTROCODE="$(lsb_release -sc | awk '{print tolower($0)}')"

# Folder hierarchy
BASE="$(pwd)"
SCRIPT_BASE="$(dirname $0)"
CODE="$BASE/code"
DEVELOPMENT="$BASE/build"
KEEPERS="$BASE/keepers"
DEPENDENCIES="$BASE/dependencies"
PACKAGE_TMP="$BASE/package"
EXTRA="$BASE/extra"

# Dependency locations
RAKNET_LOCATION="$DEPENDENCIES"/raknet

# Check if this is a server only install
if [ -f "$BASE"/.serveronly ]; then
  SERVER_ONLY=true
fi

# Check if there is a persistent version file
if [ -f "$KEEPERS"/version ]; then
  HANDLE_VERSION_FILE=true
fi

if [ $CMAKE_LOCAL ]; then
  export PATH=/usr/local/bin:$PATH
  export LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib:"$LD_LIBRARY_PATH"
fi

# Upgrade the TES3MP-deploy script
if [ $SCRIPT_UPGRADE ]; then

  SCRIPT_OLD_VERSION=$(cat "$SCRIPT_BASE"/tes3mp-deploy.sh | grep ^VERSION= | cut -d'"' -f2)

  if [ -d "$SCRIPT_BASE"/.git ]; then
    echo -e "\n>>Upgrading the TES3MP-deploy git repository"
    cd "$SCRIPT_BASE"
    git stash
    git pull
    cd "$BASE"
  else
    echo -e "\n>>Downloading TES3MP-deploy from GitHub"
    mv "$0" "$SCRIPT_BASE"/.tes3mp-deploy.sh.bkp
    wget --no-verbose -O "$SCRIPT_BASE"/tes3mp-deploy.sh https://raw.githubusercontent.com/GrimKriegor/TES3MP-deploy/master/tes3mp-deploy.sh
    chmod +x "$SCRIPT_BASE"/tes3mp-deploy.sh
  fi

  SCRIPT_NEW_VERSION=$(cat "$SCRIPT_BASE"/tes3mp-deploy.sh | grep ^VERSION= | cut -d'"' -f2)

  if [ "$SCRIPT_NEW_VERSION" == "" ]; then
    echo -e "\nThere was a problem downloading the script, exiting."
    exit 1
  fi

  if [ "$SCRIPT_OLD_VERSION" != "$SCRIPT_NEW_VERSION" ]; then
    echo -e "\nScript upgraded from ($SCRIPT_OLD_VERSION) to ($SCRIPT_NEW_VERSION)"
    echo -e "\nReloading...\n"
    SCRIPT_ARGS_TRUNC="$(echo "$SCRIPT_ARGS" | sed 's/--script-upgrade//g;s/-y//g')"
    eval $(which bash) "$0 $SCRIPT_ARGS_TRUNC"
    exit 0
  else
    echo -e "\nScript already at the latest avaliable version ($SCRIPT_OLD_VERSION)"
  fi

fi

# Install mode
if [ $INSTALL ]; then

  # Create folder hierarchy
  echo -e ">> Creating folder hierarchy"
  mkdir -p "$DEVELOPMENT" "$KEEPERS" "$DEPENDENCIES"

  # Check distro and install dependencies
  if [ ! $SKIP_PACKAGE_INSTALL ]; then
  echo -e "\n>> Checking which GNU/Linux distro is installed"
  case $DISTRO in

    "debian" | "devuan" )
        echo -e "You seem to be running Debian or Devuan"
        sudo apt-get update
        sudo apt-get install \
          unzip \
          wget \
          git \
          cmake \
          libopenal-dev \
          qt5-default \
          qtbase5-dev \
          qtbase5-dev-tools \
          qttools5-dev-tools \
          libqt5opengl5-dev \
          libopenthreads-dev \
          libopenscenegraph-dev \
          libsdl2-dev \
          libboost-filesystem-dev \
          libboost-thread-dev \
          libboost-program-options-dev \
          libboost-system-dev \
          libavcodec-dev \
          libavformat-dev \
          libavutil-dev \
          libswscale-dev \
          libswresample-dev \
          libmygui-dev \
          libunshield-dev \
          cmake \
          build-essential \
          g++ \
          libncurses5-dev \
          luajit \
          libluajit-5.1-dev \
          liblua5.1-0-dev
        if [ $DISTROCODE == "stretch" ]; then
               sudo apt-get -y install libbullet-dev/stretch-backports
        else
               sudo apt-get -y install libbullet-dev
        fi
        sudo sed -i "s_# deb-src_deb-src_g" /etc/apt/sources.list
    ;;

    "arch" | "parabola" | "manjarolinux" )
        echo -e "You seem to be running either Arch Linux, Parabola GNU/Linux-libre or Manjaro"
        sudo pacman -Sy --needed unzip \
          wget \
          git \
          cmake \
          boost \
          openal \
          openscenegraph \
          mygui \
          bullet \
          qt5-base \
          ffmpeg \
          sdl2 \
          unshield \
          libxkbcommon-x11 \
          ncurses \
          luajit
        if [ ! -d "/usr/share/licenses/gcc-libs-multilib/" ]; then
              sudo pacman -S --needed gcc-libs
        fi
    ;;

    "ubuntu" | "linuxmint" | "elementary" )
        echo -e "You seem to be running Ubuntu, Mint or elementary OS"
        echo -e "
The OpenMW PPA repository needs to be enabled
https://wiki.openmw.org/index.php?title=Development_Environment_Setup#Ubuntu
Type YES if you want the script to do it automatically
If you already have it enabled or want to do it manually,
press ENTER to continue"
        read INPUT
        if [ "$INPUT" == "YES" ]; then
              echo -e "\nEnabling the OpenMW PPA repository..."
              sudo add-apt-repository ppa:openmw/openmw
              echo -e "Done!"
        fi
        sudo apt-get update
        sudo apt-get install \
          unzip \
          wget \
          git \
          cmake \
          libopenal-dev \
          qt5-default \
          qtbase5-dev \
          qtbase5-dev-tools \
          qttools5-dev-tools \
          libqt5opengl5-dev \
          libopenthreads-dev \
          libopenscenegraph-dev \
          libsdl2-dev \
          libboost-filesystem-dev \
          libboost-thread-dev \
          libboost-program-options-dev \
          libboost-system-dev \
          libbullet-dev \
          libavcodec-dev \
          libavformat-dev \
          libavutil-dev \
          libswscale-dev \
          libswresample-dev \
          libmygui-dev \
          libunshield-dev \
          cmake \
          build-essential \
          g++ \
          libncurses5-dev \
          luajit \
          libluajit-5.1-dev \
          liblua5.1-0-dev
        sudo sed -i "s_# deb-src_deb-src_g" /etc/apt/sources.list
    ;;

    "fedora" )
        echo -e "You seem to be running Fedora"
        echo -e "
Fedora users are required to enable the RPMFusion FREE and NON-FREE repositories
https://wiki.openmw.org/index.php?title=Development_Environment_Setup#Fedora_Workstation
Type YES if you want the script to do it automatically
If you already have it enabled or want to do it manually,
press ENTER to continue"
        read INPUT
        if [ "$INPUT" == "YES" ]; then
              echo -e "\nEnabling RPMFusion..."
              su -c 'dnf install \
                http://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
                http://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm'
              echo -e "Done!"
        fi
        sudo dnf --refresh groupinstall development-tools
        sudo dnf --refresh install \
          unzip \
          wget \
          cmake \
          openal-devel \
          OpenSceneGraph-qt-devel \
          SDL2-devel \
          qt5-devel \
          boost-filesystem \
          git \
          boost-thread \
          boost-program-options \
          boost-system \
          ffmpeg-devel \
          ffmpeg-libs \
          bullet-devel \
          gcc-c++ \
          mygui-devel \
          unshield-devel \
          tinyxml-devel \
          cmake \
          ncurses-c++-libs \
          ncurses-devel \
          luajit-devel
    ;;

    *)
        echo -e "Your GNU/Linux distro is not supported yet, press ENTER to continue without installing dependency packages"
        read
    ;;

  esac
  fi

  # Truncate target_commit when it points to stable
  if [ "$TARGET_COMMIT" == "stable" ]; then
    TARGET_COMMIT="$TES3MP_STABLE_VERSION"
  fi

  # Pull software via git
  echo -e "\n>> Downloading software"
  ! [ -e "$CODE" ] && git clone -b "${TARGET_COMMIT:-master}" https://github.com/TES3MP/TES3MP.git "$CODE"
  ! [ -e "$DEPENDENCIES"/raknet ] && git clone https://github.com/TES3MP/CrabNet "$DEPENDENCIES"/raknet
  ! [ -e "$KEEPERS"/CoreScripts ] && git clone -b "${TARGET_COMMIT:-master}" https://github.com/TES3MP/CoreScripts.git "$KEEPERS"/CoreScripts

  # Copy static server and client configs
  echo -e "\n>> Copying server and client configs to their permanent place"
  cp "$CODE"/files/tes3mp/tes3mp-{client,server}-default.cfg "$KEEPERS"

  # Set home variable in tes3mp-server-default.cfg
  echo -e "\n>> Autoconfiguring"
  sed -i "s|home = .*|home = $KEEPERS/CoreScripts|g" "${KEEPERS}"/tes3mp-server-default.cfg

  # Dirty hacks
  echo -e "\n>> Applying some dirty hacks"
  sed -i "s|tes3mp.lua,chat_parser.lua|server.lua|g" "${KEEPERS}"/tes3mp-server-default.cfg #Fixes server scripts

  # Build RakNet
  echo -e "\n>> Building RakNet"
  cd "$DEPENDENCIES"/raknet
  git checkout 19e66190e83f53bcdcbcd6513238ed2e54878a21

  mkdir -p "$DEPENDENCIES"/raknet/build
  cd "$DEPENDENCIES"/raknet/build

  rm -f CMakeCache.txt
  cmake -DCMAKE_BUILD_TYPE=Release -DRAKNET_ENABLE_DLL=OFF -DRAKNET_ENABLE_SAMPLES=OFF -DRAKNET_ENABLE_STATIC=ON -DRAKNET_GENERATE_INCLUDE_ONLY_DIR=ON ..
  make -j$CORES

  ln -sf "$DEPENDENCIES"/raknet/include/RakNet "$DEPENDENCIES"/raknet/include/raknet #Stop being so case sensitive

  cd "$BASE"

  # Build the stable branch if no target commit is specified
  if [ ! $BUILD_COMMIT ]; then
    echo -e "\n>> Switching to the STABLE branch."
    BUILD_COMMIT=true
    TARGET_COMMIT="stable"

    # Switch to the stable branch on CoreScripts as well
    cd "$KEEPERS"/CoreScripts
    git stash
    git pull
    git checkout "$TES3MP_STABLE_VERSION"
    cd "$BASE"

    # Handle version file
    HANDLE_VERSION_FILE=true
  fi

fi

# Check the remote repository for changes
if [ $UPGRADE ]; then

  # Check if there are changes in the git remote
  echo -e "\n>> Checking the git repository for changes"
  cd "$CODE"
  git remote update
  if [ "$(git rev-parse @)" != "$(git rev-parse @{u})" ]; then
    echo -e "\nNEW CHANGES on the git repository"
    GIT_CHANGES=true
  else
    echo -e "\nNo changes on the git repository"
  fi
  cd "$BASE"

  # Check if there are changes in the CoreScripts git remote
  if [ $HANDLE_CORESCRIPTS ]; then
    echo -e "\n>> Checking the CoreScripts git repository for changes"
    cd "$KEEPERS"/CoreScripts
    git remote update
    if [ "$(git rev-parse @)" != "$(git rev-parse @{u})" ]; then
      echo -e "\nNEW CHANGES on the CoreScripts git repository"
      GIT_CHANGES_CORESCRIPTS=true
    else
      echo -e "\nNo changes on the CoreScripts git repository"
    fi
    cd "$BASE"
  fi

  # Automatically upgrade if there are git changes
  if [ $AUTO_UPGRADE ]; then
    if [ $GIT_CHANGES ]; then
      REBUILD="YES"
      UPGRADE="YES"
    elif [ $GIT_CHANGES_CORESCRIPTS ]; then
      UPGRADE="YES"
    else
      echo -e "\nNo new commits, exiting."
      exit 0
    fi
  else
    echo -e "\nDo you wish to rebuild TES3MP? (type YES to continue)"
    read REBUILD_PROMPT
    if [ "$REBUILD_PROMPT" == "YES" ]; then
      REBUILD="YES"
      UPGRADE="YES"
    else
      if [ $HANDLE_CORESCRIPTS ]; then
        echo -e "\nUpgrade CoreScripts at least? (type YES to upgrade)"
        read CORESCRIPTS_UPGRADE_PROMPT
        if [ "$CORESCRIPTS_UPGRADE_PROMPT" == "YES" ]; then
          UPGRADE="YES"
        fi
      fi
    fi
  fi
fi

# CoreScripts handling (hack, please make me more elegant later :( )
if [ $HANDLE_CORESCRIPTS ]; then
  if [ $UPGRADE ]; then
    echo -e "\n>> Pulling CoreScripts code changes from git"
    cd "$KEEPERS"/CoreScripts
    git stash
    git pull
    cd "$BASE"
  fi

  if [ $BUILD_COMMIT ]; then
    cd "$KEEPERS"/CoreScripts
    if [[ "$TARGET_COMMIT" == "" || "$TARGET_COMMIT" == "latest" ]]; then
      echo -e "\nChecking out the latest CoreScripts commit."
      git stash
      git pull
      git checkout master
    elif [ "$TARGET_COMMIT" == "stable" ]; then
      echo -e "\nChecking out the CoreScripts stable branch. \"$TES3MP_STABLE_VERSION\""
      git stash
      git pull
      git checkout "$TES3MP_STABLE_VERSION"
    else
      echo -e "\nChecking out CoreScripts $TARGET_COMMIT"
      git stash
      git pull
      git checkout "$TARGET_COMMIT"
    fi
    cd "$BASE"
  fi

fi

# Rebuild TES3MP
if [ $REBUILD ]; then

  # Switch to a specific commit
  if [ $BUILD_COMMIT ]; then
    cd "$CODE"
    if [[ "$TARGET_COMMIT" == "" || "$TARGET_COMMIT" == "latest" ]]; then
      echo -e "\nChecking out the latest commit."
      git stash
      git pull
      git checkout master
    elif [ "$TARGET_COMMIT" == "stable" ]; then
      echo -e "\nChecking out the stable branch. \"$TES3MP_STABLE_VERSION\""
      git stash
      git pull
      git checkout "$TES3MP_STABLE_VERSION"
      if [ $HANDLE_VERSION_FILE ]; then
        echo -e "\n>> Creating persistent version file"
        echo -e $TES3MP_STABLE_VERSION_FILE > "$KEEPERS"/version
      fi
    else
      echo -e "\nChecking out $TARGET_COMMIT"
      git stash
      git pull
      git checkout "$TARGET_COMMIT"
    fi
    cd "$BASE"

    if [ $HANDLE_VERSION_FILE ]; then
      echo -e "\n(!) VERSION FILE OVERRIDE DETECTED (!)\nIf this was not intended, remove $KEEPERS/version"
    fi

  fi

  # Change version string
  if [ $CHANGE_VERSION_STRING ]; then
    cd "$CODE"

    if [[ "$TARGET_VERSION_STRING" == "" || "$TARGET_VERSION_STRING" == "latest" ]]; then
      echo -e "\nUsing the upstream version string"
      git stash
      cd "$KEEPERS"/CoreScripts
      git stash
      cd "$CODE"
    else
      echo -e "\nUsing \"$TARGET_VERSION_STRING\" as version string"
      sed -i "s|#define TES3MP_VERSION .*|#define TES3MP_VERSION \"$TARGET_VERSION_STRING\"|g" ./components/openmw-mp/Version.hpp
      sed -i "s|    if tes3mp.GetServerVersion() ~= .*|    if tes3mp.GetServerVersion() ~= \"$TARGET_VERSION_STRING\" then|g" "$KEEPERS"/CoreScripts/scripts/server.lua
    fi

    cd "$BASE"
  fi

    # Pull code changes from the git repository
  if [ "$UPGRADE" == "YES" ]; then
    echo -e "\n>> Pulling code changes from git"
    cd "$CODE"
    git stash
    git pull
    cd "$BASE"
  fi

  echo -e "\n>> Doing a clean build of TES3MP"

  rm -r "$DEVELOPMENT"
  mkdir -p "$DEVELOPMENT"

  cd "$DEVELOPMENT"

  CMAKE_PARAMS="-Wno-dev \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_OPENCS=OFF \
      -DCMAKE_CXX_STANDARD=14 \
      -DCMAKE_CXX_FLAGS=\"-std=c++14\" \
      -DDESIRED_QT_VERSION=5 \
      -DRakNet_INCLUDES="${RAKNET_LOCATION}"/include \
      -DRakNet_LIBRARY_DEBUG="${RAKNET_LOCATION}"/build/lib/libRakNetLibStatic.a \
      -DRakNet_LIBRARY_RELEASE="${RAKNET_LOCATION}"/build/lib/libRakNetLibStatic.a"

  if [ $SERVER_ONLY ]; then
    CMAKE_PARAMS="$CMAKE_PARAMS \
      -DBUILD_OPENMW_MP=ON \
      -DBUILD_OPENCS=OFF \
      -DBUILD_BROWSER=OFF \
      -DBUILD_BSATOOL=OFF \
      -DBUILD_ESMTOOL=OFF \
      -DBUILD_ESSIMPORTER=OFF \
      -DBUILD_LAUNCHER=OFF \
      -DBUILD_MWINIIMPORTER=OFF \
      -DBUILD_MYGUI_PLUGIN=OFF \
      -DBUILD_OPENMW=OFF \
      -DBUILD_NIFTEST=OFF \
      -DBUILD_WIZARD=OFF"
  fi

  if [ $CMAKE_LOCAL ]; then
    CMAKE_PARAMS="$CMAKE_PARAMS \
      -DCMAKE_LIBRARY_PATH=/usr/local/lib64"
  fi

  echo -e "\n\n$CMAKE_PARAMS\n\n"
  cmake "$CODE" $CMAKE_PARAMS || true
  set -o pipefail # so that the "tee" below would not make build always return success
  make -j $CORES 2>&1 | tee "${BASE}"/build.log

  cd "$BASE"

  # Create symlinks for the config files inside the new build folder
  echo -e "\n>> Creating symlinks of the config files in the build folder"
  for file in "$KEEPERS"/*.cfg
  do
    FILEPATH=$file
    FILENAME=$(basename $file)
    mv "$DEVELOPMENT/$FILENAME" "$DEVELOPMENT/$FILENAME.bkp" 2> /dev/null
    ln -sf "../keepers/$FILENAME" "$DEVELOPMENT/"
  done

  # Create symlinks for resources inside the config folder
  echo -e "\n>> Creating symlinks for resources inside the config folder"
  ln -sf ../"$(basename $DEVELOPMENT)"/resources "$KEEPERS"/resources 2> /dev/null

  # Create useful shortcuts on the base directory
  echo -e "\n>> Creating useful shortcuts on the base directory"
  if [ $SERVER_ONLY ]; then
    SHORTCUTS=( "tes3mp-server" )
  else
    SHORTCUTS=( "tes3mp" "tes3mp-browser" "tes3mp-server" )
  fi
  for i in ${SHORTCUTS[@]}; do
    printf "#!/bin/bash\n\ncd build/\n./$i\ncd .." > "$i".sh
    chmod +x "$i".sh
  done

  # Handle version file
  if [ $HANDLE_VERSION_FILE ]; then
    echo -e "\n>> Linking persistent version file"
    rm "$DEVELOPMENT"/resources/version
    ln -sf "$KEEPERS"/version "$DEVELOPMENT"/resources/version
  fi

  # Copy creditation files
  echo -e "\n>> Copying creditation files"
  cp "$CODE"/AUTHORS.md "$DEVELOPMENT"
  cp "$CODE"/tes3mp-credits.md "$DEVELOPMENT"

  # All done
  echo -e "\n\n\nAll done! Press any key to exit.\nMay Vehk bestow his blessing upon your Muatra."

fi

# Make portable package
if [ $MAKE_PACKAGE ]; then
  echo -e "\n>> Creating TES3MP package"

  PACKAGE_BINARIES=( \
    "tes3mp" \
    "tes3mp-browser" \
    "tes3mp-server" \
    "openmw-launcher" \
    "openmw-wizard" \
    "openmw-essimporter" \
    "openmw-iniimporter" \
    "bsatool" \
    "esmtool" \
   )

  LIBRARIES_OPENMW=( \
    "libavcodec.so" \
    "libavformat.so" \
    "libavutil.so" \
    "libboost_thread.so" \
    "libboost_system.so" \
    "libboost_filesystem.so" \
    "libboost_program_options.so" \
    "libboost_iostreams.so" \
    "libBulletCollision.so" \
    "libbz2.so" \
    "libLinearMath.so" \
    "libMyGUIEngine.so" \
    "libopenal.so" \
    "libOpenThreads.so" \
    "libosgAnimation.so" \
    "libosgDB.so" \
    "libosgFX.so" \
    "libosgGA.so" \
    "libosgParticle.so" \
    "libosg.so" \
    "libosgText.so" \
    "libosgUtil.so" \
    "libosgViewer.so" \
    "libosgWidget.so" \
    "libosgShadow.so" \
    "libSDL2" \
    "libswresample.so" \
    "libswscale.so" \
    "libts.so" \
    "libtxc_dxtn.so" \
    "libunshield.so" \
    "libuuid.so" \
    "libsndio.so" \
    "libvpx.so" \
    "libwebp.so" \
    "libcrystalhd.so" \
    "libaom.so" \
    "libcodec2.so" \
    "libshine.so" \
    "libx264.so" \
    "libx265.so" \
    "libssh-gcrypt.so" \
    "osgPlugins" \
  )

  LIBRARIES_TES3MP=( \
    "libRakNetLibStatic.a" \
    "libtinfo.so" \
    "liblua5.1.so" \
   )

  LIBRARIES_EXTRA=( \
    "libpng16.so" \
    "libpng12.so" \
  )

  LIBRARIES_SERVER=( \
    "libboost_system.so" \
    "libboost_filesystem.so" \
    "libboost_program_options.so" \
    "libboost_iostreams.so" \
    "liblua5.1.so" \
  )

  # Exit if tes3mp hasn't been compiled yet
  if [[ ! -f "$DEVELOPMENT"/tes3mp && ! -f "$DEVELOPMENT"/tes3mp-server ]]; then
    echo -e "\nTES3MP has to be built before packaging"
    exit 1
  fi

  # Copy the entire build folder for packaging
  cp -r "$DEVELOPMENT" "$PACKAGE_TMP"

  # Copy the license file
  cp -f "$CODE"/LICENSE "$PACKAGE_TMP"/LICENSE

  # Copy the source code
  SOURCE_TMP="$BASE/TES3MP"
  cp -r "$CODE" "$SOURCE_TMP"
  rm -r "$SOURCE_TMP/.git"
  tar cvf "$PACKAGE_TMP/source.tar.gz" -C "$BASE" "$(basename $SOURCE_TMP)"
  rm -r "$SOURCE_TMP"

  # Copy the persistent version file as well
  if [ $HANDLE_VERSION_FILE ]; then
    rm -f "$PACKAGE_TMP"/resources/version
    cp -fn "$KEEPERS"/version "$PACKAGE_TMP"/resources/version
  fi

  cd "$PACKAGE_TMP"

  # Cleanup unneeded files
  echo -e "\nCleaning up unneeded files"
  find "$PACKAGE_TMP" -type d -name "CMakeFiles" -exec rm -rf "{}" \; || true
  #find "$PACKAGE_TMP" -type d -name ".git" -exec rm -rf "{}" \; || true
  find "$PACKAGE_TMP" -type l -exec rm -f "{}" \; || true
  rm -f "$PACKAGE_TMP"/{Make*,CMake*,*cmake}
  rm -f "$PACKAGE_TMP"/{*.bkp,*.desktop,*.xml}
  rm -rf "$PACKAGE_TMP"/{apps,components,docs,extern,files}

  # Copy useful files
  echo -e "\nCopying useful files"
  cp -r "$KEEPERS"/CoreScripts "$PACKAGE_TMP"/server
  cp -r "$KEEPERS"/*.cfg "$PACKAGE_TMP"
  sed -i "s|home = .*|home = ./server|g" "$PACKAGE_TMP"/tes3mp-server-default.cfg

  # Copy whatever extra files are currently present
  if [ -d "$EXTRA" ]; then
    echo -e "\nCopying some extra files"
    cp -rf --preserve=links "$EXTRA"/* "$PACKAGE_TMP"/
  fi

  # List and copy all libs
  mkdir -p lib
  echo -e "\nCopying needed libraries"

  LIBRARIES=("${LIBRARIES_OPENMW[@]}" "${LIBRARIES_TES3MP[@]}" "${LIBRARIES_EXTRA[@]}")
  if [ $SERVER_ONLY ]; then LIBRARIES=("${LIBRARIES_SERVER[@]}"); fi

  for LIB in "${LIBRARIES[@]}"; do
    find /lib /usr/lib /usr/local/lib /usr/local/lib64 "$DEPENDENCIES" -name "$LIB*" -exec cp -r --preserve=links "{}" ./lib \; 2> /dev/null || true
    echo -ne "$LIB\033[0K\r"
  done

  # Make sure all symlinks are relative
  echo -e "\nMaking sure all symlinks are relative"
  find ./lib -type l | while read LINK; do
    LINK_BASENAME="$(basename $LINK)"
    LINK_TARGET="$(readlink -f $LINK)"
    LINK_TARGET_BASENAME="$(basename $LINK_TARGET)"
    ln -sf ./"$LINK_TARGET_BASENAME" ./lib/"$LINK_BASENAME"
    echo -ne "$LINK\033[0K\r"
  done

  # Package info

  PACKAGE_PREFIX="tes3mp"
  if [ $SERVER_ONLY ]; then
    PACKAGE_PREFIX="$PACKAGE_PREFIX-server"
  fi

  PACKAGE_ARCH=$(uname -m)
  PACKAGE_SYSTEM=$(uname -o  | sed 's,/,+,g')
  PACKAGE_DISTRO="$DISTRO"
  PACKAGE_VERSION=$(cat "$CODE"/components/openmw-mp/Version.hpp | grep TES3MP_VERSION | awk -F'"' '{print $2}')
  PACKAGE_COMMIT=$(git --git-dir=$CODE/.git rev-parse @ | head -c10)
  PACKAGE_COMMIT_SCRIPTS=$(git --git-dir=$KEEPERS/CoreScripts/.git rev-parse @ | head -c10)

  PACKAGE_NAME="$PACKAGE_PREFIX-$PACKAGE_SYSTEM-$PACKAGE_ARCH-release-$PACKAGE_VERSION-$PACKAGE_COMMIT-$PACKAGE_COMMIT_SCRIPTS"
  PACKAGE_DATE="$(date +"%Y-%m-%d")"

  echo -e "TES3MP $PACKAGE_VERSION ($PACKAGE_COMMIT $PACKAGE_COMMIT_SCRIPTS) built on $PACKAGE_SYSTEM $PACKAGE_ARCH ($PACKAGE_DISTRO) on $PACKAGE_DATE by $USER ($HOSTNAME)" > "$PACKAGE_TMP"/tes3mp-package-info.txt

  # Create pre-launch script
  cat << 'EOF' > tes3mp-prelaunch
#!/bin/bash

ARGS="$*"
GAMEDIR="$(cd "$(dirname "$0")"; pwd -P)"
TES3MP_HOME="$HOME/.config/openmw"

# If there are config files in the home directory, load those
# Otherwise check the package/installation directory and load those
# Otherwise copy them to the home directory
if [[ "$ARGS" = 'tes3mp-server' ]]; then
    if [[ -f "$TES3MP_HOME"/tes3mp-server.cfg ]]; then
        echo -e "Loading server config from the home directory"
        LOADING_FROM_HOME=true
    elif [[ -f "$GAMEDIR"/tes3mp-server-default.cfg ]]; then
        echo -e "Loading server config from the package directory"
    else
        echo -e "Server config not found in home and package directory, trying to copy from .example"
        cp -f tes3mp-server-default.cfg.example "$TES3MP_HOME"/tes3mp-server.cfg
        LOADING_FROM_HOME=true
    fi
    if [[ $LOADING_FROM_HOME ]]; then
        if [[ -d "$TES3MP_HOME"/server ]]; then
            echo -e "Loading CoreScripts folder from the home directory"
        else
            echo -e "CoreScripts folder not found in home directory, copying from package directory"
            cp -rf "$GAMEDIR"/server/ "$TES3MP_HOME"/
            sed -i "s|home = .*|home = $TES3MP_HOME/server |g" "$TES3MP_HOME"/tes3mp-server.cfg
        fi
    fi
else
    if [[ -f $TES3MP_HOME/tes3mp-client.cfg ]]; then
        echo -e "Loading client config from the home directory"
    elif [[ -f tes3mp-client-default.cfg ]]; then
        echo -e "Loading client config from the package directory"
    else
        echo -e "Client config not found in home and package directory, trying to copy from .example"
        cp -f "$GAMEDIR"/tes3mp-client-default.cfg.example "$TES3MP_HOME"/tes3mp-client.cfg
    fi
fi
EOF

  # Create wrappers
  echo -e "\n\nCreating wrappers"
  for BINARY in "${PACKAGE_BINARIES[@]}"; do
    if [ ! -f "$BINARY" ]; then
      echo -e "Binary $BINARY not found"
    else
      WRAPPER="$BINARY"
      BINARY_RENAME="$BINARY.$PACKAGE_ARCH"
      mv "$BINARY" "$BINARY_RENAME"
      printf "#!/bin/bash\n\nWRAPPER=\"\$(basename \$0)\"\nGAMEDIR=\"\$(dirname \$0)\"\ncd \"\$GAMEDIR\"\nif test -f ./tes3mp-prelaunch; then bash ./tes3mp-prelaunch \"\$WRAPPER\"; fi\nLD_LIBRARY_PATH=\"./lib\" ./$BINARY_RENAME \"\$@\"" > "$WRAPPER"
    fi
  done
  chmod 755 *

  # Create archive
  echo -e "\nCreating archive"

  PACKAGE_FOLDER="TES3MP"
  if [ $SERVER_ONLY ]; then PACKAGE_FOLDER="$PACKAGE_FOLDER-server"; fi

  mv "$PACKAGE_TMP" "$BASE"/"$PACKAGE_FOLDER"
  PACKAGE_TMP="$BASE"/"$PACKAGE_FOLDER"
  tar cvzf "$BASE"/package.tar.gz --directory="$BASE" "$PACKAGE_FOLDER"/

  # Rename archive
  mv "$BASE"/package.tar.gz "$BASE"/"$PACKAGE_NAME".tar.gz

  # Cleanup temporary folder and finish
  rm -rf "$PACKAGE_TMP"
  echo -e "\n>> Package created as \"$PACKAGE_NAME\""

  cd "$BASE"
fi
