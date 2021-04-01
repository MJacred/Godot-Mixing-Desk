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


Requirements
------------

* on import of audio files, disable `loop`
* fully define your `Song` nodes: tempo, bars, beats in bars, transition beats


Limitations
-----------

* length of track `TODO`: overlay tracks must be of equal length or shorter than the first track in CoreContainer
  * overlay containers: RanContainer, SeqContainer
    * currently, Concat* and Rollover* are not implemented as overlays (i.e. no clones)
* Playing more than one Song at a time will break this setup.
* all fading and muting logic only applies to the tracks in the CoreContainer (except if stated otherwise below, e.g. `stop()`)
  * and, for now, is only applied on their next usage/loop (i.e. no immediate effect)
* supported audio files: wav, ogg
  * mp3 comes with Godot 3.3
  * use * for sound effects and tracks in RolloverContainer, *
  * use * for music


Signals
-------

```gdscript
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


Modes & Types
-------------

Mixing Desk Music
* on `play_once`
  * plays song once
* on `loop_song`
  * plays the same song over and over, until you decide to stop or transition to another, which will then start looping
* on `loop_song_mix`
  * plays all songs in the mix in order of their appearance in the tree
  * uses `func change_song()` internally
  * in detail:
    * stops any tracks in a RolloverContainer
    * fades out overlays and currently playing tracks in CoreContainer
* on `shuffle`
  * play a random song, silence for 2-3 secs (random), then play another random one
* on `endless_shuffle`
  * seamlessly shuffle between all songs in the mix

AutoLayer: Play Modes
* on `additive`
  * fade in all tracks below a certain index, and fade out all above
* on `single`
  * fade in only a single one of the tracks
* on `pad`
  * fade in tracks around the chosen index

AutoFade
* on `random`
  * randomly selected single track to play
* on `all`
  * play all tracks


Transitions
-----------

* bar/beat transition (if it's a new Song)
  * stops any tracks in a RolloverContainer
  * fades out overlays and currently playing tracks in CoreContainer


Functions
---------

```gdscript
# loads a song and gets ready to play.
# if you called `mute()`, now it will be applied.
func init_song(song_name : String)
```

```gdscript
# play a song
func play(song_name : String)
```

```gdscript
func get_current_song() -> Song
```

```gdscript
# returns an empty String, if no Song is initialized.
# call song_is_playing() or is_playing() to check if song is actually playing.
func get_current_song_name() -> String
```

```gdscript
func is_playing() -> bool
```

```gdscript
# returns false if given song is not playing.
# also returns false, if given song is unknown.
func song_is_playing(song_name : String) -> bool
```

```gdscript
# initialize and play the song immediately
func quickplay(song_name : String)
```

```gdscript
# unload and stops the current song, then initialises and plays the new one
# all tracks in CoreContainer are faded out. Besides that: all tracks not in a RolloverContainer are stopped immediately
# not another track of the old Song's RolloverContainer will be played
func change_song(song_name : String)
```

```gdscript
# start a song with only one track playing in default volume.
# the others are muted, but are also running
func play_with_solo_opening(song_name : String, track_name : String)
```

```gdscript
# slowly bring in the specified track
# fadein uses: Tween.TRANS_QUAD, Tween.EASE_OUT
func fade_in(song_name : String, track_name : String)
```

```gdscript
# slowly take out the specified track
# fadeout uses: Tween.TRANS_SINE, Tween.EASE_OUT
func fade_out(song_name : String, track_name : String)
```

```gdscript
# mute all tracks via fadeout, except for specified track
func fadeout_to_solo(song_name : String, track_name : String)
```

```gdscript
# mute all tracks above specified track
func fadeout_above_track(song_name : String, track_name : String)
```

```gdscript
# mute all tracks below specified track
func fadeout_below_track(song_name : String, track_name : String)
```

```gdscript
# unmute all tracks above specified track
func fadein_above_track(song_name : String, track_name : String)
```

```gdscript
# unmute all tracks below specified track
func fadein_below_track(song_name : String, track_name : String)
```

```gdscript
# mute only the specified track in CoreContainer
func mute(song_name : String, track_name : String)
```

```gdscript
# unmute only the specified track in CoreContainer
func unmute(song_name : String, track_name : String):
```

```gdscript
# mutes a track if not mutes, or vice versa
func toggle_mute(song_name : String, track_name : String)
```

```gdscript
# fades a track in if silent, fades out if not
func toggle_fade(song_name : String, track_name : String)
```

```gdscript
# change to the specified song at the next bar
# uses `func change_song()` internally
func queue_bar_transition(song_name : String)
```

```gdscript
# change to the specified song at the next beat
# uses `func change_song()` internally
func queue_beat_transition(song_name : String)
```

```gdscript
# play two tracks in order, either ending, looping or shuffling on the second
# uses `func change_song()` internally
func queue_sequence(sequence : Array, type : String, on_end : String):
```

```gdscript
# stops playing given song. Fades out currently playing overlays.
func stop(song_name : String)
```

```gdscript
# choose new song randomly
# * stops any tracks in a RolloverContainer
# * fades out overlays and currently playing tracks in CoreContainer
# uses `func change_song()` internally
func shuffle_songs()
```
