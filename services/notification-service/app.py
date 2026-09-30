from flask import Flask
import os
import pika
import json
import threading
import time

app = Flask(__name__)


RABBITMQ_HOST = os.getenv(
    "RABBITMQ_HOST",
    "rabbitmq"
)

RABBITMQ_PORT = int(
    os.getenv("RABBITMQ_PORT", "5672")
)


@app.get("/health")
def health():
    return {
        "service": "notification-service",
        "status": "healthy"
    }


def process_message(
    channel,
    method,
    properties,
    body
):

    event = json.loads(body)

    print(
        f"Notification processed for order "
        f"{event['order_id']}: "
        f"product={event['product_id']}, "
        f"quantity={event['quantity']}",
        flush=True
    )

    channel.basic_ack(
        delivery_tag=method.delivery_tag
    )


def consume_messages():

    while True:

        try:

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

            channel.basic_qos(
                prefetch_count=1
            )

            channel.basic_consume(
                queue="order_notifications",
                on_message_callback=process_message
            )

            print(
                "Notification Service waiting "
                "for order events...",
                flush=True
            )

            channel.start_consuming()

        except Exception as error:

            print(
                f"RabbitMQ connection failed: {error}",
                flush=True
            )

        print(
            "Retrying RabbitMQ connection "
            "in 5 seconds...",
            flush=True
        )

        time.sleep(5)


if __name__ == "__main__":

    consumer_thread = threading.Thread(
        target=consume_messages,
        daemon=True
    )

    consumer_thread.start()

    app.run(
        host="0.0.0.0",
        port=5003
    )
