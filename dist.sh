rm -r build
xcodebuild -configuration Release -project Audioscrobbler.xcodeproj && \
    open build/Release