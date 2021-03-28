Mixing Desk Music plugin documentation
======================================


Overview
--------

Example Setup  
```
MixingDeskMusic
├── SongA # the combination of various (or only one) tracks playing at the same time
│   ├── CoreContainer
│   │   ├── AudioStreamPlayer1 # also known as a track
│   │   └── AudioStreamPlayer2
│   └── AutofadeContainer
└── SongB
│   └── CoreContainer
└── ...
```


Signals
-------

```javascript
// on every beat of the song
signal beat()
// when starting to play a song as well when the next bar starts
signal bar_changed(bar : int)
// last beat in last bar finished playing; depending on chosen play_mode, the same/next song is played
signal core_loop_finished(current_song_node_name : String)
// in case the user calls shuffle_songs() or the play_mode is set to shuffle and the next song is played automatically
signal shuffle(old_song_node_name : String, new_song_node_name : String)
// every time a different song starts playing
signal song_changed(old_song_node_name : String, new_song_node_name : String)
```


Play Modes
----------

* on `endless_loop`
  * stops any tracks in a RolloverContainer
  * fades out overlays and currently playing tracks in CoreContainer


Transitions
-----------

* bar/beat transition (if it's a new Song)
  * stops any tracks in a RolloverContainer
  * fades out overlays and currently playing tracks in CoreContainer


Functions
---------

```csharp
# loads a song and gets ready to play.
# if you called `mute()`, now it will be applied.
func init_song(song_name : String)
```

```csharp
# play a song
func play(song_name : String)
```

```csharp
# initialize and play the song immediately
func quickplay(song_name : String)
```

```csharp
# start a song with only one track playing in default volume.
# the others are muted, but are also running
func play_with_solo_opening(song_name : String, track_name : String)
```

```csharp
# slowly bring in the specified track
func fade_in(song_name : String, track_name : String)
```

```csharp
# slowly take out the specified track
func fade_out(song_name : String, track_name : String)
```

```csharp
# mute all tracks via fadeout, except for specified track
func fadeout_to_solo(song_name : String, track_name : String)
```

```csharp
# mute all tracks above specified track
func fadeout_above_track(song_name : String, track_name : String)
```

```csharp
# mute all tracks below specified track
func fadeout_below_track(song_name : String, track_name : String)
```

```csharp
# unmute all tracks above specified track
func fadein_above_track(song_name : String, track_name : String)
```

```csharp
# unmute all tracks below specified track
func fadein_below_track(song_name : String, track_name : String)
```

```csharp
# mute only the specified track in CoreContainer
func mute(song_name : String, track_name : String)
```

```csharp
# unmute only the specified track in CoreContainer
func unmute(song_name : String, track_name : String):
```

```csharp
# mutes a track if not mutes, or vice versa
func toggle_mute(song_name : String, track_name : String)
```

```csharp
# fades a track in if silent, fades out if not
func toggle_fade(song_name : String, track_name : String)
```

```csharp
# change to the specified song at the next bar
func queue_bar_transition(song_name : String)
```

```csharp
# change to the specified song at the next beat
func queue_beat_transition(song_name : String)
```

```csharp
# play two tracks in order, either ending, looping or shuffling on the second
func queue_sequence(sequence : Array, type : String, on_end : String):
```

```csharp
# stops playing given song
func stop(song_name : String)
```

```csharp
# choose new song randomly
# * stops any tracks in a RolloverContainer
# * fades out overlays and currently playing tracks in CoreContainer
func shuffle_songs()
```
