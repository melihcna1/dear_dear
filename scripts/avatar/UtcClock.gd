class_name UtcClock
extends RefCounted

# Backend boundary for rental timestamps. This prototype intentionally uses the
# device's UTC clock and is not cheat-resistant until an authoritative service
# supplies this implementation.

func now_unix() -> int:
	return int(Time.get_unix_time_from_system())
