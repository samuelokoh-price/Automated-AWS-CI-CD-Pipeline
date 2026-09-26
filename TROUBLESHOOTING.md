# 🛠️ CI/CD Troubleshooting Case Study: Block Nesting Mismatches

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
