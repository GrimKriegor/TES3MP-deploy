#!/bin/bash

set -e

VERSION="2.12.0"

TES3MP_STABLE_VERSION="0.6.2"
TES3MP_STABLE_VERSION_FILE="0.43.0\n5fd9079b26a60d3a8a52299d0ea8146b85323339"

HEADERTEXT="\
TES3MP-deploy ($VERSION)
Grim Kriegor <grimkriegor@krutt.org>
Licensed under the GNU GPLv3 free license
"

HELPTEXT="\
Usage $0 MODE [OPTIONS]

Modes of operation:
  -i, --install			Prepare and install TES3MP and its dependencies
  -u, --upgrade			Upgrade TES3MP
  -a, --auto-upgrade		Automatically upgrade TES3MP if there are changes on the remote repository
  -r, --rebuild			Simply rebuild TES3MP
  -y, --script-upgrade		Upgrade the TES3MP-deploy script
  -p, --make-package		Make a portable package for easy distribution
  -h, --help			This help text

Options:
  -s, --server-only		Only build the server
  -c, --cores N			Use N cores for building TES3MP and its dependencies
  -v, --version ID		Checkout and build a specific TES3MP commit or branch
  -V, --version-string STRING	Set the version string for compatibility
  -m, --build-master		Build the master server
  -C, --container		Run inside a container, for increasced compatibility

Peculiar options:
  --debug-symbols		Build with debug symbols
  --skip-pkgs			Skip package installation
  --cmake-local			Tell CMake to look in /usr/local/ for libraries
  --handle-corescripts		Handle CoreScripts, pulls and branch switches
  --handle-version-file		Handle version file by overwritting it with a persistent one

Please report bugs in the GitHub issue page or directly on the TES3MP Discord.
https://github.com/GrimKriegor/TES3MP-deploy
"

SCRIPT_DIR="$(dirname $(readlink -f $0))"

echo -e "$HEADERTEXT"


#RUN IN CONTAINER
function run_in_container() {

  #CHECK IF DOCKER IS INSTALLED
  if ! which docker 2>&1 >/dev/null; then
    echo -e "Please install Docker before proceeding."
    exit 1
  fi

  #CLEAN ARGUMENTS
  ARGUMENTS=$(echo "$@" | sed 's/-C//;s/--container//')

  #NOTIFY
  echo -e "\n[!] Now running inside the TES3MP-forge container [!]\n\n"

  #RUN THROUGH TES3MP-FORGE
  eval $(which docker) run --name tes3mp-deploy --rm -it -v "$SCRIPT_DIR/tes3mp-deploy.sh":"/deploy/tes3mp-deploy.sh" -v "$SCRIPT_DIR/container":"/build" --entrypoint "/bin/bash" grimkriegor/tes3mp-forge /deploy/tes3mp-deploy.sh --skip-pkgs --cmake-local "$ARGUMENTS"

  exit 0
}

#PARSE ARGUMENTS
SCRIPT_ARGS="$@"
if [ $# -eq 0 ]; then
  echo -e "$HELPTEXT"
  echo -e "No parameter specified."
  exit 1

else
  while [ $# -ne 0 ]; do
    case $1 in

    #HELP TEXT
    -h | --help )
      echo -e "$HELPTEXT"
      exit 1
    ;;

    #INSTALL DEPENDENCIES AND BUILD TES3MP
    -i | --install )
      INSTALL=true
      REBUILD=true
    ;;

    #CHECK IF THERE ARE UPDATES, PROMPT TO REBUILD IF SO
    -u | --upgrade )
      UPGRADE=true
    ;;

    #UPGRADE AUTOMATICALLY IF THERE ARE CHANGES IN THE UPSTREAM CODE
    -a | --auto-upgrade )
      UPGRADE=true
      AUTO_UPGRADE=true
    ;;

    #REBUILD TES3MP
    -r | --rebuild )
      REBUILD=true
    ;;

    #UPGRADE THE SCRIPT
    -y | --script-upgrade )
      SCRIPT_UPGRADE=true
    ;;

    #MAKE PACKAGE
    -p | --make-package )
      MAKE_PACKAGE=true
    ;;

    #DEFINE INSTALLATION AS SERVER ONLY
    -s | --server-only )
      SERVER_ONLY=true
      touch .serveronly
    ;;

    #BUILD SPECIFIC COMMIT
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

    #CUSTOM VERSION STRING FOR COMPATIBILITY
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

    #NUMBER OF CPU THREADS TO USE IN COMPILATION
    -c | --cores )
      if [[ "$2" =~ ^-.* || "$2" == "" ]]; then
        ARG_CORES=""
      else
        ARG_CORES=$2
        shift
      fi
    ;;

    #BUILD MASTER SERVER
    -m | --build-master )
      BUILD_MASTER=true
      touch .buildmaster
    ;;

    #RUN IN CONTAINER
    -C | --container )
    run_in_container "$SCRIPT_ARGS"
    ;;

    #BUILD WITH DEBUG SYMBOLS
    --debug-symbols )
      DEBUG_SYMBOLS=true
    ;;

    #SKIP PACKAGE INSTALLATION
    --skip-pkgs )
      SKIP_PACKAGE_INSTALL=true
    ;;

    #TELL CMAKE TO LOOK FOR DEPENDENCIES ON /USR/LOCAL/
    --cmake-local )
      CMAKE_LOCAL=true
    ;;

    #HANDLE CORESCRIPTS
    --handle-corescripts )
      HANDLE_CORESCRIPTS=true
    ;;

    #HANDLE VERSION FILE
    --handle-version-file )
      HANDLE_VERSION_FILE=true
    ;;

    esac
    shift
  done

fi

#EXIT IF NO OPERATION IS SPECIFIED
if [[ ! $INSTALL && ! $UPGRADE && ! $REBUILD && ! $SCRIPT_UPGRADE && ! $MAKE_PACKAGE ]]; then
  echo -e "\nNo operation specified, exiting."
  exit 1
fi

#NUMBER OF CPU CORES USED FOR COMPILATION
if [[ "$ARG_CORES" == "" || "$ARG_CORES" == "0" ]]; then
    CORES="$(cat /proc/cpuinfo | awk '/^processor/{print $3}' | wc -l)"
else
    CORES="$ARG_CORES"
fi

#DISTRO IDENTIFICATION
DISTRO="$(lsb_release -si | awk '{print tolower($0)}')"

#FOLDER HIERARCHY
BASE="$(pwd)"
SCRIPT_BASE="$(dirname $0)"
CODE="$BASE/code"
DEVELOPMENT="$BASE/build"
KEEPERS="$BASE/keepers"
DEPENDENCIES="$BASE/dependencies"
PACKAGE_TMP="$BASE/package"
EXTRA="$BASE/extra"

#DEPENDENCY LOCATIONS
CALLFF_LOCATION="$DEPENDENCIES"/callff
RAKNET_LOCATION="$DEPENDENCIES"/raknet
OSG_LOCATION="$DEPENDENCIES"/osg
BULLET_LOCATION="$DEPENDENCIES"/bullet

#CHECK IF THIS IS A SERVER ONLY INSTALL
if [ -f "$BASE"/.serveronly ]; then
  SERVER_ONLY=true
fi

#CHECK IF MASTER SERVER IS SUPPOSED TO BE BUILT
if [ -f "$BASE"/.buildmaster ]; then
  BUILD_MASTER=true
fi

#CHECK IF THERE IS A PERSISTENT VERSION FILE
if [ -f "$KEEPERS"/version ]; then
  HANDLE_VERSION_FILE=true
fi

if [ $CMAKE_LOCAL ]; then
  export PATH=/usr/local/bin:$PATH
  export LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib:"$LD_LIBRARY_PATH"
fi

#UPGRADE THE TES3MP-DEPLOY SCRIPT
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

#INSTALL MODE
if [ $INSTALL ]; then

  #CREATE FOLDER HIERARCHY
  echo -e ">> Creating folder hierarchy"
  mkdir -p "$DEVELOPMENT" "$KEEPERS" "$DEPENDENCIES"

  #CHECK DISTRO AND INSTALL DEPENDENCIES
  if [ ! $SKIP_PACKAGE_INSTALL ]; then
  echo -e "\n>> Checking which GNU/Linux distro is installed"
  case $DISTRO in
    "arch" | "parabola" | "manjarolinux" )
        echo -e "You seem to be running either Arch Linux, Parabola GNU/Linux-libre or Manjaro"
        sudo pacman -Sy --needed unzip wget git cmake boost openal openscenegraph mygui bullet qt5-base ffmpeg sdl2 unshield libxkbcommon-x11 ncurses luajit #clang35 llvm35

        if [ ! -d "/usr/share/licenses/gcc-libs-multilib/" ]; then
              sudo pacman -S --needed gcc-libs
        fi
    ;;

    "debian" | "devuan" )
        echo -e "You seem to be running Debian or Devuan"
        sudo apt-get update
        sudo apt-get install unzip wget git cmake libopenal-dev qt5-default libqt5opengl5-dev libopenthreads-dev libopenscenegraph-3.4-dev libsdl2-dev libqt4-dev libboost-filesystem-dev libboost-thread-dev libboost-program-options-dev libboost-system-dev libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev libmygui-dev libunshield-dev cmake build-essential libqt4-opengl-dev g++ libncurses5-dev libluajit-5.1-dev liblua5.1-0-dev #libbullet-dev
        sudo sed -i "s,# deb-src,deb-src,g" /etc/apt/sources.list
        sudo apt-get build-dep bullet
        BUILD_BULLET=true
    ;;

    "ubuntu" | "linuxmint" | "elementary" )
        echo -e "You seem to be running Ubuntu, Mint or elementary OS"
        echo -e "\nThe OpenMW PPA repository needs to be enabled\nhttps://wiki.openmw.org/index.php?title=Development_Environment_Setup#Ubuntu\n\nType YES if you want the script to do it automatically\nIf you already have it enabled or want to do it manually,\npress ENTER to continue"
        read INPUT
        if [ "$INPUT" == "YES" ]; then
              echo -e "\nEnabling the OpenMW PPA repository..."
              sudo add-apt-repository ppa:openmw/openmw
              echo -e "Done!"
        fi
        sudo apt-get update
        sudo apt-get install unzip wget git cmake libopenal-dev qt5-default libqt5opengl5-dev libopenthreads-dev libopenscenegraph-3.4-dev libsdl2-dev libqt4-dev libboost-filesystem-dev libboost-thread-dev libboost-program-options-dev libboost-system-dev libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev libmygui-dev libunshield-dev cmake build-essential libqt4-opengl-dev g++ libncurses5-dev luajit libluajit-5.1-dev liblua5.1-0-dev #llvm-3.5 clang-3.5 libclang-3.5-dev llvm-3.5-dev libbullet-dev
        sudo sed -i "s,# deb-src,deb-src,g" /etc/apt/sources.list
        sudo apt-get build-dep bullet
        BUILD_BULLET=true
    ;;

    "fedora" )
        echo -e "You seem to be running Fedora"
        echo -e "\nFedora users are required to enable the RPMFusion FREE and NON-FREE repositories\nhttps://wiki.openmw.org/index.php?title=Development_Environment_Setup#Fedora_Workstation\n\nType YES if you want the script to do it automatically\nIf you already have it enabled or want to do it manually,\npress ENTER to continue"
        read INPUT
        if [ "$INPUT" == "YES" ]; then
              echo -e "\nEnabling RPMFusion..."
              su -c 'dnf install http://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm http://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm'
              echo -e "Done!"
        fi
        sudo dnf --refresh groupinstall development-tools
        sudo dnf --refresh install unzip wget cmake openal-devel OpenSceneGraph-qt-devel SDL2-devel qt5-devel boost-filesystem git boost-thread boost-program-options boost-system ffmpeg-devel ffmpeg-libs bullet-devel gcc-c++ mygui-devel unshield-devel tinyxml-devel cmake ncurses-c++-libs ncurses-devel luajit-devel #llvm35 llvm clang ncurses
        BUILD_BULLET=true
    ;;

    *)
        echo -e "Your GNU/Linux distro is not supported yet, press ENTER to continue without installing dependency packages"
        read
    ;;
  esac
  fi

  #CHECK IF GCC HAS C++14 SUPPORT, DISPLAY A MESSAGE AND ABORT OTHERWISE
  echo -e "\n>> Checking if the compiler has the necessary features"
  GCCVERSION=$(gcc -dumpversion)
  GCCVERSION_F=$(echo $GCCVERSION | sed -e 's/\.\([0-9][0-9]\)/\1/g' -e 's/\.\([0-9]\)/0\1/g' -e 's/^[0-9]\{3,4\}$$/&00/')
  GCCVERSION_P=$((${GCCVERSION_F}*(10**(5-${#GCCVERSION_F}))))
  if [ $GCCVERSION_P -lt 60100 ]; then
    echo -e "\nTES3MP requires some fairly recent C++ features.\nCurrent GCC version is $GCCVERSION.\nUpdate GCC to at least version 6.1 to proceed.\n\nOnly upgrade your toolchain if you know what you are doing.\nProceed at your own risk."
    exit 1
  fi

  #AVOID SOME DEPENDENCIES ON SERVER ONLY MODE
  if [ $SERVER_ONLY ]; then
    BUILD_OSG=""
    BUILD_BULLET=""
  fi

  #PULL SOFTWARE VIA GIT
  echo -e "\n>> Downloading software"
  ! [ -e "$CODE" ] && git clone https://github.com/TES3MP/openmw-tes3mp.git "$CODE"
  ! [ -e "$DEPENDENCIES/"callff ] &&git clone https://github.com/Koncord/CallFF "$DEPENDENCIES/"callff --depth 1
  if [ $BUILD_OSG ] && ! [ -e "$DEPENDENCIES"/osg ] ; then git clone https://github.com/openscenegraph/OpenSceneGraph.git "$DEPENDENCIES"/osg --depth 1; fi
  if [ $BUILD_BULLET ] && ! [ -e "$DEPENDENCIES"/bullet ]; then git clone https://github.com/bulletphysics/bullet3.git "$DEPENDENCIES"/bullet; fi # cannot --depth 1 because we check out specific revision
  ! [ -e "$DEPENDENCIES"/raknet ] && git clone https://github.com/TES3MP/RakNet.git "$DEPENDENCIES"/raknet --depth 1
  ! [ -e "$KEEPERS"/CoreScripts ] && git clone https://github.com/TES3MP/CoreScripts.git "$KEEPERS"/CoreScripts

  #COPY STATIC SERVER AND CLIENT CONFIGS
  echo -e "\n>> Copying server and client configs to their permanent place"
  cp "$CODE"/files/tes3mp/tes3mp-{client,server}-default.cfg "$KEEPERS"

  #SET home VARIABLE IN tes3mp-server-default.cfg
  echo -e "\n>> Autoconfiguring"
  sed -i "s|home = .*|home = $KEEPERS/CoreScripts|g" "${KEEPERS}"/tes3mp-server-default.cfg

  #DIRTY HACKS
  echo -e "\n>> Applying some dirty hacks"
  sed -i "s|tes3mp.lua,chat_parser.lua|server.lua|g" "${KEEPERS}"/tes3mp-server-default.cfg #Fixes server scripts

  #BUILD CALLFF
  echo -e "\n>> Building CallFF"
  mkdir -p "$DEPENDENCIES"/callff/build
  cd "$DEPENDENCIES"/callff/build
  cmake ..
  make -j$CORES

  cd "$BASE"

  #BUILD OPENSCENEGRAPH
  if [ $BUILD_OSG ]; then
      echo -e "\n>> Building OpenSceneGraph"
      mkdir -p "$DEPENDENCIES"/osg/build
      cd "$DEPENDENCIES"/osg/build
      git checkout tags/OpenSceneGraph-3.4.0
      rm -f CMakeCache.txt
      cmake ..
      make -j$CORES

      cd "$BASE"
  fi

  #BUILD BULLET
  if [ $BUILD_BULLET ]; then
      echo -e "\n>> Building Bullet Physics"
      mkdir -p "$DEPENDENCIES"/bullet/build
      cd "$DEPENDENCIES"/bullet/build
      git checkout tags/2.86
      rm -f CMakeCache.txt
      cmake -DCMAKE_INSTALL_PREFIX="$DEPENDENCIES"/bullet/install -DBUILD_SHARED_LIBS=1 -DINSTALL_LIBS=1 -DINSTALL_EXTRA_LIBS=1 -DCMAKE_BUILD_TYPE=Release ..
      make -j$CORES

      make install

      cd "$BASE"
  fi

  #BUILD RAKNET
  echo -e "\n>> Building RakNet"
  mkdir -p "$DEPENDENCIES"/raknet/build
  cd "$DEPENDENCIES"/raknet/build

  # Compatibility hack for 0.6.2, please remove once stable becomes 0.6.3
  if [[ "$TARGET_COMMIT" == "0.6.2" || "$TARGET_COMMIT" == "stable" || "$TARGET_COMMIT" == "" ]]; then
    git fetch --unshallow | true
    git checkout 1d6bb9e88db04aaeaa8752835c17574509d05a31
  fi

  rm -f CMakeCache.txt
  cmake -DCMAKE_BUILD_TYPE=Release -DRAKNET_ENABLE_DLL=OFF -DRAKNET_ENABLE_SAMPLES=OFF -DRAKNET_ENABLE_STATIC=ON -DRAKNET_GENERATE_INCLUDE_ONLY_DIR=ON ..
  make -j$CORES

  ln -sf "$DEPENDENCIES"/raknet/include/RakNet "$DEPENDENCIES"/raknet/include/raknet #Stop being so case sensitive

  cd "$BASE"

  #BUILD THE STABLE BRANCH IF NO TARGET COMMIT IS SPECIFIED
  if [ ! $BUILD_COMMIT ]; then
    echo -e "\n>> Switching to the STABLE branch."
    BUILD_COMMIT=true
    TARGET_COMMIT="stable"

    #SWITCH TO THE STABLE BRANCH ON CORESCRIPTS AS WELL
    cd "$KEEPERS"/CoreScripts
    git stash
    git pull
    git checkout "$TES3MP_STABLE_VERSION"
    cd "$BASE"

    #HANDLE VERSION FILE
    HANDLE_VERSION_FILE=true
  fi

fi

#CHECK THE REMOTE REPOSITORY FOR CHANGES
if [ $UPGRADE ]; then

  #CHECK IF THERE ARE CHANGES IN THE GIT REMOTE
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

  #CHECK IF THERE ARE CHANGES IN THE CORESCRIPTS GIT REMOTE
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

  #AUTOMATICALLY UPGRADE IF THERE ARE GIT CHANGES
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

#CORESCRIPTS HANDLING (Hack, please make me more elegant later :( )
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

#REBUILD TES3MP
if [ $REBUILD ]; then

  #CHECK WHICH DEPENDENCIES ARE PRESENT
  if [ -d "$DEPENDENCIES"/osg ]; then
    BUILD_OSG=true
  fi
  if [ -d "$DEPENDENCIES"/bullet ]; then
    BUILD_BULLET=true
  fi

  #SWITCH TO A SPECIFIC COMMIT
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

  #CHANGE VERSION STRING
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

    #PULL CODE CHANGES FROM THE GIT REPOSITORY
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
      -DCallFF_INCLUDES="${CALLFF_LOCATION}"/include \
      -DCallFF_LIBRARY="${CALLFF_LOCATION}"/build/src/libcallff.a \
      -DRakNet_INCLUDES="${RAKNET_LOCATION}"/include \
      -DRakNet_LIBRARY_DEBUG="${RAKNET_LOCATION}"/build/lib/libRakNetLibStatic.a \
      -DRakNet_LIBRARY_RELEASE="${RAKNET_LOCATION}"/build/lib/libRakNetLibStatic.a"

  if [ $BUILD_OSG ]; then
    CMAKE_PARAMS="$CMAKE_PARAMS \
      -DOPENTHREADS_INCLUDE_DIR="${OSG_LOCATION}"/include \
      -DOPENTHREADS_LIBRARY="${OSG_LOCATION}"/build/lib/libOpenThreads.so \
      -DOSG_INCLUDE_DIR="${OSG_LOCATION}"/include \
      -DOSG_LIBRARY="${OSG_LOCATION}"/build/lib/libosg.so \
      -DOSGANIMATION_INCLUDE_DIR="${OSG_LOCATION}"/include \
      -DOSGANIMATION_LIBRARY="${OSG_LOCATION}"/build/lib/libosgAnimation.so \
      -DOSGDB_INCLUDE_DIR="${OSG_LOCATION}"/include \
      -DOSGDB_LIBRARY="${OSG_LOCATION}"/build/lib/libosgDB.so \
      -DOSGFX_INCLUDE_DIR="${OSG_LOCATION}"/include \
      -DOSGFX_LIBRARY="${OSG_LOCATION}"/build/lib/libosgFX.so \
      -DOSGGA_INCLUDE_DIR="${OSG_LOCATION}"/include \
      -DOSGGA_LIBRARY="${OSG_LOCATION}"/build/lib/libosgGA.so \
      -DOSGPARTICLE_INCLUDE_DIR="${OSG_LOCATION}"/include \
      -DOSGPARTICLE_LIBRARY="${OSG_LOCATION}"/build/lib/libosgParticle.so \
      -DOSGTEXT_INCLUDE_DIR="${OSG_LOCATION}"/include \
      -DOSGTEXT_LIBRARY="${OSG_LOCATION}"/build/lib/libosgText.so\
      -DOSGUTIL_INCLUDE_DIR="${OSG_LOCATION}"/include \
      -DOSGUTIL_LIBRARY="${OSG_LOCATION}"/build/lib/libosgUtil.so \
      -DOSGVIEWER_INCLUDE_DIR="${OSG_LOCATION}"/include \
      -DOSGVIEWER_LIBRARY="${OSG_LOCATION}"/build/lib/libosgViewer.so"
  fi

  if [ $BUILD_BULLET ]; then
    CMAKE_PARAMS="$CMAKE_PARAMS \
      -DBullet_INCLUDE_DIR="${BULLET_LOCATION}"/install/include/bullet \
      -DBullet_BulletCollision_LIBRARY="${BULLET_LOCATION}"/install/lib/libBulletCollision.so \
      -DBullet_LinearMath_LIBRARY="${BULLET_LOCATION}"/install/lib/libLinearMath.so"
    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH":"${BULLET_LOCATION}"/install/lib
    export BULLET_ROOT="${BULLET_LOCATION}"/install
  fi

  if [ $SERVER_ONLY ]; then
    CMAKE_PARAMS="$CMAKE_PARAMS \
      -DBUILD_OPENMW_MP=ON \
      -DBUILD_BROWSER=OFF \
      -DBUILD_BSATOOL=OFF \
      -DBUILD_ESMTOOL=OFF \
      -DBUILD_ESSIMPORTER=OFF \
      -DBUILD_LAUNCHER=OFF \
      -DBUILD_MWINIIMPORTER=OFF \
      -DBUILD_MYGUI_PLUGIN=OFF \
      -DBUILD_OPENMW=OFF \
      -DBUILD_WIZARD=OFF"
  fi

  if [ $BUILD_MASTER ]; then
    CMAKE_PARAMS="$CMAKE_PARAMS \
      -DBUILD_MASTER=ON"
  fi

  if [ $DEBUG_SYMBOLS ]; then
    CMAKE_PARAMS="$CMAKE_PARAMS \
      -DCMAKE_BUILD_TYPE=Debug"
  fi

  if [ $CMAKE_LOCAL ]; then
    CMAKE_PARAMS="$CMAKE_PARAMS \
      -DCMAKE_LIBRARY_PATH=/usr/local/lib64 \
      -DBOOST_ROOT=/usr/local \
      -DBoost_NO_SYSTEM_PATHS=ON"
  fi

  echo -e "\n\n$CMAKE_PARAMS\n\n"
  cmake "$CODE" $CMAKE_PARAMS || true
  set -o pipefail # so that the "tee" below would not make build always return success
  make -j $CORES 2>&1 | tee "${BASE}"/build.log

  cd "$BASE"

  #CREATE SYMLINKS FOR THE CONFIG FILES INSIDE THE NEW BUILD FOLDER
  echo -e "\n>> Creating symlinks of the config files in the build folder"
  for file in "$KEEPERS"/*.cfg
  do
    FILEPATH=$file
    FILENAME=$(basename $file)
    mv "$DEVELOPMENT/$FILENAME" "$DEVELOPMENT/$FILENAME.bkp" 2> /dev/null
    ln -sf "../keepers/$FILENAME" "$DEVELOPMENT/"
  done

  #CREATE SYMLINKS FOR RESOURCES INSIDE THE CONFIG FOLDER
  echo -e "\n>> Creating symlinks for resources inside the config folder"
  ln -sf ../"$(basename $DEVELOPMENT)"/resources "$KEEPERS"/resources 2> /dev/null

  #CREATE USEFUL SHORTCUTS ON THE BASE DIRECTORY
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

  #HANDLE VERSION FILE
  if [ $HANDLE_VERSION_FILE ]; then
    echo -e "\n>> Linking persistent version file"
    rm "$DEVELOPMENT"/resources/version
    ln -sf "$KEEPERS"/version "$DEVELOPMENT"/resources/version
  fi

  #ALL DONE
  echo -e "\n\n\nAll done! Press any key to exit.\nMay Vehk bestow his blessing upon your Muatra."

fi

#MAKE PORTABLE PACKAGE
if [ $MAKE_PACKAGE ]; then
  echo -e "\n>> Creating TES3MP package"

  PACKAGE_BINARIES=("tes3mp" "tes3mp-browser" "tes3mp-server" "openmw-launcher" "openmw-wizard" "openmw-essimporter" "openmw-iniimporter" "bsatool" "esmtool")
  LIBRARIES_OPENMW=("libavcodec.so" "libavformat.so" "libavutil.so" "libboost_filesystem.so" "libboost_program_options.so" "libboost_system.so" "libboost_thread.so" "libBulletCollision.so" "libbz2.so" "libLinearMath.so" "libMyGUIEngine.so" "libopenal.so" "libOpenThreads.so" "libosgAnimation.so" "libosgDB.so" "libosgFX.so" "libosgGA.so" "libosgParticle.so" "libosg.so" "libosgText.so" "libosgUtil.so" "libosgViewer.so" "libosgWidget.so" "libSDL2" "libswresample.so" "libswscale.so" "libts.so" "libtxc_dxtn.so" "libunshield.so" "libuuid.so" "osgPlugins") #"libfreetype.so"
  LIBRARIES_TES3MP=("libcallff.a" "libRakNetLibStatic.a" "libtinfo.so")
  LIBRARIES_EXTRA=("libpng16.so" "libpng12.so") #"libstdc++.so.6"
  LIBRARIES_SERVER=("libboost_system.so" "libboost_filesystem.so" "libboost_program_options.so")

  #EXIT IF TES3MP hasn't been compiled yet
  if [[ ! -f "$DEVELOPMENT"/tes3mp && ! -f "$DEVELOPMENT"/tes3mp-server ]]; then
    echo -e "\nTES3MP has to be built before packaging"
    exit 1
  fi

  #COPY THE ENTIRE BUILD FOLDER FOR PACKAGING
  cp -r "$DEVELOPMENT" "$PACKAGE_TMP"

  #COPY THE PERSISTENT VERSION FILE AS WELL
  if [ $HANDLE_VERSION_FILE ]; then
    rm -f "$PACKAGE_TMP"/resources/version
    cp -fn "$KEEPERS"/version "$PACKAGE_TMP"/resources/version
  fi

  cd "$PACKAGE_TMP"

  #CLEANUP UNNEEDED FILES
  echo -e "\nCleaning up unneeded files"
  find "$PACKAGE_TMP" -type d -name "CMakeFiles" -exec rm -rf "{}" \; || true
  #find "$PACKAGE_TMP" -type d -name ".git" -exec rm -rf "{}" \; || true
  find "$PACKAGE_TMP" -type l -exec rm -f "{}" \; || true
  rm -f "$PACKAGE_TMP"/{Make*,CMake*,*cmake}
  rm -f "$PACKAGE_TMP"/{*.bkp,*.desktop,*.xml}
  rm -rf "$PACKAGE_TMP"/{apps,components,docs,extern,files}

  #COPY USEFUL FILES
  echo -e "\nCopying useful files"
  cp -r "$KEEPERS"/{CoreScripts,*.cfg} .
  sed -i "s|home = .*|home = ./CoreScripts|g" "${PACKAGE_TMP}"/tes3mp-server-default.cfg

  #COPY WHATEVER EXTRA FILES ARE CURRENTLY PRESENT
  if [ -d "$EXTRA" ]; then
    echo -e "\nCopying some extra files"
    cp -rfn --preserve=links "$EXTRA"/* "$PACKAGE_TMP"/
  fi

  #LIST AND COPY ALL LIBS
  mkdir -p lib
  echo -e "\nCopying needed libraries"

  LIBRARIES=("${LIBRARIES_OPENMW[@]}" "${LIBRARIES_TES3MP[@]}" "${LIBRARIES_EXTRA[@]}")
  if [ $SERVER_ONLY ]; then LIBRARIES=("${LIBRARIES_SERVER[@]}"); fi

  for LIB in "${LIBRARIES[@]}"; do
    find /lib /usr/lib /usr/local/lib /usr/local/lib64 "$DEPENDENCIES" -name "$LIB*" -exec cp -r --preserve=links "{}" ./lib \; 2> /dev/null || true
    echo -ne "$LIB\033[0K\r"
  done

  #MAKE SURE ALL SYMLINKS ARE RELATIVE
  echo -e "\nMaking sure all symlinks are relative"
  find ./lib -type l | while read LINK; do
    LINK_BASENAME="$(basename $LINK)"
    LINK_TARGET="$(readlink -f $LINK)"
    LINK_TARGET_BASENAME="$(basename $LINK_TARGET)"
    ln -sf ./"$LINK_TARGET_BASENAME" ./lib/"$LINK_BASENAME"
    echo -ne "$LINK\033[0K\r"
  done

  #PACKAGE INFO

  PACKAGE_PREFIX="tes3mp"
  if [ $SERVER_ONLY ]; then
    PACKAGE_PREFIX="$PACKAGE_PREFIX-server"
  fi

  PACKAGE_ARCH=$(uname -m)
  PACKAGE_SYSTEM=$(uname -o  | sed 's,/,+,g')
  PACKAGE_DISTRO=$(lsb_release -si)
  PACKAGE_VERSION=$(cat "$CODE"/components/openmw-mp/Version.hpp | grep TES3MP_VERSION | awk -F'"' '{print $2}')
  PACKAGE_COMMIT=$(git --git-dir=$CODE/.git rev-parse @ | head -c10)
  PACKAGE_COMMIT_SCRIPTS=$(git --git-dir=$KEEPERS/CoreScripts/.git rev-parse @ | head -c10)

  PACKAGE_NAME="$PACKAGE_PREFIX-$PACKAGE_SYSTEM-$PACKAGE_ARCH-release-$PACKAGE_VERSION-$PACKAGE_COMMIT-$PACKAGE_COMMIT_SCRIPTS"
  PACKAGE_DATE="$(date +"%Y-%m-%d")"

  echo -e "TES3MP $PACKAGE_VERSION ($PACKAGE_COMMIT $PACKAGE_COMMIT_SCRIPTS) built on $PACKAGE_SYSTEM $PACKAGE_ARCH ($PACKAGE_DISTRO) on $PACKAGE_DATE by $USER ($HOSTNAME)" > "$PACKAGE_TMP"/tes3mp-package-info.txt

  #CREATE PRE-LAUNCH SCRIPT
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
        if [[ -d "$TES3MP_HOME"/CoreScripts ]]; then
            echo -e "Loading CoreScripts folder from the home directory"
        else
            echo -e "CoreScripts folder not found in home directory, copying from package directory"
            cp -rf "$GAMEDIR"/CoreScripts/ "$TES3MP_HOME"/
            sed -i "s|home = .*|home = $TES3MP_HOME/CoreScripts |g" "$TES3MP_HOME"/tes3mp-server.cfg
        fi
        #if [[ -e "$TES3MP_HOME"/resources ]]; then
        #    echo -e "Loading resources folder from the home directory"
        #else
        #    echo -e "Resources folder not found in home directory, linking from package directory"
        #    ln -sf "$GAMEDIR"/resources "$TES3MP_HOME"/
        #fi
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

  #CREATE WRAPPERS
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

  #CREATE ARCHIVE
  echo -e "\nCreating archive"

  PACKAGE_FOLDER="TES3MP"
  if [ $SERVER_ONLY ]; then PACKAGE_FOLDER="$PACKAGE_FOLDER-server"; fi

  mv "$PACKAGE_TMP" "$BASE"/"$PACKAGE_FOLDER"
  PACKAGE_TMP="$BASE"/"$PACKAGE_FOLDER"
  tar cvzf "$BASE"/package.tar.gz --directory="$BASE" "$PACKAGE_FOLDER"/

  #RENAME ARCHIVE
  mv "$BASE"/package.tar.gz "$BASE"/"$PACKAGE_NAME".tar.gz

  #CLEANUP TEMPORARY FOLDER AND FINISH
  rm -rf "$PACKAGE_TMP"
  echo -e "\n>> Package created as \"$PACKAGE_NAME\""

  cd "$BASE"
fi
