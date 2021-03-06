#!/bin/bash -e

module purge
module load git/2.8.3 cmake/3.10.2
module load mpi/mpich-3.2-x86_64 boost/1.65.1-gcc8.2.0-debug gcc/8.2.0

ARGS=$@
FILENAME=$0
NUM_JOBS=`grep -c ^processor /proc/cpuinfo`

while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
        -b|--build)
            COMMAND="build"
            BUILD_TYPE="${2^}"
            shift
            shift
            ;;
        -br|--branch)
            BRANCH="$2"
            shift
            shift
            ;;
        -c|--clean)
            COMMAND="clean"
            BUILD_TYPE="${2^}"
            shift
            shift
            ;;
        --cinch-branch)
            CINCH_BRANCH="$2"
            shift
            shift
            ;;
        --cinch-remote)
            CINCH_REMOTE="$2"
            shift
            shift
            ;;
        --cinch-remote-url)
            CINCH_REMOTE_URL="$2"
            shift
            shift
            ;;
        -dc|--distclean)
            COMMAND="distclean"
            BUILD_TYPE="${2^}"
            shift
            shift
            ;;
        --flecsi-remote)
            FLECSI_REMOTE="$2"
            shift
            shift
            ;;
        --flecsi-remote-url)
            FLECSI_REMOTE_URL="$2"
            shift
            shift
            ;;
        --help)
            help
            exit 0
            shift
            ;;
        --hpx-path)
            HPX_CMAKE_PATH="$2"
            shift
            shift
            ;;
        -i|--install)
            COMMAND="install"
            BUILD_TYPE="${2^}"
            shift
            shift
            ;;
        -j|--jobs)
            NUM_JOBS=$2
            shift
            shift
            ;;
        --log)
            LOG=true
            shift
            ;;
        -p|--pull)
            PULL=true
            shift
            ;;
        --pull-cinch)
            CINCH_PULL=true
            shift
            ;;
        --prefix)
            INSTALL_PATH="$2"
            shift
            shift
            ;;
        -q|--quick)
            QUICK_BUILD=true
            shift
            ;;
        --src-path)
            SRC_PATH="$2"
            shift
            shift
            ;;
        --test)
            TEST=true
            shift
            ;;
        *) echo "Invalid argument: $1"
            exit -1
            ;;
    esac
done

if [ "$QUICK_BUILD" = true ]; then
    BRANCH='feature/hpx/hpx_backend_rebooted'
    FLECSI_REMOTE='origin'
    CINCH_REMOTE='origin'
    CINCH_BRANCH='fix/boost'
    BUILD_TYPE='Debug'
    COMMAND='install'
fi

if [ -z "$SRC_PATH" ]; then
    SRC_PATH=/home/$USER/src/repos
fi

if [ -z "$INSTALL_PATH" ]; then
    INSTALL_ROOT=/home/$USER/src/install
    INSTALL_PATH=$INSTALL_ROOT/flecsi_$BUILD_TYPE
fi

if [ -z "$HPX_CMAKE_PATH" ]; then
    HPX_CMAKE_PATH=$INSTALL_ROOT/flecsi-third-party_$BUILD_TYPE/lib/cmake/HPX/
fi

FLECSI_PATH=$SRC_PATH/flecsi
BUILD_PATH=$FLECSI_PATH/build_$BUILD_TYPE
INSTALL_PATH=$INSTALL_ROOT/flecsi_$BUILD_TYPE

if [ "$BUILD_TYPE" != "Debug" ] && [ "$BUILD_TYPE" != "Release" ] && [ "$BUILD_TYPE" != "RelWithDebInfo" ]; then
    echo "Invalid build type '$BUILD_TYPE'. Please pick one of the following build types:"
    echo "$FILENAME $COMMAND [Debug, Release, RelWithDebInfo]"
    exit -1
fi

clean_flecsi()
{
    cd $BUILD_PATH
    echo "Running 'make clean' in $BUILD_PATH"
    make clean
}


distclean_flecsi()
{
    echo "Removing $BUILD_PATH"
    rm -rf $BUILD_PATH
    echo "Removing $INSTALL_PATH"
    rm -rf $INSTALL_PATH
}

setup_src()
{
    cd $SRC_PATH
    
    if [ ! -d $FLECSI_PATH ]; then
        git clone --recursive https://github.com/laristra/flecsi.git $FLECSI_PATH
    fi

    cd $FLECSI_PATH
    if [ ! -z $FLECSI_REMOTE_URL ]; then
        git remote add $FLECSI_REMOTE $FLECSI_REMOTE_URL
    fi
    if [ ! -z $BRANCH ]; then
        if [ ! -z $FLECSI_REMOTE ]; then
            git fetch $FLECSI_REMOTE
        fi
        git checkout $BRANCH
    fi
    if [ "$PULL" = true ]; then
        git pull
    fi

    cd cinch
    if [ ! -z $CINCH_REMOTE_URL ]; then
        git remote add $CINCH_REMOTE $CINCH_REMOTE_URL
    fi
    if [ ! -z $CINCH_BRANCH ]; then
        if [ ! -z $CINCH_REMOTE ]; then
            git fetch $CINCH_REMOTE
        fi
        git checkout $CINCH_BRANCH
    fi
    if [ "$CINCH_PULL" = true ]; then
        git pull
    fi
}

build_flecsi()
{
    mkdir -p "$BUILD_PATH"
    cd "$BUILD_PATH"
    unbuffer cmake \
        -DENABLE_METIS=ON                                                          \
        -DENABLE_PARMETIS=ON                                                       \
        -DENABLE_COLORING=ON                                                       \
        -DENABLE_UNIT_TESTS=ON                                                     \
        -DENABLE_DEVEL_TARGETS=ON                                                  \
        -DHPX_DIR=$HPX_CMAKE_PATH                                                  \
        -DFLECSI_RUNTIME_MODEL=hpx                                                 \
        -DCMAKE_BUILD_TYPE=$BUILD_TYPE                                             \
        -DCMAKE_INSTALL_PREFIX=$INSTALL_PATH                                       \
        -DCMAKE_PREFIX_PATH=/home/$USER/src/install/flecsi-third-party_$BUILD_TYPE \
        -DBOOST_ROOT=/opt/boost/1.65.1-gcc8.2.0/debug/                             \
        -DBoost_DIR=/opt/boost/1.65.1-gcc8.2.0/debug/                              \
        -DBoost_NO_SYSTEM_PATHS=ON                                                 \
        -DBoost_DEBUG=ON                                                           \
        -DBoost_REALPATH=ON                                                        \
        -Wdev                                                                      \
        $FLECSI_PATH
    
    unbuffer make -j $NUM_JOBS
}

install_flecsi()
{
    build_flecsi
    cd $BUILD_PATH
    unbuffer make -j $NUM_JOBS install
}

test_flecsi()
{
    build_flecsi
    cd $BUILD_PATH
    unbuffer make -j $NUM_JOBS test
}

# Get on the correct branch on flecsi and cinch.
setup_src

# If the log option is set, log the build environment and the corresponding repos.
if [ "$LOG" = true ]; then
    LOG_DIR="/home/$USER/src/logs/flecsi"
    LOG_FILE=$LOG_DIR/"`date +%F-%H-%M`.txt"

    echo 2>&1 | tee -a $LOG_FILE
    echo "Modules" 2>&1 | tee -a $LOG_FILE
    echo "-------------------------------------------------------------------------" 2>&1 | tee -a $LOG_FILE
    module list 2>&1 | tee -a $LOG_FILE
    echo "-------------------------------------------------------------------------" 2>&1 | tee -a $LOG_FILE

    echo 2>&1 | tee -a $LOG_FILE
    echo "Environment" 2>&1 | tee -a $LOG_FILE
    echo "-------------------------------------------------------------------------" 2>&1 | tee -a $LOG_FILE
    printenv 2>&1 | tee -a $LOG_FILE
    echo "-------------------------------------------------------------------------" 2>&1 | tee -a $LOG_FILE

    echo 2>&1 | tee -a $LOG_FILE
    echo "FleCSI Third Party Git Log" 2>&1 | tee -a $LOG_FILE
    echo "-------------------------------------------------------------------------" 2>&1 | tee -a $LOG_FILE
    git --git-dir $FLECSI_PATH/.git log -1 2>&1 | tee -a $LOG_FILE

    echo 2>&1 | tee -a $LOG_FILE
    echo "FleCSI Third Party Branch"
    echo "-------------------------------------------------------------------------" 2>&1 | tee -a $LOG_FILE
    git --git-dir $FLECSI_PATH/.git branch -vv 2>&1 | tee -a $LOG_FILE
    echo "-------------------------------------------------------------------------" 2>&1 | tee -a $LOG_FILE

    echo 2>&1 | tee -a $LOG_FILE
    echo "Cinch Git Log" 2>&1 | tee -a $LOG_FILE
    echo "-------------------------------------------------------------------------" 2>&1 | tee -a $LOG_FILE
    git --git-dir $FLECSI_PATH/cinch/.git log -1 2>&1 | tee -a $LOG_FILE

    echo 2>&1 | tee -a $LOG_FILE
    echo "Cinch Branch"
    echo "-------------------------------------------------------------------------" 2>&1 | tee -a $LOG_FILE
    git --git-dir $FLECSI_PATH/cinch/.git branch -vv 2>&1 | tee -a $LOG_FILE
    echo "-------------------------------------------------------------------------" 2>&1 | tee -a $LOG_FILE
fi

# Run the command.
if [ "$COMMAND" = "clean" ]; then
    clean_flecsi
fi

if [ "$COMMAND" = "distclean" ]; then
    distclean_flecsi
fi

if [ "$COMMAND" = "build" ]; then
    if ["$LOG" = true]; then
        build_flecsi 2>&1 | tee -a $LOG_FILE
    else
        build_flecsi
    fi
fi

if [ "$COMMAND" = "install" ]; then
    if ["$LOG" = true]; then
        install_flecsi 2>&1 | tee -a $LOG_FILE
    else
        install_flecsi
    fi
fi

if [ "$COMMAND" = "test" ]; then
    if ["$LOG" = true]; then
        test_flecsi 2>&1 | tee -a $LOG_FILE
    else
        test_flecsi
    fi
fi

