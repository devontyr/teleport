# Azure Discovery

## Find `az` CLI

Run `which az` silently. If not found, stop:

> "The Azure CLI (`az`) is required. Install it from https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"

Set `AZ=<path>`. Run `$AZ account show --query id --output tsv` silently. If not logged in, stop:

> "You're not logged in to Azure. Run `az login` and then run this skill again."

Set `SUBSCRIPTION_ID` from the output.

## Teleport Version Check

If `CLUSTER_VERSION` is below `18.8`, stop:

> "Azure Discovery requires Teleport 18.8 or later. Your cluster is running v<CLUSTER_VERSION>."

## Prerequisites

Inform the user before continuing:

1. Your Azure account needs permissions to create managed identities, role definitions, and role assignments in the target subscription(s).
2. Each VM to be discovered must have a managed identity assigned (system-assigned or user-assigned).
3. VMs must run a supported Linux distribution (Ubuntu, Debian, RHEL, Amazon Linux 2, or similar).

## Collect Configuration

Extract all values already provided in the prompt. For each missing required field, ask
conversationally. Present the menu to show current state; redisplay after each change.

**Menu** (redisplay after each change):

```
Azure Discovery Configuration

  Managed Identity
    Resource group: <value or "(required)">
    Location:       <value or "eastus (default)">

  Discovery Matchers
    Subscriptions:   <value or "(required)">
    Regions:         <value or "* (all)">
    Resource groups: <value or "* (all)">
    Tags:            <value or "* (all)">

  Terraform directory: <value or "./teleport-azure-discovery">

  Discovery group: cloud-discovery-group (fixed)   ← Teleport Cloud
                   <value or "(required)">         ← self-hosted

Say what you'd like to change, or "confirm" to proceed.
```

Render only one Discovery group line based on whether `PROXY_ADDR` ends in `.cloud.gravitational.io`.

**Managed Identity** — prompt:

> "Which resource group should the managed identity go in, and which Azure location? (default: eastus)"

Accept natural language, e.g. `my-rg` or `my-rg in westeurope`. Set
`AZURE_MANAGED_IDENTITY_RESOURCE_GROUP` and `AZURE_MANAGED_IDENTITY_LOCATION`.

**Subscription** — if not already provided in the prompt, confirm the inferred value:

```
AskUserQuestion: "Enroll subscription <SUBSCRIPTION_ID>?"
Options:
  - Yes, use this subscription
  - Enter a different subscription ID
```

If the user selects "Enter a different subscription ID", prompt for it. Multiple IDs can
be provided comma-separated. → HCL: `subscriptions = ["id1", "id2"]`

**VM matchers** — use `AskUserQuestion` with clean options. Do not infer or suggest tags
from existing Terraform files:

```
AskUserQuestion: "Which VMs should Teleport discover?"
Options:
  - All VMs in the subscription
  - Match by region
  - Match by resource group
  - Match by tags (e.g. teleport-auto-enroll=true)
  - Multiple matchers
```

For each selection, follow up with a targeted text prompt:
- **Region**: "Which region(s)? e.g. `westus, eastus`" (if unsure: "Run `az account list-locations --output table` to list regions")
- **Resource group**: "Which resource group(s)?"
- **Tags**: "Which tag matcher(s)? e.g. `env=prod, teleport-auto-enroll=true`"
- **Multiple**: ask each in sequence

Parse into HCL fields. Omit fields not set:
→ `regions`, `resource_groups`, `tags` (tag values are lists)

**Terraform directory** — prompt:

> "Where should I write the Terraform files? (default: `./teleport-azure-discovery`)"

Set `WORKDIR`. Use Grep to search for an existing module reference — scoped to this directory only:

```
Grep: "terraform.releases.teleport.dev/teleport/discovery/azure"
path: <WORKDIR>
glob: "*.tf"
```

**If the module reference is found (existing discovery config):**

Read the matching file and extract current values:
- `teleport_proxy_public_addr`
- `azure_resource_group_name`
- `azure_managed_identity_location`
- `azure_matchers` (subscriptions, regions, resource_groups, tags)

Pre-populate the config menu with these values and go directly into the menu flow. Skip any `AskUserQuestion` for fields already resolved from the existing config or the user's prompt. Only ask for values that remain ambiguous.

After confirmation, overwrite `<WORKDIR>/azure_discovery.tf`.

**If `.tf` files exist but no module reference (existing project without discovery):**

Tell the user to merge the following into their provider configuration, then use `AskUserQuestion`:

```hcl
terraform {
  required_providers {
    # Add if not already present:
    teleport = {
      source  = "terraform.releases.teleport.dev/gravitational/teleport"
      version = ">= <CLUSTER_VERSION>"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
  }
}

# Add if not already present:
provider "teleport" {
  addr = "<PROXY_ADDR>"
}

provider "azurerm" {
  features {}
}
```

```
AskUserQuestion: "Ready to write azure_discovery.tf to <WORKDIR>?"
Options:
  - Yes, write the file
  - No, let me review first
```

After confirmation, write `<WORKDIR>/azure_discovery.tf`.

**If no `.tf` files (new project):**

Use `AskUserQuestion`:

```
"Ready to write versions.tf and azure_discovery.tf to <WORKDIR>?"
Options:
  - Yes, write the files
  - No, let me review first
```

After confirmation, write both files:
- `<WORKDIR>/versions.tf`
- `<WORKDIR>/azure_discovery.tf`

**Discovery group** — Cloud: `cloud-discovery-group` (fixed). Self-hosted: prompt for the value — must match `discovery_group` in the Discovery Service config. For private clusters see the [Azure VM Auto-Discovery (Terraform) docs](https://goteleport.com/docs/enroll-resources/auto-discovery/servers/azure-vm-discovery/azure-vm-discovery-terraform/).

**"confirm"** — require resource group and subscriptions before proceeding. Present summary:

> Install managed identity in resource group `<RG>` (location: `<LOCATION>`)
> Enroll subscription(s) `<SUBSCRIPTIONS>`
> [Match VMs by `<REGIONS>` / resource group `<RG_MATCHERS>` / tags `<TAG_MATCHERS>` — omit if not set]
> Write Terraform files to `<WORKDIR>`
>
> Does this look right, or would you like to change anything?

## Generate Terraform Files

Fill in all values from the configuration step and print both file contents as code blocks,
followed by a configuration summary. Ask for confirmation before writing.

**Planned `versions.tf`:**

```hcl
terraform {
  required_version = ">= 1.5.7"
  required_providers {
    teleport = {
      source  = "terraform.releases.teleport.dev/gravitational/teleport"
      version = ">= <CLUSTER_VERSION>"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
  }
}

provider "teleport" {
  addr = "<PROXY_ADDR>"
}

provider "azurerm" {
  features {}
}
```

**Planned `azure_discovery.tf`:**

```hcl
module "azure_discovery" {
  source  = "terraform.releases.teleport.dev/teleport/discovery/azure"
  version = "~> <MODULE_VERSION>"

  teleport_proxy_public_addr    = "<PROXY_ADDR>"
  teleport_discovery_group_name = "<DISCOVERY_GROUP>"

  azure_resource_group_name       = "<AZURE_MANAGED_IDENTITY_RESOURCE_GROUP>"
  azure_managed_identity_location = "<AZURE_MANAGED_IDENTITY_LOCATION>"

  azure_matchers = [
    {
      types         = ["vm"]
      subscriptions = [<SUBSCRIPTIONS — each ID quoted, comma-separated>]
      # regions         = [...] — include only if configured
      # resource_groups = [...] — include only if configured
      # tags            = {...} — include only if configured
    }
  ]
}

output "azure_discovery" {
  value = module.azure_discovery
}
```

After printing both file contents, print a configuration summary:

```
Configuration summary:
- Cluster proxy:                   <PROXY_ADDR>
- Subscriptions:                   <SUB_1>, <SUB_2>, ...
- Discovery group:                 <DISCOVERY_GROUP>
- Managed Identity Resource Group: <AZURE_MANAGED_IDENTITY_RESOURCE_GROUP>
- Managed Identity Location:       <AZURE_MANAGED_IDENTITY_LOCATION>
- Output directory:                <WORKDIR>
```

## Apply Terraform

Explain what each command does, then present them together:

> **You're ready to apply. Here's what each command does:**
>
> - `eval "$(tctl terraform env)"` — authenticates Terraform with your Teleport cluster using short-lived credentials
> - `terraform init` — downloads the Teleport discovery module and Azure provider
> - `terraform apply` — creates the managed identity, role definitions, and role assignments in Azure, and registers the OIDC integration with Teleport
>
> ```bash
> eval "$(tctl terraform env)"
> cd <WORKDIR>
> terraform init
> terraform apply
> ```
>
> Run these when you're ready. Once applied, come back and I can verify that discovery is working.

## Verify

Run silently after the user confirms apply is complete:

```bash
$TCTL discovery nodes --cloud=azure
```

Lists each VM Teleport has attempted to enroll, with status (`Online`, `Installed (offline)`, `Failed`). Present results clearly. If no rows appear yet:

> "Discovery runs automatically every ~5 minutes. Check back soon with:
>
> ```
> tctl discovery nodes --cloud=azure
> ```"

Link to the web UI: `https://<PROXY_HOST>/web/integrations` — use the hostname from the proxy address, without the port (e.g. `example.teleport.sh:443` → `https://example.teleport.sh/web/integrations`)
