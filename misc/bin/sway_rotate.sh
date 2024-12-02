#!/bin/sh

focusedtransform() {
	swaymsg -t get_outputs | jq -r '.[] | select(.focused == true) | .transform'
}

focusedname() {
	swaymsg -t get_outputs | jq -r '.[] | select(.focused == true) | .name'
}

startlisgd() {
  launch_lisgd.sh
	# pkill lisgd || true
	# lisgd -d /dev/input/event6 \
	# 	-o "$1" \
	# 	-g "3,DU,*,*,R,~/.local/bin/toggle_onscreen_keyboard.py" \
	# 	-g "3,UD,*,*,R,refresh_screen" \
	# 	-g "3,LR,*,*,R,~/.local/bin/sway_workspace goto prev" \
	# 	-g "3,RL,*,*,R,~/.local/bin/sway_workspace goto next" \
	# 	-g "4,LR,*,*,R,~/.local/bin/sway_workspace move prev" \
	# 	-g "4,RL,*,*,R,~/.local/bin/sway_workspace move next" \
	# 	-g "4,UD,*,*,R,nwg-menu -fm pcmanfm -term foot -va top -isl 48 &" &
}

rotnormal() {
	swaymsg -- output "-" transform 0 scale 1
	focused_name="$(focusedname)"
	swaymsg -- input type:touch map_to_output "$focused_name"
	swaymsg -- input type:tablet_tool map_to_output "$focused_name"
	startlisgd 0
	exit 0
}

rotleft() {
	swaymsg -- output "-" transform 90 scale 1
	focused_name="$(focusedname)"
	swaymsg -- input type:touch map_to_output "$focused_name"
	swaymsg -- input type:tablet_tool map_to_output "$focused_name"
	startlisgd 3
	exit 0
}

rotright() {
	swaymsg -- output "-" transform 270 scale 1
	focused_name="$(focusedname)"
	swaymsg -- input type:touch map_to_output "$focused_name"
	swaymsg -- input type:tablet_tool map_to_output "$focused_name"
	startlisgd 1
	exit 0
}

rotinvert() {
	swaymsg -- output "-" transform 180 scale 1
	focused_name="$(focusedname)"
	swaymsg -- input type:touch map_to_output "$focused_name"
	swaymsg -- input type:tablet_tool map_to_output "$focused_name"
	startlisgd 2
	exit 0
}

"$@"
