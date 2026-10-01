from flask import Flask, jsonify, request
from flask_cors import CORS
import os
import requests

app = Flask(__name__)
CORS(app)

PRODUCT_SERVICE_URL = os.getenv(
    "PRODUCT_SERVICE_URL",
    "http://product-service:5001"
)

ORDER_SERVICE_URL = os.getenv(
    "ORDER_SERVICE_URL",
    "http://order-service:5002"
)

PROMETHEUS_URL = os.getenv(
    "PROMETHEUS_URL",
    "http://monitoring-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090"
)


def prometheus_query(query):
    try:
        response = requests.get(
            f"{PROMETHEUS_URL}/api/v1/query",
            params={"query": query},
            timeout=5
        )

        response.raise_for_status()

        data = response.json()

        if data.get("status") != "success":
            return []

        return data.get("data", {}).get("result", [])

    except Exception as exc:
        print(f"Prometheus query failed: {exc}")
        return []


def get_metric_value(query, default=0):
    result = prometheus_query(query)

    if not result:
        return default

    try:
        return float(result[0]["value"][1])
    except (KeyError, IndexError, ValueError, TypeError):
        return default


def get_deployment_status(deployment):
    available = get_metric_value(
        f'kube_deployment_status_replicas_available{{namespace="pulseops",deployment="{deployment}"}}'
    )

    desired = get_metric_value(
        f'kube_deployment_spec_replicas{{namespace="pulseops",deployment="{deployment}"}}'
    )

    ready = get_metric_value(
        f'kube_deployment_status_replicas_ready{{namespace="pulseops",deployment="{deployment}"}}'
    )

    unavailable = get_metric_value(
        f'kube_deployment_status_replicas_unavailable{{namespace="pulseops",deployment="{deployment}"}}'
    )

    healthy = (
        available > 0
        and available >= desired
        and unavailable == 0
    )

    return {
        "name": deployment,
        "desired": int(desired),
        "available": int(available),
        "ready": int(ready),
        "unavailable": int(unavailable),
        "healthy": healthy,
        "status": "Healthy" if healthy else "Degraded"
    }


@app.get("/")
def home():
    return jsonify({
        "service": "api-gateway",
        "status": "running",
        "version": "2.3"
    })


@app.get("/health")
def health():
    return jsonify({
        "service": "api-gateway",
        "status": "healthy"
    })


@app.get("/products")
def get_products():
    try:
        response = requests.get(
            f"{PRODUCT_SERVICE_URL}/products",
            timeout=5
        )

        return jsonify(response.json()), response.status_code

    except requests.RequestException as exc:
        return jsonify({
            "error": "Product service unavailable",
            "details": str(exc)
        }), 503


@app.get("/orders")
def get_orders():
    try:
        response = requests.get(
            f"{ORDER_SERVICE_URL}/orders",
            timeout=5
        )

        return jsonify(response.json()), response.status_code

    except requests.RequestException as exc:
        return jsonify({
            "error": "Order service unavailable",
            "details": str(exc)
        }), 503


@app.post("/orders")
def create_order():
    try:
        payload = request.get_json(silent=True) or {}

        response = requests.post(
            f"{ORDER_SERVICE_URL}/orders",
            json=payload,
            timeout=10
        )

        return jsonify(response.json()), response.status_code

    except requests.RequestException as exc:
        return jsonify({
            "error": "Order service unavailable",
            "details": str(exc)
        }), 503


@app.get("/monitoring/overview")
def monitoring_overview():

    total_pods = get_metric_value(
        'count(kube_pod_info{namespace="pulseops"})'
    )

    running_pods = get_metric_value(
        'count(kube_pod_status_phase{namespace="pulseops",phase="Running"} == 1)'
    )

    failed_pods = get_metric_value(
        'count(kube_pod_status_phase{namespace="pulseops",phase="Failed"} == 1)'
    )

    gateway_cpu = get_metric_value(
        'sum(rate(container_cpu_usage_seconds_total{namespace="pulseops",pod=~"api-gateway-.*",container!="POD",container!=""}[5m])) * 100'
    )

    gateway_memory = get_metric_value(
        'sum(container_memory_working_set_bytes{namespace="pulseops",pod=~"api-gateway-.*",container!="POD",container!=""}) / 1024 / 1024'
    )

    gateway_replicas = get_metric_value(
        'kube_deployment_spec_replicas{namespace="pulseops",deployment="api-gateway"}'
    )

    gateway_available = get_metric_value(
        'kube_deployment_status_replicas_available{namespace="pulseops",deployment="api-gateway"}'
    )

    gateway_ready = get_metric_value(
        'kube_deployment_status_replicas_ready{namespace="pulseops",deployment="api-gateway"}'
    )

    gateway_unavailable = get_metric_value(
        'kube_deployment_status_replicas_unavailable{namespace="pulseops",deployment="api-gateway"}'
    )

    gateway_restarts = get_metric_value(
        'sum(kube_pod_container_status_restarts_total{namespace="pulseops",pod=~"api-gateway-.*"})'
    )

    hpa_current = get_metric_value(
        'kube_horizontalpodautoscaler_status_current_replicas{namespace="pulseops",horizontalpodautoscaler="api-gateway"}'
    )

    hpa_desired = get_metric_value(
        'kube_horizontalpodautoscaler_status_desired_replicas{namespace="pulseops",horizontalpodautoscaler="api-gateway"}'
    )

    hpa_min = get_metric_value(
        'kube_horizontalpodautoscaler_spec_min_replicas{namespace="pulseops",horizontalpodautoscaler="api-gateway"}'
    )

    hpa_max = get_metric_value(
        'kube_horizontalpodautoscaler_spec_max_replicas{namespace="pulseops",horizontalpodautoscaler="api-gateway"}'
    )

    cpu_target = get_metric_value(
        'kube_horizontalpodautoscaler_spec_target_metric{namespace="pulseops",horizontalpodautoscaler="api-gateway",metric_name="cpu"}'
    )

    services = [
        get_deployment_status("api-gateway"),
        get_deployment_status("product-service"),
        get_deployment_status("order-service"),
        get_deployment_status("notification-service"),
        get_deployment_status("postgres"),
        get_deployment_status("rabbitmq")
    ]

    healthy_services = sum(
        1 for service in services if service["healthy"]
    )

    overall_healthy = (
        failed_pods == 0
        and healthy_services == len(services)
    )

    if overall_healthy:
        healing_status = "All systems healthy"
    elif failed_pods > 0:
        healing_status = f"{int(failed_pods)} failed pod(s) detected"
    else:
        healing_status = "Service recovery in progress"

    return jsonify({
        "cluster": {
            "total_pods": int(total_pods),
            "running_pods": int(running_pods),
            "failed_pods": int(failed_pods)
        },

        "gateway": {
            "available_replicas": int(gateway_available),
            "ready_replicas": int(gateway_ready),
            "replicas": int(gateway_replicas),
            "unavailable_replicas": int(gateway_unavailable),
            "restarts": int(gateway_restarts),
            "cpu_percent": round(gateway_cpu, 2),
            "memory_mb": round(gateway_memory, 2)
        },

        "hpa": {
            "current_replicas": int(hpa_current),
            "desired_replicas": int(hpa_desired),
            "min_replicas": int(hpa_min),
            "max_replicas": int(hpa_max),
            "cpu_target_percent": round(cpu_target, 2)
        },

        "services": services,

        "autohealing": {
            "healthy": overall_healthy,
            "status": healing_status,
            "healthy_services": healthy_services,
            "total_services": len(services)
        }
    })


if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=5000,
        debug=False
    )
