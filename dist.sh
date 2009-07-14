set -o errexit
rm -r build
xcodebuild -configuration Release -project Audioscrobbler.xcodeproj
rm -rf /Applications/Audioscrobbler.app
killall Audioscrobbler
mv build/Release/Audioscrobbler.app /Applications
open /Applications/Audioscrobbler.app
