import json
import time
from datetime import UTC, datetime
from uuid import uuid4

import redis


REDIS_HOST = "localhost"
REDIS_PORT = 6380
QUEUE_KEY = "queue:tasks"
RESULTS_KEY = "queue:results"


def make_task(task_type: str, payload: dict) -> dict:
    return {
        "task_id": str(uuid4()),
        "task_type": task_type,
        "created_at": datetime.now(UTC).isoformat(),
        "payload": payload,
    }


def producer(r: redis.Redis, tasks: list[dict]) -> None:
    for task in tasks:
        r.lpush(QUEUE_KEY, json.dumps(task, ensure_ascii=False))
        print(f"[producer] queued task={task['task_id']} type={task['task_type']}")


def consumer(r: redis.Redis, max_tasks: int = 10, timeout_sec: int = 2) -> None:
    handled = 0
    while handled < max_tasks:
        entry = r.brpop(QUEUE_KEY, timeout=timeout_sec)
        if entry is None:
            print("[consumer] queue is empty, stop")
            break

        _, raw_task = entry
        task = json.loads(raw_task)
        result = process_task(task)
        r.lpush(RESULTS_KEY, json.dumps(result, ensure_ascii=False))

        handled += 1
        print(f"[consumer] handled task={task['task_id']} status={result['status']}")


def process_task(task: dict) -> dict:
    task_type = task["task_type"]
    payload = task["payload"]

    if task_type == "send_email":
        status = f"email sent to {payload['to']}"
        time.sleep(0.05)
    elif task_type == "process_order":
        status = f"order #{payload['order_id']} processed"
        time.sleep(0.05)
    elif task_type == "write_log":
        status = f"log written: {payload['message']}"
    else:
        status = f"unsupported task type: {task_type}"

    return {
        "task_id": task["task_id"],
        "task_type": task_type,
        "status": "ok",
        "details": status,
        "processed_at": datetime.now(UTC).isoformat(),
    }


def demo() -> None:
    r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, db=0, decode_responses=True)
    r.delete(QUEUE_KEY, RESULTS_KEY)

    tasks = [
        make_task("send_email", {"to": "student@example.com", "subject": "Lab5"}),
        make_task("process_order", {"order_id": 12345}),
        make_task("write_log", {"message": "redis queue demo"}),
    ]

    producer(r, tasks)
    consumer(r, max_tasks=10, timeout_sec=2)

    print("\n[results] latest processing results:")
    for item in r.lrange(RESULTS_KEY, 0, -1):
        print(item)


if __name__ == "__main__":
    demo()
