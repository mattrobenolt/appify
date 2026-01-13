#!/bin/bash
# Integration test for appify
# Tests end-to-end app bundle generation

set -e

echo "Building appify..."
zig build

echo ""
echo "Running integration tests..."
echo ""

# Test 1: Basic app creation
echo "Test 1: Basic app bundle creation"
rm -rf /tmp/TestApp.app
./zig-out/bin/appify /bin/echo --name "TestApp" --output /tmp
test -d /tmp/TestApp.app/Contents/MacOS || { echo "FAIL: MacOS directory not created"; exit 1; }
test -f /tmp/TestApp.app/Contents/Info.plist || { echo "FAIL: Info.plist not created"; exit 1; }
test -x /tmp/TestApp.app/Contents/MacOS/TestApp || { echo "FAIL: Launcher script not executable"; exit 1; }
echo "  ✓ App bundle structure created"

# Test 2: Info.plist content
echo "Test 2: Info.plist validation"
grep -q "CFBundleIdentifier" /tmp/TestApp.app/Contents/Info.plist || { echo "FAIL: CFBundleIdentifier missing"; exit 1; }
grep -q "com.appify.testapp" /tmp/TestApp.app/Contents/Info.plist || { echo "FAIL: Bundle ID incorrect"; exit 1; }
grep -q "TestApp" /tmp/TestApp.app/Contents/Info.plist || { echo "FAIL: App name missing"; exit 1; }
echo "  ✓ Info.plist contains required keys"

# Test 3: Launcher script content
echo "Test 3: Launcher script validation"
grep -q "#!/bin/sh" /tmp/TestApp.app/Contents/MacOS/TestApp || { echo "FAIL: Shebang missing"; exit 1; }
grep -q "osascript" /tmp/TestApp.app/Contents/MacOS/TestApp || { echo "FAIL: Activation script missing"; exit 1; }
grep -q "exec /Applications/Ghostty.app/Contents/MacOS/ghostty" /tmp/TestApp.app/Contents/MacOS/TestApp || { echo "FAIL: Ghostty exec missing"; exit 1; }
grep -q "/bin/echo" /tmp/TestApp.app/Contents/MacOS/TestApp || { echo "FAIL: Command missing"; exit 1; }
grep -q "confirm-close-surface=false" /tmp/TestApp.app/Contents/MacOS/TestApp || { echo "FAIL: No-confirm flag missing"; exit 1; }
echo "  ✓ Launcher script contains correct content"

# Test 4: Custom bundle ID
echo "Test 4: Custom bundle ID"
rm -rf /tmp/CustomApp.app
./zig-out/bin/appify /bin/ls --name "CustomApp" --bundle-id "com.test.custom" --output /tmp
grep -q "com.test.custom" /tmp/CustomApp.app/Contents/Info.plist || { echo "FAIL: Custom bundle ID not set"; exit 1; }
echo "  ✓ Custom bundle ID works"

# Test 5: App name with spaces
echo "Test 5: App name with spaces"
rm -rf "/tmp/My App.app"
./zig-out/bin/appify /bin/cat --name "My App" --output /tmp
test -d "/tmp/My App.app/Contents" || { echo "FAIL: App with spaces not created"; exit 1; }
grep -q "My App" "/tmp/My App.app/Contents/Info.plist" || { echo "FAIL: App name with spaces not in plist"; exit 1; }
echo "  ✓ App names with spaces work"

# Test 6: Overwrite existing app
echo "Test 6: Overwrite existing app"
./zig-out/bin/appify /bin/pwd --name "TestApp" --output /tmp
test -d /tmp/TestApp.app || { echo "FAIL: Overwrite failed"; exit 1; }
grep -q "/bin/pwd" /tmp/TestApp.app/Contents/MacOS/TestApp || { echo "FAIL: Overwrite didn't update command"; exit 1; }
echo "  ✓ Overwriting existing app works"

# Cleanup
echo ""
echo "Cleaning up test artifacts..."
rm -rf /tmp/TestApp.app /tmp/CustomApp.app "/tmp/My App.app"

echo ""
echo "✅ All integration tests passed!"
