from flask import Flask, request, jsonify
import os
import psycopg
import pika
import json
import time

app = Flask(__name__)


POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
POSTGRES_DB = os.getenv("POSTGRES_DB", "pulseops")
POSTGRES_USER = os.getenv("POSTGRES_USER", "pulseops")
POSTGRES_PASSWORD = os.getenv(
    "POSTGRES_PASSWORD",
    ""
)
POSTGRES_PORT = os.getenv("POSTGRES_PORT", "5432")


RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "rabbitmq")
RABBITMQ_PORT = int(
    os.getenv("RABBITMQ_PORT", "5672")
)


def get_connection():
    return psycopg.connect(
        host=POSTGRES_HOST,
        port=POSTGRES_PORT,
        dbname=POSTGRES_DB,
        user=POSTGRES_USER,
        password=POSTGRES_PASSWORD
    )


def initialize_database():
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS orders (
                    id SERIAL PRIMARY KEY,
                    product_id INTEGER NOT NULL,
                    quantity INTEGER NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
                """
            )

        connection.commit()


def publish_order_event(order):

    connection = pika.BlockingConnection(
        pika.ConnectionParameters(
            host=RABBITMQ_HOST,
            port=RABBITMQ_PORT
        )
    )

    channel = connection.channel()

    channel.queue_declare(
        queue="order_notifications",
        durable=True
    )

    event = {
        "order_id": order["id"],
        "product_id": order["product_id"],
        "quantity": order["quantity"],
        "created_at": order["created_at"]
    }

    channel.basic_publish(
        exchange="",
        routing_key="order_notifications",
        body=json.dumps(event),
        properties=pika.BasicProperties(
            delivery_mode=2
        )
    )

    connection.close()


@app.get("/health")
def health():
    return {
        "service": "order-service",
        "status": "healthy"
    }


@app.post("/orders")
def create_order():

    data = request.get_json(silent=True) or {}

    product_id = data.get("product_id")
    quantity = data.get("quantity")

    if product_id is None or quantity is None:
        return {
            "error": "product_id and quantity are required"
        }, 400

    try:
        product_id = int(product_id)
        quantity = int(quantity)

    except (TypeError, ValueError):
        return {
            "error": "product_id and quantity must be numbers"
        }, 400

    if quantity <= 0:
        return {
            "error": "quantity must be greater than 0"
        }, 400


    with get_connection() as connection:

        with connection.cursor() as cursor:

            cursor.execute(
                """
                INSERT INTO orders (product_id, quantity)
                VALUES (%s, %s)
                RETURNING id, product_id, quantity, created_at
                """,
                (product_id, quantity)
            )

            order = cursor.fetchone()

        connection.commit()


    order_data = {
        "id": order[0],
        "product_id": order[1],
        "quantity": order[2],
        "created_at": order[3].isoformat()
    }


    for attempt in range(5):

        try:

            publish_order_event(order_data)

            break

        except Exception:

            if attempt == 4:

                return {
                    "error": (
                        "Order saved but notification "
                        "event could not be published"
                    )
                }, 500

            time.sleep(2)


    return {
        "message": "Order created",
        "order": order_data,
        "notification": "Order event published"
    }, 201


@app.get("/orders")
def get_orders():

    with get_connection() as connection:

        with connection.cursor() as cursor:

            cursor.execute(
                """
                SELECT id, product_id, quantity, created_at
                FROM orders
                ORDER BY id DESC
                """
            )

            rows = cursor.fetchall()


    orders = []

    for row in rows:

        orders.append(
            {
                "id": row[0],
                "product_id": row[1],
                "quantity": row[2],
                "created_at": row[3].isoformat()
            }
        )


    return jsonify(orders)


if __name__ == "__main__":

    initialize_database()

    app.run(
        host="0.0.0.0",
        port=5002
    )
