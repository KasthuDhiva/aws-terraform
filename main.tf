provider "aws" {
  region = "ap-south-1"  # Mumbai region
}

resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins_sg"
  description = "Allow SSH, HTTP, and custom ports for Jenkins and SonarQube"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SonarQube"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "jenkins_server" {
  ami             = "ami-0c2af51e265bd5e0e"  # Ubuntu Server 22.04 LTS (HVM), SSD Volume Type
  instance_type   = "t3.medium"
  key_name        = "jenkins-windows"  # Use the name of your existing key pair in AWS
  security_groups = [aws_security_group.jenkins_sg.name]

  user_data = <<-EOF
    #!/bin/bash
    sudo apt-get update -y

    # Install Java OpenJDK 17
    sudo apt-get install -y fontconfig openjdk-17-jre

    # Verify Java installation
    java -version

    # Install Docker and Docker Compose
    sudo apt-get install -y docker.io docker-compose

    # Start and enable Docker service
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker ubuntu

    # Install Jenkins
    sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
      https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]" \
      https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
      /etc/apt/sources.list.d/jenkins.list > /dev/null
    sudo apt-get update -y
    sudo apt-get install -y jenkins
    sudo systemctl start jenkins
    sudo systemctl enable jenkins

    # Create Docker volumes for SonarQube
    sudo docker volume create sonarqube_data
    sudo docker volume create sonarqube_logs
    sudo docker volume create sonarqube_db_data

    # Create a Docker Compose file for SonarQube and Postgres
    sudo bash -c 'cat <<EOF > /home/ubuntu/docker-compose.yml
    version: "3.8"
    services:
      sonarqube:
        image: sonarqube:latest
        container_name: sonarqube
        ports:
          - "9000:9000"
        volumes:
          - sonarqube_data:/opt/sonarqube/data
          - sonarqube_logs:/opt/sonarqube/logs
        environment:
          - SONARQUBE_JDBC_URL=jdbc:h2:tcp://db:9092/sonar
          - SONARQUBE_JDBC_USERNAME=sonar
          - SONARQUBE_JDBC_PASSWORD=sonar
        depends_on:
          - db
      db:
        image: postgres:latest
        container_name: sonarqube_db
        environment:
          - POSTGRES_USER=sonar
          - POSTGRES_PASSWORD=sonar
          - POSTGRES_DB=sonar
        volumes:
          - sonarqube_db_data:/var/lib/postgresql/data
    volumes:
      sonarqube_data:
      sonarqube_logs:
      sonarqube_db_data:
    EOF'

    # Start SonarQube and Postgres using Docker Compose
    sudo docker-compose -f /home/ubuntu/docker-compose.yml up -d
  EOF

  tags = {
    Name = "Jenkins-Server"
  }
}

output "jenkins_server_public_ip" {
  value       = aws_instance.jenkins_server.public_ip
  description = "The public IP address of the Jenkins server"
}
