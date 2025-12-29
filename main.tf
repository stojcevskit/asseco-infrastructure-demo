terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

provider "docker" {}

# 1. Мрежа за изолација
resource "docker_network" "private_net" {
  name = "asseco_internal"
}

# 2. MariaDB со Persistence (Податоците се чуваат на диск)
resource "docker_container" "db" {
  name  = "mariadb_server"
  image = "mariadb:latest"
  networks_advanced { name = docker_network.private_net.name }
  env = [
    "MARIADB_ROOT_PASSWORD=lozinka123",
    "MARIADB_DATABASE=TihoDB"
  ]
  volumes {
    host_path      = "/root/terraform-proekt/mysql-data"
    container_path = "/var/lib/mysql"
  }
}

# 3. Nginx со локалниот HTML
resource "docker_container" "web" {
  name  = "nginx_proxy"
  image = "nginx:latest"
  networks_advanced { name = docker_network.private_net.name }
  ports {
    internal = 80
    external = 80
  }
  volumes {
    host_path      = "/root/terraform-proekt/index.html"
    container_path = "/usr/share/nginx/html/index.html"
    read_only      = true
  }
}

# 4. Netdata за Мониторинг 
resource "docker_container" "monitoring" {
  name  = "netdata"
  image = "netdata/netdata:latest"
  ports {
    internal = 19999
    external = 19999
  }
  capabilities { add = ["SYS_PTRACE"] }
  security_opts = ["apparmor=unconfined"]
  volumes {
    host_path = "/proc"
    container_path = "/host/proc"
    read_only = true
  }
  volumes {
    host_path = "/sys"
    container_path = "/host/sys"
    read_only = true
  }
}
# Elasticsearch Image
resource "docker_image" "elasticsearch" {
  name = "docker.elastic.co/elasticsearch/elasticsearch:7.17.10"
}

# Kibana Image (Визуелизација на логови)
resource "docker_image" "kibana" {
  name = "docker.elastic.co/kibana/kibana:7.17.10"
}

# Elasticsearch Container
resource "docker_container" "elasticsearch" {
  name  = "asseco_elastic"
  image = docker_image.elasticsearch.image_id
  networks_advanced {
    name = docker_network.private_net.name
  }
  env = [
    "discovery.type=single-node",
    "ES_JAVA_OPTS=-Xms512m -Xmx512m" # Ограничување на RAM за да не кочи компјутерот
  ]
  ports {
    internal = 9200
    external = 9200
  }
}

# Kibana Container
resource "docker_container" "kibana" {
  name  = "asseco_kibana"
  image = docker_image.kibana.image_id
  networks_advanced {
    name = docker_network.private_net.name
  }
  ports {
    internal = 5601
    external = 5601
  }
  env = [
    "ELASTICSEARCH_HOSTS=http://asseco_elastic:9200"
  ]
  depends_on = [docker_container.elasticsearch]
}
