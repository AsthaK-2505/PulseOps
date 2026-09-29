from flask import Flask, request

app = Flask(__name__)


@app.get("/health")
def health():
    return {
        "service": "order-service",
        "status": "healthy"
    }


@app.post("/orders")
def create_order():
    data = request.get_json(silent=True) or {}

    return {
        "message": "Order created",
        "product_id": data.get("product_id"),
        "quantity": data.get("quantity")
    }, 201


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5002)
