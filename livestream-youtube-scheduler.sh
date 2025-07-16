#!/usr/bin/env bash


# Load configuration
source /home/user/config/config.sh


# === CONFIGURATION ===
# Paths
BASH_PATH=$(which bash)
DOCKER_PATH=$(which docker)
CRONTAB_PATH=$(which crontab)

# Retry count for each YouTube API request - Sometimes the API can be slow or unresponsive and we need to retry
RETRY_AMOUNT=5

# Passed Arguments
ARG_STREAM_NAME="$1"    # The stream name defined in go2rtc.yaml e.g. `teststream`
ARG_TITLE="$2"          # The title of the YouTube live stream
ARG_DESCRIPTION="$3"    # The description of the YouTube live stream
ARG_THUMBNAIL="$4"      # The thumbnail of the YouTube live stream

# Define stream Start and End time. Passed in ISO 8601 or another parseable format
ARG_START_TIME="$5"
ARG_END_TIME="$6"

# Set timezone
ARG_TZ="${7:-Europe/London}"  # Default to Europe/London if not provided

# Define stream privacy status. Options: public, unlisted, private
ARG_PRIVACY="${8:-public}"  # Default to public if not provided


# === Step 1: Check required args are passed ===
if [[ -z "$ARG_STREAM_NAME" || -z "$ARG_TITLE" || -z "$ARG_DESCRIPTION" || -z "$ARG_THUMBNAIL" || -z "$ARG_START_TIME" || -z "$ARG_END_TIME" ]]; then
  echo "🚫 Missing required arguments."
  echo "Usage: $0 <stream_name> <title> <description> <thumbnail> <start_time> <end_time> [timezone] [privacy]"
  exit 1
fi


# === Step 2: Verify Docker and container ===
# Check if Docker is installed
if ! command -v $DOCKER_PATH &> /dev/null; then
  echo "🚫 Docker is not installed or not in PATH."
  exit 1
fi

# Check if Docker is running
if ! $DOCKER_PATH info &> /dev/null; then
  echo "🚫 Docker is not running. Please start Docker."
  exit 1
fi

# Check if the Go2Rtc container exists
if ! $DOCKER_PATH ps -a --format '{{.Names}}' | grep -q "^${DOCKER_CONTAINER_NAME}$"; then
  echo "🚫 Docker container '$DOCKER_CONTAINER_NAME' does not exist."
  echo "Creating '$DOCKER_CONTAINER_NAME' ..."
  $DOCKER_PATH run -d \
    --name "$DOCKER_CONTAINER_NAME" \
    --network host \
    --privileged \
    --restart unless-stopped \
    -e TZ="$ARG_TZ" \
    -v /home/user/config/go2rtc:/config \
    -v /home/user/config/images:/images \
    -v /home/user/config/audio:/audio \
    alexxit/go2rtc

  #exit 1
fi

# Start the Go2Rtc docker container
$DOCKER_PATH start "$DOCKER_CONTAINER_NAME"


# === Step 3: Parse start/end times ISO format ===
# Convert to ISO 8601 (UK timezone) and extract cron fields
START_ISO=$(TZ=$ARG_TZ date -d "$ARG_START_TIME" --iso-8601=seconds)
START_MINUTE=$(TZ=$ARG_TZ date -d "$ARG_START_TIME" +%-M)
START_HOUR=$(TZ=$ARG_TZ date -d "$ARG_START_TIME" +%-H)
START_DAY=$(TZ=$ARG_TZ date -d "$ARG_START_TIME" +%-d)
START_MONTH=$(TZ=$ARG_TZ date -d "$ARG_START_TIME" +%-m)

END_ISO=$(TZ=$ARG_TZ date -d "$ARG_END_TIME" --iso-8601=seconds)
END_MINUTE=$(TZ=$ARG_TZ date -d "$ARG_END_TIME" +%-M)
END_HOUR=$(TZ=$ARG_TZ date -d "$ARG_END_TIME" +%-H)
END_DAY=$(TZ=$ARG_TZ date -d "$ARG_END_TIME" +%-d)
END_MONTH=$(TZ=$ARG_TZ date -d "$ARG_END_TIME" +%-m)

# Value to hold retry count for API requests
RETRY_COUNT=0

# === Step 4: Get access token ===
echo "Getting access token..."
ACCESS_TOKEN=""
while [[ $RETRY_COUNT -lt $RETRY_AMOUNT ]]; do
    ((RETRY_COUNT++))
    ACCESS_TOKEN=$(curl -s \
        --request POST \
        --data "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&refresh_token=$REFRESH_TOKEN&grant_type=refresh_token" \
        https://oauth2.googleapis.com/token | jq -r .access_token)
    if [[ -n "$ACCESS_TOKEN" && "$ACCESS_TOKEN" != "null" ]]; then
        echo "Access token obtained successfully."
        RETRY_COUNT=0   # Reset retry count on success
        break
    fi
    echo "Attempt $RETRY_COUNT to get access token failed. Retrying..."
    sleep 2
done
if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
    echo "Failed to get access token after $RETRY_AMOUNT attempts."
    exit 1
fi


# === Step 5: Create Live Broadcast ===
#Docs: https://developers.google.com/youtube/v3/live/docs/liveBroadcasts#properties
#For `latencyPreference` use: `normal`, `low`, `ultraLow`
echo "Creating livestream broadcast..."
BROADCAST_RESPONSE=""
BROADCAST_ID=""
while [[ $RETRY_COUNT -lt $RETRY_AMOUNT ]]; do
    ((RETRY_COUNT++))
    BROADCAST_RESPONSE=$(curl -s -X POST \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d @- https://www.googleapis.com/youtube/v3/liveBroadcasts?part=snippet,status,contentDetails <<EOF
{
  "snippet": {
    "title": "$ARG_TITLE",
    "description": "$ARG_DESCRIPTION",
    "scheduledStartTime": "$START_ISO",
    "scheduledEndTime": "$END_ISO"
  },
  "status": {
    "privacyStatus": "$ARG_PRIVACY",
    "selfDeclaredMadeForKids": false
  },
  "contentDetails": {
    "recordFromStart": true,
    "enableAutoStart": true,
    "enableAutoStop": true,
    "latencyPreference": "ultraLow"
  }
}
EOF
    )
    BROADCAST_ID=$(echo "$BROADCAST_RESPONSE" | jq -r .id)
    if [[ -n "$BROADCAST_ID" && "$BROADCAST_ID" != "null" ]]; then
        echo "Broadcast created: ID = $BROADCAST_ID"
        RETRY_COUNT=0   # Reset retry count on success
        break
    fi
    echo "Attempt $RETRY_COUNT to create broadcast failed. Retrying..."
    sleep 2
done
if [[ -z "$BROADCAST_ID" || "$BROADCAST_ID" == "null" ]]; then
  echo "Failed to create broadcast after $RETRY_AMOUNT attempts:"
  echo "$BROADCAST_RESPONSE"
  exit 1
fi


# === Step 6: Set Thumbnail for the Broadcast ===
echo "Uploading thumbnail..."

THUMBNAIL_RESPONSE=""
RETRY_COUNT=0
while [[ $RETRY_COUNT -lt $RETRY_AMOUNT ]]; do
    ((RETRY_COUNT++))
    THUMBNAIL_RESPONSE=$(curl -s -X POST \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -F "media=@${ARG_THUMBNAIL}" \
      "https://www.googleapis.com/upload/youtube/v3/thumbnails/set?videoId=${BROADCAST_ID}")
    if echo "$THUMBNAIL_RESPONSE" | grep -q '"kind": "youtube#thumbnailSetResponse"'; then
        echo "📷 Thumbnail successfully uploaded."
        RETRY_COUNT=0   # Reset retry count on success
        break
    fi
    echo "Attempt $RETRY_COUNT to upload thumbnail failed. Retrying..."
    sleep 2
done
if ! echo "$THUMBNAIL_RESPONSE" | grep -q '"kind": "youtube#thumbnailSetResponse"'; then
  echo "❌ Failed to upload thumbnail after $RETRY_AMOUNT attempts:"
  echo "$THUMBNAIL_RESPONSE"
fi


# === Step 7: Create a Live Stream ===
echo "Creating livestream encoder..."
STREAM_RESPONSE=""
STREAM_ID=""
STREAM_KEY=""
INGEST_URL=""
RETRY_COUNT=0
while [[ $RETRY_COUNT -lt $RETRY_AMOUNT ]]; do
    ((RETRY_COUNT++))
    STREAM_RESPONSE=$(curl -s -X POST \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d @- https://www.googleapis.com/youtube/v3/liveStreams?part=snippet,cdn <<EOF
{
  "snippet": {
    "title": "Stream for $ARG_TITLE"
  },
  "cdn": {
    "ingestionType": "rtmp",
    "resolution": "1080p",
    "frameRate": "30fps"
  }
}
EOF
    )
    STREAM_ID=$(echo "$STREAM_RESPONSE" | jq -r .id)
    STREAM_KEY=$(echo "$STREAM_RESPONSE" | jq -r .cdn.ingestionInfo.streamName)
    INGEST_URL=$(echo "$STREAM_RESPONSE" | jq -r .cdn.ingestionInfo.ingestionAddress)
    if [[ -n "$STREAM_ID" && "$STREAM_ID" != "null" ]]; then
        echo "Stream created: ID = $STREAM_ID"
        RETRY_COUNT=0   # Reset retry count on success
        break
    fi
    echo "Attempt $RETRY_COUNT to create stream failed. Retrying..."
    sleep 2
done
if [[ -z "$STREAM_ID" || "$STREAM_ID" == "null" ]]; then
  echo "Failed to create stream after $RETRY_AMOUNT attempts:"
  echo "$STREAM_RESPONSE"
  exit 1
fi


# === Step 8: Bind broadcast to stream ===
echo "Binding stream to broadcast..."
BIND_RESPONSE=""
RETRY_COUNT=0
while [[ $RETRY_COUNT -lt $RETRY_AMOUNT ]]; do
    ((RETRY_COUNT++))
    BIND_RESPONSE=$(curl -s -X POST \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      "https://www.googleapis.com/youtube/v3/liveBroadcasts/bind?id=$BROADCAST_ID&part=id,contentDetails&streamId=$STREAM_ID")
    if echo "$BIND_RESPONSE" | grep -q "$BROADCAST_ID"; then
        echo "Stream successfully bound to broadcast!"
        RETRY_COUNT=0   # Reset retry count on success
        break
    fi
    echo "Attempt $RETRY_COUNT to bind stream failed. Retrying..."
    sleep 2
done
if ! echo "$BIND_RESPONSE" | grep -q "$BROADCAST_ID"; then
  echo "Failed to bind stream after $RETRY_AMOUNT attempts:"
  echo "$BIND_RESPONSE"
  exit 1
fi


# === Step 9: Setup Cronjobs ===
if [[ $RETRY_COUNT -eq 0 ]]; then
  echo "No errors found during YouTube API calls, so continuing to create Cronjobs."
fi

# Unique cron job identifiers
CRON_START_JOB_TAG="publish_stream_$(date -d "$ARG_START_TIME" +%s)"
CRON_END_JOB_TAG="end_stream_$(date -d "$ARG_END_TIME" +%s)"

# Paths for temporary Cron scripts
CRON_START_SCRIPT="/tmp/${CRON_START_JOB_TAG}.sh"
CRON_END_SCRIPT="/tmp/${CRON_END_JOB_TAG}.sh"

# Redefine time for cron start datetime. Subtract 5 minutes from the start time.
CRON_START_MINUTE=$((START_MINUTE - 5))
CRON_START_HOUR=$((START_HOUR))
CRON_START_DAY=$((START_DAY))
CRON_START_MONTH=$((START_MONTH))

# If the minute value is less than 0 (e.g., 5 minutes before 00), adjust the hour and minute accordingly
if [[ $CRON_START_MINUTE -lt 0 ]]; then
  CRON_START_MINUTE=$((60 + CRON_START_MINUTE))  # Set minutes to the positive value
  CRON_START_HOUR=$((START_HOUR - 1))  # Decrease hour by 1
  if [[ $CRON_START_HOUR -lt 0 ]]; then
    CRON_START_HOUR=23  # Wrap around to 23 if hour goes below 0
    CRON_START_DAY=$((START_DAY - 1))  # Decrease the day by 1
    # Handle day wrapping with real month-day logic
    if [[ $CRON_START_DAY -lt 1 ]]; then
      CRON_START_MONTH=$((START_MONTH - 1))
      # Handle month transition (simplified, assuming 31 days in each month)
      if [[ $CRON_START_MONTH -lt 1 ]]; then
        CRON_START_MONTH=12  # Wrap to December if the month goes below 1
        CRON_START_DAY=31  # December's 31st
      else
        # Adjust based on month lengths (simplified logic)
        case $CRON_START_MONTH in
          1|3|5|7|8|10|12) CRON_START_DAY=31 ;;  # Months with 31 days
          4|6|9|11) CRON_START_DAY=30 ;;          # Months with 30 days
          2) CRON_START_DAY=28 ;;                 # Simplified February case
        esac
      fi
    fi
  fi
fi

# Format the cron start datetime using the adjusted values
CRON_START_DATETIME="$CRON_START_MINUTE $CRON_START_HOUR $CRON_START_DAY $CRON_START_MONTH *"
#CRON_START_DATETIME="$START_MINUTE $START_HOUR $START_DAY $START_MONTH *"

# Create start script
cat <<EOF > "$CRON_START_SCRIPT"
#!$BASH_PATH

RETRY_AMOUNT=$RETRY_AMOUNT
RETRY_COUNT=0

while [[ \$RETRY_COUNT -lt \$RETRY_AMOUNT ]]; do
  ((RETRY_COUNT++))
  RESPONSE=\$(curl -s -o /dev/null -w "%{http_code}" -X POST "${GO2RTC_API_URL}/streams?src=${ARG_STREAM_NAME}&dst=rtmp://a.rtmp.youtube.com/live2/${STREAM_KEY}")
  if [[ "\$RESPONSE" == "200" || "\$RESPONSE" == "201" ]]; then
    echo "Stream started successfully."
    RETRY_COUNT=0   # Reset retry count on success
    SUCCESS=1
    break
  fi
  echo "Attempt \$RETRY_COUNT to start stream failed (HTTP \$RESPONSE). Retrying..."
  sleep 2
done
if [[ \$SUCCESS -ne 1 ]]; then
  echo "Failed to start stream after \$RETRY_AMOUNT attempts."
  exit 1
fi

$CRONTAB_PATH -l | grep -v "$CRON_START_JOB_TAG" | $CRONTAB_PATH -
rm -- "\$0"
EOF

# Redefine time for cron end datetime.
CRON_END_MINUTE=$((END_MINUTE))
CRON_END_HOUR=$((END_HOUR))
CRON_END_DAY=$((END_DAY))
CRON_END_MONTH=$((END_MONTH))

if [[ $CRON_END_MINUTE -lt 0 ]]; then
  CRON_END_MINUTE=$((60 + CRON_END_MINUTE))
  CRON_END_HOUR=$((END_HOUR - 1))
  if [[ $CRON_END_HOUR -lt 0 ]]; then
    CRON_END_HOUR=23
    CRON_END_DAY=$((END_DAY - 1))
  fi
fi

# Format the cron end datetime
CRON_END_DATETIME="$CRON_END_MINUTE $CRON_END_HOUR $CRON_END_DAY $CRON_END_MONTH *"

# Create stop stream script
cat <<EOF > "$CRON_END_SCRIPT"
#!$BASH_PATH

RETRY_AMOUNT=$RETRY_AMOUNT
RETRY_COUNT=0
TRANSITION_SUCCESS=0

# Get a new access token
while [[ \$RETRY_COUNT -lt \$RETRY_AMOUNT ]]; do
  ((RETRY_COUNT++))
  ACCESS_TOKEN=\$(curl -s \\
    --request POST \\
    --data "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&refresh_token=$REFRESH_TOKEN&grant_type=refresh_token" \\
    https://oauth2.googleapis.com/token | jq -r .access_token)
  if [[ -n "\$ACCESS_TOKEN" && "\$ACCESS_TOKEN" != "null" ]]; then
    echo "Access token obtained successfully."
    RETRY_COUNT=0   # Reset retry count on success
    break
  fi
  echo "Attempt \$RETRY_COUNT to get access token failed. Retrying..."
  sleep 2
done
if [[ -z "\$ACCESS_TOKEN" || "\$ACCESS_TOKEN" == "null" ]]; then
  echo "Failed to get access token after \$RETRY_AMOUNT attempts."
  exit 1
fi

# Call YouTube API to transition the broadcast with retry logic
while [[ \$RETRY_COUNT -lt \$RETRY_AMOUNT ]]; do
  ((RETRY_COUNT++))
  TRANSITION_RESPONSE=\$(curl -s -X POST "https://www.googleapis.com/youtube/v3/liveBroadcasts/transition?broadcastStatus=complete&id=$BROADCAST_ID" \\
    -H "Authorization: Bearer \$ACCESS_TOKEN" \\
    -H "Content-Type: application/json")
  # Check for a successful transition (look for broadcastStatus or no error)
  if echo "\$TRANSITION_RESPONSE" | grep -q '"status":' && echo "\$TRANSITION_RESPONSE" | grep -q '"lifeCycleStatus": "complete"'; then
    echo "Broadcast transitioned to complete successfully."
    RETRY_COUNT=0   # Reset retry count on success
    TRANSITION_SUCCESS=1
    break
  fi
  echo "Attempt \$RETRY_COUNT to transition broadcast failed. Retrying..."
  sleep 2
done
if [[ \$TRANSITION_SUCCESS -ne 1 ]]; then
  echo "Failed to transition broadcast after \$RETRY_AMOUNT attempts."
  echo "\$TRANSITION_RESPONSE"
  exit 1
fi

# Remove the cron job and delete this script
$CRONTAB_PATH -l | grep -v "$CRON_END_JOB_TAG" | $CRONTAB_PATH -
rm -- "\$0"
EOF

# Make scripts executable
chmod +x "$CRON_START_SCRIPT" "$CRON_END_SCRIPT"

# Schedule the cron jobs
($CRONTAB_PATH -l 2>/dev/null; echo "$CRON_START_DATETIME $BASH_PATH $CRON_START_SCRIPT # $CRON_START_JOB_TAG") | $CRONTAB_PATH -
($CRONTAB_PATH -l 2>/dev/null; echo "$CRON_END_DATETIME $BASH_PATH $CRON_END_SCRIPT # $CRON_END_JOB_TAG") | $CRONTAB_PATH -


# === Step 10: Output RTMP info ===
echo ""
echo "✅ Stream Scheduled!"
echo "🔗 RTMP Ingest URL: $INGEST_URL"
echo "🔑 Stream Key: $STREAM_KEY"
echo "📺 YouTube Broadcast ID: $BROADCAST_ID"
echo "⏰ Start stream at $START_ISO"
echo "⏹️ Stop stream at $END_ISO"
echo ""
echo "Docker Container ID: $DOCKER_CONTAINER_NAME"
echo "Go2RTC Stream Name to be livestreamed: $ARG_STREAM_NAME"
echo ""
echo "📅 Cron jobs scheduled" 
echo "⏰ Publish stream at $CRON_START_DATETIME"
echo "⏹️ Stop stream at $CRON_END_DATETIME"
