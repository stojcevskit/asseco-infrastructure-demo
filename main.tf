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

# --- СЛИКИ (IMAGES) ---
resource "docker_image" "mariadb_image" {
  name = "mariadb:latest"
}

resource "docker_image" "nginx_image" {
  name = "nginx:latest"
}

resource "docker_image" "elasticsearch" {
  name = "docker.elastic.co/elasticsearch/elasticsearch:8.11.1"
}

resource "docker_image" "kibana" {
  name = "docker.elastic.co/kibana/kibana:8.11.1"
}

resource "docker_image" "filebeat_image" {
  name = "docker.elastic.co/beats/filebeat:8.11.1"
}

# --- КОНТЕЈНЕРИ ---

# 2. MariaDB
resource "docker_container" "db" {
  name  = "mariadb_server"
  image = docker_image.mariadb_image.image_id
  log_opts = {
    "max-size" = "10m"
    "max-file" = "3"
  }
  restart = "always"
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

# 3. Nginx
resource "docker_container" "web" {
  name  = "nginx_proxy"
  image = docker_image.nginx_image.image_id
  log_opts = {
    "max-size" = "10m"
    "max-file" = "3"
  }
  restart = "always"
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

# 4. Netdata (За мониторинг на перформанси)
resource "docker_container" "monitoring" {
  name  = "netdata"
  image = "netdata/netdata:latest"
  log_opts = {
    "max-size" = "10m"
    "max-file" = "3"
  }
  restart = "always"
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

# 5. Elasticsearch
resource "docker_container" "elasticsearch" {
  name  = "asseco_elastic"
  image = docker_image.elasticsearch.image_id
  log_opts = {
    "max-size" = "10m"
    "max-file" = "3"
  }
  restart = "always"
  networks_advanced { name = docker_network.private_net.name }
  env = [
    "discovery.type=single-node",
    "xpack.security.enabled=false",
    "ES_JAVA_OPTS=-Xms512m -Xmx512m"
  ]
  ports {
    internal = 9200
    external = 9200
  }
  # Ова ги чува податоците на локалниот диск
  volumes {
    host_path      = "/root/terraform-proekt/es-data"
    container_path = "/usr/share/elasticsearch/data"
  }
}

# 6. Kibana
resource "docker_container" "kibana" {
  name  = "asseco_kibana"
  image = docker_image.kibana.image_id
  log_opts = {
    "max-size" = "10m"
    "max-file" = "3"
  }
  restart = "always"
  networks_advanced { name = docker_network.private_net.name }
  ports {
    internal = 5601
    external = 5601
  }
  env = [
    "ELASTICSEARCH_HOSTS=http://asseco_elastic:9200",
    "XPACK_SECURITY_ENABLED=false"  
  ]
  depends_on = [docker_container.elasticsearch]
}

# 7. Filebeat
resource "docker_container" "filebeat" {
  name  = "asseco_filebeat"
  image = docker_image.filebeat_image.image_id
  log_opts = {
    "max-size" = "10m"
    "max-file" = "3"
  }
  user  = "root"
  restart = "always"
  networks_advanced { name = docker_network.private_net.name }
  
  command = [
    "filebeat", "-e",
    "-E", "output.elasticsearch.hosts=[\"asseco_elastic:9200\"]",
    "-E", "setup.kibana.host=asseco_kibana:5601"
  ]

  volumes {
    host_path      = "/root/terraform-proekt/filebeat.yml"
    container_path = "/usr/share/filebeat/filebeat.yml"
    read_only      = true
  }
  volumes {
    host_path      = "/var/lib/docker/containers"
    container_path = "/var/lib/docker/containers"
    read_only      = true
  }
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = true
  }

  depends_on = [
    docker_container.elasticsearch,
    docker_container.kibana
  ]
}
