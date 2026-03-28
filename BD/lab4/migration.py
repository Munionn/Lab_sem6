import csv
from pathlib import Path

import redis


DATA_DIR = Path(__file__).resolve().parent / "data"


def read_csv(name: str):
    path = DATA_DIR / name
    with path.open("r", encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def main():
    r = redis.Redis(host="localhost", port=6379, db=0, decode_responses=True)
    pipe = r.pipeline(transaction=False)

    # Для чистой демонстрации ЛР очищаем БД целиком.
    r.flushdb()

    users = read_csv("users.csv")
    categories = read_csv("categories.csv")
    products = read_csv("products.csv")
    orders = read_csv("orders.csv")
    order_items = read_csv("order_items.csv")

    for u in users:
        user_id = u["user_id"]
        pipe.hset(f"user:{user_id}", mapping=u)
        pipe.set(f"index:user:email:{u['email']}", user_id)

    for c in categories:
        category_id = c["category_id"]
        pipe.hset(f"category:{category_id}", mapping=c)

    for p in products:
        product_id = p["product_id"]
        category_id = p["category_id"]
        price = float(p["price"])
        rating = float(p["rating"])

        pipe.hset(f"product:{product_id}", mapping=p)
        pipe.sadd(f"category:{category_id}:products", product_id)
        pipe.zadd("products:by_price", {product_id: price})
        pipe.zadd("products:by_rating", {product_id: rating})

    order_to_user = {}
    for o in orders:
        order_id = o["order_id"]
        user_id = o["user_id"]
        created_at = o["created_at"]
        order_to_user[order_id] = user_id

        pipe.hset(f"order:{order_id}", mapping=o)
        pipe.lpush(f"user:{user_id}:orders", order_id)
        pipe.zadd(f"user:{user_id}:orders:z", {order_id: _to_unix_score(created_at)})

    for item in order_items:
        order_item_id = item["order_item_id"]
        order_id = item["order_id"]
        product_id = item["product_id"]
        user_id = order_to_user.get(order_id)
        qty = int(item["quantity"])
        price = float(item["price"])
        revenue = qty * price

        pipe.hset(f"order_item:{order_item_id}", mapping=item)
        pipe.sadd(f"order:{order_id}:items", order_item_id)
        pipe.zincrby("products:by_sales", qty, product_id)
        pipe.zincrby("products:by_revenue", revenue, product_id)

        if user_id is not None:
            pipe.zincrby("users:by_revenue", revenue, user_id)
            pipe.sadd(f"user:{user_id}:purchased", product_id)

    pipe.execute()
    print("Migration completed successfully.")
    print(f"Loaded: users={len(users)}, categories={len(categories)}, products={len(products)}, orders={len(orders)}, order_items={len(order_items)}")


def _to_unix_score(ts: str) -> int:
    return int(ts.replace("-", "").replace(":", "").replace("T", ""))


if __name__ == "__main__":
    main()
