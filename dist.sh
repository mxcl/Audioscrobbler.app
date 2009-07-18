set -o errexit
test -d build && rm -r build
xcodebuild -configuration Release -project Audioscrobbler.xcodeproj
osascript -e 'if application "Audioscrobbler" is running then tell application "Audioscrobbler" to quit'
open build/Release
echo "Replace the old Audioscrobbler.app with this one"
read -p "$*"
open /Applications/Audioscrobbler.app
