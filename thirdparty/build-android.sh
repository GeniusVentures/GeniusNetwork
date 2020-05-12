
yell() { echo "$0: $*" >&2; }
die() { yell "$*"; exit 111; }
try() { "$@" >>$rootdir/build-android.log 2>&1 || die "command $* failed see build-android.log"; }

# get the current working directory
rootdir=$(pwd)
# clear the log file
echo "" >build-android.log

#
# Build the restclient-cpp for Android
#
cd restclient-cpp
echo 'Building restclient-cpp for Android'
for abi in armeabi-v7a arm64-v8a x86 x86_64
do
  echo 'Building restclient-cpp '$abi'...'
  try mkdir -p build/Android/$abi
  try cd build/Android/$abi
  try cmake -DCMAKE_SYSTEM_NAME="Android" -DCMAKE_ANDROID_ARCH_ABI=$abi -DCURL_LIBRARY="../../../../curl-android-ios/prebuilt-with-ssl/android/$abi/libcurl.a" -DCURL_INCLUDE_DIR="../../../../curl-android-ios/prebuilt-with-ssl/android/include" -DCMAKE_LIBRARY_OUTPUT_DIRECTORY=../../../Lib/Android/Release/$abi -DCMAKE_BUILD_TYPE=Release ../../../
  try make
  try cmake -DCMAKE_SYSTEM_NAME="Android" -DCMAKE_ANDROID_ARCH_ABI=$abi -DCURL_LIBRARY="../../../../curl-android-ios/prebuilt-with-ssl/android/$abi/libcurl.a" -DCURL_INCLUDE_DIR="../../../../curl-android-ios/prebuilt-with-ssl/android/include" -DCMAKE_LIBRARY_OUTPUT_DIRECTORY=../../../Lib/Android/Debug/$abi -DCMAKE_BUILD_TYPE=Debug ../../../
  try make
  try mv ../../../Lib/Android/Debug/$abi/librestclient-cppd.so ../../../Lib/Android/Debug/$abi/librestclient-cpp.so
  try cd ../../../
done
