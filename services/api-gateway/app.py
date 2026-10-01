from flask import Flask, jsonify, request
import requests
import os

app = Flask(__name__)

PRODUCT_SERVICE_URL = os.getenv(
    "PRODUCT_SERVICE_URL",
    "http://localhost:5001"
)

ORDER_SERVICE_URL = os.getenv(
    "ORDER_SERVICE_URL",
    "http://localhost:5002"
)


@app.get("/")
def home():
    return {
        "message": "Welcome to PulseOps API Gateway v2.1"
    }


@app.get("/health")
def health():
    return {
        "service": "api-gateway",
        "status": "healthy"
    }


@app.get("/products")
def products():
    response = requests.get(
        f"{PRODUCT_SERVICE_URL}/products",
        timeout=5
    )

    return jsonify(response.json()), response.status_code


@app.post("/orders")
def create_order():
    data = request.get_json(silent=True) or {}

    response = requests.post(
        f"{ORDER_SERVICE_URL}/orders",
        json=data,
        timeout=5
    )

    return jsonify(response.json()), response.status_code


@app.get("/orders")
def get_orders():
    response = requests.get(
        f"{ORDER_SERVICE_URL}/orders",
        timeout=5
    )

    return jsonify(response.json()), response.status_code


if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=5000,
        debug=True
    )
