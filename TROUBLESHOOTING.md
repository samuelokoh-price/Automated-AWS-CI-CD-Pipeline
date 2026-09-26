# 🛠️ Troubleshooting Case Study
# CiCd - Block Nesting Mismatches

This section documents an intentional failure case study engineered to test our **GitHub Actions CI/CD pipeline** and validate syntax error handling.

---

## 1. The Evidence: Pipeline Error Log
During the evaluation, the configuration in `main.tf` was intentionally modified around lines 80–105 to simulate a brace mismatch and incorrect block nesting. 

When the pipeline executed, the **Terraform Validate** step failed under the **Actions** tab on GitHub, producing the following logs:

```text
The Terraform configuration must be valid before initialization so that Terraform can determine which modules and providers need to be installed.
╷
│ Error: Unsupported block type
│ 
│ on main.tf line 82:
│ 82: ingress {
│ 
│ Blocks of type "ingress" are not expected here.
╵
╷
│ Error: Unsupported block type
│ 
│ on main.tf line 90:
│ 90: ingress {
│ 
│ Blocks of type "ingress" are not expected here.
╵
╷
│ Error: Unsupported block type
│ 
│ on main.tf line 98:
│ 98: egress {
│ 
│ Blocks of type "egress" are not expected here.
╵
╷
│ Error: Argument or block definition required
│ 
│ on main.tf line 104:
│ 104: }
│ 
│ An argument or block definition is required here.
╵
Error: Process completed with exit code 1.
```

---

<img width="1920" height="1080" alt="Screenshot from 2026-09-24 14-21-57" src="https://github.com/user-attachments/assets/78836bd7-4aa3-4f8e-8b16-210640f3426e" />
<img width="1920" height="1080" alt="Screenshot from 2026-09-24 14-22-47" src="https://github.com/user-attachments/assets/b528014c-507d-453e-8459-56e045a99b9d" />


## 2. Root Cause Analysis (RCA)
The HCL compiler threw these errors due to a combined structural failure:

* **Scope Mismatch:** A missing or misplaced closing curly brace (`}`) above line 82 caused the parent `resource` block to terminate prematurely.
* **Orphaned Blocks:** Because the parent resource closed early, the `ingress` and `egress` blocks were left floating in the global scope of `main.tf`, where they are unrecognized by the HCL parser. 
* **Trailing Syntax Error:** Line 104 (`}`) became an extra, unmatched brace because the parser's structural alignment was completely broken.

---

## 3. Step-by-Step Resolution Playbook
To reproduce or fix this issue locally before committing to GitHub, execute the following workflow in your terminal:

### Step 1: Visual Structural Isolation
Run the native formatting tool to quickly see where the nesting broke:
```bash
terraform fmt
```
* **Evidence of Bug:** Lines 82–104 will shift aggressively to the left margin, proving the block scope was broken above them. Fix the missing brace above line 82.

### Step 2: Schema Initialization
To allow the local compiler to download provider definitions without hitting a remote state or requiring cloud credentials, run:
```bash
terraform init -backend=false
```

### Step 3: Local Validation
Verify the structural fix locally:
```bash
terraform validate
```
* **Expected Success Output:** `Success! The configuration is valid.`

---

## 4. CI/CD Prevention Mechanism
This project uses **GitHub Actions** to ensure these errors never reach production. The pipeline automates the verification via `.github/workflows/terraform-ci.yml`:

<img width="1920" height="1080" alt="Screenshot from 2026-09-24 15-03-15" src="https://github.com/user-attachments/assets/12e2aa51-ad16-4b2c-b38f-857aeb9f1615" />


### Where to Verify Results in GitHub
1. Navigate to the repository on **GitHub**.
2. Click on the **Actions** tab.
3. Select the failing run under the workflow list.
4. Expand the **Terraform Validate** step to view the exact console logs shown in Section 1.

## 📊 Troubleshooting Guide: Grafana Dashboard - Connection Refused

This section logs a historical connection issue encountered when attempting to access the Grafana user interface, along with the diagnostic steps and solution applied.

---

## 1. The Symptoms
* Attempting to navigate to the Grafana URL (e.g., `http://<IP-ADDRESS>:3000`) resulted in an immediate **`ERR_CONNECTION_REFUSED`** error in the web browser.
* The application layer was verified as active, but the network layer completely rejected the incoming handshake on the designated port.

---

## 2. Diagnostics & Root Cause Analysis (RCA)
A `Connection Refused` error explicitly indicates that nothing was listening on the target port at the network interface level, or the traffic was actively dropped before reaching the application. The issue stemmed from one of two vectors:

* **Container Port Isolation:** After inspecting the running containers,I noticed the Grafana server was running successfully *inside* the container on port `3000`, but that port was never bound or exposed to the host machine's public network interface. 
* **Cloud Security Group Block:** The service was hosted on a remote virtual machine (e.g., AWS EC2), but the cloud firewall had no inbound rules defined for TCP port `3000`, causing the network interface to drop the connection requests.

### Diagnostic Verification Commands
To isolate the issue, the following commands were used:
```bash
# 1. Check if the port is actively listening on the host machine
ss -tuln | grep 3000

# 2. Test external network handshake to the target IP
nc -zv <-my target IP> 3000
```
* **Result:** The host check showed no active listener on port 3000, and the network handshake test timed out/refused immediately.

---

## 3. Step-by-Step Resolution Playbook

### Step 1: Correct Container Port Mapping
Ensure the deployment configuration explicitly maps the host's port to the internal container port:

### Step 2: Update Infrastructure Firewall Rules
Ensure your infrastructure-as-code configuration on **main.tf** includes a valid ingress rule to open access to port `3000`:
```hcl
resource "aws_security_group_rule" "allow_grafana" {
  type              = "ingress"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"] # Restrict to trusted administrative IP blocks in production
  security_group_id = aws_security_group.app_sg.id
}
```
*Apply changes:* `git commit

---

## 4. Post-Resolution Verification
Access is verified as fully restored when a cURL command against the local or remote host target successfully completes a TCP handshake and returns a valid HTTP header:

<img width="1920" height="1080" alt="Screenshot from 2026-09-09 17-46-36" src="https://github.com/user-attachments/assets/81151833-d367-4bc1-a4a3-bb2b682d4c9c" />


```bash
curl -I http://localhost:3000/login
```
```text
HTTP/1.1 200 OK
Content-Type: text/html; charset=UTF-8
Date: Sat, 26 Sep 2026 11:38:00 GMT
Connection: keep-alive
```

# 📊 Troubleshooting Guide: Grafana & Prometheus Connection Failures

This section logs a historical multi-stage connection issue encountered when setting up the Grafana metrics dashboard, along with the diagnostic workflows and final engineering fixes.

---

## 1. The Symptoms
After successfully establishing access to the Grafana UI, the application threw an error when attempting to reach the time-series backend:
* **Error Behavior:** Grafana could not read or connect to Prometheus (`HTTP Error Bad Gateway` or `Context Deadline Exceeded`).
* **Root Cause Manifestation:** Even after updating the backend target configurations in `datasource.yml`, Grafana failed to execute metric queries and continued attempting connection handshakes with a stale engine mapping.

---

## 2. Root Cause Analysis (RCA)

The breakdown happened across two distinct layers:

1. **Network Layer Container Isolation:** By default, a standalone Docker container resolving `localhost` or `127.0.0.1` points to its *own* internal network interface. It cannot see a Prometheus service running directly on the host machine or another unlinked bridge.
2. **Grafana Provisioning Caching:** Grafana preserves provisioned data sources inside its sqlite/internal database. When you modify a local file volume like `/etc/grafana/provisioning/datasources/datasource.yml`, Grafana frequently ignores updates to an existing data source layout unless its configuration engine is explicitly forced to reload the relational map.

---

## 3. Step-by-Step Resolution Playbook

To resolve the connection issue, updates were applied to the deployment blueprint and the datasource orchestration code.

### Step 1: Bridge Docker to the Host Gateway (`etc_hosts`)
We configured the engine to recognize the host network gateway explicitly. This maps the domain `host.docker.internal` inside Linux Docker container runtimes:

```yaml
# Inside the monitoring deployment playbook
    recreate: true 
    ports:
      - "3000:3000"
    # FIX: Explicitly instructs Linux Docker to resolve host.docker.internal to the host gateway
    etc_hosts:
      host.docker.internal: "host-gateway"
    volumes:
      - "/etc/grafana/provisioning/datasources/datasource.yml:/etc/grafana/provisioning/datasources/datasource.yml:ro"
      - "/etc/grafana/provisioning/dashboards/provider.yml:/etc/grafana/provisioning/dashboards/provider.yml:ro"
      - "/var/lib/grafana/dashboards:/var/lib/grafana/dashboards:rw"
```

### Step 2: Force Engine Mapping Reload (`version` increment)
Because Grafana caches provisioned datasources, you must change the `version` field directly inside your `datasource.yml` layout. Incrementing this counter forces Grafana to overwrite its internal cache database with your fresh network targets during the `recreate: true` cycle.

```yaml
# File: /etc/grafana/provisioning/datasources/datasource.yml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    # Point to the freshly mapped Docker host loopback bridge
    url: http://docker.internal 
    isDefault: true
    editable: false
    # FIX: Incrementing this version flags the internal engine to drop stale mappings and reload configurations
    version: 2 
```
<img width="1920" height="1080" alt="Screenshot from 2026-09-26 11-56-22" src="https://github.com/user-attachments/assets/1a2e5045-741c-4a4b-aa32-e0ac805a5641" />

---

## 4. Post-Resolution Verification
Access is verified as completely functional when the Git commit resolves the deployment and the Grafana data sources panel confirms connectivity:

```text
Commit Hash: fix(monitoring): increment datasource version to force engine mapping reload
```

1. Navigate to Grafana > **Connections** > **Data Sources**.
2. Click **Prometheus** and select **Save & Test**.
3. **Expected Success Output:** `Successfully queried the Prometheus API.`
