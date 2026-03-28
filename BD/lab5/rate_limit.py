import time

import redis


REDIS_HOST = "localhost"
REDIS_PORT = 6380


def allow_fixed_window(
    r: redis.Redis, user_id: str, limit: int, window_seconds: int, now_ts: int | None = None
) -> tuple[bool, int, str]:
    if now_ts is None:
        now_ts = int(time.time())

    window_start = now_ts - (now_ts % window_seconds)
    key = f"rate:{user_id}:{window_start}"

    current = r.incr(key)
    if current == 1:
        r.expire(key, window_seconds)

    allowed = current <= limit
    return allowed, current, key


SLIDING_WINDOW_LUA = """
local key = KEYS[1]
local now_ms = tonumber(ARGV[1])
local window_ms = tonumber(ARGV[2])
local limit = tonumber(ARGV[3])
local member = ARGV[4]

redis.call('ZREMRANGEBYSCORE', key, 0, now_ms - window_ms)
local current = redis.call('ZCARD', key)
if current >= limit then
  return {0, current}
end

redis.call('ZADD', key, now_ms, member)
redis.call('PEXPIRE', key, window_ms)
current = redis.call('ZCARD', key)
return {1, current}
"""


def allow_sliding_window(
    r: redis.Redis, user_id: str, limit: int, window_seconds: int
) -> tuple[bool, int, str]:
    key = f"rate:sw:{user_id}"
    now_ms = int(time.time() * 1000)
    window_ms = window_seconds * 1000
    member = f"{now_ms}-{r.incr('rate:sw:seq')}"

    allowed, current = r.eval(
        SLIDING_WINDOW_LUA,
        1,
        key,
        now_ms,
        window_ms,
        limit,
        member,
    )
    return bool(allowed), int(current), key


def demo_fixed_window(r: redis.Redis) -> None:
    print("=== Fixed window demo (limit=5, window=10s) ===")
    user_id = "u1"
    limit = 5
    window = 10
    for i in range(1, 8):
        allowed, count, key = allow_fixed_window(r, user_id, limit, window)
        print(f"request={i} allowed={allowed} count={count} key={key}")


def demo_sliding_window(r: redis.Redis) -> None:
    print("\n=== Sliding window demo (limit=5, window=10s) ===")
    user_id = "u2"
    limit = 5
    window = 10
    for i in range(1, 8):
        allowed, count, key = allow_sliding_window(r, user_id, limit, window)
        print(f"request={i} allowed={allowed} count={count} key={key}")
        time.sleep(0.4)


def main() -> None:
    r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, db=0, decode_responses=True)
    r.delete("rate:sw:seq")
    demo_fixed_window(r)
    demo_sliding_window(r)


if __name__ == "__main__":
    main()
