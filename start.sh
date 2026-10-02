#!/usr/bin/env bash

set -u

PROJECT="PulseOps"
NAMESPACE="pulseops"
MONITORING_NAMESPACE="monitoring"

GATEWAY_PORT="31486"
PROMETHEUS_PORT="9090"
GRAFANA_PORT="3000"
RABBITMQ_PORT="15672"

PROMETHEUS_SERVICE="monitoring-kube-prometheus-prometheus"
GRAFANA_SERVICE="monitoring-grafana"

PF_DIR="/tmp/pulseops-demo"
mkdir -p "$PF_DIR"

# ------------------------------------------------------------
# Colors / formatting
# ------------------------------------------------------------

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

success() {
    echo -e "${GREEN}✓${RESET} $1"
}

failure() {
    echo -e "${RED}✗${RESET} $1"
}

info() {
    echo -e "${CYAN}→${RESET} $1"
}

section() {
    echo
    echo -e "${BLUE}${BOLD}==============================================${RESET}"
    echo -e "${BLUE}${BOLD} $1${RESET}"
    echo -e "${BLUE}${BOLD}==============================================${RESET}"
}

# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------

cleanup_port_forwards() {
    if [[ -f "$PF_DIR/prometheus.pid" ]]; then
        kill "$(cat "$PF_DIR/prometheus.pid")" 2>/dev/null || true
        rm -f "$PF_DIR/prometheus.pid"
    fi

    if [[ -f "$PF_DIR/grafana.pid" ]]; then
        kill "$(cat "$PF_DIR/grafana.pid")" 2>/dev/null || true
        rm -f "$PF_DIR/grafana.pid"
    fi

    if [[ -f "$PF_DIR/rabbitmq.pid" ]]; then
        kill "$(cat "$PF_DIR/rabbitmq.pid")" 2>/dev/null || true
        rm -f "$PF_DIR/rabbitmq.pid"
    fi
}

trap cleanup_port_forwards EXIT

# ------------------------------------------------------------
# Prerequisites
# ------------------------------------------------------------

check_command() {
    if command -v "$1" >/dev/null 2>&1; then
        success "$1 installed"
        return 0
    else
        failure "$1 not found"
        return 1
    fi
}

check_prerequisites() {
    section "CHECKING PREREQUISITES"

    local failed=0

    check_command docker || failed=1
    check_command minikube || failed=1
    check_command kubectl || failed=1
    check_command trivy || failed=1
    check_command curl || failed=1

    if [[ "$failed" -ne 0 ]]; then
        echo
        failure "Required tools are missing."
        exit 1
    fi

    success "All required tools are available"
}

# ------------------------------------------------------------
# Minikube
# ------------------------------------------------------------

start_minikube() {
    section "STARTING MINIKUBE"

    if minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
        success "Minikube is already running"
    else
        info "Starting Minikube..."
        minikube start --driver=docker
    fi

    if kubectl get nodes >/dev/null 2>&1; then
        success "Kubernetes cluster is reachable"
    else
        failure "Kubernetes cluster is not reachable"
        exit 1
    fi
}

# ------------------------------------------------------------
# Kubernetes application status
# ------------------------------------------------------------

check_pulseops() {
    section "CHECKING PULSEOPS"

    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        failure "Namespace '$NAMESPACE' does not exist"
        return 1
    fi

    success "Namespace '$NAMESPACE' exists"

    echo
    kubectl get deployments -n "$NAMESPACE"

    echo
    kubectl get pods -n "$NAMESPACE"

    echo
    kubectl get services -n "$NAMESPACE"

    echo
    kubectl get hpa -n "$NAMESPACE" 2>/dev/null || true
}

# ------------------------------------------------------------
# Wait for application
# ------------------------------------------------------------

wait_for_workloads() {
    section "WAITING FOR APPLICATION"

    local deployments=(
        "api-gateway"
        "product-service"
        "order-service"
        "notification-service"
        "postgres"
        "rabbitmq"
    )

    for deployment in "${deployments[@]}"; do
        info "Waiting for $deployment..."

        if kubectl rollout status \
            "deployment/$deployment" \
            -n "$NAMESPACE" \
            --timeout=120s >/dev/null 2>&1; then

            success "$deployment ready"

        else
            failure "$deployment did not become ready"
            return 1
        fi
    done

    success "All PulseOps workloads are ready"
}

# ------------------------------------------------------------
# Gateway URL
# ------------------------------------------------------------

get_gateway_url() {
    local ip
    ip="$(minikube ip)"

    echo "http://${ip}:${GATEWAY_PORT}"
}

# ------------------------------------------------------------
# Application health
# ------------------------------------------------------------

check_application_health() {
    section "APPLICATION HEALTH"

    local gateway
    gateway="$(get_gateway_url)"

    info "Gateway: $gateway"

    echo

    info "Checking /health..."

    if curl --fail --silent --show-error \
        "${gateway}/health"; then

        echo
        success "API Gateway health check passed"

    else

        echo
        failure "API Gateway health check failed"
        return 1
    fi

    echo

    info "Checking /products..."

    if curl --fail --silent --show-error \
        "${gateway}/products"; then

        echo
        success "Product Service is responding"

    else

        echo
        failure "Product Service check failed"
        return 1
    fi
}

# ------------------------------------------------------------
# Monitoring stack
# ------------------------------------------------------------

check_monitoring() {
    section "CHECKING MONITORING"

    if ! kubectl get namespace "$MONITORING_NAMESPACE" \
        >/dev/null 2>&1; then

        failure "Monitoring namespace '$MONITORING_NAMESPACE' not found"
        return 1
    fi

    success "Monitoring namespace exists"

    echo

    kubectl get pods -n "$MONITORING_NAMESPACE" \
        | grep -E "NAME|prometheus|grafana" || true

    echo

    if kubectl get svc "$PROMETHEUS_SERVICE" \
        -n "$MONITORING_NAMESPACE" >/dev/null 2>&1; then

        success "Prometheus service found"

    else

        failure "Prometheus service not found"
        return 1
    fi

    if kubectl get svc "$GRAFANA_SERVICE" \
        -n "$MONITORING_NAMESPACE" >/dev/null 2>&1; then

        success "Grafana service found"

    else

        failure "Grafana service not found"
        return 1
    fi
}

# ------------------------------------------------------------
# Start monitoring port forwards
# ------------------------------------------------------------

start_prometheus() {
    if [[ -f "$PF_DIR/prometheus.pid" ]] &&
       kill -0 "$(cat "$PF_DIR/prometheus.pid")" 2>/dev/null; then
        success "Prometheus port-forward already running"
        return
    fi

    info "Starting Prometheus on localhost:$PROMETHEUS_PORT..."

    kubectl port-forward \
        "svc/$PROMETHEUS_SERVICE" \
        "$PROMETHEUS_PORT:9090" \
        -n "$MONITORING_NAMESPACE" \
        >"$PF_DIR/prometheus.log" 2>&1 &

    echo $! > "$PF_DIR/prometheus.pid"

    sleep 2

    if kill -0 "$(cat "$PF_DIR/prometheus.pid")" 2>/dev/null; then
        success "Prometheus available at http://localhost:$PROMETHEUS_PORT"
    else
        failure "Prometheus port-forward failed"
    fi
}

start_grafana() {
    if [[ -f "$PF_DIR/grafana.pid" ]] &&
       kill -0 "$(cat "$PF_DIR/grafana.pid")" 2>/dev/null; then
        success "Grafana port-forward already running"
        return
    fi

    info "Starting Grafana on localhost:$GRAFANA_PORT..."

    kubectl port-forward \
        "svc/$GRAFANA_SERVICE" \
        "$GRAFANA_PORT:80" \
        -n "$MONITORING_NAMESPACE" \
        >"$PF_DIR/grafana.log" 2>&1 &

    echo $! > "$PF_DIR/grafana.pid"

    sleep 2

    if kill -0 "$(cat "$PF_DIR/grafana.pid")" 2>/dev/null; then
        success "Grafana available at http://localhost:$GRAFANA_PORT"
    else
        failure "Grafana port-forward failed"
    fi
}

start_rabbitmq() {
    info "Starting RabbitMQ management UI on localhost:$RABBITMQ_PORT..."

    kubectl port-forward \
        "svc/rabbitmq" \
        "$RABBITMQ_PORT:15672" \
        -n "$NAMESPACE" \
        >"$PF_DIR/rabbitmq.log" 2>&1 &

    echo $! > "$PF_DIR/rabbitmq.pid"

    sleep 2

    if kill -0 "$(cat "$PF_DIR/rabbitmq.pid")" 2>/dev/null; then
        success "RabbitMQ available at http://localhost:$RABBITMQ_PORT"
    else
        failure "RabbitMQ port-forward failed"
    fi
}

# ------------------------------------------------------------
# Prometheus demonstration
# ------------------------------------------------------------

show_prometheus() {
    section "PROMETHEUS"

    start_prometheus

    echo
    echo "Prometheus UI:"
    echo "  http://localhost:$PROMETHEUS_PORT"

    echo
    echo "Useful seminar query:"
    echo "  up"

    echo
    echo "Prometheus demonstrates:"
    echo "  • Metrics collection"
    echo "  • Time-series monitoring"
    echo "  • Kubernetes observability"

    echo
    read -rp "Press Enter after viewing Prometheus..."
}

# ------------------------------------------------------------
# Grafana demonstration
# ------------------------------------------------------------

show_grafana() {
    section "GRAFANA"

    start_prometheus
    start_grafana

    echo
    echo "Grafana:"
    echo "  http://localhost:$GRAFANA_PORT"

    echo
    echo "Prometheus:"
    echo "  http://localhost:$PROMETHEUS_PORT"

    echo
    echo "Explain:"
    echo "  Prometheus = collects/stores metrics"
    echo "  Grafana    = visualizes metrics"

    echo
    read -rp "Press Enter after viewing Grafana..."
}

# ------------------------------------------------------------
# RabbitMQ demonstration
# ------------------------------------------------------------

show_rabbitmq() {
    section "RABBITMQ"

    start_rabbitmq

    echo
    echo "RabbitMQ Management UI:"
    echo "  http://localhost:$RABBITMQ_PORT"

    echo
    echo "Architecture:"
    echo
    echo "  Order Service"
    echo "       │"
    echo "       ▼"
    echo "    RabbitMQ"
    echo "       │"
    echo "       ▼"
    echo "  Notification Service"

    echo
    read -rp "Press Enter after viewing RabbitMQ..."
}

# ------------------------------------------------------------
# Products
# ------------------------------------------------------------

show_products() {
    section "PRODUCT SERVICE"

    local gateway
    gateway="$(get_gateway_url)"

    curl --fail --silent --show-error \
        "${gateway}/products"

    echo
}

# ------------------------------------------------------------
# Create order
# ------------------------------------------------------------

create_order() {
    section "CREATE ORDER"

    local gateway
    gateway="$(get_gateway_url)"

    info "Creating test order..."

    echo

    curl --fail --silent --show-error \
        -X POST \
        "${gateway}/orders" \
        -H "Content-Type: application/json" \
        -d '{"product_id":1,"quantity":2}'

    echo

    success "Order request completed"

    echo
    echo "Flow:"
    echo "  API Gateway"
    echo "       ↓"
    echo "  Order Service"
    echo "       ├── PostgreSQL"
    echo "       └── RabbitMQ"
    echo "              ↓"
    echo "       Notification Service"
}

# ------------------------------------------------------------
# Show orders
# ------------------------------------------------------------

show_orders() {
    section "ORDERS"

    local gateway
    gateway="$(get_gateway_url)"

    curl --fail --silent --show-error \
        "${gateway}/orders"

    echo
}

# ------------------------------------------------------------
# Kubernetes status
# ------------------------------------------------------------

show_kubernetes() {
    section "KUBERNETES STATUS"

    echo
    echo "=== Nodes ==="
    kubectl get nodes

    echo
    echo "=== Deployments ==="
    kubectl get deployments -n "$NAMESPACE"

    echo
    echo "=== Pods ==="
    kubectl get pods -n "$NAMESPACE"

    echo
    echo "=== Services ==="
    kubectl get svc -n "$NAMESPACE"

    echo
    echo "=== HPA ==="
    kubectl get hpa -n "$NAMESPACE"
}

# ------------------------------------------------------------
# HPA
# ------------------------------------------------------------

show_hpa() {
    section "HORIZONTAL POD AUTOSCALER"

    kubectl get hpa -n "$NAMESPACE"

    echo
    echo "Current configuration:"
    echo "  Minimum replicas : 2"
    echo "  Maximum replicas : 5"
    echo "  CPU target       : 60%"

    echo
    echo "The HPA adjusts API Gateway replicas"
    echo "according to CPU utilization."
}

# ------------------------------------------------------------
# Self-healing demonstration
# ------------------------------------------------------------

self_healing_demo() {
    section "KUBERNETES SELF-HEALING DEMO"

    local pod

    pod="$(
        kubectl get pods \
            -n "$NAMESPACE" \
            -l app=api-gateway \
            -o jsonpath='{.items[0].metadata.name}'
    )"

    if [[ -z "$pod" ]]; then
        failure "Could not find API Gateway pod"
        return 1
    fi

    echo "Current API Gateway pods:"
    kubectl get pods -n "$NAMESPACE" -l app=api-gateway

    echo
    echo -e "${YELLOW}We are going to delete one API Gateway pod.${RESET}"
    echo "Kubernetes should automatically create a replacement."

    echo
    read -rp "Press Enter to continue..."

    info "Deleting pod: $pod"

    kubectl delete pod "$pod" -n "$NAMESPACE"

    echo
    info "Watching Kubernetes replace the pod..."

    kubectl get pods \
        -n "$NAMESPACE" \
        -l app=api-gateway \
        -w
}

# ------------------------------------------------------------
# Monitoring overview
# ------------------------------------------------------------

show_monitoring_overview() {
    section "PULSEOPS MONITORING OVERVIEW"

    local gateway
    gateway="$(get_gateway_url)"

    curl --fail --silent --show-error \
        "${gateway}/monitoring/overview"

    echo
}

# ------------------------------------------------------------
# Demo-ready summary
# ------------------------------------------------------------

show_summary() {
    section "PULSEOPS DEMO READY"

    local gateway
    gateway="$(get_gateway_url)"

    echo
    echo "Application"
    echo "  API Gateway : $gateway"
    echo "  Products    : $gateway/products"
    echo "  Orders      : $gateway/orders"

    echo
    echo "Monitoring"
    echo "  Prometheus  : http://localhost:$PROMETHEUS_PORT"
    echo "  Grafana     : http://localhost:$GRAFANA_PORT"

    echo
    echo "Messaging"
    echo "  RabbitMQ    : http://localhost:$RABBITMQ_PORT"

    echo
    echo "Kubernetes"
    echo "  Namespace   : $NAMESPACE"
    echo "  HPA         : 2 → 5 replicas"
    echo "  CPU target  : 60%"

    echo
    echo "CI/CD"
    echo "  GitHub Actions + Docker + Trivy"
}

# ------------------------------------------------------------
# Prepare
# ------------------------------------------------------------

prepare() {
    check_prerequisites
    start_minikube

    echo
    info "Checking current PulseOps workloads..."

    wait_for_workloads

    check_pulseops
    check_application_health
    check_monitoring

    start_prometheus
    start_grafana

    show_summary

    echo
    success "PulseOps environment is ready for demonstration."
}

# ------------------------------------------------------------
# Seminar menu
# ------------------------------------------------------------

demo_menu() {

    while true; do

        section "PULSEOPS SEMINAR DEMO"

        echo
        echo "  1. Platform Status"
        echo "  2. Application Health"
        echo "  3. Show Products"
        echo "  4. Create Test Order"
        echo "  5. Show Orders"
        echo "  6. RabbitMQ"
        echo "  7. Kubernetes Status"
        echo "  8. Kubernetes Self-Healing"
        echo "  9. HPA"
        echo " 10. Prometheus"
        echo " 11. Grafana"
        echo " 12. Monitoring Overview"
        echo " 13. CI/CD Explanation"
        echo " 14. Terraform / AWS Explanation"
        echo "  0. Exit"

        echo
        read -rp "Select an option: " choice

        case "$choice" in

            1)
                show_kubernetes
                ;;

            2)
                check_application_health
                ;;

            3)
                show_products
                ;;

            4)
                create_order
                ;;

            5)
                show_orders
                ;;

            6)
                show_rabbitmq
                ;;

            7)
                show_kubernetes
                ;;

            8)
                self_healing_demo
                ;;

            9)
                show_hpa
                ;;

            10)
                show_prometheus
                ;;

            11)
                show_grafana
                ;;

            12)
                show_monitoring_overview
                ;;

            13)
                section "CI/CD PIPELINE"

                echo
                echo "Git Push"
                echo "   ↓"
                echo "GitHub Actions"
                echo "   ↓"
                echo "Docker Build"
                echo "   ↓"
                echo "Trivy Security Scan"
                echo "   ↓"
                echo "Kubernetes Deployment"
                echo "   ↓"
                echo "Rollout Verification"
                echo "   ↓"
                echo "Application Health Check"
                ;;

            14)
                section "AWS TARGET ARCHITECTURE"

                echo
                echo "Terraform models:"
                echo
                echo "  VPC"
                echo "  Subnets"
                echo "  NAT Gateway"
                echo "  ECR"
                echo "  EKS"
                echo "  RDS PostgreSQL"
                echo "  ALB"
                echo "  IAM"
                echo "  CloudWatch"
                echo "  Route 53"

                echo
                echo "Local → AWS mapping:"
                echo
                echo "  Minikube      → EKS"
                echo "  PostgreSQL    → RDS"
                echo "  Docker images → ECR"
                echo "  NodePort      → ALB"
                echo "  Local infra   → VPC architecture"
                ;;

            0)
                echo
                success "Exiting PulseOps demo."
                exit 0
                ;;

            *)
                failure "Invalid option"
                ;;
        esac

        echo
        read -rp "Press Enter to return to the menu..."

    done
}

# ------------------------------------------------------------
# Stop
# ------------------------------------------------------------

stop_demo() {
    section "STOPPING DEMO PORT-FORWARDS"

    cleanup_port_forwards

    success "Demo port-forwards stopped."
    echo
    echo "Minikube and Kubernetes workloads were left running."
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

case "${1:-start}" in

    start)
        prepare
        ;;

    demo)
        prepare
        demo_menu
        ;;

    stop)
        stop_demo
        ;;

    *)
        echo "Usage:"
        echo
        echo "  ./start.sh         Prepare PulseOps"
        echo "  ./start.sh demo    Start seminar demo menu"
        echo "  ./start.sh stop    Stop demo port-forwards"
        exit 1
        ;;

esac
