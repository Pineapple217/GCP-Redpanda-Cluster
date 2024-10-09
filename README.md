# GCP-Redpanda-Cluster

## Example module usage

```HCL
module "cluster_prod" {
  source = "github.com/Pineapple217/GCP-Redpanda-Cluster"
  project = var.project
  zone = var.zone
  region = var.region
  broker_count = 5
  prefix = "prod"
}

module "cluster_dev" {
  source = "github.com/Pineapple217/GCP-Redpanda-Cluster"
  project = var.project
  zone = var.zone
  region = var.region
  broker_count = 3
  prefix = "dev"
}

output "console_url_prod" {
  value = module.cluster_prod.console_url
}

output "console_url_dev" {
  value = module.cluster_dev.console_url
}

```

```HCL
module "cluster_prod" {
  source = "github.com/Pineapple217/GCP-Redpanda-Cluster"
  project = var.project
  zone = var.zone
  region = var.region
  broker_count = 3
  prefix = "prod"
  vpc = data.google_compute_network.main.id
}

data "google_compute_network" "main" {
  name = "test-net"
  project = var.project
}

output "console_url_prod" {
  value = module.cluster_prod.console_url
}
```
