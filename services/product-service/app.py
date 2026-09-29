from flask import Flask, jsonify

app = Flask(__name__)

products = [
    {"id": 1, "name": "Laptop", "price": 75000},
    {"id": 2, "name": "Keyboard", "price": 2500},
    {"id": 3, "name": "Mouse", "price": 1200},
]


@app.get("/health")
def health():
    return {
        "service": "product-service",
        "status": "healthy"
    }


@app.get("/products")
def get_products():
    return jsonify(products)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)
