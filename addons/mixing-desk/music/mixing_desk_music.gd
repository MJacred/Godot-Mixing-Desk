extends Node

# Note: usually, we clone a track before we play it (and then delete after it finishes),
# except for rollover, concat, autofade and autolayer

# TODO:
# * write fade* and un-/mute funcs for all of this bus (usually called "Music")
# * write fade* and un-/mute funcs that support other containers

# taken from current Song
var tempo : int = 0
var bars : int = 0
var beats_in_bar : int = 0
var transition_beats : float = 0.0

# once/shuffle/loop
var can_shuffle : bool = true

enum play_style {play_once, loop_song, shuffle, endless_shuffle, loop_song_mix}
export(play_style) var play_mode
export(bool) var autoplay = false
export(NodePath) var autoplay_song # is played automatically, if autoplay is true on _ready()

onready var songs = get_children() # fetch MDM Song nodes on _ready()

const default_decibel : float = 0.0 # TODO: allow custom volume for each track

var ref_track : Object = null
var time : float = 0.0
var beat : int = 1
var last_beat : int = -1
var suppress_beat : float = 0.0
var beatInBar : int = 0
var bar : float = 1.0
var beats_in_sec : float = 0.0
var bar_is_locked : bool = false
var playing : bool = false
var current_song_index : int = 0
var current_song_core_container : Object = null # container node
var beat_tran : bool = false
var bar_tran : bool = false
var old_song_index : int = -1
var new_song_index : int = 0
var repeats : int = 0 # used for SequentialContainer; if > 0, then ConcatContainer won't work

var rollover : Object = null # play random track in RolloverContainer on each beat that equals the value of rollover_point
var rollover_point : int = 0

signal beat
signal bar_changed
signal core_loop_finished
signal shuffle
signal song_changed


func _ready():
	randomize() # according to Godot Doku: only call this once in _ready()

	# setup one_shot timer for shuffle as this one's child
	var shuff = Timer.new()
	shuff.name = 'shuffle_timer'
	add_child(shuff)
	shuff.one_shot = true

	# setup music root node for tracks that play in isolation (aka "overlay")
	var overlay_root = Node.new()
	overlay_root.name = "OverlayRoot"
	add_child(overlay_root)

	# setup shuffle
	shuff.connect("timeout", self, "shuffle_songs")

	# add a tween node to all track nodes in all core containers
	for song in songs:
		for track in song._get_core().get_children():
			var tween = Tween.new()
			tween.name = 'Tween'
			track.add_child(tween)

	# start autoplay song, if any defined
	if autoplay && !playing:
		quickplay(str(autoplay_song))


# updates position (i.e. time) in song and detects and caches current and last beat
func _process(delta : float):
	if suppress_beat > 0:
		suppress_beat -= delta
		return
	
	# safety measure
	if ref_track == null:
		playing = false

	if playing:
		time = ref_track.get_playback_position() # FIXME: here we pretend all tracks have the same length. acting on this will crash in some cases
		beat = int(floor((time * 1000.0/beats_in_sec) + 1.0))

		if beat != last_beat && int((beat - 1) % (bars * beats_in_bar) + 1) != last_beat:
			_beat()

		last_beat = beat


# loads a song and gets ready to play.
# if you called `mute()`, now it will be applied.
# resets `repeats` to `0`
func init_song(song_name : String):
	var song_index = _get_song_index(song_name)
	_init_song(song_index)


func _init_song(song_index : int):
	var song = songs[song_index]
	current_song_index = song_index
	current_song_core_container = song._get_core()

	repeats = 0

	# disable fadeout of given song and stop tweens of all tracks
	for track in current_song_core_container.get_children():
		if song.fading_out:
			track.get_child(0).stop(track) # stop the tween
			song.fading_out = false
		track.set_volume_db(default_decibel)

	for track in song.muted_tracks:
		_mute(song_index, track)

	# load in tempo & Co. from new song
	tempo = song.tempo
	bars = song.bars
	beats_in_bar = song.beats_in_bar
	beats_in_sec = 60000.0/tempo
	transition_beats = (beats_in_sec*song.transition_beats)/1000

	# handle rollover
	for container in song.get_children():
		if container.cont == "roll":
			rollover = container
			rollover_point = ((song.bars * song.beats_in_bar) - (container.crossover_beat - 1))
			break
		else:
			rollover = null


# returns an empty String, if no Song is initialized.
# call song_is_playing() to check if song is actually playing.
func get_current_song_name():
	if current_song_index < 0 || current_song_index >= songs.size():
		return ""

	return songs[current_song_index].name


func song_is_playing():
	return playing


# start a song with only one track playing in default volume.
# the others are muted, but are also running
func play_with_solo_opening(song_name : String, track_name : String):
	var song_index = _get_song_index(song_name)
	var track_index = _get_track_index(song_index, track_name)

	# TODO: check against _init_song(), some logic is missing

	current_song_index = song_index
	current_song_core_container = songs[song_index]._get_core()
	for track in current_song_core_container.get_children():
		track.set_volume_db(-60.0)
	current_song_core_container.get_child(track_index).set_volume_db(default_decibel)
	_play(song_index)


# copy given track, play, then remove it as soon as it's finished
func _clone_and_play(track : Node):
	var trk = track.duplicate()
	get_node("OverlayRoot").add_child(trk)
	var twe = Tween.new()
	twe.name = "Tween"
	trk.add_child(twe)
	trk.play()
	trk.connect("finished", trk, "queue_free")
	return trk


func _get_song_index(song_name : String):
	return get_node(song_name).get_index()


func _get_track_index(song_index : int, track_name : String):
	return songs[song_index]._get_core().get_node(track_name).get_index()


# play a song
func play(song_name : String):
	var song_index = _get_song_index(song_name)
	_play(song_index)


func _play(song_index : int):
	time = 0
	bar = 1
	beat = 1
	last_beat = -1
	suppress_beat = beats_in_sec / 1000.0 * 0.5

	# start playing all tracks in CoreContainer
	var core_container = songs[song_index]._get_core()
	var first = true
	for track in core_container.get_children():
		var newtrk = _clone_and_play(track)
		if first:
			ref_track = newtrk
			first = false

	if !playing:
		last_beat = 1
		emit_signal("bar_changed", bar)
		_beat()
		playing = true
					
	# now start playing all tracks of interest in the other overlay containers
	_play_overlays(song_index)


# initialize and play the song immediately
func quickplay(song_name : String):
	init_song(song_name)
	play(song_name)


# sets bar and beat transitions to FALSE.
# handles all containers, except for core and rollover.
# tracks in concat and autolayer containers are not cloned, they are played directly
func _play_overlays(song_index : int):
	for container in songs[song_index].get_children():
		if container.cont == "ran":
			if rand_range(0, 1) <= container.random_chance: # check if we should play the random track
				var rantrk = _get_rantrk(container)
				_clone_and_play(rantrk)
		if container.cont == "seq":
			# resets `repeats` to `0`, if repeats equals child count of SequentialContainer,
			# i.e. we finished last track in the SequentialContainer and now start anew (i.e. auto-loop)
			if repeats == container.get_child_count():
				repeats = 0

			_clone_and_play(container.get_child(repeats))
		if container.cont == "concat":
			if repeats < 1:
				_play_concat(container)
		if container.cont == "autofade":
			match container.play_style:
				0: # random
					var chance = randi() % container.get_child_count()
					container.get_child(chance).play()
				1: # all
					for track in container.get_children():
						track.play()
		if container.cont == "autolayer":
			for track in container.get_children():
				track.play()

	if bar_tran:
		bar_tran = false
	if beat_tran:
		beat_tran = false


# play short random tracks in sequence in 'song'
func _play_concat(container : Node):
	var rantrk = _get_rantrk(container)
	rantrk.play()
	rantrk.connect("finished", self, "_concat_fin", [container])


func _concat_fin(concat : Node):
	for i in concat.get_children():
		if i.is_connected("finished", self, "_concat_fin") :
			i.disconnect("finished", self, "_concat_fin")
	_play_concat(concat)


# slowly bring in the specified track.
# automatically unmutes track
func fade_in(song_name : String, track_name : String):
	var song_index = _get_song_index(song_name)
	var track_index = _get_track_index(song_index, track_name)
	_fade_in(song_index, track_index)


func _fade_in(song_index : int, track_index : int):
	# TODO: add bool for "include_overlays": the tracks from core are only used in next loop (if any)
	# use "for track in get_node("OverlayRoot").get_children():"
	# but we can't rely on track_index (because it's the index in core container -> not valid in OverlayRoot)

	# fade out currently NOT playing tracks
	# so in case they are used again BEFORE the tween finished: the next run won't be in full volume or muted
	var track = songs[song_index]._get_core().get_child(track_index)
	var tween = track.get_node("Tween")
	var in_from = track.get_volume_db()
	tween.interpolate_property(track, 'volume_db', in_from, default_decibel, transition_beats, Tween.TRANS_QUAD, Tween.EASE_OUT)
	tween.start()
	var pos = songs[song_index].muted_tracks.find(track_index)
	if pos != -1:
		songs[song_index].muted_tracks.remove(pos)


# slowly take out the specified track
func fade_out(song_name : String, track_name : String):
	var song_index = _get_song_index(song_name)
	var track_index = _get_track_index(song_index, track_name)
	_fade_out(song_index, track_index)


func _fade_out(song_index : int, track_index : int):
	# TODO: add bool for "include_overlays": the tracks from core are only used in next loop (if any)
	# use "for track in get_node("OverlayRoot").get_children():"
	# but we can't rely on track_index (because it's the index in core container -> not valid in OverlayRoot)

	# fade out currently NOT playing tracks
	# so in case they are used again BEFORE the tween finished: the next run won't be in full volume
	var track = songs[song_index]._get_core().get_child(track_index)
	var tween = track.get_node("Tween")
	var in_from = track.get_volume_db()
	tween.interpolate_property(track, 'volume_db', in_from, -60.0, transition_beats, Tween.TRANS_SINE, Tween.EASE_OUT)
	tween.start()
	tween.connect("tween_completed", self, "_mute_fadedout", [song_index, track_index])


# after fading, add track to muted tracks
func _mute_fadedout(object : Object, key : NodePath, song_index : String, track_index : String):
	var pos = songs[song_index].muted_tracks.find(track_index)
	if pos == null:
		songs[song_index].muted_tracks.append(track_index)


# mute all tracks via fadeout, except for specified track
func fadeout_to_solo(song_name : String, track_name : String):
	var song_index = _get_song_index(song_name)
	var track_index = _get_track_index(song_index, track_name)

	for track_iter in range(0, songs[song_index]._get_core().get_child_count()):
		if track_iter != track_index:
			_fade_out(song_index, track_iter)


# mute all tracks above specified track
func fadeout_above_track(song_name : String, track_name : String):
	var song_index = _get_song_index(song_name)
	var track_count = songs[song_index]._get_core().get_child_count()

	if track_count < 2:
		return

	var track_index = _get_track_index(song_index, track_name)

	if track_index >= (track_count - 1):
		return

	for i in range(track_index + 1, track_count):
		_fade_out(song_index, i)


# mute all tracks below specified track
func fadeout_below_track(song_name : String, track_name : String):
	var song_index = _get_song_index(song_name)
	var track_count = songs[song_index]._get_core().get_child_count()

	if track_count < 2:
		return

	var track_index = _get_track_index(song_index, track_name)

	if track_index <= 0:
		return

	for i in range(0, track_index):
		_fade_out(song_index, i)


# unmute all tracks above specified track
func fadein_above_track(song_name : String, track_name : String):
	var song_index = _get_song_index(song_name)
	var track_count = songs[song_index]._get_core().get_child_count()

	if track_count < 2:
		return

	var track_index = _get_track_index(song_index, track_name)

	if track_index >= (track_count - 1):
		return

	for i in range(track_index + 1, track_count):
		_fade_in(song_index, i)


# unmute all tracks below specified track
func fadein_below_track(song_name : String, track_name : String):
	var song_index = _get_song_index(song_name)
	var track_count = songs[song_index]._get_core().get_child_count()

	if track_count < 2:
		return

	var track_index = _get_track_index(song_index, track_name)

	if track_index <= 0:
		return

	for i in range(0, track_index):
		_fade_in(song_index, i)


# mute only the specified track in CoreContainer
func mute(song_name : String, track_name : String):
	var song_index = _get_song_index(song_name)
	_mute(song_index, track_name)


func _mute(song_index : int, track_name : String):
	# TODO: add bool for "include_overlays": the tracks from core are only used in next loop (if any)
	# use "for track in get_node("OverlayRoot").get_children():"
	# but we can't rely on track_index (because it's the index in core container -> not valid in OverlayRoot)

	# mute currently NOT playing tracks
	# so in case they are used again BEFORE the tween finished: the next run won't be in full volume
	var track_index = _get_track_index(song_index, track_name)
	var track = songs[song_index]._get_core().get_child(track_index)
	track.set_volume_db(-60.0)
	var pos = songs[song_index].muted_tracks.find(track_index)
	if pos == null:
		songs[song_index].muted_tracks.append(track_index)


# unmute only the specified track in CoreContainer
func unmute(song_name : String, track_name : String):
	var song_index = _get_song_index(song_name)
	_unmute(song_index, track_name)


func _unmute(song_index : int, track_name : String):
	# TODO: add bool for "include_overlays": the tracks from core are only used in next loop (if any)
	# use "for track in get_node("OverlayRoot").get_children():"
	# but we can't rely on track_index (because it's the index in core container -> not valid in OverlayRoot)

	# unmute currently NOT playing tracks
	# so in case they are used again BEFORE the tween finished: the next run will be in full volume
	var track_index = _get_track_index(song_index, track_name)
	var track = songs[song_index]._get_core().get_child(track_index)
	track.set_volume_db(default_decibel)
	var pos = songs[song_index].muted_tracks.find(track_index)
	if pos >= 0 && pos < songs[song_index].muted_tracks.size():
		songs[song_index].muted_tracks.remove(pos)


# mutes a track if not mutes, or vice versa
func toggle_mute(song_name : String, track_name : String):
	var song_index = _get_song_index(song_name)
	_toggle_mute(song_index, track_name)


func _toggle_mute(song_index : int, track_name : String):
	var track_index = _get_track_index(song_index, track_name)
	var track = songs[song_index]._get_core().get_child(track_index)
	if track.volume_db < 0:
		_unmute(song_index, track_name)
	else:
		_mute(song_index, track_name)


# fades a track in if silent, fades out if not
func toggle_fade(song_name : String, track_name : String):
	var song_index = _get_song_index(song_name)
	_toggle_fade(song_index, track_name)


func _toggle_fade(song_index : int, track_name : String):
	var track_index = _get_track_index(song_index, track_name)
	var track = songs[song_index]._get_core().get_child(track_index)
	if track.volume_db < 0:
		_fade_in(song_index, track_index)
	else:
		_fade_out(song_index, track_index)


# change to the specified song at the next bar
func queue_bar_transition(song_name : String):
	var song_index = _get_song_index(song_name)
	old_song_index = current_song_index
	songs[old_song_index].fading_out = true
	new_song_index = song_index
	bar_tran = true


# change to the specified song at the next beat
func queue_beat_transition(song_name : String):
	var song_index = _get_song_index(song_name)
	old_song_index = current_song_index
	songs[old_song_index].fading_out = true
	new_song_index = song_index
	beat_tran = true


# play two tracks in order, either ending, looping or shuffling on the second
func queue_sequence(sequence : Array, type : String, on_end : String):
	match type:
		"beat":
			queue_beat_transition(sequence[0])
		"bar":
			queue_bar_transition(sequence[0])
	play_mode = 0
	yield(self,"song_changed")
	yield(self,"core_loop_finished")
	init_song(sequence[1])
	play(sequence[1])
	match on_end:
		"play_once":
			play_mode = 0
		"loop":
			play_mode = 1
		"shuffle":
			play_mode = 2
		"endless":
			play_mode = 3


# unload and stops the current song, then initialises and plays the new one
# all tracks in CoreContainer are faded out. Besides that: all tracks not in a RolloverContainer are stopped immediately
# not another track of the old Song's RolloverContainer will be played
func change_song(song_name : String):
	var song_index = _get_song_index(song_name)
	_change_song(song_index)


func _change_song(song_index : int):
	old_song_index = current_song_index
	if song_index != current_song_index:
		emit_signal("song_changed", [songs[old_song_index].name, songs[song_index].name])
		_init_song(song_index)
		for container in songs[old_song_index].get_children():
			if container.cont == "core":
				if songs[old_song_index].transition_beats >= 1:
					for track in container.get_child_count():
						_fade_out(old_song_index, track)
			elif container.cont != "rollover": # rollover is not necessary, because we reset it _init_song()
				for track in container.get_children():
					if track.playing:
						track.stop()
	_fade_out_overlays()
	_play(song_index)


# fade out overlays
func _fade_out_overlays():
	for track in get_node("OverlayRoot").get_children():
		var tween = track.get_node("Tween")
		tween.interpolate_property(track, "volume_db", track.volume_db, -60, transition_beats, Tween.TRANS_LINEAR, Tween.EASE_IN)
		tween.start()
		tween.connect("tween_completed", self, "_track_faded", [track])


# delete track on fade
func _track_faded(object : Object, key : NodePath, track : Node):
	track.queue_free()


# stops playing given song. Fades out currently playing overlays.
# if any track is looping -> set track_node.stream.loop to FALSE (is this desired?)
# TODO: add option to stop immediately
func stop(song_name : String):
	var song_index = _get_song_index(song_name)
	if playing:
		playing = false
		for track in songs[song_index]._get_core().get_children():
			track.stream.loop = false
			 # in case the track is currently used as an overlay
			_fade_out_overlay(track.name)
		# TODO: fade/stop non-overlays (rollover, concat, autofade and autolayer)
		# but we can't rely on track_index (because it's the index in core container -> not valid in OverlayRoot)


# fade out overlay (if it exists)
func _fade_out_overlay(overlay_name : String):
	for track in get_node("OverlayRoot").get_children():
		if track.name == overlay_name:
			var tween = track.get_node("Tween")
			tween.interpolate_property(track, "volume_db", track.volume_db, -60, transition_beats, Tween.TRANS_LINEAR, Tween.EASE_IN)
			tween.start()
			tween.connect("tween_completed", track, "queue_free")
			return


# when the core loop finishes its loop
# increases `repeats` by 1, if play_mode == 1
func _core_finished():
	emit_signal("core_loop_finished", songs[current_song_index].name)
	match play_mode:
		1: # loop_song
			bar = 1
			beat = 1
			last_beat = -1
			repeats += 1
			_play(current_song_index)
			return
		2: # shuffle
			$shuffle_timer.start(rand_range(2, 4))
			return
		3: # endless_shuffle
			shuffle_songs()
			return
		4: # loop_song_mix
			var new_song_index : int
			if current_song_index == (get_child_count() - 3):
				new_song_index = 0
			else:
				new_song_index = current_song_index + 1

			_change_song(new_song_index)
			return

	playing = false


# called every bar
func _bar():
	if !bar_is_locked: # prevent multi-call in the same game-loop
		bar_is_locked = true
		if bar_tran:
			if current_song_index != new_song_index: # play new song in next bar
				_change_song(new_song_index)
			else: # play same song from the start in the next bar
				_play(new_song_index)
		yield(get_tree().create_timer(0.5), "timeout")
		bar_is_locked = false


# called every beat:
# * plays random rollover track (is not cloned) if the current beat equals rollover_point
func _beat():
	if beat_tran:
		if current_song_index != new_song_index:
			_change_song(new_song_index)
		else:
			_play(new_song_index)

	if beatInBar == beats_in_bar:
		beatInBar = 1
		bar += 1
		_bar()
		emit_signal("bar_changed", bar)
	else:
		beatInBar += 1

	if rollover != null && beat == rollover_point:
		if rollover.get_child_count() > 1:
			var roll = rollover.get_child(randi() % rollover.get_child_count())
			roll.play()
		else:
			rollover.get_child(0).play()

	if beat == (bars*beats_in_bar + 1):
		_core_finished()

	emit_signal("beat", (beat - 1) % int(bars * beats_in_bar) + 1)


# gets a random track from a Container and returns it
func _get_rantrk(container : Node):
	var chance = randi() % container.get_child_count()
	var rantrk = container.get_child(chance)
	return rantrk


# choose new song randomly
func shuffle_songs():
	var song_index = randi() % (songs.size())

	# if random gives us the same song, do last-ditch attempt
	if song_index == current_song_index:
		if song_index == 0:
			song_index += 1
		if song_index == songs.size() - 1:
			song_index -= 1

	emit_signal("shuffle", [songs[current_song_index].name, songs[song_index].name])
	new_song_index = song_index
	_change_song(song_index)
