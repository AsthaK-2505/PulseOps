from flask import Flask, jsonify
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
        "message": "Welcome to PulseOps API Gateway"
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
    data = requests.get(
        f"{ORDER_SERVICE_URL}/health",
        timeout=5
    )

    return {
        "message": "Order service is reachable",
        "order_service_status": data.json()
    }


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
