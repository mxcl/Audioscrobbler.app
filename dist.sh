rm -r build
xcodebuild -configuration Release -project Audioscrobbler.xcodeproj || exit $?
open build/Release

