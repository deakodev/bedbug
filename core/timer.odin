package core

import "core:time"

@(private = "file")
FRAME_TIMES_COUNT :: 60
@(private = "file")
FRAME_TIME_SLEEP_FACTOR :: 0.15

// platform agnostic high-resolution timer for frame timing and FPS calculation
Timer :: struct {
	previous_time:       time.Tick, // Time of the last frame (in seconds)
	delta_time:          f64, // Time since last frame (in seconds)
	frame_time_target:   f64, // Target frame time in seconds (inverse of target FPS)
	frame_sleep_slack:   f64, // Sleep window threshold to avoid tiny sleeps
	frame_times:         [FRAME_TIMES_COUNT]f64, // Array of recent frame times
	frame_index:         u32, // Current index in frame_times
	frame_count:         u32, // Number of valid frames (up to FRAME_TIMES_COUNT)
	frame_time_accum:    f64, // Running sum of frame times
	fps:                 f64, // Most recent FPS
	fps_update_time:     f64, // Time since last FPS update
	fps_update_interval: f64, // Interval for FPS updates
}

timer_setup :: proc(t: ^Timer, fps_target: u32 = 60.0, fps_update_interval: f64 = 1.0) {

	t.previous_time = time.tick_now()
	t.frame_time_target = 1.0 / f64(fps_target)
	t.frame_sleep_slack = t.frame_time_target * FRAME_TIME_SLEEP_FACTOR
	t.fps_update_interval = fps_update_interval
}

timer_update :: proc(t: ^Timer) #no_bounds_check {

	current_time := time.tick_now()

	t.delta_time = time.duration_seconds(time.tick_since(t.previous_time))

	// Frame rate control: Ensures we don't run faster than target frame time
	// This helps maintain consistent frame rates across different hardware
	if t.delta_time < t.frame_time_target {
		remaining_time := t.frame_time_target - t.delta_time

		// Only sleep if remaining time exceeds sleep window threshold
		// Sleep window prevents sleeping for tiny durations which can be inaccurate
		if remaining_time > t.frame_sleep_slack {
			sleep_time := remaining_time - t.frame_sleep_slack
			time.sleep(time.Duration(sleep_time * 1e9))
			current_time = time.tick_now()
			t.delta_time = time.duration_seconds(time.tick_since(t.previous_time))
		}

		// We use a busy-wait loop to precisely hit our target frame time
		// This is more CPU intensive but gives better timing precision
		for time.duration_seconds(time.tick_since(t.previous_time)) < t.frame_time_target {
			current_time = time.tick_now()
		}
	}

	frame_time := time.duration_seconds(time.tick_since(t.previous_time))

	if t.frame_count > 0 {
		t.frame_time_accum -= t.frame_times[t.frame_index]
	}

	t.frame_times[t.frame_index] = frame_time
	t.frame_time_accum += frame_time
	t.frame_index = (t.frame_index + 1) % FRAME_TIMES_COUNT
	t.frame_count = min(t.frame_count + 1, FRAME_TIMES_COUNT)
	t.fps_update_time += frame_time

	if t.fps_update_time >= t.fps_update_interval {
		t.fps = t.frame_time_accum > 0 ? 1.0 / (t.frame_time_accum / f64(t.frame_count)) : 0.0
		t.fps_update_time -= t.fps_update_interval
	}

	t.previous_time = current_time
}

timer_delta_time :: proc(t: Timer) -> f64 {
	return t.delta_time
}

timer_fps :: proc(t: Timer) -> f64 {
	return t.fps
}

timer_frame_time :: proc(t: Timer) -> f64 #no_bounds_check {
	return t.frame_times[(t.frame_index - 1 + FRAME_TIMES_COUNT) % FRAME_TIMES_COUNT]
}

timer_frame_time_target :: proc(t: Timer) -> f64 {
	return t.frame_time_target
}

timer_frame_count :: proc(t: Timer) -> u32 {
	return t.frame_count
}

timer_frame_time_accum :: proc(t: Timer) -> f64 {
	return t.frame_time_accum
}
