# PulseOps

**Microservices-based application with Kubernetes orchestration, asynchronous messaging, automated CI/CD, container security scanning, observability, and Infrastructure as Code.**

PulseOps is a production-style DevOps project built around a small e-commerce workflow. The application consists of independent Flask services that communicate through REST APIs and RabbitMQ, with PostgreSQL used for persistent data.

The application is containerized with Docker and deployed locally on Kubernetes using Minikube. GitHub Actions automates image builds, vulnerability scanning, Kubernetes deployments, and post-deployment verification. Prometheus and Grafana are used for monitoring, while Terraform defines the target AWS infrastructure architecture.

> **Cloud note:** The application is implemented and tested locally. Terraform contains the AWS target architecture, but the infrastructure has not been deployed to an AWS account.

---

## Architecture

```text
                           Client
                             |
                             v
                      +--------------+
                      | API Gateway  |
                      |    :5000     |
                      +------+-------+
                             |
                  +----------+----------+
                  |                     |
                  v                     v
          +---------------+     +---------------+
          | Product       |     | Order         |
          | Service       |     | Service       |
          | :5001         |     | :5002         |
          +---------------+     +-------+-------+
                                        |
                              +---------+---------+
                              |                   |
                              v                   v
                       +-------------+      +-------------+
                       | PostgreSQL  |      |  RabbitMQ   |
                       |    :5432    |      |    :5672    |
                       +-------------+      +------+------+
                                                   |
                                                   v
                                          +----------------+
                                          | Notification   |
                                          | Service :5003  |
                                          +----------------+


                 Kubernetes / Minikube
                         |
       +-----------------+------------------+
       |                 |                  |
       v                 v                  v
    Services            HPA             NetworkPolicy
       |
       v
  Health Probes
  Self-healing
  Persistent Storage


                 Observability
                       |
              +--------+--------+
              |                 |
              v                 v
          Prometheus          Grafana


                     CI/CD
                       |
                  GitHub Push
                       |
                       v
                GitHub Actions
                       |
             +---------+---------+
             |                   |
             v                   v
        Docker Build          Trivy
             |                   |
             +---------+---------+
                       |
                       v
                  Kubernetes


                 Infrastructure
                       |
                   Terraform
                       |
                       v
               AWS Architecture
```

---

## Services

| Service              | Port | Responsibility                                   |
| -------------------- | ---: | ------------------------------------------------ |
| API Gateway          | 5000 | External API entry point and request routing     |
| Product Service      | 5001 | Product information                              |
| Order Service        | 5002 | Order creation, persistence and event publishing |
| Notification Service | 5003 | Consumes and processes order events              |
| PostgreSQL           | 5432 | Persistent application data                      |
| RabbitMQ             | 5672 | Asynchronous service communication               |

---

## Order Flow

A typical order follows this path:

```text
Client
  |
  v
API Gateway
  |
  v
Order Service
  |
  +------> PostgreSQL
  |          |
  |          +--> Persist order
  |
  +------> RabbitMQ
               |
               +--> Notification Service
```

When an order is created, the Order Service stores the order in PostgreSQL and publishes an `order_created` event to RabbitMQ.

The Notification Service consumes the event independently.

Example event:

```json
{
  "event": "order_created",
  "order_id": 28,
  "product_id": 1,
  "quantity": 2
}
```

This allows notification processing to remain decoupled from the main order request.

---

# Technology Stack

### Application

* Python
* Flask
* PostgreSQL
* RabbitMQ

### Containerization

* Docker
* Docker Compose

### Orchestration

* Kubernetes
* Minikube
* Helm

### CI/CD

* GitHub Actions
* Self-hosted GitHub Actions runner

### Security

* Trivy

### Observability

* Prometheus
* Grafana
* Kubernetes Metrics API

### Infrastructure as Code

* Terraform
* AWS architecture modeling

---

# Kubernetes

The application is deployed into a dedicated `pulseops` namespace.

The Kubernetes configuration includes:

* Deployments
* ClusterIP and NodePort Services
* ConfigMaps
* Secrets
* PersistentVolumeClaim
* HorizontalPodAutoscaler
* Liveness and readiness probes
* NetworkPolicy

The API Gateway runs with two replicas by default and is configured with an HPA:

```text
Minimum replicas: 2
Maximum replicas: 5
CPU target: 60%
```

Kubernetes is responsible for maintaining the desired state of the application and replacing failed Pods.

---

# CI/CD Pipeline

The GitHub Actions workflow automates the local deployment lifecycle.

```text
Git Push
   |
   v
Checkout
   |
   v
Environment Verification
   |
   v
Build Docker Images
   |
   v
Trivy Security Scan
   |
   v
Update Kubernetes Images
   |
   v
Wait for Rollout
   |
   v
Application Health Check
   |
   v
HPA Verification
```

Images are tagged using the Git commit SHA:

```text
pulseops/api-gateway:<commit-sha>
```

This makes it possible to identify exactly which source revision is running in Kubernetes.

The workflow runs on a self-hosted runner because the Kubernetes cluster is running locally on the development machine.

---

# Security

Trivy is integrated into the CI/CD pipeline to scan the built container images.

The deployment stage is gated by HIGH and CRITICAL vulnerability findings.

This creates a basic security check before an image is deployed:

```text
Docker Build
     |
     v
Trivy Scan
     |
     +---- Findings → Pipeline stops
     |
     +---- Pass → Kubernetes deployment
```

---

# Observability

Prometheus and Grafana are used for local monitoring.

```text
Kubernetes
     |
     v
Prometheus
     |
     v
Grafana
```

The project also exposes an API Gateway monitoring endpoint:

```text
GET /monitoring/overview
```

It aggregates information such as:

* Pod health
* Deployment status
* Replica availability
* HPA state
* Gateway resource information
* Overall service health

---

# Infrastructure as Code

Terraform is used to model the AWS deployment architecture.

The configuration includes resources for:

* VPC
* Public and private subnets
* Route tables
* NAT Gateway
* ECR
* IAM
* EKS
* RDS PostgreSQL
* Application Load Balancer
* CloudWatch
* Route 53

The intended cloud architecture is:

```text
                    AWS VPC
                       |
          +------------+------------+
          |                         |
     Public Subnets            Private Subnets
          |                         |
          v                         v
         ALB                       EKS
                                    |
                         +----------+----------+
                         |                     |
                        Pods                Services
                                              |
                                              v
                                           RDS
```

Terraform configuration is validated locally. It is not applied to a live AWS environment.

---

# Repository Structure

```text
PulseOps/
│
├── services/
│   ├── api-gateway/
│   ├── product-service/
│   ├── order-service/
│   └── notification-service/
│
├── k8s/
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── postgres.yaml
│   ├── postgres-pvc.yaml
│   ├── postgres-secret.example.yaml
│   ├── rabbitmq.yaml
│   ├── product-service.yaml
│   ├── order-service.yaml
│   ├── notification-service.yaml
│   ├── api-gateway.yaml
│   ├── api-gateway-hpa.yaml
│   └── postgres-network-policy.yaml
│
├── helm/
│   └── pulseops/
│
├── terraform/
│
├── .github/
│   └── workflows/
│       └── ci-cd.yml
│
├── docker-compose.yml
├── .gitignore
└── README.md
```

---

# Local Setup

## Prerequisites

* Docker
* Docker Compose
* Minikube
* kubectl
* Helm
* Terraform
* Trivy

Start Minikube:

```bash
minikube start --driver=docker
```

Configure Docker to use the Minikube environment:

```bash
eval "$(minikube docker-env)"
```

Verify:

```bash
kubectl get nodes
```

Build the service images:

```bash
docker build -t pulseops/api-gateway:local services/api-gateway
docker build -t pulseops/product-service:local services/product-service
docker build -t pulseops/order-service:local services/order-service
docker build -t pulseops/notification-service:local services/notification-service
```

Deploy the Kubernetes resources:

```bash
kubectl apply -f k8s/
```

Check the workloads:

```bash
kubectl get pods -n pulseops
kubectl get deployments -n pulseops
kubectl get services -n pulseops
kubectl get hpa -n pulseops
```

---

# Validation

Application health:

```bash
curl http://<minikube-ip>:31486/health
```

Products:

```bash
curl http://<minikube-ip>:31486/products
```

Kubernetes:

```bash
kubectl get pods -n pulseops
kubectl get deployments -n pulseops
kubectl get hpa -n pulseops
```

Terraform:

```bash
cd terraform
terraform fmt -check
terraform validate
```

Helm:

```bash
helm lint helm/pulseops
```

---

# Engineering Focus

The project focuses on several practical DevOps concerns rather than only application development:

### Reliability

* Multiple API Gateway replicas
* Kubernetes self-healing
* Readiness and liveness probes
* Persistent PostgreSQL storage

### Scalability

* Kubernetes HPA
* Stateless application services
* Containerized workloads

### Security

* Trivy image scanning
* Kubernetes Secrets
* NetworkPolicy
* No AWS credentials stored in the repository

### Automation

* GitHub Actions
* Automated image builds
* Automated security scanning
* Automated Kubernetes deployment
* Rollout verification
* Application health checks

### Observability

* Prometheus
* Grafana
* Kubernetes metrics
* Application-level health information

---

# AWS Architecture

The project does not require an AWS account to run locally.

The local implementation provides a way to demonstrate the application and Kubernetes architecture, while Terraform represents how the infrastructure could be structured for an AWS deployment.

| Local                            | AWS                           |
| -------------------------------- | ----------------------------- |
| Minikube                         | EKS                           |
| PostgreSQL                       | RDS PostgreSQL                |
| Docker images                    | ECR                           |
| NodePort / Kubernetes networking | ALB                           |
| Local monitoring                 | Cloud monitoring architecture |
| Kubernetes networking            | VPC / security architecture   |

This separation keeps the project reproducible locally without representing local resources as a live cloud deployment.

---

# Project Status

**Current status: Functional local implementation**

Implemented:

* Microservices
* REST APIs
* PostgreSQL persistence
* RabbitMQ messaging
* Docker containerization
* Kubernetes deployment
* HPA
* Health probes
* Persistent storage
* NetworkPolicy
* Prometheus/Grafana monitoring
* GitHub Actions CI/CD
* Trivy security scanning
* Helm chart
* Terraform AWS architecture

---

# Author

**Astha**

GitHub: [AsthaK-2505](https://github.com/AsthaK-2505)

