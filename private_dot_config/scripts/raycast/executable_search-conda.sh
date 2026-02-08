#!/bin/bash

# @raycast.title Conda Package Search
# @raycast.author Hugh Cameron
# @raycast.authorURL https://github.com/hughcameron
# @raycast.description Search Available Anaconda Packages (cps = Conda Package Search)

# @raycast.icon images/conda.png
# @raycast.mode silent
# @raycast.packageName Web Searches
# @raycast.schemaVersion 1

# @raycast.argument1 { "type": "text", "placeholder": "Title", "percentEncoded": true }

open "https://anaconda.org/search?q=${1}"