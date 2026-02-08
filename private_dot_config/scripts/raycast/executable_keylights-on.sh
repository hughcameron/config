#!/bin/zsh

# @raycast.title Keylights On
# @raycast.author Hugh Cameron
# @raycast.authorURL https://github.com/hughcameron
# @raycast.description Switch on Elgato Key Lights

# @raycast.icon images/elgato.png
# @raycast.mode silent
# @raycast.packageName Shooting
# @raycast.schemaVersion 1

curl --request PUT \
    --url http://192.168.1.247:9123/elgato/lights \
    --header 'Accept: application/json' \
    --header 'Content-Type: application/json' \
    --data '{
      "numberOfLights": 1,
      "lights": [
          {
              "on": 1,
              "brightness": 20,
              "temperature": 300
          }
      ]
  }'
  
  curl --request PUT \
    --url http://192.168.1.246:9123/elgato/lights \
    --header 'Accept: application/json' \
    --header 'Content-Type: application/json' \
    --data '{
      "numberOfLights": 1,
      "lights": [
          {
              "on": 1,
              "brightness": 20,
              "temperature": 300
          }
      ]
  }'