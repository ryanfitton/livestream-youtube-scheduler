#!/usr/bin/env bash

# === VERSIONING ===
# Version: 1.1.0
# Date: 2025-05-29
# Author: Ryan Fitton
# Description: This script automates the creation of a scheduled YouTube livestream using Docker, Go2RTC, and YouTube API.
#
# Changelog:
# - Version 1.0.0 (2025-05-01): Initial release.
# - Version 1.1.0 (2025-05-29): Added support for multiple streams and improved error handling.


#YouTube API credentials - Can be found from the Google Developer Console
CLIENT_ID="YOUR CLIENT ID HERE"
CLIENT_SECRET="YOUR CLIENT SECRET HERE"
REFRESH_TOKEN="YOUR REFRESH TOKEN HERE"


# Docker container and Go2RTC API settings
DOCKER_CONTAINER_NAME="go2rtc"
GO2RTC_API_URL="http://127.0.0.1:1984/api"


# Youtube Livestream Schedules
# This configures the 'Go2RTC Stream name' and scheduled livestreams
# If you're using more than two streams, add more to the variables below
stream_configs=("stream1" "stream2")

# Define stream1 config as array of key=value strings
stream1=(
  "STREAM=birdcam"
  "TIMEZONE=Europe/London"
  "VISIBILITY=private"
  "TITLE='Birdcam live feed for $(date +"%A %d %B")'"
  "DESC='Birdcam live feed for $(date +"%A %d %B"). Streamed 06:30 to 18:00'"
  "THUMBNAIL='/home/user/config/images/youtube_thumbnail_1280x720.png'"
  "START=$(date +%Y-%m-%d)T06:30:00"
  "END=$(date +%Y-%m-%d)T18:00:00"
)


stream2=(
  "STREAM=ipcam"
  "TIMEZONE=Europe/London"
  "VISIBILITY=private"
  "TITLE='IP Camera live feed for $(date +"%A %d %B")'"
  "DESC='IP Camera live feed for $(date +"%A %d %B"). Streamed 09:00 to 13:00'"
  "THUMBNAIL='/home/user/config/images/default-thumbnail.jpg'"
  "START=$(date +%Y-%m-%d)T09:00:00"
  "END=$(date +%Y-%m-%d)T13:00:00"
)