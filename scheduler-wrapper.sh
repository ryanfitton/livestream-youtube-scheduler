#!/bin/bash

# Load configuration
source /home/user/config/config.sh


# === CONFIGURATION ===
# Paths
DOCKER_PATH=$(which docker)
BASH_PATH=$(which bash)


# === DOCKER ===
# Restart the go2rtc service
$DOCKER_PATH restart $DOCKER_CONTAINER_NAME


# === STREAM SCHEDULING ===
# Loop through each config array name
for config_name in "${stream_configs[@]}"; do
    echo "=== $config_name ==="

    # Use indirect expansion to loop over each config's array
    eval "config=(\"\${$config_name[@]}\")"

    # Evaluate each key=value to assign to variables
    for item in "${config[@]}"; do
        eval "$item"
    done

    # Call the actual script with all parameters
    $BASH_PATH /home/user/livestream-youtube-scheduler.sh "$STREAM" "$TITLE" "$DESC" "$THUMBNAIL" "$START" "$END" "$TIMEZONE" "$VISIBILITY"
done