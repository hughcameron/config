#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Add RMP List Items
# @raycast.mode silent

# Optional parameters:
# @raycast.icon images/things.png
# @raycast.packageName Things

# Documentation:
# @raycast.description Add a new Multiple Items in the RMP Area.
# @raycast.author Things
# @raycast.authorURL https://twitter.com/culturedcode/

IFS=$'\n' read -d '' -r -a lines <<< "$(pbpaste)"
for line in "${lines[@]}"
do
  open "things:///add?title=$line&list-id=NYAGWtVYqCDAqyBmi8PbKv"
done

echo "Created Items in RMP"
