#!/bin/bash

# @raycast.title Set Project

# @raycast.icon images/zed.png
# @raycast.mode silent
# @raycast.packageName Project Manager
# @raycast.schemaVersion 1

# @raycast.argument1 { "type": "text", "placeholder": "Directory"}


check_directory() {
    local dir_name=$1
    if [ -d "$HOME/Documents/$dir_name" ]; then
        return 0
    else
        return 1
    fi
}

# Function to open the directory with IDE
open_directory() {
    local dir_name=$1
    zed "$HOME/Documents/$dir_name"
}

# Function to create a new directory
create_directory() {
    local dir_name=$1
    mkdir -p "$HOME/Documents/$dir_name"
    echo "Directory '$dir_name' created in ~/Documents."
    zed "$HOME/Documents/$dir_name"
}

# Main script logic
# read -p "Enter the name of the directory: " dir_name
dir_name=$1

if check_directory "$dir_name"; then
    echo "Directory '$dir_name' found in ~/Documents."
    open_directory "$dir_name"
else
    echo "Directory '$dir_name' not found in ~/Documents."
    create_directory "$dir_name"
fi
