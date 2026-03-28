# Проверка очереди

```bash
redis-cli -p 6380 LLEN queue:tasks
redis-cli -p 6380 LRANGE queue:tasks 0 -1
redis-cli -p 6380 LRANGE queue:results 0 -1
```

# Проверка rate limiting (fixed window)

```bash
redis-cli -p 6380 KEYS "rate:*"
redis-cli -p 6380 TTL rate:u1:$(($(date +%s)-$(date +%s)%10))
```

# Проверка sliding window

```bash
redis-cli -p 6380 ZCARD rate:sw:u2
redis-cli -p 6380 ZRANGE rate:sw:u2 0 -1 WITHSCORES
```
