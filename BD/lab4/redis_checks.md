# Проверки через redis-cli

```bash
# Посмотреть ключи пользователей
KEYS user:*

# Пример сущностей
HGETALL user:1
HGETALL product:100
HGETALL order:1001

# Индексы и связи
SMEMBERS category:10:products
LRANGE user:1:orders 0 9
SMEMBERS order:1001:items

# Топы и агрегаты
ZREVRANGE products:by_sales 0 9 WITHSCORES
ZREVRANGE products:by_revenue 0 9 WITHSCORES
ZREVRANGE users:by_revenue 0 9 WITHSCORES

# Проверка кеша тяжёлой операции
GET cache:top_products:by_sales:3
TTL cache:top_products:by_sales:3
```
