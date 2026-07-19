# Kubernetes Final Evaluation – FastAPI & MySQL

This project implements the **Kubernetes final evaluation** scenario:

- Deploy a small data API in Kubernetes (Minikube on Ubuntu 24.04).  
- Each Pod contains **two containers**:
  - `datascientest/mysql-k8s:1.0.0` (MySQL database). [stackoverflow](https://stackoverflow.com/questions/75514910/deploying-fastapi-and-mysql-using-kubernetes)
  - `gnembac/fastapi-k8s:1.0.1` (FastAPI API).  
- Use a **Kubernetes Secret** to store the database password (`datascientest1234`) instead of hardcoding it. [kubernetes](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/)
- Expose the API inside the cluster via a **Service** and optionally externally via an **Ingress**. [github](https://github.com/AlexIoannides/kubernetes-mlops)

The repository is structured as a minimal exam-focused project: everything relevant is in the **root** directory.

***

## Project Structure

```text
k8s-final-eval/
  main.py
  Dockerfile
  requirements.txt
  my-secret-eval.yml
  my-deployment-eval.yml
  my-service-eval.yml
  my-ingress-eval.yml
  README.md
```

***

## FastAPI & SQLAlchemy – `main.py`

The `main.py` file implements a simple **User API**:

- `GET /status` → health check, returns `1`.  
- `GET /users` → returns all users from the `Users` table.  
- `GET /users/{user_id}` → returns a single user or `404` if not found. [fastapi.tiangolo](https://fastapi.tiangolo.com/tutorial/sql-databases/)

Database connection is configured via environment variables:

| Variable         | Meaning                          | Source               |
|------------------|----------------------------------|----------------------|
| `MYSQL_URL`      | Database hostname (Service name) | `mysql-service`      |
| `MYSQL_USER`     | DB user                          | `root`               |
| `MYSQL_PASSWORD` | DB password                      | Secret `mysql-secret`|
| `MYSQL_DATABASE` | Database name                    | `Main`               |

These are combined into a DSN like:

```python
mysql://<user>:<password>@<host>/<database>
```

and passed to `sqlalchemy.create_engine()`. [stackoverflow](https://stackoverflow.com/questions/78594715/cannot-connect-my-sql-database-with-fastapi-and-sql-sqlalchemy)

SQL queries are executed using SQLAlchemy 2.x **textual SQL**:

- `from sqlalchemy import text`  
- `connection.execute(text("SELECT * FROM Users;"))` [blog.csdn](https://blog.csdn.net/a272329874a/article/details/137020330)

This avoids the `ObjectNotExecutableError` that occurs when using plain strings with SQLAlchemy 2.x. [techoverflow](https://techoverflow.net/2024/07/06/how-to-fix-sqlalchemy-exc-objectnotexecutableerror-not-an-executable-object/)

***

## Docker Image – `Dockerfile`

The FastAPI container is based on `ubuntu:22.04` and installs all required system and Python dependencies:

```Dockerfile
FROM ubuntu:22.04

# System dependencies for Python and mysqlclient
RUN apt update && \
    apt install -y python3-pip python3-dev build-essential libmysqlclient-dev && \
    apt clean && rm -rf /var/lib/apt/lists/*

# Application files from the build context
COPY requirements.txt main.py ./

# Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 8000

CMD ["uvicorn", "main:server", "--host", "0.0.0.0", "--port", "8000"]
```

Key points:

- `libmysqlclient-dev` provides `mysql_config` and MySQL client libraries required by the `mysqlclient` Python package. [stackoverflow](https://stackoverflow.com/questions/47870628/oserror-mysql-config-not-found-when-trying-to-pip-install-mysqlclient-dja)
- `pip install --no-cache-dir -r requirements.txt` installs: `fastapi`, `sqlalchemy`, `mysqlclient`, `uvicorn`. [apxml](https://apxml.com/courses/docker-for-ml-projects/chapter-2-building-ml-dockerfiles/managing-pip-dependencies)

Example image tag used in the exam:  
`gnembac/fastapi-k8s:1.0.1` (Docker Hub).

***

## Secret – `my-secret-eval.yml`

The Secret `mysql-secret` stores the MySQL root password in Base64 form:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
type: Opaque
data:
  MYSQL_PASSWORD: <Base64 of "datascientest1234">
```

Characteristics:

- Type `Opaque` for generic sensitive data like passwords, tokens, keys. [kubernetes](https://kubernetes.io/docs/concepts/configuration/secret/)
- The password is injected into containers via `env.valueFrom.secretKeyRef` rather than being present in code or plain YAML. [docs.doppler](https://docs.doppler.com/docs/using-kubernetes-secrets)

***

## Deployment – `my-deployment-eval.yml`

The deployment `my-deployment-eval` creates **three Pods**, each with two containers:

| Field                            | Value            | Purpose                          |
|----------------------------------|------------------|----------------------------------|
| `apiVersion`                     | `apps/v1`        | Modern Deployment API            |
| `kind`                           | `Deployment`     | Manages replicas                 |
| `metadata.name`                  | `my-deployment-eval` | Deployment name             |
| `spec.replicas`                  | `3`              | Three identical Pods            |
| `spec.selector.matchLabels.app`  | `user-api`       | Selects Pods with label          |
| `template.metadata.labels.app`   | `user-api`       | Must match the selector          |

Pod template (simplified):

```yaml
containers:
  - name: mysql-container
    image: datascientest/mysql-k8s:1.0.0
    env:
      - name: MYSQL_ROOT_PASSWORD
        valueFrom:
          secretKeyRef:
            name: mysql-secret
            key: MYSQL_PASSWORD
      - name: MYSQL_DATABASE
        value: Main
    ports:
      - containerPort: 3306

  - name: fastapi-container
    image: gnembac/fastapi-k8s:1.0.1
    env:
      - name: MYSQL_URL
        value: mysql-service
      - name: MYSQL_USER
        value: root
      - name: MYSQL_PASSWORD
        valueFrom:
          secretKeyRef:
            name: mysql-secret
            key: MYSQL_PASSWORD
      - name: MYSQL_DATABASE
        value: Main
    ports:
      - containerPort: 8000
```

Both containers share the Pod’s IP and use the same password from the Secret. [leyaa](https://leyaa.ai/codefly/learn/kubernetes/qna/how-to-use-secret-as-environment-variable)

***

## Services – `my-service-eval.yml`

Services expose the Pods internally:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: fastapi-service
  labels:
    app: user-api
spec:
  type: ClusterIP
  selector:
    app: user-api
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 8000
---
apiVersion: v1
kind: Service
metadata:
  name: mysql-service
  labels:
    app: user-api
spec:
  type: ClusterIP
  selector:
    app: user-api
  ports:
    - name: mysql
      protocol: TCP
      port: 3306
      targetPort: 3306
```

Summary:

| Service           | Type      | Port → TargetPort | Selector       | Purpose                             |
|-------------------|-----------|-------------------|----------------|-------------------------------------|
| `fastapi-service` | ClusterIP | 80 → 8000         | `app=user-api` | HTTP access to FastAPI containers   |
| `mysql-service`   | ClusterIP | 3306 → 3306       | `app=user-api` | MySQL access for FastAPI containers |

`mysql-service` is used as the host (`MYSQL_URL`) in the API to connect to the database. [baeldung](https://www.baeldung.com/ops/kubernetes-pod-environment-variables)

***

## Ingress – `my-ingress-eval.yml`

Ingress routes external HTTP requests to the FastAPI Service:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress-eval
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
    - host: example.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: fastapi-service
                port:
                  number: 80
```

Key points:

- Uses an NGINX Ingress controller (e.g. Minikube `ingress` addon). [docs.cloud.google](https://docs.cloud.google.com/kubernetes-engine/distributed-cloud/bare-metal/docs/how-to/create-service-ingress)
- Host `example.local` can be mapped to `minikube ip` via `/etc/hosts`.  
- Path `/` proxies to `fastapi-service:80`.  

***

## Exam Workflow (Minikube on Ubuntu 24.04)

Typical exam workflow:

1. **Install and start Minikube & kubectl**. [kubernetes](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)
2. **Create Secret**:

   ```bash
   kubectl apply -f my-secret-eval.yml
   kubectl get secrets
   ```

3. **Create Deployment**:

   ```bash
   kubectl apply -f my-deployment-eval.yml
   kubectl get deployments
   kubectl get pods
   ```

4. **Create Services**:

   ```bash
   kubectl apply -f my-service-eval.yml
   kubectl get svc
   ```

5. **Create Ingress (optional, exam requirement)**:

   ```bash
   kubectl apply -f my-ingress-eval.yml
   kubectl get ingress
   ```

6. **Port-forward test**:

   ```bash
   kubectl port-forward svc/fastapi-service 8082:80
   curl http://localhost:8082/status   # → 1
   curl http://localhost:8082/users    # → API response / error trace
   ```

This demonstrates:

- Secret integration,  
- multi-container Deployment,  
- Service and optional Ingress,  
- and end-to-end cluster connectivity.

***

## Common Pitfalls & How to Avoid Them

### 1. `mysqlclient` installation error: `mysql_config not found`

**Symptom**:  
`pip install mysqlclient` fails with:

> `OSError: mysql_config not found` [blog.csdn](https://blog.csdn.net/dyg7777/article/details/128776304)

**Cause**:  
The system lacks MySQL client dev libraries; `mysqlclient` needs `mysql_config` at build time.

**Fix (Host and Dockerfile)**:

- On Ubuntu:

  ```bash
  sudo apt update
  sudo apt install python3-dev libmysqlclient-dev build-essential -y
  ```

- In Dockerfile (Ubuntu 22.04):

  ```Dockerfile
  RUN apt update && \
      apt install -y python3-pip python3-dev build-essential libmysqlclient-dev && \
      apt clean && rm -rf /var/lib/apt/lists/*
  ```

### 2. SQLAlchemy 2.x: `ObjectNotExecutableError`

**Symptom**:  
`sqlalchemy.exc.ObjectNotExecutableError: Not an executable object: 'SELECT * FROM Users;'` [blog.csdn](https://blog.csdn.net/weixin_53333436/article/details/128995090)

**Cause**:  
Plain strings are no longer executable in SQLAlchemy 2.x; you must wrap SQL in `text()` or use `select()` constructs. [atlassian](https://www.atlassian.com/data/notebook/how-to-execute-raw-sql-in-sqlalchemy)

**Fix**:

```python
from sqlalchemy import text

with mysql_engine.connect() as connection:
    results = connection.execute(text("SELECT * FROM Users;"))
```

Similarly for parameterized queries:

```python
results = connection.execute(
    text("SELECT * FROM Users WHERE Users.id = :uid"),
    {"uid": user_id}
)
```

### 3. Port-forward conflicts: `address already in use`

**Symptom**:  
`kubectl port-forward` fails with:

> `bind: address already in use` on `localhost:8080` or `8081`.

**Cause**:  
Another process (Docker container, previous port-forward, other service) already uses that port.

**Fix**:

- Stop the conflicting service/container, or  
- Use a different local port, e.g.:

  ```bash
  kubectl port-forward svc/fastapi-service 8082:80
  ```

Then connect via `http://localhost:8082/...`. [medium](https://medium.com/@swatilagad24/kubernetes-configmaps-secrets-and-environment-variables-a-comprehensive-guide-d708d520a148)

### 4. Missing Endpoints in Services

**Symptom**:  
`kubectl describe svc fastapi-service` shows `Endpoints: <none>`. [baeldung](https://www.baeldung.com/ops/kubernetes-pod-environment-variables)

**Cause**:

- Service selector doesn’t match Pod labels (e.g. `selector: app=user-api` vs. Pods labeled `app=other`).  

**Fix**:

- Ensure `spec.selector` in the Service matches `template.metadata.labels` in the Deployment:

  ```yaml
  selector:
    app: user-api
  ```

  and Pods:

  ```yaml
  labels:
    app: user-api
  ```

### 5. Ingress not working (no HTTP response from `host`)

**Symptom**:  
`curl http://example.local/...` hangs or returns 404 from the Ingress controller. [youtube](https://www.youtube.com/watch?v=9sLHoEyRq8w)

**Causes**:

- Ingress controller (e.g. NGINX) not installed/enabled in Minikube.  
- `/etc/hosts` not pointing `example.local` to `minikube ip`.  
- Ingress backend Service name/port mismatch.

**Fix**:

1. Enable Ingress in Minikube:

   ```bash
   minikube addons enable ingress
   ```

2. Map host:

   ```bash
   minikube ip   # copy IP
   # in /etc/hosts:
   <minikube-ip> example.local
   ```

3. Verify backend:

   ```yaml
   backend:
     service:
       name: fastapi-service
       port:
         number: 80
   ```

***

This README gives a concise, exam-focused overview of the architecture and the most important implementation details, plus the typical pitfalls that appear when combining FastAPI, SQLAlchemy, MySQL, Docker, and Kubernetes.

To refine it further, you could add a short section with **sample commands** for building and pushing the FastAPI image (already used in your workflow):

```bash
docker build -t gnembac/fastapi-k8s:1.0.1 .
docker push gnembac/fastapi-k8s:1.0.1
```
