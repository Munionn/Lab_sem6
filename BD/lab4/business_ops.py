import json
from typing import Any

import redis


def get_last_user_orders(r: redis.Redis, user_id: int, limit: int = 10) -> list[dict[str, Any]]:
    order_ids = r.lrange(f"user:{user_id}:orders", 0, limit - 1)
    result = []
    for order_id in order_ids:
        order_key = f"order:{order_id}"
        order_data = r.hgetall(order_key)
        if not order_data:
            continue

        items = []
        item_ids = r.smembers(f"order:{order_id}:items")
        for item_id in item_ids:
            item = r.hgetall(f"order_item:{item_id}")
            if not item:
                continue
            product = r.hgetall(f"product:{item['product_id']}")
            items.append(
                {
                    "order_item_id": item["order_item_id"],
                    "product_id": item["product_id"],
                    "product_name": product.get("name"),
                    "quantity": int(item["quantity"]),
                    "price": float(item["price"]),
                }
            )

        order_data["items"] = items
        result.append(order_data)
    return result


def get_top_products_by_sales(r: redis.Redis, n: int) -> list[dict[str, Any]]:
    top = r.zrevrange("products:by_sales", 0, n - 1, withscores=True)
    return _hydrate_product_scores(r, top, "sales")


def get_top_products_by_revenue(r: redis.Redis, n: int) -> list[dict[str, Any]]:
    top = r.zrevrange("products:by_revenue", 0, n - 1, withscores=True)
    return _hydrate_product_scores(r, top, "revenue")


def get_products_by_category_with_price(
    r: redis.Redis, category_id: int, min_price: float | None = None, max_price: float | None = None
) -> list[dict[str, Any]]:
    product_ids = r.smembers(f"category:{category_id}:products")
    result = []
    for product_id in product_ids:
        p = r.hgetall(f"product:{product_id}")
        if not p:
            continue
        price = float(p["price"])
        if min_price is not None and price < min_price:
            continue
        if max_price is not None and price > max_price:
            continue
        result.append({"product_id": int(product_id), **p})
    return sorted(result, key=lambda x: float(x["price"]))


def get_similar_users(r: redis.Redis, user_id: int) -> list[dict[str, Any]]:
    base = r.smembers(f"user:{user_id}:purchased")
    if not base:
        return []

    result = []
    all_user_keys = r.keys("user:*")
    for key in all_user_keys:
        maybe_id = key.split(":")[-1]
        if not maybe_id.isdigit() or int(maybe_id) == user_id:
            continue
        other = r.smembers(f"user:{maybe_id}:purchased")
        if not other:
            continue
        common = base.intersection(other)
        if common:
            result.append(
                {
                    "user_id": int(maybe_id),
                    "common_products": sorted(common),
                    "common_count": len(common),
                }
            )
    return sorted(result, key=lambda x: x["common_count"], reverse=True)


def get_top_products_by_sales_cached(r: redis.Redis, n: int, ttl_sec: int = 60) -> list[dict[str, Any]]:
    cache_key = f"cache:top_products:by_sales:{n}"
    cached = r.get(cache_key)
    if cached is not None:
        return json.loads(cached)

    fresh = get_top_products_by_sales(r, n)
    r.set(cache_key, json.dumps(fresh, ensure_ascii=False), ex=ttl_sec)
    return fresh


def _hydrate_product_scores(r: redis.Redis, records: list[tuple[str, float]], field_name: str) -> list[dict[str, Any]]:
    result = []
    for product_id, score in records:
        product = r.hgetall(f"product:{product_id}")
        if not product:
            continue
        result.append(
            {
                "product_id": int(product_id),
                "name": product.get("name"),
                field_name: score,
            }
        )
    return result


def demo():
    r = redis.Redis(host="localhost", port=6379, db=0, decode_responses=True)

    print("\n=== Last user orders (user_id=1) ===")
    print(json.dumps(get_last_user_orders(r, user_id=1, limit=10), indent=2, ensure_ascii=False))

    print("\n=== Top products by sales ===")
    print(json.dumps(get_top_products_by_sales(r, n=3), indent=2, ensure_ascii=False))

    print("\n=== Top products by revenue ===")
    print(json.dumps(get_top_products_by_revenue(r, n=3), indent=2, ensure_ascii=False))

    print("\n=== Products by category with price filter (category=10, 900..1300) ===")
    print(json.dumps(get_products_by_category_with_price(r, category_id=10, min_price=900, max_price=1300), indent=2, ensure_ascii=False))

    print("\n=== Similar users for user_id=1 ===")
    print(json.dumps(get_similar_users(r, user_id=1), indent=2, ensure_ascii=False))

    print("\n=== Cached top products by sales (n=3) ===")
    print(json.dumps(get_top_products_by_sales_cached(r, n=3), indent=2, ensure_ascii=False))


if __name__ == "__main__":
    demo()
