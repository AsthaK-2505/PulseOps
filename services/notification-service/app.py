from flask import Flask, request

app = Flask(__name__)


@app.get("/health")
def health():
    return {
        "service": "notification-service",
        "status": "healthy"
    }


@app.post("/notifications")
def send_notification():
    data = request.get_json(silent=True) or {}

    return {
        "message": "Notification processed",
        "recipient": data.get("recipient")
    }


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5003)
