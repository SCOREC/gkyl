#!/bin/bash

# Defaults
PREFIX=$HOME/gkylsoft

# default build options
CC=gcc
CXX=g++
MPICC=mpicc
MPICXX=mpicxx

# by default, don't build anything. will check later to see if things
# should be installed.
BUILD_GKYLZERO=
BUILD_LUAJIT=
BUILD_LUAROCKS=
BUILD_ADIOS=
BUILD_OPENMPI=
BUILD_ZMQ=
BUILD_CZMQ=

# ----------------------------------------------------------------------------
# FUNCTION DEFINITIONS
# ----------------------------------------------------------------------------

# Help

show_help() {
cat <<EOF

./mkdeps.sh CC=cc CXX=cxx MPICC=mpicc MPICXX=mpicxx

Build Gkyl dependencies. By default, only builds libraries that Gkyl 
needs that haven't yet been built or can't be found.

CC 
CXX
MPICC
MPICXX                      C, C++, MPI C and MPI C++ compilers to use

-h
--help                      This help.
--prefix=DIR                Prefix where dependencies should be installed.
                            Default is $HOME/gkylsoft

The following flags specify which libraries to build. By default, only
builds libraries that haven't yet been built or can't be found. 
If you build libraries that depend on MPI please specify the MPI C 
and C++ compilers to use.

--build-gkylzero            Should we build Gkylzero?
--build-luajit              Should we build LuaJIT?
--build-luajit-beta3        Should we build LuaJIT-beta3?
--build-luajit-ppcle        Should we build LuaJIT for PPC64 LE?
--build-luarocks            Should we build Luarocks?
--build-adios               Should we build ADIOS?
--build-openmpi             Should we build OpenMPI?
--build-zmq                 Should we build ZeroMQ?
--build-czmq                Should we build C interface to ZeroMQ?

The behavior of the flags for library xxx is as follows:
--build-xxx=no              Don't build xxx, even if it can't be found in PREFIXDIR
--build-xxx=yes             Build xxx, no matter what
[no flag specified]         Build xxx only if it can't be found in PREFIXDIR (default)
EOF
}

# Helper functions

find_program() {
   prog=`command -v "$1" 2>/dev/null`
   if [ -n "$prog" ]
   then
      dirname "$prog"
   fi
}

die() {
   echo "$*"
   echo
   echo "Dependency builds failed."
   echo
   exit 1
}

# ----------------------------------------------------------------------------
# MAIN PROGRAM
# ----------------------------------------------------------------------------

# Parse options

while [ -n "$1" ]
do
   value="`echo $1 | sed 's/[^=]*.\(.*\)/\1/'`"
   key="`echo $1 | sed 's/=.*//'`"
   if `echo "$value" | grep "~" >/dev/null 2>/dev/null`
   then
      echo
      echo '*WARNING*: the "~" sign is not expanded in flags.'
      echo 'If you mean the home directory, use $HOME instead.'
      echo
   fi
   case "$key" in
   -h)
      show_help
      exit 0
      ;;
   --help)
      show_help
      exit 0
      ;;
   CC)
      [ -n "$value" ] || die "Missing value in flag $key."
      CC="$value"
      ;;
   CXX)
      [ -n "$value" ] || die "Missing value in flag $key."
      CXX="$value"
      ;;
   MPICC)
      [ -n "$value" ] || die "Missing value in flag $key."
      MPICC="$value"
      ;;
   MPICXX)
      [ -n "$value" ] || die "Missing value in flag $key."
      MPICXX="$value"
      ;;   
   --prefix)
      [ -n "$value" ] || die "Missing value in flag $key."
      PREFIX="$value"
      ;;
   --build-openmpi)
      [ -n "$value" ] || die "Missing value in flag $key."
      BUILD_OPENMPI="$value"
      ;;
   --build-gkylzero)
      [ -n "$value" ] || die "Missing value in flag $key."
      BUILD_GKYLZERO="$value"
      ;;
   --build-luajit)
      [ -n "$value" ] || die "Missing value in flag $key."
      BUILD_LUAJIT="$value"
      ;;
   --build-adios)
      [ -n "$value" ] || die "Missing value in flag $key."
      BUILD_ADIOS="$value"
      ;;
   --build-luarocks)
      [ -n "$value" ] || die "Missing value in flag $key."
      BUILD_LUAROCKS="$value"
      ;;
   --build-czmq)
      [ -n "$value" ] || die "Missing value in flag $key."
      BUILD_CZMQ="$value"
      ;;   
   --build-zmq)
      [ -n "$value" ] || die "Missing value in flag $key."
      BUILD_ZMQ="$value"
      ;;
   *)
      die "Error: Unknown flag: $1"
      ;;
   esac
   shift
done

# if mpicc doesn't work (because it doesn't exist or it's not in path), try to use installed openmpi version
if ! [ -x "$(command -v $MPICC)" ]
then
    MPICC=$PREFIX/openmpi/bin/mpicc
    MPICXX=$PREFIX/openmpi/bin/mpicxx
fi
# if mpicc still doesn't work, force to install openmpi
if ! [ -x "$(command -v $MPICC)" ] 
then
    BUILD_OPENMPI="yes"
fi

# Write out build options for scripts to use
cat <<EOF1 > build-opts.sh
# Generated automatically! Do not edit

# Installation directory
GKYLSOFT=$PREFIX
# Various compilers
CC=$CC
CXX=$CXX
MPICC=$MPICC
MPICXX=$MPICXX

EOF1

build_openmpi() {
    if [ "$BUILD_OPENMPI" = "yes" ]
    then
	echo "Building OpenMPI"
	./build-openmpi.sh
    fi
}

build_gkylzero() {
    if [[ ! "$BUILD_GKYLZERO" = "no" && ("$BUILD_GKYLZERO" = "yes" || ! -f $PREFIX/gkylzero/include/gkylzero.h) ]]
    then   
   echo "Building Gkylzero"
   ./build-gkylzero.sh 
    fi
}

build_luajit() {
    if [[ ! "$BUILD_LUAJIT" = "no" && ("$BUILD_LUAJIT" = "yes" || ! -f $PREFIX/luajit/include/luajit-2.1/lua.hpp) ]]
    then    
   echo "Building LuaJIT"
   ./build-luajit.sh
    fi
}

build_adios() {
    if [[ ! "$BUILD_ADIOS" = "no" && ("$BUILD_ADIOS" = "yes" || ! -f $PREFIX/adios/include/adios.h) ]]
    then    
	echo "Building ADIOS"
	./build-adios.sh
    fi
}

build_luarocks() {
    if [ "$BUILD_LUAROCKS" = "yes" ]
    then    
	echo "Building Luarocks"
	./build-luarocks.sh
    fi
}

build_zmq() {
    if [ "$BUILD_ZMQ" = "yes" ]
    then    
	echo "Building ZMQ"
	./build-zmq.sh
    fi
}

build_czmq() {
    if [ "$BUILD_CZMQ" = "yes" ]
    then    
	echo "Building CZMQ"
	./build-czmq.sh
    fi
}

echo "Installations will be in $PREFIX"

build_openmpi
build_gkylzero
build_luajit
build_luarocks
build_adios
build_zmq
build_czmq
