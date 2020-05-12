
yell() { echo "$0: $*" >&2; }
die() { yell "$*"; exit 111; }
try() { "$@" >>$rootdir/build-osx.log 2>&1 || die "command $* failed see build-osx.log"; }

# get the current working directory
rootdir=$(pwd)
# clear the log file
echo "" >build-osx.log

#
# Build the restclient-cpp for OSX
#
echo Building OSX version of restclient-cpp
cd restclient-cpp
try mkdir -p build/OSX/
try cd build/OSX
try cmake -GXcode -DCMAKE_INSTALL_PREFIX=../../Lib/OSX -DCMAKE_LIBRARY_OUTPUT_DIRECTORY=../../Lib/OSX ../../
try xcodebuild -configuration Debug
try mv ../../Lib/OSX/Debug//librestclient-cppd.dylib ../../Lib/OSX/Debug/librestclient-cpp.dylib
try xcodebuild -configuration Release
