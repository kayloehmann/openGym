# Exercise video extension

This fork adds multiple YouTube videos to
each exercise (built-in or custom), stored in the profile's `exVideos` map and
synced through the existing state API. The URL parser only accepts HTTPS YouTube
video links and converts them to `youtube-nocookie.com` iframe URLs. The player
loads only after the user taps Play. The selected video's preview thumbnail is
fetched directly from `i.ytimg.com` beforehand (it is not necessarily the literal
first frame). This discloses the viewer's IP address and video ID to Google's
thumbnail service; the openGym server does not proxy or download videos or previews.
Videos are third-party content and require an internet connection.

Videos are hidden by default, including for profiles that already have saved links.
The profile setting **During a workout → Exercise videos** enables them in both
exercise details and workouts. With it off, no YouTube preview or player is rendered;
saved links remain available under **Manage videos**. The separate animation setting
can hide GIFs while leaving opted-in videos visible.

To build a static frontend, run `npm ci --ignore-scripts` and `npm run build`
in `frontend/`. For an existing v1.3.7 Docker deployment, copy `frontend/dist/`
into a build context as `dist/` and build `web/Dockerfile.video-overlay` there.
Replace only the web image; the API and its persistent data need no migration.
