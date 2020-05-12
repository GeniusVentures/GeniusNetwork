
yell() { echo "$0: $*" >&2; }
die() { yell "$*"; exit 111; }
try() { "$@" >>$rootdir/build-ios.log 2>&1 || die "command $* failed see build-ios.log"; }

# get the current working directory
rootdir=$(pwd)
# clear the log file
echo "" >build-ios.log

#
# Make sure security certificates are installed for signing
#
security import dev-geniusventures-io.cer -A
try security find-identity -p codesigning -v | grep "$CODE_SIGN_IDENTITY"

#
# Build the restclient-cpp for iOS
#
echo 'Building restclient-cpp for iOS'
cd restclient-cpp
try mkdir -p build/iOS/
try cd build/iOS

try cmake -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES="arm64;armv7;armv7s;i386;x86_64" -DCMAKE_INSTALL_PREFIX=../../Lib/iOS/ -DCMAKE_LIBRARY_OUTPUT_DIRECTORY=../../Lib/iOS/ -DCURL_LIBRARY=$PWD/../../../curl-android-ios/prebuilt-with-ssl/iOS/libcurl.a -DCURL_INCLUDE_DIR=../../../curl-android-ios/prebuilt-with-ssl/iOS/include/ -DCMAKE_OSX_DEPLOYMENT_TARGET=9.3 -DCMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=NO -DCMAKE_IOS_INSTALL_COMBINED=YES -G Xcode -DCMAKE_THREAD_LIBS_INIT="-lpthread" -DCMAKE_HAVE_THREADS_LIBRARY=1 -DCMAKE_USE_WIN32_THREADS_INIT=0 -DCMAKE_USE_PTHREADS_INIT=1 _DCMAKE_XCODE_ATTRIBUTE_DEVELOPMENT_TEAM="83VQR9GN26" -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" ../../
try cmake --config Release --target install