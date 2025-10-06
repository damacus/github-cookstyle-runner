# Kubernetes Installation

Kubernetes is ideal for production deployments, especially when using CronJobs for scheduled runs.

## Prerequisites

- Kubernetes 1.19+
- kubectl configured
- Persistent storage support

## Setup

### 1. Create Secret for GitHub App Credentials

Create a Kubernetes Secret to store your GitHub App credentials securely.

#### Option A: From Command Line

```bash
kubectl create secret generic cookstyle-runner-secrets \
  --from-literal=github-app-id=123456 \
  --from-literal=github-app-installation-id=789012 \
  --from-file=github-app-private-key=/path/to/private-key.pem \
  --namespace=default
```

#### Option B: From YAML

Create `secrets.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cookstyle-runner-secrets
  namespace: default
type: Opaque
stringData:
  github-app-id: "123456"
  github-app-installation-id: "789012"
  github-app-private-key: |
    -----BEGIN RSA PRIVATE KEY-----
    MIIEpAIBAAKCAQEA...
    -----END RSA PRIVATE KEY-----
```

Apply the secret:

```bash
kubectl apply -f secrets.yaml
```

!!! warning "Security"
    Never commit secrets to version control. Consider using tools like Sealed Secrets or external secret managers.

### 2. Create ConfigMap

Create `configmap.yaml` for application configuration:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cookstyle-runner-config
  namespace: default
data:
  GCR_DESTINATION_REPO_OWNER: "your-org-name"
  GCR_DESTINATION_REPO_TOPICS: "chef-cookbook"
  GCR_GIT_EMAIL: "bot@example.com"
  GCR_GIT_NAME: "Cookstyle Bot"
  GCR_BRANCH_NAME: "automated/cookstyle"
  GCR_DEFAULT_GIT_BRANCH: "main"
  GCR_PULL_REQUEST_TITLE: "Automated PR: Cookstyle Changes"
  GCR_PULL_REQUEST_LABELS: "tech-debt,automated"
  GCR_CREATE_MANUAL_FIX_PRS: "1"
  GCR_USE_CACHE: "1"
  GCR_CACHE_MAX_AGE: "7"
  GCR_THREAD_COUNT: "4"
  GCR_RETRY_COUNT: "3"
  GCR_DEBUG_MODE: "0"
```

Apply the ConfigMap:

```bash
kubectl apply -f configmap.yaml
```

### 3. Create PersistentVolumeClaim

Create `pvc.yaml` for cache storage:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cookstyle-runner-cache
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  # Optional: specify storage class
  # storageClassName: standard
```

Apply the PVC:

```bash
kubectl apply -f pvc.yaml
```

### 4. Create CronJob

Create `cronjob.yaml` for scheduled runs:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cookstyle-runner
  namespace: default
spec:
  # Run daily at 2 AM UTC
  schedule: "0 2 * * *"
  
  # Keep last 3 successful and 1 failed job for debugging
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  
  # Don't start new job if previous is still running
  concurrencyPolicy: Forbid
  
  jobTemplate:
    spec:
      # Clean up completed jobs after 1 hour
      ttlSecondsAfterFinished: 3600
      
      template:
        metadata:
          labels:
            app: cookstyle-runner
        spec:
          restartPolicy: OnFailure
          
          containers:
          - name: cookstyle-runner
            image: ghcr.io/damacus/github-cookstyle-runner:latest
            imagePullPolicy: Always
            
            # Resource limits (adjust based on your needs)
            resources:
              requests:
                memory: "512Mi"
                cpu: "500m"
              limits:
                memory: "2Gi"
                cpu: "2000m"
            
            # Environment variables from ConfigMap
            envFrom:
            - configMapRef:
                name: cookstyle-runner-config
            
            # Sensitive environment variables from Secret
            env:
            - name: GITHUB_APP_ID
              valueFrom:
                secretKeyRef:
                  name: cookstyle-runner-secrets
                  key: github-app-id
            - name: GITHUB_APP_INSTALLATION_ID
              valueFrom:
                secretKeyRef:
                  name: cookstyle-runner-secrets
                  key: github-app-installation-id
            - name: GITHUB_APP_PRIVATE_KEY
              valueFrom:
                secretKeyRef:
                  name: cookstyle-runner-secrets
                  key: github-app-private-key
            
            # Persistent cache volume
            volumeMounts:
            - name: cache
              mountPath: /app/.cache
          
          volumes:
          - name: cache
            persistentVolumeClaim:
              claimName: cookstyle-runner-cache
```

Apply the CronJob:

```bash
kubectl apply -f cronjob.yaml
```

### 5. Verify Deployment

```bash
# Check CronJob
kubectl get cronjob cookstyle-runner

# Check PVC
kubectl get pvc cookstyle-runner-cache

# Check ConfigMap
kubectl get configmap cookstyle-runner-config

# Check Secret
kubectl get secret cookstyle-runner-secrets
```

## Testing

Manually trigger a job to test your configuration:

```bash
# Create a test job
kubectl create job --from=cronjob/cookstyle-runner cookstyle-runner-manual-test

# View job status
kubectl get job cookstyle-runner-manual-test

# View logs
kubectl logs -f job/cookstyle-runner-manual-test

# Clean up test job
kubectl delete job cookstyle-runner-manual-test
```

## Alternative: One-time Job

For one-time runs instead of scheduled CronJobs, create `job.yaml`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: cookstyle-runner-oneshot
  namespace: default
spec:
  ttlSecondsAfterFinished: 3600
  template:
    metadata:
      labels:
        app: cookstyle-runner
    spec:
      restartPolicy: OnFailure
      containers:
      - name: cookstyle-runner
        image: ghcr.io/damacus/github-cookstyle-runner:latest
        envFrom:
        - configMapRef:
            name: cookstyle-runner-config
        env:
        - name: GITHUB_APP_ID
          valueFrom:
            secretKeyRef:
              name: cookstyle-runner-secrets
              key: github-app-id
        - name: GITHUB_APP_INSTALLATION_ID
          valueFrom:
            secretKeyRef:
              name: cookstyle-runner-secrets
              key: github-app-installation-id
        - name: GITHUB_APP_PRIVATE_KEY
          valueFrom:
            secretKeyRef:
              name: cookstyle-runner-secrets
              key: github-app-private-key
        volumeMounts:
        - name: cache
          mountPath: /app/.cache
      volumes:
      - name: cache
        persistentVolumeClaim:
          claimName: cookstyle-runner-cache
```

Run the job:

```bash
kubectl apply -f job.yaml
kubectl logs -f job/cookstyle-runner-oneshot
```

## Monitoring

### View CronJob Status

```bash
# View CronJob details
kubectl describe cronjob cookstyle-runner

# View recent jobs
kubectl get jobs --selector=app=cookstyle-runner

# View job history
kubectl get jobs --selector=app=cookstyle-runner --sort-by=.metadata.creationTimestamp
```

### View Logs

```bash
# View logs from most recent job
kubectl logs -l app=cookstyle-runner --tail=100

# View logs from specific job
kubectl logs job/cookstyle-runner-28934567

# Follow logs in real-time
kubectl logs -f -l app=cookstyle-runner
```

### Check Cache PVC

```bash
# Check PVC status
kubectl get pvc cookstyle-runner-cache

# View PVC details
kubectl describe pvc cookstyle-runner-cache

# Check storage usage (requires metrics-server)
kubectl top pv
```

## Troubleshooting

### Job Fails to Start

Check events:

```bash
kubectl describe cronjob cookstyle-runner
kubectl describe job <job-name>
```

Common issues:

- Missing secrets or ConfigMap
- Insufficient resources
- Image pull errors

### Out of Memory

If pods are killed with OOMKilled status:

1. Reduce `GCR_THREAD_COUNT` in ConfigMap
2. Increase memory limits in CronJob spec
3. Process fewer repositories using `GCR_FILTER_REPOS`

### Cache Issues

Check PVC status and clear if needed:

```bash
# Delete and recreate PVC (will lose cache)
kubectl delete pvc cookstyle-runner-cache
kubectl apply -f pvc.yaml
```

## Upgrading

Update the image version in your CronJob:

```bash
# Edit CronJob
kubectl edit cronjob cookstyle-runner

# Or update via kubectl set image
kubectl set image cronjob/cookstyle-runner \
  cookstyle-runner=ghcr.io/damacus/github-cookstyle-runner:v2.0.0

# Verify update
kubectl describe cronjob cookstyle-runner | grep Image
```

## Uninstallation

Remove all resources:

```bash
# Delete CronJob
kubectl delete cronjob cookstyle-runner

# Delete ConfigMap
kubectl delete configmap cookstyle-runner-config

# Delete Secret
kubectl delete secret cookstyle-runner-secrets

# Delete PVC (will delete cache data)
kubectl delete pvc cookstyle-runner-cache

# Or delete all at once
kubectl delete -f cronjob.yaml
kubectl delete -f configmap.yaml
kubectl delete -f secrets.yaml
kubectl delete -f pvc.yaml
```

## Next Steps

- [Configure the application](../configuration/index.md)
- [Learn about usage](../usage/basic.md)
- [Troubleshooting guide](../usage/troubleshooting.md)
