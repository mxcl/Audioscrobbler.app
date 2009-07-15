set -o errexit
rm -r build
xcodebuild -configuration Release -project Audioscrobbler.xcodeproj
test -d /Applications/Audioscrobbler.app && rm -rf /Applications/Audioscrobbler.app
killall Audioscrobbler || true
mv build/Release/Audioscrobbler.app /Applications
open /Applications/Audioscrobbler.app
