rm -r build
xcodebuild -configuration Release -project Audioscrobbler.xcodeproj || exit $?
open build/Release
hdiutil create -srcfolder build/Release/Audioscrobbler.app -format UDZO -imagekey zlib-level=9 -scrub Audioscrobbler.dmg

