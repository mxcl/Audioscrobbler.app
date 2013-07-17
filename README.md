![Screenshot][ss]

A minimal OS X iTunes scrobbling solution that implements Audioscrobbler
protocol 2.0.

To compile it you'll need to create `lastfm_api.h` and add a
[Last.fm key and secret](http://www.last.fm/api/account) like so:

```c
  #define LASTFM_API_KEY       "abcdef0123456789abcdef0123456789"
  #define LASTFM_SHARED_SECRET "abcdef0123456789abcdef0123456789"
```

[ss]: http://img213.yfrog.com/img213/365/h0l.png
