variable "project" { }

variable "prefix" {
  default = "prod"
}

variable "region" {
  default = "europe-west1"
}

variable "zone" {
  default = "europe-west1-b"
}

variable "broker_count" {
  default = 3
}
