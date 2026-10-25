# dmgbuild settings for the QuickFlow installer image.
#
# Used by package.sh:
#   dmgbuild -s Scripts/dmg_settings.py \
#            -D stage="$STAGE_DIR" \
#            -D background="$PROJECT_DIR/assets/dmg-background.png" \
#            -D volume_icon="$PROJECT_DIR/assets/QuickFlow.icns" \
#            "QuickFlow" dist/QuickFlow-<version>.dmg
#
# The window frame is 600x400 points; the title bar takes 28 pt, so the
# background artwork is 600x372 points (600x372 px at 1x, 1200x744 px @2x --
# dmgbuild combines both into a HiDPI TIFF when the @2x file sits next to it).
# Icon coordinates below are top-left origin, in points, and must stay in sync
# with ICON_ROW_Y in Scripts/make_dmg_background.swift.

import os

# dmgbuild injects the -D values as a `defines` dict before executing this file.
defines = globals().get("defines", {})

stage = defines["stage"]

app_name = "QuickFlow.app"

files = [os.path.join(stage, app_name)]
symlinks = {"Applications": "/Applications"}

background = defines["background"]
volume_icon = defines["volume_icon"]

format = "UDZO"
filesystem = "HFS+"

window_rect = ((240, 180), (600, 400))
default_view = "icon-view"
icon_size = 128

show_icon_preview = False
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_sidebar = False
show_pathbar = False
show_item_info = False

arrange_by = None
grid_offset = (0, 0)
label_pos = "bottom"
text_size = 12
scroll_position = (0, 0)

icon_locations = {
    app_name: (160, 176),
    "Applications": (440, 176),
}
