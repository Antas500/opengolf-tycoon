class_name Delay
## Timer-node based delay helper.
##
## `await get_tree().create_timer(x).timeout` leaks at exit: a coroutine still
## suspended on a SceneTreeTimer when the game quits keeps the timer (and the
## timer keeps the coroutine's function state) referenced past the ObjectDB
## cleanup check, which triggers the "ObjectDB instances leaked at exit"
## warning. A Timer NODE has the same await semantics, but when the tree is
## torn down the node is freed, its signal connections are dropped and the
## suspended coroutine is released cleanly — no leak.
##
## Usage:  await Delay.seconds(self, 1.5)
## If `host` leaves the tree first, the pending await is simply released.

## Create a one-shot Timer as a child of `host` and return its `timeout`
## signal, so callers can `await Delay.seconds(host, duration)`.
static func seconds(host: Node, duration: float) -> Signal:
	var timer := Timer.new()
	timer.name = "DelayTimer"
	timer.one_shot = true
	host.add_child(timer)
	timer.timeout.connect(timer.queue_free)
	timer.start(maxf(duration, 0.0))
	return timer.timeout
