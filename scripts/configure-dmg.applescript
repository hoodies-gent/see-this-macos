on run argv
  set mountPoint to item 1 of argv
  set volumeAlias to POSIX file mountPoint as alias
  set backgroundAlias to POSIX file (mountPoint & "/.background/dmg-background.png") as alias

  tell application "Finder"
    set volumeFolder to folder volumeAlias
    open volumeFolder
    set dmgWindow to container window of volumeFolder

    tell dmgWindow
      set current view to icon view
      set toolbar visible to false
      set statusbar visible to false
      set pathbar visible to false
      set bounds to {100, 100, 640, 460}
    end tell

    set viewOptions to icon view options of dmgWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set text size of viewOptions to 14
    set background picture of viewOptions to backgroundAlias

    set position of item "SeeThis.app" of volumeFolder to {140, 180}
    set position of item "Applications" of volumeFolder to {400, 180}

    update volumeFolder without registering applications
    delay 2
    close dmgWindow
  end tell
end run
