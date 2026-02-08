#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Add RMP Item Today
# @raycast.mode silent

# Optional parameters:
# @raycast.icon images/things.png
# @raycast.packageName Things
# @raycast.argument1 { "type": "text", "placeholder": "Title", "percentEncoded": true }

# Documentation:
# @raycast.description Add a new Item in the RMP Area.
# @raycast.author Things
# @raycast.authorURL https://twitter.com/culturedcode/

open "things:///add?title=$1&when=today&list-id=NYAGWtVYqCDAqyBmi8PbKv"
echo "Added Item in RMP"
