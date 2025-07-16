# YouTube RTSP automated scheduled live stream with Go2RTC

[License](https://github.com/ryanfitton/livestream-youtube-scheduler/blob/master/LICENSE) - Apache License 2.0

* Tested on Ubuntu Server: `24.04`.
* Version: `1.1.0`.
* Blog post/Read more: https://ryanfitton.co.uk/blog/livestream-youtube-scheduler/

## Prerequisites
* `Docker`: Used to run the go2rtc container. Tested on `Docker version 27.5.1, build a187fa5`.
* `jq`: Parses JSON output from curl responses.
* `curl`: For sending HTTP requests to the YouTube API.
* `bash`: Ensure the script runs in Bash (not sh or dash).
* `crontab`: For scheduling stream start via cron.
* `date`: GNU date with --iso-8601 support (already present on most Linux distros)
* You must have your YouTube account API v3 Client ID, Client Secret and Refresh Token for use in `config.sh`. 

## Setup:

Note the files in this repo expects your current user to have their home folder at `/home/user`. If this is incorrect, do a find and replace on this value accross all of these files.

1. Pull down the latest Go2RTC Docker image:
  ```
  sudo docker pull alexxit/go2rtc
  ```

2. Create a config folder in your user's home folder (assuming `/home/user`):
  ```
  mkdir ~/config
  ```

  Alternatively you may be able to Git clone this repo: `git clone git@github.com:ryanfitton/livestream-youtube-scheduler.git` into your home folder.

3. Now create a `config.sh` file in this folder:
  ```
  nano ~/config/config.sh
  ```

  Upload the content's of `config.sh` from this repo into this file. This file will hold your config for YouTube API keys, and livestream feed schedules.

4. Now create a config folder to hold the stream config details for Go2RTC:
  ```
  mkdir ~/config/go2rtc
  ```

  And a `go2rtc.yaml` file:
  ```
  nano ~/config/go2rtc/go2rtc.yaml
  ```

  Upload the content's of `go2rtc.yaml` from this repo into this file.

5. Now create a `livestream-youtube-scheduler.sh` file in the home folder:
  ```
  nano ~/livestream-youtube-scheduler.sh
  ```

  Upload the content's of `livestream-youtube-scheduler.sh` from this repo into this file.

  And make this file executable: `chmod +x livestream-youtube-scheduler.sh`.

6. Now create a `scheduler-wrapper.sh` file in the home folder:
  ```
  nano ~/scheduler-wrapper.sh
  ```

  Upload the content's of `scheduler-wrapper.sh` from this repo into this file.

  And make this file executable: `chmod +x scheduler-wrapper.sh`.


7. Now schedule your cronjobs as Sudo:
  ```
  sudo crontab -e 
  ```

  You can use this as an example:
  ```
  0 1 * * * /bin/bash /home/user/scheduler-wrapper.sh
  ```

  This will run the scheduler at 01:00am each day, and will schedule livestreams of those specified in `config.sh`.


## Configuring livestreams:
1. Firstly ensure your livestream sources are specified in `go2rtc.yaml`.
2. Then setup your schedules in `config.sh`:

  Example:
  ```
  stream1=(
    "STREAM=birdcam"
    "TIMEZONE=Europe/London"
    "VISIBILITY=private"
    "TODAY=$(date +"%Y-%m-%d")"
    "TITLE='Bird camera live feed for $(date +"%A %d %B")'"
    "DESC='Bird camera live feed for $(date +"%A %d %B"). Streamed 11:00 to 15:30'"
    "THUMBNAIL='/home/user/config/youtube_thumbnail_1280x720.png'"
    "START=$(date +%Y-%m-%d)T11:00:00"
    "END=$(date +%Y-%m-%d)T15:30:00"
  )
  ```

  This example will:
  * `"STREAM=birdcam"` : This is the stream name defined in the `got2rtc.yaml` config.
  * `"TIMEZONE=Europe/London"` : The timezone for the start/end date/time.
  * `"VISIBILITY=private"` : The visibility for this livestream, use either: `unlisted`, `public` or `private`.
  * `"TITLE='Bird camera live feed for $(date +"%A %d %B")'"` : The name used in YouTube for this stream.
  * `"DESC='Bird camera live feed for $(date +"%A %d %B"). Streamed 11:00 to 15:30'"` : The description used in YouTube for this stream.
  * `"THUMBNAIL='/home/user/config/youtube_thumbnail_1280x720.png'"` : The thumbnail to be used for the stream. Ideally should be 1280×720px.
  * `"START=$(date +%Y-%m-%d)T11:00:00"` : The start date/time in ISO format for the stream, todays's date at '11:00 am'
  * `"END=$(date +%Y-%m-%d)T15:30:00"` : The end date/time in ISO format for the stream,  todays's date at '15:30 am'


## Generating your YouTube keys:
1. Create a Google Cloud Project
   - Go to [Google Cloud Console](https://console.cloud.google.com/).
   - Click the project dropdown in the top menu and select **"New Project"**.
   - Give your project a name and click **Create**.

2. Enable the YouTube Data API v3
   - In the Google Cloud Console, select your project.
   - Navigate to **APIs & Services** > **Library**.
   - Search for **YouTube Data API v3**.
   - Click it and then click **Enable**.

3. Create OAuth 2.0 Credentials
   - Go to **APIs & Services** > **Credentials**.
   - Click **Create Credentials** > **OAuth Client ID**.
   - Choose:
     - **Application Type**: `Desktop App` (or `Web Application` if applicable).
   - Click **Create**.
   - Copy your:
     - **Client ID**
     - **Client Secret**

4. Get a Refresh Token via OAuth 2.0 Playground
   - Open [OAuth 2.0 Playground](https://developers.google.com/oauthplayground/)
   - Click the gear icon (⚙️) in the top right:
     - Check **"Use your own OAuth credentials"**
     - Paste your **Client ID** and **Client Secret**
   - In Step 1:
     - Scroll down to **YouTube Data API v3**
     - Select:
       - `https://www.googleapis.com/auth/youtube`
       - `https://www.googleapis.com/auth/youtube.force-ssl`
     - Click **Authorize APIs**
   - Sign in with your Google account.
   - In Step 2:
     - Click **Exchange authorization code for tokens**
     - Copy the **Refresh Token** (note: this is only shown once)

5. Save Your Credentials
   - Save your credentials in `config.sh`
